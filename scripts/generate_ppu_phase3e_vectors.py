#!/usr/bin/env python3
"""Generate integrated Phase 3A-3E background-rendering vectors."""

from argparse import ArgumentParser
from dataclasses import replace
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_background import BackgroundModel, FetchType  # noqa: E402
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
from verification.ppu_timing import PpuTimingModel  # noqa: E402


RANDOM_SEED = 0x3E200701
RANDOM_FABRIC_CYCLES = 180_000
TRACE_SCANLINES = frozenset((0, 1, 31, 239, 261))


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


def ciram_initial_value(address: int) -> int:
    return (address * 37 + (address >> 3) * 11 + 0x5A) & 0xFF


def chr_initial_value(address: int) -> int:
    return (address * 29 + (address >> 4) * 7 + 0xA5) & 0xFF


def palette_initial_value(address: int) -> int:
    return (address * 13 + 0x31) & 0xFF


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
    return (
        memory.ciram[decoded.ciram_address]
        if decoded.region == MemoryRegion.NAMETABLE
        else 0
    )


class IntegratedBackgroundReference:
    def __init__(self, trace_stream: TextIO) -> None:
        self.registers = PpuRegisterModel()
        self.timing = PpuTimingModel()
        self.memory = PpuMemoryModel()
        self.background = BackgroundModel()
        self.trace_stream = trace_stream
        for address in range(2048):
            self.memory.ciram[address] = ciram_initial_value(address)
        for address in range(8192):
            self.memory.chr[address] = chr_initial_value(address)
        for address in range(32):
            self.memory.palette[address] = palette_initial_value(address)

        self.rows = 0
        self.scenarios = [0] * 6
        self.ppu_ticks = 0
        self.ppu_stalls = 0
        self.accepted = 0
        self.collisions = 0
        self.fetches = [0] * 6
        self.tile_loads = 0
        self.shifts = 0
        self.visible_pixels = 0
        self.first_scanline_pixels = 0
        self.scroll_pixels = 0
        self.frames = 0
        self.random_ticks = 0
        self.random_stalls = 0
        self.random_accepted = 0
        self.random_collisions = 0
        self.random_fetches = [0] * 6
        self.random_tile_loads = 0
        self.random_shifts = 0
        self.random_pixels = 0

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
        background = self.background
        pre = timing.snapshot()
        pre_v = registers.v
        pre_t = registers.t
        pre_x = registers.x
        pre_ppuctrl = registers.ppuctrl
        pre_ppumask = registers.ppumask
        rendering = registers.rendering_enabled
        visible = (
            not inputs.reset
            and ppu_enable
            and pre.scanline < 240
            and 1 <= pre.dot <= 256
        )
        pixel_x = pre.dot - 1 if pre.scanline < 240 and 1 <= pre.dot <= 256 else 0
        pixel_y = pre.scanline if pre.scanline < 240 and 1 <= pre.dot <= 256 else 0

        selected, register_index = registers.decode(inputs.cpu_address)
        accepted = (
            not inputs.reset
            and inputs.cpu_enable
            and inputs.cpu_bus_valid
            and selected
        )
        cpu_memory_access = accepted and register_index == PPUDATA
        renderer_grant = not cpu_memory_access
        bg_observation = background.observe(
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            dot=pre.dot,
            scanline=pre.scanline,
            visible_pixel=visible,
            pixel_x=pixel_x,
            pixel_y=pixel_y,
            rendering_enabled=rendering,
            background_enabled=bool(registers.ppumask & 0x08),
            show_background_left=bool(registers.ppumask & 0x02),
            pattern_table=(registers.ppuctrl >> 4) & 1,
            fine_x=pre_x,
            v=pre_v,
            memory_grant=renderer_grant,
        )
        renderer_grant = bg_observation.memory_request and renderer_grant
        collision = bg_observation.memory_request and cpu_memory_access
        memory_address = (
            pre_v & 0x3FFF
            if cpu_memory_access
            else bg_observation.memory_address
        )
        memory_valid = cpu_memory_access or bg_observation.memory_request
        memory_write = cpu_memory_access and inputs.cpu_bus_write
        translation = self.memory.translation(memory_address)
        memory_read_data = self.memory.read(memory_address)
        cpu_memory_address = pre_v & 0x3FFF
        cpu_buffer_address = (
            (cpu_memory_address - 0x1000) & 0x3FFF
            if cpu_memory_address >= 0x3F00
            else cpu_memory_address
        )
        memory_buffer_read_data = buffer_read(
            self.memory, cpu_memory_address, cpu_buffer_address
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
        reg_observation = registers.observe(reg_inputs)
        chr_read = (
            not inputs.reset
            and memory_valid
            and not memory_write
            and translation.region == MemoryRegion.CHR
        )
        chr_write = (
            not inputs.reset
            and memory_valid
            and memory_write
            and translation.region == MemoryRegion.CHR
        )
        ciram_write = (
            not inputs.reset
            and memory_valid
            and memory_write
            and translation.region == MemoryRegion.NAMETABLE
        )
        palette_write = (
            not inputs.reset
            and memory_valid
            and memory_write
            and translation.region == MemoryRegion.PALETTE
        )

        if scenario == 2 and pre.scanline in TRACE_SCANLINES and bg_observation.fetch_complete:
            self.trace_stream.write(
                f"{pre.dot} {pre.scanline} {int(bg_observation.fetch_type)} "
                f"{bg_observation.memory_address:04x} {pre_v:04x} "
                f"{background.next_tile_id:02x} {(pre_v >> 12) & 7}\n"
            )

        pre_next_tile_id = background.next_tile_id
        if memory_write:
            self.memory.write(memory_address, inputs.cpu_write_data)
        background.clock(
            bg_observation,
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            v=pre_v,
            memory_data=memory_read_data,
        )
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
            int(reg_observation.selected),
            reg_observation.register_index,
            reg_observation.cpu_read_data,
            reg_observation.memory_address,
            reg_observation.memory_buffer_address,
            int(reg_observation.memory_read_request),
            int(reg_observation.memory_write_request),
            int(bg_observation.memory_request),
            bg_observation.memory_address,
            int(renderer_grant),
            int(collision),
            memory_address,
            memory_read_data,
            int(translation.region),
            translation.chr_address,
            int(chr_read),
            int(chr_write),
            int(ciram_write),
            int(palette_write),
            pre.dot,
            pre.scanline,
            int(pre.frame_odd),
            pre_v,
            pre_t,
            pre_x,
            pre_ppuctrl,
            pre_ppumask,
            int(rendering),
            bg_observation.fetch_phase,
            int(bg_observation.fetch_type),
            int(bg_observation.fetch_complete),
            int(bg_observation.tile_load),
            int(bg_observation.shifter_shift),
            int(bg_observation.pixel_valid),
            bg_observation.x,
            bg_observation.y,
            bg_observation.pattern,
            bg_observation.palette,
            int(bg_observation.opaque),
            bg_observation.index,
            0x2000 | (pre_v & 0x0FFF),
            0x23C0 | (pre_v & 0x0C00) | ((pre_v >> 4) & 0x38) | ((pre_v >> 2) & 7),
            pre_next_tile_id,
            post.dot,
            post.scanline,
            int(post.frame_odd),
            registers.v,
            registers.t,
            registers.x,
            int(registers.w),
            registers.ppuctrl,
            registers.ppumask,
            background.next_tile_id,
            background.next_tile_attribute,
            background.next_tile_pattern_low,
            background.next_tile_pattern_high,
            background.pattern_low_shift,
            background.pattern_high_shift,
            background.attribute_low_shift,
            background.attribute_high_shift,
            registers.read_buffer,
            registers.io_latch,
            int(registers.status_vblank),
        )
        stream.write(" ".join(str(value) for value in values) + "\n")

        self.rows += 1
        self.scenarios[scenario] += 1
        if not inputs.reset:
            self.ppu_ticks += int(ppu_enable)
            self.ppu_stalls += int(not ppu_enable)
            self.accepted += int(reg_observation.accepted)
            self.collisions += int(collision)
            if bg_observation.fetch_complete:
                self.fetches[int(bg_observation.fetch_type)] += 1
            self.tile_loads += int(bg_observation.tile_load)
            self.shifts += int(bg_observation.shifter_shift)
            if scenario == 2 and visible:
                self.visible_pixels += 1
                self.first_scanline_pixels += int(pre.scanline == 0)
            if scenario == 3 and visible:
                self.scroll_pixels += 1
            self.frames += int(ppu_enable and timing.frame_odd != old_parity)
            if scenario == 5:
                self.random_ticks += int(ppu_enable)
                self.random_stalls += int(not ppu_enable)
                self.random_accepted += int(reg_observation.accepted)
                self.random_collisions += int(collision)
                if bg_observation.fetch_complete:
                    self.random_fetches[int(bg_observation.fetch_type)] += 1
                self.random_tile_loads += int(bg_observation.tile_load)
                self.random_shifts += int(bg_observation.shifter_shift)
                self.random_pixels += int(visible)


def reset(reference: IntegratedBackgroundReference, stream: TextIO, scenario: int) -> None:
    reference.emit(stream, scenario, PpuBusInputs(reset=True))
    reference.emit(stream, scenario, PpuBusInputs(reset=True))


def program_scroll(
    reference: IntegratedBackgroundReference,
    stream: TextIO,
    scenario: int,
    *,
    mode: MirroringMode,
    mask: int,
    pattern_table: int,
    coarse_x: int,
    fine_x: int,
    coarse_y: int,
    fine_y: int,
    horizontal_nt: int,
    vertical_nt: int,
) -> None:
    reference.emit(
        stream, scenario, transaction(PPUMASK, write=True, data=mask), mode=mode
    )
    control = (
        ((pattern_table & 1) << 4)
        | ((vertical_nt & 1) << 1)
        | (horizontal_nt & 1)
    )
    reference.emit(
        stream, scenario, transaction(PPUCTRL, write=True, data=control), mode=mode
    )
    reference.emit(stream, scenario, transaction(PPUSTATUS, write=False), mode=mode)
    first = ((coarse_x & 31) << 3) | (fine_x & 7)
    second = ((coarse_y & 31) << 3) | (fine_y & 7)
    reference.emit(
        stream, scenario, transaction(PPUSCROLL, write=True, data=first), mode=mode
    )
    reference.emit(
        stream, scenario, transaction(PPUSCROLL, write=True, data=second), mode=mode
    )
    reference.emit(
        stream, scenario, transaction(PPUSCROLL, write=True, data=first), mode=mode
    )
    reference.emit(
        stream,
        scenario,
        transaction(PPUADDR, write=True, data=reference.registers.t & 0xFF),
        mode=mode,
    )


def run_frame(
    reference: IntegratedBackgroundReference,
    stream: TextIO,
    scenario: int,
    mode: MirroringMode,
) -> None:
    starting_parity = reference.timing.frame_odd
    while True:
        reference.emit(stream, scenario, ppu_enable=True, mode=mode)
        if reference.timing.frame_odd != starting_parity:
            return


def run_to_next_scanline(
    reference: IntegratedBackgroundReference,
    stream: TextIO,
    scenario: int,
    mode: MirroringMode,
) -> None:
    starting_scanline = reference.timing.scanline
    while reference.timing.scanline == starting_scanline:
        reference.emit(stream, scenario, ppu_enable=True, mode=mode)


def write_full_frame(reference: IntegratedBackgroundReference, stream: TextIO) -> None:
    mode = MirroringMode.VERTICAL
    reset(reference, stream, 1)
    program_scroll(
        reference,
        stream,
        1,
        mode=mode,
        mask=0x0A,
        pattern_table=1,
        coarse_x=31,
        fine_x=7,
        coarse_y=29,
        fine_y=7,
        horizontal_nt=1,
        vertical_nt=0,
    )
    run_frame(reference, stream, 1, mode)
    run_frame(reference, stream, 2, mode)


def write_scroll_and_mirroring(
    reference: IntegratedBackgroundReference, stream: TextIO
) -> None:
    coarse_x_values = (0, 1, 30, 31, 7, 15, 29, 31)
    coarse_y_values = (0, 28, 29, 30, 31, 5, 29, 31)
    for fine_x in range(8):
        mode = MirroringMode(fine_x & 3)
        program_scroll(
            reference,
            stream,
            3,
            mode=mode,
            mask=0x0A,
            pattern_table=fine_x & 1,
            coarse_x=coarse_x_values[fine_x],
            fine_x=fine_x,
            coarse_y=coarse_y_values[fine_x],
            fine_y=fine_x,
            horizontal_nt=(fine_x >> 1) & 1,
            vertical_nt=(fine_x >> 2) & 1,
        )
        run_frame(reference, stream, 3, mode)
        run_to_next_scanline(reference, stream, 3, mode)


def write_mask_cases(reference: IntegratedBackgroundReference, stream: TextIO) -> None:
    mode = MirroringMode.VERTICAL
    for mask in (0x00, 0x08, 0x0A, 0x10):
        reference.emit(
            stream,
            4,
            transaction(PPUMASK, write=True, data=mask),
            mode=mode,
        )
        run_to_next_scanline(reference, stream, 4, mode)


def random_address(rng: XorShift32, register: int) -> int:
    if rng.next() % 100 < 92:
        return 0x2000 + ((rng.next() & 0x3FF) << 3) + register
    return (0x4000 + rng.next()) & 0xFFFF


def write_random(reference: IntegratedBackgroundReference, stream: TextIO) -> None:
    reset(reference, stream, 5)
    rng = XorShift32(RANDOM_SEED)
    held = PpuBusInputs()
    weighted = (
        PPUCTRL,
        PPUMASK,
        PPUSTATUS,
        PPUSCROLL,
        PPUADDR,
        PPUADDR,
        PPUDATA,
        PPUDATA,
        PPUDATA,
        3,
        4,
    )
    for _ in range(RANDOM_FABRIC_CYCLES):
        if rng.next() % 100 < 57:
            register = weighted[rng.next() % len(weighted)]
            held = PpuBusInputs(
                cpu_bus_valid=rng.next() % 100 < 84,
                cpu_bus_write=bool(rng.next() & 1),
                cpu_address=random_address(rng, register),
                cpu_write_data=rng.next() & 0xFF,
            )
        inputs = replace(held, cpu_enable=rng.next() % 100 < 62)
        reference.emit(
            stream,
            5,
            inputs,
            ppu_enable=rng.next() % 100 < 69,
            mode=MirroringMode(rng.next() & 3),
        )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("trace_output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.trace_output.parent.mkdir(parents=True, exist_ok=True)

    with args.output.open("w", encoding="ascii", newline="\n") as stream, \
         args.trace_output.open("w", encoding="ascii", newline="\n") as trace:
        reference = IntegratedBackgroundReference(trace)
        write_full_frame(reference, stream)
        write_scroll_and_mirroring(reference, stream)
        write_mask_cases(reference, stream)
        write_random(reference, stream)

    print(
        "Integrated Phase 3E Python reference vectors: "
        f"rows={reference.rows}, seed=0x{RANDOM_SEED:08X}, "
        f"ppu_ticks={reference.ppu_ticks}, stalls={reference.ppu_stalls}, "
        f"accepted={reference.accepted}, collisions={reference.collisions}, "
        f"fetches={reference.fetches}, tile_loads={reference.tile_loads}, "
        f"shifts={reference.shifts}, full_frame_pixels={reference.visible_pixels}, "
        f"first_scanline_pixels={reference.first_scanline_pixels}, "
        f"scroll_pixels={reference.scroll_pixels}, frames={reference.frames}, "
        f"scenarios={reference.scenarios[1:]}, "
        f"random_ticks={reference.random_ticks}, "
        f"random_stalls={reference.random_stalls}, "
        f"random_accepted={reference.random_accepted}, "
        f"random_collisions={reference.random_collisions}, "
        f"random_fetches={reference.random_fetches}, "
        f"random_loads={reference.random_tile_loads}, "
        f"random_shifts={reference.random_shifts}, "
        f"random_pixels={reference.random_pixels}"
    )


if __name__ == "__main__":
    main()
