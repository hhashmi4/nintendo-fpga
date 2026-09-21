#!/usr/bin/env python3
"""Pixel-compare Phase 4E-C's complete synthetic game-plus-panel frame."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.debug_renderer import DemoSnapshot, render_combined_frame


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()

    game = bytearray()
    for y in range(480):
        for x in range(512):
            game.extend((x & 0xFF, y & 0xFF, (x ^ y) & 0xFF))
    reference = render_combined_frame(bytes(game), DemoSnapshot())

    observed = bytearray()
    with args.trace.open(encoding="ascii") as source:
        for line_number, line in enumerate(source, start=1):
            try:
                value = bytes.fromhex(line.strip())
            except ValueError as error:
                raise SystemExit(f"invalid RGB at line {line_number}: {error}") from error
            if len(value) != 3:
                raise SystemExit(f"invalid RGB width at line {line_number}")
            observed.extend(value)

    mismatches = sum(a != b for a, b in zip(observed, reference))
    pixel_count = len(observed) // 3
    if len(observed) != len(reference):
        raise SystemExit(
            f"combined frame length mismatch: observed={len(observed)} "
            f"expected={len(reference)}"
        )
    if mismatches:
        raise SystemExit(
            f"combined frame mismatch: pixels={pixel_count} byte_mismatches={mismatches}"
        )

    args.artifact.parent.mkdir(parents=True, exist_ok=True)
    header = b"P6\n640 480\n255\n"
    args.artifact.write_bytes(header + observed)
    pixel_hash = hashlib.sha256(observed).hexdigest()
    artifact_hash = hashlib.sha256(header + observed).hexdigest()
    print(
        "PASS: Phase 4E-C combined software comparison "
        f"pixels={pixel_count} mismatches=0 pixel_sha256={pixel_hash}"
    )
    print(
        f"combined frame: {args.artifact} bytes={args.artifact.stat().st_size} "
        f"sha256={artifact_hash}"
    )


if __name__ == "__main__":
    main()
