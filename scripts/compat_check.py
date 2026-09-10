#!/usr/bin/env python3
"""Static compatibility gate for IranLink releases (stdlib only).

Checks (all must pass):
  1. Main EXE is a valid PE file with machine type AMD64 (0x8664).
  2. Both bundled cores exist and are valid AMD64 PEs.
  3. EXE-adjacent version stamp (app_version.dart) matches --version
     (Runner.rc already enforced by check_version.py pre-build).
  4. installer/iranlink.iss keeps MinVersion at 6.1sp1 (Win7 SP1 floor)
     and ArchitecturesAllowed restricted to x64-compatible.
  5. If --installer is given: file exists and is a valid PE (Inno Setup
     stubs are PEs too).

This is a *static* gate; runtime behavior is covered by the smoke test and
the manual matrix in docs/verification/.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

IMAGE_FILE_MACHINE_AMD64 = 0x8664


def pe_machine_type(path: Path) -> int:
    data = path.read_bytes()
    if len(data) < 64 or data[0:2] != b"MZ":
        raise ValueError(f"{path.name}: missing MZ header")
    (lfanew,) = struct.unpack_from("<I", data, 0x3C)
    if len(data) < lfanew + 6 or data[lfanew:lfanew + 4] != b"PE\x00\x00":
        raise ValueError(f"{path.name}: missing PE signature")
    (machine,) = struct.unpack_from("<H", data, lfanew + 4)
    return machine


def check_pe(path: Path, label: str, errors: list[str]) -> None:
    if not path.is_file():
        errors.append(f"{label}: missing file {path}")
        return
    try:
        machine = pe_machine_type(path)
    except ValueError as e:
        errors.append(f"{label}: {e}")
        return
    if machine != IMAGE_FILE_MACHINE_AMD64:
        errors.append(f"{label}: expected AMD64 PE, got machine=0x{machine:04X}")
    else:
        print(f"  {label}: AMD64 PE OK ({path.stat().st_size} bytes)")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--bundle", required=True, help="Staged bundle dir")
    ap.add_argument("--installer", default=None, help="Setup.exe path (optional)")
    ap.add_argument("--root", default=".", help="Repository root")
    args = ap.parse_args(argv)

    root = Path(args.root)
    bundle = Path(args.bundle)
    errors: list[str] = []

    print("Compatibility gate:")
    check_pe(bundle / "IranLink.exe", "app exe", errors)
    check_pe(bundle / "core" / "xray.exe", "primary core", errors)
    check_pe(bundle / "core" / "win7" / "xray.exe", "legacy core", errors)
    if args.installer:
        check_pe(Path(args.installer), "installer", errors)

    dart = (root / "lib" / "src" / "core" / "app_version.dart").read_text(encoding="utf-8")
    if f"kAppVersion = '{args.version}'" not in dart:
        errors.append(f"app_version.dart does not carry {args.version}")
    else:
        print(f"  version stamp: {args.version} OK")

    iss = (root / "installer" / "iranlink.iss").read_text(encoding="utf-8")
    if "MinVersion=6.1sp1" not in iss.replace(" ", ""):
        errors.append("iranlink.iss: MinVersion=6.1sp1 (Win7 SP1 floor) missing")
    else:
        print("  installer MinVersion=6.1sp1 OK")
    if "x64compatible" not in iss:
        errors.append("iranlink.iss: ArchitecturesAllowed must include x64compatible")
    else:
        print("  installer ArchitecturesAllowed OK")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print("Compatibility gate: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
