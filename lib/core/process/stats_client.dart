import 'dart:io';
import 'dart:math' as math;

/// Traffic counters read from the core API.
class TrafficStats {
  const TrafficStats({this.uplink = 0, this.downlink = 0});

  final int uplink;
  final int downlink;

  int get total => uplink + downlink;
}

/// Queries the core statistics API.
///
/// Both Xray and v2ray expose their stats over gRPC, which we reach through
/// the `api statsquery` sub command of the core binary. When the call fails
/// (older core, API disabled, port busy) the client simply reports zeroes so
/// that the UI never breaks.
class StatsClient {
  StatsClient({required this.corePath, required this.apiPort});

  final String corePath;
  final int apiPort;

  Future<TrafficStats> query({String pattern = 'inbound>>>'}) async {
    if (corePath.isEmpty || !File(corePath).existsSync()) {
      return const TrafficStats();
    }
    try {
      final result = await Process.run(
        corePath,
        <String>[
          'api',
          'statsquery',
          '--server=127.0.0.1:$apiPort',
          '--pattern=$pattern',
        ],
        runInShell: false,
      ).timeout(const Duration(seconds: 5));

      final output =
          '${result.stdout ?? ''}\n${result.stderr ?? ''}';
      return _parse(output);
    } on Object {
      return const TrafficStats();
    }
  }

  static TrafficStats _parse(String output) {
    var up = 0;
    var down = 0;
    final regexp = RegExp(
      r'"?name"?\s*[:=]\s*"?([^"\n,]+)"?[\s\S]{0,80}?"?value"?\s*[:=]\s*(\d+)',
      multiLine: true,
    );
    for (final match in regexp.allMatches(output)) {
      final name = match.group(1) ?? '';
      final value = int.tryParse(match.group(2) ?? '') ?? 0;
      if (name.contains('uplink')) {
        up += value;
      } else if (name.contains('downlink')) {
        down += value;
      }
    }
    return TrafficStats(uplink: up, downlink: down);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    final exponent = math.min(
      units.length - 1,
      (math.log(bytes) / math.log(1024)).floor(),
    );
    final value = bytes / math.pow(1024, exponent);
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[exponent]}';
  }
}
