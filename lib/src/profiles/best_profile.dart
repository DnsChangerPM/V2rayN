/// Best-profile selection: measure, don't guess.
///
/// Two phases (both cancellable, user-triggered):
/// 1. Fast filter: direct TCP handshake to each server (concurrency 5).
/// 2. Full-chain probe for reachable candidates (concurrency 2, temp cores).
///
/// Score: reachability first, then chain latency, then stability (two
/// samples; variance penalized). Unreachable profiles sort last with a
/// recorded reason.
library;

import 'dart:async';

import '../logging/log_service.dart';
import '../models/profile.dart';
import '../models/settings.dart';
import '../network/connectivity.dart';

class ProfileScore {
  const ProfileScore({
    required this.profile,
    required this.reachable,
    this.directLatencyMs,
    this.chainLatencyMs,
    this.jitterMs,
    this.detail = '',
  });

  final ProxyProfile profile;
  final bool reachable;
  final int? directLatencyMs;
  final int? chainLatencyMs;
  final int? jitterMs;
  final String detail;

  /// Lower is better. Unreachable profiles sink to the bottom.
  int get score {
    if (!reachable) return 1 << 30;
    final chain = chainLatencyMs ?? directLatencyMs ?? 1 << 20;
    return chain + (jitterMs ?? 0);
  }
}

class BestProfileSelector {
  BestProfileSelector({
    required ProfileProbe probe,
    required ConnectivityService connectivity,
    required ProfileRepositoryPort repository,
    required LogService log,
  })  : _probe = probe,
        _connectivity = connectivity,
        _repository = repository,
        _log = log;

  final ProfileProbe _probe;
  final ConnectivityService _connectivity;
  final ProfileRepositoryPort _repository;
  final LogService _log;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  /// Rank [candidates] best-first. Records chain latency on each profile.
  Future<List<ProfileScore>> rank(
    List<ProxyProfile> candidates,
    AppSettings settings, {
    int fastConcurrency = 5,
    int chainConcurrency = 2,
    int chainSamples = 2,
  }) async {
    _cancelled = false;
    _log.info('best', 'Ranking ${candidates.length} profiles');

    // Phase 1: direct TCP reachability.
    final reachable = await _mapPool(
      candidates,
      fastConcurrency,
      (profile) => _directCheck(profile),
    );

    // Phase 2: full-chain measurement for reachable candidates only.
    final passing = reachable.where((s) => s.reachable).toList();
    final measured = await _mapPool(
      passing,
      chainConcurrency,
      (score) => _chainMeasure(score, settings, chainSamples),
    );

    final failed = reachable.where((s) => !s.reachable).toList();
    final ranked = [...measured, ...failed]
      ..sort((a, b) => a.score.compareTo(b.score));

    for (final score in measured) {
      if (score.chainLatencyMs != null) {
        await _repository.recordLatency(
            score.profile.id, score.chainLatencyMs!);
      }
    }
    _log.info('best',
        'Ranking done: ${measured.length} measured, ${failed.length} unreachable');
    return ranked;
  }

  Future<ProfileScore> _directCheck(ProxyProfile profile) async {
    if (_cancelled) {
      return ProfileScore(profile: profile, reachable: false, detail: 'cancelled');
    }
    final probe = await _connectivity.probeTcp(profile.address, profile.port);
    return ProfileScore(
      profile: profile,
      reachable: probe.success,
      directLatencyMs: probe.latencyMs,
      detail: probe.detail,
    );
  }

  Future<ProfileScore> _chainMeasure(
      ProfileScore score, AppSettings settings, int samples) async {
    if (_cancelled) return score;
    final latencies = <int>[];
    var detail = '';
    for (var i = 0; i < samples && !_cancelled; i++) {
      final result = await _probe.probe(score.profile, settings);
      if (!result.success) {
        detail = result.detail;
        break;
      }
      latencies.add(result.latencyMs ?? 0);
    }
    if (latencies.isEmpty) {
      return ProfileScore(
        profile: score.profile,
        reachable: false,
        directLatencyMs: score.directLatencyMs,
        detail: detail.isEmpty ? 'chain probe failed' : detail,
      );
    }
    latencies.sort();
    final median = latencies[latencies.length ~/ 2];
    final jitter = latencies.length > 1 ? latencies.last - latencies.first : 0;
    return ProfileScore(
      profile: score.profile,
      reachable: true,
      directLatencyMs: score.directLatencyMs,
      chainLatencyMs: median,
      jitterMs: jitter,
    );
  }

  /// Bounded-concurrency map preserving input order.
  Future<List<R>> _mapPool<T, R>(
      List<T> items, int concurrency, Future<R> Function(T) task) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        final index = next++;
        if (index >= items.length) return;
        results[index] = await task(items[index]);
      }
    }

    await Future.wait(
        [for (var i = 0; i < concurrency; i++) worker()]);
    return results.cast<R>();
  }
}

/// Narrow port so this file does not depend on the full repository.
abstract class ProfileRepositoryPort {
  Future<void> recordLatency(String id, int latencyMs);
}
