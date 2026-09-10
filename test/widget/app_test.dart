import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/app.dart';
import 'package:iranlink/src/models/connection.dart';
import 'package:iranlink/src/platform/app_paths.dart';
import 'package:iranlink/src/state/connection_provider.dart';
import 'package:iranlink/src/state/service_locator.dart';
import 'package:provider/provider.dart';

/// Boots the real service graph against a temp directory.
///
/// ALL real-async work (file IO, service init/dispose) must run inside
/// `tester.runAsync`: `testWidgets` bodies execute in a FakeAsync zone where
/// real async I/O never completes — awaiting it directly hangs the test
/// forever (the per-test timeout cannot fire either).
Future<AppServices> _boot(WidgetTester tester) async {
  final temp = (await tester.runAsync<Directory>(
      () => Directory.systemTemp.createTemp('iranlink-widget-'),))!;
  addTearDown(() => tester.runAsync(() => temp.delete(recursive: true)));
  return (await tester.runAsync<AppServices>(() => AppServices.create(
        pathsOverride: AppPaths.custom(temp, portable: true),
      )))!;
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
    addTearDown(() => tester.runAsync(services.dispose));
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
    addTearDown(() => tester.runAsync(services.dispose));
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
    addTearDown(() => tester.runAsync(services.dispose));
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
