import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the directories the app needs.
///
/// Layout after installation (`C:\Program Files\Radin`):
///
/// ```
/// Radin.exe            <- Flutter app
/// flutter_windows.dll
/// win_shell.dll
/// data/
/// core/
///   xray.exe           <- modern core (Windows 10/11)
///   xray-win7.exe      <- Windows 7/8 core
///   v2ray.exe
///   v2ray-win7.exe
///   tun2socks.exe
///   tun2socks-win7.exe
///   wintun.dll
///   geoip.dat
///   geosite.dat
/// ```
class AppPaths {
  AppPaths._();

  static Directory? _dataDir;

  /// Directory of the running executable.
  static Directory get exeDir => File(Platform.resolvedExecutable).parent;

  /// Directory that contains the bundled cores.
  ///
  /// Falls back to `%LOCALAPPDATA%\Radin\core` when the app runs from a
  /// location without a `core` folder (for example during development).
  static Directory get coreDir {
    final bundled = Directory(p.join(exeDir.path, 'core'));
    if (bundled.existsSync()) {
      return bundled;
    }
    return Directory(p.join(localDataDir.path, 'core'));
  }

  /// `%APPDATA%\Radin` - settings, subscriptions and logs.
  static Directory get dataDir {
    final cached = _dataDir;
    if (cached != null) {
      return cached;
    }
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory(p.join(appData, 'Radin'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _dataDir = dir;
    return dir;
  }

  /// `%LOCALAPPDATA%\Radin` - downloaded/updated cores.
  static Directory get localDataDir {
    final localAppData = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['TEMP'] ??
        '.';
    final dir = Directory(p.join(localAppData, 'Radin'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Directory get logDir {
    final dir = Directory(p.join(dataDir.path, 'logs'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static File get settingsFile => File(p.join(dataDir.path, 'settings.json'));

  static File get profilesFile => File(p.join(dataDir.path, 'profiles.json'));

  static File get generatedConfig =>
      File(p.join(dataDir.path, 'radin.generated.json'));

  static File get coreLog => File(p.join(logDir.path, 'core.log'));

  static File get coreErrorLog => File(p.join(logDir.path, 'core.error.log'));

  static File get tun2socksLog => File(p.join(logDir.path, 'tun2socks.log'));

  /// Trims a log file so that it cannot grow forever.
  static void truncateIfNeeded(File file, {int maxBytes = 4 * 1024 * 1024}) {
    try {
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        final lines = file.readAsLinesSync();
        file.writeAsStringSync(lines.skip(lines.length ~/ 2).join('\n'));
      }
    } on Object {
      // Logging must never break the app.
    }
  }
}
