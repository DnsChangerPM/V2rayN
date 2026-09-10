import 'dart:convert';

import '../model/enums.dart';
import '../model/profile.dart';

/// Parses `vless://`, `vmess://`, `trojan://` and `ss://` share links, plus
/// subscription payloads that contain one link per line (optionally base64
/// encoded, which is what almost every panel serves).
class LinkParser {
  LinkParser._();

  static const List<String> supportedSchemes = <String>[
    'vless',
    'vmess',
    'trojan',
    'ss',
  ];

  /// Parses a single share link. Returns `null` when the link is not
  /// recognised, so that callers can simply skip bad entries.
  static Profile? parse(String rawLink) {
    final link = rawLink.trim();
    if (link.isEmpty) {
      return null;
    }

    final separator = link.indexOf('://');
    if (separator <= 0) {
      return null;
    }

    final scheme = link.substring(0, separator).toLowerCase();
    final body = link.substring(separator + 3).trim();
    if (body.isEmpty) {
      return null;
    }

    switch (scheme) {
      case 'vless':
        return _parseVless(body);
      case 'vmess':
        return _parseVmess(body);
      case 'trojan':
        return _parseTrojan(body);
      case 'ss':
        return _parseShadowsocks(body);
      default:
        return null;
    }
  }

  /// Parses a subscription payload (plain text list or base64 blob) into
  /// profiles.
  static List<Profile> parseSubscription(
    String content, {
    String? subscriptionId,
  }) {
    final decoded = _decodeSubscription(content);
    final profiles = <Profile>[];
    // Links can be separated by new lines, spaces or a mix of both.
    for (final line in decoded.split(RegExp(r'[\r\n]+'))) {
      for (final candidate in line.split(RegExp(r'\s+'))) {
        final profile = parse(candidate);
        if (profile != null) {
          profiles.add(profile..subscriptionId = subscriptionId);
        }
      }
    }
    return profiles;
  }

  static String _decodeSubscription(String content) {
    var text = content.trim();
    if (text.isEmpty) {
      return text;
    }

    // Some panels wrap the blob in JSON (SIP008-ish / clash subscriptions).
    if (text.startsWith('{')) {
      try {
        final json = jsonDecode(text);
        if (json is Map && json['servers'] is List) {
          final buffer = StringBuffer();
          for (final entry in json['servers'] as List) {
            if (entry is Map && entry['uri'] is String) {
              buffer.writeln(entry['uri'] as String);
            }
          }
          text = buffer.toString();
        }
      } on FormatException {
        // Not JSON after all - fall through.
      }
    }

    if (text.contains('://')) {
      return text;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final normalized = _normalizeBase64(text);
      final decoded = _tryDecodeBase64(normalized);
      if (decoded != null && decoded.contains('://')) {
        return decoded;
      }
      text = normalized;
    }
    return content;
  }

  static String _normalizeBase64(String value) {
    var text = value.trim().replaceAll(RegExp(r'\s+'), '');
    text = text.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = text.length % 4;
    if (remainder == 2) {
      text = '$text==';
    } else if (remainder == 3) {
      text = '$text=';
    } else if (remainder == 1) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static String? _tryDecodeBase64(String value) {
    try {
      final bytes = base64.decode(value);
      return utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Schemes
  // -------------------------------------------------------------------------

  static ({String body, Map<String, String> query, String name}) _split(String body) {
    final hash = body.indexOf('#');
    final name = hash >= 0 ? Uri.decodeComponent(body.substring(hash + 1)) : '';
    final withoutName = hash >= 0 ? body.substring(0, hash) : body;

    final question = withoutName.indexOf('?');
    final rawBody = question >= 0 ? withoutName.substring(0, question) : withoutName;
    final queryString = question >= 0 ? withoutName.substring(question + 1) : '';

    final query = <String, String>{};
    if (queryString.isNotEmpty) {
      for (final pair in queryString.split('&')) {
        if (pair.isEmpty) {
          continue;
        }
        final index = pair.indexOf('=');
        if (index <= 0) {
          query[Uri.decodeComponent(pair)] = '';
          continue;
        }
        query[Uri.decodeComponent(pair.substring(0, index))] =
            Uri.decodeComponent(pair.substring(index + 1).replaceAll('+', ' '));
      }
    }
    return (body: rawBody, query: query, name: name);
  }

  /// Splits `userinfo@host:port`, tolerating IPv6 literals.
  static ({String userinfo, String host, int port}) _splitAuthority(String value) {
    final at = value.lastIndexOf('@');
    final userinfo = at >= 0 ? value.substring(0, at) : '';
    final hostPort = at >= 0 ? value.substring(at + 1) : value;

    String host = hostPort;
    var port = 443;

    if (hostPort.startsWith('[')) {
      final close = hostPort.indexOf(']');
      if (close > 0) {
        host = hostPort.substring(1, close);
        final rest = hostPort.substring(close + 1);
        if (rest.startsWith(':')) {
          port = int.tryParse(rest.substring(1)) ?? port;
        }
      }
    } else {
      final lastColon = hostPort.lastIndexOf(':');
      if (lastColon > 0) {
        host = hostPort.substring(0, lastColon);
        port = int.tryParse(hostPort.substring(lastColon + 1)) ?? port;
      }
    }
    return (userinfo: userinfo, host: host, port: port);
  }

  static Profile? _parseVless(String body) {
    final parts = _split(body);
    final authority = _splitAuthority(parts.body);
    if (authority.host.isEmpty) {
      return null;
    }
    final query = parts.query;
    final network = TransportType.tryParse(query['type']) ?? TransportType.tcp;
    final security = SecurityType.tryParse(query['security']) ?? SecurityType.none;

    return Profile(
      remark: parts.name,
      protocol: ProtocolType.vless,
      address: authority.host,
      port: authority.port,
      uuid: Uri.decodeComponent(authority.userinfo),
      encryption: query['encryption']?.isNotEmpty == true
          ? query['encryption']!
          : 'none',
      flow: query['flow'] ?? '',
      security: security.id,
      network: network,
      host: query['host'] ?? '',
      path: query['path'] ?? query['serviceName'] ?? '',
      sni: query['sni'] ?? '',
      fingerprint: query['fp'] ?? '',
      alpn: query['alpn'] ?? '',
      allowInsecure: _asBool(query['allowInsecure']),
      realityPublicKey: query['pbk'] ?? '',
      realityShortId: query['sid'] ?? '',
      realitySpiderX: query['spx'] ?? '/',
    );
  }

  static Profile? _parseVmess(String body) {
    final decoded = _tryDecodeBase64(_normalizeBase64(body));
    if (decoded == null) {
      return null;
    }
    Map<String, dynamic> json;
    try {
      final value = jsonDecode(decoded);
      if (value is! Map) {
        return null;
      }
      json = Map<String, dynamic>.from(value);
    } on FormatException {
      return null;
    }

    final security = (json['tls'] ?? '').toString().toLowerCase() == 'tls'
        ? SecurityType.tls
        : SecurityType.none;

    return Profile(
      remark: (json['ps'] ?? '').toString(),
      protocol: ProtocolType.vmess,
      address: (json['add'] ?? '').toString(),
      port: int.tryParse((json['port'] ?? '443').toString()) ?? 443,
      uuid: (json['id'] ?? '').toString(),
      alterId: int.tryParse((json['aid'] ?? '0').toString()) ?? 0,
      cipher: (json['scy'] ?? 'auto').toString(),
      network: TransportType.tryParse(json['net']?.toString()) ??
          TransportType.tcp,
      host: (json['host'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      sni: (json['sni'] ?? json['host'] ?? '').toString(),
      security: security.id,
    );
  }

  static Profile? _parseTrojan(String body) {
    final parts = _split(body);
    final authority = _splitAuthority(parts.body);
    if (authority.host.isEmpty) {
      return null;
    }
    final query = parts.query;
    final security = SecurityType.tryParse(query['security']) ?? SecurityType.tls;

    return Profile(
      remark: parts.name,
      protocol: ProtocolType.trojan,
      address: authority.host,
      port: authority.port,
      password: Uri.decodeComponent(authority.userinfo),
      security: security.id,
      network: TransportType.tryParse(query['type']) ?? TransportType.tcp,
      host: query['host'] ?? '',
      path: query['path'] ?? '',
      sni: query['sni'] ?? query['peer'] ?? '',
      fingerprint: query['fp'] ?? '',
      alpn: query['alpn'] ?? '',
      allowInsecure: _asBool(query['allowInsecure']),
    );
  }

  static Profile? _parseShadowsocks(String body) {
    final parts = _split(body);
    final authority = _splitAuthority(parts.body);

    String? method;
    String? password;
    String host = authority.host;
    var port = authority.port;

    final userinfo = authority.userinfo;
    final decodedUserinfo = _tryDecodeBase64(_normalizeBase64(userinfo));
    for (final candidate in <String?>[decodedUserinfo, userinfo]) {
      if (candidate == null || !candidate.contains(':')) {
        continue;
      }
      final index = candidate.indexOf(':');
      method = candidate.substring(0, index);
      password = candidate.substring(index + 1);
      break;
    }

    if (method == null) {
      // Legacy form: base64("method:password@host:port")
      final decoded = _tryDecodeBase64(_normalizeBase64(parts.body));
      if (decoded != null && decoded.contains('@')) {
        final legacy = _splitAuthority(decoded);
        final index = legacy.userinfo.indexOf(':');
        if (index > 0) {
          method = legacy.userinfo.substring(0, index);
          password = legacy.userinfo.substring(index + 1);
          host = legacy.host;
          port = legacy.port;
        }
      }
    }

    if (method == null || password == null || host.isEmpty) {
      return null;
    }

    return Profile(
      remark: parts.name,
      protocol: ProtocolType.shadowsocks,
      address: host,
      port: port,
      password: password,
      security: method,
    );
  }

  static bool _asBool(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
        return true;
      default:
        return false;
    }
  }
}
