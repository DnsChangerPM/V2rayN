import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/profile.dart';
import 'link_parser.dart';

/// Result of a subscription update.
class SubscriptionResult {
  SubscriptionResult({
    required this.profiles,
    this.usedBytes,
    this.totalBytes,
    this.expireAt,
    this.error,
  });

  final List<Profile> profiles;
  final int? usedBytes;
  final int? totalBytes;
  final DateTime? expireAt;
  final String? error;

  bool get isSuccess => error == null;
}

/// Downloads and decodes a subscription.
class SubscriptionClient {
  SubscriptionClient({this.userAgent = 'Radin'});

  String userAgent;

  Future<SubscriptionResult> fetch(
    String rawUrl, {
    String? subscriptionId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return SubscriptionResult(
        profiles: const <Profile>[],
        error: 'نشانی سابسکریپشن معتبر نیست.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent
      // Subscription panels in Iran very often serve self signed or expired
      // certificates; refusing to connect would make the app unusable.
      ..badCertificateCallback = (_, __, ___) => true;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate, identity');
      final response = await request.close().timeout(timeout);

      if (response.statusCode >= 400) {
        return SubscriptionResult(
          profiles: const <Profile>[],
          error: 'سرور پاسخ ${response.statusCode} برگرداند.',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final profiles = LinkParser.parseSubscription(
        body,
        subscriptionId: subscriptionId,
      );

      return SubscriptionResult(
        profiles: profiles,
        usedBytes: _subscriptionUserInfo(response)['upload'],
        totalBytes: _subscriptionUserInfo(response)['download'] != null
            ? _subscriptionUserInfo(response)['total']
            : null,
        expireAt: _parseExpire(_subscriptionUserInfo(response)['expire']),
      );
    } on TimeoutException {
      return SubscriptionResult(
        profiles: const <Profile>[],
        error: 'دریافت سابسکریپشن زمان‌بر شد (timeout).',
      );
    } on Object catch (error) {
      return SubscriptionResult(
        profiles: const <Profile>[],
        error: 'خطا در دریافت سابسکریپشن: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Parses the `subscription-userinfo` header, e.g.
  /// `upload=1234; download=5678; total=10737418240; expire=1735689600`.
  static Map<String, int> _subscriptionUserInfo(HttpClientResponse response) {
    final raw = response.headers.value('subscription-userinfo');
    final result = <String, int>{};
    if (raw == null) {
      return result;
    }
    for (final part in raw.split(';')) {
      final pair = part.trim().split('=');
      if (pair.length != 2) {
        continue;
      }
      final value = int.tryParse(pair[1].trim());
      if (value != null) {
        result[pair[0].trim().toLowerCase()] = value;
      }
    }
    return result;
  }

  static DateTime? _parseExpire(int? seconds) {
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}
