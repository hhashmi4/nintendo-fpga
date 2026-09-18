#!/usr/bin/env python3
"""Generate the synthesizable Phase 2K CPU board-diagnostic ROM image."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "rtl" / "diagnostic" / "cpu_board_diag_program.svh"

START = 0x8000
ROM_END = 0x83FF
SUBROUTINE = 0x8380
IRQ_HANDLER = 0x83A0
NMI_HANDLER = 0x83B0
FAIL_COMMON = 0x83D0
PASS_LOOP = 0x83F0

RESULT = 0x6000
IRQ_CONTROL = 0x6001
NMI_CONTROL = 0x6002
STALL_CONTROL = 0x6003


@dataclass(frozen=True)
class Fixup:
    operand_address: int
    label: str
    relative: bool


class Program:
    def __init__(self, origin: int) -> None:
        self.pc = origin
        self.memory: dict[int, int] = {}
        self.comments: dict[int, str] = {}
        self.labels: dict[str, int] = {}
        self.fixups: list[Fixup] = []

    def org(self, address: int) -> None:
        if address < self.pc:
            raise ValueError(f"cannot move origin backwards: {address:04X} < {self.pc:04X}")
        self.pc = address

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label {name}")
        self.labels[name] = self.pc

    def emit(self, *values: int, comment: str = "") -> None:
        start = self.pc
        for value in values:
            if not 0 <= value <= 0xFF:
                raise ValueError(f"byte out of range: {value}")
            if self.pc in self.memory:
                raise ValueError(f"overlap at {self.pc:04X}")
            self.memory[self.pc] = value
            self.pc += 1
        if comment:
            self.comments[start] = comment

    def implied(self, opcode: int, mnemonic: str) -> None:
        self.emit(opcode, comment=mnemonic)

    def immediate(self, opcode: int, value: int, mnemonic: str) -> None:
        self.emit(opcode, value, comment=f"{mnemonic} #${value:02X}")

    def zp(self, opcode: int, address: int, mnemonic: str) -> None:
        self.emit(opcode, address, comment=f"{mnemonic} ${address:02X}")

    def absolute(self, opcode: int, address: int, mnemonic: str) -> None:
        self.emit(opcode, address & 0xFF, address >> 8,
                  comment=f"{mnemonic} ${address:04X}")

    def absolute_label(self, opcode: int, label: str, mnemonic: str) -> None:
        start = self.pc
        self.emit(opcode, 0, 0, comment=f"{mnemonic} {label}")
        self.fixups.append(Fixup(start + 1, label, False))

    def branch(self, opcode: int, label: str, mnemonic: str) -> None:
        start = self.pc
        self.emit(opcode, 0, comment=f"{mnemonic} {label}")
        self.fixups.append(Fixup(start + 1, label, True))

    def resolve(self) -> None:
        for fixup in self.fixups:
            target = self.labels[fixup.label]
            if fixup.relative:
                displacement = target - (fixup.operand_address + 1)
                if not -128 <= displacement <= 127:
                    raise ValueError(
                        f"branch to {fixup.label} out of range: {displacement}"
                    )
                self.memory[fixup.operand_address] = displacement & 0xFF
            else:
                self.memory[fixup.operand_address] = target & 0xFF
                self.memory[fixup.operand_address + 1] = target >> 8


def build_program() -> Program:
    p = Program(START)
    serial = 0

    def unique(prefix: str) -> str:
        nonlocal serial
        serial += 1
        return f"{prefix}_{serial}"

    def fail(code: int) -> None:
        p.immediate(0xA9, code, "LDA")
        p.absolute_label(0x4C, "fail_common", "JMP")

    def expect_equal(value: int, code: int) -> None:
        ok = unique("equal_ok")
        p.immediate(0xC9, value, "CMP")
        p.branch(0xF0, ok, "BEQ")
        fail(code)
        p.label(ok)

    def expect_taken(opcode: int, mnemonic: str, code: int) -> None:
        ok = unique("taken_ok")
        p.branch(opcode, ok, mnemonic)
        fail(code)
        p.label(ok)

    def expect_not_taken(opcode: int, mnemonic: str, code: int) -> None:
        bad = unique("not_taken_bad")
        ok = unique("not_taken_ok")
        p.branch(opcode, bad, mnemonic)
        p.absolute_label(0x4C, ok, "JMP")
        p.label(bad)
        fail(code)
        p.label(ok)

    # Deterministic state and interrupt counters.
    p.implied(0x78, "SEI")
    p.implied(0xD8, "CLD")
    p.immediate(0xA9, 0x00, "LDA")
    p.zp(0x85, 0x10, "STA")
    p.zp(0x85, 0x11, "STA")

    # Immediate loads and all register transfers.
    p.immediate(0xA9, 0x3C, "LDA")
    p.implied(0xAA, "TAX")
    p.implied(0x8A, "TXA")
    expect_equal(0x3C, 0x01)
    p.implied(0xA8, "TAY")
    p.implied(0x98, "TYA")
    expect_equal(0x3C, 0x01)
    p.immediate(0xA2, 0xD0, "LDX")
    p.implied(0x9A, "TXS")
    p.implied(0xBA, "TSX")
    p.implied(0x8A, "TXA")
    expect_equal(0xD0, 0x01)
    p.immediate(0xA0, 0x52, "LDY")
    p.immediate(0xC0, 0x52, "CPY")
    expect_taken(0xF0, "BEQ", 0x01)
    p.immediate(0xE0, 0xD0, "CPX")
    expect_taken(0xF0, "BEQ", 0x01)

    # Zero-page, absolute, indexed, and representative page-crossing access.
    p.immediate(0xA9, 0x55, "LDA")
    p.zp(0x85, 0x20, "STA")
    p.zp(0xA5, 0x20, "LDA")
    expect_equal(0x55, 0x01)
    p.immediate(0xA9, 0xA6, "LDA")
    p.absolute(0x8D, 0x0400, "STA")
    p.absolute(0xAD, 0x0400, "LDA")
    expect_equal(0xA6, 0x01)
    p.immediate(0xA2, 0x01, "LDX")
    p.immediate(0xA9, 0x69, "LDA")
    p.zp(0x95, 0x20, "STA")
    p.zp(0xB5, 0x20, "LDA")
    expect_equal(0x69, 0x01)
    p.immediate(0xA9, 0x77, "LDA")
    p.absolute(0x9D, 0x04FF, "STA")
    p.absolute(0xBD, 0x04FF, "LDA")
    expect_equal(0x77, 0x0B)

    # Binary-only arithmetic, including proof that SED does not enable BCD.
    p.implied(0x18, "CLC")
    p.immediate(0xA9, 0x10, "LDA")
    p.immediate(0x69, 0x22, "ADC")
    expect_equal(0x32, 0x02)
    p.implied(0x38, "SEC")
    p.immediate(0xE9, 0x12, "SBC")
    expect_equal(0x20, 0x02)
    p.implied(0xF8, "SED")
    p.implied(0x18, "CLC")
    p.immediate(0xA9, 0x09, "LDA")
    p.immediate(0x69, 0x01, "ADC")
    expect_equal(0x0A, 0x02)
    p.implied(0xD8, "CLD")

    # Logic, compare, BIT, and N/V/Z branch status behavior.
    p.immediate(0xA9, 0xF0, "LDA")
    p.immediate(0x29, 0x3C, "AND")
    p.immediate(0x09, 0x03, "ORA")
    p.immediate(0x49, 0xFF, "EOR")
    expect_equal(0xCC, 0x03)
    p.immediate(0xA9, 0xC0, "LDA")
    p.zp(0x85, 0x22, "STA")
    p.immediate(0xA9, 0x40, "LDA")
    p.zp(0x24, 0x22, "BIT")
    expect_taken(0xD0, "BNE", 0x03)
    expect_taken(0x30, "BMI", 0x03)
    expect_taken(0x70, "BVS", 0x03)
    p.implied(0xB8, "CLV")
    expect_taken(0x50, "BVC", 0x03)

    # Register and memory increments/decrements plus all four shifts/rotates.
    p.immediate(0xA2, 0x00, "LDX")
    p.implied(0xE8, "INX")
    p.implied(0xCA, "DEX")
    p.immediate(0xE0, 0x00, "CPX")
    expect_taken(0xF0, "BEQ", 0x04)
    p.immediate(0xA0, 0x02, "LDY")
    p.implied(0x88, "DEY")
    p.implied(0xC8, "INY")
    p.immediate(0xC0, 0x02, "CPY")
    expect_taken(0xF0, "BEQ", 0x04)
    p.immediate(0xA9, 0x7F, "LDA")
    p.zp(0x85, 0x23, "STA")
    p.zp(0xE6, 0x23, "INC")
    p.zp(0xA5, 0x23, "LDA")
    expect_equal(0x80, 0x04)
    p.zp(0xC6, 0x23, "DEC")
    p.zp(0xA5, 0x23, "LDA")
    expect_equal(0x7F, 0x04)
    p.immediate(0xA9, 0x81, "LDA")
    p.implied(0x0A, "ASL A")
    p.implied(0x2A, "ROL A")
    p.implied(0x4A, "LSR A")
    p.implied(0x6A, "ROR A")
    expect_equal(0x81, 0x04)

    # Explicit taken and not-taken branch paths.
    p.implied(0x18, "CLC")
    expect_taken(0x90, "BCC", 0x05)
    p.implied(0x38, "SEC")
    expect_not_taken(0x90, "BCC", 0x05)
    expect_taken(0xB0, "BCS", 0x05)

    # Stack data and status round trips.
    p.immediate(0xA2, 0xD0, "LDX")
    p.implied(0x9A, "TXS")
    p.immediate(0xA9, 0x5A, "LDA")
    p.implied(0x48, "PHA")
    p.immediate(0xA9, 0x00, "LDA")
    p.implied(0x68, "PLA")
    expect_equal(0x5A, 0x06)
    p.implied(0x38, "SEC")
    p.implied(0xF8, "SED")
    p.implied(0x08, "PHP")
    p.implied(0x18, "CLC")
    p.implied(0xD8, "CLD")
    p.implied(0x28, "PLP")
    expect_taken(0xB0, "BCS", 0x06)
    p.implied(0x18, "CLC")
    p.immediate(0xA9, 0x09, "LDA")
    p.immediate(0x69, 0x01, "ADC")
    expect_equal(0x0A, 0x06)
    p.implied(0xD8, "CLD")

    # JSR/RTS and an absolute JMP that skips an immediate failure path.
    p.immediate(0xA9, 0x10, "LDA")
    p.absolute_label(0x20, "subroutine", "JSR")
    expect_equal(0x15, 0x07)
    jmp_ok = unique("jmp_ok")
    p.absolute_label(0x4C, jmp_ok, "JMP")
    fail(0x07)
    p.label(jmp_ok)

    # BRK/RTI, hardware IRQ, hardware NMI, and the real cpu_enable stall.
    p.emit(0x00, 0xEA, comment="BRK / padding")
    p.zp(0xA5, 0x10, "LDA")
    expect_equal(0x01, 0x08)
    p.implied(0x58, "CLI")
    p.immediate(0xA9, 0x5A, "LDA")
    p.absolute(0x8D, IRQ_CONTROL, "STA")
    p.implied(0xEA, "NOP")
    p.zp(0xA5, 0x10, "LDA")
    expect_equal(0x02, 0x09)
    p.implied(0x78, "SEI")
    p.immediate(0xA9, 0x5A, "LDA")
    p.absolute(0x8D, NMI_CONTROL, "STA")
    p.implied(0xEA, "NOP")
    p.zp(0xA5, 0x11, "LDA")
    expect_equal(0x01, 0x0A)
    p.immediate(0xA9, 0x5A, "LDA")
    p.absolute(0x8D, STALL_CONTROL, "STA")
    p.absolute(0xAD, STALL_CONTROL, "LDA")
    expect_equal(0xA5, 0x0C)

    # Signature is accepted only after hardware prerequisites and observation
    # of the actual stable pass loop.
    p.immediate(0xA9, 0xA5, "LDA")
    p.absolute(0x8D, RESULT, "STA")
    p.absolute_label(0x4C, "pass_loop", "JMP")

    if p.pc > SUBROUTINE:
        raise ValueError(f"main program overruns subroutine slot: {p.pc:04X}")

    p.org(SUBROUTINE)
    p.label("subroutine")
    p.implied(0x18, "CLC")
    p.immediate(0x69, 0x05, "ADC")
    p.implied(0x60, "RTS")

    p.org(IRQ_HANDLER)
    p.label("irq_handler")
    p.implied(0x48, "PHA")
    p.immediate(0xA9, 0xA5, "LDA")
    p.absolute(0x8D, IRQ_CONTROL, "STA")
    p.zp(0xE6, 0x10, "INC")
    p.implied(0x68, "PLA")
    p.implied(0x40, "RTI")

    p.org(NMI_HANDLER)
    p.label("nmi_handler")
    p.implied(0x48, "PHA")
    p.zp(0xE6, 0x11, "INC")
    p.implied(0x68, "PLA")
    p.implied(0x40, "RTI")

    p.org(FAIL_COMMON)
    p.label("fail_common")
    p.absolute(0x8D, RESULT, "STA")
    p.label("fail_loop")
    p.absolute_label(0x4C, "fail_loop", "JMP")

    p.org(PASS_LOOP)
    p.label("pass_loop")
    p.absolute_label(0x4C, "pass_loop", "JMP")

    p.resolve()
    assert p.labels["subroutine"] == SUBROUTINE
    assert p.labels["irq_handler"] == IRQ_HANDLER
    assert p.labels["nmi_handler"] == NMI_HANDLER
    assert p.labels["fail_common"] == FAIL_COMMON
    assert p.labels["pass_loop"] == PASS_LOOP
    assert min(p.memory) == START and max(p.memory) <= ROM_END
    return p


def render(program: Program) -> str:
    lines = [
        "// Generated by scripts/generate_cpu_board_diag_program.py.",
        "// Do not edit by hand; run the generator and commit the result.",
        "initial begin",
        "    for (int unsigned index = 0; index < 1024; index++) begin",
        "        program_rom[index] = 8'hEA;",
        "    end",
    ]
    for address in sorted(program.memory):
        comment = program.comments.get(address)
        if comment:
            lines.append(f"    // {address:04X}: {comment}")
        lines.append(
            f"    program_rom[10'h{address - START:03X}] = "
            f"8'h{program.memory[address]:02X};"
        )
    lines.append("end")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true",
        help="fail if the committed generated include is stale",
    )
    args = parser.parse_args()
    rendered = render(build_program())
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="ascii") != rendered:
            raise SystemExit(f"{OUTPUT.relative_to(ROOT)} is stale; regenerate it")
        return 0
    OUTPUT.write_text(rendered, encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
