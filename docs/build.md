# Build

## Requirements (developer machine)
- Windows 10/11 64-bit (Flutter 3.19 requires Win10+ **for development**;
  the *built app* additionally targets Win7 SP1/8.1 — see
  `docs/windows-compatibility.md`).
- Visual Studio 2022 with "Desktop development with C++" workload
  (matches CI `windows-2022` image).
- Flutter **3.19.6** exactly (`tooling/versions.env`, `FLUTTER_VERSION`).
- Python 3.9+ (helper scripts).
- Git.

Check with:
```powershell
flutter doctor -v
flutter --version   # must print 3.19.6
```

## First build
```powershell
# 1. Fetch the pinned Xray binaries (primary + Win7 legacy) and verify digests
#    (version comes from tooling/versions.env; never 'latest')
$env:XRAY_VERSION = (Select-String '^XRAY_VERSION=(.+)' tooling/versions.env).Matches.Groups[1].Value
python scripts/download_xray.py --xray-version $env:XRAY_VERSION --out third_party/xray

# 2. Get packages (resolves against the pinned SDK)
flutter pub get

# 3. Analyze + unit tests
flutter analyze
flutter test

# 4. Build (Release)
flutter build windows --release
```

The build output lands in `build/windows/x64/runner/Release/`. The helper
`scripts/stage_bundle.py` (invoked by CI and usable locally) copies the
verified core binaries + geo data into the bundle under `core/`:
```
Release/
  IranLink.exe
  flutter_windows.dll
  ...
  core/
    xray.exe            # primary (Win10/11)
    geosite.dat geoip.dat
    win7/
      xray.exe          # legacy (Win7 SP1 / 8.1)
```

## Versioning (local)
Releases take the version from the workflow input. For local builds the
version in `pubspec.yaml` is used; to stamp everything consistently:
```powershell
python scripts/set_version.py --version 1.4.2
```
This updates `pubspec.yaml`, `windows/runner/Runner.rc`,
`installer/iranlink.iss`, and regenerates `lib/src/core/app_version.dart`.

## Installer (local)
Requires Inno Setup 6 (`choco install innosetup --version 6.2.2`):
```powershell
iscc installer/iranlink.iss /DAppVersion=1.4.2 /DSourceDir=build/windows/x64/runner/Release
```
CI performs this step and additionally validates the installer
(`scripts/verify_artifacts.py`) before any upload.

## Portable ZIP (local)
```powershell
python scripts/make_portable.py --version 1.4.2 --source build/windows/x64/runner/Release --out dist/
```

## Troubleshooting
| Symptom | Cause / fix |
| ------- | ----------- |
| `flutter doctor` complains about VS | Install VS2022 C++ workload; rerun `flutter doctor` |
| `pub get` version solving failed | You are not on Flutter 3.19.6; `flutter --version` to confirm |
| `xray.exe not found` at runtime | Run `scripts/download_xray.py` + `scripts/stage_bundle.py` |
| App won't start on Win7 test VM | Check `ucrtbase.dll` (KB2999226) and that `core/win7/xray.exe` exists |
| CMake errors with VS2026 | Unsupported: use VS2022 (Flutter 3.19 era toolchain) |
