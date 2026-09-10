/// Connectivity probing: DNS, TCP, SOCKS-handshake, full-chain profile tests.
///
/// [ProfileProbe] is the honest latency story: it spawns a *temporary* core
/// with the candidate profile on ephemeral ports and measures a real
/// SOCKS5 CONNECT through the whole chain — not a bare ping to the server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/core_adapter.dart';
import '../core/port_probe.dart';
import '../core/xray_config_builder.dart';
import '../logging/log_service.dart';
import '../models/connection.dart';
import '../models/profile.dart';
import '../models/settings.dart';

class ConnectivityService {
  ConnectivityService({required LogService log}) : _log = log;

  final LogService _log;

  Future<ProbeResult> probeTcp(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return ProbeResult(
          name: 'tcp', success: true, latencyMs: stopwatch.elapsedMilliseconds,);
    } on Object catch (e) {
      _log.debug('probe', 'TCP $host:$port failed: $e');
      return ProbeResult(name: 'tcp', success: false, detail: '$e');
    }
  }

  Future<ProbeResult> probeSystemDns(
    String hostname, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(hostname)
          .timeout(timeout);
      if (addresses.isEmpty) {
        return const ProbeResult(
            name: 'dns', success: false, detail: 'no records',);
      }
      return ProbeResult(
          name: 'dns',
          success: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          detail: addresses.first.address,);
    } on Object catch (e) {
      return ProbeResult(name: 'dns', success: false, detail: '$e');
    }
  }

  Future<ProbeResult> probeCustomDns(
    String hostname,
    String dnsServer, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final answers =
          await DnsQuery.queryARecords(hostname, dnsServer, timeout: timeout);
      if (answers.isEmpty) {
        return const ProbeResult(
            name: 'dns', success: false, detail: 'no A records',);
      }
      return ProbeResult(
          name: 'dns',
          success: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          detail: answers.first,);
    } on Object catch (e) {
      return ProbeResult(name: 'dns', success: false, detail: '$e');
    }
  }

  /// SOCKS5 greeting handshake against a local inbound (proves the core's
  /// inbound is alive without needing any remote target).
  Future<ProbeResult> probeSocksHandshake(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      try {
        socket.add([0x05, 0x01, 0x00]); // VER, NMETHODS=1, NO AUTH
        await socket.flush();
        final reply = await socket.first.timeout(timeout);
        if (reply.length >= 2 && reply[0] == 0x05 && reply[1] == 0x00) {
          return ProbeResult(
              name: 'socks',
              success: true,
              latencyMs: stopwatch.elapsedMilliseconds,);
        }
        return const ProbeResult(
            name: 'socks', success: false, detail: 'bad handshake reply',);
      } finally {
        socket.destroy();
      }
    } on Object catch (e) {
      return ProbeResult(name: 'socks', success: false, detail: '$e');
    }
  }
}

// ---------------------------------------------------------------------------
// Minimal DNS A-query over UDP (custom-server testing without c-ares).
// ---------------------------------------------------------------------------

abstract final class DnsQuery {
  static Future<List<String>> queryARecords(
    String hostname,
    String server, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final random = Random();
    final txId = random.nextInt(0xFFFF);
    final packet = _buildQuery(txId, hostname);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(packet, InternetAddress(server), 53);
      final event = await socket
          .timeout(timeout)
          .firstWhere((e) => e == RawSocketEvent.read);
      if (event != RawSocketEvent.read) return [];
      final datagram = socket.receive();
      if (datagram == null) return [];
      return _parseARecords(datagram.data, txId);
    } finally {
      socket.close();
    }
  }

  static Uint8List _buildQuery(int txId, String hostname) {
    final builder = BytesBuilder();
    builder.add([(txId >> 8) & 0xFF, txId & 0xFF]); // ID
    builder.add([0x01, 0x00]); // flags: recursion desired
    builder.add([0x00, 0x01]); // QDCOUNT=1
    builder.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]); // AN/NS/AR = 0
    for (final label in hostname.split('.')) {
      final bytes = utf8.encode(label);
      builder.add([bytes.length]);
      builder.add(bytes);
    }
    builder.add([0x00]); // root
    builder.add([0x00, 0x01]); // QTYPE=A
    builder.add([0x00, 0x01]); // QCLASS=IN
    return builder.toBytes();
  }

  static List<String> _parseARecords(Uint8List data, int txId) {
    if (data.length < 12) return [];
    if ((data[0] << 8 | data[1]) != txId) return [];
    if ((data[3] & 0x0F) != 0) return []; // RCODE != 0
    final answers = (data[6] << 8) | data[7];
    var offset = 12;
    // Skip question section.
    while (offset < data.length && data[offset] != 0) {
      offset += data[offset] + 1;
    }
    offset += 5; // null + QTYPE + QCLASS
    final results = <String>[];
    for (var i = 0; i < answers && offset + 10 <= data.length; i++) {
      // NAME (label or pointer).
      if ((data[offset] & 0xC0) == 0xC0) {
        offset += 2;
      } else {
        while (offset < data.length && data[offset] != 0) {
          offset += data[offset] + 1;
        }
        offset += 1;
      }
      if (offset + 10 > data.length) break;
      final type = (data[offset] << 8) | data[offset + 1];
      final rdLength = (data[offset + 8] << 8) | data[offset + 9];
      offset += 10;
      if (type == 1 && rdLength == 4 && offset + 4 <= data.length) {
        results.add(
            '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}',);
      }
      offset += rdLength;
    }
    return results;
  }
}

// ---------------------------------------------------------------------------
// SOCKS5 CONNECT through an inbound (full-chain latency measurement).
// ---------------------------------------------------------------------------

class SocksConnectResult {
  const SocksConnectResult({required this.success, this.latencyMs, this.detail = ''});

  final bool success;
  final int? latencyMs;
  final String detail;
}

abstract final class Socks5Client {
  /// CONNECT [targetHost]:[targetPort] via the SOCKS5 proxy at
  /// [proxyHost]:[proxyPort]. Measures handshake+connect time, then closes.
  static Future<SocksConnectResult> connectThrough({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();
      final greeting = await socket.first.timeout(timeout);
      if (greeting.length < 2 || greeting[0] != 0x05 || greeting[1] != 0x00) {
        return const SocksConnectResult(
            success: false, detail: 'proxy auth required or bad greeting',);
      }
      final request = BytesBuilder()
        ..add([0x05, 0x01, 0x00, 0x03, targetHost.length])
        ..add(utf8.encode(targetHost))
        ..add([(targetPort >> 8) & 0xFF, targetPort & 0xFF]);
      socket.add(request.toBytes());
      await socket.flush();
      final reply = await socket.first.timeout(timeout);
      if (reply.length < 2 || reply[0] != 0x05) {
        return const SocksConnectResult(
            success: false, detail: 'bad connect reply',);
      }
      if (reply[1] != 0x00) {
        return SocksConnectResult(
            success: false, detail: 'proxy refused: code=${reply[1]}',);
      }
      return SocksConnectResult(
          success: true, latencyMs: stopwatch.elapsedMilliseconds,);
    } on Object catch (e) {
      return SocksConnectResult(success: false, detail: '$e');
    } finally {
      socket?.destroy();
    }
  }
}

// ---------------------------------------------------------------------------
// Full-chain profile probe (temporary core on ephemeral ports).
// ---------------------------------------------------------------------------

class ProfileProbeResult {
  const ProfileProbeResult({
    required this.success,
    this.latencyMs,
    this.detail = '',
  });

  final bool success;
  final int? latencyMs;
  final String detail;
}

class ProfileProbe {
  ProfileProbe({
    required CoreAdapter adapter,
    required XrayConfigBuilder builder,
    required String executable,
    required LogService log,
    this.targetHost = '8.8.8.8',
    this.targetPort = 53,
  })  : _adapter = adapter,
        _builder = builder,
        _executable = executable,
        _log = log;

  final CoreAdapter _adapter;
  final XrayConfigBuilder _builder;
  final String _executable;
  final LogService _log;
  final String targetHost;
  final int targetPort;

  /// Spawn a throwaway core for [profile], CONNECT through it, kill it.
  /// Returns measured chain latency or a structured failure.
  Future<ProfileProbeResult> probe(
    ProxyProfile profile,
    AppSettings settings, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    CoreProcess? process;
    Directory? sandbox;
    try {
      final socksPort = await _freePort();
      final httpPort = await _freePort();
      final testSettings = settings.copyWith(
        enableStatsApi: false,
        inbounds: settings.inbounds.copyWith(
          socksPort: socksPort,
          httpPort: httpPort,
          bindAddress: '127.0.0.1',
        ),
      );
      final config =
          _builder.build(profile: profile, settings: testSettings);
      sandbox = await Directory.systemTemp.createTemp('iranlink-probe-');
      final configPath = '${sandbox.path}/config.json';
      await File(configPath).writeAsString(json.encode(config));
      process = await _adapter
          .start(CoreStartRequest(
              executable: _executable, configPath: configPath,),)
          .timeout(timeout);

      // Wait for the inbound to accept connections.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var ready = false;
      var exited = false;
      unawaited(process.exitCode.then((_) => exited = true));
      while (DateTime.now().isBefore(deadline) && !exited) {
        if (await canConnect('127.0.0.1', socksPort)) {
          ready = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!ready) {
        return const ProfileProbeResult(
            success: false, detail: 'test core did not start',);
      }
      final check = await Socks5Client.connectThrough(
        proxyHost: '127.0.0.1',
        proxyPort: socksPort,
        targetHost: targetHost,
        targetPort: targetPort,
        timeout: timeout,
      );
      return ProfileProbeResult(
          success: check.success,
          latencyMs: check.latencyMs,
          detail: check.detail,);
    } on Object catch (e) {
      _log.debug('probe', 'Profile probe failed', error: e);
      return ProfileProbeResult(success: false, detail: '$e');
    } finally {
      try {
        await process?.terminateGracefully(
            timeout: const Duration(seconds: 3),);
      } on Object {
        // ignore
      }
      try {
        await sandbox?.delete(recursive: true);
      } on Object {
        // ignore
      }
    }
  }

  Future<int> _freePort() async {
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
