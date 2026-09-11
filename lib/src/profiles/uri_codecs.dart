/// Share-link codecs (pure Dart): parse + generate proxy URIs.
///
/// Supported schemes: `vmess://`, `vless://`, `trojan://`, `ss://`,
/// `socks://`, `socks5://`, `http://` (proxy form with userinfo).
/// Not supported here: subscription URLs (see [SubscriptionParser]) and
/// Clash/YAML (explicitly out of scope for v1).
library;

import 'dart:convert';

import '../models/profile.dart';
import '../utils/validators.dart';

/// Normalize lenient base64 (urlsafe alphabet, missing padding, whitespace).
String normalizeBase64(String input) {
  var s = input.trim().replaceAll(RegExp(r'\s'), '');
  final hadUrlSafe = s.contains('-') || s.contains('_');
  s = s.replaceAll('-', '+').replaceAll('_', '/');
  switch (s.length % 4) {
    case 2:
      return '$s==';
    case 3:
      return '$s=';
    case 1:
      // A length of 1 mod 4 cannot be valid base64. Plain-alphabet input is
      // rejected outright; urlsafe-flavored input gets lenient single padding
      // rather than a hard failure (upstream generators are sloppy).
      if (!hadUrlSafe) {
        throw const FormatException('Invalid base64 length');
      }
      return '$s=';
    default:
      return s;
  }
}

String decodeBase64Text(String input) {
  try {
    return utf8.decode(base64.decode(normalizeBase64(input)));
  } on FormatException {
    // Some links are base64-of-base64 or url-encoded payloads.
    final once = utf8.decode(base64.decode(normalizeBase64(input)),
        allowMalformed: true,);
    return utf8.decode(base64.decode(normalizeBase64(once)),
        allowMalformed: true,);
  }
}

String encodeBase64UrlNoPad(String input) =>
    base64Url.encode(utf8.encode(input)).replaceAll('=', '');

String _fragmentName(Uri uri, String fallback) {
  if (uri.fragment.isEmpty) return fallback;
  try {
    return Uri.decodeComponent(uri.fragment);
  } on ArgumentError {
    return uri.fragment;
  }
}

String? _query(Uri uri, List<String> keys) {
  for (final key in keys) {
    final value = uri.queryParameters[key];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

TlsMode _tlsFromSecurity(String? security) {
  switch ((security ?? '').toLowerCase()) {
    case 'tls':
      return TlsMode.tls;
    case 'reality':
      return TlsMode.reality;
    default:
      return TlsMode.none;
  }
}

TransportType _transportFrom(String? net) {
  switch ((net ?? '').toLowerCase()) {
    case 'ws':
    case 'websocket':
      return TransportType.ws;
    case 'grpc':
    case 'gun':
      return TransportType.grpc;
    case 'h2':
      return TransportType.h2;
    case 'httpupgrade':
      return TransportType.httpupgrade;
    case 'splithttp':
      return TransportType.splithttp;
    case 'kcp':
    case 'mkcp':
      return TransportType.kcp;
    case 'quic':
      return TransportType.quic;
    default:
      return TransportType.tcp;
  }
}

/// Parse any supported share link. Returns null when [link] is not a
/// recognized proxy URI (caller may treat it as subscription/raw config).
ProxyProfile? parseShareLink(String link, {required String Function() newId}) {
  final text = link.trim();
  if (text.isEmpty || !text.contains('://')) return null;
  final scheme = text.substring(0, text.indexOf('://')).toLowerCase();
  try {
    switch (scheme) {
      case 'vmess':
        return _parseVmess(text, newId());
      case 'vless':
        return _parseVless(text, newId());
      case 'trojan':
        return _parseTrojan(text, newId());
      case 'ss':
      case 'shadowsocks':
        return _parseShadowsocks(text, newId());
      case 'socks':
      case 'socks5':
        return _parseSocks(text, newId());
      case 'http':
      case 'https':
        return _parseHttpProxy(text, newId());
      default:
        return null;
    }
  } on FormatException {
    return null;
  }
}

// ---------------------------------------------------------------------------
// vmess://base64(json)
// ---------------------------------------------------------------------------
ProxyProfile? _parseVmess(String link, String id) {
  final payload = link.substring('vmess://'.length).trim();
  if (payload.isEmpty) return null;
  final decoded = decodeBase64Text(payload);
  final map = json.decode(decoded);
  if (map is! Map<dynamic, dynamic>) return null;
  String str(String key) => (map[key] ?? '').toString();
  final port = int.tryParse(str('port')) ?? 0;
  final address = str('add');
  final uuid = str('id');
  if (address.isEmpty || port <= 0 || !isValidUuid(uuid)) return null;
  final tlsWord = str('tls').toLowerCase();
  return ProxyProfile(
    id: id,
    name: str('ps').isEmpty ? '$address:$port' : str('ps'),
    protocol: ProxyProtocol.vmess,
    address: address,
    port: port,
    secret: uuid,
    security: str('scy').isEmpty ? 'auto' : str('scy'),
    transport: _transportFrom(str('net')),
    tls: (tlsWord == 'tls' || tlsWord == 'true' || tlsWord == '1')
        ? TlsMode.tls
        : TlsMode.none,
    sni: str('sni'),
    alpn: str('alpn').isEmpty ? const [] : str('alpn').split(','),
    path: str('path'),
    host: str('host'),
    fingerprint: str('fp'),
    extra: {
      'aid': str('aid').isEmpty ? '0' : str('aid'),
      'headerType': str('type'),
    },
  );
}

// ---------------------------------------------------------------------------
// vless://uuid@host:port?params#name
// ---------------------------------------------------------------------------
ProxyProfile? _parseVless(String link, String id) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final uuid = uri.userInfo;
  if (!isValidUuid(uuid)) return null;
  final params = uri.queryParameters;
  final transport = _transportFrom(params['type'] ?? params['net']);
  return ProxyProfile(
    id: id,
    name: _fragmentName(uri, '${uri.host}:${uri.port}'),
    protocol: ProxyProtocol.vless,
    address: uri.host,
    port: uri.hasPort ? uri.port : 443,
    secret: uuid,
    security: params['encryption'] ?? 'none',
    transport: transport,
    tls: _tlsFromSecurity(params['security']),
    sni: params['sni'] ?? params['peer'] ?? '',
    alpn: (params['alpn'] ?? '').isEmpty ? const [] : params['alpn']!.split(','),
    path: params['path'] ?? '',
    host: _query(uri, ['host', 'obfsParam']) ?? '',
    serviceName: params['serviceName'] ?? '',
    flow: params['flow'] ?? '',
    fingerprint: params['fp'] ?? '',
    publicKey: params['pbk'] ?? '',
    shortId: params['sid'] ?? '',
    spiderX: params['spx'] ?? '',
  );
}

// ---------------------------------------------------------------------------
// trojan://password@host:port?params#name
// ---------------------------------------------------------------------------
ProxyProfile? _parseTrojan(String link, String id) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.host.isEmpty || uri.userInfo.isEmpty) return null;
  final params = uri.queryParameters;
  final security = params['security'] ?? 'tls';
  return ProxyProfile(
    id: id,
    name: _fragmentName(uri, '${uri.host}:${uri.port}'),
    protocol: ProxyProtocol.trojan,
    address: uri.host,
    port: uri.hasPort ? uri.port : 443,
    secret: Uri.decodeComponent(uri.userInfo),
    transport: _transportFrom(params['type'] ?? params['net']),
    tls: _tlsFromSecurity(security),
    sni: params['sni'] ?? params['peer'] ?? uri.host,
    alpn: (params['alpn'] ?? '').isEmpty ? const [] : params['alpn']!.split(','),
    path: params['path'] ?? '',
    host: _query(uri, ['host', 'obfsParam']) ?? '',
    fingerprint: params['fp'] ?? '',
  );
}

// ---------------------------------------------------------------------------
// ss://...
// ---------------------------------------------------------------------------
ProxyProfile? _parseShadowsocks(String link, String id) {
  var rest = link.trim();
  rest = rest.substring(rest.indexOf('://') + 3);
  // Split off #fragment (name) and ?query (plugin etc.).
  var name = '';
  final hashIndex = rest.indexOf('#');
  if (hashIndex >= 0) {
    name = rest.substring(hashIndex + 1);
    rest = rest.substring(0, hashIndex);
    try {
      name = Uri.decodeComponent(name);
    } on ArgumentError {
      // keep raw
    }
  }
  var query = '';
  final queryIndex = rest.indexOf('?');
  if (queryIndex >= 0) {
    query = rest.substring(queryIndex);
    rest = rest.substring(0, queryIndex);
  }
  String method = '';
  String password = '';
  String hostPort;
  if (rest.contains('@')) {
    // ss://base64(method:password)@host:port
    final at = rest.lastIndexOf('@');
    final userInfo = decodeBase64Text(rest.substring(0, at));
    hostPort = rest.substring(at + 1);
    final colon = userInfo.indexOf(':');
    if (colon < 0) return null;
    method = userInfo.substring(0, colon);
    password = userInfo.substring(colon + 1);
  } else {
    // ss://base64(method:password@host:port)
    final decoded = decodeBase64Text(rest);
    final at = decoded.lastIndexOf('@');
    if (at < 0) return null;
    final userInfo = decoded.substring(0, at);
    hostPort = decoded.substring(at);
    final colon = userInfo.indexOf(':');
    if (colon < 0) return null;
    method = userInfo.substring(0, colon);
    password = userInfo.substring(colon + 1);
  }
  final probe = Uri.tryParse('ss://$hostPort');
  if (probe == null || probe.host.isEmpty || !probe.hasPort) return null;
  final plugin = query.isEmpty
      ? ''
      : (Uri.tryParse('ss://x$query')?.queryParameters['plugin'] ?? '');
  return ProxyProfile(
    id: id,
    name: name.isEmpty ? '${probe.host}:${probe.port}' : name,
    protocol: ProxyProtocol.shadowsocks,
    address: probe.host,
    port: probe.port,
    secret: password,
    method: method,
    extra: plugin.isEmpty ? const {} : {'plugin': plugin},
  );
}

// ---------------------------------------------------------------------------
// socks://[user:pass@]host:port#name
// ---------------------------------------------------------------------------
ProxyProfile? _parseSocks(String link, String id) {
  var normalized = link.trim();
  if (normalized.toLowerCase().startsWith('socks://')) {
    normalized = 'socks5://${normalized.substring('socks://'.length)}';
  }
  var uri = Uri.tryParse(normalized);
  // Some generators base64 the whole userinfo@host:port part.
  if ((uri == null || uri.host.isEmpty) && !normalized.contains('@')) {
    try {
      final decoded = decodeBase64Text(
          normalized.substring(normalized.indexOf('://') + 3),);
      uri = Uri.tryParse('socks5://$decoded');
    } on FormatException {
      return null;
    }
  }
  if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
  var username = '';
  var password = '';
  if (uri.userInfo.isNotEmpty) {
    final parts = uri.userInfo.split(':');
    username = Uri.decodeComponent(parts[0]);
    if (parts.length > 1) password = Uri.decodeComponent(parts.sublist(1).join(':'));
  }
  return ProxyProfile(
    id: id,
    name: _fragmentName(uri, '${uri.host}:${uri.port}'),
    protocol: ProxyProtocol.socks,
    address: uri.host,
    port: uri.port,
    secret: password,
    username: username,
  );
}

// ---------------------------------------------------------------------------
// http://[user:pass@]host:port — HTTP proxy form. Userinfo is optional;
// bare host:port links are valid (unauthenticated) HTTP proxies. Callers
// that must tell subscription URLs apart from proxies apply their own
// heuristic (see ProfileImporter).
// ---------------------------------------------------------------------------
ProxyProfile? _parseHttpProxy(String link, String id) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final parts = uri.userInfo.split(':');
  return ProxyProfile(
    id: id,
    name: _fragmentName(uri, '${uri.host}:${uri.port}'),
    protocol: ProxyProtocol.http,
    address: uri.host,
    port: uri.hasPort ? uri.port : 8080,
    secret: parts.length > 1 ? Uri.decodeComponent(parts.sublist(1).join(':')) : '',
    username: Uri.decodeComponent(parts[0]),
    tls: uri.scheme == 'https' ? TlsMode.tls : TlsMode.none,
  );
}

// ---------------------------------------------------------------------------
// Encoders (share / export / QR)
// ---------------------------------------------------------------------------

String _enc(String value) => Uri.encodeComponent(value);

/// Encode a profile back to its canonical share-link form. Returns '' when
/// the profile cannot be represented (e.g. raw JSON).
String encodeShareLink(ProxyProfile profile) {
  switch (profile.protocol) {
    case ProxyProtocol.vless:
      return _encodeVless(profile);
    case ProxyProtocol.trojan:
      return _encodeTrojan(profile);
    case ProxyProtocol.shadowsocks:
      return _encodeShadowsocks(profile);
    case ProxyProtocol.socks:
      return _encodeSocks(profile);
    case ProxyProtocol.http:
      return _encodeHttp(profile);
    case ProxyProtocol.vmess:
      return _encodeVmess(profile);
    case ProxyProtocol.xrayJson:
      return '';
  }
}

String _commonQuery(ProxyProfile p) {
  final params = <String, String>{
    'type': p.transport.name,
    'security': p.tls.name == 'none' ? 'none' : p.tls.name,
  };
  void addIf(String key, String value) {
    if (value.isNotEmpty) params[key] = value;
  }

  addIf('sni', p.sni);
  addIf('fp', p.fingerprint);
  addIf('alpn', p.alpn.join(','));
  addIf('path', p.path);
  addIf('host', p.host);
  addIf('serviceName', p.serviceName);
  addIf('flow', p.flow);
  addIf('pbk', p.publicKey);
  addIf('sid', p.shortId);
  addIf('spx', p.spiderX);
  return params.entries.map((e) => '${e.key}=${_enc(e.value)}').join('&');
}

String _encodeVless(ProxyProfile p) =>
    'vless://${p.secret}@${p.address}:${p.port}?${_commonQuery(p)}#${_enc(p.name)}';

String _encodeTrojan(ProxyProfile p) =>
    'trojan://${_enc(p.secret)}@${p.address}:${p.port}?${_commonQuery(p)}#${_enc(p.name)}';

String _encodeShadowsocks(ProxyProfile p) {
  final userInfo = encodeBase64UrlNoPad('${p.method}:${p.secret}');
  return 'ss://$userInfo@${p.address}:${p.port}#${_enc(p.name)}';
}

String _encodeSocks(ProxyProfile p) {
  final auth = p.username.isEmpty ? '' : '${_enc(p.username)}:${_enc(p.secret)}@';
  return 'socks5://$auth${p.address}:${p.port}#${_enc(p.name)}';
}

String _encodeHttp(ProxyProfile p) {
  final auth = p.username.isEmpty ? '' : '${_enc(p.username)}:${_enc(p.secret)}@';
  final scheme = p.tls == TlsMode.tls ? 'https' : 'http';
  return '$scheme://$auth${p.address}:${p.port}#${_enc(p.name)}';
}

String _encodeVmess(ProxyProfile p) {
  final map = {
    'v': '2',
    'ps': p.name,
    'add': p.address,
    'port': p.port.toString(),
    'id': p.secret,
    'aid': p.extra['aid'] ?? '0',
    'scy': p.security,
    'net': p.transport.name,
    'type': p.extra['headerType'] ?? 'none',
    'host': p.host,
    'path': p.path,
    'tls': p.tls == TlsMode.tls ? 'tls' : '',
    'sni': p.sni,
    'alpn': p.alpn.join(','),
    'fp': p.fingerprint,
  };
  return 'vmess://${encodeBase64UrlNoPad(json.encode(map))}';
}
