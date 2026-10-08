#!/usr/bin/env python3
"""Generate original legal NROM-128 audio programs for Phase 5J."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path


PRG_SIZE = 16 * 1024
RESET_VECTOR = 0x8000
DMC_SAMPLE_ADDRESS = 0xE000
READY_VALUE = 0xA5
SCENARIOS = (
    "pulse1", "pulse2", "triangle", "noise", "dmc", "combined",
    "silence", "silence_transition", "melody",
)

PULSE1_TIMER = 253
PULSE2_TIMER = 169
TRIANGLE_TIMER = 126
MELODY_TIMERS = (427, 380, 338, 284, 253, 284, 338, 380, 427, 338, 284, 427)


@dataclass
class Assembler:
    origin: int = RESET_VECTOR
    data: bytearray = field(default_factory=bytearray)
    labels: dict[str, int] = field(default_factory=dict)
    branches: list[tuple[int, str]] = field(default_factory=list)
    jumps: list[tuple[int, str]] = field(default_factory=list)

    @property
    def pc(self) -> int:
        return self.origin + len(self.data)

    def emit(self, *values: int) -> None:
        for value in values:
            if not 0 <= value <= 0xFF:
                raise ValueError(f"byte out of range: {value}")
            self.data.append(value)

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label {name}")
        self.labels[name] = self.pc

    def branch(self, opcode: int, target: str) -> None:
        self.emit(opcode, 0)
        self.branches.append((len(self.data) - 1, target))

    def jump(self, target: str) -> None:
        self.emit(0x4C, 0, 0)
        self.jumps.append((len(self.data) - 2, target))

    def resolve(self) -> None:
        for offset, target in self.branches:
            displacement = self.labels[target] - (self.origin + offset + 1)
            if not -128 <= displacement <= 127:
                raise ValueError(f"branch to {target} is out of range")
            self.data[offset] = displacement & 0xFF
        for offset, target in self.jumps:
            address = self.labels[target]
            self.data[offset] = address & 0xFF
            self.data[offset + 1] = address >> 8


def write_abs(asm: Assembler, address: int, value: int) -> None:
    asm.emit(0xA9, value, 0x8D, address & 0xFF, address >> 8)


def write_zp(asm: Assembler, address: int, value: int) -> None:
    asm.emit(0xA9, value, 0x85, address)


def set_timer(asm: Assembler, low_address: int, high_address: int, timer: int) -> None:
    if not 0 <= timer <= 0x7FF:
        raise ValueError("APU timer out of range")
    write_abs(asm, low_address, timer & 0xFF)
    write_abs(asm, high_address, 0xF8 | (timer >> 8))


def delay(asm: Assembler, name: str, outer_count: int) -> None:
    if not 1 <= outer_count <= 255:
        raise ValueError("delay outer count out of range")
    asm.emit(0xA2, outer_count)  # LDX #outer_count
    asm.label(f"{name}_outer")
    asm.emit(0xA0, 0x00)  # LDY #0: 256 inner iterations
    asm.label(f"{name}_inner")
    asm.emit(0x88)  # DEY
    asm.branch(0xD0, f"{name}_inner")  # BNE
    asm.emit(0xCA)  # DEX
    asm.branch(0xD0, f"{name}_outer")  # BNE


def configure_pulse1(asm: Assembler, timer: int = PULSE1_TIMER) -> None:
    write_abs(asm, 0x4000, 0xBF)  # 50% duty, halt length, constant volume 15
    set_timer(asm, 0x4002, 0x4003, timer)


def configure_pulse2(asm: Assembler, timer: int = PULSE2_TIMER) -> None:
    write_abs(asm, 0x4004, 0xBF)
    set_timer(asm, 0x4006, 0x4007, timer)


def configure_triangle(asm: Assembler, timer: int = TRIANGLE_TIMER) -> None:
    write_abs(asm, 0x4008, 0xFF)  # control set, linear reload 127
    set_timer(asm, 0x400A, 0x400B, timer)


def configure_noise(asm: Assembler) -> None:
    write_abs(asm, 0x400C, 0x3F)  # halt length, constant volume 15
    write_abs(asm, 0x400E, 0x04)  # long mode, NTSC period 64 CPU cycles
    write_abs(asm, 0x400F, 0xF8)


def configure_dmc(asm: Assembler) -> None:
    write_abs(asm, 0x4010, 0x4F)  # loop, IRQ off, fastest NTSC rate
    write_abs(asm, 0x4011, 0x40)
    write_abs(asm, 0x4012, (DMC_SAMPLE_ADDRESS - 0xC000) // 64)
    write_abs(asm, 0x4013, 0x01)  # 17-byte legal generated sample


def program_for(scenario: str) -> tuple[bytes, dict[str, object]]:
    if scenario not in SCENARIOS:
        raise ValueError(f"unknown scenario {scenario}")
    asm = Assembler()
    asm.emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A)  # SEI; CLD; LDX #$ff; TXS
    write_abs(asm, 0x2000, 0x00)  # PPU NMI off
    write_abs(asm, 0x4017, 0x40)  # inhibit frame IRQ
    write_abs(asm, 0x4015, 0x00)

    if scenario == "pulse1":
        write_abs(asm, 0x4015, 0x01)
        configure_pulse1(asm)
    elif scenario == "pulse2":
        write_abs(asm, 0x4015, 0x02)
        configure_pulse2(asm)
    elif scenario == "triangle":
        write_abs(asm, 0x4015, 0x04)
        configure_triangle(asm)
    elif scenario == "noise":
        write_abs(asm, 0x4015, 0x08)
        configure_noise(asm)
    elif scenario == "dmc":
        configure_dmc(asm)
        write_abs(asm, 0x4015, 0x10)
    elif scenario == "combined":
        write_abs(asm, 0x4015, 0x0F)
        configure_pulse1(asm)
        configure_pulse2(asm)
        configure_triangle(asm)
        configure_noise(asm)
        configure_dmc(asm)
        write_abs(asm, 0x4015, 0x1F)
    elif scenario == "silence_transition":
        write_zp(asm, 0x00, READY_VALUE)
        delay(asm, "silence_before", 220)
        write_abs(asm, 0x4015, 0x01)
        configure_pulse1(asm)
        delay(asm, "active", 255)
        write_abs(asm, 0x4015, 0x00)
        delay(asm, "silence_after", 220)
    elif scenario == "melody":
        write_zp(asm, 0x00, READY_VALUE)
        delay(asm, "melody_lead_silence", 220)
        write_abs(asm, 0x4015, 0x07)
        write_abs(asm, 0x4000, 0xBF)
        write_abs(asm, 0x4004, 0x7A)  # 25% duty, constant volume 10
        write_abs(asm, 0x4008, 0xFF)
        for index, timer in enumerate(MELODY_TIMERS):
            set_timer(asm, 0x4002, 0x4003, timer)
            harmony_timer = min(0x7FF, 2 * (timer + 1) - 1)
            set_timer(asm, 0x4006, 0x4007, harmony_timer)
            triangle_timer = max(2, (timer - 1) // 2)
            set_timer(asm, 0x400A, 0x400B, triangle_timer)
            delay(asm, f"note_{index}", 240)
        write_abs(asm, 0x4015, 0x00)
        delay(asm, "melody_tail_silence", 220)

    if scenario not in ("silence_transition", "melody"):
        write_zp(asm, 0x00, READY_VALUE)
    asm.label("forever")
    asm.jump("forever")
    asm.resolve()

    if len(asm.data) >= DMC_SAMPLE_ADDRESS - RESET_VECTOR:
        raise ValueError("program overlaps generated DMC sample")
    prg = bytearray([0xEA] * PRG_SIZE)
    prg[: len(asm.data)] = asm.data
    sample_offset = DMC_SAMPLE_ADDRESS & 0x3FFF
    dmc_bytes = bytes(
        (0x55, 0xAA, 0x0F, 0xF0, 0x33, 0xCC, 0x69, 0x96,
         0x87, 0x78, 0x1E, 0xE1, 0x4B, 0xB4, 0x25, 0xDA, 0x5A)
    )
    prg[sample_offset : sample_offset + len(dmc_bytes)] = dmc_bytes
    for offset in (0x3FFA, 0x3FFC, 0x3FFE):
        prg[offset] = RESET_VECTOR & 0xFF
        prg[offset + 1] = RESET_VECTOR >> 8
    metadata: dict[str, object] = {
        "scenario": scenario,
        "program_bytes": len(asm.data),
        "prg_crc32": f"{binascii.crc32(prg):08x}",
        "dmc_sample_address": f"{DMC_SAMPLE_ADDRESS:04x}",
        "dmc_sample_hex": dmc_bytes.hex(),
        "pulse1_timer": PULSE1_TIMER,
        "pulse2_timer": PULSE2_TIMER,
        "triangle_timer": TRIANGLE_TIMER,
        "ready_value": READY_VALUE,
        "melody_timers": list(MELODY_TIMERS),
    }
    return bytes(prg), metadata


def ines(prg: bytes) -> bytes:
    if len(prg) != PRG_SIZE:
        raise ValueError("Phase 5J images must be NROM-128")
    return b"NES\x1a" + bytes((1, 0, 0, 0)) + bytes(8) + prg


def write_outputs(output_dir: Path, scenarios: tuple[str, ...]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    reference: dict[str, object] = {}
    for scenario in scenarios:
        prg, metadata = program_for(scenario)
        stem = f"phase5j_{scenario}"
        (output_dir / f"{stem}.prg.hex").write_text(
            "".join(f"{byte:02x}\n" for byte in prg), encoding="ascii"
        )
        rom = ines(prg)
        (output_dir / f"{stem}.nes").write_bytes(rom)
        metadata["ines_sha256"] = hashlib.sha256(rom).hexdigest()
        reference[scenario] = metadata
    (output_dir / "phase5j_rom_reference.json").write_text(
        json.dumps(reference, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("build/sim"))
    parser.add_argument("--scenario", choices=("all", *SCENARIOS), default="all")
    args = parser.parse_args()
    scenarios = SCENARIOS if args.scenario == "all" else (args.scenario,)
    write_outputs(args.output_dir, scenarios)
    print(
        f"Phase 5J legal audio ROMs: {len(scenarios)} scenario(s) in "
        f"{args.output_dir}"
    )


if __name__ == "__main__":
    main()
