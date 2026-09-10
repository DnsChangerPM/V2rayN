#!/usr/bin/env python3
"""Generate SHA256SUMS.txt (GNU sha256sum format) for release artifacts."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

INCLUDE_SUFFIXES = (".exe", ".zip")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 256), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="Directory holding artifacts")
    args = ap.parse_args(argv)
    d = Path(args.dir)
    files = sorted(p for p in d.iterdir()
                   if p.is_file() and p.suffix.lower() in INCLUDE_SUFFIXES)
    if not files:
        raise SystemExit(f"ERROR: no shippable artifacts (*.exe/*.zip) in {d}")
    lines = [f"{sha256_of(p)}  {p.name}" for p in files]
    (d / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    for line in lines:
        print(f"  {line}")
    print(f"SHA256SUMS.txt written ({len(lines)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
