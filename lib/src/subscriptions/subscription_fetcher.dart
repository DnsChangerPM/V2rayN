/// Subscription HTTP fetcher: timeouts, bounded retries, cancellation.
///
/// Every request carries a connect+read timeout and a [CancellationToken].
/// Retries use exponential backoff with jitter and never exceed [maxAttempts].
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../logging/log_service.dart';
import '../utils/validators.dart';

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const FetchCancelledException();
  }
}

class FetchCancelledException implements Exception {
  const FetchCancelledException();
}

class SubscriptionFetchException implements Exception {
  const SubscriptionFetchException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SubscriptionFetchException($message)';
}

class SubscriptionFetcher {
  SubscriptionFetcher({required LogService log, http.Client? client})
      : _log = log,
        _sharedClient = client;

  final LogService _log;
  final http.Client? _sharedClient;

  Future<String> fetch({
    required Uri url,
    required String userAgent,
    Duration timeout = const Duration(seconds: 15),
    int maxAttempts = 3,
    Duration baseBackoff = const Duration(seconds: 1),
    bool allowInsecure = false,
    CancellationToken? cancellation,
  }) async {
    final random = Random();
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      cancellation?.throwIfCancelled();
      try {
        final body = await _attempt(
          url: url,
          userAgent: userAgent,
          timeout: timeout,
          allowInsecure: allowInsecure,
        );
        _log.info('subscription',
            'Fetched ${maskUrl(url.toString())} (${body.length} chars)',);
        return body;
      } on FetchCancelledException {
        rethrow;
      } on Object catch (e) {
        lastError = e;
        _log.warning('subscription',
            'Fetch attempt $attempt/$maxAttempts failed', error: e,);
        if (attempt < maxAttempts) {
          final backoff = baseBackoff * (1 << (attempt - 1)) +
              Duration(milliseconds: random.nextInt(500));
          await Future<void>.delayed(backoff);
        }
      }
    }
    throw SubscriptionFetchException(
        'Failed after $maxAttempts attempts: $lastError',);
  }

  Future<String> _attempt({
    required Uri url,
    required String userAgent,
    required Duration timeout,
    required bool allowInsecure,
  }) async {
    final client = _sharedClient ?? _createClient(allowInsecure: allowInsecure);
    final ownsClient = _sharedClient == null;
    try {
      final response = await client
          .get(url, headers: {'User-Agent': userAgent})
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw SubscriptionFetchException(
            'HTTP ${response.statusCode}', statusCode: response.statusCode,);
      }
      return response.body;
    } finally {
      if (ownsClient) client.close();
    }
  }

  http.Client _createClient({required bool allowInsecure}) {
    if (!allowInsecure) return http.Client();
    final io = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(io);
  }
}
