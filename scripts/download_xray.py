#!/usr/bin/env python3
"""Download the pinned Xray-core binaries and verify them against upstream digests.

Fetches BOTH:
  Xray-windows-64.zip (+ .dgst)  -> primary core for Windows 10/11
  Xray-win7-64.zip (+ .dgst)      -> legacy core for Windows 7 SP1 / 8.1

Upstream .dgst format (from XTLS/Xray-core .github/workflows/release.yml):
    openssl dgst -md5|-sha1|-sha256|-sha512 $FILE | sed 's/([^)]*)//g'
i.e. four lines like ``SHA256= <hex>`` (older files may say ``SHA2-256=``).

Security posture: fail closed. If a .dgst is missing, unparseable, or the
SHA-256 does not match, the download is deleted and the script exits non-zero.

Stdlib only (urllib), so it runs on stock CI Python without pip installs.

Usage:
  python scripts/download_xray.py --xray-version v26.3.27 --out third_party/xray
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

BASE_URL = "https://github.com/XTLS/Xray-core/releases/download"
ASSETS = ("Xray-windows-64.zip", "Xray-win7-64.zip")
# openssl prints "SHA256(...)= ..." or "SHA2-256(...)= ..."; Xray strips "(...)".
SHA256_LINE = re.compile(r"^\s*SHA(?:2-)?256\s*=\s*([0-9a-fA-F]{64})\s*$", re.M)
ANY_SHA256 = re.compile(r"\b[0-9a-fA-F]{64}\b")


def fetch(url: str, dest: Path, timeout: int = 120) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "IranLink-Release-Tooling"})
    with urllib.request.urlopen(req, timeout=timeout) as resp, open(dest, "wb") as f:
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            f.write(chunk)


def expected_sha256(dgst_text: str, asset: str) -> str:
    m = SHA256_LINE.search(dgst_text)
    if m:
        return m.group(1).lower()
    # Fallback: a single 64-hex token anywhere in the file.
    tokens = ANY_SHA256.findall(dgst_text)
    if len(tokens) == 1:
        return tokens[0].lower()
    raise ValueError(
        f"Cannot determine expected SHA-256 for {asset}: .dgst has no "
        "SHA256/SHA2-256 line and no unambiguous 64-hex token."
    )


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 256), b""):
            h.update(chunk)
    return h.hexdigest()


def download_asset(version: str, asset: str, out_dir: Path) -> Path:
    zipp = out_dir / asset
    dgstp = out_dir / (asset + ".dgst")
    print(f"Downloading {asset} ({version}) ...")
    fetch(f"{BASE_URL}/{version}/{asset}", zipp)
    fetch(f"{BASE_URL}/{version}/{asset}.dgst", dgstp)
    expected = expected_sha256(dgstp.read_text(encoding="utf-8", errors="replace"), asset)
    actual = sha256_of(zipp)
    if actual != expected:
        zipp.unlink(missing_ok=True)
        raise SystemExit(
            f"ERROR: SHA-256 mismatch for {asset}:\n  expected {expected}\n  actual   {actual}"
        )
    print(f"  verified sha256={actual[:16]}... size={zipp.stat().st_size} bytes")
    # Structural check: must be a valid zip containing xray.exe.
    try:
        with zipfile.ZipFile(zipp) as zf:
            if zf.testzip() is not None:
                raise SystemExit(f"ERROR: {asset} is a corrupt zip")
            names = [n.lower() for n in zf.namelist()]
            if not any(n.endswith("xray.exe") for n in names):
                raise SystemExit(f"ERROR: {asset} contains no xray.exe: {names}")
    except zipfile.BadZipFile:
        raise SystemExit(f"ERROR: {asset} is not a valid zip file")
    return zipp


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Download + verify pinned Xray-core.")
    ap.add_argument("--xray-version", required=True, help="e.g. v26.3.27 (never 'latest')")
    ap.add_argument("--out", required=True, help="Output directory")
    args = ap.parse_args(argv)
    if args.xray_version.strip().lower() == "latest":
        print("ERROR: --xray-version must be pinned, 'latest' is forbidden.", file=sys.stderr)
        return 1
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for asset in ASSETS:
        download_asset(args.xray_version, asset, out)
    print("Xray download + verification: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
