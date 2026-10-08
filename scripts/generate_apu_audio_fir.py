#!/usr/bin/env python3
"""Generate the fixed-point Phase 5J anti-alias FIR coefficient module."""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path


TAP_COUNT = 3_073
CUTOFF_HZ = 22_000
INPUT_RATE_NUMERATOR = 19_687_500
INPUT_RATE_DENOMINATOR = 11
COEFFICIENT_BITS = 30
DEFAULT_OUTPUT = Path("verification/apu_audio_fir.py")


def coefficients() -> tuple[int, ...]:
    """Return a symmetric, unity-DC-gain Blackman-windowed sinc in Q2.30."""

    middle = TAP_COUNT // 2
    normalized_cutoff = (
        CUTOFF_HZ * INPUT_RATE_DENOMINATOR / INPUT_RATE_NUMERATOR
    )
    floating: list[float] = []
    for index in range(TAP_COUNT):
        offset = index - middle
        window = (
            0.42
            - 0.5 * math.cos(2.0 * math.pi * index / (TAP_COUNT - 1))
            + 0.08 * math.cos(4.0 * math.pi * index / (TAP_COUNT - 1))
        )
        if offset == 0:
            sinc = 2.0 * normalized_cutoff
        else:
            sinc = math.sin(2.0 * math.pi * normalized_cutoff * offset) / (
                math.pi * offset
            )
        floating.append(sinc * window)

    total = sum(floating)
    scale = 1 << COEFFICIENT_BITS
    half = [round(value * scale / total) for value in floating[: middle + 1]]
    quantized_sum = 2 * sum(half[:-1]) + half[-1]
    half[-1] += scale - quantized_sum
    assert 2 * sum(half[:-1]) + half[-1] == scale
    return tuple(half)


def render() -> str:
    half = coefficients()
    coefficient_bytes = b"".join(
        value.to_bytes(8, "little", signed=True) for value in half
    )
    digest = hashlib.sha256(coefficient_bytes).hexdigest()
    lines = [
        '"""Generated fixed-point anti-alias FIR for Phase 5J. Do not edit."""',
        "",
        f"FIR_TAP_COUNT = {TAP_COUNT}",
        f"FIR_CUTOFF_HZ = {CUTOFF_HZ}",
        f"FIR_COEFFICIENT_BITS = {COEFFICIENT_BITS}",
        f'FIR_HALF_SHA256 = "{digest}"',
        "FIR_HALF = (",
    ]
    for start in range(0, len(half), 8):
        lines.append("    " + ", ".join(map(str, half[start : start + 8])) + ",")
    lines.extend(
        (
            ")",
            "FIR_COEFFICIENTS = FIR_HALF[:-1] + FIR_HALF[::-1]",
            "",
        )
    )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    generated = render()
    if args.check:
        if not args.output.is_file() or args.output.read_text() != generated:
            raise SystemExit(f"stale generated FIR coefficients: {args.output}")
        print(f"Phase 5J FIR is reproducible: {args.output}")
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(generated, encoding="ascii")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
