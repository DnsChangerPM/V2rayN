/// Start-with-Windows via HKCU ...\Run (per-user, no elevation needed).
library;

import 'dart:io';

import '../logging/log_service.dart';
import 'registry.dart';

class AutostartService {
  AutostartService({required LogService log}) : _log = log;

  static const runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const valueName = 'IranLink';

  final LogService _log;

  bool get isEnabled {
    if (!Platform.isWindows) return false;
    try {
      return WindowsRegistry.readString(runKey, valueName) != null;
    } on Object catch (e) {
      _log.warning('autostart', 'Failed to read autostart state', error: e);
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Autostart is only available on Windows');
    }
    try {
      if (enabled) {
        final exe = Platform.resolvedExecutable;
        WindowsRegistry.writeString(runKey, valueName, '"$exe" --minimized');
      } else {
        WindowsRegistry.deleteValue(runKey, valueName);
      }
      _log.info('autostart', 'Autostart ${enabled ? 'enabled' : 'disabled'}');
    } on Object catch (e) {
      _log.error('autostart', 'Failed to update autostart', error: e);
      rethrow;
    }
  }
}
