#!/usr/bin/env python3
"""Generate IranLink .ico files from the master PNG (stdlib only).

The master art is 1024x1024 RGB. This script:
  1. decodes the PNG (all filter types, 8-bit truecolor),
  2. applies a rounded-corner alpha mask (22% radius),
  3. box-resamples to 256/48/32/16,
  4. writes a multi-image ICO with PNG-compressed entries
     (supported since Windows Vista, so fine for the Win7 SP1 floor).

Outputs:
  windows/runner/resources/app_icon.ico  (EXE + taskbar icon)
  installer/assets/installer.ico         (setup icon)
  assets/icons/tray.ico                  (system-tray icon)
  assets/icons/app_icon.png              (256px preview / docs)

Usage: python scripts/make_icons.py [--master assets/images/app_icon_master.png]
"""

from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path

SIZES = (256, 48, 32, 16)
CORNER_RADIUS_RATIO = 0.22


def _chunks(data: bytes):
    pos = 8
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG file"
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        yield ctype, data[pos + 8:pos + 8 + length]
        pos += 12 + length


def decode_png_rgb(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    raw = b""
    width = height = 0
    for ctype, cdata in _chunks(data):
        if ctype == b"IHDR":
            width, height, bitdepth, colortype, _, _, _ = struct.unpack(">IIBBBBB", cdata)
            assert (bitdepth, colortype) == (8, 2), f"need 8-bit RGB, got {bitdepth}/{colortype}"
        elif ctype == b"IDAT":
            raw += cdata
    px = zlib.decompress(raw)
    stride = width * 3
    out = bytearray(width * height * 3)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        f = px[pos]
        pos += 1
        line = bytearray(px[pos:pos + stride])
        pos += stride
        if f == 1:  # Sub
            for i in range(3, stride):
                line[i] = (line[i] + line[i - 3]) & 0xFF
        elif f == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:  # Average
            for i in range(stride):
                a = line[i - 3] if i >= 3 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:  # Paeth
            for i in range(stride):
                a = line[i - 3] if i >= 3 else 0
                b = prev[i]
                c = prev[i - 3] if i >= 3 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, bytes(out)


def rounded_alpha(n: int) -> bytearray:
    r = int(n * CORNER_RADIUS_RATIO)
    alpha = bytearray(b"\xff" * (n * n))
    for y in range(r + 1):
        for x in range(r + 1):
            # Distance from the corner arc center; 1px antialiased edge.
            d = math.hypot(r - x, r - y)
            if d > r:
                a = 0
            elif d > r - 1:
                a = int(255 * (r - d))
            else:
                continue
            for cx, cy in ((x, y), (n - 1 - x, y), (x, n - 1 - y), (n - 1 - x, n - 1 - y)):
                alpha[cy * n + cx] = min(alpha[cy * n + cx], a)
    return alpha


def resample_box(src: bytes, sw: int, sh: int, n: int, alpha: bytes) -> bytes:
    """Box-resample RGB + alpha to n*n RGBA."""
    out = bytearray(n * n * 4)
    for y in range(n):
        y0 = y * sh // n
        y1 = max(y0 + 1, (y + 1) * sh // n)
        for x in range(n):
            x0 = x * sw // n
            x1 = max(x0 + 1, (x + 1) * sw // n)
            rs = gs = bs = aas = cnt = 0
            for sy in range(y0, y1):
                row = sy * sw
                for sx in range(x0, x1):
                    o = (row + sx) * 3
                    rs += src[o]
                    gs += src[o + 1]
                    bs += src[o + 2]
                    aas += alpha[row + sx]
                    cnt += 1
            o = (y * n + x) * 4
            out[o] = rs // cnt
            out[o + 1] = gs // cnt
            out[o + 2] = bs // cnt
            out[o + 3] = aas // cnt
    return bytes(out)


def encode_png_rgba(n: int, rgba: bytes) -> bytes:
    def chunk(ctype: bytes, cdata: bytes) -> bytes:
        return struct.pack(">I", len(cdata)) + ctype + cdata + struct.pack(">I", zlib.crc32(ctype + cdata))
    stride = n * 4
    raw = bytearray()
    for y in range(n):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def write_ico(images: list[tuple[int, bytes]], path: Path) -> None:
    header = struct.pack("<HHH", 0, 1, len(images))
    entries = bytearray()
    offset = 6 + 16 * len(images)
    blob = bytearray()
    for size, data in images:
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        blob += data
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(header) + bytes(entries) + bytes(blob))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--master", default="assets/images/app_icon_master.png")
    ap.add_argument("--root", default=".")
    args = ap.parse_args(argv)
    root = Path(args.root)
    w, h, rgb = decode_png_rgb(root / args.master)
    assert w == h, "master icon must be square"
    alpha = rounded_alpha(w)
    images: list[tuple[int, bytes]] = []
    for size in SIZES:
        rgba = resample_box(rgb, w, h, size, bytes(alpha))
        images.append((size, encode_png_rgba(size, rgba)))
    targets = [
        root / "windows" / "runner" / "resources" / "app_icon.ico",
        root / "installer" / "assets" / "installer.ico",
        root / "assets" / "icons" / "tray.ico",
    ]
    for target in targets:
        write_ico(images, target)
        print(f"  {target.relative_to(root)} ({target.stat().st_size} bytes)")
    preview = root / "assets" / "icons" / "app_icon.png"
    preview.write_bytes(images[0][1])
    print(f"  {preview.relative_to(root)} ({preview.stat().st_size} bytes)")
    print("Icons: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
