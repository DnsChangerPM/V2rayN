/// Secret storage: DPAPI on Windows, AES-256-GCM file vault as fallback.
///
/// [SecureVaultFactory.create] prefers DPAPI (`CryptProtectData`, user scope,
/// `CRYPTPROTECT_UI_FORBIDDEN` — available since Windows 2000, so the Win7
/// path is identical). If DPAPI is unavailable or fails its self-test, an
/// AES-256-GCM vault with a per-installation random key is used instead and
/// the fallback is disclosed via [SecureVault.usesDpapi] (shown in
/// Diagnostics + a one-time notice). No secrets are ever logged by this file.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../logging/log_service.dart';

/// CRYPTPROTECT_UI_FORBIDDEN (not exported as a win32 5.x constant).
const int _cryptProtectUiForbidden = 0x1;

abstract class SecureVault {
  Future<void> put(String key, String value);
  Future<String?> get(String key);
  Future<void> delete(String key);
  Future<void> deleteAll();

  /// False when running on the AES fallback (disclosed in Diagnostics).
  bool get usesDpapi;
  String get backendName;
}

abstract final class SecureVaultFactory {
  static Future<SecureVault> create({
    required File vaultFile,
    required File keyFile,
    required LogService log,
  }) async {
    if (Platform.isWindows) {
      try {
        final vault = DpapiVault(vaultFile);
        await vault.selfTest();
        log.info('vault', 'Secure vault: DPAPI backend');
        return vault;
      } on Object catch (e) {
        log.warning('vault',
            'DPAPI unavailable, falling back to AES file vault', error: e,);
      }
    }
    final vault = AesFileVault(vaultFile, keyFile);
    await vault.init();
    log.info('vault', 'Secure vault: AES-256-GCM file backend');
    return vault;
  }
}

// ---------------------------------------------------------------------------
// DPAPI vault: JSON {key: base64(dpapiCiphertext)}.
// ---------------------------------------------------------------------------

class DpapiVault implements SecureVault {
  DpapiVault(this.file);

  final File file;

  @override
  bool get usesDpapi => true;

  @override
  String get backendName => 'DPAPI';

  Future<void> selfTest() async {
    const probe = 'iranlink-dpapi-probe';
    final bytes = Uint8List.fromList(utf8.encode(probe));
    final roundTrip = utf8.decode(_unprotect(_protect(bytes)));
    if (roundTrip != probe) {
      throw StateError('DPAPI self-test failed');
    }
  }

  Future<Map<String, String>> _readAll() async {
    if (!await file.exists()) return {};
    try {
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<dynamic, dynamic>) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } on Object {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, String> entries) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode(entries));
    await tmp.rename(file.path);
  }

  @override
  Future<void> put(String key, String value) async {
    final entries = await _readAll();
    if (value.isEmpty) {
      entries[key] = '';
    } else {
      final cipher = _protect(Uint8List.fromList(utf8.encode(value)));
      entries[key] = base64.encode(cipher);
    }
    await _writeAll(entries);
  }

  @override
  Future<String?> get(String key) async {
    final entries = await _readAll();
    final stored = entries[key];
    if (stored == null || stored.isEmpty) return stored;
    return utf8.decode(_unprotect(base64.decode(stored)));
  }

  @override
  Future<void> delete(String key) async {
    final entries = await _readAll();
    entries.remove(key);
    await _writeAll(entries);
  }

  @override
  Future<void> deleteAll() async {
    if (await file.exists()) await file.delete();
  }

  Uint8List _protect(Uint8List plain) {
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final inData = calloc<Uint8>(plain.length)
      ..asTypedList(plain.length).setAll(0, plain);
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    try {
      inBlob.ref
        ..cbData = plain.length
        ..pbData = inData;
      final ok = CryptProtectData(inBlob, nullptr, nullptr, nullptr, nullptr,
          _cryptProtectUiForbidden, outBlob,);
      if (ok == 0) {
        throw StateError('CryptProtectData failed (code=${GetLastError()})');
      }
      return Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),);
    } finally {
      if (outBlob.ref.pbData != nullptr) {
        LocalFree(outBlob.ref.pbData);
      }
      calloc.free(inData);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }

  Uint8List _unprotect(Uint8List cipher) {
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final inData = calloc<Uint8>(cipher.length)
      ..asTypedList(cipher.length).setAll(0, cipher);
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    try {
      inBlob.ref
        ..cbData = cipher.length
        ..pbData = inData;
      final ok = CryptUnprotectData(inBlob, nullptr, nullptr, nullptr,
          nullptr, _cryptProtectUiForbidden, outBlob,);
      if (ok == 0) {
        throw StateError(
            'CryptUnprotectData failed (code=${GetLastError()})',);
      }
      return Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),);
    } finally {
      if (outBlob.ref.pbData != nullptr) {
        LocalFree(outBlob.ref.pbData);
      }
      calloc.free(inData);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }
}

// ---------------------------------------------------------------------------
// AES-256-GCM file vault (fallback / non-Windows).
// ---------------------------------------------------------------------------

class AesFileVault implements SecureVault {
  AesFileVault(this.file, this.keyFile);

  final File file;
  final File keyFile;
  encrypt.Encrypter? _encrypter;

  @override
  bool get usesDpapi => false;

  @override
  String get backendName => 'AES-256-GCM';

  Future<void> init() async {
    final keyBytes = await _loadOrCreateKey();
    _encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
  }

  Future<Uint8List> _loadOrCreateKey() async {
    if (await keyFile.exists()) {
      final stored = base64.decode((await keyFile.readAsString()).trim());
      if (stored.length == 32) return Uint8List.fromList(stored);
    }
    final key = encrypt.Key.fromSecureRandom(32).bytes;
    await keyFile.parent.create(recursive: true);
    await keyFile.writeAsString(base64.encode(key));
    return key;
  }

  encrypt.Encrypter get _enc {
    final encrypter = _encrypter;
    if (encrypter == null) {
      throw StateError('AesFileVault.init() was not called');
    }
    return encrypter;
  }

  Future<Map<String, dynamic>> _readAll() async {
    if (!await file.exists()) return {};
    try {
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<dynamic, dynamic>) return {};
      return decoded.cast<String, dynamic>();
    } on Object {
      return {};
    }
  }

  @override
  Future<void> put(String key, String value) async {
    final entries = await _readAll();
    if (value.isEmpty) {
      entries[key] = '';
    } else {
      final iv = encrypt.IV.fromSecureRandom(12);
      final cipher = _enc.encrypt(value, iv: iv);
      entries[key] = {'iv': iv.base64, 'data': cipher.base64};
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(entries));
  }

  @override
  Future<String?> get(String key) async {
    final entries = await _readAll();
    final stored = entries[key];
    if (stored == null) return null;
    if (stored is String) return stored.isEmpty ? '' : null;
    if (stored is! Map<dynamic, dynamic>) return null;
    try {
      return _enc.decrypt64(
        stored['data'].toString(),
        iv: encrypt.IV.fromBase64(stored['iv'].toString()),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    final entries = await _readAll();
    entries.remove(key);
    await file.writeAsString(json.encode(entries));
  }

  @override
  Future<void> deleteAll() async {
    if (await file.exists()) await file.delete();
  }
}
