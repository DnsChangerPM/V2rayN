#!/usr/bin/env python3
"""Strict release-version validation for IranLink.

Policy (documented in docs/release.md): release versions are strict SemVer
core ``MAJOR.MINOR.PATCH`` with no leading zeros, no ``v`` prefix, no
pre-release/build suffix. Pre-release state is carried by the separate
workflow ``prerelease`` boolean input instead, so the version string stays
identical across pubspec / EXE metadata / installer / tag / archives.

Valid:   1.0.0  1.2.3  10.20.30
Invalid: 1  1.0  v1.0.0  01.2.3  1.2.3-beta  abc  ''  ' 1.2.3 '
"""

from __future__ import annotations

import argparse
import re
import sys

STRICT_SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def is_valid(version: str) -> bool:
    return bool(STRICT_SEMVER.match(version))


def parse(version: str) -> tuple[int, int, int]:
    """Return (major, minor, patch) or raise ValueError."""
    m = STRICT_SEMVER.match(version)
    if not m:
        raise ValueError(
            f"Invalid version {version!r}: expected strict MAJOR.MINOR.PATCH "
            "(e.g. 1.4.2; no 'v' prefix, no suffixes)"
        )
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def self_test() -> None:
    for good in ("0.0.0", "1.0.0", "1.2.3", "10.20.30", "99.99.199"):
        assert is_valid(good), good
    for bad in ("", "1", "1.0", "v1.0.0", "1.0.0v", "01.2.3", "1.02.3",
                "1.2.3-beta", "1.2.3+1", "abc", "1.2", "1.2.3.4",
                " 1.2.3", "1.2.3 ", "1,2,3"):
        assert not is_valid(bad), bad
    assert parse("1.4.2") == (1, 4, 2)
    print("validate_version.py self-test: OK")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Validate a strict SemVer version.")
    ap.add_argument("--version", help="Version string to validate")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if not args.version:
        ap.error("--version is required (or pass --self-test)")
    try:
        major, minor, patch = parse(args.version)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print(f"Version OK: {args.version} (major={major} minor={minor} patch={patch})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
