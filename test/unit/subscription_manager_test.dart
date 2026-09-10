import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:iranlink/src/logging/log_service.dart';
import 'package:iranlink/src/models/subscription.dart';
import 'package:iranlink/src/profiles/profile_repository.dart';
import 'package:iranlink/src/storage/json_store.dart';
import 'package:iranlink/src/subscriptions/subscription_fetcher.dart';
import 'package:iranlink/src/subscriptions/subscription_manager.dart';

const _uuid = '123e4567-e89b-12d3-a456-426614174000';

class _FakeClient extends http.BaseClient {
  _FakeClient({this.statusCode = 200, this.body = ''});

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      statusCode,
      request: request,
      contentLength: bytes.length,
    );
  }
}

void main() {
  late Directory temp;
  late LogService log;
  var counter = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sub-manager-test-');
    log = LogService(
        logDir: Directory('${temp.path}/logs'),
        minLevel: LogLevel.error);
  });

  tearDown(() async {
    await log.dispose();
    await temp.delete(recursive: true);
  });

  ProfileRepository _profiles() => ProfileRepository(
        store: JsonStore(
            file: File('${temp.path}/profiles.json'), schemaVersion: 1),
        newId: () => 'p-${counter++}',
        log: log,
      );

  SubscriptionManager _manager(ProfileRepository profiles, _FakeClient client) =>
      SubscriptionManager(
        store: JsonStore(
            file: File('${temp.path}/subs.json'), schemaVersion: 1),
        cacheDir: Directory('${temp.path}/cache'),
        profiles: profiles,
        fetcher: SubscriptionFetcher(log: log, client: client),
        newId: () => 's-${counter++}',
        log: log,
      );

  test('refresh imports profiles and persists', () async {
    const link = 'vless://$_uuid@example.com:443#SubNode';
    final profiles = _profiles();
    await profiles.load();
    final manager =
        _manager(profiles, _FakeClient(body: base64Encode(utf8.encode('$link\n'))));
    await manager.load();
    final sub = await manager.add(
        name: 'test', url: 'https://example.com/sub');
    final ok = await manager.refresh(sub.id);
    expect(ok, isTrue);
    expect(manager.subscriptions.single.lastStatus,
        SubscriptionStatus.ok);
    expect(profiles.profiles.map((p) => p.name), ['SubNode']);
    expect(profiles.profiles.single.subscriptionId, sub.id);
  });

  test('failed refresh records error, never throws', () async {
    final profiles = _profiles();
    await profiles.load();
    final manager =
        _manager(profiles, _FakeClient(statusCode: 500, body: 'oops'));
    await manager.load();
    final sub = await manager.add(
        name: 'test', url: 'https://example.com/sub');
    final ok = await manager.refresh(sub.id);
    expect(ok, isFalse);
    expect(manager.subscriptions.single.lastStatus,
        SubscriptionStatus.error);
    expect(manager.subscriptions.single.lastError, isNotEmpty);
    expect(profiles.profiles, isEmpty);
  });

  test('add rejects invalid url', () async {
    final profiles = _profiles();
    await profiles.load();
    final manager = _manager(profiles, _FakeClient());
    await manager.load();
    expect(() => manager.add(name: 'x', url: 'not-a-url'),
        throwsArgumentError);
  });
}
