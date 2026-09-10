/// Application settings models (pure Dart, JSON-serializable).
library;

enum ThemeModeSetting { system, light, dark }

enum LocaleSetting { system, english, persian }

enum ProxyMode { system, socks, http, tun }

enum RoutingMode { global, direct, proxy, ruleBased }

enum IpPreference { auto, preferIpv4, preferIpv6 }

enum NetworkPreset { stable, balanced, highLatency, unstable }

class InboundSettings {
  const InboundSettings({
    this.socksPort = 10808,
    this.httpPort = 10809,
    this.bindAddress = '127.0.0.1',
    this.enableSocks = true,
    this.enableHttp = true,
    this.socksAuth = false,
    this.socksUsername = '',
  });

  final int socksPort;
  final int httpPort;
  final String bindAddress;
  final bool enableSocks;
  final bool enableHttp;
  final bool socksAuth;
  final String socksUsername;

  InboundSettings copyWith({
    int? socksPort,
    int? httpPort,
    String? bindAddress,
    bool? enableSocks,
    bool? enableHttp,
    bool? socksAuth,
    String? socksUsername,
  }) {
    return InboundSettings(
      socksPort: socksPort ?? this.socksPort,
      httpPort: httpPort ?? this.httpPort,
      bindAddress: bindAddress ?? this.bindAddress,
      enableSocks: enableSocks ?? this.enableSocks,
      enableHttp: enableHttp ?? this.enableHttp,
      socksAuth: socksAuth ?? this.socksAuth,
      socksUsername: socksUsername ?? this.socksUsername,
    );
  }

  Map<String, dynamic> toJson() => {
        'socksPort': socksPort,
        'httpPort': httpPort,
        'bindAddress': bindAddress,
        'enableSocks': enableSocks,
        'enableHttp': enableHttp,
        'socksAuth': socksAuth,
        'socksUsername': socksUsername,
      };

  factory InboundSettings.fromJson(Map<String, dynamic> json) {
    int intOr(String key, int fallback) =>
        (json[key] as num?)?.toInt() ?? fallback;
    return InboundSettings(
      socksPort: intOr('socksPort', 10808),
      httpPort: intOr('httpPort', 10809),
      bindAddress: (json['bindAddress'] ?? '127.0.0.1').toString(),
      enableSocks: json['enableSocks'] != false,
      enableHttp: json['enableHttp'] != false,
      socksAuth: json['socksAuth'] == true,
      socksUsername: (json['socksUsername'] ?? '').toString(),
    );
  }
}

class DnsSettings {
  const DnsSettings({
    this.servers = const ['8.8.8.8', '1.1.1.1'],
    this.useSystemDns = false,
    this.enableDoh = false,
    this.dohUrl = 'https://dns.google/dns-query',
    this.queryTimeoutSeconds = 5,
    this.disableIpv6 = false,
  });

  final List<String> servers;
  final bool useSystemDns;
  final bool enableDoh;
  final String dohUrl;
  final int queryTimeoutSeconds;
  final bool disableIpv6;

  DnsSettings copyWith({
    List<String>? servers,
    bool? useSystemDns,
    bool? enableDoh,
    String? dohUrl,
    int? queryTimeoutSeconds,
    bool? disableIpv6,
  }) {
    return DnsSettings(
      servers: servers ?? this.servers,
      useSystemDns: useSystemDns ?? this.useSystemDns,
      enableDoh: enableDoh ?? this.enableDoh,
      dohUrl: dohUrl ?? this.dohUrl,
      queryTimeoutSeconds: queryTimeoutSeconds ?? this.queryTimeoutSeconds,
      disableIpv6: disableIpv6 ?? this.disableIpv6,
    );
  }

  Map<String, dynamic> toJson() => {
        'servers': servers,
        'useSystemDns': useSystemDns,
        'enableDoh': enableDoh,
        'dohUrl': dohUrl,
        'queryTimeoutSeconds': queryTimeoutSeconds,
        'disableIpv6': disableIpv6,
      };

  factory DnsSettings.fromJson(Map<String, dynamic> json) {
    return DnsSettings(
      servers: (json['servers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const ['8.8.8.8', '1.1.1.1'],
      useSystemDns: json['useSystemDns'] == true,
      enableDoh: json['enableDoh'] == true,
      dohUrl: (json['dohUrl'] ?? 'https://dns.google/dns-query').toString(),
      queryTimeoutSeconds: (json['queryTimeoutSeconds'] as num?)?.toInt() ?? 5,
      disableIpv6: json['disableIpv6'] == true,
    );
  }
}

class RoutingRule {
  const RoutingRule({
    required this.id,
    required this.name,
    required this.outbound,
    this.domains = const [],
    this.ips = const [],
    this.ports = const [],
    this.protocols = const [],
    this.enabled = true,
  });

  /// [outbound]: 'proxy' | 'direct' | 'block'.
  final String id;
  final String name;
  final String outbound;
  final List<String> domains;
  final List<String> ips;
  final List<String> ports;
  final List<String> protocols;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'outbound': outbound,
        'domains': domains,
        'ips': ips,
        'ports': ports,
        'protocols': protocols,
        'enabled': enabled,
      };

  factory RoutingRule.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) =>
        (json[key] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
    return RoutingRule(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      outbound: (json['outbound'] ?? 'proxy').toString(),
      domains: list('domains'),
      ips: list('ips'),
      ports: list('ports'),
      protocols: list('protocols'),
      enabled: json['enabled'] != false,
    );
  }
}

class RoutingSettings {
  const RoutingSettings({
    this.mode = RoutingMode.global,
    this.rules = const [],
    this.bypassIran = false,
    this.bypassLan = true,
  });

  final RoutingMode mode;
  final List<RoutingRule> rules;
  final bool bypassIran;
  final bool bypassLan;

  RoutingSettings copyWith({
    RoutingMode? mode,
    List<RoutingRule>? rules,
    bool? bypassIran,
    bool? bypassLan,
  }) {
    return RoutingSettings(
      mode: mode ?? this.mode,
      rules: rules ?? this.rules,
      bypassIran: bypassIran ?? this.bypassIran,
      bypassLan: bypassLan ?? this.bypassLan,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'rules': rules.map((r) => r.toJson()).toList(),
        'bypassIran': bypassIran,
        'bypassLan': bypassLan,
      };

  factory RoutingSettings.fromJson(Map<String, dynamic> json) {
    RoutingMode modeFrom(String? name) => RoutingMode.values.firstWhere(
          (m) => m.name == name,
          orElse: () => RoutingMode.global,
        );
    return RoutingSettings(
      mode: modeFrom(json['mode']?.toString()),
      rules: (json['rules'] as List<dynamic>?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((m) => RoutingRule.fromJson(m.cast<String, dynamic>()))
              .toList() ??
          const [],
      bypassIran: json['bypassIran'] == true,
      bypassLan: json['bypassLan'] != false,
    );
  }
}

class NetworkTuning {
  const NetworkTuning({
    this.preset = NetworkPreset.balanced,
    this.ipPreference = IpPreference.auto,
    this.connectionTimeoutSeconds = 10,
    this.dnsTimeoutSeconds = 5,
    this.maxRetries = 2,
    this.retryBackoffMs = 1000,
    this.enableKeepAlive = true,
    this.keepAliveIntervalSeconds = 30,
    this.enableUdp = true,
    this.mtu,
    this.tcpKeepAlive = true,
  });

  final NetworkPreset preset;
  final IpPreference ipPreference;
  final int connectionTimeoutSeconds;
  final int dnsTimeoutSeconds;
  final int maxRetries;
  final int retryBackoffMs;
  final bool enableKeepAlive;
  final int keepAliveIntervalSeconds;
  final bool enableUdp;
  final int? mtu;
  final bool tcpKeepAlive;

  /// Engineering presets: each maps to concrete core/socket parameters in
  /// [XrayConfigBuilder]. Documented in Settings UI; nothing is magic.
  factory NetworkTuning.fromPreset(NetworkPreset preset) {
    return switch (preset) {
      NetworkPreset.stable => const NetworkTuning(
          preset: NetworkPreset.stable,
          connectionTimeoutSeconds: 8,
          dnsTimeoutSeconds: 4,
          maxRetries: 1,
          retryBackoffMs: 500,
          keepAliveIntervalSeconds: 60,
        ),
      NetworkPreset.balanced => const NetworkTuning(),
      NetworkPreset.highLatency => const NetworkTuning(
          preset: NetworkPreset.highLatency,
          connectionTimeoutSeconds: 20,
          dnsTimeoutSeconds: 10,
          maxRetries: 3,
          retryBackoffMs: 2000,
          keepAliveIntervalSeconds: 20,
        ),
      NetworkPreset.unstable => const NetworkTuning(
          preset: NetworkPreset.unstable,
          ipPreference: IpPreference.preferIpv4,
          connectionTimeoutSeconds: 30,
          dnsTimeoutSeconds: 12,
          maxRetries: 5,
          retryBackoffMs: 3000,
          keepAliveIntervalSeconds: 15,
        ),
    };
  }

  NetworkTuning copyWith({
    NetworkPreset? preset,
    IpPreference? ipPreference,
    int? connectionTimeoutSeconds,
    int? dnsTimeoutSeconds,
    int? maxRetries,
    int? retryBackoffMs,
    bool? enableKeepAlive,
    int? keepAliveIntervalSeconds,
    bool? enableUdp,
    int? mtu,
    bool? tcpKeepAlive,
  }) {
    return NetworkTuning(
      preset: preset ?? this.preset,
      ipPreference: ipPreference ?? this.ipPreference,
      connectionTimeoutSeconds: connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      dnsTimeoutSeconds: dnsTimeoutSeconds ?? this.dnsTimeoutSeconds,
      maxRetries: maxRetries ?? this.maxRetries,
      retryBackoffMs: retryBackoffMs ?? this.retryBackoffMs,
      enableKeepAlive: enableKeepAlive ?? this.enableKeepAlive,
      keepAliveIntervalSeconds: keepAliveIntervalSeconds ?? this.keepAliveIntervalSeconds,
      enableUdp: enableUdp ?? this.enableUdp,
      mtu: mtu ?? this.mtu,
      tcpKeepAlive: tcpKeepAlive ?? this.tcpKeepAlive,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'ipPreference': ipPreference.name,
        'connectionTimeoutSeconds': connectionTimeoutSeconds,
        'dnsTimeoutSeconds': dnsTimeoutSeconds,
        'maxRetries': maxRetries,
        'retryBackoffMs': retryBackoffMs,
        'enableKeepAlive': enableKeepAlive,
        'keepAliveIntervalSeconds': keepAliveIntervalSeconds,
        'enableUdp': enableUdp,
        'mtu': mtu,
        'tcpKeepAlive': tcpKeepAlive,
      };

  factory NetworkTuning.fromJson(Map<String, dynamic> json) {
    T enumOr<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    int intOr(String key, int fallback) => (json[key] as num?)?.toInt() ?? fallback;
    return NetworkTuning(
      preset: enumOr(NetworkPreset.values, json['preset']?.toString(), NetworkPreset.balanced),
      ipPreference: enumOr(IpPreference.values, json['ipPreference']?.toString(), IpPreference.auto),
      connectionTimeoutSeconds: intOr('connectionTimeoutSeconds', 10),
      dnsTimeoutSeconds: intOr('dnsTimeoutSeconds', 5),
      maxRetries: intOr('maxRetries', 2),
      retryBackoffMs: intOr('retryBackoffMs', 1000),
      enableKeepAlive: json['enableKeepAlive'] != false,
      keepAliveIntervalSeconds: intOr('keepAliveIntervalSeconds', 30),
      enableUdp: json['enableUdp'] != false,
      mtu: (json['mtu'] as num?)?.toInt(),
      tcpKeepAlive: json['tcpKeepAlive'] != false,
    );
  }
}

class AppSettings {
  const AppSettings({
    this.theme = ThemeModeSetting.system,
    this.locale = LocaleSetting.system,
    this.startWithWindows = false,
    this.startMinimized = false,
    this.autoConnect = false,
    this.proxyMode = ProxyMode.system,
    this.activeProfileId = '',
    this.inbounds = const InboundSettings(),
    this.dns = const DnsSettings(),
    this.routing = const RoutingSettings(),
    this.tuning = const NetworkTuning(),
    this.enableStatsApi = true,
    this.statsPort = 10810,
    this.logLevel = 'info',
    this.preferLegacyCore = false,
    this.checkUpdatesOnStartup = true,
    this.minimizeToTray = true,
    this.confirmBeforeQuit = false,
  });

  final ThemeModeSetting theme;
  final LocaleSetting locale;
  final bool startWithWindows;
  final bool startMinimized;
  final bool autoConnect;
  final ProxyMode proxyMode;
  final String activeProfileId;
  final InboundSettings inbounds;
  final DnsSettings dns;
  final RoutingSettings routing;
  final NetworkTuning tuning;
  final bool enableStatsApi;
  final int statsPort;
  final String logLevel;
  final bool preferLegacyCore;
  final bool checkUpdatesOnStartup;
  final bool minimizeToTray;
  final bool confirmBeforeQuit;

  AppSettings copyWith({
    ThemeModeSetting? theme,
    LocaleSetting? locale,
    bool? startWithWindows,
    bool? startMinimized,
    bool? autoConnect,
    ProxyMode? proxyMode,
    String? activeProfileId,
    InboundSettings? inbounds,
    DnsSettings? dns,
    RoutingSettings? routing,
    NetworkTuning? tuning,
    bool? enableStatsApi,
    int? statsPort,
    String? logLevel,
    bool? preferLegacyCore,
    bool? checkUpdatesOnStartup,
    bool? minimizeToTray,
    bool? confirmBeforeQuit,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      locale: locale ?? this.locale,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      startMinimized: startMinimized ?? this.startMinimized,
      autoConnect: autoConnect ?? this.autoConnect,
      proxyMode: proxyMode ?? this.proxyMode,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      inbounds: inbounds ?? this.inbounds,
      dns: dns ?? this.dns,
      routing: routing ?? this.routing,
      tuning: tuning ?? this.tuning,
      enableStatsApi: enableStatsApi ?? this.enableStatsApi,
      statsPort: statsPort ?? this.statsPort,
      logLevel: logLevel ?? this.logLevel,
      preferLegacyCore: preferLegacyCore ?? this.preferLegacyCore,
      checkUpdatesOnStartup: checkUpdatesOnStartup ?? this.checkUpdatesOnStartup,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      confirmBeforeQuit: confirmBeforeQuit ?? this.confirmBeforeQuit,
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'locale': locale.name,
        'startWithWindows': startWithWindows,
        'startMinimized': startMinimized,
        'autoConnect': autoConnect,
        'proxyMode': proxyMode.name,
        'activeProfileId': activeProfileId,
        'inbounds': inbounds.toJson(),
        'dns': dns.toJson(),
        'routing': routing.toJson(),
        'tuning': tuning.toJson(),
        'enableStatsApi': enableStatsApi,
        'statsPort': statsPort,
        'logLevel': logLevel,
        'preferLegacyCore': preferLegacyCore,
        'checkUpdatesOnStartup': checkUpdatesOnStartup,
        'minimizeToTray': minimizeToTray,
        'confirmBeforeQuit': confirmBeforeQuit,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    T enumOr<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    Map<String, dynamic> sub(String key) =>
        (json[key] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? const {};
    return AppSettings(
      theme: enumOr(ThemeModeSetting.values, json['theme']?.toString(), ThemeModeSetting.system),
      locale: enumOr(LocaleSetting.values, json['locale']?.toString(), LocaleSetting.system),
      startWithWindows: json['startWithWindows'] == true,
      startMinimized: json['startMinimized'] == true,
      autoConnect: json['autoConnect'] == true,
      proxyMode: enumOr(ProxyMode.values, json['proxyMode']?.toString(), ProxyMode.system),
      activeProfileId: (json['activeProfileId'] ?? '').toString(),
      inbounds: InboundSettings.fromJson(sub('inbounds')),
      dns: DnsSettings.fromJson(sub('dns')),
      routing: RoutingSettings.fromJson(sub('routing')),
      tuning: NetworkTuning.fromJson(sub('tuning')),
      enableStatsApi: json['enableStatsApi'] != false,
      statsPort: (json['statsPort'] as num?)?.toInt() ?? 10810,
      logLevel: (json['logLevel'] ?? 'info').toString(),
      preferLegacyCore: json['preferLegacyCore'] == true,
      checkUpdatesOnStartup: json['checkUpdatesOnStartup'] != false,
      minimizeToTray: json['minimizeToTray'] != false,
      confirmBeforeQuit: json['confirmBeforeQuit'] == true,
    );
  }
}
