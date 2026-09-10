#!/usr/bin/env python3
"""Assert that every versioned surface carries the expected release version.

Run after scripts/set_version.py in CI; fails the release on any drift.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def check(root: Path, version: str) -> list[str]:
    errors: list[str] = []
    major, minor, patch = version.split(".")

    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    if not re.search(rf"^version:\s*{re.escape(version)}(\+\S+)?\s*$", pubspec, re.M):
        errors.append(f"pubspec.yaml does not carry {version}")

    rc = (root / "windows" / "runner" / "Runner.rc").read_text(encoding="utf-8")
    dotted = f"{major},{minor},{patch},0"
    if f"FILEVERSION {dotted}" not in rc or f"PRODUCTVERSION {dotted}" not in rc:
        errors.append("Runner.rc FILEVERSION/PRODUCTVERSION mismatch")
    if f'VALUE "FileVersion", "{version}"' not in rc:
        errors.append("Runner.rc FileVersion string mismatch")

    iss = (root / "installer" / "iranlink.iss").read_text(encoding="utf-8")
    if f'#define MyAppVersion "{version}"' not in iss:
        errors.append("installer/iranlink.iss MyAppVersion mismatch")

    dart = (root / "lib" / "src" / "core" / "app_version.dart").read_text(encoding="utf-8")
    if f"kAppVersion = '{version}'" not in dart:
        errors.append("lib/src/core/app_version.dart mismatch")

    return errors


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--root", default=".")
    args = ap.parse_args(argv)
    errors = check(Path(args.root), args.version)
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print(f"Version propagation OK: all surfaces carry {args.version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
