/// Application settings persistence (JSON store + change stream).
library;

import 'dart:async';

import '../logging/log_service.dart';
import '../models/settings.dart';
import '../storage/json_store.dart';

class SettingsRepository {
  SettingsRepository({required JsonStore store, required LogService log})
      : _store = store,
        _log = log;

  final JsonStore _store;
  final LogService _log;
  final StreamController<AppSettings> _changed =
      StreamController<AppSettings>.broadcast();

  AppSettings _settings = const AppSettings();

  Stream<AppSettings> get changed => _changed.stream;
  AppSettings get current => _settings;

  Future<void> load() async {
    final data = await _store.read();
    if (data.isEmpty) {
      _settings = const AppSettings();
    } else {
      try {
        _settings = AppSettings.fromJson(data);
      } on Object catch (e) {
        _log.warning(
            'settings', 'Unreadable settings, using defaults', error: e,);
        _settings = const AppSettings();
      }
    }
  }

  Future<void> save(AppSettings settings) async {
    _settings = settings;
    await _store.write(settings.toJson());
    if (!_changed.isClosed) _changed.add(settings);
  }

  Future<void> update(AppSettings Function(AppSettings) mutate) =>
      save(mutate(_settings));

  Future<void> dispose() async {
    await _changed.close();
  }
}
