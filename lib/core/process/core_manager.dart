import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:win_shell/win_shell.dart';

import '../config/config_builder.dart';
import '../model/enums.dart';
import '../model/profile.dart';
import '../model/settings.dart';
import '../utils/paths.dart';

/// What the manager is currently doing.
enum CoreStatus {
  stopped,
  starting,
  running,
  stopping,
  failed;

  bool get isActive => this == starting || this == running;
}

/// Starts and stops the core process, the system proxy and the TUN device.
class CoreManager {
  CoreManager({WinShell? shell}) : _shell = shell ?? winShell;

  final WinShell _shell;

  CoreStatus status = CoreStatus.stopped;
  String? lastError;
  int? corePid;
  int? tunPid;
  bool systemProxyActive = false;
  bool tunActive = false;
  CoreType activeCore = CoreType.xray;
  bool activeCoreIsLegacy = false;

  File? _configFile;

  /// Path of the config file that is currently in use (useful for debugging).
  File? get configFile => _configFile;

  // -------------------------------------------------------------------------
  // Core binaries
  // -------------------------------------------------------------------------

  /// Resolves the core executable to use, honouring the OS and the user's
  /// preference, with a fallback when one of the two builds is missing.
  String resolveCorePath(CoreType type, {required bool preferLegacy}) {
    final dir = AppPaths.coreDir.path;
    final legacy = p.join(dir, '${type.id}-win7.exe');
    final modern = p.join(dir, '${type.id}.exe');
    final legacyExists = File(legacy).existsSync();
    final modernExists = File(modern).existsSync();

    if (preferLegacy) {
      if (legacyExists) {
        return legacy;
      }
      if (modernExists) {
        return modern;
      }
    } else {
      if (modernExists) {
        return modern;
      }
      if (legacyExists) {
        return legacy;
      }
    }
    return preferLegacy ? legacy : modern;
  }

  /// Resolves the tun2socks binary used for TUN mode.
  String resolveTun2SocksPath({required bool preferLegacy}) {
    final dir = AppPaths.coreDir.path;
    final legacy = p.join(dir, 'tun2socks-win7.exe');
    final modern = p.join(dir, 'tun2socks.exe');
    final legacyExists = File(legacy).existsSync();
    final modernExists = File(modern).existsSync();
    if (preferLegacy) {
      return legacyExists || !modernExists ? legacy : modern;
    }
    return modernExists || !legacyExists ? modern : legacy;
  }

  /// Versions reported by the cores, best effort.
  Future<String> coreVersion(CoreType type, {required bool legacy}) async {
    final path = resolveCorePath(type, preferLegacy: legacy);
    if (!File(path).existsSync()) {
      return 'not installed';
    }
    try {
      final result = await Process.run(path, <String>['version']);
      final output = (result.stdout as String?)?.trim() ?? '';
      return output.split('\n').first;
    } on Object {
      return 'unknown';
    }
  }

  // -------------------------------------------------------------------------
  // Start / stop
  // -------------------------------------------------------------------------

  Future<bool> start({
    required AppSettings settings,
    required Profile profile,
    required List<Profile> allProfiles,
  }) async {
    if (status.isActive) {
      await stop();
    }
    status = CoreStatus.starting;
    lastError = null;

    try {
      // 1. pick the right binary for this Windows version
      final os = _shell.getOsVersion();
      final preferLegacy = switch (settings.coreFlavour) {
        CoreFlavour.auto => os.needsLegacyCore,
        CoreFlavour.legacy => true,
        CoreFlavour.modern => false,
      };
      final corePath = resolveCorePath(settings.coreType, preferLegacy: preferLegacy);
      if (!File(corePath).existsSync()) {
        throw CoreException(
            'هسته‌ی ${settings.coreType.label} پیدا نشد:\n$corePath');
      }
      activeCore = settings.coreType;
      activeCoreIsLegacy = p.basename(corePath).contains('win7');

      // 2. write the generated configuration next to the core so that
      //    geoip.dat / geosite.dat are found by relative path.
      final config = CoreConfigBuilder(
        settings: settings,
        profile: profile,
        profiles: allProfiles,
        coreType: settings.coreType,
      ).build();
      _configFile = AppPaths.generatedConfig;
      await _configFile!.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
        flush: true,
      );

      // 3. start the core
      AppPaths.truncateIfNeeded(AppPaths.coreLog);
      AppPaths.truncateIfNeeded(AppPaths.coreErrorLog);
      final pid = _shell.startProcess(
        corePath,
        args: 'run -c "${_configFile!.path}"',
        workDir: AppPaths.coreDir.path,
        stdoutFile: AppPaths.coreLog.path,
        stderrFile: AppPaths.coreErrorLog.path,
      );
      if (pid == 0) {
        throw CoreException('اجرای هسته ناموفق بود:\n$corePath');
      }
      corePid = pid;

      // 4. wait until the local ports accept connections
      final ready = await _waitForPort(settings.httpPort);
      if (!ready) {
        final log = await _tailLog();
        throw CoreException('هسته پورت ${settings.httpPort} را باز نکرد.\n$log');
      }

      // 5. hand traffic over
      if (settings.proxyMode.usesSystemProxy) {
        systemProxyActive = _applySystemProxy(settings);
      }
      if (settings.proxyMode.usesTun) {
        await _startTun(settings, preferLegacy: preferLegacy);
      }

      status = CoreStatus.running;
      return true;
    } on CoreException catch (error) {
      lastError = error.message;
      status = CoreStatus.failed;
      await _cleanupAfterFailure(settings);
      return false;
    } on Object catch (error) {
      lastError = '$error';
      status = CoreStatus.failed;
      await _cleanupAfterFailure(settings);
      return false;
    }
  }

  Future<void> stop({AppSettings? settings}) async {
    status = CoreStatus.stopping;
    if (tunPid != null) {
      _shell.stopProcess(tunPid!);
      tunPid = null;
    }
    if (tunActive && settings != null) {
      await _removeTunRoutes(settings);
      tunActive = false;
    }
    if (corePid != null) {
      _shell.stopProcess(corePid!, timeoutMs: 4000);
      corePid = null;
    }
    if (systemProxyActive) {
      _shell.clearSystemProxy();
      systemProxyActive = false;
    }
    status = CoreStatus.stopped;
  }

  Future<void> _cleanupAfterFailure(AppSettings settings) async {
    if (corePid != null) {
      _shell.stopProcess(corePid!);
      corePid = null;
    }
    if (tunPid != null) {
      _shell.stopProcess(tunPid!);
      tunPid = null;
    }
    if (systemProxyActive) {
      _shell.clearSystemProxy();
      systemProxyActive = false;
    }
    if (tunActive) {
      await _removeTunRoutes(settings);
      tunActive = false;
    }
  }

  /// Kills cores left behind by a previous crash.
  void killLeftovers() {
    for (final name in <String>['xray.exe', 'v2ray.exe', 'tun2socks.exe']) {
      _shell.killProcessTree(name);
    }
  }

  bool isRunning() => status == CoreStatus.running;

  // -------------------------------------------------------------------------
  // System proxy
  // -------------------------------------------------------------------------

  String buildProxyServerString(AppSettings settings) {
    final http = 'http=127.0.0.1:${settings.httpPort}';
    final https = 'https=127.0.0.1:${settings.httpPort}';
    final socks = 'socks=127.0.0.1:${settings.socksPort}';
    return '$http;$https;$socks';
  }

  String buildBypassString(AppSettings settings) {
    final entries = <String>[
      '<local>',
      if (settings.bypassIran) ...<String>['*.ir', '*.iran.*'],
      for (final domain in settings.customBypassDomains)
        domain.startsWith('*') ? domain : '*.$domain',
    ];
    return entries.join(';');
  }

  bool _applySystemProxy(AppSettings settings) => _shell.setSystemProxy(
        server: buildProxyServerString(settings),
        bypass: buildBypassString(settings),
      );

  // -------------------------------------------------------------------------
  // TUN
  // -------------------------------------------------------------------------

  Future<void> _startTun(AppSettings settings, {required bool preferLegacy}) async {
    if (!_shell.isAdmin()) {
      throw CoreException(
        'حالت TUN به دسترسی مدیر (Administrator) نیاز دارد.\n'
        'برنامه را به عنوان اجرا-به-عنوان-مدیر باز کنید.',
      );
    }
    final tunPath = resolveTun2SocksPath(preferLegacy: preferLegacy);
    if (!File(tunPath).existsSync()) {
      throw CoreException('tun2socks پیدا نشد:\n$tunPath');
    }
    AppPaths.truncateIfNeeded(AppPaths.tun2socksLog);
    final pid = _shell.startProcess(
      tunPath,
      args: '-device "wintun://${settings.tunName}" '
          '-proxy socks5://127.0.0.1:${settings.socksPort} '
          '-mtu ${settings.tunMtu} -loglevel warn',
      workDir: AppPaths.coreDir.path,
      stdoutFile: AppPaths.tun2socksLog.path,
      stderrFile: AppPaths.tun2socksLog.path,
    );
    if (pid == 0) {
      throw CoreException('اجرای tun2socks ناموفق بود.');
    }
    tunPid = pid;

    // Give the Wintun adapter a moment to appear, then configure it.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await _setupTunRoutes(settings);
    tunActive = true;
  }

  Future<void> _setupTunRoutes(AppSettings settings) async {
    await _runHidden('netsh', <String>[
      'interface',
      'ipv4',
      'set',
      'address',
      'name=${settings.tunName}',
      'static',
      settings.tunAddress.split('/').first,
      _maskFromCidr(settings.tunAddress),
      settings.tunGateway,
    ]);
    await _runHidden('netsh', <String>[
      'interface',
      'ipv4',
      'set',
      'dnsservers',
      'name=${settings.tunName}',
      'static',
      settings.tunDns,
      'primary',
      'validate=no',
    ]);
    if (settings.tunAutoRoute) {
      // Two /1 routes beat the existing default route (lower metric) without
      // destroying it, which is the classic VPN trick on Windows.
      await _runHidden('route', <String>[
        'add',
        '0.0.0.0',
        'mask',
        '128.0.0.0',
        settings.tunGateway,
        'metric',
        '5',
      ]);
      await _runHidden('route', <String>[
        'add',
        '128.0.0.0',
        'mask',
        '128.0.0.0',
        settings.tunGateway,
        'metric',
        '5',
      ]);
    }
  }

  Future<void> _removeTunRoutes(AppSettings settings) async {
    if (settings.tunAutoRoute) {
      await _runHidden('route', <String>['delete', '0.0.0.0', 'mask', '128.0.0.0']);
      await _runHidden('route', <String>['delete', '128.0.0.0', 'mask', '128.0.0.0']);
    }
  }

  static String _maskFromCidr(String cidr) {
    final parts = cidr.split('/');
    final bits = parts.length == 2 ? int.tryParse(parts[1]) ?? 24 : 24;
    final mask = (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
    return <int>[
      (mask >> 24) & 0xFF,
      (mask >> 16) & 0xFF,
      (mask >> 8) & 0xFF,
      mask & 0xFF,
    ].join('.');
  }

  /// Runs a console tool without flashing a window.
  Future<void> _runHidden(String exe, List<String> args) async {
    final pid = _shell.startProcess(exe, args: args.join(' '));
    if (pid == 0) {
      return;
    }
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_shell.isProcessRunning(pid)) {
        return;
      }
    }
    _shell.stopProcess(pid, timeoutMs: 1000);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Future<bool> _waitForPort(int port,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (corePid != null && !_shell.isProcessRunning(corePid!)) {
        return false;
      }
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 300),
        );
        await socket.close();
        return true;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }

  Future<String> _tailLog({int lines = 20}) async {
    try {
      for (final file in <File>[AppPaths.coreErrorLog, AppPaths.coreLog]) {
        if (!file.existsSync()) {
          continue;
        }
        final all = await file.readAsLines();
        if (all.isEmpty) {
          continue;
        }
        final start = all.length > lines ? all.length - lines : 0;
        return all.sublist(start).join('\n');
      }
    } on Object {
      // ignore
    }
    return '';
  }

  /// Tails the core log for the logs screen.
  Future<List<String>> recentLogLines({int lines = 200}) async {
    try {
      final file = AppPaths.coreLog;
      if (!file.existsSync()) {
        return const <String>[];
      }
      final all = await file.readAsLines();
      final start = all.length > lines ? all.length - lines : 0;
      return all.sublist(start);
    } on Object {
      return const <String>[];
    }
  }
}

/// User facing error raised by [CoreManager].
class CoreException implements Exception {
  CoreException(this.message);
  final String message;

  @override
  String toString() => message;
}
