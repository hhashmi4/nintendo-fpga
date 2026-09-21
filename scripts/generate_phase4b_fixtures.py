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


def playable_demo_chr() -> bytes:
    """CHR ROM for the project-owned Phase 4D-B playable demo."""

    data = bytearray(CHR_BANK_SIZE)

    # Tile 1: a quiet checkerboard background.
    for row in range(8):
        data[0x10 + row] = 0x44 if row & 1 else 0x11

    # Tile 2: bordered player sprite.
    player = (0x7E, 0x42, 0x5A, 0x5A, 0x42, 0x5A, 0x42, 0x7E)
    for row, value in enumerate(player):
        data[0x20 + row] = value

    # Tile 3: visibly different action sprite selected by the B button.
    action = (0x18, 0x3C, 0x7E, 0xDB, 0xFF, 0x7E, 0x3C, 0x18)
    for row, value in enumerate(action):
        data[0x30 + row] = value
        data[0x38 + row] = value & 0x66

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


def dma_bus_master_prg() -> bytes:
    """Owned program proving RAM, cartridge, and I/O-page OAM DMA."""

    prg = bytearray([0xEA] * PRG_BANK_SIZE)
    program = Program(0x8000)
    program.emit(0x78, 0xD8)  # SEI; CLD
    program.emit(0xA2, 0x00)  # LDX #0
    program.label("fill_source")
    program.emit(0x8A, 0x49, 0x5A)  # TXA; EOR #$5a
    program.emit(0x9D, 0x00, 0x02)  # STA $0200,X
    program.emit(0xE8)  # INX
    program.branch(0xD0, "fill_source")

    # Internal RAM source; execution must resume and write marker $11.
    program.emit(0xA9, 0x00, 0x8D, 0x03, 0x20)  # OAMADDR=0
    program.emit(0xA9, 0x02, 0x8D, 0x14, 0x40)  # DMA page $02
    program.emit(0xA9, 0x11, 0x85, 0x13)

    # This instruction sequence reaches the second trigger on the opposite
    # CPU-cycle parity, covering the alternate 513/514-slot alignment case.
    program.emit(0xA9, 0x00, 0x8D, 0x03, 0x20)
    program.emit(0xA9, 0x80, 0x8D, 0x14, 0x40)  # cartridge page $80
    program.emit(0xA9, 0x22, 0x85, 0x13)

    # Page $40 crosses APU/DMA/controller/unmapped I/O and into cartridge
    # space. Unsupported I/O bytes are deterministic zero and emit no strobes.
    program.emit(0xA9, 0x00, 0x8D, 0x03, 0x20)
    program.emit(0xA9, 0x40, 0x8D, 0x14, 0x40)
    program.emit(0xA9, 0x33, 0x85, 0x13)
    program.label("done")
    program.absolute(0x4C, "done")

    put(prg, 0x8000, program.resolve())
    set_vectors(prg, nmi=0x8000, reset=0x8000, irq=0x8000)
    return bytes(prg)


def playable_demo_prg() -> bytes:
    """Project-owned playable NROM demo using NMI, DMA, and all buttons."""

    prg = bytearray([0xEA] * PRG_BANK_SIZE)
    program = Program(0x8000)

    # Normal NES startup: disable interrupts/rendering, establish the stack,
    # and wait for two VBlanks before touching PPU memory.
    program.emit(0x78, 0xD8)  # SEI; CLD
    program.emit(0xA2, 0xFF, 0x9A)  # LDX #$ff; TXS
    program.emit(0xA9, 0x00, 0x8D, 0x00, 0x20, 0x8D, 0x01, 0x20)
    program.label("wait_vblank_1")
    program.emit(0x2C, 0x02, 0x20)  # BIT $2002
    program.branch(0x10, "wait_vblank_1")  # BPL
    program.label("wait_vblank_2")
    program.emit(0x2C, 0x02, 0x20)
    program.branch(0x10, "wait_vblank_2")

    # Clear all 2 KiB of CPU RAM deterministically.
    program.emit(0xA9, 0x00, 0xA2, 0x00)  # LDA #0; LDX #0
    program.label("clear_ram")
    for page in range(8):
        program.emit(0x9D, 0x00, page)  # STA $xx00,X
    program.emit(0xE8)
    program.branch(0xD0, "clear_ram")

    # Hide every OAM entry, then establish the persistent player state.
    program.emit(0xA9, 0xFF, 0xA2, 0x00)
    program.label("hide_oam")
    program.emit(0x9D, 0x00, 0x02, 0xE8)
    program.branch(0xD0, "hide_oam")
    program.emit(0xA9, 0x78, 0x85, 0x03)  # player X
    program.emit(0xA9, 0x64, 0x85, 0x04)  # player Y after Start
    program.emit(0xA9, 0xF0, 0x8D, 0x00, 0x02)  # hidden title-screen Y
    program.emit(0xA9, 0x02, 0x8D, 0x01, 0x02)  # normal sprite tile
    program.emit(0xA9, 0x00, 0x8D, 0x02, 0x02)
    program.emit(0xA9, 0x78, 0x8D, 0x03, 0x02)

    # Load all 32 palette bytes from PRG ROM.
    program.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    program.emit(0xA2, 0x00)
    program.label("load_palette")
    program.emit(0xBD, 0x00, 0x82, 0x8D, 0x07, 0x20, 0xE8, 0xE0, 0x20)
    program.branch(0xD0, "load_palette")

    # Fill one complete nametable. The final 64 bytes are deterministic
    # attribute values too, so the background visibly exercises composition.
    program.emit(0xA9, 0x20, 0x8D, 0x06, 0x20)
    program.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    program.emit(0xA0, 0x04, 0xA2, 0x00, 0xA9, 0x01)
    program.label("fill_nametable")
    program.emit(0x8D, 0x07, 0x20, 0xE8)
    program.branch(0xD0, "fill_nametable")
    program.emit(0x88)
    program.branch(0xD0, "fill_nametable")

    # Zero scroll, enable VBlank NMI, and enable background/sprite rendering.
    program.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20)
    program.emit(0xA9, 0x80, 0x8D, 0x00, 0x20)
    program.emit(0xA9, 0x1E, 0x8D, 0x01, 0x20)
    program.emit(0xA9, 0xA5, 0x85, 0x0F)  # initialization marker

    # The foreground loop advances exactly once for each NMI-produced frame
    # token. It polls the real $4016/$4017 serial interface and updates state.
    program.label("main_loop")
    program.emit(0xA5, 0x00)
    program.branch(0xF0, "main_loop")
    program.emit(0xA9, 0x00, 0x85, 0x00)
    emit_controller_poll(program)
    program.emit(0xE6, 0x12)  # controller poll count

    # new_press = current & ~previous; remember current for edge actions.
    program.emit(0xA5, 0x13, 0x49, 0xFF, 0x25, 0x10, 0x85, 0x14)
    program.emit(0xA5, 0x10, 0x85, 0x13)

    # Start enters gameplay and makes the player visible.
    program.emit(0xA5, 0x14, 0x29, 0x08)
    program.branch(0xF0, "no_start")
    program.emit(0xA9, 0x01, 0x85, 0x02)
    program.emit(0xA5, 0x04, 0x8D, 0x00, 0x02)
    program.label("no_start")

    # A and Select choose distinct persistent sprite palettes.
    program.emit(0xA5, 0x14, 0x29, 0x01)
    program.branch(0xF0, "no_a")
    program.emit(0xA9, 0x01, 0x85, 0x05, 0x8D, 0x02, 0x02)
    program.label("no_a")
    program.emit(0xA5, 0x14, 0x29, 0x04)
    program.branch(0xF0, "no_select")
    program.emit(0xA9, 0x02, 0x85, 0x05, 0x8D, 0x02, 0x02)
    program.label("no_select")

    # B selects the persistent action sprite tile.
    program.emit(0xA5, 0x14, 0x29, 0x02)
    program.branch(0xF0, "no_b")
    program.emit(0xA9, 0x03, 0x85, 0x07, 0x8D, 0x01, 0x02)
    program.label("no_b")

    # Directional movement is level-sensitive and bounded to the visible
    # playfield. No direction can wrap an eight-bit coordinate.
    program.emit(0xA5, 0x02)
    program.branch(0xF0, "movement_done")

    program.emit(0xA5, 0x10, 0x29, 0x80)
    program.branch(0xF0, "no_right")
    program.emit(0xA5, 0x03, 0xC9, 0xF0)
    program.branch(0xB0, "no_right")
    program.emit(0x18, 0x69, 0x02, 0x85, 0x03, 0x8D, 0x03, 0x02)
    program.label("no_right")

    program.emit(0xA5, 0x10, 0x29, 0x40)
    program.branch(0xF0, "no_left")
    program.emit(0xA5, 0x03, 0xC9, 0x09)
    program.branch(0x90, "no_left")
    program.emit(0x38, 0xE9, 0x02, 0x85, 0x03, 0x8D, 0x03, 0x02)
    program.label("no_left")

    program.emit(0xA5, 0x10, 0x29, 0x10)
    program.branch(0xF0, "no_up")
    program.emit(0xA5, 0x04, 0xC9, 0x11)
    program.branch(0x90, "no_up")
    program.emit(0x38, 0xE9, 0x02, 0x85, 0x04, 0x8D, 0x00, 0x02)
    program.label("no_up")

    program.emit(0xA5, 0x10, 0x29, 0x20)
    program.branch(0xF0, "no_down")
    program.emit(0xA5, 0x04, 0xC9, 0xE0)
    program.branch(0xB0, "no_down")
    program.emit(0x18, 0x69, 0x02, 0x85, 0x04, 0x8D, 0x00, 0x02)
    program.label("no_down")
    program.label("movement_done")
    program.absolute(0x4C, "main_loop")

    put(prg, 0x8000, program.resolve())

    palette = bytes(
        (
            0x0F, 0x01, 0x21, 0x31,
            0x0F, 0x06, 0x16, 0x26,
            0x0F, 0x09, 0x19, 0x29,
            0x0F, 0x03, 0x13, 0x23,
            0x0F, 0x2A, 0x1A, 0x0A,
            0x0F, 0x27, 0x17, 0x07,
            0x0F, 0x25, 0x15, 0x05,
            0x0F, 0x2C, 0x1C, 0x0C,
        )
    )
    put(prg, 0x8200, palette)

    # NMI: preserve all registers, count the frame, DMA page $02 to OAM,
    # publish one main-loop token, then return to interrupted execution.
    nmi = Program(0x9000)
    nmi.emit(0x48, 0x8A, 0x48, 0x98, 0x48)  # PHA; TXA/PHA; TYA/PHA
    nmi.emit(0xE6, 0x01, 0xE6, 0x06)  # NMI and gameplay-frame counters
    nmi.emit(0xA9, 0x00, 0x8D, 0x03, 0x20)  # OAMADDR=0
    nmi.emit(0xA9, 0x02, 0x8D, 0x14, 0x40)  # OAM DMA from $0200
    nmi.emit(0xA9, 0x01, 0x85, 0x00)  # publish frame token
    nmi.emit(0x68, 0xA8, 0x68, 0xAA, 0x68, 0x40)  # restore; RTI
    put(prg, 0x9000, nmi.resolve())

    # A valid defensive IRQ/BRK handler records entry and returns.
    put(prg, 0x9100, bytes((0xE6, 0x0E, 0x40)))
    set_vectors(prg, nmi=0x9000, reset=0x8000, irq=0x9100)
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
    write_fixture(
        output_dir,
        "phase4d_dma_nrom128",
        dma_bus_master_prg(),
        chr_data,
        vertical=False,
    )
    write_fixture(
        output_dir,
        "phase4db_playable_nrom128",
        playable_demo_prg(),
        playable_demo_chr(),
        vertical=False,
    )


if __name__ == "__main__":
    main()
