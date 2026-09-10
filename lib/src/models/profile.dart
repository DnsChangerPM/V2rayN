/// Proxy profile model (pure Dart): immutable, JSON-serializable, core-neutral.
library;

/// Supported outbound protocols. Wire encoding is the adapter's job; the model
/// only carries typed parameters.
enum ProxyProtocol {
  vmess,
  vless,
  trojan,
  shadowsocks,
  socks,
  http,
  /// Raw Xray JSON pasted by advanced users (validated before use).
  xrayJson,
}

ProxyProtocol proxyProtocolFromName(String name) {
  return ProxyProtocol.values.firstWhere(
    (p) => p.name == name,
    orElse: () => throw FormatException('Unknown protocol: $name'),
  );
}

/// Transport / network type for stream settings.
enum TransportType {
  tcp,
  ws,
  grpc,
  h2,
  httpupgrade,
  splithttp,
  kcp,
  quic,
}

TransportType transportTypeFromName(String name) {
  return TransportType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => TransportType.tcp,
  );
}

/// TLS mode for the outbound.
enum TlsMode { none, tls, reality }

TlsMode tlsModeFromName(String name) {
  return TlsMode.values.firstWhere(
    (t) => t.name == name,
    orElse: () => TlsMode.none,
  );
}

/// A single proxy profile (one server / one outbound).
class ProxyProfile {
  const ProxyProfile({
    required this.id,
    required this.name,
    required this.protocol,
    this.address = '',
    this.port = 0,
    this.secret = '',
    this.username = '',
    this.method = '',
    this.security = 'auto',
    this.transport = TransportType.tcp,
    this.tls = TlsMode.none,
    this.sni = '',
    this.alpn = const [],
    this.path = '',
    this.host = '',
    this.serviceName = '',
    this.flow = '',
    this.fingerprint = '',
    this.publicKey = '',
    this.shortId = '',
    this.spiderX = '',
    this.extra = const {},
    this.groupId = '',
    this.subscriptionId = '',
    this.isFavorite = false,
    this.lastLatencyMs,
    this.lastSpeedKbps,
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
    this.rawJson,
  },);

  final String id;
  final String name;
  final ProxyProtocol protocol;

  /// Server address (domain/IP). Never log [secret] next to it.
  final String address;
  final int port;

  /// Credential: UUID for vmess/vless, password otherwise. SECRET.
  final String secret;
  final String username;
  final String method;
  final String security;

  final TransportType transport;
  final TlsMode tls;
  final String sni;
  final List<String> alpn;
  final String path;
  final String host;
  final String serviceName;
  final String flow;
  final String fingerprint;
  final String publicKey;
  final String shortId;
  final String spiderX;

  /// Protocol-specific leftovers (forward-compatible).
  final Map<String, String> extra;

  final String groupId;
  final String subscriptionId;
  final bool isFavorite;
  final int? lastLatencyMs;
  final int? lastSpeedKbps;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Full Xray JSON for [ProxyProtocol.xrayJson] (validated before use).
  final String? rawJson;

  ProxyProfile copyWith({
    String? id,
    String? name,
    ProxyProtocol? protocol,
    String? address,
    int? port,
    String? secret,
    String? username,
    String? method,
    String? security,
    TransportType? transport,
    TlsMode? tls,
    String? sni,
    List<String>? alpn,
    String? path,
    String? host,
    String? serviceName,
    String? flow,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    String? spiderX,
    Map<String, String>? extra,
    String? groupId,
    String? subscriptionId,
    bool? isFavorite,
    int? lastLatencyMs,
    int? lastSpeedKbps,
    DateTime? lastUsedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? rawJson,
  },) {
    return ProxyProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      address: address ?? this.address,
      port: port ?? this.port,
      secret: secret ?? this.secret,
      username: username ?? this.username,
      method: method ?? this.method,
      security: security ?? this.security,
      transport: transport ?? this.transport,
      tls: tls ?? this.tls,
      sni: sni ?? this.sni,
      alpn: alpn ?? this.alpn,
      path: path ?? this.path,
      host: host ?? this.host,
      serviceName: serviceName ?? this.serviceName,
      flow: flow ?? this.flow,
      fingerprint: fingerprint ?? this.fingerprint,
      publicKey: publicKey ?? this.publicKey,
      shortId: shortId ?? this.shortId,
      spiderX: spiderX ?? this.spiderX,
      extra: extra ?? this.extra,
      groupId: groupId ?? this.groupId,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      isFavorite: isFavorite ?? this.isFavorite,
      lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
      lastSpeedKbps: lastSpeedKbps ?? this.lastSpeedKbps,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'address': address,
        'port': port,
        'secret': secret,
        'username': username,
        'method': method,
        'security': security,
        'transport': transport.name,
        'tls': tls.name,
        'sni': sni,
        'alpn': alpn,
        'path': path,
        'host': host,
        'serviceName': serviceName,
        'flow': flow,
        'fingerprint': fingerprint,
        'publicKey': publicKey,
        'shortId': shortId,
        'spiderX': spiderX,
        'extra': extra,
        'groupId': groupId,
        'subscriptionId': subscriptionId,
        'isFavorite': isFavorite,
        'lastLatencyMs': lastLatencyMs,
        'lastSpeedKbps': lastSpeedKbps,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'rawJson': rawJson,
      };

  factory ProxyProfile.fromJson(Map<String, dynamic> json) {
    String str(String key) => (json[key] ?? '').toString();
    int? intOrNull(String key) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    DateTime? dateOrNull(String key) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return ProxyProfile(
      id: str('id'),
      name: str('name'),
      protocol: proxyProtocolFromName(str('protocol')),
      address: str('address'),
      port: intOrNull('port') ?? 0,
      secret: str('secret'),
      username: str('username'),
      method: str('method'),
      security: json['security']?.toString() ?? 'auto',
      transport: transportTypeFromName(str('transport').isEmpty ? 'tcp' : str('transport')),
      tls: tlsModeFromName(str('tls').isEmpty ? 'none' : str('tls')),
      sni: str('sni'),
      alpn: (json['alpn'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      path: str('path'),
      host: str('host'),
      serviceName: str('serviceName'),
      flow: str('flow'),
      fingerprint: str('fingerprint'),
      publicKey: str('publicKey'),
      shortId: str('shortId'),
      spiderX: str('spiderX'),
      extra: (json['extra'] as Map<dynamic, dynamic>?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      groupId: str('groupId'),
      subscriptionId: str('subscriptionId'),
      isFavorite: json['isFavorite'] == true,
      lastLatencyMs: intOrNull('lastLatencyMs'),
      lastSpeedKbps: intOrNull('lastSpeedKbps'),
      lastUsedAt: dateOrNull('lastUsedAt'),
      createdAt: dateOrNull('createdAt'),
      updatedAt: dateOrNull('updatedAt'),
      rawJson: json['rawJson']?.toString(),
    );
  }

  /// Identity used for subscription diffing (stable across refreshes).
  String get identityKey =>
      '${protocol.name}|$address|$port|${username.isEmpty ? secret : username}|$method|$sni|$path|$serviceName';
}

/// User-defined profile group.
class ProfileGroup {
  const ProfileGroup({required this.id, required this.name, this.isBuiltin = false});

  final String id;
  final String name;
  final bool isBuiltin;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'isBuiltin': isBuiltin};

  factory ProfileGroup.fromJson(Map<String, dynamic> json) => ProfileGroup(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        isBuiltin: json['isBuiltin'] == true,
      );
}

/// Built-in group ids (always present, localized at display time).
abstract final class BuiltinGroups {
  static const String all = 'all';
  static const String favorites = 'favorites';
  static const String gaming = 'gaming';
  static const String work = 'work';
  static const String personal = 'personal';
  static const List<String> values = [all, favorites, gaming, work, personal];
}

enum ProfileSortKey { name, latency, speed, lastUsed, favorite }

enum SortDirection { ascending, descending }
