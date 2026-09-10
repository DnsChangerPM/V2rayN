import 'dart:convert';

import 'enums.dart';

/// A single server (a.k.a. node / profile).
class Profile {
  Profile({
    String? id,
    this.remark = '',
    this.protocol = ProtocolType.vless,
    this.address = '',
    this.port = 443,
    this.uuid = '',
    this.password = '',
    this.security = '',
    this.flow = '',
    this.encryption = 'none',
    this.alterId = 0,
    this.cipher = 'auto',
    this.network = TransportType.tcp,
    this.host = '',
    this.path = '',
    this.sni = '',
    this.fingerprint = '',
    this.alpn = '',
    this.allowInsecure = false,
    this.realityPublicKey = '',
    this.realityShortId = '',
    this.realitySpiderX = '/',
    this.fragment = FragmentPreset.off,
    this.enableUdp = true,
    this.enabled = true,
    this.sortOrder = 0,
    this.subscriptionId,
    this.lastDelayMs,
    this.lastSpeedKbps,
    this.lastTestedAt,
  }) : id = id ?? _newId();

  static int _counter = 0;

  static String _newId() {
    _counter++;
    return 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$_counter';
  }

  final String id;
  String remark;
  ProtocolType protocol;
  String address;
  int port;

  // vless / vmess
  String uuid;
  String encryption;
  String flow;
  int alterId;
  String cipher;

  // trojan / shadowsocks
  String password;

  /// shadowsocks cipher, or `none` / `tls` / `reality` for the other protocols.
  String security;

  // transport
  TransportType network;
  String host;
  String path;
  String sni;
  String fingerprint;
  String alpn;
  bool allowInsecure;

  // reality
  String realityPublicKey;
  String realityShortId;
  String realitySpiderX;

  /// TLS-hello fragmentation (Xray only).
  FragmentPreset fragment;

  bool enableUdp;
  bool enabled;
  int sortOrder;
  String? subscriptionId;

  // measured values
  int? lastDelayMs;
  double? lastSpeedKbps;
  DateTime? lastTestedAt;

  SecurityType get securityType =>
      SecurityType.tryParse(security) ?? SecurityType.none;

  bool get isReality => securityType == SecurityType.reality;

  bool get isTls => securityType == SecurityType.tls;

  /// The value Xray expects for `streamSettings.security`.
  String get streamSecurity => switch (securityType) {
        SecurityType.reality => 'reality',
        SecurityType.tls => 'tls',
        SecurityType.none => 'none',
      };

  String get displayName =>
      remark.trim().isNotEmpty ? remark.trim() : '$address:$port';

  String get transportLabel => network.id;

  Profile copyWith({
    String? remark,
    ProtocolType? protocol,
    String? address,
    int? port,
    String? uuid,
    String? password,
    String? security,
    String? flow,
    String? encryption,
    int? alterId,
    String? cipher,
    TransportType? network,
    String? host,
    String? path,
    String? sni,
    String? fingerprint,
    String? alpn,
    bool? allowInsecure,
    String? realityPublicKey,
    String? realityShortId,
    String? realitySpiderX,
    FragmentPreset? fragment,
    bool? enableUdp,
    bool? enabled,
    int? sortOrder,
  }) {
    return Profile(
      id: id,
      remark: remark ?? this.remark,
      protocol: protocol ?? this.protocol,
      address: address ?? this.address,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
      security: security ?? this.security,
      flow: flow ?? this.flow,
      encryption: encryption ?? this.encryption,
      alterId: alterId ?? this.alterId,
      cipher: cipher ?? this.cipher,
      network: network ?? this.network,
      host: host ?? this.host,
      path: path ?? this.path,
      sni: sni ?? this.sni,
      fingerprint: fingerprint ?? this.fingerprint,
      alpn: alpn ?? this.alpn,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      realityPublicKey: realityPublicKey ?? this.realityPublicKey,
      realityShortId: realityShortId ?? this.realityShortId,
      realitySpiderX: realitySpiderX ?? this.realitySpiderX,
      fragment: fragment ?? this.fragment,
      enableUdp: enableUdp ?? this.enableUdp,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      subscriptionId: subscriptionId,
      lastDelayMs: lastDelayMs,
      lastSpeedKbps: lastSpeedKbps,
      lastTestedAt: lastTestedAt,
    );
  }

  /// Stable key used to detect duplicates when updating a subscription.
  String get fingerprintKey =>
      '${protocol.id}|$address|$port|$uuid|$password|${network.id}|$path|$host|$sni';

  // -------------------------------------------------------------------------
  // Core JSON
  // -------------------------------------------------------------------------

  /// Builds the Xray / V2Ray outbound object for this profile.
  ///
  /// [core] matters because a few options (fragmentation, XTLS flows) only
  /// exist in Xray-core.
  Map<String, dynamic> toOutbound({
    required CoreType core,
    String tag = 'proxy',
    bool fragmentEnabled = false,
    String fragmentLength = '10-20',
    String fragmentInterval = '5-10',
  }) {
    final settings = <String, dynamic>{};
    switch (protocol) {
      case ProtocolType.vless:
        settings['vnext'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'address': address,
            'port': port,
            'users': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': uuid,
                'encryption': encryption.isEmpty ? 'none' : encryption,
                if (core == CoreType.xray && flow.isNotEmpty) 'flow': flow,
                'level': 0,
              },
            ],
          },
        ];
        break;
      case ProtocolType.vmess:
        settings['vnext'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'address': address,
            'port': port,
            'users': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': uuid,
                'alterId': alterId,
                'security': cipher.isEmpty ? 'auto' : cipher,
                'level': 0,
              },
            ],
          },
        ];
        break;
      case ProtocolType.trojan:
        settings['servers'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'address': address,
            'port': port,
            'password': password,
            'level': 0,
          },
        ];
        break;
      case ProtocolType.shadowsocks:
        settings['servers'] = <Map<String, dynamic>>[
          <Map<String, dynamic>>{
            'address': address,
            'port': port,
            'method': security,
            'password': password,
            'level': 0,
          },
        ];
        break;
    }

    return <String, dynamic>{
      'tag': tag,
      'protocol': protocol.id,
      'settings': settings,
      'streamSettings': _streamSettings(
        core: core,
        fragmentEnabled: fragmentEnabled,
        fragmentLength: fragmentLength,
        fragmentInterval: fragmentInterval,
      ),
      'mux': <String, dynamic>{'enabled': false, 'concurrency': -1},
    };
  }

  Map<String, dynamic> _streamSettings({
    required CoreType core,
    required bool fragmentEnabled,
    required String fragmentLength,
    required String fragmentInterval,
  }) {
    final stream = <String, dynamic>{
      'network': network.id,
      'security': streamSecurity,
    };

    switch (network) {
      case TransportType.ws:
        stream['wsSettings'] = <String, dynamic>{
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'headers': <String, dynamic>{'Host': host},
        };
        break;
      case TransportType.grpc:
        stream['grpcSettings'] = <String, dynamic>{
          'serviceName': path.isEmpty ? '' : path,
          'multiMode': false,
        };
        break;
      case TransportType.h2:
        stream['httpSettings'] = <String, dynamic>{
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': <String>[host],
        };
        break;
      case TransportType.httpupgrade:
        stream['httpupgradeSettings'] = <String, dynamic>{
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': host,
        };
        break;
      case TransportType.xhttp:
        if (core == CoreType.xray) {
          stream['xhttpSettings'] = <String, dynamic>{
            'path': path.isEmpty ? '/' : path,
            if (host.isNotEmpty) 'host': host,
          };
        }
        break;
      case TransportType.quic:
        stream['quicSettings'] = <String, dynamic>{
          'security': 'none',
          'key': '',
          'header': <String, dynamic>{'type': 'none'},
        };
        break;
      case TransportType.tcp:
        break;
    }

    if (securityType == SecurityType.tls) {
      stream['tlsSettings'] = <String, dynamic>{
        'serverName': sni.isEmpty ? _fallbackSni : sni,
        'allowInsecure': allowInsecure,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        if (alpn.isNotEmpty) 'alpn': _splitList(alpn),
      };
    } else if (securityType == SecurityType.reality && core == CoreType.xray) {
      stream['realitySettings'] = <String, dynamic>{
        'show': false,
        'fingerprint': fingerprint.isEmpty ? 'chrome' : fingerprint,
        'serverName': sni.isEmpty ? _fallbackSni : sni,
        'publicKey': realityPublicKey,
        'shortId': realityShortId,
        'spiderX': realitySpiderX.isEmpty ? '/' : realitySpiderX,
      };
    } else if (securityType == SecurityType.reality) {
      // v2ray-core has no REALITY: degrade to plain TLS so that the config
      // still loads instead of failing to start.
      stream['security'] = 'tls';
      stream['tlsSettings'] = <String, dynamic>{
        'serverName': sni.isEmpty ? _fallbackSni : sni,
        'allowInsecure': allowInsecure,
      };
    }

    // Socket options tuned for lossy / throttled links.
    stream['sockopt'] = <String, dynamic>{
      'tcpFastOpen': true,
      'tcpKeepAliveInterval': 60,
    };

    // TLS-hello fragmentation (Xray only, `finalmask` since Xray 25.x).
    if (core == CoreType.xray &&
        fragmentEnabled &&
        fragment != FragmentPreset.off) {
      stream['finalmask'] = <String, dynamic>{
        'tcp': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'fragment',
            'settings': <String, dynamic>{
              'packets': fragment == FragmentPreset.tlsHello ? 'tlshello' : '1-3',
              'length': fragmentLength,
              'delay': fragmentInterval,
              'maxSplit': fragment == FragmentPreset.tlsHello ? '1-1' : '1-3',
            },
          },
        ],
      };
    }

    return stream;
  }

  String get _fallbackSni {
    if (host.isNotEmpty && !_isIpAddress(host)) {
      return host;
    }
    if (!_isIpAddress(address)) {
      return address;
    }
    return '';
  }

  static bool _isIpAddress(String value) {
    final parts = value.split('.');
    if (parts.length != 4) {
      return false;
    }
    return parts.every((part) => int.tryParse(part) != null);
  }

  static List<String> _splitList(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  // -------------------------------------------------------------------------
  // Share links
  // -------------------------------------------------------------------------

  String toShareLink() {
    final name = Uri.encodeComponent(displayName);
    switch (protocol) {
      case ProtocolType.vless:
        final query = <String, String>{
          'encryption': encryption.isEmpty ? 'none' : encryption,
          'security': streamSecurity,
          if (network != TransportType.tcp) 'type': network.id,
          if (flow.isNotEmpty) 'flow': flow,
          if (sni.isNotEmpty) 'sni': sni,
          if (fingerprint.isNotEmpty) 'fp': fingerprint,
          if (host.isNotEmpty && network.needsHost) 'host': host,
          if (path.isNotEmpty && network.needsPath) 'path': path,
          if (isReality) 'pbk': realityPublicKey,
          if (isReality && realityShortId.isNotEmpty) 'sid': realityShortId,
          if (isReality) 'spx': realitySpiderX,
        };
        return 'vless://$uuid@${_authority()}?${_encodeQuery(query)}#$name';

      case ProtocolType.vmess:
        final json = <String, dynamic>{
          'v': '2',
          'ps': displayName,
          'add': address,
          'port': port.toString(),
          'id': uuid,
          'aid': alterId.toString(),
          'scy': cipher,
          'net': network.id,
          'type': 'none',
          'host': host,
          'path': path,
          'tls': streamSecurity,
          'sni': sni,
        };
        return 'vmess://${base64Encode(utf8.encode(jsonEncode(json)))}';

      case ProtocolType.trojan:
        final query = <String, String>{
          'security': streamSecurity,
          if (network != TransportType.tcp) 'type': network.id,
          if (sni.isNotEmpty) 'sni': sni,
          if (host.isNotEmpty && network.needsHost) 'host': host,
          if (path.isNotEmpty && network.needsPath) 'path': path,
        };
        return 'trojan://${Uri.encodeComponent(password)}@${_authority()}?${_encodeQuery(query)}#$name';

      case ProtocolType.shadowsocks:
        final userinfo =
            base64Encode(utf8.encode('$security:$password')).replaceAll('=', '');
        return 'ss://$userinfo@${_authority()}#$name';
    }
  }

  String _authority() {
    final host =
        address.contains(':') && !address.startsWith('[') ? '[$address]' : address;
    return '$host:$port';
  }

  static String _encodeQuery(Map<String, String> values) => values.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'remark': remark,
        'protocol': protocol.id,
        'address': address,
        'port': port,
        'uuid': uuid,
        'password': password,
        'security': security,
        'flow': flow,
        'encryption': encryption,
        'alterId': alterId,
        'cipher': cipher,
        'network': network.id,
        'host': host,
        'path': path,
        'sni': sni,
        'fingerprint': fingerprint,
        'alpn': alpn,
        'allowInsecure': allowInsecure,
        'realityPublicKey': realityPublicKey,
        'realityShortId': realityShortId,
        'realitySpiderX': realitySpiderX,
        'fragment': fragment.id,
        'enableUdp': enableUdp,
        'enabled': enabled,
        'sortOrder': sortOrder,
        if (subscriptionId != null) 'subscriptionId': subscriptionId,
        if (lastDelayMs != null) 'lastDelayMs': lastDelayMs,
        if (lastSpeedKbps != null) 'lastSpeedKbps': lastSpeedKbps,
        if (lastTestedAt != null)
          'lastTestedAt': lastTestedAt!.millisecondsSinceEpoch,
      };

  static Profile fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String?,
        remark: json['remark'] as String? ?? '',
        protocol:
            ProtocolType.tryParse(json['protocol'] as String?) ?? ProtocolType.vless,
        address: json['address'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 443,
        uuid: json['uuid'] as String? ?? '',
        password: json['password'] as String? ?? '',
        security: json['security'] as String? ?? '',
        flow: json['flow'] as String? ?? '',
        encryption: json['encryption'] as String? ?? 'none',
        alterId: (json['alterId'] as num?)?.toInt() ?? 0,
        cipher: json['cipher'] as String? ?? 'auto',
        network:
            TransportType.tryParse(json['network'] as String?) ?? TransportType.tcp,
        host: json['host'] as String? ?? '',
        path: json['path'] as String? ?? '',
        sni: json['sni'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
        alpn: json['alpn'] as String? ?? '',
        allowInsecure: json['allowInsecure'] as bool? ?? false,
        realityPublicKey: json['realityPublicKey'] as String? ?? '',
        realityShortId: json['realityShortId'] as String? ?? '',
        realitySpiderX: json['realitySpiderX'] as String? ?? '/',
        fragment:
            FragmentPreset.tryParse(json['fragment'] as String?) ?? FragmentPreset.off,
        enableUdp: json['enableUdp'] as bool? ?? true,
        enabled: json['enabled'] as bool? ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        subscriptionId: json['subscriptionId'] as String?,
        lastDelayMs: (json['lastDelayMs'] as num?)?.toInt(),
        lastSpeedKbps: (json['lastSpeedKbps'] as num?)?.toDouble(),
        lastTestedAt: json['lastTestedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['lastTestedAt'] as num).toInt())
            : null,
      );
}
