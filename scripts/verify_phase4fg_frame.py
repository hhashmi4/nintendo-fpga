#!/usr/bin/env python3
"""Verify the deterministic frame rendered from the runtime-loaded CHR ROM."""

from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.video import palette_rgb  # noqa: E402


EXPECTED_SHA256 = "54648910b2b993d95d58980fefa422b4f8f88cdcb8ef695be437bdf0f9b12f0d"
PIXEL_COUNT = 256 * 240


def verify_frame(source: Path, ppm: Path) -> None:
    raw = source.read_bytes()
    values = [int(line, 16) for line in raw.decode("ascii").splitlines()]
    if len(values) != PIXEL_COUNT:
        raise SystemExit(f"{source}: {len(values)} pixels, expected {PIXEL_COUNT}")
    if any(value > 0x1FF for value in values):
        raise SystemExit(f"{source}: pixel exceeds 9-bit NES color/emphasis")

    observed = sha256(raw).hexdigest()
    if observed != EXPECTED_SHA256:
        raise SystemExit(
            f"{source}: frame mismatch SHA-256 {observed}, "
            f"expected {EXPECTED_SHA256}"
        )

    rgb = bytearray()
    for value in values:
        rgb.extend(palette_rgb(value & 0x3F, (value >> 6) & 0x07))
    ppm.write_bytes(b"P6\n256 240\n255\n" + rgb)
    print(
        f"PASS: Phase 4F-G runtime CHR-ROM frame={source.name} "
        f"pixels={PIXEL_COUNT} mismatches=0 sha256={observed}"
    )


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit(f"usage: {sys.argv[0]} FRAME_HEX [OUTPUT_PPM]")
    source = Path(sys.argv[1])
    ppm = Path(sys.argv[2]) if len(sys.argv) == 3 else source.with_suffix(".ppm")
    verify_frame(source, ppm)


if __name__ == "__main__":
    main()
