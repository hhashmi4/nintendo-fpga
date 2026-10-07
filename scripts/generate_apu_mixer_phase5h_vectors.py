#!/usr/bin/env python3
"""Generate exhaustive separated-domain and deterministic combined vectors."""

from __future__ import annotations

from argparse import ArgumentParser
from pathlib import Path
import random
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.apu_mixer import quantized_mix  # noqa: E402


RANDOM_SEED = 0x0058_2026
RANDOM_COMBINATIONS = 4_096


def main() -> int:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rows: list[tuple[int, int, int, int, int]] = []
    rows.extend((p1, p2, 0, 0, 0) for p1 in range(16) for p2 in range(16))
    rows.extend(
        (0, 0, triangle, noise, dmc)
        for triangle in range(16)
        for noise in range(16)
        for dmc in range(128)
    )
    directed = [
        (0, 0, 0, 0, 0),
        (1, 0, 0, 0, 0),
        (15, 0, 0, 0, 0),
        (0, 15, 0, 0, 0),
        (15, 15, 0, 0, 0),
        (0, 0, 1, 0, 0),
        (0, 0, 15, 0, 0),
        (0, 0, 0, 1, 0),
        (0, 0, 0, 15, 0),
        (0, 0, 0, 0, 1),
        (0, 0, 0, 0, 127),
        (0, 0, 15, 15, 0),
        (0, 0, 15, 0, 127),
        (0, 0, 0, 15, 127),
        (0, 0, 15, 15, 127),
        (1, 1, 1, 1, 1),
        (15, 15, 15, 15, 127),
    ]
    rows.extend(directed)
    randomizer = random.Random(RANDOM_SEED)
    rows.extend(
        (
            randomizer.randrange(16),
            randomizer.randrange(16),
            randomizer.randrange(16),
            randomizer.randrange(16),
            randomizer.randrange(128),
        )
        for _ in range(RANDOM_COMBINATIONS)
    )

    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        for values in rows:
            expected = quantized_mix(*values)
            stream.write(" ".join(str(value) for value in (*values, expected)) + "\n")

    print(
        "Phase 5H mixer Python reference: "
        f"rows={len(rows)} pulse_pairs=256 tnd=32768 "
        f"directed={len(directed)} random={RANDOM_COMBINATIONS} "
        f"seed=0x{RANDOM_SEED:08x}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
