/// Profile import pipeline: text / QR image / raw JSON (no UI, no pickers).
///
/// File picking and clipboard access live in the UI layer; this class takes
/// plain strings/bytes so it stays unit-testable. Detected subscription URLs
/// are returned (not auto-added) so the UI can confirm with the user.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:zxing2/zxing2.dart';

import '../logging/log_service.dart';
import '../models/profile.dart';
import '../utils/validators.dart';
import 'profile_repository.dart';
import 'uri_codecs.dart';

class ImportError {
  const ImportError({required this.line, required this.reason});

  final int line;
  final String reason;
}

class ImportResult {
  const ImportResult({
    required this.profiles,
    required this.errors,
    required this.subscriptionUrls,
  },);

  final List<ProxyProfile> profiles;
  final List<ImportError> errors;
  final List<String> subscriptionUrls;

  bool get isEmpty =>
      profiles.isEmpty && errors.isEmpty && subscriptionUrls.isEmpty;
}

class ProfileImporter {
  ProfileImporter({required ProfileRepository repository, required LogService log})
      : _repository = repository,
        _log = log;

  final ProfileRepository _repository;
  final LogService _log;

  /// Parse [text] (pasted links, one per line, or a single link / JSON).
  /// When [persist] is true, parsed profiles are stored in [groupId].
  Future<ImportResult> importText(
    String text, {
    String groupId = '',
    bool persist = true,
  },) async {
    final profiles = <ProxyProfile>[];
    final errors = <ImportError>[];
    final subscriptionUrls = <String>[];

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const ImportResult(profiles: [], errors: [], subscriptionUrls: []);
    }

    // Single raw Xray JSON object.
    if (trimmed.startsWith('{')) {
      final raw = _tryRawJson(trimmed);
      if (raw != null) {
        profiles.add(raw.copyWith(groupId: groupId));
      } else {
        errors.add(const ImportError(line: 1, reason: 'invalid JSON config'));
      }
    } else {
      final lines = trimmed.split(RegExp(r'\r?\n'));
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final profile = parseShareLink(line, newId: _repository.allocateId);
        if (profile != null) {
          profiles.add(profile.copyWith(groupId: groupId));
          continue;
        }
        if (_looksLikeSubscriptionUrl(line)) {
          subscriptionUrls.add(line);
          continue;
        }
        errors.add(ImportError(line: i + 1, reason: 'unrecognized link'));
      }
    }

    if (persist) {
      for (final profile in profiles) {
        await _repository.add(profile);
      }
    }
    _log.info('import',
        'Text import: ${profiles.length} profiles, ${errors.length} errors, '
        '${subscriptionUrls.length} subscription URLs',);
    return ImportResult(
        profiles: profiles, errors: errors, subscriptionUrls: subscriptionUrls,);
  }

  /// Decode a QR code from image [bytes] (PNG/JPEG screenshot or file photo)
  /// and import its payload as text.
  Future<ImportResult> importQrImage(
    Uint8List bytes, {
    String groupId = '',
    bool persist = true,
  },) async {
    final payload = _decodeQr(bytes);
    if (payload == null || payload.trim().isEmpty) {
      _log.warning('import', 'QR decode produced no payload');
      return const ImportResult(
        profiles: [],
        errors: [ImportError(line: 0, reason: 'no QR code found in image')],
        subscriptionUrls: [],
      );
    }
    return importText(payload, groupId: groupId, persist: persist);
  }

  bool _looksLikeSubscriptionUrl(String line) {
    if (!isValidUrl(line)) return false;
    final uri = Uri.parse(line.trim());
    // Proxy-form http(s) links carry userinfo and were handled above.
    return uri.userInfo.isEmpty;
  }

  ProxyProfile? _tryRawJson(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is! Map<dynamic, dynamic>) return null;
      final map = decoded.cast<String, dynamic>();
      final outbounds = map['outbounds'];
      if (outbounds is! List<dynamic> || outbounds.isEmpty) return null;
      return ProxyProfile(
        id: _repository.allocateId(),
        name: 'Raw Xray config',
        protocol: ProxyProtocol.xrayJson,
        rawJson: const JsonEncoder.withIndent('  ').convert(map),
      );
    } on FormatException {
      return null;
    }
  }

  String? _decodeQr(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final width = image.width;
      final height = image.height;
      final argb = Int32List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = image.getPixel(x, y);
          argb[y * width + x] = 0xFF000000 |
              ((pixel.r.toInt() & 0xFF) << 16) |
              ((pixel.g.toInt() & 0xFF) << 8) |
              (pixel.b.toInt() & 0xFF);
        }
      }
      final source = RGBLuminanceSource(width, height, argb);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      return QRCodeReader().decode(bitmap).text;
    } on Object catch (e) {
      _log.warning('import', 'QR decode failed', error: e);
      return null;
    }
  }
}
