#!/usr/bin/env python3
"""Compare every traced Phase 3K active pixel with the Python video model."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.video import diagnostic_rgb, palette_rgb, scaled_coordinate


VISIBLE_PIXELS = 640 * 480


def expected_framebuffer_pixel(x: int, y: int) -> tuple[int, int, int]:
    inside, nes_x, nes_y, _ = scaled_coordinate(x, y)
    if not inside:
        return (0, 0, 0)
    color = (nes_x ^ nes_y) & 0x3F
    emphasis = (nes_x >> 5) & 0x07
    return palette_rgb(color, emphasis)


def verify(path: Path) -> None:
    counts = [0, 0]
    mismatches = 0
    with path.open(encoding="ascii") as trace:
        for line_number, line in enumerate(trace, start=1):
            mode_text, x_text, y_text, rgb_text = line.split()
            mode, x, y = int(mode_text), int(x_text), int(y_text)
            observed = tuple(bytes.fromhex(rgb_text))
            expected = (
                expected_framebuffer_pixel(x, y)
                if mode == 0
                else diagnostic_rgb(x, y)
            )
            if observed != expected:
                mismatches += 1
                if mismatches <= 10:
                    print(
                        f"line {line_number}: mode={mode} ({x},{y}) "
                        f"observed={observed} expected={expected}",
                        file=sys.stderr,
                    )
            counts[mode] += 1

    if counts != [VISIBLE_PIXELS, VISIBLE_PIXELS] or mismatches:
        raise SystemExit(
            f"VGA trace failed: counts={counts}, mismatches={mismatches}"
        )
    print(
        "Phase 3K Python VGA trace comparison passed: "
        f"framebuffer={counts[0]}, diagnostic={counts[1]}, mismatches=0"
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_vga_trace.py TRACE")
    verify(Path(sys.argv[1]))
