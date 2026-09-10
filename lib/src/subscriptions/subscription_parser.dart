/// Subscription content parsing (pure Dart, isolate-safe).
///
/// Accepts: base64 blob of share-links, plain-text link lists, JSON arrays of
/// links, single share-link. Rejects oversized payloads before parsing.
/// Designed to run inside `Isolate.run()` — no statics, no platform channels.
library;

import 'dart:convert';

import '../models/profile.dart';
import '../profiles/uri_codecs.dart';

/// Hard limits (DoS protection for malicious subscription servers).
const int kMaxSubscriptionBytes = 5 * 1024 * 1024;
const int kMaxSubscriptionLines = 10000;

class ParsedSubscription {
  const ParsedSubscription({required this.profiles, required this.errors});

  final List<ProxyProfile> profiles;
  final List<SubscriptionParseError> errors;
}

class SubscriptionParseError {
  const SubscriptionParseError({required this.line, required this.reason});

  final int line;
  final String reason;

  @override
  String toString() => 'line $line: $reason';
}

/// Parse subscription [content] for [subscriptionId]. Profile ids are
/// deterministic (`<subId>:<index>`) so diffing across refreshes is stable.
/// Throws [SubscriptionTooLargeException] when limits are exceeded.
ParsedSubscription parseSubscriptionContent(
  String content, {
  required String subscriptionId,
  String fallbackNamePrefix = 'profile',
},) {
  if (content.length > kMaxSubscriptionBytes) {
    throw const SubscriptionTooLargeException();
  }
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const ParsedSubscription(profiles: [], errors: []);
  }

  final List<String> lines = _splitLines(trimmed);
  if (lines.length > kMaxSubscriptionLines) {
    throw const SubscriptionTooLargeException();
  }

  final profiles = <ProxyProfile>[];
  final errors = <SubscriptionParseError>[];
  var index = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final profile = parseShareLink(line, newId: () => '$subscriptionId:$index');
    if (profile == null) {
      errors.add(SubscriptionParseError(
          line: i + 1, reason: 'unrecognized or invalid link',),);
      continue;
    }
    profiles.add(profile.copyWith(
      subscriptionId: subscriptionId,
      name: profile.name.isEmpty ? '$fallbackNamePrefix ${index + 1}' : profile.name,
    ),);
    index++;
  }
  return ParsedSubscription(profiles: profiles, errors: errors);
}

List<String> _splitLines(String trimmed) {
  // JSON array of links: ["vless://...", ...]
  if (trimmed.startsWith('[')) {
    try {
      final decoded = json.decode(trimmed);
      if (decoded is List<dynamic>) {
        return decoded.map((e) => e.toString()).toList();
      }
    } on FormatException {
      // fall through to line parsing
    }
  }
  // Base64 blob of newline-joined links (most common).
  if (_looksLikeBase64Blob(trimmed)) {
    try {
      final decoded = decodeBase64Text(trimmed);
      if (decoded.contains('://')) return decoded.split(RegExp(r'\r?\n'));
    } on FormatException {
      // fall through to raw lines
    }
  }
  return trimmed.split(RegExp(r'\r?\n'));
}

bool _looksLikeBase64Blob(String text) {
  if (text.contains('://')) return false;
  final firstLine = text.split(RegExp(r'\r?\n')).first.trim();
  if (firstLine.length < 32) return false;
  return RegExp(r'^[A-Za-z0-9+/=_-]+\s*$').hasMatch(firstLine);
}

class SubscriptionTooLargeException implements Exception {
  const SubscriptionTooLargeException();
  @override
  String toString() => 'Subscription payload exceeds size/line limits';
}
