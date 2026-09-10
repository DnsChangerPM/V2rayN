/// Pre-launch Xray config validation (pure Dart).
///
/// Catches structural problems *before* spawning the core so failures surface
/// as friendly UI errors instead of cryptic process exits. This complements —
/// never replaces — the core's own validation at startup.
library;

import '../utils/validators.dart';
import 'xray_config_builder.dart';

class ConfigIssue {
  const ConfigIssue({required this.messageKey, this.detail = ''});

  /// l10n key for the UI message.
  final String messageKey;

  /// Technical detail (log-only, must already be sanitized by the caller).
  final String detail;
}

class ConfigValidation {
  const ConfigValidation({required this.isValid, this.issues = const []});

  final bool isValid;
  final List<ConfigIssue> issues;
}

class XrayConfigValidator {
  const XrayConfigValidator();

  ConfigValidation validate(Map<String, dynamic> config) {
    final issues = <ConfigIssue>[];

    final inbounds = _asMapList(config['inbounds']);
    final outbounds = _asMapList(config['outbounds']);
    if (inbounds.isEmpty) {
      issues.add(const ConfigIssue(messageKey: 'configErrorNoInbounds'));
    }
    if (outbounds.isEmpty) {
      issues.add(const ConfigIssue(messageKey: 'configErrorNoOutbounds'));
    }

    final tags = <String>{};
    for (final inbound in inbounds) {
      _checkTag(inbound, tags, issues, isInbound: true);
      final port = inbound['port'];
      if (port is! int || !isValidPort(port)) {
        issues.add(ConfigIssue(
            messageKey: 'configErrorBadPort',
            detail: 'inbound ${inbound['tag']} port=$port',),);
      }
      if ((inbound['protocol'] ?? '').toString().isEmpty) {
        issues.add(ConfigIssue(
            messageKey: 'configErrorMissingProtocol',
            detail: 'inbound ${inbound['tag']}',),);
      }
    }
    var hasProxy = false;
    for (final outbound in outbounds) {
      _checkTag(outbound, tags, issues, isInbound: false);
      if ((outbound['protocol'] ?? '').toString().isEmpty) {
        issues.add(ConfigIssue(
            messageKey: 'configErrorMissingProtocol',
            detail: 'outbound ${outbound['tag']}',),);
      }
      if (outbound['tag'] == XrayTags.proxy) hasProxy = true;
      _checkOutboundSettings(outbound, issues);
    }
    if (outbounds.isNotEmpty && !hasProxy) {
      issues.add(const ConfigIssue(messageKey: 'configErrorNoProxyOutbound'));
    }

    final routing = config['routing'];
    if (routing is Map<dynamic, dynamic>) {
      final rules = _asMapList(routing['rules']);
      for (final rule in rules) {
        final target = (rule['outboundTag'] ?? '').toString();
        if (target.isNotEmpty &&
            target != XrayTags.api &&
            !tags.contains(target)) {
          issues.add(ConfigIssue(
              messageKey: 'configErrorUnknownOutbound',
              detail: 'rule -> $target',),);
        }
      }
    }

    final dns = config['dns'];
    if (dns is Map<dynamic, dynamic> && dns['servers'] is List<dynamic>) {
      final servers = (dns['servers'] as List<dynamic>);
      if (servers.isEmpty) {
        issues.add(const ConfigIssue(messageKey: 'configErrorEmptyDns'));
      }
    }

    return ConfigValidation(isValid: issues.isEmpty, issues: issues);
  }

  void _checkTag(Map<String, dynamic> block, Set<String> tags,
      List<ConfigIssue> issues, {required bool isInbound,}) {
    final tag = (block['tag'] ?? '').toString();
    final kind = isInbound ? 'inbound' : 'outbound';
    if (tag.isEmpty) {
      issues.add(ConfigIssue(
          messageKey: 'configErrorMissingTag', detail: kind,),);
    } else if (!tags.add(tag)) {
      issues.add(ConfigIssue(
          messageKey: 'configErrorDuplicateTag', detail: tag,),);
    }
  }

  void _checkOutboundSettings(
      Map<String, dynamic> outbound, List<ConfigIssue> issues,) {
    final protocol = (outbound['protocol'] ?? '').toString();
    if (protocol == 'freedom' || protocol == 'blackhole') return;
    final settings = outbound['settings'];
    if (settings is! Map<dynamic, dynamic> || settings.isEmpty) {
      issues.add(ConfigIssue(
          messageKey: 'configErrorEmptySettings',
          detail: '$protocol ${outbound['tag']}',),);
      return;
    }
    if (protocol == 'vmess' || protocol == 'vless') {
      final vnext = _asMapList(settings['vnext']);
      if (vnext.isEmpty) {
        issues.add(ConfigIssue(
            messageKey: 'configErrorEmptySettings', detail: protocol,),);
        return;
      }
      for (final server in vnext) {
        if ((server['address'] ?? '').toString().isEmpty) {
          issues.add(const ConfigIssue(messageKey: 'configErrorEmptyAddress'));
        }
        final port = server['port'];
        if (port is! int || !isValidPort(port)) {
          issues.add(const ConfigIssue(messageKey: 'configErrorBadPort'));
        }
        if (_asMapList(server['users']).isEmpty) {
          issues.add(ConfigIssue(
              messageKey: 'configErrorEmptyUsers', detail: protocol,),);
        }
      }
    } else if (protocol == 'trojan' ||
        protocol == 'shadowsocks' ||
        protocol == 'socks' ||
        protocol == 'http') {
      final servers = _asMapList(settings['servers']);
      if (servers.isEmpty) {
        issues.add(ConfigIssue(
            messageKey: 'configErrorEmptySettings', detail: protocol,),);
        return;
      }
      for (final server in servers) {
        if ((server['address'] ?? '').toString().isEmpty) {
          issues.add(const ConfigIssue(messageKey: 'configErrorEmptyAddress'));
        }
        final port = server['port'];
        if (port is! int || !isValidPort(port)) {
          issues.add(const ConfigIssue(messageKey: 'configErrorBadPort'));
        }
      }
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List<dynamic>) return [];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }
}
