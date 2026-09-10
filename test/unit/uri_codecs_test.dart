import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/profiles/uri_codecs.dart';

const _uuid = '123e4567-e89b-12d3-a456-426614174000';
var _counter = 0;
String _newId() => 'id-${_counter++}';

void main() {
  group('normalizeBase64', () {
    test('url-safe + padding', () {
      expect(normalizeBase64('ab'), 'ab==');
      expect(normalizeBase64('abc'), 'abc=');
      expect(normalizeBase64('abcd'), 'abcd');
      expect(normalizeBase64('a-b_c'), 'a+b/c=');
    });

    test('invalid length throws', () {
      expect(() => normalizeBase64('abcde'), throwsFormatException);
    });
  });

  group('vmess', () {
    test('parses standard link', () {
      final json = jsonEncode({
        'v': '2',
        'ps': 'my server',
        'add': 'example.com',
        'port': '443',
        'id': _uuid,
        'aid': '0',
        'scy': 'auto',
        'net': 'ws',
        'type': 'none',
        'host': 'example.com',
        'path': '/ws',
        'tls': 'tls',
        'sni': 'example.com',
        'alpn': 'h2,http/1.1',
        'fp': 'chrome',
      });
      final profile = parseShareLink(
          'vmess://${base64Encode(utf8.encode(json))}',
          newId: _newId,)!;
      expect(profile.protocol, ProxyProtocol.vmess);
      expect(profile.name, 'my server');
      expect(profile.address, 'example.com');
      expect(profile.port, 443);
      expect(profile.secret, _uuid);
      expect(profile.transport, TransportType.ws);
      expect(profile.tls, TlsMode.tls);
      expect(profile.path, '/ws');
      expect(profile.alpn, ['h2', 'http/1.1']);
    });

    test('rejects bad uuid', () {
      final json =
          jsonEncode({'add': 'h', 'port': '1', 'id': 'nope', 'ps': 'x'});
      expect(
          parseShareLink('vmess://${base64Encode(utf8.encode(json))}',
              newId: _newId,),
          isNull,);
    });
  });

  group('vless', () {
    test('parses reality link', () {
      final profile = parseShareLink(
        'vless://$_uuid@example.com:443?'
        'encryption=none&security=reality&sni=example.com&fp=chrome&'
        'pbk=PUBLICKEY&sid=short&spx=%2F&flow=xtls-rprx-vision&'
        'type=tcp#Test%20Node',
        newId: _newId,
      )!;
      expect(profile.protocol, ProxyProtocol.vless);
      expect(profile.name, 'Test Node');
      expect(profile.tls, TlsMode.reality);
      expect(profile.publicKey, 'PUBLICKEY');
      expect(profile.shortId, 'short');
      expect(profile.flow, 'xtls-rprx-vision');
      expect(profile.transport, TransportType.tcp);
    });

    test('defaults port 443', () {
      final profile =
          parseShareLink('vless://$_uuid@example.com', newId: _newId)!;
      expect(profile.port, 443);
    });

    test('rejects bad uuid', () {
      expect(parseShareLink('vless://nope@example.com:443', newId: _newId),
          isNull,);
    });
  });

  group('trojan', () {
    test('parses link', () {
      final profile = parseShareLink(
        'trojan://p%40ss@example.com:443?sni=example.com&type=ws&path=%2Fws#T',
        newId: _newId,
      )!;
      expect(profile.protocol, ProxyProtocol.trojan);
      expect(profile.secret, 'p@ss');
      expect(profile.transport, TransportType.ws);
      expect(profile.path, '/ws');
      expect(profile.tls, TlsMode.tls);
    });

    test('rejects missing password', () {
      expect(parseShareLink('trojan://@example.com:443', newId: _newId),
          isNull,);
    });
  });

  group('shadowsocks', () {
    test('parses userinfo form', () {
      final userInfo =
          base64Encode(utf8.encode('aes-256-gcm:secretpw'));
      final profile = parseShareLink(
          'ss://$userInfo@example.com:8388#SS%20Node',
          newId: _newId,)!;
      expect(profile.protocol, ProxyProtocol.shadowsocks);
      expect(profile.method, 'aes-256-gcm');
      expect(profile.secret, 'secretpw');
      expect(profile.name, 'SS Node');
    });

    test('parses whole-blob form', () {
      final blob = base64Encode(
          utf8.encode('chacha20-ietf-poly1305:pw@example.com:8388'),);
      final profile =
          parseShareLink('ss://$blob', newId: _newId)!;
      expect(profile.method, 'chacha20-ietf-poly1305');
      expect(profile.address, 'example.com');
      expect(profile.port, 8388);
    });
  });

  group('socks/http', () {
    test('parses socks with auth', () {
      final profile = parseShareLink(
          'socks5://user:pass@127.0.0.1:1080#Local',
          newId: _newId,)!;
      expect(profile.protocol, ProxyProtocol.socks);
      expect(profile.username, 'user');
      expect(profile.secret, 'pass');
      expect(profile.port, 1080);
    });

    test('parses http proxy', () {
      final profile = parseShareLink(
          'http://127.0.0.1:8080', newId: _newId,)!;
      expect(profile.protocol, ProxyProtocol.http);
      expect(profile.port, 8080);
    });
  });

  test('unknown scheme returns null', () {
    expect(parseShareLink('wireguard://abc', newId: _newId), isNull);
    expect(parseShareLink('not a link', newId: _newId), isNull);
  });

  group('encode roundtrip', () {
    test('vless', () {
      final original = parseShareLink(
          'vless://$_uuid@example.com:443?security=tls&sni=example.com#N',
          newId: _newId,)!;
      final again =
          parseShareLink(encodeShareLink(original), newId: _newId)!;
      expect(again.protocol, original.protocol);
      expect(again.address, original.address);
      expect(again.port, original.port);
      expect(again.secret, original.secret);
      expect(again.tls, original.tls);
      expect(again.sni, original.sni);
    });

    test('shadowsocks', () {
      const link = 'ss://YWVzLTI1Ni1nY206cHcxMjM@example.com:8388#N';
      final original = parseShareLink(link, newId: _newId)!;
      final again =
          parseShareLink(encodeShareLink(original), newId: _newId)!;
      expect(again.method, 'aes-256-gcm');
      expect(again.secret, 'pw123');
      expect(again.port, 8388);
    });
  });
}
