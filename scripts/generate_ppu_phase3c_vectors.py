#!/usr/bin/env python3
"""Generate combined Phase 3B-register/Phase 3C-memory reference vectors."""

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
    PPUDATA,
    PpuBusInputs,
    PpuRegisterModel,
)
from verification.ppu_timing import PpuTimingModel  # noqa: E402


RANDOM_SEED = 0x3C200701
RANDOM_FABRIC_CYCLES = 120_000


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


def buffer_read(memory: PpuMemoryModel, primary_address: int, address: int) -> int:
    if memory.translation(primary_address).region != MemoryRegion.PALETTE:
        return 0
    decoded = memory.translation(address)
    if decoded.region == MemoryRegion.NAMETABLE:
        return memory.ciram[decoded.ciram_address]
    return 0


class IntegratedMemoryReference:
    def __init__(self) -> None:
        self.registers = PpuRegisterModel()
        self.timing = PpuTimingModel()
        self.memory = PpuMemoryModel()

    def emit(
        self,
        stream: TextIO,
        scenario: int,
        inputs: PpuBusInputs,
        *,
        ppu_enable: bool = False,
        mode: MirroringMode = MirroringMode.VERTICAL,
    ) -> tuple[bool, int, MemoryRegion]:
        self.memory.set_mode(mode)
        address = self.registers.v & 0x3FFF
        buffer_address = (
            (address - 0x1000) & 0x3FFF if address >= 0x3F00 else address
        )
        memory_read_data = self.memory.read(address)
        memory_buffer_read_data = buffer_read(self.memory, address, buffer_address)
        reg_inputs = replace(
            inputs,
            memory_read_data=memory_read_data,
            memory_buffer_read_data=memory_buffer_read_data,
            vblank_start_event=(
                self.timing.vblank_start(ppu_enable) and not inputs.reset
            ),
            status_clear_event=(
                self.timing.vblank_end(ppu_enable) and not inputs.reset
            ),
        )
        observation = self.registers.observe(reg_inputs)
        translation = self.memory.translation(observation.memory_address)
        accepted_write = observation.memory_write_request
        chr_read = observation.memory_read_request and (
            translation.region == MemoryRegion.CHR
        )
        chr_write = accepted_write and translation.region == MemoryRegion.CHR
        ciram_write = (
            accepted_write and translation.region == MemoryRegion.NAMETABLE
        )
        palette_write = (
            accepted_write and translation.region == MemoryRegion.PALETTE
        )
        pre_timing = self.timing.snapshot()
        rendering_enabled = self.registers.rendering_enabled

        if observation.memory_write_request:
            self.memory.write(observation.memory_address, inputs.cpu_write_data)
        self.registers.clock(reg_inputs)
        self.timing.clock(
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            rendering_enabled=rendering_enabled,
        )

        post_address = self.registers.v & 0x3FFF
        post_buffer_address = (
            (post_address - 0x1000) & 0x3FFF
            if post_address >= 0x3F00
            else post_address
        )
        post_timing = self.timing.snapshot()
        registers = self.registers

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
            inputs.cpu_write_data & 0xFF,
            translation.chr_address,
            int(chr_read),
            int(chr_write),
            inputs.cpu_write_data & 0xFF,
            int(translation.region),
            translation.normalized_nametable_address,
            translation.logical_nametable,
            translation.nametable_offset,
            translation.physical_ciram_page,
            translation.ciram_address,
            translation.palette_index,
            int(ciram_write),
            int(palette_write),
            memory_read_data,
            memory_buffer_read_data,
            pre_timing.dot,
            pre_timing.scanline,
            int(pre_timing.frame_odd),
            int(pre_timing.vblank),
            registers.ppuctrl,
            registers.ppumask,
            int(registers.status_vblank),
            int(registers.status_sprite_zero_hit),
            int(registers.status_sprite_overflow),
            registers.oam_addr,
            registers.v,
            registers.t,
            registers.x,
            int(registers.w),
            registers.read_buffer,
            registers.io_latch,
            post_timing.dot,
            post_timing.scanline,
            int(post_timing.frame_odd),
            int(post_timing.vblank),
            self.memory.read(post_address),
            buffer_read(self.memory, post_address, post_buffer_address),
        )
        stream.write(" ".join(str(value) for value in values) + "\n")
        return observation.accepted, observation.register_index, translation.region


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


def append_address(sequence: list[PpuBusInputs], address: int) -> None:
    sequence.append(transaction(6, write=True, data=(address >> 8) & 0x3F))
    sequence.append(transaction(6, write=True, data=address & 0xFF))


def write_directed(
    stream: TextIO, reference: IntegratedMemoryReference
) -> tuple[int, int]:
    rows = 0
    ppudata = 0
    for _ in range(2):
        reference.emit(stream, 1, PpuBusInputs(reset=True))
        rows += 1

    sequence: list[tuple[PpuBusInputs, MirroringMode, bool]] = []
    for mode in MirroringMode:
        for address, data in (
            (0x0000, 0x11),
            (0x1FFF, 0x22),
            (0x2000, 0x33),
            (0x2BFF, 0x44),
            (0x3000, 0x55),
            (0x3EFF, 0x66),
            (0x3F00, 0x77),
            (0x3F10, 0x88),
            (0x3FFF, 0x99),
        ):
            pair: list[PpuBusInputs] = []
            append_address(pair, address)
            pair.append(transaction(PPUDATA, write=True, data=data))
            append_address(pair, address)
            pair.append(transaction(PPUDATA, write=False))
            if address < 0x3F00:
                append_address(pair, address)
                pair.append(transaction(PPUDATA, write=False))
            sequence.extend((item, mode, bool((address + data) & 1)) for item in pair)

    # Verify both increments and low-14-bit wrap through the real register path.
    sequence.append((transaction(0, write=True, data=0x04), MirroringMode.VERTICAL, False))
    wrapped: list[PpuBusInputs] = []
    append_address(wrapped, 0x3FF0)
    wrapped.extend(
        (
            transaction(PPUDATA, write=True, data=0xA5),
            transaction(PPUDATA, write=True, data=0x5A),
        )
    )
    sequence.extend((item, MirroringMode.VERTICAL, False) for item in wrapped)
    sequence.append((transaction(0, write=True, data=0x00), MirroringMode.VERTICAL, False))

    # A held PPUDATA write/read may be visible on the bus, but only the cycle
    # with both enable and valid asserted may commit or emit a memory strobe.
    stalled_write = transaction(PPUDATA, write=True, data=0xC3, enable=False)
    sequence.extend((stalled_write, MirroringMode.HORIZONTAL, True) for _ in range(7))
    sequence.append((replace(stalled_write, cpu_enable=True), MirroringMode.HORIZONTAL, True))
    stalled_read = transaction(PPUDATA, write=False, enable=True, valid=False)
    sequence.extend((stalled_read, MirroringMode.HORIZONTAL, False) for _ in range(5))
    sequence.append((replace(stalled_read, cpu_bus_valid=True), MirroringMode.HORIZONTAL, False))

    for inputs, mode, ppu_enable in sequence:
        accepted, register, _ = reference.emit(
            stream, 1, inputs, ppu_enable=ppu_enable, mode=mode
        )
        rows += 1
        ppudata += int(accepted and register == PPUDATA)
    return rows, ppudata


def write_random(
    stream: TextIO, reference: IntegratedMemoryReference
) -> tuple[int, int, int, int, int, list[int], list[int]]:
    for _ in range(2):
        reference.emit(stream, 2, PpuBusInputs(reset=True))
    rng = XorShift32(RANDOM_SEED)
    held = PpuBusInputs()
    accepted = 0
    ppudata = 0
    ppudata_reads = 0
    ppudata_writes = 0
    active_stalls = 0
    ppu_ticks = 0
    region_counts = [0, 0, 0]
    mode_counts = [0, 0, 0, 0]
    weighted_registers = (0, 1, 2, 5, 6, 6, 7, 7, 7, 7, 7, 7)

    for _ in range(RANDOM_FABRIC_CYCLES):
        if rng.next() % 100 < 57:
            register = weighted_registers[rng.next() % len(weighted_registers)]
            held = transaction(
                register,
                write=bool(rng.next() & 1),
                data=rng.next() & 0xFF,
                enable=False,
                valid=rng.next() % 100 < 81,
                mirror=rng.next() & 0x3FF,
            )
        cpu_enable = rng.next() % 100 < 61
        inputs = replace(held, cpu_enable=cpu_enable)
        mode = MirroringMode(rng.next() & 3)
        ppu_enable = rng.next() % 100 < 68
        was_accepted, register, region = reference.emit(
            stream, 2, inputs, ppu_enable=ppu_enable, mode=mode
        )
        accepted += int(was_accepted)
        ppu_ticks += int(ppu_enable)
        if (
            not cpu_enable
            and inputs.cpu_bus_valid
            and 0x2000 <= inputs.cpu_address <= 0x3FFF
        ):
            active_stalls += 1
        if was_accepted and register == PPUDATA:
            ppudata += 1
            ppudata_writes += int(inputs.cpu_bus_write)
            ppudata_reads += int(not inputs.cpu_bus_write)
            region_counts[int(region)] += 1
            mode_counts[int(mode)] += 1

    return (
        2 + RANDOM_FABRIC_CYCLES,
        accepted,
        ppudata,
        ppudata_reads,
        ppudata_writes,
        [active_stalls, ppu_ticks, *region_counts],
        mode_counts,
    )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    reference = IntegratedMemoryReference()
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        directed_rows, directed_ppudata = write_directed(stream, reference)
        random_stats = write_random(stream, reference)

    rows, accepted, ppudata, reads, writes, extra, modes = random_stats
    stalls, ticks, chr_count, nt_count, palette_count = extra
    print(
        "Integrated Phase 3C Python reference vectors: "
        f"rows={directed_rows + rows}, directed_rows={directed_rows}, "
        f"directed_ppudata={directed_ppudata}, seed=0x{RANDOM_SEED:08X}, "
        f"random_fabric_cycles={RANDOM_FABRIC_CYCLES}, accepted={accepted}, "
        f"ppudata={ppudata}, reads={reads}, writes={writes}, "
        f"active_stalls={stalls}, ppu_ticks={ticks}, chr={chr_count}, "
        f"nametable={nt_count}, palette={palette_count}, modes={modes}"
    )


if __name__ == "__main__":
    main()
