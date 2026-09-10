/// Headless CI smoke test (`IranLink.exe --smoke-test`).
///
/// Exercises the REAL bundled core (no mocks): version probe, config build +
/// validation, process start, SOCKS handshake, stats query attempt, graceful
/// stop — plus a system-proxy enable/restore roundtrip. Prints `SMOKE-OK` on
/// success. Any failure prints `SMOKE-FAIL: <reason>` and returns 1.
///
/// The test profile points at a discard address: readiness only requires the
/// local inbounds, so no internet access is needed and the test is hermetic.
library;

import 'dart:async';
import 'dart:io';

import '../../src/core/app_version.dart';
import '../../src/models/profile.dart';
import '../../src/models/settings.dart';
import '../../src/network/connectivity.dart';
import '../../src/platform/app_paths.dart';
import '../../src/state/service_locator.dart';

Future<int> runSmokeTest(List<String> args) async {
  final timeoutSeconds = _flagValue(args, '--smoke-timeout', '120');
  final timeout = Duration(seconds: int.tryParse(timeoutSeconds) ?? 120);
  try {
    await _run().timeout(timeout);
    stdout.writeln('SMOKE-OK iranlink=$kAppVersion');
    return 0;
  } on TimeoutException {
    stdout.writeln('SMOKE-FAIL: timed out after ${timeout.inSeconds}s');
    return 1;
  } on Object catch (e, stack) {
    stdout.writeln('SMOKE-FAIL: $e');
    stdout.writeln(stack.toString().split('\n').take(8).join('\n'));
    return 1;
  }
}

String _flagValue(List<String> args, String flag, String fallback) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return fallback;
  return args[index + 1];
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
  stdout.writeln('smoke: $message OK');
}

Future<void> _run() async {
  stdout.writeln('smoke: IranLink $kAppVersion headless test starting');
  final sandbox =
      await Directory.systemTemp.createTemp('iranlink-smoke-');
  final paths = AppPaths.custom(sandbox, portable: true);

  // Core binaries must be staged (scripts/stage_bundle.py in CI).
  final coreDir = AppPaths.bundledCoreDir();
  _check(await File('${coreDir.path}/xray.exe').exists(),
      'primary core staged at ${coreDir.path}');
  _check(await File('${coreDir.path}/win7/xray.exe').exists(),
      'legacy core staged');

  final services = await AppServices.create(pathsOverride: paths);
  try {
    _check(services.core.coreVersion.isNotEmpty,
        'core version probe (${services.core.coreVersion})');

    // Hermetic test profile: local inbounds + discard outbound target.
    final profile = ProxyProfile(
      id: 'smoke-profile',
      name: 'smoke',
      protocol: ProxyProtocol.socks,
      address: '127.0.0.1',
      port: 9,
    );
    final settings = const AppSettings().copyWith(
      inbounds: const InboundSettings(
          socksPort: 18080, httpPort: 18081, bindAddress: '127.0.0.1'),
      statsPort: 18082,
    );

    await services.core.connect(profile: profile, settings: settings);
    _check(services.core.status.name == 'running',
        'core running (pid=${services.core.pid})');

    final handshake = await ConnectivityService(log: services.log)
        .probeSocksHandshake('127.0.0.1', 18080);
    _check(handshake.success, 'SOCKS handshake on 127.0.0.1:18080');

    // Stats query is best-effort (API timing), but must not throw.
    await services.core.trafficStream.first
        .timeout(const Duration(seconds: 10));
    stdout.writeln('smoke: traffic sample received OK');

    if (Platform.isWindows) {
      final before = services.systemProxy.current();
      await services.systemProxy
          .enable(server: '127.0.0.1:18081');
      final during = services.systemProxy.current();
      _check(during.enabled && during.server == '127.0.0.1:18081',
          'system proxy enabled');
      await services.systemProxy.disable();
      final after = services.systemProxy.current();
      _check(after.enabled == before.enabled &&
          after.server == before.server, 'system proxy restored');
    }

    await services.core.disconnect();
    _check(services.core.status.name == 'stopped', 'core stopped');
  } finally {
    await services.dispose();
    try {
      await sandbox.delete(recursive: true);
    } on Object {
      // ignore
    }
  }
}
