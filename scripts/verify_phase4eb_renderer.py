#!/usr/bin/env python3
"""Compare every RTL debug pixel with the Python reference and emit a PPM."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verification.debug_renderer import render_frame


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()

    lines = args.trace.read_text(encoding="ascii").splitlines()
    if len(lines) != 640 * 480:
        raise SystemExit(f"expected 307200 pixels, found {len(lines)}")
    rtl = bytes.fromhex("".join(lines))
    reference = render_frame()
    mismatches = sum(
        rtl[offset:offset + 3] != reference[offset:offset + 3]
        for offset in range(0, len(reference), 3)
    )
    if mismatches:
        first = next(
            offset // 3
            for offset in range(0, len(reference), 3)
            if rtl[offset:offset + 3] != reference[offset:offset + 3]
        )
        x, y = first % 640, first // 640
        raise SystemExit(
            f"renderer mismatch: pixels={mismatches}, first=({x},{y}), "
            f"rtl={rtl[first*3:first*3+3].hex()}, "
            f"reference={reference[first*3:first*3+3].hex()}"
        )

    header = b"P6\n640 480\n255\n"
    args.artifact.parent.mkdir(parents=True, exist_ok=True)
    args.artifact.write_bytes(header + rtl)
    pixel_hash = hashlib.sha256(rtl).hexdigest()
    artifact_hash = hashlib.sha256(header + rtl).hexdigest()
    print(
        "PASS: Phase 4E-B pixel-perfect renderer comparison "
        f"pixels=307200 mismatches=0 pixel_sha256={pixel_hash}"
    )
    print(
        f"developer frame: {args.artifact} bytes={args.artifact.stat().st_size} "
        f"sha256={artifact_hash}"
    )


if __name__ == "__main__":
    main()
