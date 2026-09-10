import 'dart:convert';

import '../model/enums.dart';
import '../model/profile.dart';
import '../model/settings.dart';

/// Builds the full Xray / V2Ray JSON configuration for a connection.
///
/// The generated configuration is deliberately opinionated:
///
/// * **IPv4 only DNS** - IPv6 is broken or missing on most Iranian ISPs, and
///   AAAA answers cause long stalls.
/// * **Iranian domains and IPs go direct** - no reason to pay the latency (or
///   the traffic quota) for traffic that never leaves the country.
/// * **QUIC (UDP/443) is blocked by default** - Iranian ISPs throttle UDP hard,
///   so forcing browsers back to TCP/TLS is usually much faster.
/// * **mux disabled** - it destroys throughput on lossy links.
/// * **sniffing with `routeOnly`** - routing decisions use the real domain
///   without leaking the resolved IP to the proxy.
class CoreConfigBuilder {
  CoreConfigBuilder({
    required this.settings,
    required this.profile,
    required this.profiles,
    required this.coreType,
  });

  final AppSettings settings;
  final Profile profile;
  final List<Profile> profiles;

  /// The core that will consume this config; a few options are Xray only.
  final CoreType coreType;

  static const String tagProxy = 'proxy';
  static const String tagDirect = 'direct';
  static const String tagBlock = 'block';
  static const String tagDnsOut = 'dns-out';
  static const String tagApiIn = 'api-in';
  static const String tagApiOut = 'api';
  static const String tagBalancer = 'balancer';

  bool get _isXray => coreType == CoreType.xray;

  Map<String, dynamic> build() {
    final outbounds = <Map<String, dynamic>>[];
    final balancerTags = <String>[];

    if (settings.autoSelectFastest) {
      final candidates = _balancerCandidates();
      for (var i = 0; i < candidates.length; i++) {
        final tag = 's$i';
        balancerTags.add(tag);
        outbounds.add(candidates[i].toOutbound(
          core: coreType,
          tag: tag,
          fragmentEnabled: settings.enableFragment,
          fragmentLength: settings.fragmentLength,
          fragmentInterval: settings.fragmentInterval,
        ));
      }
      // Guard against an empty selector (Xray refuses to start then).
      if (balancerTags.isEmpty) {
        balancerTags.add(tagProxy);
        outbounds.add(_mainOutbound());
      }
    } else {
      outbounds.add(_mainOutbound());
    }

    outbounds.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'tag': tagDirect,
        'protocol': 'freedom',
        'settings': <String, dynamic>{
          // Force IPv4 on direct connections as well: many Iranian sites
          // publish AAAA records that simply do not work.
          'domainStrategy': settings.dnsUseIpv4Only ? 'UseIPv4' : 'AsIs',
        },
      },
      <String, dynamic>{
        'tag': tagBlock,
        'protocol': 'blackhole',
        'settings': <String, dynamic>{
          'response': <String, dynamic>{'type': 'none'},
        },
      },
      if (_isXray)
        <String, dynamic>{
          'tag': tagDnsOut,
          'protocol': 'dns',
          'settings': <String, dynamic>{
            'network': 'tcp',
            'address': settings.dnsIran,
            'port': 53,
          },
        },
    ]);

    return <String, dynamic>{
      'log': <String, dynamic>{'loglevel': settings.logLevel},
      'dns': _buildDns(),
      'inbounds': _buildInbounds(),
      'outbounds': outbounds,
      'routing': _buildRouting(balancerTags),
      'policy': _buildPolicy(),
      'stats': <String, dynamic>{},
      'api': <String, dynamic>{
        'tag': tagApiOut,
        'services': <String>['StatsService', 'RoutingService'],
      },
      if (_isXray && settings.autoSelectFastest)
        'observatory': <String, dynamic>{
          'subjectSelector': balancerTags,
          'probeUrl': settings.probeUrl,
          'probeInterval': '${settings.probeIntervalSeconds}s',
          'enableConcurrency': true,
        },
    };
  }

  Map<String, dynamic> _mainOutbound() => profile.toOutbound(
        core: coreType,
        tag: tagProxy,
        fragmentEnabled: settings.enableFragment,
        fragmentLength: settings.fragmentLength,
        fragmentInterval: settings.fragmentInterval,
      );

  /// Servers that take part in the "fastest server" balancer.
  List<Profile> _balancerCandidates() {
    final candidates = <Profile>[
      profile,
      ...profiles.where((p) => p.enabled && p.id != profile.id),
    ];
    // Keep the config small and the probing cheap.
    return candidates.take(32).toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // DNS
  // -------------------------------------------------------------------------

  Map<String, dynamic> _buildDns() {
    final servers = <Object>[];

    if (settings.bypassIran && settings.routingMode != RoutingMode.global) {
      // Iranian domains are resolved by an in-country resolver, which returns
      // the correct CDN/peering IPs. This traffic stays direct.
      servers.add(<String, dynamic>{
        'address': settings.dnsIran,
        'domains': <String>['geosite:category-ir'],
      });
    }

    // Everything else is resolved over DoH through the tunnel, so that the ISP
    // cannot see (or poison) the queries.
    servers.add(<String, dynamic>{
      'address': settings.dnsRemoteDoh,
      'skipFallback': true,
    });

    // Last resort: a plain resolver, useful when the DoH server is blocked.
    servers.add('1.1.1.1');

    return <String, dynamic>{
      'servers': servers,
      // Iran: IPv6 is almost always broken. Asking for it only costs time.
      'queryStrategy': settings.dnsUseIpv4Only ? 'UseIPv4' : 'UseIP',
      'disableCache': !settings.enableDnsCache,
    };
  }

  // -------------------------------------------------------------------------
  // Inbounds
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> _buildInbounds() {
    final listen = settings.allowLan ? '0.0.0.0' : '127.0.0.1';
    final sniffing = <String, dynamic>{
      'enabled': true,
      'destOverride': <String>['http', 'tls', 'quic'],
      // routeOnly keeps the original domain for routing decisions and avoids
      // sending plain IP traffic (which leaks metadata) to the proxy.
      'routeOnly': true,
    };

    return <Map<String, dynamic>>[
      <String, dynamic>{
        'tag': 'http-in',
        'listen': listen,
        'port': settings.httpPort,
        'protocol': 'http',
        'settings': <String, dynamic>{
          'allowTransparent': false,
          'timeout': 0,
        },
        'sniffing': sniffing,
      },
      <String, dynamic>{
        'tag': 'socks-in',
        'listen': listen,
        'port': settings.socksPort,
        'protocol': 'socks',
        'settings': <String, dynamic>{
          'auth': 'noauth',
          'udp': true,
        },
        'sniffing': sniffing,
      },
      <String, dynamic>{
        'tag': tagApiIn,
        'listen': '127.0.0.1',
        'port': settings.apiPort,
        'protocol': 'dokodemo-door',
        'settings': <String, dynamic>{
          'address': '127.0.0.1',
          'port': 0,
          'network': 'tcp',
        },
      },
    ];
  }

  // -------------------------------------------------------------------------
  // Routing
  // -------------------------------------------------------------------------

  Map<String, dynamic> _buildRouting(List<String> balancerTags) {
    final rules = <Map<String, dynamic>>[];

    // 1. API traffic must never leave the machine.
    rules.add(<String, dynamic>{
      'type': 'field',
      'inboundTag': <String>[tagApiIn],
      'outboundTag': tagApiOut,
    });

    // 2. Internal DNS queries handled by the core.
    if (_isXray) {
      rules.add(<String, dynamic>{
        'type': 'field',
        'protocol': <String>['dns'],
        'outboundTag': tagDnsOut,
      });
    }

    // 3. LAN / loopback / link-local is always direct.
    rules.add(<String, dynamic>{
      'type': 'field',
      'ip': <String>['geoip:private'],
      'outboundTag': tagDirect,
    });

    // 4. Ads (Iranian ad networks included).
    if (settings.blockAds) {
      rules.add(<String, dynamic>{
        'type': 'field',
        'domain': <String>['geosite:category-ads-all'],
        'outboundTag': tagBlock,
      });
    }

    // 5. User overrides.
    if (settings.customBypassDomains.isNotEmpty) {
      rules.add(<String, dynamic>{
        'type': 'field',
        'domain': settings.customBypassDomains.map(_toRule).toList(),
        'outboundTag': tagDirect,
      });
    }
    if (settings.customProxyDomains.isNotEmpty) {
      rules.add(<String, dynamic>{
        'type': 'field',
        'domain': settings.customProxyDomains.map(_toRule).toList(),
        'outboundTag': _proxyTarget(balancerTags),
      });
    }

    // 6. Mode specific rules.
    switch (settings.routingMode) {
      case RoutingMode.global:
        break;
      case RoutingMode.smartIran:
        rules.addAll(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'field',
            'domain': <String>['geosite:category-ir'],
            'outboundTag': tagDirect,
          },
          <String, dynamic>{
            'type': 'field',
            'ip': <String>['geoip:ir'],
            'outboundTag': tagDirect,
          },
        ]);
        break;
      case RoutingMode.custom:
        rules.addAll(_parseCustomRules());
        break;
    }

    // 7. QUIC is throttled to death on Iranian mobile/fixed lines; blocking it
    //    makes browsers fall back to TCP, which is usually much faster.
    if (settings.blockQuic) {
      rules.add(<String, dynamic>{
        'type': 'field',
        'network': 'udp',
        'port': '443',
        'outboundTag': tagBlock,
      });
    }

    // 8. Everything else goes through the proxy.
    rules.add(<String, dynamic>{
      'type': 'field',
      'network': 'tcp,udp',
      'outboundTag': _proxyTarget(balancerTags),
    });

    return <String, dynamic>{
      // IPIfNonMatch lets the geoip:* rules work for connections that arrive
      // as raw IP addresses.
      'domainStrategy': 'IPIfNonMatch',
      'domainMatcher': 'hybrid',
      'rules': rules,
      if (balancerTags.isNotEmpty)
        'balancers': <Map<String, dynamic>>[
          <String, dynamic>{
            'tag': tagBalancer,
            'selector': balancerTags,
            'fallbackTag': balancerTags.first,
            'strategy': <String, dynamic>{'type': 'leastPing'},
          },
        ],
    };
  }

  String _proxyTarget(List<String> balancerTags) =>
      balancerTags.isNotEmpty ? tagBalancer : tagProxy;

  static String _toRule(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('geosite:') ||
        trimmed.startsWith('regexp:') ||
        trimmed.startsWith('domain:') ||
        trimmed.startsWith('full:') ||
        trimmed.startsWith('keyword:') ||
        trimmed.startsWith('subdomain:')) {
      return trimmed;
    }
    // Bare entries are treated as domain: so that example.com matches
    // sub.example.com as well.
    return 'domain:$trimmed';
  }

  List<Map<String, dynamic>> _parseCustomRules() {
    final raw = settings.customRulesJson.trim();
    if (raw.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
    } on FormatException {
      // Invalid JSON: skip instead of breaking the whole configuration.
    }
    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _buildPolicy() => <String, dynamic>{
        'levels': <String, dynamic>{
          '0': <String, dynamic>{
            'statsUserUplink': true,
            'statsUserDownlink': true,
          },
        },
        'system': <String, dynamic>{
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      };
}
