#!/usr/bin/env python3
"""Generate project-owned deterministic Mapper 0 cartridges and artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ines import (  # noqa: E402
    CHR_BANK_SIZE,
    PRG_BANK_SIZE,
    convert_ines,
)


class Program:
    def __init__(self, origin: int) -> None:
        self.origin = origin
        self.data = bytearray()
        self.labels: dict[str, int] = {}
        self.absolute_fixups: list[tuple[int, str]] = []
        self.relative_fixups: list[tuple[int, str]] = []

    @property
    def pc(self) -> int:
        return self.origin + len(self.data)

    def emit(self, *values: int) -> None:
        self.data.extend(value & 0xFF for value in values)

    def label(self, name: str) -> None:
        self.labels[name] = self.pc

    def absolute(self, opcode: int, label: str) -> None:
        self.emit(opcode, 0, 0)
        self.absolute_fixups.append((len(self.data) - 2, label))

    def branch(self, opcode: int, label: str) -> None:
        self.emit(opcode, 0)
        self.relative_fixups.append((len(self.data) - 1, label))

    def resolve(self) -> bytes:
        for offset, label in self.absolute_fixups:
            address = self.labels[label]
            self.data[offset] = address & 0xFF
            self.data[offset + 1] = address >> 8
        for offset, label in self.relative_fixups:
            operand_address = self.origin + offset
            displacement = self.labels[label] - (operand_address + 1)
            if not -128 <= displacement <= 127:
                raise ValueError(f"branch to {label} is out of range")
            self.data[offset] = displacement & 0xFF
        return bytes(self.data)


def put(prg: bytearray, cpu_address: int, values: bytes) -> None:
    index = cpu_address - 0x8000
    if len(prg) == PRG_BANK_SIZE:
        index &= 0x3FFF
    prg[index : index + len(values)] = values


def set_vectors(
    prg: bytearray, *, nmi: int, reset: int, irq: int
) -> None:
    for cpu_address, vector in ((0xFFFA, nmi), (0xFFFC, reset), (0xFFFE, irq)):
        index = cpu_address - 0x8000
        if len(prg) == PRG_BANK_SIZE:
            index &= 0x3FFF
        prg[index] = vector & 0xFF
        prg[index + 1] = vector >> 8


def pattern_chr() -> bytes:
    data = bytearray(CHR_BANK_SIZE)
    for row in range(8):
        data[0x10 + row] = 0xAA if row & 1 else 0x55
        data[0x20 + row] = 0xFF if row in (0, 7) else 0x81
        data[0x28 + row] = 0x18 if row in (2, 5) else 0x00
        data[0x30 + row] = 1 << row
    return bytes(data)


def boot_prg() -> bytes:
    prg = bytearray([0xEA] * PRG_BANK_SIZE)
    reset = Program(0x8000)
    reset.emit(0x78, 0xD8)  # SEI; CLD
    reset.emit(0xA2, 0xFF, 0x9A)  # LDX #$ff; TXS
    reset.emit(0xA9, 0x4B, 0x85, 0x02)  # recognizable CPU RAM write
    reset.emit(0xA9, 0x80, 0x8D, 0x00, 0x20)  # PPUCTRL
    reset.emit(0xA9, 0x00, 0x8D, 0x01, 0x20)  # rendering off
    reset.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x0F, 0x8D, 0x07, 0x20)
    reset.emit(0xA9, 0x21, 0x8D, 0x07, 0x20)
    reset.emit(0xA9, 0x20, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x01, 0x8D, 0x07, 0x20)  # tile 1 at $2000
    reset.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20)
    reset.emit(0xA9, 0x1E, 0x8D, 0x01, 0x20)  # enable rendering
    reset.emit(0xA9, 0x5A, 0x85, 0x03)
    reset.label("loop")
    reset.absolute(0x4C, "loop")
    put(prg, 0x8000, reset.resolve())
    put(prg, 0x9000, bytes((0xE6, 0x04, 0x40)))  # INC $04; RTI
    put(prg, 0x9100, bytes((0xE6, 0x05, 0x40)))  # INC $05; RTI
    set_vectors(prg, nmi=0x9000, reset=0x8000, irq=0x9100)
    return bytes(prg)


def display_prg() -> bytes:
    prg = bytearray([0xEA] * PRG_BANK_SIZE)
    program = Program(0x8000)
    program.emit(0x78, 0xD8)  # SEI; CLD
    program.emit(0xA9, 0x00, 0x8D, 0x00, 0x20)  # disable NMI
    program.emit(0x8D, 0x01, 0x20)  # disable rendering
    program.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    program.emit(0xA2, 0x00)
    program.label("palette")
    program.emit(0xBD, 0x00, 0x81)  # LDA $8100,X
    program.emit(0x8D, 0x07, 0x20, 0xE8, 0xE0, 0x20)
    program.branch(0xD0, "palette")
    program.emit(0xA9, 0x20, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    program.emit(0xA0, 0x04, 0xA2, 0x00, 0xA9, 0x01)
    program.label("nametable")
    program.emit(0x8D, 0x07, 0x20, 0xE8)
    program.branch(0xD0, "nametable")
    program.emit(0x88)
    program.branch(0xD0, "nametable")
    program.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20)
    program.emit(0x8D, 0x00, 0x20)
    program.emit(0xA9, 0x0A, 0x8D, 0x01, 0x20)
    program.label("loop")
    program.absolute(0x4C, "loop")
    put(prg, 0x8000, program.resolve())
    palette = bytes(
        (0x0F, 0x01, 0x21, 0x31) * 4 + (0x0F, 0x06, 0x16, 0x26) * 4
    )
    put(prg, 0x8100, palette)
    set_vectors(prg, nmi=0x8000, reset=0x8000, irq=0x8000)
    return bytes(prg)


def emit_controller_poll(program: Program) -> None:
    """Poll both ports into $10/$11 in NES A-to-Right bit order."""

    program.emit(0xA9, 0x01, 0x8D, 0x16, 0x40)  # LDA #1; STA $4016
    program.emit(0xA9, 0x00, 0x8D, 0x16, 0x40)  # LDA #0; STA $4016

    program.emit(0xA2, 0x08, 0xA9, 0x00, 0x85, 0x10)  # X=8; result1=0
    program.label("controller1_poll")
    program.emit(0xAD, 0x16, 0x40)  # LDA $4016
    program.emit(0x4A, 0x66, 0x10, 0xCA)  # LSR A; ROR $10; DEX
    program.branch(0xD0, "controller1_poll")

    program.emit(0xA2, 0x08, 0xA9, 0x00, 0x85, 0x11)  # X=8; result2=0
    program.label("controller2_poll")
    program.emit(0xAD, 0x17, 0x40)  # LDA $4017
    program.emit(0x4A, 0x66, 0x11, 0xCA)  # LSR A; ROR $11; DEX
    program.branch(0xD0, "controller2_poll")


def controller_poll_prg() -> bytes:
    """Owned test program proving controller input -> bus -> CPU RAM."""

    prg = bytearray([0xEA] * PRG_BANK_SIZE)
    program = Program(0x8000)
    program.emit(0x78, 0xD8)  # SEI; CLD
    program.emit(0xA2, 0xFF, 0x9A)  # LDX #$ff; TXS
    program.label("poll_loop")
    emit_controller_poll(program)
    program.emit(0xE6, 0x12)  # INC $12 poll counter
    program.absolute(0x4C, "poll_loop")
    put(prg, 0x8000, program.resolve())
    set_vectors(prg, nmi=0x8000, reset=0x8000, irq=0x8000)
    return bytes(prg)


def controller_display_prg() -> bytes:
    """Board image: display pattern and color it from Controller 1 polls."""

    prg = bytearray([0xEA] * PRG_BANK_SIZE)
    program = Program(0x8000)
    program.emit(0x78, 0xD8)  # SEI; CLD
    program.emit(0xA9, 0x00, 0x8D, 0x00, 0x20)  # disable NMI
    program.emit(0x8D, 0x01, 0x20)  # disable rendering
    program.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    program.emit(0xA2, 0x00)
    program.label("palette")
    program.emit(0xBD, 0x00, 0x81)  # LDA $8100,X
    program.emit(0x8D, 0x07, 0x20, 0xE8, 0xE0, 0x20)
    program.branch(0xD0, "palette")
    program.emit(0xA9, 0x20, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    program.emit(0xA0, 0x04, 0xA2, 0x00, 0xA9, 0x01)
    program.label("nametable")
    program.emit(0x8D, 0x07, 0x20, 0xE8)
    program.branch(0xD0, "nametable")
    program.emit(0x88)
    program.branch(0xD0, "nametable")
    program.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20)
    program.emit(0x8D, 0x00, 0x20)
    program.emit(0xA9, 0x0A, 0x8D, 0x01, 0x20)

    program.label("poll_loop")
    emit_controller_poll(program)
    program.emit(0xE6, 0x12)  # INC $12 poll counter
    program.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x01, 0x8D, 0x06, 0x20)  # PPU address $3f01
    program.emit(0xA5, 0x10)  # LDA Controller 1 result
    program.branch(0xF0, "no_buttons")  # BEQ
    program.emit(0xA9, 0x21)  # visible blue when any button is pressed
    program.branch(0xD0, "color_ready")  # unconditional because A != 0
    program.label("no_buttons")
    program.emit(0xA9, 0x0F)  # black when no buttons are pressed
    program.label("color_ready")
    program.emit(0x8D, 0x07, 0x20)  # STA PPUDATA
    program.absolute(0x4C, "poll_loop")

    put(prg, 0x8000, program.resolve())
    palette = bytes(
        (0x0F, 0x01, 0x21, 0x31) * 4 + (0x0F, 0x06, 0x16, 0x26) * 4
    )
    put(prg, 0x8100, palette)
    set_vectors(prg, nmi=0x8000, reset=0x8000, irq=0x8000)
    return bytes(prg)


def mapping_prg(size: int) -> bytes:
    data = bytearray(
        ((index * 37) ^ (index >> 8) ^ 0xA5) & 0xFF
        for index in range(size)
    )
    set_vectors(data, nmi=0x9234, reset=0x8123, irq=0xABCD)
    return bytes(data)


def make_ines(prg: bytes, chr_data: bytes, *, vertical: bool) -> bytes:
    header = bytearray(b"NES\x1a")
    header.extend((len(prg) // PRG_BANK_SIZE, len(chr_data) // CHR_BANK_SIZE))
    header.extend((0x01 if vertical else 0x00, 0x00, 0x01, 0x00))
    header.extend(b"\x00" * 6)
    return bytes(header) + prg + chr_data


def write_fixture(
    output_dir: Path,
    name: str,
    prg: bytes,
    chr_data: bytes,
    *,
    vertical: bool,
) -> None:
    nes_path = output_dir / f"{name}.nes"
    nes_path.write_bytes(make_ines(prg, chr_data, vertical=vertical))
    artifacts = convert_ines(nes_path, output_dir / name)
    print(f"{name}: {nes_path} ({', '.join(sorted(artifacts))})")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT_DIRECTORY")
    output_dir = Path(sys.argv[1])
    output_dir.mkdir(parents=True, exist_ok=True)
    chr_data = pattern_chr()
    write_fixture(
        output_dir,
        "phase4b_boot_nrom128",
        boot_prg(),
        chr_data,
        vertical=False,
    )
    write_fixture(
        output_dir,
        "phase4b_display_nrom128",
        display_prg(),
        chr_data,
        vertical=True,
    )
    write_fixture(
        output_dir,
        "phase4b_map_nrom128",
        mapping_prg(PRG_BANK_SIZE),
        chr_data,
        vertical=False,
    )
    write_fixture(
        output_dir,
        "phase4b_map_nrom256",
        mapping_prg(2 * PRG_BANK_SIZE),
        chr_data,
        vertical=True,
    )
    write_fixture(
        output_dir,
        "phase4b_chrram_nrom128",
        boot_prg(),
        b"",
        vertical=False,
    )
    write_fixture(
        output_dir,
        "phase4c_controller_nrom128",
        controller_poll_prg(),
        chr_data,
        vertical=False,
    )
    write_fixture(
        output_dir,
        "phase4c_controller_display_nrom128",
        controller_display_prg(),
        chr_data,
        vertical=True,
    )


if __name__ == "__main__":
    main()
