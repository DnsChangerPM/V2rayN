/// Minimal Windows process helpers (tasklist/taskkill wrappers).
///
/// Used for orphan-core cleanup and Diagnostics. Non-Windows calls return
/// safe defaults (false/null) instead of throwing.
library;

import 'dart:io';

abstract final class WindowsProcessUtils {
  /// True when [pid] is alive and its image name matches [imageName]
  /// (case-insensitive, e.g. `xray.exe`).
  static Future<bool> isPidAliveWithImage(int pid, String imageName) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'tasklist',
        ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return false;
      return result.stdout
          .toString()
          .toLowerCase()
          .contains('"${imageName.toLowerCase()}"');
    } on Object {
      return false;
    }
  }

  /// Force-terminate [pid]. Returns true when taskkill reports success.
  static Future<bool> killPid(int pid) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'taskkill',
        ['/PID', '$pid', '/F'],
        runInShell: true,
      ).timeout(const Duration(seconds: 15));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Image name for [pid] (e.g. from a port-conflict lookup), or null.
  static Future<String?> imageNameForPid(int pid) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'tasklist',
        ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split('\n').firstOrNull();
      if (line == null || !line.startsWith('"')) return null;
      return line.substring(1, line.indexOf('"', 1));
    } on Object {
      return null;
    }
  }
}

extension<T> on Iterable<T> {
  T? firstOrNull() {
    for (final element in this) {
      return element;
    }
    return null;
  }
}
