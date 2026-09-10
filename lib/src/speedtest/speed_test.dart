/// User-triggered speed test through the active connection.
///
/// Measures: TCP ping to the proxy server, SOCKS CONNECT latency (chain
/// latency), and optional download/upload throughput via plain HTTP over a
/// SOCKS5 tunnel. Never runs automatically; always cancellable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/app_version.dart';
import '../logging/log_service.dart';
import '../models/profile.dart';
import '../models/settings.dart';
import '../network/connectivity.dart';

class SpeedTestResult {
  const SpeedTestResult({
    required this.serverPingMs,
    required this.chainLatencyMs,
    this.downloadKbps,
    this.uploadKbps,
    this.detail = '',
  },);

  final int? serverPingMs;
  final int? chainLatencyMs;
  final int? downloadKbps;
  final int? uploadKbps;
  final String detail;
}

class SpeedTestService {
  SpeedTestService({required LogService log}) : _log = log;

  final LogService _log;

  /// Well-known endpoints; overridable for restricted networks.
  String downloadUrl = 'https://speed.cloudflare.com/__down?bytes=5000000';
  String uploadUrl = 'https://speed.cloudflare.com/__up';

  Future<SpeedTestResult> run({
    required ProxyProfile profile,
    required AppSettings settings,
    bool includeThroughput = true,
  },) async {
    _log.info('speedtest', 'Starting speed test for ${profile.name}');
    final connectivity = ConnectivityService(log: _log);
    final ping = await connectivity.probeTcp(profile.address, profile.port);
    final chain = await Socks5Client.connectThrough(
      proxyHost: settings.inbounds.bindAddress,
      proxyPort: settings.inbounds.socksPort,
      targetHost: '8.8.8.8',
      targetPort: 53,
    );
    if (!includeThroughput) {
      return SpeedTestResult(
        serverPingMs: ping.latencyMs,
        chainLatencyMs: chain.latencyMs,
      );
    }
    final download = await _measureDownload(settings);
    final upload = await _measureUpload(settings);
    _log.info('speedtest',
        'Done: ping=${ping.latencyMs} chain=${chain.latencyMs} '
        'down=${download}kbps up=${upload}kbps',);
    return SpeedTestResult(
      serverPingMs: ping.latencyMs,
      chainLatencyMs: chain.latencyMs,
      downloadKbps: download,
      uploadKbps: upload,
    );
  }

  Future<int?> _measureDownload(AppSettings settings) async {
    try {
      final uri = Uri.parse(downloadUrl);
      final socket = await _tunnelSocket(settings, uri);
      try {
        final request = 'GET ${uri.path}?${uri.query} HTTP/1.1\r\n'
            'Host: ${uri.host}\r\n'
            'Connection: close\r\n'
            'User-Agent: IranLink/$kAppVersion\r\n\r\n';
        socket.add(utf8.encode(request));
        await socket.flush();
        var bodyBytes = 0;
        var headerDone = false;
        var headerBuffer = <int>[];
        final stopwatch = Stopwatch()..start();
        await for (final chunk
            in socket.timeout(const Duration(seconds: 45))) {
          if (!headerDone) {
            headerBuffer.addAll(chunk);
            final text = utf8.decode(headerBuffer, allowMalformed: true);
            final end = text.indexOf('\r\n\r\n');
            if (end >= 0) {
              headerDone = true;
              bodyBytes +=
                  headerBuffer.length - (end + 4) > 0 ? headerBuffer.length - (end + 4) : 0;
              headerBuffer = [];
            }
          } else {
            bodyBytes += chunk.length;
          }
        }
        stopwatch.stop();
        if (bodyBytes <= 0 || stopwatch.elapsedMilliseconds <= 0) return null;
        return (bodyBytes / 1024 / (stopwatch.elapsedMilliseconds / 1000)).round();
      } finally {
        socket.destroy();
      }
    } on Object catch (e) {
      _log.warning('speedtest', 'Download test failed', error: e);
      return null;
    }
  }

  Future<int?> _measureUpload(AppSettings settings) async {
    try {
      final uri = Uri.parse(uploadUrl);
      final payload = Uint8List(1024 * 1024); // 1 MiB of zeros
      final socket = await _tunnelSocket(settings, uri);
      try {
        final header = 'POST ${uri.path} HTTP/1.1\r\n'
            'Host: ${uri.host}\r\n'
            'Content-Length: ${payload.length}\r\n'
            'Connection: close\r\n'
            'User-Agent: IranLink\r\n\r\n';
        final stopwatch = Stopwatch()..start();
        socket.add(utf8.encode(header));
        socket.add(payload);
        await socket.flush();
        // Wait for any response bytes (or close) to confirm delivery.
        await socket.first.timeout(const Duration(seconds: 45));
        stopwatch.stop();
        if (stopwatch.elapsedMilliseconds <= 0) return null;
        return (payload.length / 1024 / (stopwatch.elapsedMilliseconds / 1000)).round();
      } finally {
        socket.destroy();
      }
    } on Object catch (e) {
      _log.warning('speedtest', 'Upload test failed', error: e);
      return null;
    }
  }

  /// Open a TCP tunnel to [uri] through the local SOCKS inbound (CONNECT),
  /// upgrading to TLS for `https` URLs, and return the ready socket.
  Future<Socket> _tunnelSocket(AppSettings settings, Uri uri) async {
    final socket = await Socket.connect(
      settings.inbounds.bindAddress,
      settings.inbounds.socksPort,
      timeout: const Duration(seconds: 10),
    );
    try {
      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();
      final greeting =
          await socket.first.timeout(const Duration(seconds: 10));
      if (greeting.length < 2 || greeting[1] != 0x00) {
        throw StateError('SOCKS handshake failed');
      }
      final port = uri.hasPort ? uri.port : 80;
      final request = BytesBuilder()
        ..add([0x05, 0x01, 0x00, 0x03, uri.host.length])
        ..add(utf8.encode(uri.host))
        ..add([(port >> 8) & 0xFF, port & 0xFF]);
      socket.add(request.toBytes());
      await socket.flush();
      final reply = await socket.first.timeout(const Duration(seconds: 10));
      if (reply.length < 2 || reply[1] != 0x00) {
        throw StateError('SOCKS connect refused');
      }
      if (uri.scheme == 'https') {
        final secure = await SecureSocket.secure(
          socket,
          host: uri.host,
          onBadCertificate: (_) => false,
        ).timeout(const Duration(seconds: 15));
        return secure;
      }
      return socket;
    } on Object {
      socket.destroy();
      rethrow;
    }
  }
}
