/// Connect flow against the REAL service graph. In the widget-test sandbox
/// there is no Xray binary, so the expected outcome is a friendly
/// `coreErrorMissingExe` failure — this test pins the failure path wiring
/// (button -> provider -> core -> error banner).
///
/// Real-async work (file IO, service boot/dispose, repository writes) runs
/// inside `tester.runAsync`: the FakeAsync zone of `testWidgets` never
/// completes real async I/O, so awaiting it directly would hang the test.
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
    final temp = (await tester.runAsync<Directory>(
        () => Directory.systemTemp.createTemp('iranlink-connect-'),))!;
    addTearDown(() => tester.runAsync(() => temp.delete(recursive: true)));
    final services = (await tester.runAsync<AppServices>(() =>
        AppServices.create(
            pathsOverride: AppPaths.custom(temp, portable: true,),)))!;
    addTearDown(() => tester.runAsync(services.dispose));

    final profile = (await tester.runAsync<ProxyProfile>(
        () => services.profiles.add(const ProxyProfile(
              id: 'p1',
              name: 'test node',
              protocol: ProxyProtocol.vless,
              address: '127.0.0.1',
              port: 9,
              secret: '123e4567-e89b-12d3-a456-426614174000',
            ),)))!;
    await tester.runAsync(() => services.settings
        .update((s) => s.copyWith(activeProfileId: profile.id),));

    await tester.pumpWidget(IranLinkApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONNECT'));
    await tester.pump();
    // Give the real event loop a beat so any async work started by the
    // connect flow (file probes, logging writes) can complete, then settle.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),);
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
