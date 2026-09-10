/// Subscription manager: CRUD, refresh (manual/auto), last-good caching.
///
/// Refresh pipeline: fetch -> parse in an isolate -> atomic replace in the
/// profile repository. On ANY failure the previous profiles are kept and the
/// error is recorded on the subscription row (never thrown to the UI layer
/// as an unhandled exception).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../core/app_version.dart';
import '../logging/log_service.dart';
import '../models/subscription.dart';
import '../profiles/profile_repository.dart';
import '../storage/json_store.dart';
import '../utils/validators.dart';
import 'subscription_fetcher.dart';
import 'subscription_parser.dart';

class SubscriptionManager {
  SubscriptionManager({
    required JsonStore store,
    required Directory cacheDir,
    required ProfileRepository profiles,
    required SubscriptionFetcher fetcher,
    required String Function() newId,
    required LogService log,
  },)  : _store = store,
        _cacheDir = cacheDir,
        _profiles = profiles,
        _fetcher = fetcher,
        _newId = newId,
        _log = log;

  final JsonStore _store;
  final Directory _cacheDir;
  final ProfileRepository _profiles;
  final SubscriptionFetcher _fetcher;
  final String Function() _newId;
  final LogService _log;

  final List<Subscription> _subscriptions = [];
  final StreamController<void> _changed = StreamController<void>.broadcast();
  final Map<String, CancellationToken> _inflight = {};
  Timer? _autoRefreshTimer;

  Stream<void> get changed => _changed.stream;
  List<Subscription> get subscriptions => List.unmodifiable(_subscriptions);

  Future<void> load() async {
    final data = await _store.read();
    _subscriptions
      ..clear()
      ..addAll(_readAll(data['subscriptions']));
    _log.info(
        'subscriptions', 'Loaded ${_subscriptions.length} subscriptions',);
    _rescheduleAutoRefresh();
  }

  List<Subscription> _readAll(dynamic raw) {
    if (raw is! List<dynamic>) return [];
    final result = <Subscription>[];
    for (final item in raw.whereType<Map<dynamic, dynamic>>()) {
      try {
        result.add(
            Subscription.fromJson(item.cast<String, dynamic>()).copyWith(
                lastStatus: SubscriptionStatus.idle,),);
      } on Object catch (e) {
        _log.warning('subscriptions', 'Skipping unreadable entry', error: e);
      }
    }
    return result;
  }

  Future<void> _persist() async {
    await _store.write({
      'subscriptions': _subscriptions.map((s) => s.toJson()).toList(),
    });
    _changed.add(null);
  }

  Subscription? findById(String id) {
    for (final subscription in _subscriptions) {
      if (subscription.id == id) return subscription;
    }
    return null;
  }

  Future<Subscription> add({
    required String name,
    required String url,
    bool autoRefresh = false,
    int refreshIntervalMinutes = 240,
  },) async {
    if (!isValidUrl(url.trim())) {
      throw ArgumentError('Invalid subscription URL');
    }
    final subscription = Subscription(
      id: _newId(),
      name: name.trim().isEmpty ? maskUrl(url.trim()) : name.trim(),
      url: url.trim(),
      autoRefresh: autoRefresh,
      refreshIntervalMinutes: refreshIntervalMinutes,
      createdAt: DateTime.now(),
    );
    _subscriptions.add(subscription);
    await _persist();
    _rescheduleAutoRefresh();
    return subscription;
  }

  Future<void> update(Subscription subscription) async {
    final index = _subscriptions.indexWhere((s) => s.id == subscription.id);
    if (index < 0) return;
    _subscriptions[index] = subscription;
    await _persist();
    _rescheduleAutoRefresh();
  }

  Future<void> remove(String id) async {
    _inflight[id]?.cancel();
    _subscriptions.removeWhere((s) => s.id == id);
    await _profiles.removeSubscriptionProfiles(id);
    await _cacheFile(id).delete().catchError((_) => File(''));
    await _persist();
    _rescheduleAutoRefresh();
  }

  File _cacheFile(String id) =>
      File('${_cacheDir.path}/${Uri.encodeComponent(id)}.txt');

  /// Refresh one subscription. Returns true on success. Never throws —
  /// failures are recorded on the subscription row.
  Future<bool> refresh(String id) async {
    final subscription = findById(id);
    if (subscription == null || _inflight.containsKey(id)) return false;
    final token = CancellationToken();
    _inflight[id] = token;
    _setStatus(id,
        lastStatus: SubscriptionStatus.refreshing, lastError: '',);
    try {
      final body = await _fetcher.fetch(
        url: Uri.parse(subscription.url),
        userAgent: subscription.userAgent.isEmpty
            ? 'IranLink/$kAppVersion'
            : subscription.userAgent,
        allowInsecure: subscription.allowInsecure,
        cancellation: token,
      );
      final parsed = await Isolate.run(
          () => parseSubscriptionContent(body, subscriptionId: id),);
      await _profiles.replaceSubscriptionProfiles(id, parsed.profiles);
      await _cacheDir.create(recursive: true);
      await _cacheFile(id).writeAsString(body);
      _setStatus(
        id,
        lastStatus: SubscriptionStatus.ok,
        lastError: parsed.errors.isEmpty
            ? ''
            : '${parsed.errors.length} lines skipped',
        lastUpdatedAt: DateTime.now(),
        profileCount: parsed.profiles.length,
      );
      _log.info('subscriptions',
          'Refresh OK: ${parsed.profiles.length} profiles (${parsed.errors.length} skipped)',);
      return true;
    } on FetchCancelledException {
      _setStatus(id,
          lastStatus: SubscriptionStatus.idle, lastError: 'cancelled',);
      return false;
    } on Object catch (e) {
      // Last-good profiles stay untouched in the repository.
      _setStatus(id,
          lastStatus: SubscriptionStatus.error, lastError: e.toString(),);
      _log.warning('subscriptions', 'Refresh failed, kept last-good profiles',
          error: e,);
      return false;
    } finally {
      _inflight.remove(id);
    }
  }

  Future<void> refreshAllEnabled() async {
    for (final subscription
        in _subscriptions.where((s) => s.enabled).toList()) {
      await refresh(subscription.id);
    }
  }

  void cancelRefresh(String id) => _inflight[id]?.cancel();

  void _setStatus(
    String id, {
    required SubscriptionStatus lastStatus,
    required String lastError,
    DateTime? lastUpdatedAt,
    int? profileCount,
  },) {
    final index = _subscriptions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final current = _subscriptions[index];
    _subscriptions[index] = current.copyWith(
      lastStatus: lastStatus,
      lastError: lastError,
      lastUpdatedAt: lastUpdatedAt ?? current.lastUpdatedAt,
      profileCount: profileCount ?? current.profileCount,
    );
    unawaited(_persist());
  }

  void _rescheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    final due = _subscriptions
        .where((s) => s.enabled && s.autoRefresh)
        .map((s) => s.refreshIntervalMinutes)
        .where((m) => m > 0)
        .toList();
    if (due.isEmpty) return;
    final minutes = due.reduce((a, b) => a < b ? a : b).clamp(5, 24 * 60);
    _autoRefreshTimer = Timer(Duration(minutes: minutes), () async {
      for (final subscription in _subscriptions
          .where((s) => s.enabled && s.autoRefresh)
          .toList()) {
        final last = subscription.lastUpdatedAt;
        final interval = Duration(minutes: subscription.refreshIntervalMinutes);
        if (last == null || DateTime.now().difference(last) >= interval) {
          await refresh(subscription.id);
        }
      }
      _rescheduleAutoRefresh();
    });
  }

  Future<void> dispose() async {
    _autoRefreshTimer?.cancel();
    for (final token in _inflight.values) {
      token.cancel();
    }
    await _changed.close();
  }
}
