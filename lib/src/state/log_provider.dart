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
      Timer(const Duration(milliseconds: 250), () {
        _pending = false;
        notifyListeners();
      });
    });
  }

  final LogService _log;
  late final StreamSubscription<LogEntry> _subscription;
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
    _subscription.cancel();
    super.dispose();
  }
}
