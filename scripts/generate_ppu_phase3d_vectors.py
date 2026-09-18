#!/usr/bin/env python3
"""Generate integrated Phase 3A-3D timing/register/memory/scroll vectors."""

from argparse import ArgumentParser
from dataclasses import replace
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_memory import (  # noqa: E402
    MemoryRegion,
    MirroringMode,
    PpuMemoryModel,
)
from verification.ppu_registers import (  # noqa: E402
    PPUADDR,
    PPUCTRL,
    PPUDATA,
    PPUMASK,
    PPUSCROLL,
    PPUSTATUS,
    PpuBusInputs,
    PpuRegisterModel,
)
from verification.ppu_scroll import (  # noqa: E402
    active_render_period,
    attribute_fetch_address,
    events_for_coordinate,
    is_rendering_scanline,
    nametable_fetch_address,
)
from verification.ppu_timing import PpuTimingModel  # noqa: E402


RANDOM_SEED = 0x3D200701
RANDOM_FABRIC_CYCLES = 180_000
STALL_FRAME_SEED = 0x3D57A110


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


def transaction(
    register: int,
    *,
    write: bool,
    data: int = 0,
    enable: bool = True,
    valid: bool = True,
    mirror: int = 0,
) -> PpuBusInputs:
    return PpuBusInputs(
        cpu_enable=enable,
        cpu_bus_valid=valid,
        cpu_bus_write=write,
        cpu_address=0x2000 + ((mirror & 0x3FF) << 3) + register,
        cpu_write_data=data,
    )


def buffer_read(memory: PpuMemoryModel, primary_address: int, address: int) -> int:
    if memory.translation(primary_address).region != MemoryRegion.PALETTE:
        return 0
    decoded = memory.translation(address)
    if decoded.region == MemoryRegion.NAMETABLE:
        return memory.ciram[decoded.ciram_address]
    return 0


class IntegratedScrollReference:
    def __init__(self) -> None:
        self.registers = PpuRegisterModel()
        self.timing = PpuTimingModel()
        self.memory = PpuMemoryModel()
        self.rows = 0
        self.ppu_ticks = 0
        self.ppu_stalls = 0
        self.accepted = 0
        self.scroll_transactions = 0
        self.ppudata_transactions = 0
        self.x_increments = 0
        self.y_increments = 0
        self.horizontal_copies = 0
        self.vertical_copies = 0
        self.collisions = 0
        self.frames = 0

    def emit(
        self,
        stream: TextIO,
        scenario: int,
        inputs: PpuBusInputs = PpuBusInputs(),
        *,
        ppu_enable: bool = False,
        mode: MirroringMode = MirroringMode.VERTICAL,
    ) -> None:
        self.memory.set_mode(mode)
        registers = self.registers
        timing = self.timing
        pre = timing.snapshot()
        rendering = registers.rendering_enabled
        memory_address = registers.v & 0x3FFF
        memory_buffer_address = (
            (memory_address - 0x1000) & 0x3FFF
            if memory_address >= 0x3F00
            else memory_address
        )
        memory_read_data = self.memory.read(memory_address)
        memory_buffer_read_data = buffer_read(
            self.memory, memory_address, memory_buffer_address
        )
        reg_inputs = replace(
            inputs,
            ppu_enable=ppu_enable,
            dot=pre.dot,
            scanline=pre.scanline,
            memory_read_data=memory_read_data,
            memory_buffer_read_data=memory_buffer_read_data,
            vblank_start_event=timing.vblank_start(ppu_enable) and not inputs.reset,
            status_clear_event=timing.vblank_end(ppu_enable) and not inputs.reset,
        )
        observation = registers.observe(reg_inputs)
        pre_write_toggle = registers.w
        translation = self.memory.translation(observation.memory_address)
        chr_read = observation.memory_read_request and (
            translation.region == MemoryRegion.CHR
        )
        chr_write = observation.memory_write_request and (
            translation.region == MemoryRegion.CHR
        )
        ciram_write = observation.memory_write_request and (
            translation.region == MemoryRegion.NAMETABLE
        )
        palette_write = observation.memory_write_request and (
            translation.region == MemoryRegion.PALETTE
        )
        events = events_for_coordinate(
            ppu_enable=ppu_enable,
            rendering_enabled=rendering,
            scanline=pre.scanline,
            dot=pre.dot,
        )
        fetch_nt = nametable_fetch_address(registers.v)
        fetch_attr = attribute_fetch_address(registers.v)

        if observation.memory_write_request:
            self.memory.write(observation.memory_address, inputs.cpu_write_data)
        registers.clock(reg_inputs)
        old_parity = timing.frame_odd
        timing.clock(
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            rendering_enabled=rendering,
        )
        post = timing.snapshot()

        values = (
            scenario,
            int(inputs.reset),
            int(ppu_enable),
            int(inputs.cpu_enable),
            int(inputs.cpu_bus_valid),
            int(inputs.cpu_bus_write),
            inputs.cpu_address & 0xFFFF,
            inputs.cpu_write_data & 0xFF,
            int(mode),
            int(observation.selected),
            observation.register_index,
            observation.cpu_read_data,
            observation.memory_address,
            observation.memory_buffer_address,
            int(observation.memory_read_request),
            int(observation.memory_write_request),
            memory_read_data,
            memory_buffer_read_data,
            translation.chr_address,
            int(chr_read),
            int(chr_write),
            int(ciram_write),
            int(palette_write),
            pre.dot,
            pre.scanline,
            int(pre.frame_odd),
            int(rendering),
            int(is_rendering_scanline(pre.scanline)),
            int(active_render_period(rendering, pre.scanline)),
            int(events.coarse_x_increment),
            int(events.vertical_increment),
            int(events.horizontal_copy),
            int(events.vertical_copy),
            int(events.any),
            fetch_nt,
            fetch_attr,
            post.dot,
            post.scanline,
            int(post.frame_odd),
            registers.ppuctrl,
            registers.ppumask,
            registers.v,
            registers.t,
            registers.x,
            int(registers.w),
            registers.read_buffer,
            registers.io_latch,
            int(registers.status_vblank),
            int(translation.region),
        )
        stream.write(" ".join(str(value) for value in values) + "\n")

        self.rows += 1
        if not inputs.reset:
            self.ppu_ticks += int(ppu_enable)
            self.ppu_stalls += int(not ppu_enable)
            self.accepted += int(observation.accepted)
            if observation.accepted and observation.register_index in (
                PPUCTRL,
                PPUMASK,
                PPUSTATUS,
                PPUSCROLL,
                PPUADDR,
            ):
                self.scroll_transactions += 1
            if observation.accepted and observation.register_index == PPUDATA:
                self.ppudata_transactions += 1
            self.x_increments += int(events.coarse_x_increment)
            self.y_increments += int(events.vertical_increment)
            self.horizontal_copies += int(events.horizontal_copy)
            self.vertical_copies += int(events.vertical_copy)
            cpu_v_operation = observation.accepted and (
                observation.register_index == PPUDATA
                or (
                    observation.register_index == PPUADDR
                    and inputs.cpu_bus_write
                    and pre_write_toggle
                )
            )
            self.collisions += int(events.any and cpu_v_operation)
            self.frames += int(ppu_enable and timing.frame_odd != old_parity)


def reset(reference: IntegratedScrollReference, stream: TextIO, scenario: int) -> None:
    reference.emit(stream, scenario, PpuBusInputs(reset=True))
    reference.emit(stream, scenario, PpuBusInputs(reset=True))


def program_scroll(
    reference: IntegratedScrollReference,
    stream: TextIO,
    scenario: int,
    *,
    mask: int,
    coarse_x: int,
    fine_x: int,
    coarse_y: int,
    fine_y: int,
    horizontal_nt: int,
    vertical_nt: int,
) -> None:
    reference.emit(stream, scenario, transaction(PPUMASK, write=True, data=mask))
    reference.emit(
        stream,
        scenario,
        transaction(PPUCTRL, write=True, data=(vertical_nt << 1) | horizontal_nt),
    )
    reference.emit(stream, scenario, transaction(PPUSTATUS, write=False))
    first_scroll = ((coarse_x & 31) << 3) | (fine_x & 7)
    second_scroll = ((coarse_y & 31) << 3) | (fine_y & 7)
    reference.emit(
        stream, scenario, transaction(PPUSCROLL, write=True, data=first_scroll)
    )
    reference.emit(
        stream, scenario, transaction(PPUSCROLL, write=True, data=second_scroll)
    )
    # Re-enter the first-write state, then use a second $2006 write to copy
    # the completed loopy t value into v without destroying fine Y.
    reference.emit(
        stream, scenario, transaction(PPUSCROLL, write=True, data=first_scroll)
    )
    reference.emit(
        stream,
        scenario,
        transaction(PPUADDR, write=True, data=reference.registers.t & 0xFF),
    )


def advance_to(
    reference: IntegratedScrollReference,
    stream: TextIO,
    scenario: int,
    scanline: int,
    dot: int,
) -> None:
    while (reference.timing.scanline, reference.timing.dot) != (scanline, dot):
        reference.emit(stream, scenario, ppu_enable=True)


def write_collision_scenario(
    reference: IntegratedScrollReference, stream: TextIO
) -> None:
    scenario = 1
    reset(reference, stream, scenario)
    program_scroll(
        reference,
        stream,
        scenario,
        mask=0x08,
        coarse_x=31,
        fine_x=5,
        coarse_y=29,
        fine_y=7,
        horizontal_nt=1,
        vertical_nt=0,
    )
    targets = (
        (0, 255, transaction(PPUADDR, write=True, data=0x2A)),
        (0, 256, transaction(PPUDATA, write=False)),
        (0, 257, transaction(PPUADDR, write=True, data=0x55)),
        (0, 258, transaction(PPUDATA, write=True, data=0xA5)),
        (261, 279, transaction(PPUSCROLL, write=True, data=0xFD)),
        (261, 280, transaction(PPUSCROLL, write=True, data=0xEF)),
        (261, 304, transaction(PPUDATA, write=False)),
        (261, 305, transaction(PPUDATA, write=False)),
        (261, 327, transaction(PPUADDR, write=True, data=0x31)),
        (261, 328, transaction(PPUADDR, write=True, data=0x7C)),
        (261, 336, transaction(PPUDATA, write=True, data=0x5A)),
    )
    for scanline, dot, inputs in targets:
        advance_to(reference, stream, scenario, scanline, dot)
        reference.emit(stream, scenario, inputs, ppu_enable=True)
    advance_to(reference, stream, scenario, 261, 337)
    reference.emit(stream, scenario, ppu_enable=True)


def run_frame(
    reference: IntegratedScrollReference,
    stream: TextIO,
    scenario: int,
    rng: XorShift32 | None = None,
) -> None:
    starting_parity = reference.timing.frame_odd
    while True:
        enabled = True if rng is None else rng.next() % 100 < 68
        reference.emit(stream, scenario, ppu_enable=enabled)
        if reference.timing.frame_odd != starting_parity:
            return


def write_full_frames(reference: IntegratedScrollReference, stream: TextIO) -> None:
    scenario = 2
    cases = (
        (0x00, 31, 2, 29, 7, 0, 0, 1),
        (0x08, 30, 7, 31, 7, 1, 1, 2),
        (0x10, 31, 0, 30, 6, 0, 1, 1),
        (0x18, 0, 3, 29, 7, 1, 0, 1),
    )
    stall_rng = XorShift32(STALL_FRAME_SEED)
    for mask, cx, fx, cy, fy, hnt, vnt, frame_count in cases:
        reset(reference, stream, scenario)
        program_scroll(
            reference,
            stream,
            scenario,
            mask=mask,
            coarse_x=cx,
            fine_x=fx,
            coarse_y=cy,
            fine_y=fy,
            horizontal_nt=hnt,
            vertical_nt=vnt,
        )
        for frame_index in range(frame_count):
            rng = stall_rng if mask == 0x08 and frame_index == 1 else None
            run_frame(reference, stream, scenario, rng)


def random_address(rng: XorShift32, register: int) -> int:
    if rng.next() % 100 < 91:
        return 0x2000 + ((rng.next() & 0x3FF) << 3) + register
    return (0x4000 + rng.next()) & 0xFFFF


def write_random(reference: IntegratedScrollReference, stream: TextIO) -> None:
    scenario = 3
    reset(reference, stream, scenario)
    rng = XorShift32(RANDOM_SEED)
    held = PpuBusInputs()
    weighted = (PPUCTRL, PPUMASK, PPUSTATUS, PPUSCROLL, PPUADDR, PPUADDR,
                PPUDATA, PPUDATA, PPUDATA, 3, 4)
    for _ in range(RANDOM_FABRIC_CYCLES):
        if rng.next() % 100 < 59:
            register = weighted[rng.next() % len(weighted)]
            held = PpuBusInputs(
                cpu_bus_valid=rng.next() % 100 < 83,
                cpu_bus_write=bool(rng.next() & 1),
                cpu_address=random_address(rng, register),
                cpu_write_data=rng.next() & 0xFF,
                # Consume dedicated deterministic draws while keeping sprite
                # events outside this scroll-focused trace.
                sprite_zero_hit_set=bool(rng.next() & 0),
                sprite_overflow_set=bool(rng.next() & 0),
            )
        inputs = replace(held, cpu_enable=rng.next() % 100 < 61)
        reference.emit(
            stream,
            scenario,
            inputs,
            ppu_enable=rng.next() % 100 < 69,
            mode=MirroringMode(rng.next() & 3),
        )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    reference = IntegratedScrollReference()
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        write_collision_scenario(reference, stream)
        write_full_frames(reference, stream)
        write_random(reference, stream)

    print(
        "Integrated Phase 3D Python reference vectors: "
        f"rows={reference.rows}, random_seed=0x{RANDOM_SEED:08X}, "
        f"stall_frame_seed=0x{STALL_FRAME_SEED:08X}, "
        f"ppu_ticks={reference.ppu_ticks}, ppu_stalls={reference.ppu_stalls}, "
        f"accepted={reference.accepted}, "
        f"scroll_transactions={reference.scroll_transactions}, "
        f"ppudata={reference.ppudata_transactions}, "
        f"x_increments={reference.x_increments}, "
        f"y_increments={reference.y_increments}, "
        f"horizontal_copies={reference.horizontal_copies}, "
        f"vertical_copies={reference.vertical_copies}, "
        f"collisions={reference.collisions}, complete_frames={reference.frames}"
    )


if __name__ == "__main__":
    main()
