#!/usr/bin/env python3
"""Reference-check one complete VGA frame captured from the real NES core."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.video import palette_rgb, scaled_coordinate


def verify(path: Path) -> None:
    mismatches = 0
    count = 0
    with path.open(encoding="ascii") as trace:
        for line_number, line in enumerate(trace, start=1):
            x_text, y_text, inside_text, pixel_text, rgb_text = line.split()
            x, y, inside = int(x_text), int(y_text), bool(int(inside_text))
            pixel = int(pixel_text, 16)
            observed = tuple(bytes.fromhex(rgb_text))
            mapped, _, _, _ = scaled_coordinate(x, y)
            expected = (
                palette_rgb(pixel & 0x3F, (pixel >> 6) & 0x07)
                if inside
                else (0, 0, 0)
            )
            if inside != mapped or observed != expected:
                mismatches += 1
                if mismatches <= 10:
                    print(
                        f"line {line_number}: ({x},{y}) inside={inside}/{mapped} "
                        f"pixel={pixel:03x} observed={observed} expected={expected}",
                        file=sys.stderr,
                    )
            count += 1
    if count != 640 * 480 or mismatches:
        raise SystemExit(
            f"integrated VGA trace failed: pixels={count}, mismatches={mismatches}"
        )
    print(
        "Phase 3K Python integrated VGA comparison passed: "
        f"pixels={count}, mismatches=0"
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_nes_vga_trace.py TRACE")
    verify(Path(sys.argv[1]))
