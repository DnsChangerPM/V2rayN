/// Secret-aware log sanitization (pure Dart).
///
/// Every log sink (file, viewer, diagnostics export, crash info) must pass
/// through [LogSanitizer.sanitize]. The rules are intentionally aggressive:
/// a slightly over-redacted log is always preferable to a leaked credential.
library;

class LogSanitizer {
  LogSanitizer._();

  static final RegExp _uuid = RegExp(
      r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',);

  /// password=..., token: "...", "passwd": "..." etc.
  static final RegExp _secretAssignment = RegExp(
    '([\'"]?(?:password|passwd|pwd|token|secret|api[_-]?key|access[_-]?key|private[_-]?key|uuid|sid|auth)[\'"]?\\s*[:=]\\s*)([\'"]?)([^\\s\'",}\\]]+)',
    caseSensitive: false,
  );

  /// userinfo passwords in URIs: scheme://user:pass@host
  static final RegExp _uriUserInfo = RegExp(r'(://[^/\s:@]+):([^/\s@]+)@');

  /// query strings and fragments of absolute URIs.
  static final RegExp _uriQuery = RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://[^\s?#]+)(\?[^\s#]*)?(#[^\s]*)?');

  /// Long unbroken base64-ish blobs (subscription bodies, tokens, keys).
  static final RegExp _bulkBlob = RegExp(r'[A-Za-z0-9+/=_-]{128,}');

  /// vmess:// / vless:// / trojan:// / ss:// links: keep scheme + host only.
  static final RegExp _proxyUri =
      RegExp(r'\b(vmess|vless|trojan|ss|shadowsocks|socks5?|http)://([^\s#]+)(#[^\s]*)?');

  static String sanitize(String input) {
    var out = input;
    out = out.replaceAllMapped(_proxyUri, (m) {
      final body = m.group(2)!;
      final at = body.lastIndexOf('@');
      final host = at >= 0 ? body.substring(at + 1) : '<payload>';
      return '${m.group(1)}://•••@$host';
    });
    out = out.replaceAllMapped(_uriUserInfo, (m) => '${m.group(1)}:<redacted>@');
    out = out.replaceAllMapped(_uriQuery, (m) {
      final base = m.group(1)!;
      final hadQuery = m.group(2) != null;
      final hadFragment = m.group(3) != null;
      if (!hadQuery && !hadFragment) return base;
      return '$base?<redacted>';
    });
    out = out.replaceAllMapped(
        _secretAssignment, (m) => '${m.group(1)}${m.group(2)}<redacted>',);
    out = out.replaceAll(_uuid, '<redacted-uuid>');
    out = out.replaceAllMapped(
        _bulkBlob, (m) => '<redacted-bulk:${m.group(0)!.length}chars>',);
    return out;
  }

  /// Sanitizes each line; optionally truncates pathological single lines.
  static String sanitizeMultiline(String input, {int maxLineLength = 2000}) {
    final buffer = StringBuffer();
    final lines = input.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = sanitize(lines[i]);
      if (line.length > maxLineLength) {
        line = '${line.substring(0, maxLineLength)}…<truncated>';
      }
      if (i > 0) buffer.writeln();
      buffer.write(line);
    }
    return buffer.toString();
  }
}
