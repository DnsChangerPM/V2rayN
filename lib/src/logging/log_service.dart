/// Leveled, sanitized, rotating log service (no Flutter dependency).
///
/// All messages pass through [LogSanitizer] before reaching any sink.
/// In-memory ring keeps the Log Viewer fast; file writes are serialized
/// through a future chain so callers never block on IO.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'log_sanitizer.dart';

enum LogLevel { debug, info, warning, error }

extension LogLevelName on LogLevel {
  String get name => toString().split('.').last.toUpperCase();
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  String toLine() =>
      '${timestamp.toIso8601String()} [${level.name}] [$tag] $message';
}

class LogService {
  LogService({
    required this.logDir,
    this.maxMemoryEntries = 2000,
    this.maxFileBytes = 2 * 1024 * 1024,
    this.maxRotatedFiles = 5,
    this.minLevel = LogLevel.info,
  });

  final Directory logDir;
  final int maxMemoryEntries;
  final int maxFileBytes;
  final int maxRotatedFiles;
  LogLevel minLevel;

  final ListQueue<LogEntry> _ring = ListQueue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();
  Future<void> _writeChain = Future<void>.value();
  IOSink? _sink;
  bool _disposed = false;

  Stream<LogEntry> get stream => _controller.stream;

  List<LogEntry> snapshot({LogLevel? minLevel, String? query}) {
    return _ring.where((entry) {
      if (minLevel != null && entry.level.index < minLevel.index) return false;
      if (query != null &&
          query.isNotEmpty &&
          !entry.message.toLowerCase().contains(query.toLowerCase()) &&
          !entry.tag.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> init() async {
    await logDir.create(recursive: true);
    await _rotateIfNeeded();
    final file = File('${logDir.path}/iranlink.log');
    _sink = file.openWrite(mode: FileMode.append);
  }

  void log(LogLevel level, String tag, String message, {Object? error}) {
    if (_disposed) return;
    final safe = LogSanitizer.sanitizeMultiline(
      error == null ? message : '$message | error: $error',
    );
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: safe,
    );
    if (level.index >= minLevel.index) {
      _ring.addLast(entry);
      while (_ring.length > maxMemoryEntries) {
        _ring.removeFirst();
      }
      _controller.add(entry);
    }
    final line = entry.toLine();
    _writeChain = _writeChain.then((_) async {
      try {
        _sink?.writeln(line);
      } on Object {
        // Logging must never crash the app; file errors are swallowed
        // deliberately (a broken log sink is reported via the ring only).
      }
    });
  }

  void debug(String tag, String message, {Object? error}) =>
      log(LogLevel.debug, tag, message, error: error);
  void info(String tag, String message, {Object? error}) =>
      log(LogLevel.info, tag, message, error: error);
  void warning(String tag, String message, {Object? error}) =>
      log(LogLevel.warning, tag, message, error: error);
  void error(String tag, String message, {Object? error}) =>
      log(LogLevel.error, tag, message, error: error);

  /// Wait for pending writes (call before reading the file externally).
  Future<void> flush() => _writeChain;

  Future<void> _rotateIfNeeded() async {
    final current = File('${logDir.path}/iranlink.log');
    if (!await current.exists()) return;
    if (await current.length() < maxFileBytes) return;
    for (var i = maxRotatedFiles - 1; i >= 1; i--) {
      final src = File('${logDir.path}/iranlink.log.$i');
      if (await src.exists()) {
        if (i == maxRotatedFiles - 1) {
          await src.delete();
        } else {
          await src.rename('${logDir.path}/iranlink.log.${i + 1}');
        }
      }
    }
    await current.rename('${logDir.path}/iranlink.log.1');
  }

  Future<void> dispose() async {
    _disposed = true;
    await _writeChain;
    await _sink?.flush();
    await _sink?.close();
    await _controller.close();
  }
}
