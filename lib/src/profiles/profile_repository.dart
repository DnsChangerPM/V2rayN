/// Profile + group repository: in-memory state, JSON persistence, queries.
library;

import 'dart:async';

import '../logging/log_service.dart';
import '../models/profile.dart';
import '../storage/json_store.dart';
import 'best_profile.dart';

class ProfileRepository implements ProfileRepositoryPort {
  ProfileRepository({
    required JsonStore store,
    required String Function() newId,
    required LogService log,
  },)  : _store = store,
        _newId = newId,
        _log = log;

  final JsonStore _store;
  final String Function() _newId;
  final LogService _log;

  final List<ProxyProfile> _profiles = [];
  final List<ProfileGroup> _groups = [];
  final StreamController<void> _changed = StreamController<void>.broadcast();

  Stream<void> get changed => _changed.stream;
  List<ProxyProfile> get profiles => List.unmodifiable(_profiles);
  List<ProfileGroup> get groups => List.unmodifiable(_groups);

  Future<void> load() async {
    final data = await _store.read();
    _profiles
      ..clear()
      ..addAll(_readProfiles(data['profiles']));
    _groups
      ..clear()
      ..addAll(_readGroups(data['groups']));
    _ensureBuiltinGroups();
    _log.info('profiles', 'Loaded ${_profiles.length} profiles, ${_groups.length} groups');
  }

  List<ProxyProfile> _readProfiles(dynamic raw) {
    if (raw is! List<dynamic>) return [];
    final result = <ProxyProfile>[];
    for (final item in raw.whereType<Map<dynamic, dynamic>>()) {
      try {
        result.add(ProxyProfile.fromJson(item.cast<String, dynamic>()));
      } on Object catch (e) {
        _log.warning('profiles', 'Skipping unreadable profile entry', error: e);
      }
    }
    return result;
  }

  List<ProfileGroup> _readGroups(dynamic raw) {
    if (raw is! List<dynamic>) return [];
    final result = <ProfileGroup>[];
    for (final item in raw.whereType<Map<dynamic, dynamic>>()) {
      try {
        result.add(ProfileGroup.fromJson(item.cast<String, dynamic>()));
      } on Object catch (e) {
        _log.warning('profiles', 'Skipping unreadable group entry', error: e);
      }
    }
    return result;
  }

  void _ensureBuiltinGroups() {
    for (final id in [BuiltinGroups.gaming, BuiltinGroups.work, BuiltinGroups.personal]) {
      if (_groups.every((g) => g.id != id)) {
        _groups.add(ProfileGroup(id: id, name: id, isBuiltin: true));
      }
    }
  }

  Future<void> _persist() async {
    await _store.write({
      'profiles': _profiles.map((p) => p.toJson()).toList(),
      'groups': _groups.map((g) => g.toJson()).toList(),
    });
    _changed.add(null);
  }

  ProxyProfile? findById(String id) {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  String allocateId() => _newId();

  Future<ProxyProfile> add(ProxyProfile profile) async {
    final withId = profile.id.isEmpty ? profile.copyWith(id: _newId()) : profile;
    final now = DateTime.now();
    _profiles.add(withId.copyWith(createdAt: now, updatedAt: now));
    await _persist();
    return withId;
  }

  Future<void> update(ProxyProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index < 0) return;
    _profiles[index] = profile.copyWith(updatedAt: DateTime.now());
    await _persist();
  }

  Future<void> remove(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    await _persist();
  }

  Future<ProxyProfile?> duplicate(String id) async {
    final source = findById(id);
    if (source == null) return null;
    final now = DateTime.now();
    final copy = source.copyWith(
      id: _newId(),
      name: '${source.name} (copy)',
      subscriptionId: '',
      createdAt: now,
      updatedAt: now,
    );
    _profiles.add(copy);
    await _persist();
    return copy;
  }

  Future<void> toggleFavorite(String id) async {
    final profile = findById(id);
    if (profile == null) return;
    await update(profile.copyWith(isFavorite: !profile.isFavorite));
  }

  Future<void> moveToGroup(String id, String groupId) async {
    final profile = findById(id);
    if (profile == null) return;
    await update(profile.copyWith(groupId: groupId));
  }

  Future<void> recordLatency(String id, int latencyMs) async {
    final profile = findById(id);
    if (profile == null) return;
    _profiles[_profiles.indexWhere((p) => p.id == id)] =
        profile.copyWith(lastLatencyMs: latencyMs);
    await _persist();
  }

  Future<void> recordUsage(String id) async {
    final profile = findById(id);
    if (profile == null) return;
    _profiles[_profiles.indexWhere((p) => p.id == id)] =
        profile.copyWith(lastUsedAt: DateTime.now());
    // Usage timestamps are low-value writes; still persist for "Last used" sort.
    await _persist();
  }

  /// Atomically replace all profiles owned by [subscriptionId], preserving
  /// user state (favorite, group, latency) matched by [ProxyProfile.identityKey].
  Future<void> replaceSubscriptionProfiles(
      String subscriptionId, List<ProxyProfile> fresh,) async {
    final preserved = <String, ProxyProfile>{
      for (final p in _profiles.where((p) => p.subscriptionId == subscriptionId))
        p.identityKey: p,
    };
    _profiles.removeWhere((p) => p.subscriptionId == subscriptionId);
    for (final profile in fresh) {
      final old = preserved[profile.identityKey];
      _profiles.add(old == null
          ? profile
          : profile.copyWith(
              id: old.id,
              isFavorite: old.isFavorite,
              groupId: old.groupId,
              lastLatencyMs: old.lastLatencyMs,
              lastSpeedKbps: old.lastSpeedKbps,
              lastUsedAt: old.lastUsedAt,
            ),);
    }
    await _persist();
  }

  Future<void> removeSubscriptionProfiles(String subscriptionId) async {
    _profiles.removeWhere((p) => p.subscriptionId == subscriptionId);
    await _persist();
  }

  // -- groups --------------------------------------------------------------

  Future<ProfileGroup> addGroup(String name) async {
    final group = ProfileGroup(id: _newId(), name: name);
    _groups.add(group);
    await _persist();
    return group;
  }

  Future<void> renameGroup(String id, String name) async {
    final index = _groups.indexWhere((g) => g.id == id);
    if (index < 0 || _groups[index].isBuiltin) return;
    _groups[index] = ProfileGroup(id: id, name: name);
    await _persist();
  }

  Future<void> removeGroup(String id) async {
    final index = _groups.indexWhere((g) => g.id == id);
    if (index < 0 || _groups[index].isBuiltin) return;
    _groups.removeAt(index);
    for (var i = 0; i < _profiles.length; i++) {
      if (_profiles[i].groupId == id) {
        _profiles[i] = _profiles[i].copyWith(groupId: '');
      }
    }
    await _persist();
  }

  // -- queries -------------------------------------------------------------

  List<ProxyProfile> query({
    String search = '',
    String groupId = BuiltinGroups.all,
    ProfileSortKey sortKey = ProfileSortKey.name,
    SortDirection direction = SortDirection.ascending,
  },) {
    Iterable<ProxyProfile> result = _profiles;
    if (groupId == BuiltinGroups.favorites) {
      result = result.where((p) => p.isFavorite);
    } else if (groupId != BuiltinGroups.all) {
      result = result.where((p) => p.groupId == groupId);
    }
    final needle = search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      result = result.where((p) =>
          p.name.toLowerCase().contains(needle) ||
          p.address.toLowerCase().contains(needle) ||
          p.protocol.name.contains(needle) ||
          _groupName(p.groupId).toLowerCase().contains(needle),);
    }
    final sorted = result.toList()
      ..sort((a, b) {
        final cmp = switch (sortKey) {
          ProfileSortKey.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ProfileSortKey.latency => _nullsLast(a.lastLatencyMs, b.lastLatencyMs),
          ProfileSortKey.speed => _nullsLast(b.lastSpeedKbps, a.lastSpeedKbps),
          ProfileSortKey.lastUsed => _nullsLastDate(a.lastUsedAt, b.lastUsedAt),
          ProfileSortKey.favorite =>
            (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0),
        };
        return direction == SortDirection.ascending ? cmp : -cmp;
      });
    return sorted;
  }

  String _groupName(String id) {
    for (final group in _groups) {
      if (group.id == id) return group.name;
    }
    return '';
  }

  int _nullsLast(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  int _nullsLastDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a); // most recent first by default
  }

  Future<void> dispose() async {
    await _changed.close();
  }
}
