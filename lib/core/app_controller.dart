import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win_shell/win_shell.dart';

import 'model/enums.dart';
import 'model/profile.dart';
import 'model/settings.dart';
import 'net/latency.dart';
import 'net/link_parser.dart';
import 'net/subscription.dart';
import 'process/core_manager.dart';
import 'process/stats_client.dart';
import 'store/store.dart';
import 'utils/app_version.dart';
import 'utils/paths.dart';

/// Central application state.
///
/// The UI listens to this object and rebuilds whenever something changes.
class AppController extends ChangeNotifier {
  AppController({WinShell? shell, CoreManager? coreManager})
      : _shell = shell ?? winShell,
        coreManager = coreManager ?? CoreManager(shell: shell) {
    store = AppStore.load();
  }

  final WinShell _shell;
  final CoreManager coreManager;
  final LatencyTester _latency = LatencyTester();
  final SubscriptionClient _subscriptions = SubscriptionClient();

  late AppStore store;
  ConnectionState connectionState = ConnectionState.disconnected;
  String? statusMessage;
  String? errorMessage;
  Profile? activeProfile;
  TrafficStats traffic = const TrafficStats();
  List<String> logLines = <String>[];
  WinShellOsVersion? osVersion;
  String coreVersionText = '';
  bool initialized = false;

  Timer? _statsTimer;
  Timer? _logTimer;
  StreamSubscription<WinShellEvent>? _events;

  AppSettings get settings => store.settings;
  List<Profile> get profiles => store.profiles;
  List<Subscription> get subscriptions => store.subscriptions;
  bool get isConnected => connectionState == ConnectionState.connected;

  // -------------------------------------------------------------------------
  // Startup
  // -------------------------------------------------------------------------

  Future<void> init() async {
    if (initialized) {
      return;
    }
    initialized = true;

    osVersion = _shell.getOsVersion();

    // Single instance: if another copy is already running, ask it to show its
    // window and exit.
    if (!_shell.claimSingleInstance()) {
      exit(0);
    }

    _shell.attach();
    _shell.setCloseToTray(settings.closeToTray);
    _events = _shell.events.listen(_onShellEvent);
    _shell.createTray('${AppVersion.name} ${AppVersion.version}');

    await refreshCoreVersion();
    await _loadLogs();

    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
    _logTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadLogs());

    if (settings.autoConnect) {
      final profile = store.selectedProfile;
      if (profile != null) {
        unawaited(connect(profile));
      }
    }
    notifyListeners();
  }

  void _onShellEvent(WinShellEvent event) {
    switch (event) {
      case WinShellEvent.trayClick:
      case WinShellEvent.trayDoubleClick:
      case WinShellEvent.menuShow:
      case WinShellEvent.wakeup:
        if (_shell.isWindowVisible()) {
          _shell.hideWindow();
        } else {
          _shell.showWindow();
        }
        break;
      case WinShellEvent.closeRequested:
        break;
      case WinShellEvent.menuConnect:
        final profile = store.selectedProfile;
        if (profile != null) {
          unawaited(connect(profile));
        }
        break;
      case WinShellEvent.menuDisconnect:
        unawaited(disconnect());
        break;
      case WinShellEvent.menuExit:
        unawaited(shutdown());
        break;
      case WinShellEvent.menuSettings:
        _shell.showWindow();
        break;
    }
  }

  Future<void> shutdown() async {
    await disconnect(silent: true);
    _shell.destroyTray();
    exit(0);
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _logTimer?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Connection
  // -------------------------------------------------------------------------

  Future<void> connect(Profile profile) async {
    if (connectionState.isBusy) {
      return;
    }
    errorMessage = null;
    connectionState = ConnectionState.connecting;
    activeProfile = profile;
    settings.selectedProfileId = profile.id;
    statusMessage = '${AppVersion.name}: ${profile.displayName}';
    notifyListeners();

    final started = await coreManager.start(
      settings: settings,
      profile: profile,
      allProfiles: profiles,
    );

    if (started) {
      connectionState = ConnectionState.connected;
      errorMessage = null;
      _shell.setTrayTooltip('${AppVersion.name} - ${profile.displayName}');
      _shell.showBalloon(
        AppVersion.name,
        'متصل شد: ${profile.displayName}',
      );
    } else {
      connectionState = ConnectionState.failed;
      errorMessage = coreManager.lastError;
      _shell.showBalloon(AppVersion.name, errorMessage ?? '', isError: true);
    }
    notifyListeners();
  }

  Future<void> disconnect({bool silent = false}) async {
    if (connectionState == ConnectionState.disconnected) {
      return;
    }
    connectionState = ConnectionState.disconnecting;
    notifyListeners();
    await coreManager.stop(settings: settings);
    connectionState = ConnectionState.disconnected;
    activeProfile = null;
    traffic = const TrafficStats();
    if (!silent) {
      _shell.setTrayTooltip(AppVersion.name);
    }
    notifyListeners();
  }

  Future<void> toggleConnection() async {
    if (isConnected) {
      await disconnect();
      return;
    }
    final profile = store.selectedProfile;
    if (profile == null) {
      errorMessage = 'هیچ سروری انتخاب نشده است.';
      notifyListeners();
      return;
    }
    await connect(profile);
  }

  void selectProfile(Profile profile) {
    settings.selectedProfileId = profile.id;
    notifyListeners();
    unawaited(save());
    if (isConnected) {
      unawaited(connect(profile));
    }
  }

  // -------------------------------------------------------------------------
  // Measurements
  // -------------------------------------------------------------------------

  Future<void> testDelay(Profile profile) async {
    profile.lastDelayMs = null;
    final index = profiles.indexOf(profile);
    if (index >= 0) {
      notifyListeners();
    }

    // Measure through the running proxy when possible (that is the latency the
    // user actually experiences), otherwise fall back to a raw TCP ping.
    int? delay;
    if (isConnected) {
      delay = await _latency.proxyDelay(settings.httpPort);
    }
    delay ??= await _latency.tcpPing(profile.address, profile.port);
    profile.lastDelayMs = delay;
    profile.lastTestedAt = DateTime.now();
    notifyListeners();
    unawaited(save());
  }

  Future<void> testAllDelays() async {
    final selected = store.selectedProfile;
    if (selected != null) {
      await testDelay(selected);
    }
    await Future.wait(profiles
        .where((p) => p != selected)
        .map((p) => _latency.tcpPing(p.address, p.port).then((value) {
              p.lastDelayMs = value;
              p.lastTestedAt = DateTime.now();
              notifyListeners();
            })));
    notifyListeners();
    unawaited(save());
  }

  Future<void> runSpeedTest() async {
    if (!isConnected) {
      errorMessage = 'ابتدا متصل شوید.';
      notifyListeners();
      return;
    }
    final profile = activeProfile;
    final speed = await _latency.downloadThroughputKbps(settings.httpPort);
    if (profile != null && speed != null) {
      profile.lastSpeedKbps = speed;
    }
    notifyListeners();
    unawaited(save());
  }

  // -------------------------------------------------------------------------
  // Servers
  // -------------------------------------------------------------------------

  Future<void> addProfile(Profile profile) async {
    profiles.add(profile);
    settings.selectedProfileId ??= profile.id;
    notifyListeners();
    await save();
  }

  Future<void> updateProfile(Profile profile) async {
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
      if (isConnected && activeProfile?.id == profile.id) {
        await connect(profile);
      }
    }
    notifyListeners();
    await save();
  }

  Future<void> removeProfile(Profile profile) async {
    profiles.removeWhere((p) => p.id == profile.id);
    if (settings.selectedProfileId == profile.id) {
      settings.selectedProfileId = profiles.isEmpty ? null : profiles.first.id;
    }
    notifyListeners();
    await save();
  }

  /// Copies text to the Windows clipboard.
  void copyToClipboard(String text) => _shell.setClipboardText(text);

  /// Opens a path or URL with the shell.
  bool open(String target) => target.startsWith('http')
      ? _shell.openUrl(target)
      : _shell.showInExplorer(target);

  Future<int> importFromClipboard() async {
    final text = _shell.getClipboardText();
    if (text == null || text.trim().isEmpty) {
      return 0;
    }
    return importFromText(text);
  }

  int importFromText(String text) {
    final parsed = <Profile>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      for (final candidate in line.split(RegExp(r'\s+'))) {
        final profile = LinkParserParse(candidate);
        if (profile != null) {
          parsed.add(profile);
        }
      }
    }
    if (parsed.isEmpty) {
      return 0;
    }
    profiles.addAll(parsed);
    settings.selectedProfileId ??= parsed.first.id;
    notifyListeners();
    unawaited(save());
    return parsed.length;
  }

  // -------------------------------------------------------------------------
  // Subscriptions
  // -------------------------------------------------------------------------

  Future<void> addSubscription(String url, {String? name}) async {
    final subscription = Subscription(
      name: name ?? _nameFromUrl(url),
      url: url.trim(),
    );
    subscriptions.add(subscription);
    notifyListeners();
    await updateSubscription(subscription);
  }

  Future<void> updateSubscription(Subscription subscription) async {
    final result = await _subscriptions.fetch(
      subscription.url,
      subscriptionId: subscription.id,
      timeout: const Duration(seconds: 45),
    );
    if (result.isSuccess) {
      store.mergeSubscription(subscription, result.profiles);
      subscription
        ..usedBytes = result.usedBytes
        ..totalBytes = result.totalBytes
        ..expireAt = result.expireAt
        ..lastError = null;
    } else {
      subscription.lastError = result.error;
    }
    notifyListeners();
    await save();
  }

  Future<void> updateAllSubscriptions() async {
    for (final subscription
        in subscriptions.where((s) => s.enabled && s.url.isNotEmpty)) {
      await updateSubscription(subscription);
    }
  }

  Future<void> removeSubscription(Subscription subscription) async {
    subscriptions.removeWhere((s) => s.id == subscription.id);
    profiles.removeWhere((p) => p.subscriptionId == subscription.id);
    notifyListeners();
    await save();
  }

  static String _nameFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return url.trim();
    }
    final segments = uri.pathSegments;
    return segments.isEmpty ? uri.host : segments.last;
  }

  // -------------------------------------------------------------------------
  // Settings
  // -------------------------------------------------------------------------

  /// Applies a settings change.
  ///
  /// [reconnect] restarts the connection so that core level options (ports,
  /// routing, core binary, ...) take effect immediately.
  Future<void> patchSettings(
    AppSettings updated, {
    bool reconnect = false,
  }) async {
    store.settings = updated;
    _shell.setCloseToTray(updated.closeToTray);
    await applyAutoStart();
    if (reconnect && isConnected) {
      final profile = activeProfile ?? store.selectedProfile;
      await disconnect(silent: true);
      if (profile != null) {
        await connect(profile);
      }
    }
    await refreshCoreVersion();
    notifyListeners();
    await save();
  }

  Future<void> updateSettings(AppSettings updated) =>
      patchSettings(updated, reconnect: true);

  Future<void> applyAutoStart() async {
    await _shell.setAutoStart(
      enabled: settings.autoStartEnabled,
      exePath: Platform.resolvedExecutable,
      args: settings.startMinimized ? '--minimized' : '',
    );
  }

  Future<void> refreshCoreVersion() async {
    final os = osVersion ?? _shell.getOsVersion();
    final legacy = switch (settings.coreFlavour) {
      CoreFlavour.auto => os.needsLegacyCore,
      CoreFlavour.legacy => true,
      CoreFlavour.modern => false,
    };
    coreVersionText =
        await coreManager.coreVersion(settings.coreType, legacy: legacy);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Background jobs
  // -------------------------------------------------------------------------

  Future<void> _pollStats() async {
    if (!isConnected) {
      return;
    }
    final path = coreManager.resolveCorePath(
      settings.coreType,
      preferLegacy: coreManager.activeCoreIsLegacy,
    );
    final stats = await StatsClient(
      corePath: path,
      apiPort: settings.apiPort,
    ).query();
    if (stats.total > 0) {
      traffic = stats;
      notifyListeners();
    }
  }

  Future<void> _loadLogs() async {
    final lines = await coreManager.recentLogLines();
    if (lines.length != logLines.length ||
        (lines.isNotEmpty && lines.last != logLines.safeLast)) {
      logLines = lines;
      notifyListeners();
    }
  }

  Future<void> clearLogs() async {
    for (final file in <File>[AppPaths.coreLog, AppPaths.coreErrorLog]) {
      if (file.existsSync()) {
        await file.writeAsString('');
      }
    }
    logLines = <String>[];
    notifyListeners();
  }

  Future<void> save() => store.save();
}

extension _SafeList on List<String> {
  String? get safeLast => isEmpty ? null : last;
}
