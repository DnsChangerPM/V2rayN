# Release

Releases are fully automated. A maintainer runs the workflow; everything else
— version stamping, core download + verification, build, installer, portable
ZIP, checksums, validation, GitHub Release — happens in CI. **If any
significant step fails, no release is created.**

## How to cut a release
1. Go to **Actions → Release → Run workflow**.
2. Fill the inputs:
   - `version` (required): strict SemVer `MAJOR.MINOR.PATCH`, e.g. `1.4.2`.
     `v1.4.2`, `1.0`, `abc` are rejected.
   - `release_name` (optional): defaults to `IranLink v1.4.2`.
   - `prerelease` (optional, default `false`).
   - `architecture` (optional, default `x64`; pipeline is arch-parameterized
     for future `x86`/`arm64`).
3. Watch the run. On success you get:
```
dist/
  IranLink-1.4.2-Windows-x64-Setup.exe
  IranLink-1.4.2-Windows-x64-Portable.zip
  SHA256SUMS.txt
```
attached to tag `v1.4.2` with generated notes (features/fixes template + core
version + compatibility + checksums).

## Pipeline (release.yml)
```
validate-version → setup (Flutter 3.19.6, Python) → pub get
  → analyze → unit tests → download Xray (pinned, .dgst verified)
  → build windows → stage bundle → Inno Setup installer
  → portable ZIP → SHA256SUMS → verify artifacts → compat check
  → create GitHub Release (gh) → upload assets
```
- Runner: `windows-2022` (pinned), actions pinned by commit SHA.
- Permissions: minimal (`contents: write` only on the release job).
- No `latest` downloads anywhere: Flutter, Xray, Inno are all pinned in
  `tooling/versions.env`.
- Concurrency: one release run at a time (`concurrency: release`).

## Version propagation
`scripts/set_version.py --version X.Y.Z` stamps:
`pubspec.yaml`, `windows/runner/Runner.rc` (EXE metadata),
`installer/iranlink.iss` (`AppVersion`), generated
`lib/src/core/app_version.dart` (About screen), archive names, tag (`vX.Y.Z`),
release title. CI asserts all of them agree before building.

## Artifact validation (all must pass)
- files exist and exceed minimum sizes (installer > 10 MiB, portable > 10 MiB)
- PE architecture is x64; `FileVersion` equals input version
- `core/xray.exe` and `core/win7/xray.exe` present in the bundle
- installer compiles without warnings-as-errors; ZIP integrity verified
- `SHA256SUMS.txt` covers every shipped file

## Xray supply chain
- Pinned `XRAY_VERSION` (e.g. `v26.3.27`) in `tooling/versions.env`.
- `scripts/download_xray.py` fetches both zips **and** their upstream `.dgst`
  files, verifies SHA-256, and only then extracts.
- Release notes always state the bundled core version.

## Compatibility claims in release notes
The notes template contains a Windows table that is filled from
`docs/verification/<version>.md` if present, otherwise marked
"Not verified". Claims are never upgraded without evidence.

## Self-hosted runner (optional, for real-hardware smoke tests)
A Windows 10/11 self-hosted runner with Flutter 3.19.6 + VS2022 can run the
`smoke` job via `workflow_dispatch` input `runner: self-hosted-windows`.
Setup steps and hardening notes live in `docs/verification/self-hosted.md`.
GitHub-hosted runs remain the default; self-hosted only *adds* evidence.
