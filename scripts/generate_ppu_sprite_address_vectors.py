#!/usr/bin/env python3
"""Generate exhaustive independent Phase 3G sprite-address vectors."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_sprite_render import sprite_pattern_address  # noqa: E402


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    vectors_8 = 0
    vectors_16 = 0
    with output.open("w", encoding="ascii") as stream:
        for table in range(2):
            for tile in range(256):
                for row in range(8):
                    for flip in range(2):
                        result = sprite_pattern_address(
                            tile=tile,
                            relative_row=row,
                            size_16=False,
                            pattern_table=table,
                            vertical_flip=bool(flip),
                        )
                        print(
                            0,
                            table,
                            tile,
                            row,
                            flip,
                            result.row,
                            result.low,
                            result.high,
                            file=stream,
                        )
                        vectors_8 += 1
        for tile in range(256):
            for row in range(16):
                for flip in range(2):
                    result = sprite_pattern_address(
                        tile=tile,
                        relative_row=row,
                        size_16=True,
                        pattern_table=(tile ^ row) & 1,
                        vertical_flip=bool(flip),
                    )
                    print(
                        1,
                        (tile ^ row) & 1,
                        tile,
                        row,
                        flip,
                        result.row,
                        result.low,
                        result.high,
                        file=stream,
                    )
                    vectors_16 += 1
    print(
        "Phase 3G sprite-address vectors: "
        f"8x8_vectors={vectors_8} 8x8_plane_cases={vectors_8 * 2} "
        f"8x16_vectors={vectors_16} 8x16_plane_cases={vectors_16 * 2} "
        f"total_plane_cases={(vectors_8 + vectors_16) * 2}"
    )


if __name__ == "__main__":
    main()
