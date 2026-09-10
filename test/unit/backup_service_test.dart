import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/logging/log_service.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/models/settings.dart';
import 'package:iranlink/src/models/subscription.dart';
import 'package:iranlink/src/settings/backup_service.dart';

void main() {
  late Directory temp;
  late LogService log;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('backup-test-');
    log = LogService(
        logDir: Directory('${temp.path}/logs'),
        minLevel: LogLevel.error,);
  });

  tearDown(() async {
    await log.dispose();
    await temp.delete(recursive: true);
  });

  AppSettings get settings => const AppSettings();
  List<ProxyProfile> get profiles => [
        const ProxyProfile(
          id: 'p1',
          name: 'node',
          protocol: ProxyProtocol.vless,
          address: 'example.com',
          port: 443,
          secret: 'TOPSECRET',
        ),
      ];
  List<Subscription> get subscriptions => [
        Subscription(
          id: 's1',
          name: 'sub',
          url: 'https://example.com/sub?token=abc',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];

  BackupService service() => BackupService(log: log);

  test('no-password export strips all secrets', () async {
    final file = File('${temp.path}/backup.json');
    await service().exportToFile(
      file: file,
      settings: settings,
      profiles: profiles,
      subscriptions: subscriptions,
    );
    final text = await file.readAsString();
    expect(text, isNot(contains('TOPSECRET')));
    expect(text, isNot(contains('token=abc')));
    final decoded = json.decode(text) as Map<String, dynamic>;
    expect(decoded['includesSecrets'], isFalse);

    final imported = await service().importFromFile(file);
    expect(imported.profiles.single.secret, isEmpty);
  });

  test('password export encrypts and roundtrips', () async {
    final file = File('${temp.path}/backup.json');
    await service().exportToFile(
      file: file,
      settings: settings,
      profiles: profiles,
      subscriptions: subscriptions,
      password: 'correct horse',
    );
    final text = await file.readAsString();
    expect(text, isNot(contains('TOPSECRET')));
    expect(text, isNot(contains('token=abc')));

    final imported =
        await service().importFromFile(file, password: 'correct horse');
    expect(imported.profiles.single.secret, 'TOPSECRET');
    expect(imported.subscriptions.single.url,
        'https://example.com/sub?token=abc',);
    expect(imported.settings.inbounds.socksPort,
        settings.inbounds.socksPort,);
  });

  test('wrong password fails closed', () async {
    final file = File('${temp.path}/backup.json');
    await service().exportToFile(
      file: file,
      settings: settings,
      profiles: profiles,
      subscriptions: subscriptions,
      password: 'correct horse',
    );
    expect(() => service().importFromFile(file, password: 'wrong'),
        throwsA(anything),);
    expect(() => service().importFromFile(file), throwsA(anything));
  });
}
