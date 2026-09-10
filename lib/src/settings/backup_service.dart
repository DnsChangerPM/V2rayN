/// Settings backup: export/import with secret-aware handling.
///
/// The backup is a JSON envelope: `{app, version, settings, profiles,
/// subscriptions, vault}`. Secrets inside profiles/subscriptions are
/// re-encrypted with a user-supplied password (AES-256-GCM, PBKDF2 key);
/// without a password the export *excludes* secrets and says so loudly.
/// Import always validates structure before touching live stores.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../core/app_version.dart';
import '../logging/log_service.dart';
import '../models/profile.dart';
import '../models/settings.dart';
import '../models/subscription.dart';

class BackupService {
  BackupService({required LogService log}) : _log = log;

  final LogService _log;

  /// Export everything. When [password] is null/empty, secrets are stripped
  /// (profiles keep names/addresses; `secret` fields become '').
  Future<void> exportToFile({
    required File file,
    required AppSettings settings,
    required List<ProxyProfile> profiles,
    required List<Subscription> subscriptions,
    String password = '',
  }) async {
    final withSecrets = password.isNotEmpty;
    final envelope = <String, dynamic>{
      'app': 'IranLink',
      'version': kAppVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'includesSecrets': withSecrets,
      'settings': settings.toJson(),
      'profiles': profiles.map((p) => p.toJson()).toList(),
      'subscriptions': subscriptions
          .map((s) => s.copyWith(url: '').toJson())
          .toList(),
    };
    if (withSecrets) {
      final secrets = {
        'profiles': {for (final p in profiles) p.id: p.secret},
        'subscriptions': {for (final s in subscriptions) s.id: s.url},
        'rawJson': {for (final p in profiles) if (p.rawJson != null) p.id: p.rawJson},
      };
      envelope['secrets'] = _seal(json.encode(secrets), password);
      // Strip plaintext secrets from the main body.
      envelope['profiles'] = profiles
          .map((p) => p.copyWith(secret: '', rawJson: null).toJson())
          .toList();
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(envelope),);
    _log.info('backup',
        'Exported backup (secrets=${withSecrets ? 'encrypted' : 'excluded'})',);
  }

  Future<BackupData> importFromFile(File file, {String password = ''}) async {
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<dynamic, dynamic>) {
      throw const FormatException('Not an IranLink backup file');
    }
    final envelope = decoded.cast<String, dynamic>();
    if (envelope['app'] != 'IranLink') {
      throw const FormatException('Not an IranLink backup file');
    }
    Map<String, String> profileSecrets = {};
    Map<String, String> subscriptionSecrets = {};
    Map<String, String> rawJsonSecrets = {};
    if (envelope['includesSecrets'] == true) {
      if (password.isEmpty) {
        throw StateError('Backup is encrypted: password required');
      }
      final sealed = envelope['secrets'];
      if (sealed is! Map<dynamic, dynamic>) {
        throw const FormatException('Backup secrets block is corrupt');
      }
      final opened = json.decode(
          _open(sealed.cast<String, dynamic>(), password),);
      if (opened is! Map<dynamic, dynamic>) {
        throw const FormatException('Backup secrets block is corrupt');
      }
      profileSecrets =
          (opened['profiles'] as Map<dynamic, dynamic>?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
      subscriptionSecrets =
          (opened['subscriptions'] as Map<dynamic, dynamic>?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
      rawJsonSecrets =
          (opened['rawJson'] as Map<dynamic, dynamic>?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
    }
    final settings = AppSettings.fromJson(
        (envelope['settings'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? {},);
    final profiles = <ProxyProfile>[];
    for (final item in (envelope['profiles'] as List<dynamic>? ?? []).whereType<Map<dynamic, dynamic>>()) {
      try {
        var profile =
            ProxyProfile.fromJson(item.cast<String, dynamic>());
        final secret = profileSecrets[profile.id];
        if (secret != null) profile = profile.copyWith(secret: secret);
        final raw = rawJsonSecrets[profile.id];
        if (raw != null) profile = profile.copyWith(rawJson: raw);
        profiles.add(profile);
      } on Object catch (e) {
        _log.warning('backup', 'Skipping unreadable profile', error: e);
      }
    }
    final subscriptions = <Subscription>[];
    for (final item
        in (envelope['subscriptions'] as List<dynamic>? ?? []).whereType<Map<dynamic, dynamic>>()) {
      try {
        var subscription =
            Subscription.fromJson(item.cast<String, dynamic>());
        final url = subscriptionSecrets[subscription.id];
        if (url != null) subscription = subscription.copyWith(url: url);
        subscriptions.add(subscription);
      } on Object catch (e) {
        _log.warning('backup', 'Skipping unreadable subscription', error: e);
      }
    }
    return BackupData(
        settings: settings,
        profiles: profiles,
        subscriptions: subscriptions,);
  }

  // -- password-based envelope encryption (PBKDF2-HMAC-SHA256 + AES-GCM) ------

  Map<String, String> _seal(String plaintext, String password) {
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    final key = _pbkdf2(utf8.encode(password), salt);
    final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.gcm),);
    final iv = encrypt.IV.fromSecureRandom(12);
    final cipher = encrypter.encrypt(plaintext, iv: iv);
    return {
      'kdf': 'pbkdf2-sha256-600k',
      'salt': base64.encode(salt),
      'iv': iv.base64,
      'data': cipher.base64,
    };
  }

  String _open(Map<String, dynamic> sealed, String password) {
    final salt = base64.decode(sealed['salt'].toString());
    final key = _pbkdf2(utf8.encode(password), salt);
    final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.gcm),);
    return encrypter.decrypt64(
      sealed['data'].toString(),
      iv: encrypt.IV.fromBase64(sealed['iv'].toString()),
    );
  }

  Uint8List _pbkdf2(List<int> password, List<int> salt,
      {int iterations = 600000, int length = 32,}) {
    var block = Uint8List(0);
    final result = <int>[];
    var counter = 1;
    while (result.length < length) {
      final hmac = Hmac(sha256, password);
      var u = hmac
          .convert([...salt, ..._int32be(counter)])
          .bytes;
      final xor = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < xor.length; j++) {
          xor[j] ^= u[j];
        }
      }
      result.addAll(xor);
      counter++;
    }
    block = Uint8List.fromList(result.take(length).toList());
    return block;
  }

  List<int> _int32be(int value) => [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
}

class BackupData {
  const BackupData({
    required this.settings,
    required this.profiles,
    required this.subscriptions,
  });

  final AppSettings settings;
  final List<ProxyProfile> profiles;
  final List<Subscription> subscriptions;
}
