#!/usr/bin/env python3
"""Generate the legal NROM-128 programs used by the Phase 5I RTL test.

The programs are deliberately assembled here instead of embedding opaque ROM
bytes in the testbench.  Game A exercises real CPU/APU interrupt handling;
Game B is the runtime-replacement/reset sentinel.  Both outputs include an
iNES image for inspection and a one-byte-per-line PRG image for $readmemh.
"""

from __future__ import annotations

import argparse
import binascii
from dataclasses import dataclass, field
from pathlib import Path


PRG_SIZE = 16 * 1024
RESET = 0x8000
IRQ_HANDLER = 0x9000
NMI_HANDLER = 0x9200
SAMPLE = 0xF000


@dataclass
class Assembler:
    origin: int = RESET
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
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.pc

    def branch(self, opcode: int, target: str) -> None:
        self.emit(opcode, 0)
        self.branches.append((len(self.data) - 1, target))

    def jump(self, target: str) -> None:
        self.emit(0x4C, 0, 0)
        self.jumps.append((len(self.data) - 2, target))

    def pad_to(self, address: int, fill: int = 0xEA) -> None:
        if self.pc > address:
            raise ValueError(f"assembly crossed ${address:04X}")
        self.data.extend([fill] * (address - self.pc))

    def resolve(self) -> None:
        for operand_offset, target in self.branches:
            target_address = self.labels[target]
            next_pc = self.origin + operand_offset + 1
            displacement = target_address - next_pc
            if not -128 <= displacement <= 127:
                raise ValueError(
                    f"branch to {target} is out of range ({displacement})"
                )
            self.data[operand_offset] = displacement & 0xFF
        for operand_offset, target in self.jumps:
            target_address = self.labels[target]
            self.data[operand_offset] = target_address & 0xFF
            self.data[operand_offset + 1] = target_address >> 8


def lda_imm(asm: Assembler, value: int) -> None:
    asm.emit(0xA9, value)


def lda_zp(asm: Assembler, address: int) -> None:
    asm.emit(0xA5, address)


def sta_zp(asm: Assembler, address: int) -> None:
    asm.emit(0x85, address)


def lda_abs(asm: Assembler, address: int) -> None:
    asm.emit(0xAD, address & 0xFF, address >> 8)


def sta_abs(asm: Assembler, address: int) -> None:
    asm.emit(0x8D, address & 0xFF, address >> 8)


def write_abs(asm: Assembler, address: int, value: int) -> None:
    lda_imm(asm, value)
    sta_abs(asm, address)


def write_zp(asm: Assembler, address: int, value: int) -> None:
    lda_imm(asm, value)
    sta_zp(asm, address)


def wait_gate(asm: Assembler, address: int, name: str) -> None:
    asm.label(name)
    lda_zp(asm, address)
    asm.branch(0xF0, name)  # BEQ


def configure_tonal_channels(asm: Assembler) -> None:
    # Enable first so timer-high writes load all four length counters.
    write_abs(asm, 0x4015, 0x0F)
    for address, value in (
        (0x4000, 0x3F), (0x4002, 0x08), (0x4003, 0x08),
        (0x4004, 0xBF), (0x4006, 0x0A), (0x4007, 0x08),
        (0x4008, 0xFF), (0x400A, 0x02), (0x400B, 0x08),
        (0x400C, 0x3F), (0x400E, 0x00), (0x400F, 0x08),
    ):
        write_abs(asm, address, value)


def configure_dmc(
    asm: Assembler, *, control: int, length: int, enable_mask: int = 0x1F
) -> None:
    write_abs(asm, 0x4010, control)
    write_abs(asm, 0x4011, 0x40)
    write_abs(asm, 0x4012, 0xC0)  # $F000
    write_abs(asm, 0x4013, length)
    write_abs(asm, 0x4015, 0x0F)  # stop/ack any old DMC transaction
    write_abs(asm, 0x4015, enable_mask)


def build_game_a() -> tuple[bytes, dict[str, int]]:
    asm = Assembler()
    asm.emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A)  # SEI; CLD; LDX #$FF; TXS
    write_abs(asm, 0x2000, 0x00)
    write_abs(asm, 0x4017, 0x40)
    write_abs(asm, 0x4015, 0x00)
    write_zp(asm, 0x00, 0x5A)

    # Five live channels, a controller transaction, and OAM/DMC overlap.
    configure_tonal_channels(asm)
    configure_dmc(asm, control=0x4F, length=0x01)
    write_abs(asm, 0x4016, 0x01)
    write_abs(asm, 0x4016, 0x00)
    lda_abs(asm, 0x4016)
    sta_zp(asm, 0x02)
    write_abs(asm, 0x4014, 0x02)
    asm.emit(0xA2, 0x00)  # LDX #0
    asm.label("warm_loop")
    asm.emit(0xE6, 0x01, 0xCA)  # INC $01; DEX
    asm.branch(0xD0, "warm_loop")
    # A second transfer starts after the DMC output unit has begun consuming
    # buffered bytes, guaranteeing at least one refill collision.
    write_abs(asm, 0x4014, 0x02)
    lda_abs(asm, 0x4017)  # Direction-sensitive Controller 2 read.
    sta_zp(asm, 0x03)

    # DMC-only IRQ: prove it remains pending while I=1, then take it after
    # CLI's documented old-I boundary and acknowledge it with $4015 write.
    asm.emit(0x78)  # SEI
    configure_dmc(asm, control=0x8F, length=0x00)
    asm.label("wait_dmc_irq")
    lda_abs(asm, 0x4015)
    asm.branch(0x10, "wait_dmc_irq")  # BPL
    sta_zp(asm, 0x10)
    write_zp(asm, 0x30, 0x01)
    asm.emit(0x58, 0xEA)  # CLI; NOP (old-I poll delay)
    write_zp(asm, 0x12, 0xD2)

    # Frame-only IRQ.  The testbench opens the gate only after the real frame
    # latch is pending, making the masked/pending condition deterministic.
    asm.emit(0x78)
    write_abs(asm, 0x4017, 0x00)
    configure_dmc(asm, control=0x4F, length=0x01)
    write_zp(asm, 0x30, 0x02)
    wait_gate(asm, 0x70, "wait_frame_gate")
    write_zp(asm, 0x13, 0xF0)
    asm.emit(0x58, 0xEA)
    write_zp(asm, 0x16, 0xF2)

    # Both sources, frame-read first.  $4015 read clears frame while DMC keeps
    # the level asserted; the subsequent write clears DMC.
    asm.emit(0x78)
    write_abs(asm, 0x4017, 0x00)
    configure_dmc(asm, control=0x8F, length=0x00)
    write_zp(asm, 0x30, 0x03)
    wait_gate(asm, 0x71, "wait_both_read_gate")
    asm.emit(0x58, 0xEA)
    write_zp(asm, 0x19, 0xB2)

    # Both sources, DMC-write first.  The frame source keeps IRQ asserted
    # until the handler's later status read.
    asm.emit(0x78)
    write_abs(asm, 0x4017, 0x00)
    configure_dmc(asm, control=0x8F, length=0x00)
    write_zp(asm, 0x30, 0x04)
    wait_gate(asm, 0x72, "wait_both_write_gate")
    asm.emit(0x58, 0xEA)
    write_zp(asm, 0x1C, 0xC2)

    # IRQ is already pending when real PPU NMI is enabled.  NMI must win,
    # RTI must restore I=1, and the still-level IRQ is taken only after CLI.
    asm.emit(0x78)
    write_abs(asm, 0x4017, 0x00)
    write_zp(asm, 0x30, 0x05)
    wait_gate(asm, 0x73, "wait_nmi_irq_gate")
    write_abs(asm, 0x2000, 0x80)
    asm.label("wait_nmi_handler")
    lda_zp(asm, 0x31)
    asm.branch(0xF0, "wait_nmi_handler")
    write_zp(asm, 0x1E, 0xA2)
    asm.emit(0x58, 0xEA)
    write_zp(asm, 0x20, 0xA4)
    write_abs(asm, 0x2000, 0x00)

    # BRK shares the IRQ vector but pushes B=1 and returns after its padding
    # byte.  Hardware IRQ paths above push B=0.
    asm.emit(0x78)
    write_abs(asm, 0x4017, 0x40)
    write_abs(asm, 0x4015, 0x0F)
    write_zp(asm, 0x30, 0x06)
    asm.emit(0x00, 0xEA)  # BRK and padding
    write_zp(asm, 0x23, 0xB2)

    # Leave the frame source asserted across one RTI.  With the restored I=0
    # it must vector a second time before the interrupted program resumes.
    asm.emit(0x78)
    write_abs(asm, 0x4017, 0x00)
    write_zp(asm, 0x24, 0x00)
    write_zp(asm, 0x30, 0x07)
    wait_gate(asm, 0x74, "wait_reassert_gate")
    asm.emit(0x58, 0xEA)
    write_zp(asm, 0x26, 0xE2)

    # Finish with pending DMC IRQ plus active OAM DMA.  Runtime replacement
    # begins in this state and must synchronously clear every source/master.
    asm.emit(0x78)
    configure_dmc(asm, control=0x8F, length=0x00)
    write_abs(asm, 0x4014, 0x02)
    asm.label("replacement_wait")
    lda_abs(asm, 0x4016)
    sta_zp(asm, 0x02)
    asm.emit(0x4C, asm.labels["replacement_wait"] & 0xFF,
             asm.labels["replacement_wait"] >> 8)

    asm.pad_to(IRQ_HANDLER)
    asm.label("irq_handler")
    asm.emit(0xBA, 0xBD, 0x01, 0x01)  # TSX; LDA $0101,X (pushed P)
    sta_zp(asm, 0x3E)
    asm.emit(0x29, 0x10)  # AND #B
    asm.branch(0xF0, "hardware_dispatch")
    lda_zp(asm, 0x3E)
    sta_zp(asm, 0x22)
    write_zp(asm, 0x21, 0xB1)
    asm.emit(0x40)

    asm.label("hardware_dispatch")
    lda_zp(asm, 0x30)
    for index, (stage, target) in enumerate((
        (1, "handle_dmc"), (2, "handle_frame"),
        (3, "handle_both_read"), (4, "handle_both_write"),
        (5, "handle_irq_after_nmi"), (7, "handle_reassert"),
    )):
        next_test = f"dispatch_next_{index}"
        asm.emit(0xC9, stage)
        asm.branch(0xD0, next_test)
        asm.jump(target)
        asm.label(next_test)
    asm.emit(0x40)  # defensive RTI

    asm.label("handle_dmc")
    lda_abs(asm, 0x4015)
    sta_zp(asm, 0x10)
    write_abs(asm, 0x4015, 0x0F)
    write_zp(asm, 0x11, 0xD1)
    asm.emit(0x40)

    asm.label("handle_frame")
    lda_abs(asm, 0x4015)
    sta_zp(asm, 0x14)
    write_abs(asm, 0x4017, 0x40)
    write_zp(asm, 0x15, 0xF1)
    # Long enough that a fast looping DMC in extended runs can steal slots
    # while the CPU is genuinely inside the handler.
    asm.emit(*([0xEA] * 256))
    asm.emit(0x40)

    asm.label("handle_both_read")
    lda_abs(asm, 0x4015)
    sta_zp(asm, 0x17)
    asm.emit(0xEA, 0xEA)
    write_abs(asm, 0x4015, 0x0F)
    write_abs(asm, 0x4017, 0x40)
    write_zp(asm, 0x18, 0xB1)
    asm.emit(0x40)

    asm.label("handle_both_write")
    write_abs(asm, 0x4015, 0x0F)
    asm.emit(0xEA, 0xEA)
    lda_abs(asm, 0x4015)
    sta_zp(asm, 0x1A)
    write_abs(asm, 0x4017, 0x40)
    write_zp(asm, 0x1B, 0xC1)
    asm.emit(0x40)

    asm.label("handle_irq_after_nmi")
    lda_abs(asm, 0x4015)
    sta_zp(asm, 0x1F)
    write_abs(asm, 0x4017, 0x40)
    write_zp(asm, 0x1F, 0xA3)
    asm.emit(0x40)

    asm.label("handle_reassert")
    asm.emit(0xE6, 0x24)  # INC $24
    lda_zp(asm, 0x24)
    asm.emit(0xC9, 0x02)
    asm.branch(0xF0, "handle_reassert_ack")
    asm.emit(0x40)
    asm.label("handle_reassert_ack")
    lda_abs(asm, 0x4015)
    write_abs(asm, 0x4017, 0x40)
    write_zp(asm, 0x25, 0xE1)
    asm.emit(0x40)

    asm.pad_to(NMI_HANDLER)
    asm.label("nmi_handler")
    asm.emit(0xE6, 0x31)  # INC $31
    write_zp(asm, 0x1D, 0xA1)
    asm.emit(0x40)
    asm.resolve()

    prg = bytearray([0xEA] * PRG_SIZE)
    prg[: len(asm.data)] = asm.data
    sample_offset = SAMPLE & 0x3FFF
    for index in range(256):
        prg[sample_offset + index] = (index * 37 + 0x53) & 0xFF
    for offset, vector in ((0x3FFA, NMI_HANDLER), (0x3FFC, RESET),
                           (0x3FFE, IRQ_HANDLER)):
        prg[offset] = vector & 0xFF
        prg[offset + 1] = vector >> 8
    return bytes(prg), asm.labels


def build_game_b() -> bytes:
    prg = bytearray([0xEA] * PRG_SIZE)
    program = bytes(
        (
            0x78,                         # SEI
            0xD8,                         # CLD
            0xA2, 0xFF, 0x9A,             # LDX #$FF; TXS
            0xA9, 0x00, 0x8D, 0x15, 0x40, # LDA #0; STA $4015
            0xA9, 0x40, 0x8D, 0x17, 0x40, # inhibit frame IRQ
            0xA9, 0x99, 0x85, 0x2F,       # replacement signature
            0x4C, 0x13, 0x80,             # JMP $8013
        )
    )
    prg[: len(program)] = program
    for offset in (0x3FFA, 0x3FFC, 0x3FFE):
        prg[offset] = RESET & 0xFF
        prg[offset + 1] = RESET >> 8
    return bytes(prg)


def ines(prg: bytes) -> bytes:
    if len(prg) != PRG_SIZE:
        raise ValueError("Phase 5I images must be NROM-128")
    header = b"NES\x1a" + bytes((1, 0, 0, 0)) + bytes(8)
    return header + prg


def write_outputs(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    game_a, labels = build_game_a()
    game_b = build_game_b()
    for stem, prg in (("phase5i_game_a", game_a), ("phase5i_game_b", game_b)):
        (output_dir / f"{stem}.prg.hex").write_text(
            "".join(f"{byte:02x}\n" for byte in prg), encoding="ascii"
        )
        (output_dir / f"{stem}.nes").write_bytes(ines(prg))
    lines = [
        f"game_a_crc32={binascii.crc32(game_a):08x}",
        f"game_b_crc32={binascii.crc32(game_b):08x}",
        *(f"{name}={address:04x}" for name, address in sorted(labels.items())),
    ]
    (output_dir / "phase5i_rom_reference.txt").write_text(
        "\n".join(lines) + "\n", encoding="ascii"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("build/sim"))
    args = parser.parse_args()
    write_outputs(args.output_dir)


if __name__ == "__main__":
    main()
