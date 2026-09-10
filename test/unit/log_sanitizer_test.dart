import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/logging/log_sanitizer.dart';

void main() {
  group('LogSanitizer', () {
    test('redacts UUIDs', () {
      const uuid = '123e4567-e89b-12d3-a456-426614174000';
      final out = LogSanitizer.sanitize('user id=$uuid connected');
      expect(out, isNot(contains(uuid)));
      expect(out, contains('<redacted-uuid>'));
    });

    test('redacts secret assignments', () {
      final out = LogSanitizer.sanitize(
          '{"password": "hunter2", "token": "abc123", "port": 10808}');
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('abc123')));
      expect(out, contains('10808')); // non-secrets survive
    });

    test('redacts URI passwords and queries', () {
      final out = LogSanitizer.sanitize(
          'fetch https://user:s3cret@example.com/sub?token=abc#frag done');
      expect(out, isNot(contains('s3cret')));
      expect(out, isNot(contains('token=abc')));
      expect(out, contains('https://user:<redacted>@example.com/sub?<redacted>'));
    });

    test('redacts proxy share links', () {
      const link =
          'vless://123e4567-e89b-12d3-a456-426614174000@host:443?security=tls#name';
      final out = LogSanitizer.sanitize('import $link');
      expect(out, isNot(contains('123e4567')));
      expect(out, contains('vless://'));
    });

    test('redacts long base64 blobs', () {
      final blob = 'A' * 200;
      final out = LogSanitizer.sanitize('body: $blob');
      expect(out, contains('<redacted-bulk:200chars>'));
    });

    test('keeps ordinary technical lines', () {
      const line = 'Core exited (code=1) on 127.0.0.1:10808';
      expect(LogSanitizer.sanitize(line), line);
    });

    test('multiline truncation', () {
      final out = LogSanitizer.sanitizeMultiline('short\n${'word ' * 600}',
          maxLineLength: 100);
      expect(out.split('\n').length, 2);
      expect(out, contains('<truncated>'));
    });
  });
}
