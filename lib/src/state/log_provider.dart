/// Log viewer state: bounded snapshot + filters over [LogService].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/log_service.dart';

class LogProvider extends ChangeNotifier {
  LogProvider({required LogService log}) : _log = log {
    _subscription = _log.stream.listen((_) {
      // Coalesce bursts: at most one rebuild per 250ms.
      if (_pending) return;
      _pending = true;
      _coalesceTimer = Timer(const Duration(milliseconds: 250), () {
        _coalesceTimer = null;
        _pending = false;
        notifyListeners();
      });
    });
  }

  final LogService _log;
  late final StreamSubscription<LogEntry> _subscription;
  Timer? _coalesceTimer;
  bool _pending = false;

  LogLevel? _minLevel;
  String _query = '';

  LogLevel? get minLevel => _minLevel;
  String get query => _query;

  List<LogEntry> get entries {
    final snapshot = _log.snapshot(minLevel: _minLevel, query: _query);
    const max = 500;
    if (snapshot.length <= max) return snapshot;
    return snapshot.sublist(snapshot.length - max);
  }

  void setMinLevel(LogLevel? level) {
    _minLevel = level;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel the pending coalesce tick: otherwise it fires after dispose
    // (notifyListeners on a dead notifier) and, in widget tests, leaves a
    // pending timer that fails the binding's post-test invariants.
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _subscription.cancel();
    super.dispose();
  }
}
