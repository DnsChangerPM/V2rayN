#!/usr/bin/env python3
"""Validate tooling/versions.env: required keys, formats, allowlists.

Catches accidental edits (e.g. floating Flutter, 'latest' Xray) before CI burns
minutes. Run in CI and locally.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REQUIRED = {
    "FLUTTER_VERSION": re.compile(r"^\d+\.\d+\.\d+$"),
    "FLUTTER_CHANNEL": re.compile(r"^(stable|beta)$"),
    "RUNNER_OS": re.compile(r"^windows-202\d$"),
    "XRAY_VERSION": re.compile(r"^v\d+\.\d+\.\d+$"),
    "XRAY_PRIMARY_ASSET": re.compile(r"^Xray-windows-64\.zip$"),
    "XRAY_LEGACY_ASSET": re.compile(r"^Xray-win7-64\.zip$"),
    "INNO_VERSION": re.compile(r"^\d+\.\d+\.\d+$"),
    "ARCH": re.compile(r"^x64$"),
}

BANNED_SUBSTRINGS = ("latest", "master", "main", "*", " ")


def load(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip()
    return values


def check(path: Path) -> list[str]:
    errors: list[str] = []
    values = load(path)
    for key, pattern in REQUIRED.items():
        if key not in values:
            errors.append(f"missing required key: {key}")
            continue
        value = values[key]
        if not pattern.match(value):
            errors.append(f"{key}={value!r} does not match {pattern.pattern}")
        for banned in BANNED_SUBSTRINGS:
            if banned in value.lower():
                errors.append(f"{key}={value!r} contains banned {banned!r}")
    return errors


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="tooling/versions.env")
    args = ap.parse_args(argv)
    errors = check(Path(args.file))
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print(f"Toolchain file OK: {args.file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
