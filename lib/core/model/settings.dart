import 'enums.dart';

/// A subscription (list of servers published as one URL).
class Subscription {
  Subscription({
    String? id,
    this.name = '',
    this.url = '',
    this.enabled = true,
    this.autoUpdate = true,
    this.lastUpdatedAt,
    this.lastError,
    this.serverCount = 0,
    this.usedBytes,
    this.totalBytes,
    this.expireAt,
  }) : id = id ?? 's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  final String id;
  String name;
  String url;
  bool enabled;
  bool autoUpdate;
  DateTime? lastUpdatedAt;
  String? lastError;
  int serverCount;

  /// Traffic information parsed from the `subscription-userinfo` header.
  int? usedBytes;
  int? totalBytes;
  DateTime? expireAt;

  Subscription copyWith({
    String? name,
    String? url,
    bool? enabled,
    bool? autoUpdate,
    DateTime? lastUpdatedAt,
    String? lastError,
    int? serverCount,
    int? usedBytes,
    int? totalBytes,
    DateTime? expireAt,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        enabled: enabled ?? this.enabled,
        autoUpdate: autoUpdate ?? this.autoUpdate,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
        lastError: lastError ?? this.lastError,
        serverCount: serverCount ?? this.serverCount,
        usedBytes: usedBytes ?? this.usedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        expireAt: expireAt ?? this.expireAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        'autoUpdate': autoUpdate,
        if (lastUpdatedAt != null)
          'lastUpdatedAt': lastUpdatedAt!.millisecondsSinceEpoch,
        if (lastError != null) 'lastError': lastError,
        'serverCount': serverCount,
        if (usedBytes != null) 'usedBytes': usedBytes,
        if (totalBytes != null) 'totalBytes': totalBytes,
        if (expireAt != null) 'expireAt': expireAt!.millisecondsSinceEpoch,
      };

  static Subscription fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        autoUpdate: json['autoUpdate'] as bool? ?? true,
        lastUpdatedAt: json['lastUpdatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['lastUpdatedAt'] as num).toInt())
            : null,
        lastError: json['lastError'] as String?,
        serverCount: (json['serverCount'] as num?)?.toInt() ?? 0,
        usedBytes: (json['usedBytes'] as num?)?.toInt(),
        totalBytes: (json['totalBytes'] as num?)?.toInt(),
        expireAt: json['expireAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['expireAt'] as num).toInt())
            : null,
      );
}

/// Persisted application settings.
///
/// The defaults are chosen for Iran: IPv4 only DNS (IPv6 is broken or absent on
/// most Iranian ISPs), Iranian domains routed directly, QUIC blocked (UDP 443
/// is heavily throttled) and mux disabled (it collapses on lossy links).
class AppSettings {
  AppSettings({
    this.coreType = CoreType.xray,
    this.coreFlavour = CoreFlavour.auto,
    this.routingMode = RoutingMode.smartIran,
    this.proxyMode = ProxyMode.systemProxy,
    this.httpPort = 2080,
    this.socksPort = 2081,
    this.apiPort = 2085,
    this.allowLan = false,
    this.enableFragment = false,
    this.fragmentLength = '10-20',
    this.fragmentInterval = '5-10',
    this.blockQuic = true,
    this.muxEnabled = false,
    this.dnsRemoteDoh = 'https://1.1.1.1/dns-query',
    this.dnsIran = '178.22.122.100',
    this.dnsUseIpv4Only = true,
    this.enableDnsCache = true,
    this.blockAds = true,
    this.bypassIran = true,
    this.customBypassDomains = const <String>[],
    this.customProxyDomains = const <String>[],
    this.customRulesJson = '',
    this.autoSelectFastest = false,
    this.probeUrl = 'https://www.gstatic.com/generate_204',
    this.probeIntervalSeconds = 30,
    this.tunEnabled = false,
    this.tunName = 'radin-tun',
    this.tunAddress = '10.255.0.2/24',
    this.tunGateway = '10.255.0.1',
    this.tunMtu = 1420,
    this.tunDns = '1.1.1.1',
    this.tunAutoRoute = true,
    this.startMinimized = false,
    this.closeToTray = true,
    this.autoStartEnabled = false,
    this.autoConnect = false,
    this.autoReconnect = true,
    this.language = AppLanguage.system,
    this.themeMode = 'system',
    this.logLevel = 'warning',
    this.maxLogLines = 500,
    this.subscriptionUserAgent = 'Radin',
    this.checkForUpdates = true,
    this.selectedProfileId,
  });

  // -- core -----------------------------------------------------------------
  CoreType coreType;
  CoreFlavour coreFlavour;

  // -- routing --------------------------------------------------------------
  RoutingMode routingMode;
  ProxyMode proxyMode;

  // -- ports ----------------------------------------------------------------
  int httpPort;
  int socksPort;
  int apiPort;
  bool allowLan;

  // -- DPI / performance ----------------------------------------------------
  bool enableFragment;
  String fragmentLength;
  String fragmentInterval;
  bool blockQuic;
  bool muxEnabled;

  // -- DNS ------------------------------------------------------------------
  String dnsRemoteDoh;
  String dnsIran;
  bool dnsUseIpv4Only;
  bool enableDnsCache;

  // -- rules ----------------------------------------------------------------
  bool blockAds;
  bool bypassIran;
  List<String> customBypassDomains;
  List<String> customProxyDomains;

  /// Raw JSON array of extra routing rules (`RoutingMode.custom`).
  String customRulesJson;

  // -- balancing ------------------------------------------------------------
  bool autoSelectFastest;
  String probeUrl;
  int probeIntervalSeconds;

  // -- TUN ------------------------------------------------------------------
  bool tunEnabled;
  String tunName;
  String tunAddress;
  String tunGateway;
  int tunMtu;
  String tunDns;
  bool tunAutoRoute;

  // -- behaviour ------------------------------------------------------------
  bool startMinimized;
  bool closeToTray;
  bool autoStartEnabled;
  bool autoConnect;
  bool autoReconnect;

  // -- ui -------------------------------------------------------------------
  AppLanguage language;
  String themeMode;
  String logLevel;
  int maxLogLines;

  // -- subscription ---------------------------------------------------------
  String subscriptionUserAgent;
  bool checkForUpdates;

  String? selectedProfileId;

  AppSettings copyWith({
    CoreType? coreType,
    CoreFlavour? coreFlavour,
    RoutingMode? routingMode,
    ProxyMode? proxyMode,
    int? httpPort,
    int? socksPort,
    int? apiPort,
    bool? allowLan,
    bool? enableFragment,
    String? fragmentLength,
    String? fragmentInterval,
    bool? blockQuic,
    bool? muxEnabled,
    String? dnsRemoteDoh,
    String? dnsIran,
    bool? dnsUseIpv4Only,
    bool? enableDnsCache,
    bool? blockAds,
    bool? bypassIran,
    List<String>? customBypassDomains,
    List<String>? customProxyDomains,
    String? customRulesJson,
    bool? autoSelectFastest,
    String? probeUrl,
    int? probeIntervalSeconds,
    bool? tunEnabled,
    String? tunName,
    String? tunAddress,
    String? tunGateway,
    int? tunMtu,
    String? tunDns,
    bool? tunAutoRoute,
    bool? startMinimized,
    bool? closeToTray,
    bool? autoStartEnabled,
    bool? autoConnect,
    bool? autoReconnect,
    AppLanguage? language,
    String? themeMode,
    String? logLevel,
    int? maxLogLines,
    String? subscriptionUserAgent,
    bool? checkForUpdates,
    String? selectedProfileId,
  }) =>
      AppSettings(
        coreType: coreType ?? this.coreType,
        coreFlavour: coreFlavour ?? this.coreFlavour,
        routingMode: routingMode ?? this.routingMode,
        proxyMode: proxyMode ?? this.proxyMode,
        httpPort: httpPort ?? this.httpPort,
        socksPort: socksPort ?? this.socksPort,
        apiPort: apiPort ?? this.apiPort,
        allowLan: allowLan ?? this.allowLan,
        enableFragment: enableFragment ?? this.enableFragment,
        fragmentLength: fragmentLength ?? this.fragmentLength,
        fragmentInterval: fragmentInterval ?? this.fragmentInterval,
        blockQuic: blockQuic ?? this.blockQuic,
        muxEnabled: muxEnabled ?? this.muxEnabled,
        dnsRemoteDoh: dnsRemoteDoh ?? this.dnsRemoteDoh,
        dnsIran: dnsIran ?? this.dnsIran,
        dnsUseIpv4Only: dnsUseIpv4Only ?? this.dnsUseIpv4Only,
        enableDnsCache: enableDnsCache ?? this.enableDnsCache,
        blockAds: blockAds ?? this.blockAds,
        bypassIran: bypassIran ?? this.bypassIran,
        customBypassDomains: customBypassDomains ?? this.customBypassDomains,
        customProxyDomains: customProxyDomains ?? this.customProxyDomains,
        customRulesJson: customRulesJson ?? this.customRulesJson,
        autoSelectFastest: autoSelectFastest ?? this.autoSelectFastest,
        probeUrl: probeUrl ?? this.probeUrl,
        probeIntervalSeconds: probeIntervalSeconds ?? this.probeIntervalSeconds,
        tunEnabled: tunEnabled ?? this.tunEnabled,
        tunName: tunName ?? this.tunName,
        tunAddress: tunAddress ?? this.tunAddress,
        tunGateway: tunGateway ?? this.tunGateway,
        tunMtu: tunMtu ?? this.tunMtu,
        tunDns: tunDns ?? this.tunDns,
        tunAutoRoute: tunAutoRoute ?? this.tunAutoRoute,
        startMinimized: startMinimized ?? this.startMinimized,
        closeToTray: closeToTray ?? this.closeToTray,
        autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
        autoConnect: autoConnect ?? this.autoConnect,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        logLevel: logLevel ?? this.logLevel,
        maxLogLines: maxLogLines ?? this.maxLogLines,
        subscriptionUserAgent:
            subscriptionUserAgent ?? this.subscriptionUserAgent,
        checkForUpdates: checkForUpdates ?? this.checkForUpdates,
        selectedProfileId: selectedProfileId ?? this.selectedProfileId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'coreType': coreType.id,
        'coreFlavour': coreFlavour.id,
        'routingMode': routingMode.id,
        'proxyMode': proxyMode.id,
        'httpPort': httpPort,
        'socksPort': socksPort,
        'apiPort': apiPort,
        'allowLan': allowLan,
        'enableFragment': enableFragment,
        'fragmentLength': fragmentLength,
        'fragmentInterval': fragmentInterval,
        'blockQuic': blockQuic,
        'muxEnabled': muxEnabled,
        'dnsRemoteDoh': dnsRemoteDoh,
        'dnsIran': dnsIran,
        'dnsUseIpv4Only': dnsUseIpv4Only,
        'enableDnsCache': enableDnsCache,
        'blockAds': blockAds,
        'bypassIran': bypassIran,
        'customBypassDomains': customBypassDomains,
        'customProxyDomains': customProxyDomains,
        'customRulesJson': customRulesJson,
        'autoSelectFastest': autoSelectFastest,
        'probeUrl': probeUrl,
        'probeIntervalSeconds': probeIntervalSeconds,
        'tunEnabled': tunEnabled,
        'tunName': tunName,
        'tunAddress': tunAddress,
        'tunGateway': tunGateway,
        'tunMtu': tunMtu,
        'tunDns': tunDns,
        'tunAutoRoute': tunAutoRoute,
        'startMinimized': startMinimized,
        'closeToTray': closeToTray,
        'autoStartEnabled': autoStartEnabled,
        'autoConnect': autoConnect,
        'autoReconnect': autoReconnect,
        'language': language.id,
        'themeMode': themeMode,
        'logLevel': logLevel,
        'maxLogLines': maxLogLines,
        'subscriptionUserAgent': subscriptionUserAgent,
        'checkForUpdates': checkForUpdates,
        if (selectedProfileId != null) 'selectedProfileId': selectedProfileId,
      };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings();
    return AppSettings(
      coreType: CoreType.values.firstWhere(
        (e) => e.id == json['coreType'],
        orElse: () => defaults.coreType,
      ),
      coreFlavour: CoreFlavour.tryParse(json['coreFlavour'] as String?) ??
          defaults.coreFlavour,
      routingMode: RoutingMode.tryParse(json['routingMode'] as String?) ??
          defaults.routingMode,
      proxyMode: ProxyMode.tryParse(json['proxyMode'] as String?) ??
          defaults.proxyMode,
      httpPort: (json['httpPort'] as num?)?.toInt() ?? defaults.httpPort,
      socksPort: (json['socksPort'] as num?)?.toInt() ?? defaults.socksPort,
      apiPort: (json['apiPort'] as num?)?.toInt() ?? defaults.apiPort,
      allowLan: json['allowLan'] as bool? ?? defaults.allowLan,
      enableFragment:
          json['enableFragment'] as bool? ?? defaults.enableFragment,
      fragmentLength:
          json['fragmentLength'] as String? ?? defaults.fragmentLength,
      fragmentInterval:
          json['fragmentInterval'] as String? ?? defaults.fragmentInterval,
      blockQuic: json['blockQuic'] as bool? ?? defaults.blockQuic,
      muxEnabled: json['muxEnabled'] as bool? ?? defaults.muxEnabled,
      dnsRemoteDoh: json['dnsRemoteDoh'] as String? ?? defaults.dnsRemoteDoh,
      dnsIran: json['dnsIran'] as String? ?? defaults.dnsIran,
      dnsUseIpv4Only:
          json['dnsUseIpv4Only'] as bool? ?? defaults.dnsUseIpv4Only,
      enableDnsCache: json['enableDnsCache'] as bool? ?? defaults.enableDnsCache,
      blockAds: json['blockAds'] as bool? ?? defaults.blockAds,
      bypassIran: json['bypassIran'] as bool? ?? defaults.bypassIran,
      customBypassDomains: _stringList(json['customBypassDomains']),
      customProxyDomains: _stringList(json['customProxyDomains']),
      customRulesJson:
          json['customRulesJson'] as String? ?? defaults.customRulesJson,
      autoSelectFastest:
          json['autoSelectFastest'] as bool? ?? defaults.autoSelectFastest,
      probeUrl: json['probeUrl'] as String? ?? defaults.probeUrl,
      probeIntervalSeconds: (json['probeIntervalSeconds'] as num?)?.toInt() ??
          defaults.probeIntervalSeconds,
      tunEnabled: json['tunEnabled'] as bool? ?? defaults.tunEnabled,
      tunName: json['tunName'] as String? ?? defaults.tunName,
      tunAddress: json['tunAddress'] as String? ?? defaults.tunAddress,
      tunGateway: json['tunGateway'] as String? ?? defaults.tunGateway,
      tunMtu: (json['tunMtu'] as num?)?.toInt() ?? defaults.tunMtu,
      tunDns: json['tunDns'] as String? ?? defaults.tunDns,
      tunAutoRoute: json['tunAutoRoute'] as bool? ?? defaults.tunAutoRoute,
      startMinimized:
          json['startMinimized'] as bool? ?? defaults.startMinimized,
      closeToTray: json['closeToTray'] as bool? ?? defaults.closeToTray,
      autoStartEnabled:
          json['autoStartEnabled'] as bool? ?? defaults.autoStartEnabled,
      autoConnect: json['autoConnect'] as bool? ?? defaults.autoConnect,
      autoReconnect: json['autoReconnect'] as bool? ?? defaults.autoReconnect,
      language: AppLanguage.tryParse(json['language'] as String?) ??
          defaults.language,
      themeMode: json['themeMode'] as String? ?? defaults.themeMode,
      logLevel: json['logLevel'] as String? ?? defaults.logLevel,
      maxLogLines: (json['maxLogLines'] as num?)?.toInt() ?? defaults.maxLogLines,
      subscriptionUserAgent: json['subscriptionUserAgent'] as String? ??
          defaults.subscriptionUserAgent,
      checkForUpdates:
          json['checkForUpdates'] as bool? ?? defaults.checkForUpdates,
      selectedProfileId: json['selectedProfileId'] as String?,
    );
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
      : const <String>[];
}
