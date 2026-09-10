#!/usr/bin/env python3
"""Generate release notes for an IranLink release.

Compatibility section is evidence-driven: if docs/verification/<version>.md
exists it is embedded; otherwise the table defaults to 'Not verified'.
"""

from __future__ import annotations

import argparse
from pathlib import Path

TEMPLATE = """# IranLink v{version}

## Highlights

- TODO(maintainer): summarize user-facing changes since the previous release.
  (Edit the published release notes after CI attaches the binaries.)

## Core

- Xray-core `{xray}` (pinned, digest-verified at build time)
  - Primary: `Xray-windows-64.zip` (Windows 10/11)
  - Legacy: `Xray-win7-64.zip` (Windows 7 SP1 / 8.1, auto-selected at runtime)

## Windows compatibility

{compat}

## Artifacts

- `IranLink-{version}-Windows-{arch}-Setup.exe` — installer (per-user, no admin needed)
- `IranLink-{version}-Windows-{arch}-Portable.zip` — portable, runs from any folder
- `SHA256SUMS.txt` — verify downloads with `certutil -hashfile <file> SHA256`

## Upgrade notes

- Settings, profiles and subscriptions are preserved on upgrade.
- Portable mode: keep your existing `Data/` folder next to the new EXE.
"""

UNVERIFIED_TABLE = """| OS | Status |
| -- | ------ |
| Windows 11 (x64) | Supported — built & smoke-tested in CI |
| Windows 10 (x64) | Supported — same binary lineage |
| Windows 8.1 (x64) | Partially supported — NOT VERIFIED this release |
| Windows 7 SP1 (x64) | Partially supported — NOT VERIFIED this release |

> Full policy: docs/windows-compatibility.md. Verification records live in
> docs/verification/ — contributions with real-hardware evidence are welcome."""


def build_notes(version: str, xray: str, arch: str, root: Path) -> str:
    record = root / "docs" / "verification" / f"{version}.md"
    if record.is_file():
        compat = record.read_text(encoding="utf-8").strip()
    else:
        compat = UNVERIFIED_TABLE
    return TEMPLATE.format(version=version, xray=xray, arch=arch, compat=compat)


def self_test() -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        notes = build_notes("1.4.2", "v26.3.27", "x64", root)
        assert "# IranLink v1.4.2" in notes
        assert "v26.3.27" in notes
        assert "NOT VERIFIED" in notes
        rec = root / "docs" / "verification"
        rec.mkdir(parents=True)
        (rec / "1.4.2.md").write_text("custom evidence", encoding="utf-8")
        assert "custom evidence" in build_notes("1.4.2", "v26.3.27", "x64", root)
    print("release_notes.py self-test: OK")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version")
    ap.add_argument("--xray-version")
    ap.add_argument("--arch", default="x64")
    ap.add_argument("--out")
    ap.add_argument("--root", default=".")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    for flag in ("version", "xray_version", "out"):
        if not getattr(args, flag):
            ap.error(f"--{flag.replace('_', '-')} is required (or pass --self-test)")
    notes = build_notes(args.version, args.xray_version, args.arch, Path(args.root))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(notes, encoding="utf-8")
    print(f"Release notes written to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
