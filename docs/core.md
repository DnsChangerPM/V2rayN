# Core (Xray) Integration

IranLink is core-agnostic: the UI talks to `CoreManager`, which talks to a
`CoreAdapter`. Xray is the first and default adapter.

## Binaries shipped
| File               | Source asset (pinned release) | Used on              |
| ------------------ | ----------------------------- | -------------------- |
| `core/xray.exe`    | `Xray-windows-64.zip`         | Windows 10 / 11      |
| `core/win7/xray.exe` | `Xray-win7-64.zip`          | Windows 7 SP1 / 8.1  |
| `core/geoip.dat`, `core/geosite.dat` | bundled in both zips | all          |

Selection is automatic via unshimmed OS detection (`RtlGetVersion`). The user
can override in Settings → Core ("Prefer legacy core") for troubleshooting;
the override is logged and shown in Diagnostics.

## Lifecycle
```
validate(config) ──ok──▶ spawn ──▶ running ──▶ graceful stop
       │                      │  ▲
       │                      ▼  │ crash (≤3 restarts, backoff)
       └────────▶ error (no spawn) └─▶ crashed ──▶ stopped + report
```
- **Prestart validation**: JSON schema + semantic checks (inbounds, outbounds,
  ports free, referenced files exist). Invalid config ⇒ no spawn, localized
  human-readable error, technical detail in logs only.
- **Graceful shutdown**: close stdin / `SIGTERM` equivalent (`taskkill`-free:
  `Process.kill()` after asking the API to stop when the stats API is on),
  wait 5 s, then force-kill; always remove the temp config file.
- **Orphan cleanup**: on startup, IranLink looks for `xray.exe` processes it
  previously spawned (tracked PID file + command-line marker) and terminates
  strays before starting a new instance.
- **Health**: 1 Hz sampler (process alive, API ping, port listen state);
  states: `stopped/starting/running/stopping/crashed/error`.

## Failure taxonomy (user messages)
| Signal | Shown to user |
| ------ | ------------- |
| exit code 1 + "invalid config" on stderr | "Xray could not start because the configuration is invalid." |
| `bind: address already in use` | "Local port N is already in use (PID …). Change the port or stop the other app." |
| missing executable | "Core executable is missing. Reinstall IranLink or re-download the core." |
| access denied / exit 5 | "Permission denied. …" (never silently elevate) |
| crash loop (3 fails) | "The core keeps crashing. Auto-restart stopped — see Logs." |

Raw stderr is kept in logs (sanitized) for support; UI strings stay human.

## Config generation
`XrayConfigBuilder(profile, settings)` emits canonical Xray JSON:
- inbounds: SOCKS5 `127.0.0.1:socksPort`, HTTP `127.0.0.1:httpPort`
  (defaults 10808/10809, configurable, conflict-checked)
- outbound: from the active profile (vmess/vless/trojan/ss/socks/http)
- routing: from Routing mode (direct/proxy/block rules, geoip/geosite)
- dns: from DNS settings; stats API enabled on `127.0.0.1` for traffic stats
- log: stderr, warning level (parsed by IranLink, never shown raw)

Temp config path: `%AppData%/IranLink/cache/xray-runtime.json`, unique per
start, deleted on stop. The profile store never writes raw core JSON with
secrets to disk unprotected — secrets live in `SecureVault`.

## Version reporting
`xray version` output is parsed (`Xray <ver> (Xray, Penetrates Everything.)`)
and shown in Dashboard/Diagnostics/About. CI records the pinned version in
release notes. `UpdateService` does NOT auto-update the core; core updates
ship with app releases (reproducibility first).

## Adding another core (e.g. sing-box)
1. Implement `CoreAdapter` (+ builder + validator).
2. Register in `CoreRegistry`.
3. Add `core/<name>/` staging in `scripts/download_xray.py` sibling script.
No UI changes required; routing/DNS/profile models are core-neutral.
