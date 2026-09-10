/// Versioned JSON document store with atomic writes (no Flutter dependency).
library;

import 'dart:convert';
import 'dart:io';

typedef JsonMigration = Map<String, dynamic> Function(Map<String, dynamic> data);

/// A single JSON document on disk with `schemaVersion` + forward migrations.
///
/// - Missing file reads as `{}` (first run).
/// - Corrupt JSON is moved aside (`<name>.corrupt-<timestamp>`) and reads as
///   `{}` — the app never refuses to start over a broken store file.
/// - Writes are atomic (temp file + rename) and always stamp `schemaVersion`.
class JsonStore {
  JsonStore({
    required this.file,
    required this.schemaVersion,
    this.migrations = const {},
  });

  final File file;
  final int schemaVersion;
  final Map<int, JsonMigration> migrations;

  Future<Map<String, dynamic>> read() async {
    if (!await file.exists()) return {};
    try {
      final text = await file.readAsString();
      final decoded = json.decode(text);
      if (decoded is! Map<dynamic, dynamic>) return _quarantine('not-a-json-object');
      final data = (decoded as Map<dynamic, dynamic>).cast<String, dynamic>();
      return _migrate(data);
    } on FormatException {
      return _quarantine('invalid-json');
    } on FileSystemException {
      return _quarantine('unreadable');
    }
  }

  Future<Map<String, dynamic>> _quarantine(String reason) async {
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      await file.rename('${file.path}.$reason-$stamp');
    } on Object {
      // Best effort only.
    }
    return {};
  }

  Map<String, dynamic> _migrate(Map<String, dynamic> data) {
    var version = (data['schemaVersion'] as num?)?.toInt() ?? 0;
    final migrated = Map<String, dynamic>.from(data);
    while (version < schemaVersion) {
      final migration = migrations[version];
      if (migration == null) break; // unknown gap: stop, keep data as-is
      final next = migration(migrated);
      migrated
        ..clear()
        ..addAll(next);
      version++;
    }
    migrated['schemaVersion'] = schemaVersion;
    return migrated;
  }

  Future<void> write(Map<String, dynamic> data) async {
    await file.parent.create(recursive: true);
    final stamped = Map<String, dynamic>.from(data)
      ..['schemaVersion'] = schemaVersion;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(stamped));
    await tmp.rename(file.path);
  }
}
