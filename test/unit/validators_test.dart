import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/utils/validators.dart';

void main() {
  test('ports', () {
    expect(isValidPort(1), isTrue);
    expect(isValidPort(10808), isTrue);
    expect(isValidPort(65535), isTrue);
    expect(isValidPort(0), isFalse);
    expect(isValidPort(65536), isFalse);
    expect(isValidPort(-1), isFalse);
  });

  test('uuids', () {
    expect(isValidUuid('123e4567-e89b-12d3-a456-426614174000'), isTrue);
    expect(isValidUuid('123E4567-E89B-12D3-A456-426614174000'), isTrue);
    expect(isValidUuid('not-a-uuid'), isFalse);
    expect(isValidUuid(''), isFalse);
  });

  test('hosts', () {
    expect(isValidHost('example.com'), isTrue);
    expect(isValidHost('sub.domain-example.ir'), isTrue);
    expect(isValidHost('8.8.8.8'), isTrue);
    expect(isValidHost('::1'), isTrue);
    expect(isValidHost('[2001:db8::1]'), isTrue);
    expect(isValidHost('256.1.1.1'), isFalse);
    expect(isValidHost('bad..host'), isFalse);
    expect(isValidHost(''), isFalse);
  });

  test('urls', () {
    expect(isValidUrl('https://example.com/sub?token=abc'), isTrue);
    expect(isValidUrl('http://127.0.0.1:8080/x'), isTrue);
    expect(isValidUrl('ftp://example.com'), isFalse);
    expect(isValidUrl('not a url'), isFalse);
  });

  test('maskUrl hides secrets', () {
    expect(maskUrl('https://example.com/sub?token=secret123'),
        'https://example.com/•••',);
    expect(maskUrl('https://user:pass@example.com/'), 'https://user@example.com/•••');
    expect(maskUrl('https://example.com'), 'https://example.com');
    expect(maskUrl('garbage'), '<invalid-url>');
  });
}
