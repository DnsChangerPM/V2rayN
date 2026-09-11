/// Strict + lenient semantic-version parsing (pure Dart, no dependencies).
///
/// Release versions use [SemVersion.parseStrict] (mirrors
/// `scripts/validate_version.py`). The update checker uses [SemVersion.tryParse]
/// which tolerates a leading `v` and pre-release suffixes from upstream tags.
library;

class SemVersion implements Comparable<SemVersion> {
  const SemVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final RegExp _strict = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');
  static final RegExp _lenient =
      RegExp(r'^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$');

  /// Throws [FormatException] unless [input] is strict MAJOR.MINOR.PATCH.
  /// Strict means *exactly* the three dotted numbers — no leading `v`, no
  /// pre-release/build suffix, no leading or trailing whitespace.
  factory SemVersion.parseStrict(String input) {
    final match = _strict.firstMatch(input);
    if (match == null) {
      throw FormatException('Not strict SemVer MAJOR.MINOR.PATCH: $input');
    }
    return SemVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Parses upstream-style tags (`v1.2.3`, `1.2.3-rc.1`). Returns null when the
  /// core `X.Y.Z` cannot be extracted.
  static SemVersion? tryParse(String input) {
    final match = _lenient.firstMatch(input.trim());
    if (match == null) return null;
    return SemVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  bool get isPreReleaseCandidate => false;

  @override
  int compareTo(SemVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(SemVersion other) => compareTo(other) > 0;
  bool operator <(SemVersion other) => compareTo(other) < 0;
  bool operator >=(SemVersion other) => compareTo(other) >= 0;
  bool operator <=(SemVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is SemVersion && major == other.major && minor == other.minor && patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
