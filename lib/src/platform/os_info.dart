/// Operating-system detection (Windows version, capabilities).
///
/// Primary source: `RtlGetVersion` via our own FFI (unshimmed). Fallback:
/// parsing `Platform.operatingSystemVersion`. Capability flags drive every
/// OS-gated feature (legacy core selection, TUN availability).
library;

import 'dart:io';

import 'win32_bindings.dart';

class OsInfo {
  const OsInfo({
    required this.isWindows,
    required this.major,
    required this.minor,
    required this.build,
    required this.distro,
  },);

  final bool isWindows;
  final int major;
  final int minor;
  final int build;

  /// Raw version string from Dart (for Diagnostics display).
  final String distro;

  bool get isWindows10OrGreater => isWindows && major >= 10;
  bool get isWindows11OrGreater => isWindows && (major > 10 || (major == 10 && build >= 22000));
  bool get isWindows7 => isWindows && major == 6 && minor == 1;
  bool get isWindows8x =>
      isWindows && major == 6 && (minor == 2 || minor == 3);
  bool get isLegacyWindows => isWindows && !isWindows10OrGreater;

  /// TUN is only offered on Windows 10+ (driver + stack requirements).
  bool get supportsTun => isWindows10OrGreater;

  /// Which bundled core binary to launch.
  bool get useLegacyCore => isLegacyWindows;

  String get displayName {
    if (!isWindows) return distro;
    final edition = isWindows11OrGreater
        ? 'Windows 11'
        : isWindows10OrGreater
            ? 'Windows 10'
            : isWindows8x
                ? (minor == 3 ? 'Windows 8.1' : 'Windows 8')
                : isWindows7
                    ? 'Windows 7'
                    : 'Windows';
    final arch = Platform.version.contains('x64') || Platform.environment['PROCESSOR_ARCHITECTURE'] == 'AMD64'
        ? 'x64'
        : 'x86';
    return '$edition (build $build, $arch)';
  }

  static OsInfo? _cached;

  /// Cached process-wide (the OS does not change under us).
  static OsInfo current() {
    final cached = _cached;
    if (cached != null) return cached;
    final info = _detect();
    _cached = info;
    return info;
  }

  static OsInfo _detect() {
    const distro = '';
    if (!Platform.isWindows) {
      return OsInfo(
        isWindows: false,
        major: 0,
        minor: 0,
        build: 0,
        distro: Platform.operatingSystemVersion,
      );
    }
    final rtl = Ntdll.version();
    if (rtl != null) {
      return OsInfo(
        isWindows: true,
        major: rtl.$1,
        minor: rtl.$2,
        build: rtl.$3,
        distro: Platform.operatingSystemVersion,
      );
    }
    final parsed = parseDartVersionString(Platform.operatingSystemVersion);
    return OsInfo(
      isWindows: true,
      major: parsed?.$1 ?? 10,
      minor: parsed?.$2 ?? 0,
      build: parsed?.$3 ?? 0,
      distro: '$distro${Platform.operatingSystemVersion}',
    );
  }

  /// Parse Dart's `Platform.operatingSystemVersion`, e.g.
  /// `Windows 10.0.22621` / `Windows 11 Version 23H2 (Build 22631)`.
  /// Returns (major, minor, build); build may be 0 when absent.
  static (int, int, int)? parseDartVersionString(String input) {
    final numbers =
        RegExp(r'\d+').allMatches(input).map((m) => int.parse(m.group(0)!)).toList();
    if (numbers.isEmpty) return null;
    if (numbers.length == 1) return (numbers[0], 0, 0);
    if (numbers.length == 2) return (numbers[0], numbers[1], 0);
    return (numbers[0], numbers[1], numbers.last);
  }
}
