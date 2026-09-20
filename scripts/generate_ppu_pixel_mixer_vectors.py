#!/usr/bin/env python3
"""Generate deterministic Phase 3H standalone mixer reference vectors."""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_pixel_mixer import (  # noqa: E402
    BackgroundPixel,
    PixelSource,
    SpriteCandidate,
    mix_pixel,
    palette_index,
)


SEED = 0x38202601
RANDOM_CYCLES = 120_000


def emit(
    stream,
    *,
    reset: bool,
    ppu_enable: bool,
    visible: bool,
    x: int,
    y: int,
    background_enabled: bool,
    sprites_enabled: bool,
    bg_left: bool,
    sp_left: bool,
    grayscale: bool,
    emphasis: int,
    bg: BackgroundPixel,
    sp: SpriteCandidate,
    palette: list[int],
):
    result = mix_pixel(
        reset=reset,
        ppu_enable=ppu_enable,
        visible_pixel=visible,
        x=x,
        y=y,
        background=bg,
        sprite=sp,
        background_enabled=background_enabled,
        sprites_enabled=sprites_enabled,
        show_background_left=bg_left,
        show_sprites_left=sp_left,
        grayscale=grayscale,
        emphasis=emphasis,
        palette_ram=palette,
    )
    palette_data = palette[palette_index(result.palette_address)]
    values = (
        int(reset), int(ppu_enable), int(visible), x, y,
        int(background_enabled), int(sprites_enabled), int(bg_left),
        int(sp_left), int(grayscale), emphasis,
        int(bg.valid), bg.x, bg.y, bg.pattern, bg.palette, int(bg.opaque),
        int(sp.valid), sp.x, sp.y, sp.pattern, sp.palette, int(sp.opaque),
        int(sp.behind_background), int(sp.is_zero), sp.slot,
        sp.original_index, palette_data,
        result.palette_address, int(result.valid), result.x, result.y,
        result.nes_color, result.emphasis, int(result.source),
        int(result.sprite_zero_hit), result.winning_sprite_slot,
        int(result.winning_sprite_zero),
    )
    stream.write(" ".join(str(value) for value in values) + "\n")
    return result


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} VECTORS STATS")
    vector_path, stats_path = map(Path, sys.argv[1:])
    vector_path.parent.mkdir(parents=True, exist_ok=True)
    stats_path.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    palette = [(index * 23 + 0x41) & 0xFF for index in range(32)]
    counters = [0] * 10

    with vector_path.open("w", encoding="ascii") as stream:
        # Explicit truth-table, identity, priority, left-edge, and X=255 rows.
        directed = []
        for bg_opaque in (False, True):
            for sp_opaque in (False, True):
                for behind in (False, True):
                    for zero in (False, True):
                        directed.append((20, bg_opaque, sp_opaque, behind,
                                         zero, True, True))
        for x in range(8):
            for bg_left in (False, True):
                for sp_left in (False, True):
                    directed.append((x, True, True, False, True,
                                     bg_left, sp_left))
        directed.extend(
            ((254, True, True, True, True, True, True),
             (255, True, True, True, True, True, True))
        )
        for x, bg_opaque, sp_opaque, behind, zero, bg_left, sp_left in directed:
            bg = BackgroundPixel(True, x, 30, 1, 2, bg_opaque)
            sp = SpriteCandidate(
                True, x, 30, 2, 1, sp_opaque, behind, zero, 3,
                0 if zero else 17,
            )
            result = emit(
                stream,
                reset=False,
                ppu_enable=True,
                visible=True,
                x=x,
                y=30,
                background_enabled=True,
                sprites_enabled=True,
                bg_left=bg_left,
                sp_left=sp_left,
                grayscale=False,
                emphasis=5,
                bg=bg,
                sp=sp,
                palette=palette,
            )
            counters[0] += 1
            counters[1] += 1
            counters[3] += int(result.valid)
            counters[4 + int(result.source)] += int(result.valid)
            counters[7] += int(result.valid)
            counters[8] += int(result.sprite_zero_hit)

        # One deterministic 256-pixel scanline combines universal, background,
        # sprite, front/behind overlap, sprite zero, and left clipping.
        for x in range(256):
            bg_opaque = (x // 19) % 3 != 0
            sp_opaque = 32 <= x < 176 and (x % 7) != 0
            zero = 112 <= x < 128
            bg = BackgroundPixel(
                True, x, 73, 1 + (x % 3), (x // 32) & 3, bg_opaque
            )
            sp = SpriteCandidate(
                True, x, 73, 1 + ((x // 3) % 3), (x // 16) & 3,
                sp_opaque, bool((x // 24) & 1), zero, x & 7,
                0 if zero else 12,
            )
            result = emit(
                stream,
                reset=False,
                ppu_enable=True,
                visible=True,
                x=x,
                y=73,
                background_enabled=True,
                sprites_enabled=True,
                bg_left=False,
                sp_left=False,
                grayscale=bool((x // 64) & 1),
                emphasis=(x // 32) & 7,
                bg=bg,
                sp=sp,
                palette=palette,
            )
            counters[0] += 1
            counters[1] += 1
            counters[3] += 1
            counters[4 + int(result.source)] += 1
            counters[7] += 1
            counters[8] += int(result.sprite_zero_hit)
            counters[9] += int(bool((x // 64) & 1))

        for _ in range(RANDOM_CYCLES):
            ppu_enable = rng.random() < 0.78
            visible = rng.random() < 0.90
            x = rng.randrange(256)
            y = rng.randrange(256)
            bg = BackgroundPixel(
                rng.random() < 0.97,
                x if rng.random() < 0.98 else rng.randrange(256),
                y if rng.random() < 0.98 else rng.randrange(256),
                rng.randrange(4),
                rng.randrange(4),
                bool(rng.getrandbits(1)),
            )
            original = rng.randrange(64)
            is_zero = rng.random() < 0.12
            if is_zero and rng.random() < 0.85:
                original = 0
            sp = SpriteCandidate(
                rng.random() < 0.97,
                x if rng.random() < 0.98 else rng.randrange(256),
                y if rng.random() < 0.98 else rng.randrange(256),
                rng.randrange(4),
                rng.randrange(4),
                bool(rng.getrandbits(1)),
                bool(rng.getrandbits(1)),
                is_zero,
                rng.randrange(8),
                original,
            )
            grayscale = bool(rng.getrandbits(1))
            result = emit(
                stream,
                reset=rng.random() < 0.001,
                ppu_enable=ppu_enable,
                visible=visible,
                x=x,
                y=y,
                background_enabled=bool(rng.getrandbits(1)),
                sprites_enabled=bool(rng.getrandbits(1)),
                bg_left=bool(rng.getrandbits(1)),
                sp_left=bool(rng.getrandbits(1)),
                grayscale=grayscale,
                emphasis=rng.randrange(8),
                bg=bg,
                sp=sp,
                palette=palette,
            )
            counters[0] += 1
            counters[1] += int(ppu_enable)
            counters[2] += int(not ppu_enable)
            counters[3] += int(result.valid)
            counters[4 + int(result.source)] += int(result.valid)
            counters[7] += int(result.valid)
            counters[8] += int(result.sprite_zero_hit)
            counters[9] += int(result.valid and grayscale)

    stats_path.write_text(
        " ".join(str(value) for value in counters) + "\n",
        encoding="ascii",
    )
    print(
        f"Phase 3H mixer vectors: seed=0x{SEED:08X} "
        f"fabric={counters[0]} ticks={counters[1]} stalls={counters[2]} "
        f"pixels={counters[3]} universal={counters[4]} "
        f"background={counters[5]} sprite={counters[6]} "
        f"palette_reads={counters[7]} zero_hits={counters[8]} "
        f"grayscale={counters[9]}"
    )


if __name__ == "__main__":
    main()
