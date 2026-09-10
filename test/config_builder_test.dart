import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:radin/core/config/config_builder.dart';
import 'package:radin/core/model/enums.dart';
import 'package:radin/core/model/profile.dart';
import 'package:radin/core/model/settings.dart';

Profile sampleProfile() => Profile(
      remark: 'Sample',
      protocol: ProtocolType.vless,
      address: '1.2.3.4',
      port: 443,
      uuid: 'uuid',
      flow: 'xtls-rprx-vision',
      security: SecurityType.reality.id,
      sni: 'www.microsoft.com',
      fingerprint: 'chrome',
      realityPublicKey: 'pk',
    );

Map<String, dynamic> build({
  required AppSettings settings,
  Profile? profile,
  CoreType core = CoreType.xray,
}) =>
    CoreConfigBuilder(
      settings: settings,
      profile: profile ?? sampleProfile(),
      profiles: <Profile>[profile ?? sampleProfile()],
      coreType: core,
    ).build();

void main() {
  test('produces a valid top level structure', () {
    final config = build(settings: AppSettings());

    expect(config['log'], isA<Map>());
    expect(config['dns'], isA<Map>());
    expect(config['inbounds'], isA<List>());
    expect(config['outbounds'], isA<List>());
    expect(config['routing'], isA<Map>());
    expect(jsonEncode(config), isA<String>());
  });

  test('exposes http, socks and api inbounds on the configured ports', () {
    final settings = AppSettings(
      httpPort: 2080,
      socksPort: 2081,
      apiPort: 2085,
    );
    final inbounds = build(settings: settings)['inbounds'] as List;

    final byTag = <String, Map<String, dynamic>>{
      for (final inbound in inbounds)
        (inbound as Map)['tag'] as String: inbound as Map<String, dynamic>,
    };
    expect(byTag['http-in']!['port'], 2080);
    expect(byTag['socks-in']!['port'], 2081);
    expect(byTag['api-in']!['port'], 2085);
    expect(byTag['http-in']!['listen'], '127.0.0.1');
  });

  test('uses IPv4 only DNS by default (Iran)', () {
    final dns = build(settings: AppSettings())['dns'] as Map;
    expect(dns['queryStrategy'], 'UseIPv4');
    expect((dns['servers'] as List).first, isA<Map>());
  });

  test('routes Iranian domains and IPs direct in smart mode', () {
    final settings = AppSettings(routingMode: RoutingMode.smartIran);
    final rules = (build(settings: settings)['routing'] as Map)['rules'] as List;

    final domains = rules.where((rule) {
      final map = rule as Map;
      final list = map['domain'] as List?;
      return list != null && list.contains('geosite:category-ir');
    });
    final ips = rules.where((rule) {
      final map = rule as Map;
      final list = map['ip'] as List?;
      return list != null && list.contains('geoip:ir');
    });

    expect(domains, isNotEmpty);
    expect(ips, isNotEmpty);
  });

  test('blocks QUIC by default', () {
    final rules = (build(settings: AppSettings())['routing'] as Map)['rules'] as List;
    final quic = rules.where((rule) {
      final map = rule as Map;
      return map['port'] == '443' && map['network'] == 'udp';
    });
    expect(quic, isNotEmpty);
  });

  test('adds the finalmask fragment block for Xray only', () {
    final settings = AppSettings(
      enableFragment: true,
      fragmentLength: '10-20',
      fragmentInterval: '5-10',
    );
    final profile = sampleProfile()..fragment = FragmentPreset.tlsHello;

    final xray = build(settings: settings, profile: profile, core: CoreType.xray);
    final xrayOutbound = (xray['outbounds'] as List).first as Map;
    final stream = xrayOutbound['streamSettings'] as Map;
    expect(stream.containsKey('finalmask'), isTrue);
    final mask = (stream['finalmask'] as Map)['tcp'] as List;
    expect((mask.first as Map)['type'], 'fragment');

    final v2ray =
        build(settings: settings, profile: profile, core: CoreType.v2ray);
    final v2rayOutbound = (v2ray['outbounds'] as List).first as Map;
    expect(
      (v2rayOutbound['streamSettings'] as Map).containsKey('finalmask'),
      isFalse,
    );
  });

  test('degrades REALITY to TLS on v2ray', () {
    final config = build(settings: AppSettings(), core: CoreType.v2ray);
    final outbound = (config['outbounds'] as List).first as Map;
    final stream = outbound['streamSettings'] as Map;

    expect(stream['security'], 'tls');
    expect(stream.containsKey('realitySettings'), isFalse);
    expect(stream.containsKey('tlsSettings'), isTrue);
  });

  test('keeps REALITY on Xray', () {
    final config = build(settings: AppSettings(), core: CoreType.xray);
    final outbound = (config['outbounds'] as List).first as Map;
    final stream = outbound['streamSettings'] as Map;

    expect(stream['security'], 'reality');
    expect((stream['realitySettings'] as Map)['publicKey'], 'pk');
  });

  test('creates a leastPing balancer when auto select is enabled', () {
    final settings = AppSettings(autoSelectFastest: true);
    final config = build(settings: settings);
    final routing = config['routing'] as Map;

    expect(config.containsKey('observatory'), isTrue);
    final balancers = routing['balancers'] as List;
    expect(balancers, isNotEmpty);
    expect((balancers.first as Map)['strategy'], {'type': 'leastPing'});
  });

  test('custom routing rules are appended', () {
    final settings = AppSettings(
      routingMode: RoutingMode.custom,
      customRulesJson:
          '[{"type":"field","domain":["domain:example.com"],"outboundTag":"direct"}]',
    );
    final rules = (build(settings: settings)['routing'] as Map)['rules'] as List;
    final custom = rules.where((rule) {
      final list = (rule as Map)['domain'] as List?;
      return list != null && list.contains('domain:example.com');
    });
    expect(custom, isNotEmpty);
  });

  test('bare custom domains become domain: rules', () {
    final settings = AppSettings(customBypassDomains: <String>['example.com']);
    final rules = (build(settings: settings)['routing'] as Map)['rules'] as List;
    final match = rules.where((rule) {
      final list = (rule as Map)['domain'] as List?;
      return list != null && list.contains('domain:example.com');
    });
    expect(match, isNotEmpty);
  });
}
