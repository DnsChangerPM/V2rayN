/// Xray core adapter: process spawn, version probe, bounded output capture.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/log_sanitizer.dart';
import 'core_adapter.dart';

/// `xray.exe` started with `run -c <config>`. stdout/stderr are decoded as
/// UTF-8 (malformed-tolerant), split into lines, and exposed as broadcast
/// streams. [CoreManager] applies bounded buffering on top.
class XrayProcess implements CoreProcess {
  XrayProcess._(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Stream<List<int>> get stdoutStream => _process.stdout;

  @override
  Stream<List<int>> get stderrStream => _process.stderr;

  @override
  Future<int> terminateGracefully(
      {Duration timeout = const Duration(seconds: 5)}) async {
    _process.kill(ProcessSignal.sigterm);
    try {
      return await _process.exitCode.timeout(timeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      return _process.exitCode;
    }
  }

  @override
  void kill() => _process.kill(ProcessSignal.sigkill);
}

class XrayCoreAdapter implements CoreAdapter {
  XrayCoreAdapter({Duration versionTimeout = const Duration(seconds: 10)})
      : _versionTimeout = versionTimeout;

  final Duration _versionTimeout;

  @override
  String get coreName => 'xray';

  @override
  Future<String> readVersion(String executable) async {
    final result = await Process.run(
      executable,
      ['version'],
      runInShell: false,
    ).timeout(_versionTimeout);
    final output = '${result.stdout}\n${result.stderr}';
    final version = parseXrayVersion(output);
    if (version == null) {
      throw StateError('Unrecognized version output: '
          '${LogSanitizer.sanitize(output).trim().split('\n').take(3).join(' | ')}');
    }
    return version;
  }

  @override
  Future<CoreProcess> start(CoreStartRequest request) async {
    final process = await Process.start(
      request.executable,
      ['run', '-c', request.configPath, ...request.extraArgs],
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    return XrayProcess._(process);
  }
}

/// Parse `Xray 26.3.27 (Xray, Penetrates Everything.) ...` -> `26.3.27`.
/// Returns null when no version token is found.
String? parseXrayVersion(String output) {
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'Xray\s+(\d+\.\d+\.\d+)').firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Decode a byte stream into lines (shared by manager + diagnostics).
Stream<String> decodeLines(Stream<List<int>> bytes) =>
    bytes.transform(utf8.decoder).transform(const LineSplitter());
