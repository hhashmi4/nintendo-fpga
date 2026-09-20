#!/usr/bin/env python3
"""Generate all Phase 3F sprite-range comparison vectors."""

from argparse import ArgumentParser
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_sprite_eval import (  # noqa: E402
    relative_sprite_row,
    sprite_height,
    sprite_in_range,
)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    cases = 0
    with args.output.open("w", encoding="ascii") as stream:
        for size_16 in (False, True):
            for scanline in range(240):
                for sprite_y in range(256):
                    stream.write(
                        f"{scanline} {sprite_y} {int(size_16)} "
                        f"{relative_sprite_row(scanline, sprite_y)} "
                        f"{sprite_height(size_16)} "
                        f"{int(sprite_in_range(scanline, sprite_y, size_16))}\n"
                    )
                    cases += 1
    print(f"Phase 3F sprite-range vectors: cases={cases}")


if __name__ == "__main__":
    main()
