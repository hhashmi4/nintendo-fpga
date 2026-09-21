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
    pixel_x: int = 0x80
    pixel_y: int = 0x70
    pixel_valid: bool = True
    palette_address: int = 0x3F12
    nmi_enabled: bool = True
    nmi_event: bool = False
    nmi_suppressed: bool = False
    vblank: bool = True
    nmi_level: bool = True
    sprite_zero_hit: bool = True
    sprite_overflow: bool = False
    cart_present: bool = True
    mapper: int = 0
    nrom_256: bool = False
    prg_address: int = 0x40A5
    prg_data: int = 0x4C
    prg_read: bool = True
    prg_write: bool = False
    chr_address: int = 0x12F0
    chr_data: int = 0x03
    chr_read: bool = True
    chr_write: bool = False
    mirroring: int = 1
    chr_is_ram: bool = False
    pad1: int = 0x99
    pad2: int = 0x42
    shift1: int = 0xA5
    shift2: int = 0x5A
    index1: int = 3
    index2: int = 7
    strobe: bool = False
    serial1: bool = True
    serial2: bool = False
    read_4016: bool = True
    read_4017: bool = False
    latch_event: bool = False
    dma_active: bool = False
    dma_page: int = 0x02
    dma_address: int = 0x02C1
    dma_source_data: int = 0x5A
    dma_index: int = 0xC1
    dma_oam_data: int = 0xA5
    dma_phase: int = 3
    dma_started_odd: bool = True
    dma_slots: int = 0x201
    dma_reads: int = 0x100
    dma_writes: int = 0x100
    dma_owner: int = 1
    dma_cpu_stall: bool = False
    dma_start_event: bool = False
    dma_read_event: bool = True
    dma_write_event: bool = False
    dma_complete_event: bool = False
    dma_dummy_cycle: bool = False
    dma_alignment_cycle: bool = True
    snapshot_id: int = 0x0000012C
    source_frame: int = 0x0000012C
    nmi_count: int = 0x00000129
    dma_count: int = 0x00000129
    poll_count: int = 0x00000129
    cpu_slots: int = 0x0087DE98
    ppu_cycles: int = 0x0197A4A8
    prg_reads: int = 0x00034567
    chr_reads: int = 0x00045678
    missed_captures: int = 0


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


PANEL_WIDTH = 128
GAME_WIDTH = 512
PANEL_SEPARATOR_Y = frozenset((32, 120, 200, 280, 328, 392, 479))


def build_panel_character_grid(
    snapshot: DemoSnapshot = DemoSnapshot(), *, valid: bool = True,
    stale: bool = False, page: int = 0,
) -> tuple[list[list[str]], dict[tuple[int, int], tuple[int, int, int]]]:
    """Build one compact 16-column by 30-row Phase 4E-D text page."""

    if page not in range(5):
        raise ValueError("page must be in the range 0..4")

    grid = [[" " for _ in range(16)] for _ in range(30)]
    colors: dict[tuple[int, int], tuple[int, int, int]] = {}

    def put(row: int, column: int, text: str, color=TEXT) -> None:
        for offset, character in enumerate(text):
            if 0 <= row < 30 and 0 <= column + offset < 16:
                grid[row][column + offset] = character
                colors[row, column + offset] = color

    titles = ("OVERVIEW", "CPU/BUS", "PPU/CART", "DMA/PAD", "SYSTEM")
    put(0, 1, titles[page], HEADING)
    put(0, 12, f"{page + 1}/5", HEADING)
    put(1, 1, "INVALID" if not valid else "STALE" if stale else "VALID",
        BAD if (not valid or stale) else GOOD)

    if page == 0:
        put(2, 1, "CPU", SECTION)
        put(3, 1, "PC")
        put(3, 4, hex_value(snapshot.pc, 4))
        put(4, 1, "A")
        put(4, 3, hex_value(snapshot.a, 2))
        put(4, 6, "X")
        put(4, 8, hex_value(snapshot.x, 2))
        put(4, 11, "Y")
        put(4, 13, hex_value(snapshot.y, 2))
        put(5, 1, "SP")
        put(5, 3, hex_value(snapshot.sp, 2))
        put(5, 6, "P")
        put(5, 7, hex_value(snapshot.status, 2))
        put(5, 10, "OP")
        put(5, 12, hex_value(snapshot.opcode, 2))
        put(6, 1, "STALL" if snapshot.stalled else "RUN",
            BAD if snapshot.stalled else GOOD)
        put(6, 7, owner_text(snapshot.bus_owner))
        put(8, 1, "PPU", SECTION)
        put(9, 1, "SL")
        put(9, 3, hex_value(snapshot.scanline, 3))
        put(9, 7, "DT")
        put(9, 9, hex_value(snapshot.dot, 3))
        put(10, 1, f"C{hex_value(snapshot.ctrl, 2)}")
        put(10, 5, f"M{hex_value(snapshot.mask, 2)}")
        put(10, 9, f"S{hex_value(snapshot.ppu_status, 2)}")
        put(11, 1, f"N{int(snapshot.nmi_level)}")
        put(11, 4, f"V{int(snapshot.vblank)}")
        put(11, 7, f"Z{int(snapshot.sprite_zero_hit)}")
        put(13, 1, "CART", SECTION)
        put(14, 1, "MAP")
        put(14, 4, hex_value(snapshot.mapper, 2))
        put(14, 7, f"N{'256' if snapshot.nrom_256 else '128'}")
        put(15, 1, "PRG")
        put(15, 4, hex_value(snapshot.prg_address, 4))
        put(16, 1, "CHR")
        put(16, 4, hex_value(snapshot.chr_address, 4))
        put(16, 9, "MIR")
        put(16, 12, "H" if snapshot.mirroring == 1 else "V")
        put(18, 1, "PAD1", SECTION)
        put(19, 1, pad_text(snapshot.pad1))
        put(21, 1, "DMA", SECTION)
        put(21, 5, "ACTIVE" if snapshot.dma_active else "IDLE",
            BAD if snapshot.dma_active else GOOD)
        put(22, 1, "PG")
        put(22, 3, hex_value(snapshot.dma_page, 2))
        put(22, 6, "IX")
        put(22, 8, hex_value(snapshot.dma_index, 2))
        put(23, 1, "CT")
        put(23, 3, hex_value(snapshot.dma_count, 8))
        put(25, 1, "SYSTEM", SECTION)
        put(26, 1, "FR")
        put(26, 3, hex_value(snapshot.source_frame, 8))
        put(27, 1, "ID")
        put(27, 3, hex_value(snapshot.snapshot_id, 8))
        put(28, 1, "NMI")
        put(28, 4, hex_value(snapshot.nmi_count, 8))
        put(29, 1, "DMA")
        put(29, 4, hex_value(snapshot.dma_count, 8))
    elif page == 1:
        put(2, 1, "CPU/BUS", SECTION)
        put(3, 1, f"PC {hex_value(snapshot.pc, 4)}")
        put(4, 1, f"A {hex_value(snapshot.a, 2)} X {hex_value(snapshot.x, 2)} Y {hex_value(snapshot.y, 2)}")
        put(5, 1, f"SP {hex_value(snapshot.sp, 2)} P {hex_value(snapshot.status, 2)} OP{hex_value(snapshot.opcode, 2)}")
        put(7, 1, f"ADDR {hex_value(snapshot.address, 4)}")
        put(8, 1, f"RD {hex_value(snapshot.read_data, 2)}  WR {hex_value(snapshot.write_data, 2)}")
        rw = "W" if snapshot.write else "R" if snapshot.read else "I"
        put(9, 1, f"RW {rw}  V{int(snapshot.bus_valid)}")
        put(10, 1, "STALL" if snapshot.stalled else "RUN",
            BAD if snapshot.stalled else GOOD)
        put(12, 1, f"OWNER {owner_text(snapshot.bus_owner)}")
        if snapshot.address < 0x2000:
            target = "RAM"
        elif snapshot.address < 0x4000:
            target = "PPU"
        elif snapshot.address == 0x4016:
            target = "PAD1"
        elif snapshot.address == 0x4017:
            target = "PAD2"
        elif snapshot.address < 0x4020:
            target = "IO"
        else:
            target = "CART"
        put(13, 1, f"TARGET {target}")
        put(15, 1, f"R{int(snapshot.read)}  W{int(snapshot.write)}  {owner_text(snapshot.dma_owner)}")
    elif page == 2:
        put(2, 1, "PPU", SECTION)
        put(3, 1, f"SL {hex_value(snapshot.scanline, 3)} DT {hex_value(snapshot.dot, 3)}")
        put(4, 1, f"PAR {int(snapshot.frame_odd)}  FR {hex_value(snapshot.source_frame, 4)}")
        put(5, 1, f"C {hex_value(snapshot.ctrl, 2)}  M {hex_value(snapshot.mask, 2)}")
        put(6, 1, f"STAT {hex_value(snapshot.ppu_status, 2)}")
        put(7, 1, f"VB{int(snapshot.vblank)} NMI{int(snapshot.nmi_level)} EN{int(snapshot.nmi_enabled)}")
        put(8, 1, f"NE{int(snapshot.nmi_event)} SUP{int(snapshot.nmi_suppressed)} Z{int(snapshot.sprite_zero_hit)} O{int(snapshot.sprite_overflow)}")
        put(9, 1, f"PIX {hex_value(snapshot.pixel_color, 2)}  PAL{hex_value(snapshot.palette_address, 4)}")
        put(10, 1, f"XY {hex_value(snapshot.pixel_x, 2)} {hex_value(snapshot.pixel_y, 2)}  V{int(snapshot.pixel_valid)}")
        put(12, 1, "CART", SECTION)
        put(13, 1, f"PRES {int(snapshot.cart_present)} MAP {hex_value(snapshot.mapper, 2)}")
        put(14, 1, f"NROM {'256' if snapshot.nrom_256 else '128'}")
        put(16, 1, f"PRG {hex_value(snapshot.prg_address, 4)}:{hex_value(snapshot.prg_data, 2)}")
        put(17, 1, f"CHR {hex_value(snapshot.chr_address, 4)}:{hex_value(snapshot.chr_data, 2)}")
        put(18, 1, f"PR{int(snapshot.prg_read)} PW{int(snapshot.prg_write)} CR{int(snapshot.chr_read)} CW{int(snapshot.chr_write)}")
        put(19, 1, f"MIR {'H' if snapshot.mirroring == 1 else 'V'}  CHR {'RAM' if snapshot.chr_is_ram else 'ROM'}")
    elif page == 3:
        put(2, 1, "DMA", SECTION)
        put(3, 1, "ACTIVE" if snapshot.dma_active else "IDLE",
            BAD if snapshot.dma_active else GOOD)
        put(4, 1, f"PAGE {hex_value(snapshot.dma_page, 2)}")
        put(5, 1, f"ADDR {hex_value(snapshot.dma_address, 4)}")
        put(6, 1, f"DAT {hex_value(snapshot.dma_source_data, 2)}  OAM {hex_value(snapshot.dma_oam_data, 2)}")
        put(7, 1, f"IDX {hex_value(snapshot.dma_index, 2)}  PH {hex_value(snapshot.dma_phase, 1)}")
        put(8, 1, f"ODD {int(snapshot.dma_started_odd)}  SLOT{hex_value(snapshot.dma_slots, 3)}")
        put(9, 1, f"RD {hex_value(snapshot.dma_reads, 3)}  WR {hex_value(snapshot.dma_writes, 3)}")
        put(10, 1, f"EVT {int(snapshot.dma_start_event)} {int(snapshot.dma_read_event)} {int(snapshot.dma_write_event)} {int(snapshot.dma_complete_event)}")
        put(11, 1, f"CYC {int(snapshot.dma_dummy_cycle)} {int(snapshot.dma_alignment_cycle)} {owner_text(snapshot.dma_owner)}")
        put(12, 1, f"STALL {int(snapshot.dma_cpu_stall)}")
        put(14, 1, "PAD1", SECTION)
        put(15, 1, pad_text(snapshot.pad1))
        put(16, 1, f"LAT {hex_value(snapshot.shift1, 2)}  IX {hex_value(snapshot.index1, 1)}")
        put(17, 1, f"SER {int(snapshot.serial1)}  PAD2")
        put(18, 1, pad_text(snapshot.pad2))
        put(19, 1, f"LAT {hex_value(snapshot.shift2, 2)}  IX {hex_value(snapshot.index2, 1)}")
        put(20, 1, f"SER {int(snapshot.serial2)}  STB {int(snapshot.strobe)}")
        put(21, 1, f"R16 {int(snapshot.read_4016)}  R17 {int(snapshot.read_4017)}")
        put(22, 1, f"LATCH {int(snapshot.latch_event)}")
        put(24, 1, f"POLL {hex_value(snapshot.poll_count, 8)}")
        put(25, 1, f"DMA {hex_value(snapshot.dma_count, 8)}")
    else:
        put(2, 1, "SYSTEM", SECTION)
        counters = (
            (3, "FRAME", snapshot.source_frame),
            (4, "SNAP", snapshot.snapshot_id),
            (5, "NMI", snapshot.nmi_count),
            (6, "DMA", snapshot.dma_count),
            (7, "POLL", snapshot.poll_count),
            (8, "CPU", snapshot.cpu_slots),
            (9, "PPU", snapshot.ppu_cycles),
            (10, "PRG R", snapshot.prg_reads),
            (11, "CHR R", snapshot.chr_reads),
            (12, "MISS", snapshot.missed_captures),
        )
        for row, label, value in counters:
            put(row, 1, label)
            put(row, 7, hex_value(value, 8))
        put(15, 1, "SNAPSHOT", SECTION)
        put(16, 1, "INVALID" if not valid else "STALE" if stale else "VALID",
            BAD if (not valid or stale) else GOOD)
    return grid, colors


def render_panel(
    snapshot: DemoSnapshot = DemoSnapshot(), *, valid: bool = True,
    stale: bool = False, page: int = 0,
) -> bytes:
    """Render the 128x480 side panel using the shared deterministic font."""

    grid, colors = build_panel_character_grid(
        snapshot, valid=valid, stale=stale, page=page)
    pixels = bytearray()
    for y in range(480):
        for x in range(PANEL_WIDTH):
            color = HEADER_BACKGROUND if y < 32 else BACKGROUND
            if x in (0, PANEL_WIDTH - 1) or y in PANEL_SEPARATOR_Y:
                color = BORDER
            column = x >> 3
            row = y >> 4
            glyph_column = x & 7
            glyph_row = (y & 15) >> 1
            character = grid[row][column]
            if glyph_column < 6:
                row_bits = FONT_5X8.get(character, FONT_5X8[" "])[glyph_row] + "0"
                if row_bits[glyph_column] == "1":
                    color = colors.get((row, column), TEXT)
            pixels.extend(color)
    return bytes(pixels)


def render_combined_frame(
    game_pixels: bytes,
    snapshot: DemoSnapshot = DemoSnapshot(), *, valid: bool = True,
    stale: bool = False, page: int = 0,
) -> bytes:
    """Compose 512x480 game RGB bytes with the 128x480 debug panel."""

    if len(game_pixels) != GAME_WIDTH * 480 * 3:
        raise ValueError("game_pixels must contain exactly 512x480 RGB pixels")
    panel = render_panel(snapshot, valid=valid, stale=stale, page=page)
    combined = bytearray()
    game_stride = GAME_WIDTH * 3
    panel_stride = PANEL_WIDTH * 3
    for y in range(480):
        combined.extend(game_pixels[y * game_stride:(y + 1) * game_stride])
        combined.extend(panel[y * panel_stride:(y + 1) * panel_stride])
    return bytes(combined)
