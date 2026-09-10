/// Thin, exception-safe registry helper for HKCU (Windows only).
///
/// Uses `package:win32` advapi32 bindings (signatures verified against the
/// v5.5.0 tag). All functions throw [UnsupportedError] off-Windows and
/// [RegistryException] on Win32 failures so callers can map them to UI errors.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Predefined key (same value on every Windows release; not exported by
/// win32 5.x as a constant, so defined here).
const int hkeyCurrentUser = 0x80000001;

class RegistryException implements Exception {
  const RegistryException(this.message, {this.code = 0});

  final String message;
  final int code;

  @override
  String toString() => 'RegistryException($message, code=$code)';
}

abstract final class WindowsRegistry {
  static void _ensureWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows registry is only available on Windows');
    }
  }

  static int _open(String subKey, int access) {
    _ensureWindows();
    final subKeyNative = subKey.toNativeUtf16();
    final result = calloc<IntPtr>();
    try {
      final code = RegOpenKeyEx(
          hkeyCurrentUser, subKeyNative, 0, access, result,);
      if (code != ERROR_SUCCESS) {
        throw RegistryException('Cannot open HKCU\\$subKey', code: code);
      }
      return result.value;
    } finally {
      free(subKeyNative);
      calloc.free(result);
    }
  }

  static void _close(int hKey) {
    RegCloseKey(hKey);
  }

  static String? readString(String subKey, String valueName) {
    final hKey = _open(subKey, KEY_QUERY_VALUE);
    try {
      final nameNative = valueName.toNativeUtf16();
      final type = calloc<Uint32>();
      final size = calloc<Uint32>();
      try {
        var code = RegQueryValueEx(
            hKey, nameNative, nullptr, type, nullptr, size,);
        if (code != ERROR_SUCCESS || size.value == 0) return null;
        final data = calloc<Uint8>(size.value);
        try {
          code = RegQueryValueEx(
              hKey, nameNative, nullptr, type, data, size,);
          if (code != ERROR_SUCCESS) return null;
          return data.cast<Utf16>().toDartString();
        } finally {
          calloc.free(data);
        }
      } finally {
        free(nameNative);
        calloc.free(type);
        calloc.free(size);
      }
    } finally {
      _close(hKey);
    }
  }

  static int? readDword(String subKey, String valueName) {
    final hKey = _open(subKey, KEY_QUERY_VALUE);
    try {
      final nameNative = valueName.toNativeUtf16();
      final type = calloc<Uint32>();
      final data = calloc<Uint32>();
      final size = calloc<Uint32>()..value = sizeOf<Uint32>();
      try {
        final code = RegQueryValueEx(
            hKey, nameNative, nullptr, type, data.cast<Uint8>(), size,);
        if (code != ERROR_SUCCESS) return null;
        return data.value;
      } finally {
        free(nameNative);
        calloc.free(type);
        calloc.free(data);
        calloc.free(size);
      }
    } finally {
      _close(hKey);
    }
  }

  static void writeString(String subKey, String valueName, String value) {
    final hKey = _open(subKey, KEY_SET_VALUE);
    try {
      final nameNative = valueName.toNativeUtf16();
      final valueNative = value.toNativeUtf16();
      try {
        final bytes = (value.length + 1) * 2;
        final code = RegSetValueEx(hKey, nameNative, 0, REG_SZ,
            valueNative.cast<Uint8>(), bytes,);
        if (code != ERROR_SUCCESS) {
          throw RegistryException(
              'Cannot write HKCU\\$subKey\\$valueName', code: code,);
        }
      } finally {
        free(nameNative);
        free(valueNative);
      }
    } finally {
      _close(hKey);
    }
  }

  static void writeDword(String subKey, String valueName, int value) {
    final hKey = _open(subKey, KEY_SET_VALUE);
    try {
      final nameNative = valueName.toNativeUtf16();
      final data = calloc<Uint32>()..value = value;
      try {
        final code = RegSetValueEx(hKey, nameNative, 0, REG_DWORD,
            data.cast<Uint8>(), sizeOf<Uint32>(),);
        if (code != ERROR_SUCCESS) {
          throw RegistryException(
              'Cannot write HKCU\\$subKey\\$valueName', code: code,);
        }
      } finally {
        free(nameNative);
        calloc.free(data);
      }
    } finally {
      _close(hKey);
    }
  }

  static void deleteValue(String subKey, String valueName) {
    final hKey = _open(subKey, KEY_SET_VALUE);
    try {
      final nameNative = valueName.toNativeUtf16();
      try {
        RegDeleteValue(hKey, nameNative);
      } finally {
        free(nameNative);
      }
    } finally {
      _close(hKey);
    }
  }
}
