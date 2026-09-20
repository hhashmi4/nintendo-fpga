#!/usr/bin/env python3
"""Generate randomized, stall-aware Phase 3G sprite-renderer vectors."""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_sprite_render import (  # noqa: E402
    SpriteFetchType,
    SpriteMetadata,
    SpriteRendererModel,
)

SEED = 0x37202601
SCENARIOS = 480


def chr_data(address: int) -> int:
    address &= 0x1FFF
    return ((address * 37) ^ (address >> 3) ^ 0xA5) & 0xFF


def candidate_count(model: SpriteRendererModel, pixel_x: int, enabled: bool) -> int:
    if not enabled:
        return 0
    count = 0
    for slot in range(8):
        if not model.valid[slot] or model.x_counter[slot]:
            continue
        pattern = (((model.high[slot] >> 7) & 1) << 1) | (
            (model.low[slot] >> 7) & 1
        )
        count += bool(pattern)
    return count


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} VECTOR TRACE STATS")
    vector_path, trace_path, stats_path = map(Path, sys.argv[1:])
    for path in (vector_path, trace_path, stats_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    rng = random.Random(SEED)
    model = SpriteRendererModel()
    counters = {
        "fabric": 0,
        "ticks": 0,
        "stalls": 0,
        "slots": 0,
        "low": 0,
        "high": 0,
        "dummy": 0,
        "decrements": 0,
        "shifts": 0,
        "opaque": 0,
        "overlaps": 0,
        "zero": 0,
        "collisions": 0,
    }

    with vector_path.open("w", encoding="ascii") as vectors, trace_path.open(
        "w", encoding="ascii"
    ) as trace:

        def emit(
            *,
            reset: bool,
            ppu_enable: bool,
            dot: int,
            scanline: int,
            visible_pixel: bool,
            pixel_x: int,
            pixel_y: int,
            rendering_enabled: bool,
            sprites_enabled: bool,
            show_sprites_left: bool,
            size_16: bool,
            pattern_table: int,
            nametable_address: int,
            memory_grant: bool,
            metadata: SpriteMetadata,
            trace_fetch: bool = False,
        ) -> None:
            observation = model.observe(
                reset=reset,
                ppu_enable=ppu_enable,
                dot=dot,
                scanline=scanline,
                visible_pixel=visible_pixel,
                pixel_x=pixel_x,
                pixel_y=pixel_y,
                rendering_enabled=rendering_enabled,
                sprites_enabled=sprites_enabled,
                show_sprites_left=show_sprites_left,
                size_16=size_16,
                pattern_table=pattern_table,
                nametable_address=nametable_address,
                metadata=metadata,
                memory_grant=memory_grant,
            )
            data = chr_data(observation.address)
            pixel = observation.pixel
            values = (
                int(reset),
                int(ppu_enable),
                dot,
                scanline,
                int(visible_pixel),
                pixel_x,
                pixel_y,
                int(rendering_enabled),
                int(sprites_enabled),
                int(show_sprites_left),
                int(size_16),
                pattern_table,
                nametable_address,
                int(memory_grant),
                metadata.y,
                metadata.tile,
                metadata.attributes,
                metadata.x,
                metadata.original_index,
                int(metadata.valid),
                data,
                observation.slot if 257 <= dot <= 320 else 0,
                int(observation.request),
                observation.address,
                observation.slot,
                observation.phase,
                int(observation.kind),
                int(observation.complete),
                int(observation.load),
                observation.relative_row,
                observation.selected_row,
                observation.low_address,
                observation.high_address,
                observation.decrement_mask,
                observation.shift_mask,
                int(pixel.valid),
                pixel.x,
                pixel.y,
                pixel.pattern,
                pixel.palette,
                pixel.palette_index,
                int(pixel.opaque),
                int(pixel.behind_background),
                int(pixel.is_zero),
                pixel.slot,
                pixel.original_index,
            )
            print(*values, file=vectors)

            counters["fabric"] += 1
            counters["ticks"] += int(ppu_enable and not reset)
            counters["stalls"] += int(not ppu_enable and not reset)
            counters["slots"] += int(observation.load)
            counters["low"] += int(
                observation.complete
                and observation.kind == SpriteFetchType.PATTERN_LOW
            )
            counters["high"] += int(
                observation.complete
                and observation.kind == SpriteFetchType.PATTERN_HIGH
            )
            counters["dummy"] += int(
                observation.complete
                and observation.kind
                in (SpriteFetchType.DUMMY_FIRST, SpriteFetchType.DUMMY_SECOND)
            )
            counters["decrements"] += observation.decrement_mask.bit_count()
            counters["shifts"] += observation.shift_mask.bit_count()
            counters["opaque"] += int(ppu_enable and pixel.opaque)
            counters["zero"] += int(
                ppu_enable and pixel.opaque and pixel.is_zero
            )
            count = candidate_count(
                model,
                pixel_x,
                visible_pixel
                and sprites_enabled
                and (show_sprites_left or pixel_x >= 8),
            )
            counters["overlaps"] += int(ppu_enable and count > 1)
            counters["collisions"] += int(
                observation.request and not memory_grant
            )
            if trace_fetch and observation.complete:
                print(
                    scanline,
                    dot,
                    observation.slot,
                    int(observation.kind),
                    metadata.tile,
                    observation.selected_row,
                    observation.address,
                    data,
                    file=trace,
                )
            model.clock(
                observation,
                reset=reset,
                ppu_enable=ppu_enable,
                visible_pixel=visible_pixel,
                metadata=metadata,
                memory_data=data,
            )

        emit(
            reset=True,
            ppu_enable=True,
            dot=0,
            scanline=0,
            visible_pixel=False,
            pixel_x=0,
            pixel_y=0,
            rendering_enabled=False,
            sprites_enabled=False,
            show_sprites_left=False,
            size_16=False,
            pattern_table=0,
            nametable_address=0x2000,
            memory_grant=False,
            metadata=SpriteMetadata(),
        )
        emit(
            reset=True,
            ppu_enable=False,
            dot=0,
            scanline=0,
            visible_pixel=False,
            pixel_x=0,
            pixel_y=0,
            rendering_enabled=False,
            sprites_enabled=False,
            show_sprites_left=False,
            size_16=False,
            pattern_table=0,
            nametable_address=0x2000,
            memory_grant=False,
            metadata=SpriteMetadata(),
        )

        for scenario in range(SCENARIOS):
            scanline = 1 + (scenario % 238)
            size_16 = bool(scenario & 1)
            height = 16 if size_16 else 8
            pattern_table = rng.randrange(2)
            sprites_enabled = scenario % 9 != 0
            show_sprites_left = scenario % 5 != 0
            nametable_address = 0x2000 | rng.randrange(0x1000)
            metadata_slots: list[SpriteMetadata] = []
            shared_x = scenario & 0xFF
            for slot in range(8):
                row = rng.randrange(height)
                attributes = rng.randrange(4)
                attributes |= rng.randrange(2) << 5
                attributes |= rng.randrange(2) << 6
                attributes |= rng.randrange(2) << 7
                x = shared_x if scenario % 7 == 0 else (
                    shared_x + slot * (3 + scenario % 13)
                ) & 0xFF
                metadata_slots.append(
                    SpriteMetadata(
                        y=(scanline - row) & 0xFF,
                        tile=rng.randrange(256),
                        attributes=attributes,
                        x=x,
                        original_index=(slot if scenario % 11 else slot + 8),
                        valid=slot < (scenario % 9),
                    )
                )

            for dot in range(257, 321):
                slot = (dot - 257) >> 3
                metadata = metadata_slots[slot]
                if rng.random() < 0.18:
                    emit(
                        reset=False,
                        ppu_enable=False,
                        dot=dot,
                        scanline=scanline,
                        visible_pixel=False,
                        pixel_x=0,
                        pixel_y=scanline,
                        rendering_enabled=True,
                        sprites_enabled=sprites_enabled,
                        show_sprites_left=show_sprites_left,
                        size_16=size_16,
                        pattern_table=pattern_table,
                        nametable_address=nametable_address,
                        memory_grant=False,
                        metadata=metadata,
                    )
                collision = scenario % 4 != 0 and rng.random() < 0.08
                emit(
                    reset=False,
                    ppu_enable=True,
                    dot=dot,
                    scanline=scanline,
                    visible_pixel=False,
                    pixel_x=0,
                    pixel_y=scanline,
                    rendering_enabled=True,
                    sprites_enabled=sprites_enabled,
                    show_sprites_left=show_sprites_left,
                    size_16=size_16,
                    pattern_table=pattern_table,
                    nametable_address=nametable_address,
                    memory_grant=not collision,
                    metadata=metadata,
                    trace_fetch=scenario == 0,
                )

            for pixel_x in range(256):
                if rng.random() < 0.22:
                    emit(
                        reset=False,
                        ppu_enable=False,
                        dot=pixel_x + 1,
                        scanline=scanline + 1,
                        visible_pixel=True,
                        pixel_x=pixel_x,
                        pixel_y=scanline + 1,
                        rendering_enabled=True,
                        sprites_enabled=sprites_enabled,
                        show_sprites_left=show_sprites_left,
                        size_16=size_16,
                        pattern_table=pattern_table,
                        nametable_address=nametable_address,
                        memory_grant=False,
                        metadata=SpriteMetadata(),
                    )
                emit(
                    reset=False,
                    ppu_enable=True,
                    dot=pixel_x + 1,
                    scanline=scanline + 1,
                    visible_pixel=True,
                    pixel_x=pixel_x,
                    pixel_y=scanline + 1,
                    rendering_enabled=True,
                    sprites_enabled=sprites_enabled,
                    show_sprites_left=show_sprites_left,
                    size_16=size_16,
                    pattern_table=pattern_table,
                    nametable_address=nametable_address,
                    memory_grant=False,
                    metadata=SpriteMetadata(),
                )

    ordered = (
        counters["fabric"],
        counters["ticks"],
        counters["stalls"],
        counters["slots"],
        counters["low"],
        counters["high"],
        counters["dummy"],
        counters["decrements"],
        counters["shifts"],
        counters["opaque"],
        counters["overlaps"],
        counters["zero"],
        counters["collisions"],
    )
    stats_path.write_text(" ".join(map(str, ordered)) + "\n", encoding="ascii")
    print(
        f"Phase 3G sprite renderer vectors: seed=0x{SEED:08X} "
        f"fabric_cycles={ordered[0]} enabled_ppu_ticks={ordered[1]} "
        f"stalls={ordered[2]} slots={ordered[3]} low={ordered[4]} "
        f"high={ordered[5]} dummy={ordered[6]} decrements={ordered[7]} "
        f"shifts={ordered[8]} opaque={ordered[9]} overlaps={ordered[10]} "
        f"sprite_zero={ordered[11]} collisions={ordered[12]}"
    )


if __name__ == "__main__":
    main()
