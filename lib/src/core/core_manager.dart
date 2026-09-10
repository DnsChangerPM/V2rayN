/// Core lifecycle manager: state machine, supervision, crash recovery.
///
/// Owns the only core process IranLink ever runs. Responsibilities:
/// - executable selection (legacy Win7/8.1 core vs primary core),
/// - pre-launch port + config validation (refuse to start when invalid),
/// - readiness probing, stderr capture (bounded, sanitized),
/// - crash detection with bounded auto-restart (max 3, then stop + report),
/// - graceful shutdown + temp-file cleanup + orphan handling at startup.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../logging/log_service.dart';
import '../models/connection.dart';
import '../models/profile.dart';
import '../models/settings.dart';
import '../platform/app_paths.dart';
import '../platform/os_info.dart';
import '../platform/windows_process.dart';
import 'core_adapter.dart';
import 'port_probe.dart';
import 'xray_adapter.dart';
import 'xray_config_builder.dart';
import 'xray_config_validator.dart';
import 'xray_stats.dart';

class CoreManager {
  CoreManager({
    required CoreAdapter adapter,
    required XrayConfigBuilder builder,
    required XrayConfigValidator validator,
    required XrayStatsClient statsClient,
    required AppPaths paths,
    required OsInfo os,
    required LogService log,
    this.maxRestarts = 3,
  })  : _adapter = adapter,
        _builder = builder,
        _validator = validator,
        _statsClient = statsClient,
        _paths = paths,
        _os = os,
        _log = log;

  final CoreAdapter _adapter;
  final XrayConfigBuilder _builder;
  final XrayConfigValidator _validator;
  final XrayStatsClient _statsClient;
  final AppPaths _paths;
  final OsInfo _os;
  final LogService _log;
  final int maxRestarts;

  CoreStatus _status = CoreStatus.stopped;
  final StreamController<CoreStatus> _statusController =
      StreamController<CoreStatus>.broadcast();
  final StreamController<TrafficStats> _trafficController =
      StreamController<TrafficStats>.broadcast();

  CoreProcess? _process;
  StreamSubscription<String>? _stderrSub;
  Timer? _statsTimer;
  AppFailure? _lastFailure;
  ProxyProfile? _activeProfile;
  AppSettings? _activeSettings;
  String _configPath = '';
  String _coreVersion = '';
  String _executable = '';
  int _restartAttempts = 0;
  bool _expectExit = false;
  bool _disposed = false;
  DateTime? _connectedAt;
  int _lastUp = 0;
  int _lastDown = 0;
  DateTime? _lastSampleAt;
  bool _statsDegradedLogged = false;
  final List<String> _recentCoreOutput = [];

  Stream<CoreStatus> get statusStream => _statusController.stream;
  Stream<TrafficStats> get trafficStream => _trafficController.stream;
  CoreStatus get status => _status;
  AppFailure? get lastFailure => _lastFailure;
  ProxyProfile? get activeProfile => _activeProfile;
  String get coreVersion => _coreVersion;
  String get executable => _executable;
  int? get pid => _process?.pid;
  List<String> get recentCoreOutput => List.unmodifiable(_recentCoreOutput);

  void _setStatus(CoreStatus status) {
    if (_status == status) return;
    _status = status;
    _log.info('core', 'Status -> ${status.name}');
    _statusController.add(status);
  }

  // -- lifecycle -----------------------------------------------------------

  Future<void> init() async {
    await _cleanupOrphans();
    await _probeVersionBestEffort();
  }

  Future<void> _cleanupOrphans() async {
    // Our own stale runtime files (single-instance mutex guarantees no other
    // IranLink owns them).
    try {
      await for (final entity in _paths.cacheDir.list()) {
        final name = p.basename(entity.path);
        if (name.startsWith('iranlink-core-') && entity is File) {
          await entity.delete();
        }
      }
    } on Object catch (e) {
      _log.warning('core', 'Cache cleanup failed', error: e);
    }
    final pidFile = File(p.join(_paths.cacheDir.path, 'iranlink-core.pid'));
    if (!await pidFile.exists()) return;
    try {
      final pid = int.tryParse((await pidFile.readAsString()).trim());
      await pidFile.delete();
      if (pid == null) return;
      if (await WindowsProcessUtils.isPidAliveWithImage(pid, 'xray.exe')) {
        _log.warning('core', 'Removing orphan core process (pid=$pid)');
        await WindowsProcessUtils.killPid(pid);
      }
    } on Object catch (e) {
      _log.warning('core', 'Orphan cleanup failed', error: e);
    }
  }

  Future<void> _probeVersionBestEffort() async {
    try {
      final exe = _selectExecutable(checkExists: false);
      if (exe == null) {
        _log.warning('core', 'No core executable found during init probe');
        return;
      }
      _coreVersion = await _adapter.readVersion(exe);
      _log.info('core', 'Core version: $_coreVersion');
    } on Object catch (e) {
      _log.warning('core', 'Core version probe failed', error: e);
    }
  }

  /// Absolute path of the core binary for this OS (+ user override).
  ///
  /// `IRANLINK_CORE_DIR` (dev/CI only) overrides the bundled location; it
  /// must contain `xray.exe` and optionally `win7/xray.exe`.
  String? _selectExecutable({bool checkExists = true}) {
    final override = Platform.environment['IRANLINK_CORE_DIR'];
    final bundled = override != null && override.isNotEmpty
        ? Directory(override)
        : AppPaths.bundledCoreDir();
    final primary = File(p.join(bundled.path, 'xray.exe'));
    final legacy = File(p.join(bundled.path, 'win7', 'xray.exe'));
    final preferLegacy =
        _activeSettings?.preferLegacyCore == true || _os.useLegacyCore;
    final first = preferLegacy ? legacy : primary;
    final second = preferLegacy ? primary : legacy;
    if (!checkExists) return first.path;
    if (first.existsSync()) return first.path;
    if (second.existsSync()) {
      _log.warning('core',
          'Preferred core missing, falling back to ${p.basename(second.path)}',);
      return second.path;
    }
    return null;
  }

  // -- connect / disconnect ------------------------------------------------

  Future<void> connect({
    required ProxyProfile profile,
    required AppSettings settings,
  }) async {
    if (_disposed) return;
    if (_status == CoreStatus.starting || _status == CoreStatus.running) {
      _log.warning('core', 'connect() ignored: already ${_status.name}');
      return;
    }
    _activeProfile = profile;
    _activeSettings = settings;
    _lastFailure = null;
    _restartAttempts = 0;
    _setStatus(CoreStatus.starting);

    final exe = _selectExecutable();
    if (exe == null) {
      return _fail(const AppFailure(messageKey: 'coreErrorMissingExe'));
    }
    _executable = exe;

    final portFailure = await _checkPorts(settings);
    if (portFailure != null) return _fail(portFailure);

    late final Map<String, dynamic> config;
    try {
      config = _builder.build(profile: profile, settings: settings);
    } on Object catch (e) {
      return _fail(AppFailure(
          messageKey: 'coreErrorInvalidConfig', details: e.toString(),),);
    }
    final validation = _validator.validate(config);
    if (!validation.isValid) {
      final first = validation.issues.first;
      _log.error('core',
          'Config invalid: ${validation.issues.length} issues (${first.messageKey})',);
      return _fail(AppFailure(
          messageKey: 'coreErrorInvalidConfig', details: first.messageKey,),);
    }

    _configPath =
        p.join(_paths.cacheDir.path, 'iranlink-core-${DateTime.now().microsecondsSinceEpoch}.json');
    try {
      await _paths.cacheDir.create(recursive: true);
      await File(_configPath)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(config));
    } on Object catch (e) {
      return _fail(AppFailure(
          messageKey: 'coreErrorConfigWrite', details: e.toString(),),);
    }

    try {
      _process = await _adapter.start(
          CoreStartRequest(executable: exe, configPath: _configPath),);
    } on Object catch (e) {
      await _deleteConfig();
      return _fail(_mapSpawnError(e));
    }
    final pid = _process!.pid;
    _log.info('core', 'Spawned ${_adapter.coreName} (pid=$pid)');
    unawaited(File(p.join(_paths.cacheDir.path, 'iranlink-core.pid'))
        .writeAsString('$pid')
        .catchError((_) => File('')),);

    _expectExit = false;
    _subscribeStderr();
    unawaited(_process!.exitCode.then(_onProcessExit));

    final ready = await _waitForReady(settings);
    if (!ready) {
      // _fail was already called by the exit handler or the timeout path.
      return;
    }
    _connectedAt = DateTime.now();
    _lastUp = 0;
    _lastDown = 0;
    _lastSampleAt = null;
    _statsDegradedLogged = false;
    _setStatus(CoreStatus.running);
    _startStatsSampler(settings);
  }

  Future<AppFailure?> _checkPorts(AppSettings settings) async {
    final inbounds = settings.inbounds;
    final checks = <(String, int)>[
      if (inbounds.enableSocks) ('SOCKS', inbounds.socksPort),
      if (inbounds.enableHttp) ('HTTP', inbounds.httpPort),
      if (settings.enableStatsApi) ('stats', settings.statsPort),
    ];
    for (final check in checks) {
      final host =
          check.$1 == 'stats' ? '127.0.0.1' : inbounds.bindAddress;
      if (!await isPortFree(host, check.$2)) {
        final owner = await findTcpListenerOwner(check.$2);
        final ownerName =
            owner == null ? null : await WindowsProcessUtils.imageNameForPid(owner);
        _log.error('core', 'Port ${check.$2} (${check.$1}) busy (pid=$owner)');
        return AppFailure(
          messageKey: 'proxyErrorPortBusy',
          port: check.$2,
          pid: owner,
          details: ownerName ?? '',
        );
      }
    }
    return null;
  }

  AppFailure _mapSpawnError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('access is denied') || text.contains('access denied')) {
      return AppFailure(
          messageKey: 'coreErrorPermission', details: error.toString(),);
    }
    if (text.contains('not found') || text.contains('no such file')) {
      return const AppFailure(messageKey: 'coreErrorMissingExe');
    }
    return AppFailure(
        messageKey: 'coreErrorStartFailed', details: error.toString(),);
  }

  void _subscribeStderr() {
    _stderrSub?.cancel();
    final process = _process;
    if (process == null) return;
    _stderrSub = decodeLines(process.stderrStream).listen((line) {
      _recentCoreOutput.add(line);
      if (_recentCoreOutput.length > 100) _recentCoreOutput.removeAt(0);
      _log.info('xray', line);
    });
  }

  Future<bool> _waitForReady(AppSettings settings) async {
    final inbounds = settings.inbounds;
    final probeHost =
        inbounds.bindAddress.isEmpty ? '127.0.0.1' : inbounds.bindAddress;
    final probePort =
        inbounds.enableSocks ? inbounds.socksPort : inbounds.httpPort;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (_status != CoreStatus.starting) {
        // The exit handler already failed or stopped us.
        return _status == CoreStatus.running;
      }
      if (await canConnect(probeHost, probePort)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    _log.error('core', 'Readiness timeout on $probeHost:$probePort');
    await _terminateProcess();
    await _deleteConfig();
    _fail(AppFailure(
      messageKey: 'coreErrorStartTimeout',
      details: _recentCoreOutput.take(5).join(' | '),
    ),);
    return false;
  }

  Future<void> _onProcessExit(int exitCode) async {
    await _stderrSub?.cancel();
    _stderrSub = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    if (_expectExit || _status == CoreStatus.stopping) {
      await _deleteConfig();
      _process = null;
      if (!_disposed) _setStatus(CoreStatus.stopped);
      return;
    }
    // Unexpected exit.
    await _deleteConfig();
    _process = null;
    if (_disposed) return;
    if (_status == CoreStatus.starting) {
      _fail(_mapEarlyExit(exitCode));
      return;
    }
    _log.error('core', 'Core exited unexpectedly (code=$exitCode)');
    _setStatus(CoreStatus.crashed);
    await _maybeAutoRestart();
  }

  AppFailure _mapEarlyExit(int exitCode) {
    final tail = _recentCoreOutput.join('\n').toLowerCase();
    if (tail.contains('address already in use') ||
        tail.contains('bind:') && tail.contains('in use')) {
      return AppFailure(
          messageKey: 'proxyErrorPortBusy', details: 'exit=$exitCode',);
    }
    if (tail.contains('invalid') ||
        tail.contains('failed to parse') ||
        tail.contains('bad ') && tail.contains('config')) {
      return AppFailure(
          messageKey: 'coreErrorInvalidConfig', details: 'exit=$exitCode',);
    }
    if (tail.contains('permission denied') || tail.contains('access is denied')) {
      return const AppFailure(messageKey: 'coreErrorPermission');
    }
    return AppFailure(
      messageKey: 'coreErrorStartFailed',
      details:
          'exit=$exitCode ${_recentCoreOutput.take(3).join(' | ')}',
    );
  }

  Future<void> _maybeAutoRestart() async {
    final profile = _activeProfile;
    final settings = _activeSettings;
    if (profile == null || settings == null) {
      _fail(const AppFailure(messageKey: 'coreErrorCrashed'));
      return;
    }
    _restartAttempts++;
    if (_restartAttempts > maxRestarts) {
      _log.error(
          'core', 'Crash loop: $maxRestarts restarts exhausted, giving up',);
      _fail(const AppFailure(messageKey: 'coreErrorCrashed'));
      return;
    }
    _log.warning('core',
        'Auto-restart attempt $_restartAttempts/$maxRestarts in 2s',);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_disposed || _status != CoreStatus.crashed) return;
    // connect() moves crashed -> starting itself; attempts are preserved
    // because connect() only resets them on a fresh user-initiated call.
    final attempts = _restartAttempts;
    await connect(profile: profile, settings: settings);
    _restartAttempts = attempts;
  }

  Future<void> disconnect() async {
    if (_status != CoreStatus.running &&
        _status != CoreStatus.starting &&
        _status != CoreStatus.crashed &&
        _status != CoreStatus.error) {
      return;
    }
    _setStatus(CoreStatus.stopping);
    _expectExit = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    await _terminateProcess();
    await _stderrSub?.cancel();
    _stderrSub = null;
    await _deleteConfig();
    _process = null;
    _activeProfile = null;
    if (!_disposed) _setStatus(CoreStatus.stopped);
  }

  Future<void> _terminateProcess() async {
    final process = _process;
    if (process == null) return;
    try {
      await process.terminateGracefully();
    } on Object catch (e) {
      _log.warning('core', 'Graceful stop failed, killing', error: e);
      process.kill();
    }
  }

  Future<void> _deleteConfig() async {
    if (_configPath.isEmpty) return;
    try {
      await File(_configPath).delete();
    } on Object {
      // Best effort.
    }
    _configPath = '';
    try {
      await File(p.join(_paths.cacheDir.path, 'iranlink-core.pid')).delete();
    } on Object {
      // Best effort.
    }
  }

  void _fail(AppFailure failure) {
    _lastFailure = failure;
    _activeProfile = null;
    _log.error('core', 'Failed: ${failure.messageKey} ${failure.details}');
    _setStatus(CoreStatus.error);
  }

  // -- traffic stats ---------------------------------------------------------

  void _startStatsSampler(AppSettings settings) {
    _statsTimer?.cancel();
    if (!settings.enableStatsApi) {
      _trafficController.add(TrafficStats(connectedAt: _connectedAt));
      return;
    }
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_status != CoreStatus.running) return;
      final traffic = await _statsClient.proxyTraffic(
          host: '127.0.0.1', port: settings.statsPort,);
      if (_status != CoreStatus.running) return;
      if (traffic == null) {
        if (!_statsDegradedLogged) {
          _statsDegradedLogged = true;
          _log.warning('core', 'Stats API unreachable, traffic unknown');
        }
        _trafficController.add(TrafficStats(connectedAt: _connectedAt));
        return;
      }
      final now = DateTime.now();
      var upSpeed = 0;
      var downSpeed = 0;
      if (_lastSampleAt != null) {
        final dt = now.difference(_lastSampleAt!).inMilliseconds / 1000;
        if (dt > 0) {
          upSpeed = ((traffic.uplinkBytes - _lastUp) / dt).round().clamp(0, 1 << 62);
          downSpeed =
              ((traffic.downlinkBytes - _lastDown) / dt).round().clamp(0, 1 << 62);
        }
      }
      _lastUp = traffic.uplinkBytes;
      _lastDown = traffic.downlinkBytes;
      _lastSampleAt = now;
      _trafficController.add(TrafficStats(
        downloadBytes: traffic.downlinkBytes,
        uploadBytes: traffic.uplinkBytes,
        downloadSpeedBps: downSpeed,
        uploadSpeedBps: upSpeed,
        connectedAt: _connectedAt,
      ),);
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _statsTimer?.cancel();
    await _stderrSub?.cancel();
    await disconnect().catchError((_) {});
    await _statusController.close();
    await _trafficController.close();
  }
}
