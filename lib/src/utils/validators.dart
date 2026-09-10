/// Input validation helpers (pure Dart). Used by importers, the config
/// validator, and form fields. Never throws; returns booleans / error keys.
library;

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final RegExp _ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
final RegExp _domainLabel = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');

bool isValidPort(int port) => port >= 1 && port <= 65535;

bool isValidUuid(String value) => _uuid.hasMatch(value.trim());

/// Accepts IPv4 literals, bracketed-or-bare IPv6, and DNS names. This is a
/// syntax check, not a resolvability check.
bool isValidHost(String value) {
  final host = value.trim();
  if (host.isEmpty || host.length > 253) return false;
  if (_ipv4.hasMatch(host)) {
    return host.split('.').every((part) {
      final n = int.tryParse(part);
      return n != null && n >= 0 && n <= 255;
    });
  }
  if (host.contains(':')) {
    // Bare or bracketed IPv6: let Uri do the strict parsing.
    final probe = host.startsWith('[') ? host : '[$host]';
    return Uri.tryParse('http://$probe/') != null;
  }
  if (host.startsWith('.') || host.endsWith('.') || host.contains('..')) {
    return false;
  }
  return host.split('.').every((label) => _domainLabel.hasMatch(label));
}

bool isValidUrl(String value, {List<String> schemes = const ['http', 'https']}) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.hasAuthority && schemes.contains(uri.scheme);
}

/// Portion of a URL safe to show/log: scheme + host + masked path marker.
String maskUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasAuthority) return '<invalid-url>';
  final hasSecret = uri.hasQuery || uri.hasFragment || uri.pathSegments.isNotEmpty;
  final suffix = hasSecret ? '/•••' : '';
  final user = uri.userInfo.isEmpty ? '' : '${uri.userInfo.split(':').first}@';
  return '${uri.scheme}://$user${uri.host}$suffix';
}
