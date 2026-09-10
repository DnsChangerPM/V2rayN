import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/core/xray_config_builder.dart';
import 'package:iranlink/src/core/xray_config_validator.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/models/settings.dart';

const _builder = XrayConfigBuilder();
const _validator = XrayConfigValidator();
const _uuid = '123e4567-e89b-12d3-a456-426614174000';

const ProxyProfile _vless = ProxyProfile(
  id: 'p1',
  name: 'node',
  protocol: ProxyProtocol.vless,
  address: 'example.com',
  port: 443,
  secret: _uuid,
  tls: TlsMode.tls,
  sni: 'example.com',
);

void main() {
  group('builder', () {
    test('vless produces valid config', () {
      final config =
          _builder.build(profile: _vless, settings: const AppSettings());
      expect(_validator.validate(config).isValid, isTrue);
      final outbounds = config['outbounds'] as List<dynamic>;
      expect(outbounds.first['protocol'], 'vless');
      expect(
          (outbounds.first['settings']['vnext'] as List<dynamic>)
              .first['address'],
          'example.com');
    });

    test('all protocols build', () {
      const profiles = [
        ProxyProfile(
            id: 'a',
            name: 'a',
            protocol: ProxyProtocol.vmess,
            address: 'h',
            port: 1,
            secret: _uuid),
        ProxyProfile(
            id: 'b',
            name: 'b',
            protocol: ProxyProtocol.trojan,
            address: 'h',
            port: 1,
            secret: 'pw'),
        ProxyProfile(
            id: 'c',
            name: 'c',
            protocol: ProxyProtocol.shadowsocks,
            address: 'h',
            port: 1,
            secret: 'pw',
            method: 'aes-256-gcm'),
        ProxyProfile(
            id: 'd',
            name: 'd',
            protocol: ProxyProtocol.socks,
            address: 'h',
            port: 1),
        ProxyProfile(
            id: 'e',
            name: 'e',
            protocol: ProxyProtocol.http,
            address: 'h',
            port: 1),
      ];
      for (final profile in profiles) {
        final config = _builder.build(
            profile: profile, settings: const AppSettings());
        expect(_validator.validate(config).isValid, isTrue,
            reason: profile.protocol.name);
      }
    });

    test('rawJson merges managed inbounds', () {
      const raw = ProxyProfile(
        id: 'r',
        name: 'raw',
        protocol: ProxyProtocol.xrayJson,
        rawJson: '{"outbounds":[{"protocol":"freedom","tag":"direct"}]}',
      );
      final config =
          _builder.build(profile: raw, settings: const AppSettings());
      final tags = [
        for (final b in (config['inbounds'] as List<dynamic>)) b['tag'] as String
      ];
      expect(tags, containsAll(['socks-in', 'http-in', 'api']));
    });

    test('direct mode adds catch-all direct rule', () {
      final config = _builder.build(
        profile: _vless,
        settings: const AppSettings(
            routing: RoutingSettings(mode: RoutingMode.direct)),
      );
      final rules =
          (config['routing'] as Map<String, dynamic>)['rules']
              as List<dynamic>;
      expect(rules.any((r) => r['outboundTag'] == 'direct'), isTrue);
    });

    test('custom inbound ports propagate', () {
      final config = _builder.build(
        profile: _vless,
        settings: const AppSettings(
            inbounds: InboundSettings(socksPort: 11111, httpPort: 22222)),
      );
      final inbounds = config['inbounds'] as List<dynamic>;
      expect(
          inbounds.firstWhere((b) => b['tag'] == 'socks-in')['port'],
          11111);
      expect(
          inbounds.firstWhere((b) => b['tag'] == 'http-in')['port'],
          22222);
    });
  });

  group('validator', () {
    test('rejects missing outbounds', () {
      final result = _validator.validate({
        'inbounds': [
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808}
        ],
        'outbounds': <dynamic>[],
      });
      expect(result.isValid, isFalse);
      expect(result.issues.map((i) => i.messageKey),
          contains('configErrorNoOutbounds'));
    });

    test('rejects bad ports and dup tags', () {
      final result = _validator.validate({
        'inbounds': [
          {'tag': 'x', 'protocol': 'socks', 'port': 99999},
          {'tag': 'x', 'protocol': 'http', 'port': 10809},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless', 'settings': <String, dynamic>{}}
        ],
      });
      expect(result.isValid, isFalse);
      final keys = result.issues.map((i) => i.messageKey).toSet();
      expect(keys, contains('configErrorBadPort'));
      expect(keys, contains('configErrorDuplicateTag'));
    });

    test('minimal complete config is valid', () {
      final result = _validator.validate({
        'inbounds': [
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808}
        ],
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'example.com',
                  'port': 443,
                  'users': [
                    {'id': _uuid, 'encryption': 'none'}
                  ],
                }
              ],
            },
          }
        ],
      });
      expect(result.issues, isEmpty);
      expect(result.isValid, isTrue);
    });

    test('empty vnext is rejected', () {
      final result = _validator.validate({
        'inbounds': [
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808}
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless', 'settings': <String, dynamic>{}}
        ],
      });
      expect(result.isValid, isFalse);
      expect(result.issues.map((i) => i.messageKey),
          contains('configErrorEmptySettings'));
    });
  });
}
