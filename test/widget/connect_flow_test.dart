/// Connect flow against the REAL service graph. In the widget-test sandbox
/// there is no Xray binary, so the expected outcome is a friendly
/// `coreErrorMissingExe` failure — this test pins the failure path wiring
/// (button -> provider -> core -> error banner).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/app.dart';
import 'package:iranlink/src/models/connection.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/platform/app_paths.dart';
import 'package:iranlink/src/state/connection_provider.dart';
import 'package:iranlink/src/state/service_locator.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('connect surfaces missing-core error honestly', (tester) async {
    // Boot + seed the real service graph under runAsync: the test body runs
    // in a FakeAsync zone where real filesystem/IO completions never resolve,
    // so awaiting them bare would deadlock the suite.
    final booted = await tester.runAsync<AppServices>(() async {
      final temp =
          await Directory.systemTemp.createTemp('iranlink-connect-');
      addTearDown(() => temp.delete(recursive: true).catchError((_) => temp));
      final created = await AppServices.create(
          pathsOverride: AppPaths.custom(temp, portable: true),);

      final profile = await created.profiles.add(const ProxyProfile(
        id: 'p1',
        name: 'test node',
        protocol: ProxyProtocol.vless,
        address: '127.0.0.1',
        port: 9,
        secret: '123e4567-e89b-12d3-a456-426614174000',
      ),);
      await created.settings
          .update((s) => s.copyWith(activeProfileId: profile.id));
      return created;
    });
    final services = booted!;
    addTearDown(services.dispose);

    await tester.pumpWidget(IranLinkApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONNECT'));
    await tester.pumpAndSettle();

    final element = tester.element(find.text('CONNECT'));
    final connection =
        Provider.of<ConnectionProvider>(element, listen: false);
    expect(connection.state, ConnectionState.error);
    expect(connection.failureKey, 'coreErrorMissingExe');
    // Banner + status bar both render the translated message.
    expect(
        find.text(
            'Core executable is missing. Reinstall IranLink or re-download the core.',),
        findsWidgets,);
  });
}
