import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/app.dart';
import 'package:iranlink/src/models/connection.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/platform/app_paths.dart';
import 'package:iranlink/src/state/service_locator.dart';

/// Connect flow against the REAL service graph. In the widget-test sandbox
/// there is no Xray binary, so the expected outcome is a friendly
/// `coreErrorMissingExe` failure — this test pins the failure path wiring
/// (button -> provider -> core -> error banner).
void main() {
  testWidgets('connect surfaces missing-core error honestly', (tester) async {
    final temp =
        await Directory.systemTemp.createTemp('iranlink-connect-');
    addTearDown(() => temp.delete(recursive: true).catchError((_) => temp));
    final services = await AppServices.create(
        pathsOverride: AppPaths.custom(temp, portable: true));
    addTearDown(services.dispose);

    final profile = await services.profiles.add(const ProxyProfile(
      id: 'p1',
      name: 'test node',
      protocol: ProxyProtocol.vless,
      address: '127.0.0.1',
      port: 9,
      secret: '123e4567-e89b-12d3-a456-426614174000',
    ));
    await services.settings
        .update((s) => s.copyWith(activeProfileId: profile.id));

    await tester.pumpWidget(IranLinkApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONNECT'));
    await tester.pumpAndSettle();

    expect(services.connection.state, ConnectionState.error);
    expect(services.connection.failureKey, 'coreErrorMissingExe');
    // Banner + status bar both render the translated message.
    expect(
        find.text(
            'Core executable is missing. Reinstall IranLink or re-download the core.'),
        findsWidgets);
  });
}
