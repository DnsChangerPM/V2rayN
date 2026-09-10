import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/utils/semver.dart';

void main() {
  group('SemVersion.parseStrict', () {
    test('accepts strict versions', () {
      expect(SemVersion.parseStrict('0.0.0').toString(), '0.0.0');
      expect(SemVersion.parseStrict('1.4.2').toString(), '1.4.2');
      expect(SemVersion.parseStrict('10.20.30').toString(), '10.20.30');
    });

    test('rejects non-strict versions', () {
      for (final bad in [
        '',
        '1',
        '1.0',
        'v1.0.0',
        '01.2.3',
        '1.2.3-beta',
        '1.2.3+1',
        'abc',
        '1.2.3.4',
        ' 1.2.3',
      ]) {
        expect(() => SemVersion.parseStrict(bad), throwsFormatException,
            reason: bad);
      }
    });
  });

  group('SemVersion.tryParse', () {
    test('tolerates upstream tags', () {
      expect(SemVersion.tryParse('v26.3.27').toString(), '26.3.27');
      expect(SemVersion.tryParse('1.2.3-rc.1').toString(), '1.2.3');
      expect(SemVersion.tryParse('nonsense'), isNull);
    });
  });

  test('comparison', () {
    expect(
        const SemVersion(1, 4, 2) < const SemVersion(1, 4, 3), isTrue);
    expect(
        const SemVersion(2, 0, 0) > const SemVersion(1, 99, 99), isTrue);
    expect(const SemVersion(1, 2, 3) == const SemVersion(1, 2, 3), isTrue);
  });
}
