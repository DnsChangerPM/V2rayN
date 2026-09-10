#!/usr/bin/env python3
"""Static security audit for the IranLink repository. Fails CI on violations.

FAIL (errors):
  - private key blocks, known token prefixes (ghp_, AKIA, xox-, ...)
  - hardcoded password/secret assignments in lib/ (outside _test fixtures)
  - downloading/polishing 'latest' external binaries (supply-chain rule)
  - shell=True in helper scripts (injection risk)

WARN (non-fatal, printed):
  - TODO/FIXME/HACK markers in lib/ (must be zero before a release; release
    job promotes these to errors via --strict)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ERROR_PATTERNS = [
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key block"),
    (r"ghp_[A-Za-z0-9]{20,}", "GitHub token (ghp_)"),
    (r"github_pat_[A-Za-z0-9_]{20,}", "GitHub fine-grained token"),
    (r"AKIA[0-9A-Z]{16}", "AWS access key"),
    (r"xox[baprs]-[A-Za-z0-9-]{10,}", "Slack token"),
    (r"(?i)\b(password|passwd|pwd|secret|api[_-]?key)\b\s*=\s*[\"'][^\"']+[\"']",
     "hardcoded password/secret literal"),
]

# 'latest' may only appear in docs/comments explaining why it is forbidden,
# in CHANGELOG comparisons, or in test fixtures — never in download/build code.
LATEST_SCAN_DIRS = ("scripts", "installer", ".github", "windows", "tooling")

WARN_PATTERNS = [
    (r"\bTODO\b", "TODO marker"),
    (r"\bFIXME\b", "FIXME marker"),
    (r"\bHACK\b", "HACK marker"),
]

TEXT_SUFFIXES = {".dart", ".py", ".yml", ".yaml", ".ps1", ".iss", ".rc", ".cpp",
                 ".h", ".cmake", ".txt", ".md", ".env", ".json"}


def iter_files(dirs: tuple[str, ...]) -> list[Path]:
    files: list[Path] = []
    for d in dirs:
        p = ROOT / d
        if not p.exists():
            continue
        for f in p.rglob("*"):
            if f.is_file() and f.suffix.lower() in TEXT_SUFFIXES:
                # Skip this audit's own pattern literals.
                if f.name == "security_audit.py":
                    continue
                files.append(f)
    return files


def audit(strict: bool) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    lib_files = iter_files(("lib", "test", "integration_test"))
    for f in lib_files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = f.relative_to(ROOT).as_posix()
        for pattern, label in ERROR_PATTERNS:
            for m in re.finditer(pattern, text):
                line = text.count("\n", 0, m.start()) + 1
                # Allow obviously-fake fixtures in tests.
                snippet = m.group(0)
                if "test" in rel and ("fake" in snippet.lower() or "example" in snippet.lower()):
                    continue
                errors.append(f"{rel}:{line}: {label}: {snippet[:60]}")

    for f in iter_files(LATEST_SCAN_DIRS):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = f.relative_to(ROOT).as_posix()
        for i, line in enumerate(text.splitlines(), 1):
            low = line.lower()
            if "latest" in low and "releases/latest" in low:
                errors.append(f"{rel}:{i}: downloads from 'latest' release (must pin versions)")
            if "shell=True" in line:
                errors.append(f"{rel}:{i}: shell=True in helper script")

    for f in lib_files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = f.relative_to(ROOT).as_posix()
        for pattern, label in WARN_PATTERNS:
            for m in re.finditer(pattern, text):
                line = text.count("\n", 0, m.start()) + 1
                warnings.append(f"{rel}:{line}: {label}")

    if strict and warnings:
        errors.extend(f"STRICT: {w}" for w in warnings)
    return errors, warnings


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true",
                    help="Promote TODO/FIXME/HACK to errors")
    args = ap.parse_args(argv)
    errors, warnings = audit(args.strict)
    for w in warnings:
        print(f"WARNING: {w}")
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print(f"Security audit: OK ({len(warnings)} warnings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
