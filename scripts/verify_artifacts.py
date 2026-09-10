#!/usr/bin/env python3
"""Gate check before publishing: every artifact must exist and be sane.

Checks:
  - Setup.exe and Portable.zip exist, match the versioned names, exceed
    minimum sizes (catches truncated/empty builds)
  - Portable.zip integrity (testzip) and contains IranLink.exe + core files
  - SHA256SUMS.txt exists and covers both artifacts with correct hashes
  - Bundle still contains both core binaries (installer source of truth)
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path

MIN_INSTALLER_BYTES = 10 * 1024 * 1024
MIN_PORTABLE_BYTES = 10 * 1024 * 1024


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 256), b""):
            h.update(chunk)
    return h.hexdigest()


def verify(version: str, arch: str, dist: Path, bundle: Path) -> list[str]:
    errors: list[str] = []
    setup = dist / f"IranLink-{version}-Windows-{arch}-Setup.exe"
    portable = dist / f"IranLink-{version}-Windows-{arch}-Portable.zip"
    sums = dist / "SHA256SUMS.txt"

    if not setup.is_file():
        errors.append(f"missing installer: {setup.name}")
    elif setup.stat().st_size < MIN_INSTALLER_BYTES:
        errors.append(f"installer suspiciously small: {setup.stat().st_size} bytes")

    if not portable.is_file():
        errors.append(f"missing portable zip: {portable.name}")
    elif portable.stat().st_size < MIN_PORTABLE_BYTES:
        errors.append(f"portable zip suspiciously small: {portable.stat().st_size} bytes")
    else:
        try:
            with zipfile.ZipFile(portable) as zf:
                if zf.testzip() is not None:
                    errors.append("portable zip is corrupt (testzip failed)")
                names = zf.namelist()
                for needed in ("IranLink/IranLink.exe", "IranLink/core/xray.exe",
                               "IranLink/core/win7/xray.exe"):
                    if needed not in names:
                        errors.append(f"portable zip missing {needed}")
        except zipfile.BadZipFile:
            errors.append("portable file is not a valid zip")

    if not sums.is_file():
        errors.append("missing SHA256SUMS.txt")
    else:
        covered: dict[str, str] = {}
        for line in sums.read_text(encoding="utf-8").splitlines():
            parts = line.strip().split()
            if len(parts) == 2:
                covered[parts[1].lstrip("*")] = parts[0]
        for artifact in (setup, portable):
            if not artifact.is_file():
                continue
            want = covered.get(artifact.name)
            if not want:
                errors.append(f"SHA256SUMS.txt does not cover {artifact.name}")
            elif want.lower() != sha256_of(artifact):
                errors.append(f"SHA256 mismatch for {artifact.name}")

    for core_exe in (bundle / "core" / "xray.exe", bundle / "core" / "win7" / "xray.exe"):
        if not core_exe.is_file():
            errors.append(f"bundle missing {core_exe.relative_to(bundle)}")
    return errors


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--arch", required=True)
    ap.add_argument("--dir", required=True)
    ap.add_argument("--bundle", required=True)
    args = ap.parse_args(argv)
    errors = verify(args.version, args.arch, Path(args.dir), Path(args.bundle))
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print("Artifact verification: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
