/// Enumerations shared by the configuration model and the UI.
library;

/// Which core binary should run the connection.
enum CoreType {
  xray('xray', 'Xray-core'),
  v2ray('v2ray', 'V2Ray-core');

  const CoreType(this.id, this.label);
  final String id;
  final String label;
}

/// Outbound protocol of a server profile.
enum ProtocolType {
  vless('vless'),
  vmess('vmess'),
  trojan('trojan'),
  shadowsocks('shadowsocks');

  const ProtocolType(this.id);
  final String id;

  static ProtocolType? tryParse(String? value) {
    final id = (value ?? '').toLowerCase();
    for (final protocol in values) {
      if (protocol.id == id) {
        return protocol;
      }
    }
    return null;
  }
}

/// Transport layer (Xray calls it `network`).
enum TransportType {
  tcp('tcp'),
  ws('ws'),
  grpc('grpc'),
  h2('h2'),
  quic('quic'),
  httpupgrade('httpupgrade'),
  xhttp('xhttp');

  const TransportType(this.id);
  final String id;

  static TransportType? tryParse(String? value) {
    final id = (value ?? '').toLowerCase().trim();
    for (final transport in values) {
      if (transport.id == id) {
        return transport;
      }
    }
    // Common aliases seen in subscription links.
    switch (id) {
      case 'websocket':
        return ws;
      case 'h2c':
      case 'http/2':
        return h2;
      case 'httpupgrade':
      case 'http-upgrade':
        return httpupgrade;
      case 'splithttp':
        return xhttp;
      default:
        return null;
    }
  }

  bool get needsHost => this == ws || this == h2 || this == httpupgrade;
  bool get needsPath => this == ws || this == grpc || this == h2 || this == httpupgrade;
}

/// TLS layer of the outbound.
enum SecurityType {
  none('none'),
  tls('tls'),
  reality('reality');

  const SecurityType(this.id);
  final String id;

  static SecurityType? tryParse(String? value) {
    switch ((value ?? '').toLowerCase().trim()) {
      case 'tls':
        return tls;
      case 'reality':
        return reality;
      case 'none':
      case '':
        return none;
      default:
        return null;
    }
  }
}

/// How traffic is routed.
enum RoutingMode {
  /// Everything except LAN goes through the proxy.
  global('global'),

  /// Recommended for Iran: Iranian sites and LAN go direct, everything else
  /// goes through the proxy. Ads are blocked.
  smartIran('smart_iran'),

  /// User supplied rules.
  custom('custom');

  const RoutingMode(this.id);
  final String id;

  static RoutingMode? tryParse(String? value) {
    final id = (value ?? '').toLowerCase();
    for (final mode in values) {
      if (mode.id == id) {
        return mode;
      }
    }
    return null;
  }
}

/// What the client does with the traffic of other applications.
enum ProxyMode {
  /// Windows system proxy (HTTP + SOCKS), no administrator rights needed.
  systemProxy('system_proxy'),

  /// TUN device through tun2socks + Wintun, requires administrator rights.
  tun('tun'),

  /// Both at the same time.
  both('both');

  const ProxyMode(this.id);
  final String id;

  static ProxyMode? tryParse(String? value) {
    final id = (value ?? '').toLowerCase();
    for (final mode in values) {
      if (mode.id == id) {
        return mode;
      }
    }
    return null;
  }

  bool get usesSystemProxy => this == systemProxy || this == both;
  bool get usesTun => this == tun || this == both;
}

/// TLS-hello fragmentation presets (Xray only).
enum FragmentPreset {
  off('off'),

  /// Splits the TLS ClientHello into small chunks - defeats simple DPI boxes.
  tlsHello('tlshello'),

  /// Splits the first few packets of every connection.
  ranged('ranged');

  const FragmentPreset(this.id);
  final String id;

  static FragmentPreset? tryParse(String? value) {
    final id = (value ?? '').toLowerCase();
    for (final preset in values) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }
}

/// Which core build flavour to prefer.
enum CoreFlavour {
  /// Pick Win7 binaries on Windows 7/8, modern binaries on Windows 10/11.
  auto('auto'),

  /// Always use the Windows 7 compatible binaries.
  legacy('legacy'),

  /// Always use the modern (Go >= 1.21) binaries. Windows 10+ only.
  modern('modern');

  const CoreFlavour(this.id);
  final String id;

  static CoreFlavour? tryParse(String? value) {
    final id = (value ?? '').toLowerCase();
    for (final flavour in values) {
      if (flavour.id == id) {
        return flavour;
      }
    }
    return null;
  }
}

/// UI language.
enum AppLanguage {
  persian('fa'),
  english('en'),
  system('system');

  const AppLanguage(this.id);
  final String id;

  static AppLanguage? tryParse(String? value) {
    final id = (value ?? '').toLowerCase();
    for (final language in values) {
      if (language.id == id) {
        return language;
      }
    }
    return null;
  }
}

/// Current state of the connection.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  failed;

  bool get isBusy => this == connecting || this == disconnecting;
}
