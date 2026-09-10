import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/app.dart';
import 'package:iranlink/src/models/connection.dart';
import 'package:iranlink/src/platform/app_paths.dart';
import 'package:iranlink/src/state/connection_provider.dart';
import 'package:iranlink/src/state/service_locator.dart';
import 'package:provider/provider.dart';

Future<AppServices> _boot(WidgetTester tester) async {
  // The test body runs inside a FakeAsync zone: real-async completions
  // (filesystem IO, service bootstrap) only resolve under runAsync, so all
  // genuine IO for boot must happen here — awaiting it in the bare test body
  // would deadlock the suite.
  final services = await tester.runAsync<AppServices>(() async {
    final temp = await Directory.systemTemp.createTemp('iranlink-widget-');
    addTearDown(() => temp.delete(recursive: true).catchError((_) => temp));
    return AppServices.create(
        pathsOverride: AppPaths.custom(temp, portable: true),);
  });
  return services!;
}

Future<void> _pump(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(IranLinkApp(services: services));
  await tester.pumpAndSettle();
}

/// The [ConnectionProvider] owned by the pumped widget tree.
ConnectionProvider _connectionOf(WidgetTester tester) {
  final element = tester.element(find.text('CONNECT'));
  return Provider.of<ConnectionProvider>(element, listen: false);
}

void main() {
  testWidgets('boots to dashboard; connect without profile fails friendly',
      (tester) async {
    final services = await _boot(tester);
    addTearDown(services.dispose);
    await _pump(tester, services);

    expect(find.text('IranLink'), findsWidgets);
    final connect = find.text('CONNECT');
    expect(connect, findsOneWidget);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    final connection = _connectionOf(tester);
    expect(connection.state, ConnectionState.error);
    expect(connection.failureKey, 'errorNoProfile');
    expect(find.text('Select a profile first.'), findsWidgets);
  });

  testWidgets('navigates between pages', (tester) async {
    final services = await _boot(tester);
    addTearDown(services.dispose);
    await _pump(tester, services);

    for (final destination in [
      'Profiles',
      'Subscriptions',
      'Speed Test',
      'Diagnostics',
      'Logs',
      'Settings',
      'About',
      'Dashboard',
    ]) {
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle();
    }
    expect(find.text('CONNECT'), findsOneWidget);
  });

  testWidgets('settings toggle persists to service layer', (tester) async {
    final services = await _boot(tester);
    addTearDown(services.dispose);
    await _pump(tester, services);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Minimize to tray'));
    final tile = find.ancestor(
      of: find.text('Minimize to tray'),
      matching: find.byType(SwitchListTile),
    );
    expect(tile, findsOneWidget);
    final before = services.settings.current.minimizeToTray;
    await tester.tap(tile);
    await tester.pump();
    expect(services.settings.current.minimizeToTray, !before);
  });
}
