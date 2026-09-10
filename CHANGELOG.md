# Changelog

All notable changes to IranLink are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Initial IranLink application scaffold and architecture.
- Xray-core process management (start/stop/restart/health/crash detection).
- Profile management (add/edit/delete/duplicate/groups/search/sort/favorites).
- Subscription manager (add/refresh/cache/auto-refresh, credential-safe logging).
- URI importers: VMess, VLESS, Trojan, Shadowsocks, SOCKS, HTTP.
- QR import from image files (pure-Dart decoder, no camera requirement).
- System proxy management with state restore on disconnect.
- TUN mode behind OS capability detection (Win10+ only, documented).
- Routing modes (global/direct/proxy/rule-based) and DNS manager.
- Diagnostics page, connection tests, best-profile selection, speed test.
- System tray, autostart, single-instance enforcement.
- Dark/light/system themes, Persian (RTL) + English localization.
- Inno Setup installer, portable ZIP, SHA256SUMS, automated release workflow.

## [0.1.0] - TBD
- First internal development snapshot (not released).

[Unreleased]: https://github.com/DnsChangerPM/V2rayN/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DnsChangerPM/V2rayN/releases/tag/v0.1.0
