#!/usr/bin/env python3
"""Create a deterministic OAM/CHR scene and 61,440 Phase 3G pixels."""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_sprite_render import render_scene_pixel  # noqa: E402

SEED = 0x3F37A6E1


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(f"usage: {sys.argv[0]} OAM CHR PIXELS STATS")
    oam_path, chr_path, pixel_path, stats_path = map(Path, sys.argv[1:])
    for path in (oam_path, chr_path, pixel_path, stats_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    rng = random.Random(SEED)
    oam = [0] * 256
    # A structured but dense scene exercises first-eight selection, overlap,
    # both flips, clipping, sprite zero, priority, and off-right-edge pixels.
    for index in range(64):
        base = index * 4
        y = (index * 11 + (index // 8) * 3) % 232
        tile = (index * 29 + 7) & 0xFF
        attributes = index & 3
        attributes |= ((index >> 2) & 1) << 5
        attributes |= ((index >> 3) & 1) << 6
        attributes |= ((index >> 4) & 1) << 7
        if index < 12:
            # Force early-scanline overlap and left-edge clipping coverage.
            y = 0 if index < 8 else 5
            x = (8 if index == 0 else index) if index < 8 else 4
        elif index >= 60:
            x = 248 + (index - 60) * 2
        else:
            x = (index * 37 + (index // 5) * 9) & 0xFF
        oam[base : base + 4] = [y, tile, attributes, x]

    # Deterministic fake cartridge CHR for simulation only.
    chr_memory = [rng.randrange(256) for _ in range(8192)]
    # Guarantee visible/nonzero asymmetric rows for sprite zero and directed
    # edge sprites while retaining random data everywhere else.
    for tile in (oam[1], oam[5], oam[9], oam[13]):
        bank = (tile & 1) << 12
        pair = tile & 0xFE
        for row in range(16):
            selected_tile = pair + (row >> 3)
            address = bank | (selected_tile << 4) | (row & 7)
            chr_memory[address] = (0x81 ^ (row * 13)) & 0xFF
            chr_memory[address | 8] = (0x42 ^ (row * 7)) & 0xFF

    oam_path.write_text(
        "".join(f"{value:02x}\n" for value in oam), encoding="ascii"
    )
    chr_path.write_text(
        "".join(f"{value:02x}\n" for value in chr_memory), encoding="ascii"
    )

    opaque = 0
    sprite_zero = 0
    clipped = 0
    with pixel_path.open("w", encoding="ascii") as stream:
        for y in range(240):
            for x in range(256):
                pixel = render_scene_pixel(
                    primary_oam=oam,
                    chr_memory=chr_memory,
                    x=x,
                    y=y,
                    size_16=True,
                    pattern_table=0,
                    sprites_enabled=True,
                    show_sprites_left=False,
                )
                unclipped = render_scene_pixel(
                    primary_oam=oam,
                    chr_memory=chr_memory,
                    x=x,
                    y=y,
                    size_16=True,
                    pattern_table=0,
                    sprites_enabled=True,
                    show_sprites_left=True,
                )
                was_clipped = x < 8 and unclipped.opaque and not pixel.opaque
                opaque += int(pixel.opaque)
                sprite_zero += int(pixel.opaque and pixel.is_zero)
                clipped += int(was_clipped)
                print(
                    x,
                    y,
                    pixel.pattern,
                    pixel.palette,
                    pixel.palette_index,
                    int(pixel.opaque),
                    int(pixel.behind_background),
                    int(pixel.is_zero),
                    pixel.slot,
                    pixel.original_index,
                    int(was_clipped),
                    file=stream,
                )
    transparent = 61_440 - opaque
    stats_path.write_text(
        f"61440 {opaque} {transparent} {sprite_zero} {clipped}\n",
        encoding="ascii",
    )
    print(
        f"Phase 3G full-frame reference: seed=0x{SEED:08X} "
        f"visible=61440 opaque={opaque} transparent={transparent} "
        f"sprite_zero={sprite_zero} clipped={clipped}"
    )


if __name__ == "__main__":
    main()
