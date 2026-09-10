import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:radin/core/model/enums.dart';
import 'package:radin/core/net/link_parser.dart';

void main() {
  group('vless', () {
    test('parses a REALITY link', () {
      final profile = LinkParser.parse(
        'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443'
        '?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp'
        '&sni=www.microsoft.com&fp=chrome&pbk=PUBKEY&sid=abcdef12&spx=%2F'
        '#My%20Server',
      );

      expect(profile, isNotNull);
      expect(profile!.protocol, ProtocolType.vless);
      expect(profile.remark, 'My Server');
      expect(profile.address, '1.2.3.4');
      expect(profile.port, 443);
      expect(profile.uuid, '11111111-2222-3333-4444-555555555555');
      expect(profile.flow, 'xtls-rprx-vision');
      expect(profile.securityType, SecurityType.reality);
      expect(profile.sni, 'www.microsoft.com');
      expect(profile.fingerprint, 'chrome');
      expect(profile.realityPublicKey, 'PUBKEY');
      expect(profile.realityShortId, 'abcdef12');
    });

    test('round trips a generated link', () {
      final profile = LinkParser.parse(
        'vless://uuid-uuid@host.example:8443?encryption=none&security=tls'
        '&type=ws&path=%2Fws&host=host.example&sni=host.example#WS',
      )!;
      final link = profile.toShareLink();
      final again = LinkParser.parse(link)!;
      expect(again.address, 'host.example');
      expect(again.port, 8443);
      expect(again.network, TransportType.ws);
      expect(again.path, '/ws');
      expect(again.securityType, SecurityType.tls);
    });
  });

  group('vmess', () {
    test('parses a base64 json link', () {
      final json = jsonEncode(<String, dynamic>{
        'v': '2',
        'ps': 'VMess node',
        'add': '5.6.7.8',
        'port': '80',
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'aid': '0',
        'net': 'ws',
        'path': '/path',
        'host': 'example.com',
        'tls': 'tls',
      });
      final profile = LinkParser.parse('vmess://${base64Encode(utf8.encode(json))}');

      expect(profile, isNotNull);
      expect(profile!.protocol, ProtocolType.vmess);
      expect(profile.remark, 'VMess node');
      expect(profile.address, '5.6.7.8');
      expect(profile.port, 80);
      expect(profile.network, TransportType.ws);
      expect(profile.securityType, SecurityType.tls);
    });
  });

  group('trojan', () {
    test('parses a trojan link', () {
      final profile = LinkParser.parse(
        'trojan://secret@trojan.example:443?security=tls&type=ws&path=%2Ftrojan'
        '&sni=example.org#Trojan',
      );

      expect(profile, isNotNull);
      expect(profile!.protocol, ProtocolType.trojan);
      expect(profile.password, 'secret');
      expect(profile.port, 443);
      expect(profile.network, TransportType.ws);
      expect(profile.path, '/trojan');
      expect(profile.sni, 'example.org');
    });
  });

  group('shadowsocks', () {
    test('parses SIP002', () {
      final userinfo =
          base64Encode(utf8.encode('aes-256-gcm:pass')).replaceAll('=', '');
      final profile =
          LinkParser.parse('ss://$userinfo@9.9.9.9:8388#Shadowsocks');

      expect(profile, isNotNull);
      expect(profile!.protocol, ProtocolType.shadowsocks);
      expect(profile.security, 'aes-256-gcm');
      expect(profile.password, 'pass');
      expect(profile.address, '9.9.9.9');
      expect(profile.port, 8388);
    });

    test('parses the legacy form', () {
      final body = base64Encode(utf8.encode('chacha20-ietf-poly1305:secret@8.8.4.4:1234'))
          .replaceAll('=', '');
      final profile = LinkParser.parse('ss://$body#Legacy');

      expect(profile, isNotNull);
      expect(profile!.security, 'chacha20-ietf-poly1305');
      expect(profile.password, 'secret');
      expect(profile.address, '8.8.4.4');
      expect(profile.port, 1234);
    });
  });

  group('subscription', () {
    test('decodes a base64 blob with one link per line', () {
      final links = <String>[
        'vless://u1@a.example:443?security=tls#one',
        'trojan://p@b.example:443#two',
      ].join('\n');
      final payload = base64Encode(utf8.encode(links));

      final profiles = LinkParser.parseSubscription(payload);
      expect(profiles.length, 2);
      expect(profiles.first.remark, 'one');
      expect(profiles.last.remark, 'two');
    });

    test('accepts plain text as well', () {
      final profiles = LinkParser.parseSubscription(
        'vless://u@a.example:443?security=tls#x\n\ntrojan://p@b.example:443#y',
      );
      expect(profiles.length, 2);
    });

    test('ignores garbage', () {
      final profiles = LinkParser.parseSubscription('hello world\n\nnot a link');
      expect(profiles, isEmpty);
    });
  });
}
