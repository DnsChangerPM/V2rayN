/// IranLink entry point.
///
/// CLI: `--smoke-test [--smoke-timeout N]` (CI headless test), `--version`,
/// `--minimized` (start hidden in tray, used by autostart).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'src/core/app_version.dart';
import 'src/l10n/strings.dart';
import 'src/models/connection.dart';
import 'src/models/profile.dart';
import 'src/smoke/smoke_test.dart';
import 'src/state/navigation_provider.dart';
import 'src/state/service_locator.dart';
import 'src/tray/tray_service.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--smoke-test')) {
    exit(await runSmokeTest(args));
  }
  if (args.contains('--version')) {
    stdout.writeln('IranLink $kAppVersion');
    exit(0);
  }

  WidgetsFlutterBinding.ensureInitialized();

  final minimized = args.contains('--minimized');
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(960, 640),
        center: true,
        title: 'IranLink',
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        if (!minimized) {
          await windowManager.show();
          await windowManager.focus();
        }
      }
    );
    await windowManager.setPreventClose(true);
  }

  final services = await AppServices.create();
  final windowHandler = _WindowCloseHandler(services);
  if (Platform.isWindows) {
    windowManager.addListener(windowHandler);
  }

  runApp(IranLinkApp(services: services));

  // Post-first-frame: tray, auto-connect, update check (all lazy, none block
  // first paint longer than necessary).
  unawaited(_postLaunch(services, windowHandler));
}

Future<void> _postLaunch(AppServices services, _WindowCloseHandler handler) async {
  final settings = services.settings.current;

  if (Platform.isWindows) {
    final tray = TrayService(
      connection: _BridgeConnection(services),
      paths: services.paths,
      log: services.log,
      callbacks: TrayCallbacks(
        onShowWindow: () async {
          await windowManager.show();
          await windowManager.focus();
        },
        onToggleConnection: () => _toggleFromTray(services),
        onOpenSettings: () async {
          globalNavigation.go(AppPages.settings);
          await windowManager.show();
          await windowManager.focus();
        },
        onQuit: () => _quitApp(services),
        // Tray builds before MaterialApp locales; keep English labels.
        localize: (key) => Strings.en[key] ?? key,
      ),
    );
    handler.tray = tray;
    await tray.init();
  }

  if (settings.autoConnect && settings.activeProfileId.isNotEmpty) {
    // Slight delay: let the window paint first.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _toggleFromTray(services, onlyConnect: true);
  }

  if (settings.checkUpdatesOnStartup) {
    final info = await services.updates.checkForUpdates();
    if (info != null && info.isAvailable) {
      services.log.info('update',
          'Update available: ${info.current} -> ${info.latest} (${info.releaseUrl})',);
    }
  }
}

/// Connection control shared by tray + auto-connect (headless path that does
/// not need a BuildContext).
Future<void> _toggleFromTray(AppServices services,
    {bool onlyConnect = false},) async {
  final core = services.core;
  if (core.status.name == 'running') {
    if (onlyConnect) return;
    try {
      await services.systemProxy.disable();
    } on Object {
      // ignore
    }
    await core.disconnect();
    return;
  }
  if (core.status.name == 'starting') return;
  final settings = services.settings.current;
  final profile = services.profiles.findById(settings.activeProfileId);
  if (profile == null) return;
  await core.connect(profile: profile, settings: settings);
}

/// Pre-widget [TrayConnectionSource]: mirrors core status until the widget
/// tree (and its [ConnectionProvider]) exists. The tray keeps working even
/// if the window was never shown (autostart minimized).
class _BridgeConnection extends ChangeNotifier
    implements TrayConnectionSource {
  _BridgeConnection(this.services) {
    services.core.statusStream.listen((_) => notifyListeners());
  }

  final AppServices services;

  @override
  ConnectionState get state => switch (services.core.status) {
        CoreStatus.running => ConnectionState.connected,
        CoreStatus.starting => ConnectionState.connecting,
        CoreStatus.stopping => ConnectionState.disconnecting,
        CoreStatus.crashed || CoreStatus.error => ConnectionState.error,
        CoreStatus.stopped => ConnectionState.disconnected,
      };

  @override
  bool get isBusy =>
      state == ConnectionState.connecting ||
      state == ConnectionState.disconnecting;

  @override
  ProxyProfile? get activeProfile {
    final id = services.settings.current.activeProfileId;
    return services.profiles.findById(id);
  }
}

Future<void> _quitApp(AppServices services) async {
  services.log.info('app', 'Quit requested');
  try {
    await services.systemProxy.disable();
  } on Object {
    // ignore
  }
  await services.core.disconnect();
  await services.dispose();
  exit(0);
}

class _WindowCloseHandler extends WindowListener {
  _WindowCloseHandler(this.services);

  final AppServices services;
  TrayService? tray;

  @override
  Future<void> onWindowClose() async {
    final minimize = services.settings.current.minimizeToTray;
    if (minimize) {
      await windowManager.hide();
    } else {
      await _quitApp(services);
    }
  }
}
