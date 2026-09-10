/// Minimal hand-written Windows FFI bindings (IranLink-owned).
///
/// Why not `package:win32` for these?
/// - `wininet.InternetSetOption` (system-proxy refresh) is not covered by
///   win32 5.x at all (verified against the v5.5.0 tag).
/// - `ntdll.RtlGetVersion` (unshimmed OS version) is not covered either.
///
/// Both APIs exist since Windows 2000, so the legacy (Win7 SP1) path is
/// identical to the modern one. Every entry point is resolved lazily and
/// every call is guarded by [Platform.isWindows] + try/catch, so importing
/// this file on other platforms (CI analyze, unit tests) is safe.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// wininet: InternetSetOption (proxy refresh broadcast)
// ---------------------------------------------------------------------------

typedef _InternetSetOptionNative = Int32 Function(
    Pointer<Void> hInternet, Uint32 dwOption, Pointer<Void> lpBuffer, Uint32 dwBufferLength);
typedef _InternetSetOptionDart = int Function(
    Pointer<Void> hInternet, int dwOption, Pointer<Void> lpBuffer, int dwBufferLength);

abstract final class Wininet {
  static const int internetOptionSettingsChanged = 39;
  static const int internetOptionRefresh = 37;

  static DynamicLibrary? _lib;
  static int Function(Pointer<Void>, int, Pointer<Void>, int)? _setOption;

  /// Broadcast a proxy-settings change. Returns false on any failure
  /// (never throws — callers fall back to registry-only behavior).
  static bool refreshProxySettings() {
    if (!Platform.isWindows) return false;
    try {
      _lib ??= DynamicLibrary.open('wininet.dll');
      _setOption ??= _lib!.lookupFunction<_InternetSetOptionNative, _InternetSetOptionDart>(
        'InternetSetOption',
      );
      final changed =
          _setOption!(nullptr, internetOptionSettingsChanged, nullptr, 0);
      final refreshed =
          _setOption!(nullptr, internetOptionRefresh, nullptr, 0);
      return changed != 0 && refreshed != 0;
    } on Object {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// ntdll: RtlGetVersion (real OS version, unaffected by app-compat shims)
// ---------------------------------------------------------------------------

final class _OsVersionInfo extends Struct {
  @Uint32()
  external int dwOSVersionInfoSize;
  @Uint32()
  external int dwMajorVersion;
  @Uint32()
  external int dwMinorVersion;
  @Uint32()
  external int dwBuildNumber;
  @Uint32()
  external int dwPlatformId;
  @Array<Uint16>(128)
  external Array<Uint16> szCSDVersion;
}

typedef _RtlGetVersionNative = Int32 Function(Pointer<_OsVersionInfo> info);
typedef _RtlGetVersionDart = int Function(Pointer<_OsVersionInfo> info);

abstract final class Ntdll {
  /// Returns (major, minor, build) or null when unavailable.
  static (int, int, int)? version() {
    if (!Platform.isWindows) return null;
    try {
      final lib = DynamicLibrary.open('ntdll.dll');
      final getVersion = lib.lookupFunction<_RtlGetVersionNative, _RtlGetVersionDart>(
        'RtlGetVersion',
      );
      final info = calloc<_OsVersionInfo>();
      try {
        info.ref.dwOSVersionInfoSize = sizeOf<_OsVersionInfo>();
        final status = getVersion(info);
        if (status != 0) return null;
        return (
          info.ref.dwMajorVersion,
          info.ref.dwMinorVersion,
          info.ref.dwBuildNumber,
        );
      } finally {
        calloc.free(info);
      }
    } on Object {
      return null;
    }
  }
}
