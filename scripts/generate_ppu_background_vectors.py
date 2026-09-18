#!/usr/bin/env python3
"""Generate standalone Phase 3E background-pipeline reference vectors."""

from argparse import ArgumentParser
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_background import (  # noqa: E402
    BackgroundModel,
    attribute_address,
    nametable_address,
)


RANDOM_SEED = 0x3E5EED01
RANDOM_CYCLES = 50_000


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
        self.model = BackgroundModel()
        self.rows = 0
        self.scenarios = [0] * 6
        self.fetches = [0] * 6
        self.tile_loads = 0
        self.shifts = 0

    def emit(
        self,
        stream: TextIO,
        scenario: int,
        *,
        reset: bool = False,
        ppu_enable: bool = True,
        dot: int = 0,
        scanline: int = 0,
        visible_pixel: bool | None = None,
        pixel_x: int | None = None,
        pixel_y: int | None = None,
        rendering_enabled: bool = True,
        background_enabled: bool = True,
        show_background_left: bool = True,
        pattern_table: int = 0,
        fine_x: int = 0,
        v: int = 0,
        memory_grant: bool = True,
        memory_data: int = 0,
    ) -> None:
        if visible_pixel is None:
            visible_pixel = (
                not reset
                and ppu_enable
                and scanline < 240
                and 1 <= dot <= 256
            )
        if pixel_x is None:
            pixel_x = dot - 1 if scanline < 240 and 1 <= dot <= 256 else 0
        if pixel_y is None:
            pixel_y = scanline if scanline < 240 and 1 <= dot <= 256 else 0

        observation = self.model.observe(
            reset=reset,
            ppu_enable=ppu_enable,
            dot=dot,
            scanline=scanline,
            visible_pixel=visible_pixel,
            pixel_x=pixel_x,
            pixel_y=pixel_y,
            rendering_enabled=rendering_enabled,
            background_enabled=background_enabled,
            show_background_left=show_background_left,
            pattern_table=pattern_table,
            fine_x=fine_x,
            v=v,
            memory_grant=memory_grant,
        )
        self.model.clock(
            observation,
            reset=reset,
            ppu_enable=ppu_enable,
            v=v,
            memory_data=memory_data,
        )
        values = (
            scenario,
            int(reset),
            int(ppu_enable),
            dot,
            scanline,
            int(visible_pixel),
            pixel_x,
            pixel_y,
            int(rendering_enabled),
            int(background_enabled),
            int(show_background_left),
            pattern_table,
            fine_x,
            v,
            nametable_address(v),
            attribute_address(v),
            int(memory_grant),
            memory_data,
            int(observation.memory_request),
            observation.memory_address,
            observation.fetch_phase,
            int(observation.fetch_type),
            int(observation.fetch_complete),
            int(observation.tile_load),
            int(observation.shifter_shift),
            int(observation.pixel_valid),
            observation.x,
            observation.y,
            observation.pattern,
            observation.palette,
            int(observation.opaque),
            observation.index,
            self.model.next_tile_id,
            self.model.next_tile_attribute,
            self.model.next_tile_pattern_low,
            self.model.next_tile_pattern_high,
            self.model.pattern_low_shift,
            self.model.pattern_high_shift,
            self.model.attribute_low_shift,
            self.model.attribute_high_shift,
        )
        stream.write(" ".join(str(value) for value in values) + "\n")
        self.rows += 1
        self.scenarios[scenario] += 1
        if observation.fetch_complete:
            self.fetches[int(observation.fetch_type)] += 1
        self.tile_loads += int(observation.tile_load)
        self.shifts += int(observation.shifter_shift)


def reset(writer: VectorWriter, stream: TextIO, scenario: int) -> None:
    writer.emit(stream, scenario, reset=True, ppu_enable=False)
    writer.emit(stream, scenario, reset=True, ppu_enable=False)


def write_schedule(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 1
    reset(writer, stream, scenario)
    for scanline in (0, 239, 240, 241, 260, 261):
        for dot in range(341):
            writer.emit(stream, scenario, scanline=scanline, dot=dot, v=0x73DF)


def write_attributes(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 2
    reset(writer, stream, scenario)
    for attribute in range(256):
        for coarse_y_bit in range(2):
            for coarse_x_bit in range(2):
                v = (coarse_y_bit << 6) | (coarse_x_bit << 1)
                writer.emit(
                    stream,
                    scenario,
                    dot=4,
                    v=v,
                    memory_data=attribute,
                )


def write_pattern_addresses(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 3
    reset(writer, stream, scenario)
    for table in range(2):
        for tile_id in range(256):
            for fine_y in range(8):
                v = fine_y << 12
                writer.emit(
                    stream,
                    scenario,
                    dot=2,
                    v=v,
                    pattern_table=table,
                    memory_data=tile_id,
                )
                writer.emit(stream, scenario, dot=5, v=v, pattern_table=table)
                writer.emit(stream, scenario, dot=7, v=v, pattern_table=table)


def write_orientation(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 4
    rows = (
        (0x80, 0x00, 0),
        (0x40, 0x00, 1),
        (0x01, 0x00, 2),
        (0xFF, 0x00, 3),
        (0xAA, 0x55, 1),
        (0x55, 0xAA, 2),
        (0x81, 0x81, 3),
    )
    for low, high, palette in rows:
        reset(writer, stream, scenario)
        for dot in range(1, 9):
            data = 0
            if dot == 2:
                data = 0x2A
            elif dot == 4:
                data = palette
            elif dot == 6:
                data = low
            elif dot == 8:
                data = high
            writer.emit(stream, scenario, dot=dot, memory_data=data)
        for fine_x in range(8):
            writer.emit(
                stream,
                scenario,
                ppu_enable=False,
                dot=9,
                visible_pixel=True,
                pixel_x=8,
                pixel_y=0,
                fine_x=fine_x,
            )


def write_random(writer: VectorWriter, stream: TextIO) -> None:
    scenario = 5
    reset(writer, stream, scenario)
    rng = XorShift32(RANDOM_SEED)
    for _ in range(RANDOM_CYCLES):
        dot = rng.next() % 341
        scanline = rng.next() % 262
        ppu_enable = rng.next() % 100 < 71
        rendering = rng.next() % 100 < 74
        background = rng.next() % 100 < 66
        writer.emit(
            stream,
            scenario,
            ppu_enable=ppu_enable,
            dot=dot,
            scanline=scanline,
            rendering_enabled=rendering,
            background_enabled=background,
            show_background_left=bool(rng.next() & 1),
            pattern_table=rng.next() & 1,
            fine_x=rng.next() & 7,
            v=rng.next() & 0x7FFF,
            memory_grant=rng.next() % 100 < 83,
            memory_data=rng.next() & 0xFF,
        )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    writer = VectorWriter()
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        write_schedule(writer, stream)
        write_attributes(writer, stream)
        write_pattern_addresses(writer, stream)
        write_orientation(writer, stream)
        write_random(writer, stream)

    print(
        "PPU background Python reference vectors: "
        f"rows={writer.rows}, attribute_cases=1024, pattern_addresses=8192, "
        f"random={RANDOM_CYCLES}, seed=0x{RANDOM_SEED:08X}, "
        f"fetches={writer.fetches}, tile_loads={writer.tile_loads}, "
        f"shifts={writer.shifts}"
    )


if __name__ == "__main__":
    main()
