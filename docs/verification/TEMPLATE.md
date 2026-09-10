# Verification: IranLink <version> — <OS + build>

- Tester:
- Date:
- Machine (VM/host, CPU/RAM):
- Installer SHA-256 (must match `SHA256SUMS.txt`):
- App version (About screen):
- Bundled core (`xray version`, primary):
- Bundled core (`win7/xray.exe version`, legacy):

## Checklist

| # | Check | Result | Evidence |
| - | ----- | ------ | -------- |
| 1 | Installer launches, per-user default, no admin prompt | | |
| 2 | App launches, dashboard renders, no crash in 60 s idle | | |
| 3 | `--version` prints `<version>` | | |
| 4 | `--smoke-test` exits 0 (`SMOKE-OK`) | | |
| 5 | Correct core binary selected for this OS (see Diagnostics) | | |
| 6 | Import share link (clipboard + file) succeeds | | |
| 7 | Connect → SOCKS handshake on configured port succeeds | | |
| 8 | System proxy enabled while connected, **restored** after disconnect | | |
| 9 | Subscription add + refresh imports profiles | | |
| 10 | Routing mode switch (global→direct) takes effect | | |
| 11 | Speed test completes (or fails with a friendly message, no crash) | | |
| 12 | Diagnostics export produces a redacted report (no secrets) | | |
| 13 | Tray: show/hide, connect/disconnect, quit | | |
| 14 | Autostart toggle writes/removes `HKCU\...\Run` entry | | |
| 15 | Persian locale renders RTL correctly (Settings → language) | | |
| 16 | TUN row: hidden with explanation on Win7/8.1; consent-gated on Win10/11 | | |
| 17 | Backup export (with password) → import restores profiles + settings | | |
| 18 | Update check reports honestly (no update / available / offline) | | |
| 19 | Uninstall removes app; user data handling matches installer prompt | | |
| 20 | Portable ZIP: runs from folder, leaves no documented traces outside it | | |

## Verdict

- [ ] All rows pass → this OS is **Verified** for `<version>`.
- [ ] Any row fails → file an issue, link it here, OS stays **Not verified**.

Failure notes:
