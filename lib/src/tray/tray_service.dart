/// System-tray integration (Windows): icon, menu, click behavior.
///
/// The tray icon is materialized from Flutter assets to a real file at
/// startup (the native side needs a filesystem path). The menu rebuilds on
/// every connection-state change.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';

import '../logging/log_service.dart';
import '../models/connection.dart';
import '../models/profile.dart';
import '../platform/app_paths.dart';

/// Narrow interface the tray needs (implemented by [ConnectionProvider] and
/// by the pre-widget bridge in `main.dart`).
abstract class TrayConnectionSource extends Listenable {
  ConnectionState get state;
  bool get isBusy;
  ProxyProfile? get activeProfile;
}

class TrayCallbacks {
  const TrayCallbacks({
    required this.onShowWindow,
    required this.onToggleConnection,
    required this.onOpenSettings,
    required this.onQuit,
    required this.localize,
  });

  final Future<void> Function() onShowWindow;
  final Future<void> Function() onToggleConnection;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onQuit;
  final String Function(String key) localize;
}

class TrayService {
  TrayService({
    required TrayConnectionSource connection,
    required AppPaths paths,
    required LogService log,
    required TrayCallbacks callbacks,
  })  : _connection = connection,
        _paths = paths,
        _log = log,
        _callbacks = callbacks;

  final TrayConnectionSource _connection;
  final AppPaths _paths;
  final LogService _log;
  final TrayCallbacks _callbacks;

  final SystemTray _tray = SystemTray();
  VoidCallback? _connectionListener;
  bool _ready = false;

  Future<void> init() async {
    if (!Platform.isWindows) {
      _log.info('tray', 'Tray disabled (not Windows)');
      return;
    }
    try {
      final iconPath = await _materializeIcon();
      await _tray.initSystemTray(
        iconPath: iconPath,
        toolTip: 'IranLink',
      );
      _tray.registerSystemTrayEventHandler(_onEvent);
      _connectionListener = () => unawaited(_rebuildMenu());
      _connection.addListener(_connectionListener!);
      await _rebuildMenu();
      _ready = true;
      _log.info('tray', 'Tray initialized');
    } on Object catch (e) {
      _log.warning('tray', 'Tray init failed', error: e);
    }
  }

  Future<String> _materializeIcon() async {
    final target = File('${_paths.cacheDir.path}/tray.ico');
    if (!await target.exists()) {
      final data = await rootBundle.load('assets/icons/tray.ico');
      await target.writeAsBytes(data.buffer.asUint8List());
    }
    return target.path;
  }

  String _t(String key) => _callbacks.localize(key);

  Future<void> _rebuildMenu() async {
    final connected =
        _connection.state == ConnectionState.connected;
    final busy = _connection.isBusy;
    final profile = _connection.activeProfile;
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: connected
            ? '${_t('trayDisconnect')} (${profile?.name ?? ''})'
            : _t('trayConnect'),
        enabled: !busy,
        onClicked: (_) => _callbacks.onToggleConnection(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _t('trayShow'),
        onClicked: (_) => _callbacks.onShowWindow(),
      ),
      MenuItemLabel(
        label: _t('traySettings'),
        onClicked: (_) => _callbacks.onOpenSettings(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _t('trayQuit'),
        onClicked: (_) => _callbacks.onQuit(),
      ),
    ]);
    try {
      await _tray.setContextMenu(menu);
      await _tray.setToolTip(
          connected ? 'IranLink — ${profile?.name ?? ''}' : 'IranLink');
    } on Object catch (e) {
      _log.debug('tray', 'Menu rebuild failed', error: e);
    }
  }

  Future<void> _onEvent(String eventName) async {
    if (eventName == kSystemTrayEventClick) {
      await _callbacks.onShowWindow();
    } else if (eventName == kSystemTrayEventRightClick) {
      await _rebuildMenu();
      await _tray.popUpContextMenu();
    }
  }

  Future<void> dispose() async {
    final listener = _connectionListener;
    if (listener != null) _connection.removeListener(listener);
    _connectionListener = null;
    if (_ready) {
      try {
        await _tray.destroy();
      } on Object {
        // ignore
      }
    }
  }
}
