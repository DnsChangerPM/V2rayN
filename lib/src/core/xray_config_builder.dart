/// Xray configuration builder (pure Dart).
///
/// Translates a [ProxyProfile] + [AppSettings] into canonical Xray JSON.
/// No secrets leave this layer unprotected: the emitted config is written to a
/// private runtime file by [CoreManager] and deleted on stop.
library;

import 'dart:convert';

import '../models/profile.dart';
import '../models/settings.dart';

/// Tags used by the generated config (stable contract with the validator,
/// the stats client, and routing rules).
abstract final class XrayTags {
  static const String proxy = 'proxy';
  static const String direct = 'direct';
  static const String blocked = 'blocked';
  static const String api = 'api';
  static const String socksInbound = 'socks-in';
  static const String httpInbound = 'http-in';
}

class XrayConfigBuilder {
  const XrayConfigBuilder();

  /// Build a complete Xray config for [profile] under [settings].
  Map<String, dynamic> build({
    required ProxyProfile profile,
    required AppSettings settings,
  }) {
    if (profile.protocol == ProxyProtocol.xrayJson) {
      return buildFromRawJson(
        rawJson: profile.rawJson ?? '{}',
        settings: settings,
      );
    }
    return {
      'log': {'loglevel': 'warning'},
      'inbounds': _inbounds(settings),
      'outbounds': _outbounds(profile, settings),
      'routing': _routing(settings),
      'dns': _dns(settings),
      'api': {'tag': XrayTags.api, 'services': ['StatsService']},
      'policy': _policy(),
      'stats': <String, dynamic>{},
    };
  }

  /// Merge user-supplied raw Xray JSON with IranLink-managed blocks.
  /// Guarantees: our inbounds exist, stats API exists, api routing rule
  /// exists. Everything else passes through untouched.
  Map<String, dynamic> buildFromRawJson({
    required String rawJson,
    required AppSettings settings,
  }) {
    final decoded = json.decode(rawJson);
    if (decoded is! Map<dynamic, dynamic>) {
      throw const FormatException('Raw config must be a JSON object');
    }
    final config = (decoded as Map<dynamic, dynamic>).cast<String, dynamic>();

    final inbounds = _asMapList(config['inbounds']);
    for (final managed in _inbounds(settings)) {
      final tag = managed['tag'];
      if (!inbounds.any((b) => b['tag'] == tag)) inbounds.add(managed);
    }
    config['inbounds'] = inbounds;

    config['api'] ??= {'tag': XrayTags.api, 'services': ['StatsService']};
    config['policy'] ??= _policy();
    config['stats'] ??= <String, dynamic>{};

    final routing = (config['routing'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? {};
    final rules = _asMapList(routing['rules']);
    final hasApiRule = rules.any((r) =>
        _asStrings(r['inboundTag']).contains(XrayTags.api) &&
        r['outboundTag'] == XrayTags.api);
    if (!hasApiRule) {
      rules.insert(0, {
        'type': 'field',
        'inboundTag': [XrayTags.api],
        'outboundTag': XrayTags.api,
      });
    }
    routing['rules'] = rules;
    config['routing'] = routing;
    return config;
  }

  // -- inbounds ------------------------------------------------------------

  List<Map<String, dynamic>> _inbounds(AppSettings settings) {
    final inbounds = settings.inbounds;
    final tuning = settings.tuning;
    final result = <Map<String, dynamic>>[];
    if (inbounds.enableSocks) {
      result.add({
        'tag': XrayTags.socksInbound,
        'protocol': 'socks',
        'listen': inbounds.bindAddress,
        'port': inbounds.socksPort,
        'settings': {
          'auth': inbounds.socksAuth ? 'password' : 'noauth',
          if (inbounds.socksAuth)
            'accounts': [
              {'user': inbounds.socksUsername, 'pass': ''}
            ],
          'udp': tuning.enableUdp,
          'ip': inbounds.bindAddress,
        },
        'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']},
      });
    }
    if (inbounds.enableHttp) {
      result.add({
        'tag': XrayTags.httpInbound,
        'protocol': 'http',
        'listen': inbounds.bindAddress,
        'port': inbounds.httpPort,
        'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']},
      });
    }
    if (settings.enableStatsApi) {
      result.add({
        'tag': XrayTags.api,
        'protocol': 'dokodemo-door',
        'listen': '127.0.0.1',
        'port': settings.statsPort,
        'settings': {'address': '127.0.0.1'},
      });
    }
    return result;
  }

  // -- outbounds -----------------------------------------------------------

  List<Map<String, dynamic>> _outbounds(
      ProxyProfile profile, AppSettings settings) {
    return [
      _proxyOutbound(profile, settings),
      {'tag': XrayTags.direct, 'protocol': 'freedom', 'settings': <String, dynamic>{}},
      {'tag': XrayTags.blocked, 'protocol': 'blackhole', 'settings': <String, dynamic>{}},
    ];
  }

  Map<String, dynamic> _proxyOutbound(
      ProxyProfile profile, AppSettings settings) {
    final stream = _streamSettings(profile, settings);
    switch (profile.protocol) {
      case ProxyProtocol.vmess:
        return {
          'tag': XrayTags.proxy,
          'protocol': 'vmess',
          'settings': {
            'vnext': [
              {
                'address': profile.address,
                'port': profile.port,
                'users': [
                  {
                    'id': profile.secret,
                    'alterId': int.tryParse(profile.extra['aid'] ?? '0') ?? 0,
                    'security': profile.security.isEmpty ? 'auto' : profile.security,
                  }
                ],
              }
            ],
          },
          'streamSettings': stream,
        };
      case ProxyProtocol.vless:
        return {
          'tag': XrayTags.proxy,
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': profile.address,
                'port': profile.port,
                'users': [
                  {
                    'id': profile.secret,
                    'encryption': profile.security.isEmpty ? 'none' : profile.security,
                    if (profile.flow.isNotEmpty) 'flow': profile.flow,
                  }
                ],
              }
            ],
          },
          'streamSettings': stream,
        };
      case ProxyProtocol.trojan:
        return {
          'tag': XrayTags.proxy,
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {
                'address': profile.address,
                'port': profile.port,
                'password': profile.secret,
              }
            ],
          },
          'streamSettings': stream,
        };
      case ProxyProtocol.shadowsocks:
        return {
          'tag': XrayTags.proxy,
          'protocol': 'shadowsocks',
          'settings': {
            'servers': [
              {
                'address': profile.address,
                'port': profile.port,
                'method': profile.method,
                'password': profile.secret,
              }
            ],
          },
          'streamSettings': {'network': 'tcp'},
        };
      case ProxyProtocol.socks:
        return {
          'tag': XrayTags.proxy,
          'protocol': 'socks',
          'settings': {
            'servers': [
              {
                'address': profile.address,
                'port': profile.port,
                if (profile.username.isNotEmpty)
                  'users': [
                    {'user': profile.username, 'pass': profile.secret}
                  ],
              }
            ],
          },
          'streamSettings': {'network': 'tcp'},
        };
      case ProxyProtocol.http:
        return {
          'tag': XrayTags.proxy,
          'protocol': 'http',
          'settings': {
            'servers': [
              {
                'address': profile.address,
                'port': profile.port,
                if (profile.username.isNotEmpty)
                  'users': [
                    {'user': profile.username, 'pass': profile.secret}
                  ],
              }
            ],
          },
          'streamSettings': {'network': 'tcp'},
        };
      case ProxyProtocol.xrayJson:
        throw StateError('Raw-JSON profiles use buildFromRawJson');
    }
  }

  Map<String, dynamic> _streamSettings(
      ProxyProfile profile, AppSettings settings) {
    final stream = <String, dynamic>{'network': _network(profile.transport)};
    final security =
        profile.tls == TlsMode.none ? 'none' : profile.tls.name;
    stream['security'] = security;
    if (profile.tls == TlsMode.tls) {
      stream['tlsSettings'] = {
        'serverName': profile.sni.isEmpty ? profile.address : profile.sni,
        if (profile.fingerprint.isNotEmpty) 'fingerprint': profile.fingerprint,
        if (profile.alpn.isNotEmpty) 'alpn': profile.alpn,
      };
    } else if (profile.tls == TlsMode.reality) {
      stream['realitySettings'] = {
        'serverName': profile.sni.isEmpty ? profile.address : profile.sni,
        'fingerprint': profile.fingerprint,
        'publicKey': profile.publicKey,
        'shortId': profile.shortId,
        if (profile.spiderX.isNotEmpty) 'spiderX': profile.spiderX,
      };
    }
    switch (profile.transport) {
      case TransportType.ws:
        stream['wsSettings'] = {
          'path': profile.path.isEmpty ? '/' : profile.path,
          if (profile.host.isNotEmpty)
            'headers': {'Host': profile.host},
        };
      case TransportType.grpc:
        stream['grpcSettings'] = {
          'serviceName': profile.serviceName,
        };
      case TransportType.h2:
        stream['httpSettings'] = {
          if (profile.host.isNotEmpty) 'host': [profile.host],
          'path': profile.path.isEmpty ? '/' : profile.path,
        };
      case TransportType.httpupgrade:
        stream['httpupgradeSettings'] = {
          'path': profile.path.isEmpty ? '/' : profile.path,
          if (profile.host.isNotEmpty) 'host': profile.host,
        };
      case TransportType.splithttp:
        stream['splithttpSettings'] = {
          'path': profile.path.isEmpty ? '/' : profile.path,
          if (profile.host.isNotEmpty) 'host': profile.host,
        };
      case TransportType.kcp:
        stream['kcpSettings'] = {
          'header': {'type': profile.extra['headerType'] ?? 'none'},
        };
      case TransportType.quic:
        stream['quicSettings'] = {
          'security': 'none',
          'header': {'type': profile.extra['headerType'] ?? 'none'},
        };
      case TransportType.tcp:
        final headerType = profile.extra['headerType'] ?? 'none';
        if (headerType == 'http') {
          stream['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': [profile.path.isEmpty ? '/' : profile.path],
                if (profile.host.isNotEmpty)
                  'headers': {
                    'Host': [profile.host]
                  },
              },
            },
          };
        }
    }
    final tuning = settings.tuning;
    if (tuning.tcpKeepAlive) {
      stream['sockopt'] = {
        'tcpKeepAliveIdle': tuning.keepAliveIntervalSeconds,
      };
    }
    return stream;
  }

  String _network(TransportType transport) {
    return switch (transport) {
      TransportType.tcp => 'tcp',
      TransportType.ws => 'ws',
      TransportType.grpc => 'grpc',
      TransportType.h2 => 'h2',
      TransportType.httpupgrade => 'httpupgrade',
      TransportType.splithttp => 'splithttp',
      TransportType.kcp => 'mkcp',
      TransportType.quic => 'quic',
    };
  }

  // -- routing -------------------------------------------------------------

  Map<String, dynamic> _routing(AppSettings settings) {
    final routing = settings.routing;
    final rules = <Map<String, dynamic>>[
      {
        'type': 'field',
        'inboundTag': [XrayTags.api],
        'outboundTag': XrayTags.api,
      },
    ];
    switch (routing.mode) {
      case RoutingMode.global:
        if (routing.bypassLan) {
          rules.add({
            'type': 'field',
            'outboundTag': XrayTags.direct,
            'ip': ['geoip:private'],
          });
        }
        rules.add({
          'type': 'field',
          'outboundTag': XrayTags.proxy,
          'network': 'tcp,udp',
        });
      case RoutingMode.proxy:
        // Strict: absolutely everything through the proxy.
        rules.add({
          'type': 'field',
          'outboundTag': XrayTags.proxy,
          'network': 'tcp,udp',
        });
      case RoutingMode.direct:
        rules.add({
          'type': 'field',
          'outboundTag': XrayTags.direct,
          'network': 'tcp,udp',
        });
      case RoutingMode.ruleBased:
        for (final rule in routing.rules.where((r) => r.enabled)) {
          rules.add({
            'type': 'field',
            'outboundTag': _ruleTarget(rule.outbound),
            if (rule.domains.isNotEmpty) 'domain': rule.domains,
            if (rule.ips.isNotEmpty) 'ip': rule.ips,
            if (rule.ports.isNotEmpty) 'port': rule.ports.join(','),
            if (rule.protocols.isNotEmpty) 'protocol': rule.protocols,
          });
        }
        if (routing.bypassLan) {
          rules.add({
            'type': 'field',
            'outboundTag': XrayTags.direct,
            'ip': ['geoip:private'],
          });
        }
        if (routing.bypassIran) {
          rules.add({
            'type': 'field',
            'outboundTag': XrayTags.direct,
            'ip': ['geoip:ir'],
            'domain': ['geosite:category-ir'],
          });
        }
        rules.add({
          'type': 'field',
          'outboundTag': XrayTags.proxy,
          'network': 'tcp,udp',
        });
    }
    return {'domainStrategy': 'IPIfNonMatch', 'rules': rules};
  }

  String _ruleTarget(String outbound) {
    return switch (outbound) {
      'direct' => XrayTags.direct,
      'block' => XrayTags.blocked,
      _ => XrayTags.proxy,
    };
  }

  // -- dns / policy --------------------------------------------------------

  Map<String, dynamic> _dns(AppSettings settings) {
    final dns = settings.dns;
    final tuning = settings.tuning;
    final servers = <dynamic>[];
    if (dns.enableDoh && dns.dohUrl.isNotEmpty) {
      servers.add(dns.dohUrl);
    }
    if (dns.useSystemDns) {
      servers.add('localhost');
    }
    servers.addAll(dns.servers.where((s) => s.trim().isNotEmpty));
    if (servers.isEmpty) servers.add('8.8.8.8');
    final queryStrategy = switch (tuning.ipPreference) {
      IpPreference.preferIpv4 => 'UseIPv4',
      IpPreference.preferIpv6 => 'UseIPv6',
      IpPreference.auto => 'UseIP',
    };
    return {
      'servers': servers,
      'queryStrategy': queryStrategy,
      'disableCache': false,
    };
  }

  Map<String, dynamic> _policy() => {
        'levels': {
          '0': {'statsUserUplink': true, 'statsUserDownlink': true},
        },
        'system': {
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      };

  // -- helpers -------------------------------------------------------------

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List<dynamic>) return [];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  List<String> _asStrings(dynamic value) {
    if (value is List<dynamic>) return value.map((e) => e.toString()).toList();
    if (value is String) return [value];
    return const [];
  }
}
