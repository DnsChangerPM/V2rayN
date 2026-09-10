import 'package:flutter_test/flutter_test.dart';
import 'package:radin/core/utils/app_version.dart';

void main() {
  group('AppVersion.compare', () {
    test('detects newer patch versions', () {
      expect(AppVersion.compare('1.2.4', '1.2.3'), greaterThan(0));
      expect(AppVersion.compare('1.2.3', '1.2.4'), lessThan(0));
      expect(AppVersion.compare('1.2.3', '1.2.3'), 0);
    });

    test('detects newer minor and major versions', () {
      expect(AppVersion.compare('1.3.0', '1.2.9'), greaterThan(0));
      expect(AppVersion.compare('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('tolerates a leading v and pre-release suffixes', () {
      expect(AppVersion.compare('v1.2.3', '1.2.3'), 0);
      expect(AppVersion.compare('1.2.3-beta.1', '1.2.3'), 0);
    });

    test('pads short versions', () {
      expect(AppVersion.compare('1.2', '1.2.0'), 0);
      expect(AppVersion.compare('1', '1.0.0'), 0);
    });
  });

  test('numeric splits the version into parts', () {
    expect(AppVersion.numeric.length, greaterThanOrEqualTo(3));
  });
}
