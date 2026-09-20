#!/usr/bin/env python3
"""Generate Phase 3F primary/secondary OAM evaluator reference traces."""

from argparse import ArgumentParser
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_sprite_eval import SpriteEvaluationModel  # noqa: E402


RANDOM_SEED = 0x3F5EED01
RANDOM_SCANLINES = 128


class XorShift32:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFF_FFFF

    def next(self) -> int:
        value = self.state
        value ^= (value << 13) & 0xFFFF_FFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFF_FFFF
        self.state = value & 0xFFFF_FFFF
        return self.state


class VectorWriter:
    def __init__(self) -> None:
        self.model = SpriteEvaluationModel()
        self.rows = 0
        self.ppu_ticks = 0
        self.stalls = 0
        self.cpu_accesses = 0
        self.cpu_writes = 0
        self.cpu_commits = 0
        self.collisions = 0
        self.clear_writes = 0
        self.secondary_writes = 0
        self.overflow_sets = 0
        self.sprite_zero_selections = 0
        self.completed_sprites = 0
        self.visible_lines = 0
        self.scenarios = [0] * 8

    def emit(
        self,
        stream: TextIO,
        scenario: int,
        *,
        reset: bool = False,
        ppu_enable: bool = False,
        dot: int = 0,
        scanline: int = 240,
        rendering_enabled: bool = False,
        sprite_size_16: bool = False,
        cpu_oam_addr: int = 0,
        cpu_write_data: int = 0,
        cpu_write_enable: bool = False,
        cpu_access: bool = False,
        secondary_read_slot: int = 0,
    ) -> None:
        old_count = self.model.selected_count
        observation = self.model.observe(
            reset=reset,
            ppu_enable=ppu_enable,
            dot=dot,
            scanline=scanline,
            rendering_enabled=rendering_enabled,
            sprite_size_16=sprite_size_16,
            cpu_oam_addr=cpu_oam_addr,
            cpu_write_data=cpu_write_data,
            cpu_write_enable=cpu_write_enable,
            cpu_access=cpu_access,
        )
        self.model.clock(
            observation,
            reset=reset,
            ppu_enable=ppu_enable,
            dot=dot,
            scanline=scanline,
            rendering_enabled=rendering_enabled,
            sprite_size_16=sprite_size_16,
            cpu_oam_addr=cpu_oam_addr,
            cpu_write_data=cpu_write_data,
        )
        slot = secondary_read_slot & 7
        base = slot * 4
        values = (
            scenario,
            int(reset),
            int(ppu_enable),
            dot,
            scanline,
            int(rendering_enabled),
            int(sprite_size_16),
            cpu_oam_addr,
            cpu_write_data,
            int(cpu_write_enable),
            int(cpu_access),
            slot,
            observation.cpu_read_data,
            int(observation.cpu_write_commit),
            int(observation.cpu_collision),
            observation.primary_read_address,
            observation.primary_read_data,
            int(observation.secondary_clear_write),
            int(observation.secondary_evaluation_write),
            observation.secondary_write_address,
            observation.secondary_write_data,
            observation.evaluated_relative_row,
            int(observation.evaluated_in_range),
            self.model.selected_count,
            int(self.model.sprite_zero_selected),
            int(self.model.overflow_set),
            int(self.model.phase),
            self.model.n,
            self.model.m,
            16 if sprite_size_16 else 8,
            int(self.model.done),
            self.model.secondary_oam[base],
            self.model.secondary_oam[base + 1],
            self.model.secondary_oam[base + 2],
            self.model.secondary_oam[base + 3],
            self.model.secondary_indices[slot],
            int(slot < self.model.selected_count),
        )
        stream.write(" ".join(str(value) for value in values) + "\n")

        self.rows += 1
        self.scenarios[scenario] += 1
        self.ppu_ticks += int(ppu_enable)
        self.stalls += int(not ppu_enable and not reset)
        self.cpu_accesses += int(cpu_access)
        self.cpu_writes += int(cpu_write_enable)
        self.cpu_commits += int(observation.cpu_write_commit)
        self.collisions += int(observation.cpu_collision)
        self.clear_writes += int(observation.secondary_clear_write)
        self.secondary_writes += int(observation.secondary_evaluation_write)
        self.overflow_sets += int(self.model.overflow_set)
        self.completed_sprites += max(0, self.model.selected_count - old_count)
        if self.model.sprite_zero_selected and old_count == 0 and (
            self.model.selected_count or self.model.phase.value == 3
        ):
            self.sprite_zero_selections += 1


def reset(writer: VectorWriter, stream: TextIO, scenario: int) -> None:
    for _ in range(2):
        writer.emit(stream, scenario, reset=True)


def load_oam(
    writer: VectorWriter,
    stream: TextIO,
    scenario: int,
    contents: list[int],
    *,
    held_stalls: bool = False,
) -> None:
    assert len(contents) == 256
    for address, data in enumerate(contents):
        if held_stalls and address % 7 == 0:
            writer.emit(
                stream,
                scenario,
                cpu_oam_addr=address,
                cpu_write_data=data,
                cpu_write_enable=False,
                cpu_access=True,
            )
        writer.emit(
            stream,
            scenario,
            cpu_oam_addr=address,
            cpu_write_data=data,
            cpu_write_enable=True,
            cpu_access=True,
        )


def default_oam(scanline: int) -> list[int]:
    result = []
    for sprite in range(64):
        result.extend(((scanline + 64) & 0xFF, 0x80, 0x80, 0x80))
    return result


def put_sprite(
    contents: list[int],
    index: int,
    y: int,
    *,
    tile: int | None = None,
    attributes: int | None = None,
    x: int | None = None,
) -> None:
    base = index * 4
    contents[base : base + 4] = [
        y & 0xFF,
        (tile if tile is not None else index * 3 + 1) & 0xFF,
        (attributes if attributes is not None else index ^ 0xA5) & 0xFF,
        (x if x is not None else index * 5 + 7) & 0xFF,
    ]


def run_scanline(
    writer: VectorWriter,
    stream: TextIO,
    scenario: int,
    scanline: int,
    *,
    size_16: bool = False,
    rendering: bool = True,
    stall_dots: set[int] | None = None,
    rng: XorShift32 | None = None,
) -> None:
    stall_dots = stall_dots or set()
    for dot in range(1, 258):
        if dot in stall_dots:
            writer.emit(
                stream,
                scenario,
                ppu_enable=False,
                dot=dot,
                scanline=scanline,
                rendering_enabled=rendering,
                sprite_size_16=size_16,
                cpu_oam_addr=(rng.next() & 0xFF) if rng else 0,
                cpu_access=bool(rng and rng.next() % 11 == 0),
                secondary_read_slot=dot & 7,
            )
        cpu_access = bool(rng and rng.next() % 17 == 0)
        cpu_write = bool(cpu_access and rng and rng.next() & 1)
        writer.emit(
            stream,
            scenario,
            ppu_enable=True,
            dot=dot,
            scanline=scanline,
            rendering_enabled=rendering,
            sprite_size_16=size_16,
            cpu_oam_addr=(rng.next() & 0xFF) if rng else 0,
            cpu_write_data=(rng.next() & 0xFF) if rng else 0,
            cpu_write_enable=cpu_write,
            cpu_access=cpu_access,
            secondary_read_slot=dot & 7,
        )
    writer.visible_lines += int(rendering and scanline < 240)


def write_cpu_storage(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 1
    reset(writer, stream, scenario)
    contents = [address ^ 0xA5 for address in range(256)]
    load_oam(writer, stream, scenario, contents, held_stalls=True)
    for address in range(256):
        writer.emit(
            stream,
            scenario,
            cpu_oam_addr=address,
            cpu_access=True,
            secondary_read_slot=address & 7,
        )


def write_clear_and_single(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 2
    scanline = 80
    for index in (0, 1, 31, 63):
        reset(writer, stream, scenario)
        contents = default_oam(scanline)
        put_sprite(contents, index, scanline)
        load_oam(writer, stream, scenario, contents)
        run_scanline(
            writer,
            stream,
            scenario,
            scanline,
            stall_dots={2, 17, 63, 64, 65, 128, 255},
        )


def write_priority_and_height(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 3
    scanline = 100
    contents = default_oam(scanline)
    for index in (1, 3, 4, 9, 12, 20, 21, 23, 24, 30):
        put_sprite(contents, index, scanline)
    reset(writer, stream, scenario)
    load_oam(writer, stream, scenario, contents)
    run_scanline(writer, stream, scenario, scanline)

    boundaries = default_oam(scanline)
    for index, row in enumerate((7, 8, 15, 16)):
        put_sprite(boundaries, index, scanline - row)
    for size_16 in (False, True):
        reset(writer, stream, scenario)
        load_oam(writer, stream, scenario, boundaries)
        run_scanline(writer, stream, scenario, scanline, size_16=size_16)


def write_overflow_bug(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 4
    scanline = 120

    true_overflow = default_oam(scanline)
    for index in range(9):
        put_sprite(true_overflow, index, scanline)
    reset(writer, stream, scenario)
    load_oam(writer, stream, scenario, true_overflow)
    run_scanline(writer, stream, scenario, scanline)

    false_positive = default_oam(scanline)
    for index in range(8):
        put_sprite(false_positive, index, scanline)
    put_sprite(false_positive, 9, scanline + 64, tile=scanline)
    reset(writer, stream, scenario)
    load_oam(writer, stream, scenario, false_positive)
    run_scanline(writer, stream, scenario, scanline)

    false_negative = default_oam(scanline)
    for index in range(8):
        put_sprite(false_negative, index, scanline)
    put_sprite(false_negative, 9, scanline, tile=0xF0)
    reset(writer, stream, scenario)
    load_oam(writer, stream, scenario, false_negative)
    run_scanline(writer, stream, scenario, scanline)


def write_region_gating(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 5
    reset(writer, stream, scenario)
    contents = default_oam(20)
    put_sprite(contents, 0, 20)
    load_oam(writer, stream, scenario, contents)
    run_scanline(writer, stream, scenario, 20, rendering=False)
    for scanline in (240, 241, 260, 261):
        run_scanline(writer, stream, scenario, scanline, rendering=True)


def write_random(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 6
    rng = XorShift32(RANDOM_SEED)
    reset(writer, stream, scenario)
    for iteration in range(RANDOM_SCANLINES):
        scanline = rng.next() % 240
        contents = [rng.next() & 0xFF for _ in range(256)]
        load_oam(writer, stream, scenario, contents)
        stalls = {
            dot for dot in range(1, 258) if rng.next() % 100 < 19
        }
        run_scanline(
            writer,
            stream,
            scenario,
            scanline,
            size_16=bool(rng.next() & 1),
            rendering=bool(rng.next() % 5),
            stall_dots=stalls,
            rng=rng,
        )


def full_frame_layout(layout: int, size_16: bool) -> list[int]:
    contents = []
    for sprite in range(64):
        if layout == 0:
            y = (sprite * 4 - 1) & 0xFF
        elif layout == 1:
            y = ((sprite // 12) * 24 + (sprite & 1)) & 0xFF
        elif layout == 2:
            y = (sprite * 17 + (7 if size_16 else 3)) & 0xFF
        else:
            y = (sprite * sprite + 239) & 0xFF
        contents.extend((y, sprite, sprite ^ 0x5A, sprite * 3 & 0xFF))
    return contents


def write_full_frames(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 7
    for layout, size_16 in ((0, False), (1, False), (2, True), (3, True)):
        reset(writer, stream, scenario)
        load_oam(writer, stream, scenario, full_frame_layout(layout, size_16))
        for scanline in range(240):
            run_scanline(
                writer,
                stream,
                scenario,
                scanline,
                size_16=size_16,
            )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    writer = VectorWriter()
    with args.output.open("w", encoding="ascii") as stream:
        write_cpu_storage(writer, stream)
        write_clear_and_single(writer, stream)
        write_priority_and_height(writer, stream)
        write_overflow_bug(writer, stream)
        write_region_gating(writer, stream)
        write_random(writer, stream)
        write_full_frames(writer, stream)
    print(
        "Phase 3F OAM vectors: "
        f"seed={RANDOM_SEED:08x} rows={writer.rows} "
        f"ppu_ticks={writer.ppu_ticks} stalls={writer.stalls} "
        f"cpu_accesses={writer.cpu_accesses} cpu_writes={writer.cpu_writes} "
        f"cpu_commits={writer.cpu_commits} collisions={writer.collisions} "
        f"clear_writes={writer.clear_writes} "
        f"secondary_writes={writer.secondary_writes} "
        f"sprites_selected={writer.completed_sprites} "
        f"overflow_sets={writer.overflow_sets} "
        f"visible_lines={writer.visible_lines}"
    )


if __name__ == "__main__":
    main()
