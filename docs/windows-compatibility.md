# Windows Compatibility

This document is the evidence base for every compatibility claim IranLink makes.
Status vocabulary (used consistently in README and release notes):

| Term                 | Meaning                                                      |
| -------------------- | ------------------------------------------------------------ |
| Verified             | Actually executed/tested on that OS with recorded evidence.  |
| Supported            | Designed and built for that OS; upstream supports it.        |
| Partially supported  | Core flows work; some features are OS-gated (listed below).  |
| Not verified         | No test evidence yet; no claim of working is made.           |

## Current status (honest, as of this commit)

| OS            | Build target | Status              | Evidence / notes                          |
| ------------- | ------------ | ------------------- | ----------------------------------------- |
| Windows 11    | x64          | Supported           | CI builds on Win Server 2022; smoke tests |
| Windows 10    | x64          | Supported           | Same binary lineage as Win11              |
| Windows 8.1   | x64          | Partially supported | Needs Win7-line core; TUN unavailable     |
| Windows 7 SP1 | x64          | Partially supported | Needs Win7-line core + updates; see below |

> "Supported" here means: installer runs, app launches, core starts, config
> validates, proxy connects — by design. Until per-OS test runs are recorded
> in `docs/verification/`, treat Win7/8.1 rows as **design intent backed by
> upstream support statements**, not as tested fact. We do not print
> "Windows 7 supported" in user-facing UI without verification.

## Compatibility matrix (design)

| Component    | Win7 SP1                    | Win8.1                      | Win10     | Win11     |
| ------------ | --------------------------- | --------------------------- | --------- | --------- |
| Flutter UI   | 3.19.6 (last w/ support)    | 3.19.6                      | 3.19.6    | 3.19.6    |
| Dart runtime | 3.3.4 (last w/ support)     | 3.3.4                       | 3.3.4     | 3.3.4     |
| MSVC runtime | VS2022 redist (see note 1)  | VS2022 redist               | VS2022    | VS2022    |
| Xray-core    | Xray-win7-64 (go-win7 SDK)  | Xray-win7-64                | windows-64| windows-64|
| Installer    | Inno Setup 6 (Min 6.1sp1)   | Inno Setup 6                | Inno 6    | Inno 6    |
| System proxy | Yes (WinINet API)           | Yes                         | Yes       | Yes       |
| TUN          | **No** (not reliable)       | **No**                      | Yes       | Yes       |
| Secure store | DPAPI (Win2000+)            | DPAPI                       | DPAPI     | DPAPI     |

Note 1: Flutter 3.19 desktop apps link against the VS2022 C++ runtime. On
Windows 7 SP1, `KB2999226` (Universal CRT) is required — the installer checks
for `ucrtbase.dll` and directs the user to Windows Update if missing.

## Evidence

### Flutter / Dart (Win7/8 support window)
- flutter-announce, 2024-02-15 ("Flutter will no longer support Windows 7/8"):
  > "Dart 3.3 and Flutter 3.19 will be the last releases supporting
  > Windows 7 and 8."
- Tracking issue: `flutter/flutter#140830` — minimum supported Windows raised
  to 10 after 3.19.
- Consequence: IranLink pins **Flutter 3.19.6 / Dart 3.3.4** (last 3.19 patch,
  tag verified to exist upstream). Newer Flutter is intentionally NOT used:
  compatibility outranks novelty (project rule §3). RustDesk demonstrated that
  running newer Flutter on Win7 requires reverting engine commits — we do not
  fork the engine; we pin the supported line.

### Xray-core (Win7 builds exist and are current)
- XTLS news, 2024-07-15: "Xray-core now supports Windows 7 again! ... users
  can download the archive named `Xray-win7-32.zip` or `Xray-win7-64.zip`".
- Mechanism: separate `release-win7.yml` workflow builds with the patched
  `XTLS/go-win7` SDK (upstream Go dropped Win7 in Go 1.21).
- Verified 2026-09-10 via GitHub API for pinned `XRAY_VERSION=v26.3.27`
  (latest stable): assets `Xray-windows-64.zip`, `Xray-win7-64.zip`, each with
  a `.dgst` checksum file, are attached to the release.
- Requirement drift warning: newer go-win7 SDKs require Win7 SP1 **plus**
  updates (`KB4474419`, and before 2027 possibly `KB3125574` rollup). IranLink
  therefore treats "Windows 7 SP1 fully updated" as the actual floor and the
  app surfaces a clear error if the legacy core fails to launch.
- Runtime selection: the app detects the OS version at startup
  (`RtlGetVersion`, not the shimmed `GetVersionEx`) and launches the matching
  bundled core: `core/xray.exe` on Win10+, `core/win7/xray.exe` on Win7/8.x.

### Installer
- Inno Setup 6: minimum supported OS is Windows 7 / Server 2008 R2;
  `[Setup] MinVersion` defaults to `6.1sp1`
  (jrsoftware.org `ishelp/topic_setup_minversion.htm`).
- IranLink uses Inno Setup **6.2.2** (pinned via Chocolatey), `MinVersion=
  6.1sp1`, `ArchitecturesAllowed=x64compatible`, per-user install by default
  (`PrivilegesRequired=lowest`) so no admin rights are needed.

### Dependencies (Win7 review)
Every dependency was screened for Win10-only API usage:

| Package         | Native? | Win7 verdict | Reason                              |
| --------------- | ------- | ------------ | ----------------------------------- |
| provider        | No      | Safe         | Pure Dart                           |
| http            | No      | Safe         | Pure Dart (`dart:io`)               |
| path/provider   | path_provider | Safe   | Known-folder APIs exist since XP/Vista |
| window_manager  | Win32   | Safe         | Classic window messages             |
| system_tray     | Win32   | Safe         | `Shell_NotifyIcon` (Win2000+)       |
| file_picker     | COM     | Safe         | Common Item Dialog (Vista+)         |
| win32 (FFI)     | FFI     | Safe         | We call only pre-Win7 APIs; guarded |
| uuid/encrypt/…  | No      | Safe         | Pure Dart                           |
| zxing2 + image  | No      | Safe         | Pure-Dart QR decode                 |

`win32` usage rule: only APIs available on Windows 7 SP1 may be called on the
legacy path; any newer API must be version-gated with `IsWindows10OrGreater()`
style checks. See `lib/src/platform/windows_apis.dart`.

### TUN
TUN requires the Wintun driver, an elevated installer/service flow, and modern
network stack behavior. It is **not offered on Windows 7/8.1** (UI hides the
option with an explanation). Win10/11: supported behind explicit user consent
+ elevation prompt. No silent driver installation, ever.

## Validation strategy (no Win7 hosted runner exists)

GitHub does not offer Windows 7/8.1 hosted runners. Validation layers:

1. **CI (windows-2022)**: analyzer, unit tests, widget tests, Flutter build,
   artifact validation (`scripts/verify_artifacts.py`), installer compile,
   portable ZIP checks, SHA256 generation. A Windows **smoke job** launches
   the built app headless (`--smoke-test`), starts the real bundled Xray with
   a test config, and asserts proxy ports respond.
2. **Static compat check** (`scripts/compat_check.py`): PE machine type,
   version resources, bundled-core presence, `MinVersion` in the `.iss`.
3. **Manual matrix** (`docs/verification/`): checklist + evidence screenshots
   for real Win7 SP1 / 8.1 / 10 / 11 machines or VMs. A release may only claim
   "Verified" for an OS with a filled checklist.
4. **Optional self-hosted runner**: documented in `docs/release.md`; a Win10/11
   self-hosted runner can run the same smoke job on real hardware.

## What we explicitly do NOT claim
- No "50% faster / 70% less RAM than v2rayN" without measured benchmarks
  (see `docs/performance.md`: targets only, until measured).
- No "Windows 7 supported" badge in UI/marketing until a verification record
  exists. The app itself feature-gates by real OS detection instead.
