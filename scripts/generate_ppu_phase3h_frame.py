#!/usr/bin/env python3
"""Generate a deterministic integrated Phase 3H scene and final pixels."""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_background import BackgroundModel  # noqa: E402
from verification.ppu_memory import MirroringMode, PpuMemoryModel  # noqa: E402
from verification.ppu_pixel_mixer import (  # noqa: E402
    BackgroundPixel,
    SpriteCandidate,
    mix_pixel,
)
from verification.ppu_registers import PpuBusInputs, PpuRegisterModel  # noqa: E402
from verification.ppu_sprite_render import render_scene_pixel  # noqa: E402
from verification.ppu_timing import PpuTimingModel  # noqa: E402


SEED = 0x3F38A6E1
PPUCTRL_VALUE = 0x10  # BG table $1000, 8x8 sprites from $0000.
PPUMASK_VALUE = 0xBE  # BG/sprites + both left edges + red/blue emphasis.


def set_pattern(chr_memory: bytearray, table: int, tile: int, rows: list[int],
                high_rows: list[int] | None = None) -> None:
    high_rows = high_rows or [0] * 8
    base = (table << 12) | ((tile & 0xFF) << 4)
    for row in range(8):
        chr_memory[base | row] = rows[row] & 0xFF
        chr_memory[base | 8 | row] = high_rows[row] & 0xFF


def build_scene() -> tuple[bytearray, bytearray, bytearray, bytearray]:
    rng = random.Random(SEED)
    memory = PpuMemoryModel(MirroringMode.VERTICAL)

    # Two physical nametables form broad recognizable regions with varying
    # attribute palettes. Tile zero is intentionally used in small windows.
    for page in range(2):
        base = page * 0x400
        for tile_y in range(30):
            for tile_x in range(32):
                selector = (
                    tile_x // 4 + tile_y // 3 + page * 2 + rng.randrange(3)
                ) % 7
                tile = 0 if (tile_x + tile_y * 3) % 29 == 0 else selector + 1
                memory.ciram[base + tile_y * 32 + tile_x] = tile
        for attribute_y in range(8):
            for attribute_x in range(8):
                palettes = [
                    (attribute_x + attribute_y + quadrant + page +
                     rng.randrange(2)) & 3
                    for quadrant in range(4)
                ]
                value = sum(palette << (quadrant * 2)
                            for quadrant, palette in enumerate(palettes))
                memory.ciram[base + 0x3C0 + attribute_y * 8 + attribute_x] = value

    # Background table $1000: checkerboards, stripes, diagonals, and solids.
    background_rows = {
        0: ([0x00] * 8, [0x00] * 8),
        1: ([0xAA, 0x55] * 4, [0x00] * 8),
        2: ([0xF0, 0xF0, 0x0F, 0x0F] * 2, [0x33] * 8),
        3: ([0xFF] * 8, [0x00, 0x18, 0x3C, 0x7E, 0x7E, 0x3C, 0x18, 0x00]),
        4: ([0x80 >> row for row in range(8)],
            [0x01 << row for row in range(8)]),
        5: ([0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81],
            [0x00, 0x18, 0x24, 0x42, 0x42, 0x24, 0x18, 0x00]),
        6: ([0xFF, 0x81, 0xBD, 0xA5, 0xA5, 0xBD, 0x81, 0xFF],
            [0x00, 0x7E, 0x42, 0x5A, 0x5A, 0x42, 0x7E, 0x00]),
        7: ([0xCC, 0xCC, 0x33, 0x33] * 2, [0x0F, 0xF0] * 4),
    }
    for tile, (low, high) in background_rows.items():
        set_pattern(memory.chr, 1, tile, low, high)

    # Sprite table $0000. Each row is asymmetric to exercise orientation and
    # provides opaque overlap with the background for sprite-zero hit.
    for tile in range(0x20, 0x30):
        low = [
            ((0x81 >> (row & 3)) | (1 << ((tile + row) & 7)) |
             rng.randrange(256)) & 0xFF
            for row in range(8)
        ]
        high = [
            ((0x42 << (row & 1)) ^ (tile * 7 + row * 13) ^
             rng.randrange(256)) & 0xFF
            for row in range(8)
        ]
        set_pattern(memory.chr, 0, tile, low, high)

    oam = bytearray([0xF0, 0x00, 0x00, 0x00] * 64)
    sprites = [
        (8, 0x20, 0x21, 40),   # sprite zero, behind opaque background
        (24, 0x21, 0x02, 64),  # front
        (24, 0x22, 0x43, 68),  # horizontal flip and overlap
        (40, 0x23, 0x80, 112), # vertical flip
        (60, 0x24, 0x01, 0),   # left-edge content
        (80, 0x25, 0x22, 248), # behind and partly off-right
        (92, 0x26, 0x03, 150),
        (92, 0x27, 0x00, 152),
    ]
    # Twelve simultaneous in-range sprites force retained overflow behavior.
    sprites.extend(
        (100, 0x20 + rng.randrange(16), rng.randrange(4),
         (16 + index * 15 + rng.randrange(8)) & 0xFF)
        for index in range(12)
    )
    for index, values in enumerate(sprites):
        oam[index * 4:index * 4 + 4] = bytes(values)

    palette = bytearray(
        ((index * 9 + (index >> 2) * 5 + 0x03) & 0x3F)
        for index in range(32)
    )
    # Explicit universal and palette anchors ease waveform inspection.
    palette[0x00] = 0x21
    palette[0x01:0x04] = bytes((0x01, 0x16, 0x2A))
    palette[0x11:0x14] = bytes((0x06, 0x19, 0x30))
    return memory.ciram, memory.chr, oam, palette


def main() -> None:
    if len(sys.argv) != 7:
        raise SystemExit(
            f"usage: {sys.argv[0]} CIRAM CHR OAM PALETTE PIXELS STATS"
        )
    ciram_path, chr_path, oam_path, palette_path, pixel_path, stats_path = (
        map(Path, sys.argv[1:])
    )
    for path in (ciram_path, chr_path, oam_path, palette_path,
                 pixel_path, stats_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    ciram, chr_memory, oam, palette = build_scene()
    ciram_path.write_text("".join(f"{value:02x}\n" for value in ciram),
                          encoding="ascii")
    chr_path.write_text("".join(f"{value:02x}\n" for value in chr_memory),
                        encoding="ascii")
    oam_path.write_text("".join(f"{value:02x}\n" for value in oam),
                        encoding="ascii")
    palette_path.write_text("".join(f"{value:02x}\n" for value in palette),
                            encoding="ascii")

    memory = PpuMemoryModel(MirroringMode.VERTICAL)
    memory.ciram[:] = ciram
    memory.chr[:] = chr_memory
    memory.palette[:] = palette
    registers = PpuRegisterModel()
    registers.ppuctrl = PPUCTRL_VALUE
    registers.ppumask = PPUMASK_VALUE
    timing = PpuTimingModel()
    background_model = BackgroundModel()
    counts = [0] * 7
    behind_zero_hit_pixels = 0

    with pixel_path.open("w", encoding="ascii") as stream:
        while counts[0] < 61_440:
            pre = timing.snapshot()
            visible = timing.visible_pixel(True)
            x, y = timing.pixel if timing.pixel is not None else (0, 0)
            bg = background_model.observe(
                reset=False,
                ppu_enable=True,
                dot=pre.dot,
                scanline=pre.scanline,
                visible_pixel=visible,
                pixel_x=x,
                pixel_y=y,
                rendering_enabled=registers.rendering_enabled,
                background_enabled=bool(registers.ppumask & 0x08),
                show_background_left=bool(registers.ppumask & 0x02),
                pattern_table=(registers.ppuctrl >> 4) & 1,
                fine_x=registers.x,
                v=registers.v,
                memory_grant=True,
            )
            memory_data = memory.read(bg.memory_address)
            sprite_pixel = render_scene_pixel(
                primary_oam=oam,
                chr_memory=chr_memory,
                x=x,
                y=y,
                size_16=False,
                pattern_table=(registers.ppuctrl >> 3) & 1,
                sprites_enabled=bool(registers.ppumask & 0x10),
                show_sprites_left=bool(registers.ppumask & 0x04),
            ) if visible else None

            hit = False
            if visible and sprite_pixel is not None:
                final = mix_pixel(
                    reset=False,
                    ppu_enable=True,
                    visible_pixel=True,
                    x=x,
                    y=y,
                    background=BackgroundPixel(
                        bg.pixel_valid, bg.x, bg.y, bg.pattern,
                        bg.palette, bg.opaque,
                    ),
                    sprite=SpriteCandidate(
                        sprite_pixel.valid, sprite_pixel.x, sprite_pixel.y,
                        sprite_pixel.pattern, sprite_pixel.palette,
                        sprite_pixel.opaque,
                        sprite_pixel.behind_background,
                        sprite_pixel.is_zero, sprite_pixel.slot,
                        sprite_pixel.original_index,
                    ),
                    background_enabled=bool(registers.ppumask & 0x08),
                    sprites_enabled=bool(registers.ppumask & 0x10),
                    show_background_left=bool(registers.ppumask & 0x02),
                    show_sprites_left=bool(registers.ppumask & 0x04),
                    grayscale=bool(registers.ppumask & 0x01),
                    emphasis=(registers.ppumask >> 5) & 7,
                    palette_ram=memory.palette,
                )
                print(
                    final.x, final.y, int(final.source),
                    final.palette_address, final.nes_color, final.emphasis,
                    int(final.sprite_zero_hit),
                    file=stream,
                )
                counts[0] += 1
                counts[1 + int(final.source)] += 1
                counts[4] += 1
                counts[5] += int(final.sprite_zero_hit)
                counts[6] += int(final.valid and bool(registers.ppumask & 1))
                hit = final.sprite_zero_hit
                behind_zero_hit_pixels += int(
                    hit and sprite_pixel.behind_background and
                    final.source.value == 1
                )

            background_model.clock(
                bg,
                reset=False,
                ppu_enable=True,
                v=registers.v,
                memory_data=memory_data,
            )
            registers.clock(PpuBusInputs(
                ppu_enable=True,
                dot=pre.dot,
                scanline=pre.scanline,
                vblank_start_event=timing.vblank_start(True),
                status_clear_event=timing.vblank_end(True),
                sprite_zero_hit_set=hit,
            ))
            timing.clock(
                ppu_enable=True,
                rendering_enabled=registers.rendering_enabled,
            )

    assert sum(counts[1:4]) == 61_440
    assert counts[2] > 0 and counts[3] > 0 and counts[1] > 0
    assert counts[5] > 0 and behind_zero_hit_pixels > 0
    stats_path.write_text(
        " ".join(str(value) for value in (*counts, behind_zero_hit_pixels))
        + "\n",
        encoding="ascii",
    )
    print(
        f"Phase 3H full-frame reference: seed=0x{SEED:08X} "
        f"visible={counts[0]} universal={counts[1]} background={counts[2]} "
        f"sprite={counts[3]} palette_reads={counts[4]} "
        f"zero_hits={counts[5]} grayscale={counts[6]} "
        f"behind_zero_hits={behind_zero_hit_pixels}"
    )


if __name__ == "__main__":
    main()
