/// Core abstraction: the UI and [CoreManager] only speak this interface.
///
/// Adding another core (e.g. sing-box) means implementing [CoreAdapter] plus
/// a config builder/validator — no UI or manager changes.
library;

import 'dart:async';

/// A supervised core process.
abstract class CoreProcess {
  int get pid;
  Future<int> get exitCode;
  Stream<List<int>> get stdoutStream;
  Stream<List<int>> get stderrStream;

  /// Ask the process to exit and wait up to [timeout]; force-kills after.
  /// Returns the exit code (or -1 when the wait itself failed).
  Future<int> terminateGracefully({Duration timeout = const Duration(seconds: 5)});

  void kill();
}

class CoreStartRequest {
  const CoreStartRequest({
    required this.executable,
    required this.configPath,
    this.extraArgs = const [],
  },);

  final String executable;
  final String configPath;
  final List<String> extraArgs;
}

abstract class CoreAdapter {
  String get coreName;

  /// Runs `<exe> version` and returns the parsed version string.
  Future<String> readVersion(String executable);

  /// Spawns the core with the given config file. No secrets on argv.
  Future<CoreProcess> start(CoreStartRequest request);
}
