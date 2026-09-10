/// Filesystem layout (Windows conventions + portable mode).
///
/// Installed mode:  `<support>/IranLink/{config,profiles,subscriptions,logs,core,cache}`
/// Portable mode:   `<exeDir>/Data/{...}` when `portable.marker` sits next to
/// the EXE (created on first portable launch after user confirmation).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths._({required this.base, required this.portable});

  final Directory base;
  final bool portable;

  Directory get configDir => Directory(p.join(base.path, 'config'));
  Directory get profilesDir => Directory(p.join(base.path, 'profiles'));
  Directory get subscriptionsDir =>
      Directory(p.join(base.path, 'subscriptions'));
  Directory get logsDir => Directory(p.join(base.path, 'logs'));
  Directory get coreDir => Directory(p.join(base.path, 'core'));
  Directory get cacheDir => Directory(p.join(base.path, 'cache'));

  File get settingsFile => File(p.join(configDir.path, 'settings.json'));
  File get profilesFile => File(p.join(profilesDir.path, 'profiles.json'));
  File get subscriptionsFile =>
      File(p.join(subscriptionsDir.path, 'subscriptions.json'));
  File get vaultFile => File(p.join(configDir.path, 'vault.dat'));

  /// Directory holding the bundled core next to the executable
  /// (`<exeDir>/core/{xray.exe, win7/xray.exe, ...}`).
  static Directory bundledCoreDir() =>
      Directory(p.join(File(Platform.resolvedExecutable).parent.path, 'core'));

  static Future<AppPaths> resolve() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final marker = File(p.join(exeDir.path, 'portable.marker'));
    if (await marker.exists()) {
      final base = Directory(p.join(exeDir.path, 'Data'));
      return AppPaths._(base: base, portable: true);
    }
    final support = await getApplicationSupportDirectory();
    final base = p.basename(support.path) == 'IranLink'
        ? Directory(support.path)
        : Directory(p.join(support.path, 'IranLink'));
    return AppPaths._(base: base, portable: false);
  }

  /// Create `portable.marker` + Data dir (portable first-run, user-confirmed).
  static Future<AppPaths> enablePortable() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    await File(p.join(exeDir.path, 'portable.marker'))
        .writeAsString('IranLink portable mode. Delete this file to use %AppData% paths.\n');
    return AppPaths._(
        base: Directory(p.join(exeDir.path, 'Data')), portable: true);
  }

  /// Test seam (and smoke-test sandbox).
  factory AppPaths.custom(Directory base, {bool portable = false}) =>
      AppPaths._(base: base, portable: portable);

  Future<void> ensureCreated() async {
    for (final dir in [
      configDir,
      profilesDir,
      subscriptionsDir,
      logsDir,
      coreDir,
      cacheDir
    ]) {
      await dir.create(recursive: true);
    }
  }
}
