/// Compile time constants injected by the release workflow:
///
/// ```sh
/// flutter build windows --dart-define=APP_VERSION=1.2.3 --dart-define=APP_BUILD=7
/// ```
class AppVersion {
  const AppVersion._();

  static const String name = 'Radin';
  static const String version =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0-dev');
  static const String build =
      String.fromEnvironment('APP_BUILD', defaultValue: '0');
  static const String gitSha =
      String.fromEnvironment('GIT_SHA', defaultValue: '');
  static const String repository = 'https://github.com/DnsChangerPM/V2rayN';

  static String get display =>
      build == '0' ? version : '$version (build $build)';

  /// Numeric version used for update checks, `0` when unparsable.
  static List<int> get numeric => version
      .split(RegExp(r'[.+-]'))
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);

  /// Compares two semantic versions. Returns > 0 when [a] is newer.
  static int compare(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    for (var i = 0; i < 3; i++) {
      final diff = left[i] - right[i];
      if (diff != 0) {
        return diff;
      }
    }
    return 0;
  }

  static List<int> _parts(String version) {
    final parts = version
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[.+-]'))
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}
