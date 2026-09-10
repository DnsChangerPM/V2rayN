import 'dart:async';
import 'dart:io';

/// Latency and throughput measurements.
///
/// "Real ping" measures a request that actually traverses the proxy, which is
/// the only number that matters for a user sitting behind a throttled link.
class LatencyTester {
  LatencyTester({this.testUrl = 'http://www.gstatic.com/generate_204'});

  final String testUrl;

  /// Plain TCP connect time to [host]:[port], in milliseconds.
  Future<int?> tcpPing(String host, int port,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } on Object {
      return null;
    }
  }

  /// Measures the round trip of an HTTP request through the local proxy.
  ///
  /// Returns `null` when the proxy cannot be reached.
  Future<int?> proxyDelay(int httpPort,
      {Duration timeout = const Duration(seconds: 6)}) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(testUrl);
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        httpPort,
        timeout: const Duration(seconds: 3),
      );
      socket.write(
        'GET $testUrl HTTP/1.1\r\n'
        'Host: ${uri.host}\r\n'
        'User-Agent: Radin\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await socket.flush();
      await socket.first.timeout(timeout);
      return stopwatch.elapsedMilliseconds;
    } on Object {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// Downloads [url] through the local proxy for at most [maxDuration] and
  /// returns the throughput in kbit/s.
  Future<double?> downloadThroughputKbps(
    int httpPort, {
    String url = 'https://speed.cloudflare.com/__down?bytes=10000000',
    Duration maxDuration = const Duration(seconds: 10),
  }) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    var bytes = 0;
    try {
      final uri = Uri.parse(url);
      final ssl = uri.scheme == 'https';
      final targetPort = uri.hasPort
          ? uri.port
          : (ssl ? 443 : 80);

      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        httpPort,
        timeout: const Duration(seconds: 3),
      );
      if (ssl) {
        // Ask the proxy to tunnel, then upgrade to TLS.
        socket.write('CONNECT ${uri.host}:$targetPort HTTP/1.1\r\n\r\n');
        await socket.flush();
        final completer = Completer<void>();
        final subscription = socket.listen((_) => completer.complete());
        await completer.future.timeout(const Duration(seconds: 5));
        await subscription.cancel();
        socket = await SecureSocket.secure(socket, host: uri.host);
      }

      socket.write(
        'GET ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''} HTTP/1.1\r\n'
        'Host: ${uri.host}\r\n'
        'User-Agent: Radin\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await socket.flush();

      var headerDone = false;
      await for (final chunk in socket.timeout(maxDuration)) {
        bytes += chunk.length;
        if (!headerDone) {
          // Skip the response headers so that they do not count as payload.
          headerDone = true;
          bytes -= _headerLength(chunk);
        }
      }
      final seconds = stopwatch.elapsedMicroseconds / 1000000;
      if (seconds <= 0) {
        return null;
      }
      return (bytes * 8) / seconds / 1000;
    } on TimeoutException {
      final seconds = stopwatch.elapsedMicroseconds / 1000000;
      if (seconds <= 0 || bytes == 0) {
        return null;
      }
      return (bytes * 8) / seconds / 1000;
    } on Object {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static int _headerLength(List<int> chunk) {
    const pattern = <int>[13, 10, 13, 10];
    for (var i = 0; i + 3 < chunk.length; i++) {
      if (chunk[i] == pattern[0] &&
          chunk[i + 1] == pattern[1] &&
          chunk[i + 2] == pattern[2] &&
          chunk[i + 3] == pattern[3]) {
        return i + 4;
      }
    }
    return 0;
  }
}
