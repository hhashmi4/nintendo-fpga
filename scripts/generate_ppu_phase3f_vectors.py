#!/usr/bin/env python3
"""Generate integrated timing/register/OAM Phase 3F reference vectors."""

from argparse import ArgumentParser
from dataclasses import replace
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_registers import (  # noqa: E402
    OAMADDR,
    OAMDATA,
    PPUCTRL,
    PPUMASK,
    PPUSTATUS,
    PpuBusInputs,
    PpuRegisterModel,
)
from verification.ppu_sprite_eval import SpriteEvaluationModel  # noqa: E402
from verification.ppu_timing import PpuTimingModel  # noqa: E402


RANDOM_SEED = 0x3F200401
RANDOM_FABRIC_CYCLES = 220_000


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


class IntegratedSpriteReference:
    def __init__(self) -> None:
        self.registers = PpuRegisterModel()
        self.timing = PpuTimingModel()
        self.oam = SpriteEvaluationModel()
        self.rows = 0
        self.scenarios = [0] * 6
        self.ppu_ticks = 0
        self.ppu_stalls = 0
        self.accepted = 0
        self.oam_transactions = 0
        self.oam_reads = 0
        self.oam_writes = 0
        self.oam_commits = 0
        self.collisions = 0
        self.clear_writes = 0
        self.secondary_writes = 0
        self.overflow_sets = 0
        self.sprite_zero_selections = 0
        self.evaluated_y = 0
        self.selected = 0
        self.visible_lines = 0
        self.frames = 0

    def emit(
        self,
        stream: TextIO,
        scenario: int,
        inputs: PpuBusInputs = PpuBusInputs(),
        *,
        ppu_enable: bool = False,
        mirroring_mode: int = 0,
        secondary_read_slot: int = 0,
    ) -> None:
        pre = self.timing.snapshot()
        rendering = self.registers.rendering_enabled
        size_16 = bool(self.registers.ppuctrl & 0x20)
        pre_oam_addr = self.registers.oam_addr
        pre_phase = self.oam.phase
        selected, register_index = self.registers.decode(inputs.cpu_address)
        accepted = (
            not inputs.reset
            and inputs.cpu_enable
            and inputs.cpu_bus_valid
            and selected
        )
        oam_access = accepted and register_index == OAMDATA
        oam_write_enable = oam_access and inputs.cpu_bus_write
        oam_observation = self.oam.observe(
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            dot=pre.dot,
            scanline=pre.scanline,
            rendering_enabled=rendering,
            sprite_size_16=size_16,
            cpu_oam_addr=pre_oam_addr,
            cpu_write_data=inputs.cpu_write_data,
            cpu_write_enable=oam_write_enable,
            cpu_access=oam_access,
        )
        reg_inputs = replace(
            inputs,
            ppu_enable=ppu_enable,
            dot=pre.dot,
            scanline=pre.scanline,
            oam_read_data=oam_observation.cpu_read_data,
            vblank_start_event=(
                self.timing.vblank_start(ppu_enable) and not inputs.reset
            ),
            status_clear_event=(
                self.timing.vblank_end(ppu_enable) and not inputs.reset
            ),
            sprite_overflow_set=self.oam.overflow_set,
        )
        reg_observation = self.registers.observe(reg_inputs)
        assert reg_observation.oam_write_enable == oam_write_enable

        old_count = self.oam.selected_count
        old_zero = self.oam.sprite_zero_selected
        old_parity = self.timing.frame_odd
        self.registers.clock(reg_inputs)
        self.oam.clock(
            oam_observation,
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            dot=pre.dot,
            scanline=pre.scanline,
            rendering_enabled=rendering,
            sprite_size_16=size_16,
            cpu_oam_addr=pre_oam_addr,
            cpu_write_data=inputs.cpu_write_data,
        )
        self.timing.clock(
            reset=inputs.reset,
            ppu_enable=ppu_enable,
            rendering_enabled=rendering,
        )
        post = self.timing.snapshot()

        slot = secondary_read_slot & 7
        base = slot * 4
        values = (
            scenario,
            int(inputs.reset),
            int(ppu_enable),
            int(inputs.cpu_enable),
            int(inputs.cpu_bus_valid),
            int(inputs.cpu_bus_write),
            inputs.cpu_address & 0xFFFF,
            inputs.cpu_write_data & 0xFF,
            mirroring_mode & 3,
            slot,
            pre.dot,
            pre.scanline,
            int(pre.frame_odd),
            int(reg_observation.selected),
            reg_observation.register_index,
            reg_observation.cpu_read_data,
            pre_oam_addr,
            int(oam_write_enable),
            int(oam_observation.cpu_write_commit),
            int(oam_observation.cpu_collision),
            oam_observation.primary_read_address,
            oam_observation.primary_read_data,
            int(oam_observation.secondary_clear_write),
            int(oam_observation.secondary_evaluation_write),
            oam_observation.secondary_write_address,
            oam_observation.secondary_write_data,
            int(self.registers.status_sprite_overflow),
            post.dot,
            post.scanline,
            int(post.frame_odd),
            self.registers.ppuctrl,
            self.registers.ppumask,
            self.registers.oam_addr,
            self.registers.io_latch,
            self.oam.selected_count,
            int(self.oam.sprite_zero_selected),
            int(self.oam.overflow_set),
            int(self.oam.phase),
            self.oam.n,
            self.oam.m,
            int(self.oam.done),
            self.oam.secondary_oam[base],
            self.oam.secondary_oam[base + 1],
            self.oam.secondary_oam[base + 2],
            self.oam.secondary_oam[base + 3],
            self.oam.secondary_indices[slot],
            int(slot < self.oam.selected_count),
        )
        stream.write(" ".join(str(value) for value in values) + "\n")

        self.rows += 1
        self.scenarios[scenario] += 1
        if not inputs.reset:
            self.ppu_ticks += int(ppu_enable)
            self.ppu_stalls += int(not ppu_enable)
            self.accepted += int(accepted)
            self.oam_transactions += int(oam_access)
            self.oam_reads += int(oam_access and not inputs.cpu_bus_write)
            self.oam_writes += int(oam_write_enable)
            self.oam_commits += int(oam_observation.cpu_write_commit)
            self.collisions += int(oam_observation.cpu_collision)
            self.clear_writes += int(oam_observation.secondary_clear_write)
            self.secondary_writes += int(
                oam_observation.secondary_evaluation_write
            )
            self.overflow_sets += int(self.oam.overflow_set)
            self.sprite_zero_selections += int(
                self.oam.sprite_zero_selected and not old_zero
            )
            self.selected += max(0, self.oam.selected_count - old_count)
            self.evaluated_y += int(
                ppu_enable
                and 65 <= pre.dot <= 256
                and pre.dot % 2 == 0
                and pre_phase.value in (2, 4)
            )
            self.visible_lines += int(
                ppu_enable and pre.scanline < 240 and pre.dot == 1 and rendering
            )
            self.frames += int(self.timing.frame_odd != old_parity)


def reset(reference: IntegratedSpriteReference, stream: TextIO, scenario: int) -> None:
    reference.emit(stream, scenario, PpuBusInputs(reset=True))
    reference.emit(stream, scenario, PpuBusInputs(reset=True))


def cpu_write(
    reference: IntegratedSpriteReference,
    stream: TextIO,
    scenario: int,
    register: int,
    data: int,
    *,
    mirror: int = 0,
) -> None:
    reference.emit(
        stream,
        scenario,
        transaction(register, write=True, data=data, mirror=mirror),
    )


def load_primary_oam(
    reference: IntegratedSpriteReference,
    stream: TextIO,
    scenario: int,
    contents: list[int],
) -> None:
    cpu_write(reference, stream, scenario, OAMADDR, 0)
    for address, data in enumerate(contents):
        if address % 19 == 0:
            reference.emit(
                stream,
                scenario,
                transaction(OAMDATA, write=True, data=data, enable=False),
            )
        cpu_write(
            reference,
            stream,
            scenario,
            OAMDATA,
            data,
            mirror=address & 0x3FF,
        )


def deterministic_oam(kind: int) -> list[int]:
    contents = []
    for sprite in range(64):
        if kind == 0:
            y = (sprite * 4 - 1) & 0xFF
        elif kind == 1:
            y = ((sprite // 12) * 24) & 0xFF
        else:
            y = (sprite * 29 + 239) & 0xFF
        contents.extend((y, sprite, sprite ^ 0xA5, sprite * 7 & 0xFF))
    return contents


def run_until(
    reference: IntegratedSpriteReference,
    stream: TextIO,
    scenario: int,
    predicate,
    *,
    max_cycles: int = 100_000,
) -> None:
    for _ in range(max_cycles):
        if predicate():
            return
        reference.emit(
            stream,
            scenario,
            ppu_enable=True,
            secondary_read_slot=reference.timing.dot & 7,
        )
    raise RuntimeError("Phase 3F integration predicate timed out")


def write_cpu_oam(reference: IntegratedSpriteReference, stream: TextIO) -> None:
    scenario = 1
    reset(reference, stream, scenario)
    contents = [address ^ 0x5A for address in range(256)]
    load_primary_oam(reference, stream, scenario, contents)
    for address, expected in enumerate(contents):
        cpu_write(reference, stream, scenario, OAMADDR, address)
        reference.emit(
            stream,
            scenario,
            transaction(OAMDATA, write=False, mirror=address),
            secondary_read_slot=address & 7,
        )
        assert reference.oam.primary_oam[address] == expected
    assert reference.registers.oam_addr == 0xFF
    cpu_write(reference, stream, scenario, OAMDATA, 0xC3)
    assert reference.registers.oam_addr == 0
    assert reference.oam.primary_oam[0xFF] == 0xC3


def write_mask_cases(reference: IntegratedSpriteReference, stream: TextIO) -> None:
    scenario = 2
    for mask in (0x00, 0x08, 0x10, 0x18):
        reset(reference, stream, scenario)
        load_primary_oam(reference, stream, scenario, deterministic_oam(mask))
        cpu_write(reference, stream, scenario, PPUMASK, mask)
        run_until(
            reference,
            stream,
            scenario,
            lambda: reference.timing.scanline == 1 and reference.timing.dot == 0,
        )
        if mask == 0:
            assert reference.oam.phase.value == 0
        else:
            assert reference.oam.phase.value == 6


def write_status_lifetime(reference: IntegratedSpriteReference, stream: TextIO) -> None:
    scenario = 3
    reset(reference, stream, scenario)
    contents = [0x80] * 256
    for sprite in range(9):
        base = sprite * 4
        contents[base : base + 4] = [0, sprite, 0, sprite * 8]
    load_primary_oam(reference, stream, scenario, contents)
    cpu_write(reference, stream, scenario, PPUMASK, 0x08)
    run_until(
        reference,
        stream,
        scenario,
        lambda: reference.registers.status_sprite_overflow,
    )
    reference.emit(stream, scenario, transaction(PPUSTATUS, write=False))
    assert reference.registers.status_sprite_overflow
    run_until(
        reference,
        stream,
        scenario,
        lambda: reference.timing.scanline == 261 and reference.timing.dot == 2,
    )
    assert not reference.registers.status_sprite_overflow


def random_address(rng: XorShift32, register: int) -> int:
    if rng.next() % 100 < 93:
        return 0x2000 + ((rng.next() & 0x3FF) << 3) + register
    return 0x4000 | (rng.next() & 0xBFFF)


def write_random(reference: IntegratedSpriteReference, stream: TextIO) -> None:
    scenario = 4
    reset(reference, stream, scenario)
    load_primary_oam(reference, stream, scenario, deterministic_oam(2))
    rng = XorShift32(RANDOM_SEED)
    held = PpuBusInputs()
    weighted = (
        OAMADDR,
        OAMDATA,
        OAMDATA,
        OAMDATA,
        PPUMASK,
        PPUCTRL,
        PPUSTATUS,
    )
    for _ in range(RANDOM_FABRIC_CYCLES):
        if rng.next() % 100 < 59:
            register = weighted[rng.next() % len(weighted)]
            held = PpuBusInputs(
                cpu_bus_valid=rng.next() % 100 < 87,
                cpu_bus_write=(
                    False if register == PPUSTATUS else bool(rng.next() & 1)
                ),
                cpu_address=random_address(rng, register),
                cpu_write_data=rng.next() & 0xFF,
            )
        inputs = replace(held, cpu_enable=rng.next() % 100 < 61)
        reference.emit(
            stream,
            scenario,
            inputs,
            ppu_enable=rng.next() % 100 < 72,
            mirroring_mode=rng.next() & 3,
            secondary_read_slot=rng.next() & 7,
        )


def write_full_frames(reference: IntegratedSpriteReference, stream: TextIO) -> None:
    scenario = 5
    for kind, size_16 in ((0, False), (1, False), (2, True)):
        reset(reference, stream, scenario)
        load_primary_oam(reference, stream, scenario, deterministic_oam(kind))
        cpu_write(reference, stream, scenario, PPUCTRL, 0x20 if size_16 else 0)
        cpu_write(reference, stream, scenario, PPUMASK, 0x10)
        starting_parity = reference.timing.frame_odd
        while reference.timing.frame_odd == starting_parity:
            reference.emit(
                stream,
                scenario,
                ppu_enable=True,
                secondary_read_slot=reference.timing.dot & 7,
            )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    reference = IntegratedSpriteReference()
    with args.output.open("w", encoding="ascii") as stream:
        write_cpu_oam(reference, stream)
        write_mask_cases(reference, stream)
        write_status_lifetime(reference, stream)
        write_random(reference, stream)
        write_full_frames(reference, stream)
    print(
        "Integrated Phase 3F vectors: "
        f"seed={RANDOM_SEED:08x} rows={reference.rows} "
        f"ppu_ticks={reference.ppu_ticks} stalls={reference.ppu_stalls} "
        f"accepted={reference.accepted} oam_transactions={reference.oam_transactions} "
        f"oam_reads={reference.oam_reads} oam_writes={reference.oam_writes} "
        f"oam_commits={reference.oam_commits} collisions={reference.collisions} "
        f"clear_writes={reference.clear_writes} "
        f"secondary_writes={reference.secondary_writes} "
        f"evaluated_y={reference.evaluated_y} selected={reference.selected} "
        f"overflow_sets={reference.overflow_sets} "
        f"sprite_zero={reference.sprite_zero_selections} "
        f"visible_lines={reference.visible_lines} frames={reference.frames} "
        f"scenarios={reference.scenarios[1:]}"
    )


if __name__ == "__main__":
    main()
