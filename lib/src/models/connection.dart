/// Connection/core state models (pure Dart).
library;

/// Lifecycle of the core process as observed by [CoreManager].
enum CoreStatus {
  stopped,
  starting,
  running,
  stopping,
  crashed,
  error,
}

/// User-facing connection state (core + proxy mode applied).
enum ConnectionState { disconnected, connecting, connected, disconnecting, error }

/// Traffic sample from the core stats API (or estimated zeros).
class TrafficStats {
  const TrafficStats({
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.downloadSpeedBps = 0,
    this.uploadSpeedBps = 0,
    this.connectedAt,
  });

  final int downloadBytes;
  final int uploadBytes;
  final int downloadSpeedBps;
  final int uploadSpeedBps;
  final DateTime? connectedAt;

  int get uptimeSeconds =>
      connectedAt == null ? 0 : DateTime.now().difference(connectedAt!).inSeconds;

  TrafficStats copyWith({
    int? downloadBytes,
    int? uploadBytes,
    int? downloadSpeedBps,
    int? uploadSpeedBps,
    DateTime? connectedAt,
  }) {
    return TrafficStats(
      downloadBytes: downloadBytes ?? this.downloadBytes,
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadSpeedBps: downloadSpeedBps ?? this.downloadSpeedBps,
      uploadSpeedBps: uploadSpeedBps ?? this.uploadSpeedBps,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }
}

/// Structured, localizable failure. [messageKey] maps to l10n strings;
/// [details] is technical, log-only (already sanitized by the caller).
class AppFailure {
  const AppFailure({
    required this.messageKey,
    this.details = '',
    this.port,
    this.pid,
  });

  final String messageKey;
  final String details;
  final int? port;
  final int? pid;

  @override
  String toString() =>
      'AppFailure($messageKey${details.isEmpty ? '' : ': $details'})';
}

/// Result of a single connectivity probe.
class ProbeResult {
  const ProbeResult({
    required this.name,
    required this.success,
    this.latencyMs,
    this.detail = '',
  });

  final String name;
  final bool success;
  final int? latencyMs;
  final String detail;
}
