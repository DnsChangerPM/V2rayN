# Architecture

IranLink is a Flutter (Dart) desktop application for Windows with a
core-agnostic backend. The UI never spawns processes directly; all core
interaction flows through `CoreManager` → `CoreAdapter` → process.

```
┌────────────────────────────────────────────────────────────┐
│ Flutter UI (screens/widgets)  — Material 3, no logic       │
├────────────────────────────────────────────────────────────┤
│ State (provider) — AppState, ConnectionState, ...          │
├────────────────────────────────────────────────────────────┤
│ Services                                                    │
│  CoreManager  SubscriptionManager  ProxyService  DnsService │
│  RoutingService  DiagnosticsService  UpdateService ...      │
├────────────────────────────────────────────────────────────┤
│ Core abstraction                                            │
│  CoreAdapter (interface)                                    │
│   ├─ XrayCoreAdapter (ships in v1)                         │
│   └─ SingBoxCoreAdapter (future, same interface)           │
├────────────────────────────────────────────────────────────┤
│ Platform layer (Windows)                                    │
│  win32 FFI: proxy, autostart, tray glue, OS detection, DPAPI│
│  runner (C++): single-instance mutex, window bootstrap      │
└────────────────────────────────────────────────────────────┘
```

## Layer rules
1. `screens/` and `widgets/` contain zero business logic; they read state and
   dispatch intents to services via providers.
2. `services/` never import Flutter widgets (`dart:ui` only where unavoidable).
3. `models/` are pure Dart (immutable, `copyWith`, JSON serialization).
4. Blocking work (parsing, hashing, network, process IO) never runs on the UI
   isolate: services use `async`, `Isolate.run()` for heavy parsing, and
   broadcast streams for logs/stats.
5. All user-visible errors are mapped to human-readable messages
   (`AppError` → localized string); technical details go only to the log.
6. Secrets rule: credentials may live in memory and in secure storage only.
   They are never written to logs, crash reports, or `SharedPreferences`-style
   plaintext. See `docs/security.md`.

## Key components

### CoreManager (`lib/src/core/`)
Owns core lifecycle as a state machine:
`stopped → starting → running → stopping → stopped`, plus `crashed` and
`error`. Responsibilities:
- select the right bundled binary for the OS (Win10+ vs Win7/8.1),
- validate config before launch (refuse to start on invalid config),
- spawn + supervise the process, capture stdout/stderr (bounded buffers),
- crash detection with bounded restart attempts (max 3, then stop + report),
- orphan cleanup of previous instances on startup,
- port-conflict detection with actionable errors (incl. owning PID where known).

### CoreAdapter interface
```dart
abstract class CoreAdapter {
  String get coreName;            // 'xray'
  Future<CoreVersion> version();  // `xray version`
  Future<ConfigValidation> validate(String configJson);
  Future<CoreProcess> start(StartRequest request);
}
```
`XrayCoreAdapter` implements this by invoking the bundled `xray.exe`
(`run -c config.json`, `api` stats where enabled). A future
`SingBoxCoreAdapter` plugs in without UI changes.

### Config pipeline
`Profile (model)` → `XrayConfigBuilder` → canonical Xray JSON →
`XrayConfigValidator` (schema + semantic checks: ports, UUIDs, file refs) →
write to a temp file with restricted ACL → launch. Every external config
(paste/URL/file/QR/subscription) passes validation before it can run.

### Storage (`lib/src/storage/`)
- JSON document stores under `%AppData%/IranLink/` (profiles, subscriptions,
  settings, cache) with `schemaVersion` + migrations.
- Secrets (UUIDs, passwords, tokens, subscription URLs) in `SecureVault`:
  DPAPI-protected via `win32` (`CryptProtectData`, machine+user scope) with an
  AES-256 fallback file (key derived per-installation) if DPAPI is unavailable.
  Fallback usage is logged (without secrets) and surfaced in Diagnostics.

### Subscription pipeline
Fetch (timeout + retry + cancellation) → parse in an isolate (base64/URI/JSON
lists) → diff against cached set → atomic replace; on failure the last good
snapshot is kept and the error is recorded with the subscription row.

### Logging (`lib/src/logging/`)
Leveled (`debug/info/warning/error`), sanitized (`LogSanitizer` redacts UUIDs,
tokens, passwords, subscription query strings), bounded in-memory ring +
rotating files (`iranlink.log`, max 5 × 2 MiB). Core stdout/stderr are piped
through the same sanitizer.

## Threading model
- UI isolate: widgets + providers only.
- `Isolate.run()`: subscription parsing, QR decode, large imports, checksum
  verification.
- Long-lived background: `CoreSupervisor` stream loop, stats sampler
  (1 Hz, cheap), log writer (async queue).
- Cancellation: every network/process operation takes a `CancellationToken`.

## Windows integration points
| Concern        | Implementation                              |
| -------------- | ------------------------------------------- |
| Single instance| Named mutex in `windows/runner/main.cpp`    |
| System proxy   | WinINet `InternetSetOption` via `win32`     |
| Autostart      | `HKCU\...\Run` registry via `win32`         |
| Tray           | `system_tray` plugin                        |
| OS detection   | `RtlGetVersion` via `win32` (unshimmed)     |
| Secure storage | DPAPI `CryptProtectData/Unprotect` via FFI  |
| Elevation      | `ShellExecuteEx` `runas` only for TUN setup |

## Directory map (lib/)
```
lib/
  main.dart                  bootstrap (single-instance, storage, runApp)
  app.dart                   MaterialApp, theme, locale, navigation shell
  src/
    core/        CoreManager, adapters, supervisor, health, ports
    models/      Profile, Subscription, Settings, Routing, Dns, ...
    profiles/    repository, importers (URI/QR/file), exporters
    subscriptions/ manager, fetcher, parsers
    proxy/       system proxy, TUN manager (gated), modes
    routing/     routing + DNS managers, presets
    network/     connectivity/latency tests, stats sampler
    diagnostics/ collectors, report builder
    speedtest/   user-triggered ping/download/upload estimates
    logging/     log service, sanitizer, rotation
    storage/     json stores, migrations, secure vault
    platform/    windows_apis (win32 wrappers), capabilities
    update/      GitHub releases checker
    state/       providers (AppState, Connection, Profiles, ...)
    screens/     dashboard, profiles, subscriptions, speedtest,
                 diagnostics, logs, settings, about, shell
    widgets/     shared UI components
    utils/       semver, validators, formatters
    l10n/        localizations (en/fa), hand-written (no codegen)
    theme/       light/dark themes
```

## Test strategy
- `test/unit/`: pure-Dart tests (parsers, semver, sanitizer, routing,
  repositories with temp dirs, CoreManager with fake adapter).
- `test/widget/`: key flows with fakes (connect/disconnect, import, refresh).
- `integration_test/`: real core lifecycle on Windows runners
  (`flutter test integration_test -d windows`).
