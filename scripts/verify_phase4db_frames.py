#!/usr/bin/env python3
"""Verify deterministic PPU frames and emit developer-viewable PPM files."""

from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.video import palette_rgb  # noqa: E402


EXPECTED = {
    "title": "e7707b93cddfbdfa148dffb38523d03013d2ff9a717981a416cb00078db05ae2",
    "started": "a49d66d2e3a6662c3b8113f701f70a4dc44e932e05d18100c270de626f951e52",
    "a": "ffe9da19bfc93c2c717dd5dfb046ebe8cb7330503556e4a12deb6d24d54f8939",
    "b": "35bba0c5f1de0b9159cccd77e4f7a045cd4e103950fad1c35bc17101a27b14ba",
    "select": "35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c",
    "right": "71d5e3a9e3268eddd86d5653fbb00ce16056fd73fbc6c1cf82b536cc2aacdb41",
    "left": "35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c",
    "up": "83aaf2a6db7ad77d207c9cbad8293e4d2aa9f7e1b9379383aa989d2cd284d159",
    "down": "35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c",
}


def verify_frame(source: Path, expected_hash: str) -> Path:
    raw = source.read_bytes()
    observed_hash = sha256(raw).hexdigest()
    if observed_hash != expected_hash:
        raise SystemExit(
            f"{source}: SHA-256 {observed_hash}, expected {expected_hash}"
        )

    values = [int(line, 16) for line in raw.decode("ascii").splitlines()]
    if len(values) != 256 * 240:
        raise SystemExit(f"{source}: {len(values)} pixels, expected 61440")
    if any(value > 0x1FF for value in values):
        raise SystemExit(f"{source}: pixel exceeds 9-bit NES color/emphasis")

    ppm = source.with_suffix(".ppm")
    rgb = bytearray()
    for value in values:
        rgb.extend(palette_rgb(value & 0x3F, (value >> 6) & 0x07))
    ppm.write_bytes(b"P6\n256 240\n255\n" + rgb)
    return ppm


def main() -> None:
    directory = Path(sys.argv[1]) if len(sys.argv) == 2 else Path("build/sim")
    if len(sys.argv) > 2:
        raise SystemExit(f"usage: {sys.argv[0]} [FRAME_DIRECTORY]")
    for name, expected_hash in EXPECTED.items():
        source = directory / f"phase4db_{name}.hex"
        ppm = verify_frame(source, expected_hash)
        print(f"{name}: {expected_hash} ({ppm})")
    print("PASS: Phase 4D-B deterministic FPGA PPU frames")


if __name__ == "__main__":
    main()
