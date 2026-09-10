# Verification records

Per-OS, per-release test evidence. A compatibility claim ("Verified on …")
may only be made when a filled checklist exists here.

## Status board

| Release | Win11 x64 | Win10 x64 | Win8.1 x64 | Win7 SP1 x64 | Notes |
| ------- | --------- | --------- | ---------- | ------------ | ----- |
| — | Not verified | Not verified | Not verified | Not verified | No release cut yet |

## How to verify a release (manual matrix)

1. Copy [`TEMPLATE.md`](TEMPLATE.md) to `<version>.md` (e.g. `1.4.2.md`).
2. On each target OS (real hardware or VM, clean snapshot):
   - install from `IranLink-<version>-Windows-x64-Setup.exe`,
   - run every checklist row, record pass/fail + evidence (screenshot, log
     snippet, `--smoke-test` output),
   - test the portable ZIP too (extract → run → connect → remove; no traces
     outside its folder except documented user data).
3. Commit the filled file. Only then may release notes / README claim
   “Verified” for that OS.

Minimum bar per OS: install → launch → core starts (correct binary for the
OS) → config validates → SOCKS handshake works → system proxy roundtrip
restores → uninstall/portable-removal is clean.
