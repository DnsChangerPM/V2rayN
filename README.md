# IranLink

A modern, lightweight Windows proxy/VPN client built with Flutter, powered by
Xray-core. Clean core-agnostic architecture, full Persian (RTL) + English UI,
system tray, subscriptions, routing/DNS control, diagnostics, and a fully
automated release pipeline.

> **Name status:** “IranLink” is a temporary working name used consistently
> across the app, installer, and docs (`com.parsa.iranlink`).

## Features

- **Profiles** — vmess / vless / trojan / shadowsocks / socks / http + raw
  Xray JSON; groups, search, sort, favorites, QR/file/clipboard import.
- **Subscriptions** — auto-refresh, local cache, per-subscription TLS toggle.
- **Routing & DNS** — global / direct / proxy / rule-based modes, LAN bypass,
  custom DNS with system-DNS and DoH options, per-network tuning presets.
- **System integration** — system proxy with restore-on-exit, SOCKS + HTTP
  inbounds, tray with quick actions, autostart, single instance.
- **TUN mode** — only on Windows 10/11 and only after explicit user consent;
  the option is hidden on Windows 7/8.1.
- **Observability** — live traffic stats, latency, speed test (ping, chain
  latency, throughput), log viewer with level filter, one-click sanitized
  diagnostics export.
- **Security** — DPAPI vault for secrets (AES-256 file fallback, disclosed),
  aggressive log redaction, password-protected backups, no telemetry.
- **i18n** — English + Persian with true RTL layout.

## Compatibility (honest)

| OS | Status |
| -- | ------ |
| Windows 11 (x64) | Supported |
| Windows 10 (x64) | Supported |
| Windows 8.1 (x64) | Partially supported (legacy core, no TUN) |
| Windows 7 SP1, fully updated (x64) | Partially supported (legacy core, no TUN) |

“Supported” = installer runs, app launches, core starts, config validates,
proxy connects — by design. Per-OS test evidence is recorded in
[`docs/verification/`](docs/verification/); until a checklist exists for an
OS, treat its row as design intent backed by upstream support statements, not
tested fact. Full evidence base: [`docs/windows-compatibility.md`](docs/windows-compatibility.md).

## Download

Get the installer or portable ZIP from
[Releases](https://github.com/DnsChangerPM/V2rayN/releases).
Every release ships `SHA256SUMS.txt` — verify before installing:

```powershell
(Get-FileHash IranLink-1.4.2-Windows-x64-Setup.exe -Algorithm SHA256).Hash
# compare with SHA256SUMS.txt
```

No release published yet? Follow [`docs/build.md`](docs/build.md) to build
from source.

## Quick start (users)

1. Install (per-user, no admin needed) or unzip the portable build.
2. Add a profile: **Profiles → Import** (paste a share link, scan a QR image,
   or add a subscription URL under **Subscriptions**).
3. Select it on the **Dashboard** and press **CONNECT**.
4. Your system proxy now routes through the tunnel; press **DISCONNECT** (or
   quit) to restore the previous proxy state.

## Development

```powershell
# pinned toolchain: Flutter 3.19.6, VS2022, Python 3.9+
flutter --version          # must print 3.19.6
$env:XRAY_VERSION = (Select-String '^XRAY_VERSION=(.+)' tooling/versions.env).Matches.Groups[1].Value
python scripts/download_xray.py --xray-version $env:XRAY_VERSION --out third_party/xray
flutter pub get
flutter analyze
flutter test               # unit + widget (ubuntu-safe)
flutter build windows --release
python scripts/stage_bundle.py --xray-dir third_party/xray --bundle build/windows/x64/runner/Release
# headless end-to-end against the real core:
.\build\windows\x64\runner\Release\IranLink.exe --smoke-test --smoke-timeout 120
```

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Xray integration: [`docs/core.md`](docs/core.md)
- Build & installer: [`docs/build.md`](docs/build.md)
- Releases: [`docs/release.md`](docs/release.md) (manual trigger, SemVer input)
- Security model: [`docs/security.md`](docs/security.md)
- Performance targets: [`docs/performance.md`](docs/performance.md) (targets only — no comparative claims without measured benchmarks)

## Project rules (what we will not do)

- No “Windows 7 supported” badge anywhere until a verification record exists.
- No performance comparison with other clients without a published, reproducible benchmark.
- No `latest` downloads, no hardcoded secrets, no silent elevation, no telemetry.

## License

MIT — see [LICENSE](LICENSE). IranLink is an independent implementation; it
shares no code with other clients.
