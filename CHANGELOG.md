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

### Fixed
- Release workflow: the "Validate version input" step failed with "Process
  completed with exit code 1" and no error output whenever the release tag did
  not yet exist. Root cause: the GitHub Actions pwsh wrapper appends
  `exit $LASTEXITCODE` to every step script (and pwsh `-Command` normalizes
  non-0/1 exit codes to 1), while `git ls-remote --exit-code` deliberately
  exits 2 when no tag matches — so the healthy path was reported as failure.
  The step now ends with an explicit `exit 0`, keeps `$ErrorActionPreference`
  at `Continue` around the stderr redirection, and treats unexpected
  `ls-remote` exit codes (network/credentials) as hard errors instead of
  silently continuing.
- CI/release: `flutter analyze` failed on the pinned Flutter 3.19.6 / Dart 3.3
  toolchain — Dart-3.7-only wildcard parameters `(_, _, _)`, the Flutter-3.22
  `ColorScheme.surfaceContainerHighest` API, `LogService.debug/info` calls
  passing an `error:` parameter the methods did not accept, a protobuf
  `clone()` calling a non-existent unnamed constructor, and two unused
  imports.
- CI: analyze-failure annotations now report findings 10–18 as well
  (previously only the first 9 were surfaced, hiding part of the list).

## [0.1.0] - TBD
- First internal development snapshot (not released).

[Unreleased]: https://github.com/DnsChangerPM/V2rayN/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DnsChangerPM/V2rayN/releases/tag/v0.1.0
