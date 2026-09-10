import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/subscriptions/subscription_parser.dart';

const _uuid = '123e4567-e89b-12d3-a456-426614174000';
const _vless = 'vless://$_uuid@example.com:443?security=tls#Node1';
const _ss = 'ss://YWVzLTI1Ni1nY206cHcxMjM@example.com:8388#Node2';

void main() {
  test('plain lines', () {
    final parsed = parseSubscriptionContent('$_vless\n$_ss\n',
        subscriptionId: 'sub1',);
    expect(parsed.profiles.map((p) => p.name), ['Node1', 'Node2']);
    expect(parsed.errors, isEmpty);
    expect(parsed.profiles.first.subscriptionId, 'sub1');
  });

  test('base64 blob', () {
    final blob = base64Encode(utf8.encode('$_vless\n$_ss\n'));
    final parsed =
        parseSubscriptionContent(blob, subscriptionId: 'sub1');
    expect(parsed.profiles.length, 2);
  });

  test('json array of links', () {
    final parsed = parseSubscriptionContent(jsonEncode([_vless, _ss]),
        subscriptionId: 'sub1',);
    expect(parsed.profiles.length, 2);
  });

  test('json array of vmess objects', () {
    final vmess = base64Encode(utf8.encode(jsonEncode({
      'ps': 'V',
      'add': 'h.example',
      'port': '1',
      'id': _uuid,
    }),),);
    final parsed = parseSubscriptionContent(jsonEncode(['vmess://$vmess']),
        subscriptionId: 'sub1',);
    expect(parsed.profiles.single.address, 'h.example');
  });

  test('bad lines become errors, not crashes', () {
    final parsed = parseSubscriptionContent('$_vless\nnot-a-link\n$_ss\n',
        subscriptionId: 'sub1',);
    expect(parsed.profiles.length, 2);
    expect(parsed.errors.length, 1);
    expect(parsed.errors.single.line, 2);
  });

  test('comments and blanks skipped', () {
    final parsed = parseSubscriptionContent('# c\n\n$_vless\n',
        subscriptionId: 'sub1',);
    expect(parsed.profiles.length, 1);
    expect(parsed.errors, isEmpty);
  });

  test('oversize content throws', () {
    expect(
        () => parseSubscriptionContent('x' * (6 * 1024 * 1024),
            subscriptionId: 's',),
        throwsA(isA<SubscriptionTooLargeException>()),);
  });

  test('empty content parses to empty', () {
    final parsed =
        parseSubscriptionContent('  \n ', subscriptionId: 's');
    expect(parsed.profiles, isEmpty);
    expect(parsed.errors, isEmpty);
  });
}
