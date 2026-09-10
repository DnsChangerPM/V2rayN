# Optional self-hosted Windows runner (real-hardware smoke tests)

GitHub-hosted `windows-2022` remains the default for CI and releases. A
self-hosted Windows 10/11 runner only *adds* evidence (real GPU, real
network stack, real reboot persistence); it never replaces hosted runs.

## Setup

1. Provision a clean Windows 10/11 x64 machine or VM (snapshot it).
2. Install: Visual Studio 2022 (Desktop C++ workload), Flutter **3.19.6**,
   Python 3.11, Git. Add `flutter` and `python` to `PATH`.
3. Install the GitHub Actions runner as an **unprivileged service account**
   (do NOT run as admin; TUN tests are consent-gated and skipped here).
4. Register with a dedicated runner group, labels:
   `self-hosted, windows, iranlink`.
5. Harden: auto-logon disabled, RDP restricted, Windows Update current,
   snapshot before each verification；revert after.

## Running the smoke suite

```powershell
git checkout v<version>
$env:XRAY_VERSION = (Select-String '^XRAY_VERSION=(.+)' tooling/versions.env).Matches.Groups[1].Value
python scripts/download_xray.py --xray-version $env:XRAY_VERSION --out third_party/xray
flutter pub get
flutter build windows --release
python scripts/stage_bundle.py --xray-dir third_party/xray --bundle build/windows/x64/runner/Release
.\build\windows\x64\runner\Release\IranLink.exe --smoke-test --smoke-timeout 120
```

Record the output (`SMOKE-OK` + timings) in `docs/verification/<version>.md`.

## What self-hosted runs must never do

- Run with admin rights or with elevation prompts auto-accepted.
- Upload `SHA256SUMS.txt`-covered artifacts anywhere except the release flow.
- Persist state between verifications (always revert to the clean snapshot).
