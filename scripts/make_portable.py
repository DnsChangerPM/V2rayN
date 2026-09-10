#!/usr/bin/env python3
"""Build the portable ZIP: IranLink-<ver>-Windows-<arch>-Portable.zip.

Layout inside the zip:
  IranLink/IranLink.exe
  IranLink/... (full bundle incl. core/)
  IranLink/README-Portable.txt
  IranLink/Data/  (created on first run; portable mode marker lives here)

Portable mode: if a file named ``portable.marker`` sits next to the EXE, the
app stores all data under ``./Data`` instead of %AppData%. The ZIP ships
``Data/.keep`` so the folder exists; the marker file itself is created by the
app on first portable launch (documented in README-Portable.txt).
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

README_PORTABLE = """IranLink {version} — Portable (Windows {arch})
=============================================

No installation needed: extract this folder anywhere and run IranLink.exe.

Portable mode
-------------
On first launch the app creates a "portable.marker" file next to IranLink.exe
and stores ALL data (profiles, subscriptions, settings, logs) in the "Data"
folder inside this directory. Nothing is written to %AppData% or the registry
(except the optional system-proxy toggle while connected, which is restored
on disconnect).

To return to installed-style paths, delete "portable.marker" (data stays).

Contents
--------
IranLink.exe          the application
core/xray.exe         primary Xray core (Windows 10/11)
core/win7/xray.exe    legacy Xray core (Windows 7 SP1 / 8.1)
core/geoip.dat, geosite.dat  routing data

Security: verify SHA256SUMS.txt before running.
Docs: https://github.com/DnsChangerPM/V2rayN
"""


def make_portable(version: str, arch: str, source: Path, out_dir: Path) -> Path:
    if not source.is_dir():
        raise SystemExit(f"ERROR: source bundle not found: {source}")
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"IranLink-{version}-Windows-{arch}-Portable.zip"
    if target.exists():
        target.unlink()

    top = "IranLink"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                zf.write(path, f"{top}/{path.relative_to(source).as_posix()}")
        zf.writestr(f"{top}/README-Portable.txt",
                    README_PORTABLE.format(version=version, arch=arch))
        zf.writestr(f"{top}/Data/.keep", "")
    print(f"Portable ZIP: {target} ({target.stat().st_size} bytes)")
    return target


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--arch", required=True)
    ap.add_argument("--source", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    make_portable(args.version, args.arch, Path(args.source), Path(args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
