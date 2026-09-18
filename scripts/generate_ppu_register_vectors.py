#!/usr/bin/env python3
"""Generate deterministic Phase 3B integrated PPU reference vectors."""

from argparse import ArgumentParser
from dataclasses import replace
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_registers import PpuBusInputs, PpuRegisterModel  # noqa: E402
from verification.ppu_timing import PpuTimingModel  # noqa: E402


RANDOM_SEED = 0x3B5EED01
RANDOM_FABRIC_CYCLES = 200_000


class XorShift32:
    def __init__(self, seed: int) -> None:
        if not seed:
            raise ValueError("xorshift seed must be nonzero")
        self.state = seed & 0xFFFF_FFFF

    def next(self) -> int:
        value = self.state
        value ^= (value << 13) & 0xFFFF_FFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFF_FFFF
        self.state = value & 0xFFFF_FFFF
        return self.state


class IntegratedReference:
    def __init__(self) -> None:
        self.registers = PpuRegisterModel()
        self.timing = PpuTimingModel()

    def write_row(
        self,
        stream: TextIO,
        scenario: int,
        inputs: PpuBusInputs,
        ppu_enable: bool,
    ) -> tuple[bool, int]:
        rendering = self.registers.rendering_enabled
        reg_inputs = replace(
            inputs,
            vblank_start_event=self.timing.vblank_start(ppu_enable)
            and not inputs.reset,
            status_clear_event=self.timing.vblank_end(ppu_enable)
            and not inputs.reset,
        )
        observation = self.registers.observe(reg_inputs)
        pre = self.timing.snapshot()
        pre_oam_addr = self.registers.oam_addr
        vblank_start = self.timing.vblank_start(ppu_enable) and not inputs.reset
        vblank_end = self.timing.vblank_end(ppu_enable) and not inputs.reset

        self.registers.clock(reg_inputs)
        self.timing.clock(
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            rendering_enabled=rendering,
        )
        post = self.timing.snapshot()
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
            int(inputs.sprite_zero_hit_set),
            int(inputs.sprite_overflow_set),
            inputs.oam_read_data & 0xFF,
            inputs.memory_read_data & 0xFF,
            inputs.memory_buffer_read_data & 0xFF,
            int(observation.selected),
            observation.register_index,
            observation.cpu_read_data,
            pre_oam_addr,
            int(observation.oam_write_enable),
            inputs.cpu_write_data & 0xFF,
            observation.memory_address,
            observation.memory_buffer_address,
            int(observation.memory_read_request),
            int(observation.memory_write_request),
            inputs.cpu_write_data & 0xFF,
            pre.dot,
            pre.scanline,
            int(pre.frame_odd),
            int(pre.vblank),
            int(vblank_start),
            int(vblank_end),
            int(rendering),
            post.dot,
            post.scanline,
            int(post.frame_odd),
            int(post.vblank),
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
        )
        stream.write(" ".join(str(value) for value in values) + "\n")
        return observation.accepted, observation.register_index


def bus(
    register: int,
    *,
    write: bool,
    data: int = 0,
    mirror: int = 0,
    enable: bool = True,
    valid: bool = True,
    oam: int = 0,
    memory: int = 0,
    buffer: int = 0,
) -> PpuBusInputs:
    return PpuBusInputs(
        cpu_enable=enable,
        cpu_bus_valid=valid,
        cpu_bus_write=write,
        cpu_address=0x2000 + ((mirror & 0x3FF) << 3) + register,
        cpu_write_data=data,
        oam_read_data=oam,
        memory_read_data=memory,
        memory_buffer_read_data=buffer,
    )


def write_reset(stream: TextIO, scenario: int, reference: IntegratedReference) -> int:
    rows = 0
    for _ in range(2):
        reference.write_row(stream, scenario, PpuBusInputs(reset=True), False)
        rows += 1
    return rows


def write_mirroring(stream: TextIO, reference: IntegratedReference) -> int:
    scenario = 1
    rows = write_reset(stream, scenario, reference)
    for address in range(0x2000, 0x4000):
        reference.write_row(
            stream,
            scenario,
            PpuBusInputs(cpu_address=address),
            False,
        )
        rows += 1
    for address in (0x0000, 0x1FFF, 0x4000, 0x4014, 0xFFFF):
        reference.write_row(
            stream,
            scenario,
            PpuBusInputs(cpu_address=address),
            False,
        )
        rows += 1
    return rows


def write_directed(stream: TextIO, reference: IntegratedReference) -> int:
    scenario = 2
    rows = write_reset(stream, scenario, reference)
    sequence: list[tuple[PpuBusInputs, bool]] = []

    for bit in range(8):
        sequence.append((bus(0, write=True, data=1 << bit, mirror=bit * 17), False))
    for bit in range(8):
        sequence.append((bus(1, write=True, data=1 << bit, mirror=bit * 19), False))

    sequence.extend(
        (
            (bus(3, write=True, data=0xFF), False),
            (bus(4, write=True, data=0x63), False),
            (bus(4, write=False, oam=0x9C), False),
            (bus(5, write=True, data=0xAE), False),
            (bus(5, write=True, data=0xD3), False),
            (bus(5, write=True, data=0x29), False),
            (bus(6, write=True, data=0x88), False),
            (bus(6, write=True, data=0x21), False),
            (bus(5, write=True, data=0x57), False),
            (bus(5, write=True, data=0xFF), False),
            (bus(2, write=False), False),
            (bus(6, write=True, data=0x3F), False),
            (bus(6, write=True, data=0x10), False),
            (bus(7, write=False, memory=0x67, buffer=0x89), False),
            (bus(6, write=True, data=0x23), False),
            (bus(6, write=True, data=0x45), False),
            (bus(7, write=False, memory=0xA5, buffer=0x00), False),
            (bus(0, write=True, data=0x04), False),
            (bus(7, write=True, data=0xDE), False),
        )
    )

    # Hold write/read buses across disabled or invalid cycles, then accept
    # exactly once.  The wrapper must emit no external strobe during stalls.
    held_write = bus(7, write=True, data=0xBA, enable=False)
    sequence.extend((held_write, False) for _ in range(5))
    sequence.append((replace(held_write, cpu_enable=True), False))
    held_status = bus(2, write=False, enable=True, valid=False)
    sequence.extend((held_status, True) for _ in range(4))
    sequence.append((replace(held_status, cpu_bus_valid=True), True))

    for inputs, ppu_enable in sequence:
        reference.write_row(stream, scenario, inputs, ppu_enable)
        rows += 1
    return rows


def random_address(rng: XorShift32) -> int:
    selection = rng.next() % 100
    if selection < 76:
        return 0x2000 + (rng.next() & 0x1FFF)
    if selection < 88:
        return rng.next() & 0x1FFF
    return 0x4000 + (rng.next() % 0xC000)


def write_random(
    stream: TextIO, reference: IntegratedReference
) -> tuple[int, int, int, list[int], int]:
    scenario = 3
    rows = write_reset(stream, scenario, reference)
    rng = XorShift32(RANDOM_SEED)
    held = PpuBusInputs()
    accepted = 0
    access_counts = [0] * 8
    ppu_ticks = 0

    for _ in range(RANDOM_FABRIC_CYCLES):
        if rng.next() % 100 < 62:
            held = PpuBusInputs(
                cpu_bus_valid=rng.next() % 100 < 78,
                cpu_bus_write=bool(rng.next() & 1),
                cpu_address=random_address(rng),
                cpu_write_data=rng.next() & 0xFF,
                sprite_zero_hit_set=rng.next() % 4096 == 0,
                sprite_overflow_set=rng.next() % 4096 == 0,
                oam_read_data=rng.next() & 0xFF,
                memory_read_data=rng.next() & 0xFF,
                memory_buffer_read_data=rng.next() & 0xFF,
            )
        inputs = replace(held, cpu_enable=rng.next() % 100 < 64)
        ppu_enable = rng.next() % 100 < 67
        was_accepted, register = reference.write_row(
            stream, scenario, inputs, ppu_enable
        )
        accepted += int(was_accepted)
        if was_accepted:
            access_counts[register] += 1
        ppu_ticks += int(ppu_enable)
        rows += 1

    return rows, accepted, RANDOM_FABRIC_CYCLES - accepted, access_counts, ppu_ticks


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    reference = IntegratedReference()
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        mirror_rows = write_mirroring(stream, reference)
        directed_rows = write_directed(stream, reference)
        random_stats = write_random(stream, reference)

    random_rows, accepted, rejected, counts, ppu_ticks = random_stats
    print(
        "PPU register Python reference vectors: "
        f"rows={mirror_rows + directed_rows + random_rows}, "
        f"mirror_addresses=8192, seed=0x{RANDOM_SEED:08X}, "
        f"random_fabric_cycles={RANDOM_FABRIC_CYCLES}, accepted={accepted}, "
        f"rejected_or_stalled={rejected}, ppu_ticks={ppu_ticks}, "
        f"register_accesses={counts}"
    )


if __name__ == "__main__":
    main()
