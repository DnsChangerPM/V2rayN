/// Update checker: GitHub Releases, version compare, no auto-install.
///
/// v1 behavior is deliberately conservative: check + notify + open the
/// release page. Download/install automation is a documented future step.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import '../logging/log_service.dart';
import '../utils/semver.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.releaseUrl,
    required this.isAvailable,
  });

  final SemVersion current;
  final SemVersion latest;
  final String releaseUrl;
  final bool isAvailable;
}

class UpdateService {
  UpdateService({required LogService log, http.Client? client})
      : _log = log,
        _client = client;

  static const releasesApi =
      'https://api.github.com/DnsChangerPM/V2rayN/releases/latest';
  static const releasesPage =
      'https://github.com/DnsChangerPM/V2rayN/releases';

  final LogService _log;
  final http.Client? _client;

  /// Returns null when the check cannot complete (offline, rate-limited…).
  /// Never throws.
  Future<UpdateInfo?> checkForUpdates(
      {Duration timeout = const Duration(seconds: 15)}) async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse(releasesApi),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'IranLink/$kAppVersion',
        },
      ).timeout(timeout);
      if (response.statusCode != 200) {
        _log.warning(
            'update', 'Release check HTTP ${response.statusCode}');
        return null;
      }
      final decoded = json.decode(response.body);
      if (decoded is! Map<dynamic, dynamic>) return null;
      final tag = (decoded['tag_name'] ?? '').toString();
      final latest = SemVersion.tryParse(tag);
      if (latest == null) {
        _log.warning('update', 'Unparseable release tag: $tag');
        return null;
      }
      final current = SemVersion.tryParse(kAppVersion) ??
          const SemVersion(0, 0, 0);
      final url = (decoded['html_url'] ?? releasesPage).toString();
      return UpdateInfo(
        current: current,
        latest: latest,
        releaseUrl: url,
        isAvailable: latest > current,
      );
    } on Object catch (e) {
      _log.warning('update', 'Release check failed', error: e);
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
