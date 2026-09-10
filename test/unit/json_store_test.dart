import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/storage/json_store.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('json-store-test-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('missing file reads as empty', () async {
    final store = JsonStore(
        file: File('${temp.path}/x.json'), schemaVersion: 1);
    expect(await store.read(), isEmpty);
  });

  test('write then read roundtrip', () async {
    final store = JsonStore(
        file: File('${temp.path}/x.json'), schemaVersion: 1);
    await store.write({'a': 1, 'b': 'x'});
    expect(await store.read(), {'a': 1, 'b': 'x', 'schemaVersion': 1});
  });

  test('corrupt file quarantines and returns empty', () async {
    final file = File('${temp.path}/x.json');
    await file.writeAsString('{not json');
    final store = JsonStore(file: file, schemaVersion: 1);
    expect(await store.read(), isEmpty);
    // Original preserved as .invalid-json-*.
    final siblings = temp.listSync();
    expect(
        siblings.any((e) => e.path.contains('.invalid-json-')), isTrue);
  });

  test('migration runs when version lags', () async {
    final file = File('${temp.path}/x.json');
    await file.writeAsString(jsonEncode({'schemaVersion': 1, 'v': 1}));
    final store = JsonStore(
      file: file,
      schemaVersion: 2,
      migrations: {
        1: (data) => {...data, 'migrated': true},
      },
    );
    final read = await store.read();
    expect(read['migrated'], isTrue);
    expect(read['schemaVersion'], 2);
  });
}
