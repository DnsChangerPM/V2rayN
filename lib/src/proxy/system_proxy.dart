/// Windows system-proxy integration (WinINet registry + refresh broadcast).
///
/// Contract:
/// - IranLink records the pre-connect state and restores it on disconnect
///   (only if it was the one that changed the settings).
/// - Registry writes use HKCU (per-user, no elevation).
/// - After every write, `InternetSetOption(SETTINGS_CHANGED + REFRESH)` is
///   broadcast so running applications pick the change up immediately.
/// - Never touches proxy settings the user manages elsewhere: if the proxy
///   was already enabled with a *different* server, we still take over while
///   connected (documented in UI) but restore the exact previous values after.
library;

import 'dart:io';

import '../logging/log_service.dart';
import '../platform/registry.dart';
import '../platform/win32_bindings.dart';

class SystemProxyState {
  const SystemProxyState({
    required this.enabled,
    required this.server,
    required this.bypass,
  });

  final bool enabled;
  final String server;
  final String bypass;

  @override
  String toString() =>
      'SystemProxyState(enabled=$enabled, server=$server, bypass=$bypass)';
}

class SystemProxyService {
  SystemProxyService({required LogService log}) : _log = log;

  static const internetSettingsKey =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  final LogService _log;

  /// State before IranLink touched the settings (this session).
  SystemProxyState? _previous;

  /// Whether IranLink currently owns the system proxy.
  bool _owned = false;

  bool get isOwned => _owned;

  SystemProxyState current() {
    if (!Platform.isWindows) {
      throw UnsupportedError('System proxy is only available on Windows');
    }
    final enabled = WindowsRegistry.readDword(internetSettingsKey, 'ProxyEnable') == 1;
    final server = WindowsRegistry.readString(internetSettingsKey, 'ProxyServer') ?? '';
    final bypass =
        WindowsRegistry.readString(internetSettingsKey, 'ProxyOverride') ?? '';
    return SystemProxyState(enabled: enabled, server: server, bypass: bypass);
  }

  /// Enable the system proxy pointing at [server] (`host:port`).
  Future<void> enable({
    required String server,
    String bypass = 'localhost;127.*',
  }) async {
    final before = current();
    if (!_owned) _previous = before;
    WindowsRegistry.writeDword(internetSettingsKey, 'ProxyEnable', 1);
    WindowsRegistry.writeString(internetSettingsKey, 'ProxyServer', server);
    if (bypass.isNotEmpty) {
      WindowsRegistry.writeString(internetSettingsKey, 'ProxyOverride', bypass);
    }
    final refreshed = Wininet.refreshProxySettings();
    _owned = true;
    _log.info('proxy', 'System proxy enabled -> $server (broadcast=$refreshed)');
  }

  /// Disable only if IranLink owns the proxy; restores the exact previous
  /// values (server, bypass, enabled flag).
  Future<void> disable() async {
    if (!_owned) return;
    final previous = _previous;
    if (previous == null) {
      WindowsRegistry.writeDword(internetSettingsKey, 'ProxyEnable', 0);
    } else {
      WindowsRegistry.writeDword(
          internetSettingsKey, 'ProxyEnable', previous.enabled ? 1 : 0,);
      WindowsRegistry.writeString(
          internetSettingsKey, 'ProxyServer', previous.server,);
      WindowsRegistry.writeString(
          internetSettingsKey, 'ProxyOverride', previous.bypass,);
    }
    final refreshed = Wininet.refreshProxySettings();
    _owned = false;
    _previous = null;
    _log.info('proxy', 'System proxy restored (broadcast=$refreshed)');
  }
}
