/// Human-readable formatting (pure Dart). Locale-specific digit shaping is
/// handled by the UI layer; these helpers produce plain ASCII strings.
library;

const List<String> _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB'];

/// `1536` -> `1.5 KB`. [decimals] defaults to 1.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _byteUnits.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
  return '$text ${_byteUnits[unit]}';
}

/// Bytes/second -> `1.5 MB/s`.
String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// `90` -> `1:30`, `3661` -> `1:01:01`. Negative/zero -> `0:00`.
String formatUptime(int totalSeconds) {
  if (totalSeconds <= 0) return '0:00';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// `–` for unknown latency, otherwise `42 ms`.
String formatLatency(int? milliseconds) =>
    milliseconds == null || milliseconds < 0 ? '–' : '$milliseconds ms';

/// Masks the middle of a secret for UI display: `abcdef123456` -> `ab•••56`.
String maskMiddle(String secret, {int keepStart = 2, int keepEnd = 2}) {
  if (secret.length <= keepStart + keepEnd + 3) return '•••';
  return '${secret.substring(0, keepStart)}•••${secret.substring(secret.length - keepEnd)}';
}
