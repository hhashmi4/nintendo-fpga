#!/usr/bin/env python3
"""Generate exhaustive 6x8 glyph rows from the Python font model."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verification.debug_renderer import FONT_5X8, SUPPORTED_CHARACTERS


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as output:
        for character in SUPPORTED_CHARACTERS:
            for row_index, visible_bits in enumerate(FONT_5X8[character]):
                six_bits = int(visible_bits + "0", 2)
                output.write(f"{ord(character):02x} {row_index:x} {six_bits:02x}\n")
    print(
        f"debug font vectors: glyphs={len(SUPPORTED_CHARACTERS)} "
        f"rows={len(SUPPORTED_CHARACTERS) * 8} output={args.output}"
    )


if __name__ == "__main__":
    main()
