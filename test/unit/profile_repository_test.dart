import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/logging/log_service.dart';
import 'package:iranlink/src/models/profile.dart';
import 'package:iranlink/src/profiles/profile_repository.dart';
import 'package:iranlink/src/storage/json_store.dart';

ProxyProfile _profile(String id) => ProxyProfile(
      id: id,
      name: 'node $id',
      protocol: ProxyProtocol.vless,
      address: 'example.com',
      port: 443,
      secret: 'secret-$id',
    );

void main() {
  late Directory temp;
  late LogService log;
  var counter = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('profile-repo-test-');
    log = LogService(
        logDir: Directory('${temp.path}/logs'),
        minLevel: LogLevel.error,);
  });

  tearDown(() async {
    await log.dispose();
    await temp.delete(recursive: true);
  });

  ProfileRepository makeRepo() => ProfileRepository(
        store: JsonStore(
            file: File('${temp.path}/profiles.json'), schemaVersion: 1,),
        newId: () => 'gen-${counter++}',
        log: log,
      );

  test('add/update/remove roundtrip with persistence', () async {
    final repo = makeRepo();
    await repo.load();
    expect(repo.profiles, isEmpty);

    final added = await repo.add(_profile('p1').copyWith(id: ''));
    expect(added.id, startsWith('gen-'));

    await repo.update(added.copyWith(name: 'renamed'));
    expect(repo.profiles.single.name, 'renamed');

    // Reload from disk.
    final repo2 = makeRepo();
    await repo2.load();
    expect(repo2.profiles.single.name, 'renamed');

    await repo2.remove(added.id);
    expect(repo2.profiles, isEmpty);
  });

  test('replaceSubscriptionProfiles swaps group atomically', () async {
    final repo = makeRepo();
    await repo.load();
    await repo.add(_profile('manual'));
    await repo.replaceSubscriptionProfiles('sub1', [
      _profile('sub1:0').copyWith(subscriptionId: 'sub1'),
      _profile('sub1:1').copyWith(subscriptionId: 'sub1'),
    ]);
    expect(repo.profiles.length, 3);
    await repo.replaceSubscriptionProfiles('sub1', [
      _profile('sub1:0').copyWith(subscriptionId: 'sub1', name: 'fresh'),
    ]);
    expect(repo.profiles.length, 2);
    expect(repo.profiles.any((p) => p.name == 'fresh'), isTrue);
    expect(repo.profiles.any((p) => p.id == 'manual'), isTrue);
  });

  test('query filters by text and favorite', () async {
    final repo = makeRepo();
    await repo.load();
    await repo.add(_profile('a').copyWith(isFavorite: true));
    await repo.add(_profile('b'));
    expect(repo.query(search: 'node a').length, 1);
    expect(repo.query(groupId: BuiltinGroups.favorites).length, 1);
    expect(repo.query(search: 'trojan'), isEmpty);
  });
}
