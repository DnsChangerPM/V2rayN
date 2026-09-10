/// End-to-end lifecycle against a REAL Xray binary on Windows CI.
///
/// Requires `IRANLINK_CORE_DIR` pointing at a directory with `xray.exe`
/// (+ `win7/xray.exe`); skipped otherwise. Uses a hermetic discard profile
/// (127.0.0.1:9, ephemeral inbound ports) so the test makes no real network
/// connections. SOCKS-only mode: the installer smoke test covers the system
/// proxy roundtrip separately.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iranlink/app.dart';
import 'package:iranlink/src/models/connection.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/models/settings.dart';
import 'package:iranlink/src/platform/app_paths.dart';
import 'package:iranlink/src/state/service_locator.dart';

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real core connect/disconnect reflects in UI', (tester) async {
    final coreDir = Platform.environment['IRANLINK_CORE_DIR'];
    if (coreDir == null || coreDir.isEmpty) {
      markTestSkipped('IRANLINK_CORE_DIR not set; skipping core E2E.');
      return;
    }

    // Ephemeral ports first (avoids races with parallel CI jobs).
    final socksPort = await _freePort();
    var httpPort = await _freePort();
    if (httpPort == socksPort) httpPort = await _freePort();

    final temp =
        await Directory.systemTemp.createTemp('iranlink-e2e-');
    final services = await AppServices.create(
        pathsOverride: AppPaths.custom(temp, portable: true));
    addTearDown(() async {
      await services.dispose();
      await temp.delete(recursive: true).catchError((_) => temp);
    });

    final profile = await services.profiles.add(const ProxyProfile(
      id: 'e2e',
      name: 'e2e discard',
      protocol: ProxyProtocol.vless,
      address: '127.0.0.1',
      port: 9,
      secret: '123e4567-e89b-12d3-a456-426614174000',
    ));
    await services.settings.update((s) => s.copyWith(
          activeProfileId: profile.id,
          proxyMode: ProxyMode.socks,
          inbounds: s.inbounds.copyWith(
            socksPort: socksPort,
            httpPort: httpPort,
          ),
        ));

    await tester.pumpWidget(IranLinkApp(services: services));
    await tester.pumpAndSettle();

    await services.connection.connect();
    await tester.pumpAndSettle();
    expect(services.connection.state, ConnectionState.connected,
        reason: services.connection.failureKey);
    expect(services.core.status, CoreStatus.running);
    expect(find.text('DISCONNECT'), findsOneWidget);

    await services.connection.disconnect();
    await tester.pumpAndSettle();
    expect(services.connection.state, ConnectionState.disconnected);
    expect(find.text('CONNECT'), findsOneWidget);
  });
}
