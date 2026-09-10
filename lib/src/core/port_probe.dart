/// Local-port probing: availability checks + listener owner lookup.
///
/// [isPortFree] binds to prove freedom. [findTcpListenerOwner] parses
/// `netstat -ano` on Windows to name the PID holding a conflicting port so
/// the UI can show an actionable error.
library;

import 'dart:async';
import 'dart:io';

Future<bool> isPortFree(String host, int port) async {
  try {
    final socket = await ServerSocket.bind(host, port);
    await socket.close();
    return true;
  } on Object {
    return false;
  }
}

/// PID of the process LISTENING on TCP [port] (IPv4/IPv6, any interface),
/// or null when unknown (non-Windows, parse failure, or not listening).
Future<int?> findTcpListenerOwner(int port) async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run(
      'netstat',
      ['-ano', '-p', 'TCP'],
      runInShell: true,
    ).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) return null;
    return parseNetstatOwner(result.stdout.toString(), port);
  } on Object {
    return null;
  }
}

/// Pure netstat parser (unit-testable). Matches lines like:
/// `  TCP    127.0.0.1:10808    0.0.0.0:0    LISTENING    1234`
int? parseNetstatOwner(String output, int port) {
  final suffix = ':$port';
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 5) continue;
    if (parts[0].toUpperCase() != 'TCP') continue;
    if (parts[1].endsWith(suffix) &&
        parts[3].toUpperCase() == 'LISTENING') {
      return int.tryParse(parts[4]);
    }
  }
  return null;
}

/// True when TCP [port] on [host] accepts a connection (readiness probe).
Future<bool> canConnect(String host, int port,
    {Duration timeout = const Duration(milliseconds: 500)},) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}
