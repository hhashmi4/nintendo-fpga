#!/usr/bin/env python3
"""Pixel-compare all five Phase 4E-D combined Developer Mode pages."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.debug_renderer import DemoSnapshot, render_combined_frame


def game_fixture() -> bytes:
    pixels = bytearray()
    for y in range(480):
        for x in range(512):
            pixels.extend((x & 0xFF, y & 0xFF, (x ^ y) & 0xFF))
    return bytes(pixels)


def read_trace(path: Path) -> bytes:
    observed = bytearray()
    with path.open(encoding="ascii") as source:
        for line_number, line in enumerate(source, start=1):
            try:
                value = bytes.fromhex(line.strip())
            except ValueError as error:
                raise SystemExit(
                    f"{path}: invalid RGB at line {line_number}: {error}"
                ) from error
            if len(value) != 3:
                raise SystemExit(f"{path}: invalid RGB width at line {line_number}")
            observed.extend(value)
    return bytes(observed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace_directory", type=Path)
    parser.add_argument("artifact_directory", type=Path)
    args = parser.parse_args()

    args.artifact_directory.mkdir(parents=True, exist_ok=True)
    game = game_fixture()
    header = b"P6\n640 480\n255\n"
    total_pixels = 0
    for page in range(5):
        trace = args.trace_directory / f"phase4ed_page{page}_combined_pixels.txt"
        observed = read_trace(trace)
        reference = render_combined_frame(game, DemoSnapshot(), page=page)
        if len(observed) != len(reference):
            raise SystemExit(
                f"page {page}: frame length mismatch: observed={len(observed)} "
                f"expected={len(reference)}"
            )
        mismatches = sum(a != b for a, b in zip(observed, reference))
        if mismatches:
            raise SystemExit(
                f"page {page}: byte mismatches={mismatches} "
                f"pixels={len(observed) // 3}"
            )
        artifact = args.artifact_directory / f"phase4ed_page{page}.ppm"
        artifact.write_bytes(header + observed)
        pixel_hash = hashlib.sha256(observed).hexdigest()
        artifact_hash = hashlib.sha256(header + observed).hexdigest()
        pixels = len(observed) // 3
        total_pixels += pixels
        print(
            f"PASS: Phase 4E-D page={page} pixels={pixels} mismatches=0 "
            f"pixel_sha256={pixel_hash}"
        )
        print(
            f"page frame: {artifact} bytes={artifact.stat().st_size} "
            f"sha256={artifact_hash}"
        )
    print(f"PASS: Phase 4E-D five-page comparison total_pixels={total_pixels}")


if __name__ == "__main__":
    main()
