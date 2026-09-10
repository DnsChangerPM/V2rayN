/// Profile list state: queries, selection, import, best-profile runs.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../logging/log_service.dart';
import '../models/profile.dart';
import '../profiles/best_profile.dart';
import '../profiles/profile_importer.dart';
import '../profiles/profile_repository.dart';
import '../settings/settings_repository.dart';

class ProfileProvider extends ChangeNotifier
    implements ProfileRepositoryPort {
  ProfileProvider({
    required ProfileRepository repository,
    required ProfileImporter importer,
    required BestProfileSelector selector,
    required SettingsRepository settings,
    required LogService log,
  },)  : _repository = repository,
        _importer = importer,
        _selector = selector,
        _settings = settings,
        _log = log {
    _repositorySubscription = _repository.changed.listen((_) {
      _refreshVisible();
    });
  }

  final ProfileRepository _repository;
  final ProfileImporter _importer;
  final BestProfileSelector _selector;
  final SettingsRepository _settings;
  final LogService _log;
  late final StreamSubscription<void> _repositorySubscription;

  String _search = '';
  String _groupId = BuiltinGroups.all;
  ProfileSortKey _sortKey = ProfileSortKey.name;
  SortDirection _direction = SortDirection.ascending;
  List<ProxyProfile> _visible = const [];
  bool _ranking = false;
  List<ProfileScore> _lastRanking = const [];

  String get search => _search;
  String get groupId => _groupId;
  ProfileSortKey get sortKey => _sortKey;
  SortDirection get direction => _direction;
  List<ProxyProfile> get visible => _visible;
  List<ProfileGroup> get groups => _repository.groups;
  List<ProxyProfile> get all => _repository.profiles;
  bool get ranking => _ranking;
  List<ProfileScore> get lastRanking => _lastRanking;
  String get activeProfileId => _settings.current.activeProfileId;

  void refresh() => _refreshVisible();

  void _refreshVisible() {
    _visible = _repository.query(
      search: _search,
      groupId: _groupId,
      sortKey: _sortKey,
      direction: _direction,
    );
    notifyListeners();
  }

  void setSearch(String value) {
    _search = value;
    _refreshVisible();
  }

  void setGroup(String groupId) {
    _groupId = groupId;
    _refreshVisible();
  }

  void setSort(ProfileSortKey key, SortDirection direction) {
    _sortKey = key;
    _direction = direction;
    _refreshVisible();
  }

  Future<void> selectProfile(String id) async {
    await _settings.update((s) => s.copyWith(activeProfileId: id));
    notifyListeners();
  }

  ProxyProfile? findById(String id) => _repository.findById(id);

  Future<ImportResult> importText(String text, {String groupId = ''}) =>
      _importer.importText(text, groupId: groupId);

  Future<ImportResult> importQrImage(Uint8List bytes, {String groupId = ''}) =>
      _importer.importQrImage(bytes, groupId: groupId);

  Future<ProxyProfile> addManual(ProxyProfile profile) =>
      _repository.add(profile);

  Future<void> update(ProxyProfile profile) => _repository.update(profile);

  Future<void> remove(String id) async {
    if (_settings.current.activeProfileId == id) {
      await _settings.update((s) => s.copyWith(activeProfileId: ''));
    }
    await _repository.remove(id);
  }

  Future<ProxyProfile?> duplicate(String id) => _repository.duplicate(id);

  Future<void> toggleFavorite(String id) => _repository.toggleFavorite(id);

  Future<void> moveToGroup(String id, String groupId) =>
      _repository.moveToGroup(id, groupId);

  Future<void> addGroup(String name) async {
    await _repository.addGroup(name);
    notifyListeners();
  }

  Future<void> removeGroup(String id) async {
    if (_groupId == id) _groupId = BuiltinGroups.all;
    await _repository.removeGroup(id);
  }

  Future<List<ProfileScore>> rankBest() async {
    if (_ranking) return _lastRanking;
    _ranking = true;
    notifyListeners();
    try {
      final candidates = _repository.profiles
          .where((p) => p.protocol != ProxyProtocol.xrayJson)
          .toList();
      _lastRanking = await _selector.rank(candidates, _settings.current);
      return _lastRanking;
    } finally {
      _ranking = false;
      _refreshVisible();
    }
  }

  void cancelRanking() => _selector.cancel();

  @override
  Future<void> recordLatency(String id, int latencyMs) =>
      _repository.recordLatency(id, latencyMs);

  @override
  void dispose() {
    _repositorySubscription.cancel();
    super.dispose();
  }
}
