#!/usr/bin/env python3
"""Stage verified Xray binaries into the Flutter build bundle.

Input : third_party/xray/{Xray-windows-64.zip, Xray-win7-64.zip}
Output: <bundle>/core/{xray.exe, geoip.dat, geosite.dat, win7/xray.exe}

Only the allowlisted files are extracted — never the full zip blindly —
so upstream packaging changes cannot smuggle unexpected files into releases.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

PRIMARY_ZIP = "Xray-windows-64.zip"
LEGACY_ZIP = "Xray-win7-64.zip"
ALLOWLIST = {"xray.exe", "geoip.dat", "geosite.dat"}


def extract_allowlisted(zip_path: Path, dest: Path) -> list[str]:
    staged: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        with zipfile.ZipFile(zip_path) as zf:
            for info in zf.infolist():
                name = Path(info.filename).name.lower()
                if name in ALLOWLIST:
                    target = tmpdir / name
                    with zf.open(info) as src, open(target, "wb") as dst:
                        shutil.copyfileobj(src, dst)
                    staged.append(name)
        for name in staged:
            shutil.copy2(tmpdir / name, dest / name)
    return staged


def stage(xray_dir: Path, bundle: Path) -> None:
    primary = xray_dir / PRIMARY_ZIP
    legacy = xray_dir / LEGACY_ZIP
    for p in (primary, legacy):
        if not p.is_file():
            raise SystemExit(f"ERROR: missing {p} — run scripts/download_xray.py first")
    if not bundle.is_dir():
        raise SystemExit(f"ERROR: bundle dir not found: {bundle}")

    core = bundle / "core"
    win7 = core / "win7"
    core.mkdir(parents=True, exist_ok=True)
    win7.mkdir(parents=True, exist_ok=True)

    got_primary = extract_allowlisted(primary, core)
    got_legacy = extract_allowlisted(legacy, win7)
    # Legacy zip ships its own geo files; keep the primary set as canonical and
    # only keep the legacy xray.exe.
    for extra in ("geoip.dat", "geosite.dat"):
        (win7 / extra).unlink(missing_ok=True)

    required = {"xray.exe", "geoip.dat", "geosite.dat"}
    if required - set(got_primary):
        raise SystemExit(f"ERROR: primary zip missing {required - set(got_primary)}")
    if "xray.exe" not in got_legacy:
        raise SystemExit("ERROR: legacy (win7) zip missing xray.exe")

    print("Staged core bundle:")
    for f in sorted(core.rglob("*")):
        if f.is_file():
            print(f"  core/{f.relative_to(core)} ({f.stat().st_size} bytes)")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--xray-dir", required=True)
    ap.add_argument("--bundle", required=True)
    args = ap.parse_args(argv)
    stage(Path(args.xray_dir), Path(args.bundle))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
