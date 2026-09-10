/// Settings state with side effects (autostart applied immediately).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/log_service.dart';
import '../models/settings.dart';
import '../platform/autostart.dart';
import '../settings/settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required SettingsRepository repository,
    required AutostartService autostart,
    required LogService log,
  })  : _repository = repository,
        _autostart = autostart,
        _log = log {
    _subscription = _repository.changed.listen((_) => notifyListeners());
  }

  final SettingsRepository _repository;
  final AutostartService _autostart;
  final LogService _log;
  late final StreamSubscription<AppSettings> _subscription;

  AppSettings get settings => _repository.current;

  Future<void> update(AppSettings Function(AppSettings) mutate) =>
      _repository.update(mutate);

  Future<void> setTheme(ThemeModeSetting theme) =>
      update((s) => s.copyWith(theme: theme));

  Future<void> setLocale(LocaleSetting locale) =>
      update((s) => s.copyWith(locale: locale));

  Future<void> setProxyMode(ProxyMode mode) =>
      update((s) => s.copyWith(proxyMode: mode));

  Future<void> setStartWithWindows(bool enabled) async {
    try {
      await _autostart.setEnabled(enabled);
      await update((s) => s.copyWith(startWithWindows: enabled));
    } on Object catch (e) {
      _log.error('settings', 'Autostart change failed', error: e);
      rethrow;
    }
  }

  Future<void> applyNetworkPreset(NetworkPreset preset) => update(
      (s) => s.copyWith(tuning: NetworkTuning.fromPreset(preset)));

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
