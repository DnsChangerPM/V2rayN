#!/usr/bin/env python3
"""Headless launch benchmark (Windows only, stdlib only).

Runs the built IranLink.exe twice and records honest, reproducible numbers:
  1. `--version` wall time (process spawn + Dart runtime baseline).
  2. `--smoke-test` wall time + peak working set of IranLink.exe and the
     spawned xray.exe children (polled via `tasklist`, 4 Hz).

This does NOT measure time-to-first-paint (not observable headless); it is a
regression tripwire for startup time and connected RSS. Results append to a
JSON-lines file for `docs/performance.md`.

Usage:
    python scripts/bench_startup.py --exe build/windows/x64/runner/Release/IranLink.exe
"""

import argparse
import csv
import datetime
import io
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

POLL_INTERVAL_S = 0.25


def tasklist_rss_kb(image: str) -> int:
    """Sum of working-set KB for all processes named [image] (0 on error)."""
    try:
        out = subprocess.run(
            ["tasklist", "/FI", f"IMAGENAME eq {image}", "/FO", "CSV", "/NH"],
            capture_output=True,
            text=True,
            timeout=15,
        ).stdout
    except OSError:
        return 0
    total = 0
    try:
        for row in csv.reader(io.StringIO(out)):
            if len(row) >= 5:
                total += int(row[4].replace(",", "").replace(" K", "").strip())
    except ValueError:
        return 0
    return total


class RssSampler(threading.Thread):
    def __init__(self, images: list[str]) -> None:
        super().__init__(daemon=True)
        self.images = images
        self.peak_kb = 0
        self.samples = 0
        self._stop = threading.Event()

    def run(self) -> None:
        while not self._stop.is_set():
            current = sum(tasklist_rss_kb(i) for i in self.images)
            self.samples += 1
            self.peak_kb = max(self.peak_kb, current)
            time.sleep(POLL_INTERVAL_S)

    def stop(self) -> int:
        self._stop.set()
        self.join(timeout=5)
        return self.peak_kb


def run_timed(exe: str, args: list[str], timeout: int) -> tuple[int, float, str]:
    start = time.perf_counter()
    proc = subprocess.run(
        [exe, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return proc.returncode, time.perf_counter() - start, (proc.stdout + proc.stderr)[-2000:]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Headless IranLink benchmark.")
    ap.add_argument("--exe", required=True, help="Path to IranLink.exe")
    ap.add_argument("--smoke-timeout", type=int, default=120)
    ap.add_argument("--out", default="dist/bench.jsonl",
                    help="JSON-lines file to append results to")
    ap.add_argument("--label", default="",
                    help="Free-form label (e.g. CI run id)")
    args = ap.parse_args(argv)

    exe = str(Path(args.exe))
    result: dict = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "label": args.label,
        "exe": exe,
    }

    print("== --version baseline ==")
    code, wall, tail = run_timed(exe, ["--version"], 60)
    result["version_exit"] = code
    result["version_wall_s"] = round(wall, 3)
    print(f"  exit={code} wall={wall:.2f}s")

    print("== --smoke-test (timed + RSS sampled) ==")
    sampler = RssSampler(["IranLink.exe", "xray.exe"])
    sampler.start()
    try:
        code, wall, tail = run_timed(
            exe, ["--smoke-test", "--smoke-timeout", str(args.smoke_timeout)],
            args.smoke_timeout + 60)
    finally:
        peak_kb = sampler.stop()
    result["smoke_exit"] = code
    result["smoke_wall_s"] = round(wall, 3)
    result["peak_rss_kb"] = peak_kb
    result["peak_rss_mib"] = round(peak_kb / 1024, 1)
    result["smoke_ok"] = "SMOKE-OK" in tail
    print(f"  exit={code} wall={wall:.2f}s peak_rss={peak_kb / 1024:.1f} MiB "
          f"smoke_ok={result['smoke_ok']}")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "a", encoding="utf-8") as f:
        f.write(json.dumps(result) + "\n")
    print(f"Appended to {out}")
    return 0 if (result["smoke_ok"] and code == 0) else 1


if __name__ == "__main__":
    raise SystemExit(main())
