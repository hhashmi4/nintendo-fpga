"""Independent software model of the Phase 4E-B direct-pixel renderer."""

from __future__ import annotations

from dataclasses import dataclass


FONT_5X8: dict[str, tuple[str, ...]] = {
    " ": ("00000",) * 8,
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110", "00000"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110", "00000"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111", "00000"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110", "00000"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010", "00000"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110", "00000"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110", "00000"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000", "00000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110", "00000"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110", "00000"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001", "00000"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110", "00000"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111", "00000"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110", "00000"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111", "00000"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000", "00000"),
    "G": ("01111", "10000", "10000", "10111", "10001", "10001", "01111", "00000"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001", "00000"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111", "00000"),
    "J": ("00001", "00001", "00001", "00001", "10001", "10001", "01110", "00000"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001", "00000"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111", "00000"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001", "00000"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001", "00000"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110", "00000"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000", "00000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101", "00000"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001", "00000"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110", "00000"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100", "00000"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110", "00000"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100", "00000"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010", "00000"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001", "00000"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100", "00000"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "00110", "00110", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000", "00000"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000", "00000"),
    ":": ("00000", "00110", "00110", "00000", "00110", "00110", "00000", "00000"),
    "=": ("00000", "00000", "11111", "00000", "11111", "00000", "00000", "00000"),
    "[": ("01110", "01000", "01000", "01000", "01000", "01000", "01110", "00000"),
    "]": ("01110", "00010", "00010", "00010", "00010", "00010", "01110", "00000"),
}

SUPPORTED_CHARACTERS = " " + "0123456789" + "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + ".-/:=[]"

BACKGROUND = (0x08, 0x10, 0x20)
HEADER_BACKGROUND = (0x10, 0x28, 0x44)
TEXT = (0xD0, 0xE0, 0xE8)
HEADING = (0x50, 0xE8, 0xF0)
SECTION = (0xF0, 0xD0, 0x50)
GOOD = (0x60, 0xF0, 0x80)
BAD = (0xFF, 0x50, 0x60)
BORDER = (0x28, 0x70, 0x90)


@dataclass(frozen=True)
class DemoSnapshot:
    pc: int = 0x80A5
    a: int = 0x03
    x: int = 0x10
    y: int = 0x20
    sp: int = 0xFF
    status: int = 0x24
    opcode: int = 0xA9
    address: int = 0x2002
    read_data: int = 0xEA
    write_data: int = 0x55
    bus_owner: int = 1
    bus_valid: bool = True
    read: bool = True
    write: bool = False
    stalled: bool = False
    scanline: int = 142
    dot: int = 221
    frame_odd: bool = True
    ctrl: int = 0x80
    mask: int = 0x1E
    ppu_status: int = 0xA0
    pixel_color: int = 0x23
    palette_address: int = 0x3F12
    vblank: bool = True
    nmi_level: bool = True
    sprite_zero_hit: bool = True
    sprite_overflow: bool = False
    cart_present: bool = True
    mapper: int = 0
    nrom_256: bool = False
    prg_address: int = 0x40A5
    prg_data: int = 0x4C
    chr_address: int = 0x12F0
    chr_data: int = 0x03
    mirroring: int = 1
    chr_is_ram: bool = False
    pad1: int = 0x99
    pad2: int = 0x42
    shift1: int = 0xA5
    shift2: int = 0x5A
    index1: int = 3
    index2: int = 7
    strobe: bool = False
    dma_active: bool = False
    dma_page: int = 0x02
    dma_address: int = 0x02C1
    dma_index: int = 0xC1
    dma_slots: int = 0x201
    dma_reads: int = 0x100
    dma_writes: int = 0x100
    dma_owner: int = 1
    snapshot_id: int = 0x0000012C
    source_frame: int = 0x0000012C
    nmi_count: int = 0x00000129
    dma_count: int = 0x00000129
    poll_count: int = 0x00000129
    cpu_slots: int = 0x0087DE98
    ppu_cycles: int = 0x0197A4A8


def hex_value(value: int, digits: int) -> str:
    return f"{value & ((1 << (digits * 4)) - 1):0{digits}X}"


def owner_text(owner: int) -> str:
    return {1: "CPU", 2: "DMA"}.get(owner, "NONE")


def pad_text(buttons: int) -> str:
    labels = "ABSTUDLR"
    return "".join(label if buttons & (1 << index) else "-"
                   for index, label in enumerate(labels))


def build_character_grid(
    snapshot: DemoSnapshot = DemoSnapshot(), *, valid: bool = True,
    stale: bool = False,
) -> tuple[list[list[str]], dict[tuple[int, int], tuple[int, int, int]]]:
    grid = [[" " for _ in range(78)] for _ in range(29)]
    colors: dict[tuple[int, int], tuple[int, int, int]] = {}

    def put(row: int, column: int, text: str, color=TEXT) -> None:
        for offset, character in enumerate(text):
            if 0 <= row < len(grid) and 0 <= column + offset < len(grid[row]):
                grid[row][column + offset] = character
                colors[row, column + offset] = color

    put(0, 1, "FPGA CONSOLE", HEADING)
    put(0, 14, "-", HEADING)
    put(0, 16, "DEVELOPER MODE", HEADING)
    put(1, 1, f"SNAP={hex_value(snapshot.snapshot_id, 8)}")
    if not valid:
        put(1, 20, "INVALID", BAD)
    elif stale:
        put(1, 20, "STALE", BAD)
    else:
        put(1, 20, "VALID", GOOD)

    put(3, 1, "CPU", SECTION)
    put(3, 27, "PPU", SECTION)
    put(3, 53, "CART", SECTION)
    put(4, 1, f"PC={hex_value(snapshot.pc, 4)}")
    put(4, 27, f"SL={hex_value(snapshot.scanline, 3)}")
    put(4, 53, f"PRESENT={int(snapshot.cart_present)}")
    put(5, 1, f"A={hex_value(snapshot.a, 2)}  X={hex_value(snapshot.x, 2)}")
    put(5, 27, f"DOT={hex_value(snapshot.dot, 3)}")
    put(5, 53, f"MAP={hex_value(snapshot.mapper, 2)}")
    put(6, 1, f"Y={hex_value(snapshot.y, 2)}  SP={hex_value(snapshot.sp, 2)}")
    put(6, 27, f"CTRL={hex_value(snapshot.ctrl, 2)}")
    put(6, 53, f"NROM={'256' if snapshot.nrom_256 else '128'}")
    put(7, 1, f"P={hex_value(snapshot.status, 2)}  OP={hex_value(snapshot.opcode, 2)}")
    put(7, 27, f"MASK={hex_value(snapshot.mask, 2)}")
    put(7, 53, f"PRG={hex_value(snapshot.prg_address, 4)}:{hex_value(snapshot.prg_data, 2)}")
    put(8, 1, f"ADR={hex_value(snapshot.address, 4)}")
    put(8, 27, f"STAT={hex_value(snapshot.ppu_status, 2)}")
    put(8, 53, f"CHR={hex_value(snapshot.chr_address, 4)}:{hex_value(snapshot.chr_data, 2)}")
    put(9, 1, f"RD={hex_value(snapshot.read_data, 2)}  WR={hex_value(snapshot.write_data, 2)}")
    put(9, 27, f"VB={int(snapshot.vblank)} NMI={int(snapshot.nmi_level)}")
    mirror = {0: "V", 1: "H"}.get(snapshot.mirroring, "-")
    put(9, 53, f"MIR={mirror}")
    put(10, 1, f"BUS={owner_text(snapshot.bus_owner)}")
    put(10, 27, f"Z={int(snapshot.sprite_zero_hit)} OV={int(snapshot.sprite_overflow)}")
    put(10, 53, f"CHR={'RAM' if snapshot.chr_is_ram else 'ROM'}")
    rw = "-" if not snapshot.bus_valid else "W" if snapshot.write else "R" if snapshot.read else "I"
    put(11, 1, f"RW={rw}")
    put(11, 27, f"PIX={hex_value(snapshot.pixel_color, 2)} /{hex_value(snapshot.palette_address, 2)}")
    put(12, 1, "STALL" if snapshot.stalled else "RUN", BAD if snapshot.stalled else GOOD)
    put(12, 27, f"PAR={int(snapshot.frame_odd)}")

    put(16, 1, "CONTROLLER", SECTION)
    put(16, 27, "DMA", SECTION)
    put(16, 53, "SYSTEM", SECTION)
    put(17, 1, f"P1={pad_text(snapshot.pad1)}")
    put(17, 27, "ACTIVE" if snapshot.dma_active else "IDLE",
        BAD if snapshot.dma_active else GOOD)
    put(17, 53, f"SNAP={hex_value(snapshot.snapshot_id, 8)}")
    put(18, 1, f"P2={pad_text(snapshot.pad2)}")
    put(18, 27, f"PG={hex_value(snapshot.dma_page, 2)}")
    put(18, 53, f"FRAME={hex_value(snapshot.source_frame, 8)}")
    put(19, 1, f"STB={int(snapshot.strobe)}")
    put(19, 27, f"ADR={hex_value(snapshot.dma_address, 4)}")
    put(19, 53, f"NMI={hex_value(snapshot.nmi_count, 8)}")
    put(20, 1, f"I1={hex_value(snapshot.index1, 1)} I2={hex_value(snapshot.index2, 1)}")
    put(20, 27, f"IDX={hex_value(snapshot.dma_index, 2)}")
    put(20, 53, f"DMA={hex_value(snapshot.dma_count, 8)}")
    put(21, 1, f"SHIFT1={hex_value(snapshot.shift1, 2)}")
    put(21, 27, f"SLOT={hex_value(snapshot.dma_slots, 3)}")
    put(21, 53, f"POLL={hex_value(snapshot.poll_count, 8)}")
    put(22, 1, f"SHIFT2={hex_value(snapshot.shift2, 2)}")
    put(22, 27, f"RD={hex_value(snapshot.dma_reads, 3)} WR={hex_value(snapshot.dma_writes, 3)}")
    put(22, 53, f"CPU={hex_value(snapshot.cpu_slots, 8)}")
    put(23, 27, f"OWN={owner_text(snapshot.dma_owner)}")
    put(23, 53, f"PPU={hex_value(snapshot.ppu_cycles, 8)}")
    put(27, 1, "READ ONLY", HEADING)
    put(27, 11, "-", HEADING)
    put(27, 13, "FPGA CONSOLE", HEADING)
    return grid, colors


def render_frame(
    snapshot: DemoSnapshot = DemoSnapshot(), *, valid: bool = True,
    stale: bool = False,
) -> bytes:
    grid, colors = build_character_grid(snapshot, valid=valid, stale=stale)
    pixels = bytearray()
    for y in range(480):
        for x in range(640):
            color = HEADER_BACKGROUND if y < 48 else BACKGROUND
            if x in (4, 635) or y in (4, 48, 248, 475):
                color = BORDER
            if 8 <= x < 632 and 8 <= y < 472:
                column = (x - 8) >> 3
                row = (y - 8) >> 4
                glyph_column = (x - 8) & 7
                glyph_row = ((y - 8) & 15) >> 1
                character = grid[row][column]
                if glyph_column < 6:
                    row_bits = FONT_5X8.get(character, FONT_5X8[" "])[glyph_row] + "0"
                    if row_bits[glyph_column] == "1":
                        color = colors.get((row, column), TEXT)
            pixels.extend(color)
    return bytes(pixels)
