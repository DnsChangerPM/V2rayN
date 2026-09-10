import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/utils/formatters.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });

  test('formatSpeed', () {
    expect(formatSpeed(1536), '1.5 KB/s');
  });

  test('formatUptime', () {
    expect(formatUptime(0), '0:00');
    expect(formatUptime(90), '1:30');
    expect(formatUptime(3661), '1:01:01');
  });

  test('formatLatency', () {
    expect(formatLatency(null), '–');
    expect(formatLatency(-1), '–');
    expect(formatLatency(42), '42 ms');
  });

  test('maskMiddle', () {
    expect(maskMiddle('abcdef123456'), 'ab•••56');
    expect(maskMiddle('short'), '•••');
  });
}
