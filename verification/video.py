"""Independent Phase 3K VGA, scaling, color, and frame-handoff reference."""

from dataclasses import dataclass
from fractions import Fraction
from typing import Iterator


H_ACTIVE = 640
H_FRONT = 16
H_SYNC = 96
H_BACK = 48
H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK

V_ACTIVE = 480
V_FRONT = 10
V_SYNC = 2
V_BACK = 33
V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK

PIXEL_CLOCK_HZ = 25_200_000
VGA_REFRESH_HZ = Fraction(PIXEL_CLOCK_HZ, H_TOTAL * V_TOTAL)

NES_PPU_HZ = Fraction(945_000_000, 44 * 4)
NES_CPU_HZ = NES_PPU_HZ / 3
NES_PPU_ENABLE_RATIO = NES_PPU_HZ / 50_000_000

NES_WIDTH = 256
NES_HEIGHT = 240
LEFT_BORDER = 64
SCALED_WIDTH = 512


BASE_PALETTE = (
    0x626262, 0x001C95, 0x1904AC, 0x42009D,
    0x61006B, 0x6E0025, 0x650500, 0x491E00,
    0x223700, 0x004900, 0x004F00, 0x004816,
    0x00355E, 0x000000, 0x000000, 0x000000,
    0xABABAB, 0x0C4EDB, 0x3D2EFF, 0x7115F3,
    0x9B0BB9, 0xB01262, 0xA92704, 0x894600,
    0x576600, 0x237F00, 0x008900, 0x008332,
    0x006D90, 0x000000, 0x000000, 0x000000,
    0xFFFFFF, 0x57A5FF, 0x8287FF, 0xB46DFF,
    0xDF60FF, 0xF863C6, 0xF8746D, 0xDE9020,
    0xB3AE00, 0x81C800, 0x56D522, 0x3DD36F,
    0x3EC1C8, 0x4E4E4E, 0x000000, 0x000000,
    0xFFFFFF, 0xBEE0FF, 0xCDD4FF, 0xE0CAFF,
    0xF1C4FF, 0xFCC4EF, 0xFDCACE, 0xF5D4AF,
    0xE6DF9C, 0xD3E99A, 0xC2EFA8, 0xB7EFC4,
    0xB6EAE5, 0xB8B8B8, 0x000000, 0x000000,
)


@dataclass(frozen=True)
class VgaSample:
    x: int
    y: int
    active: bool
    hsync_n: bool
    vsync_n: bool


def vga_frame() -> Iterator[VgaSample]:
    """Yield one complete 800x525 scan in raster order."""

    for y in range(V_TOTAL):
        for x in range(H_TOTAL):
            yield VgaSample(
                x=x,
                y=y,
                active=x < H_ACTIVE and y < V_ACTIVE,
                hsync_n=not (
                    H_ACTIVE + H_FRONT
                    <= x
                    < H_ACTIVE + H_FRONT + H_SYNC
                ),
                vsync_n=not (
                    V_ACTIVE + V_FRONT
                    <= y
                    < V_ACTIVE + V_FRONT + V_SYNC
                ),
            )


def scaled_coordinate(x: int, y: int) -> tuple[bool, int, int, int]:
    """Return region flag, NES x/y, and framebuffer address."""

    if not (0 <= x < H_ACTIVE and 0 <= y < V_ACTIVE):
        return False, 0, 0, 0
    if not LEFT_BORDER <= x < LEFT_BORDER + SCALED_WIDTH:
        return False, 0, 0, 0
    nes_x = (x - LEFT_BORDER) >> 1
    nes_y = y >> 1
    return True, nes_x, nes_y, nes_y * NES_WIDTH + nes_x


def palette_rgb(color: int, emphasis: int = 0) -> tuple[int, int, int]:
    """Match the RTL's documented digital emphasis approximation."""

    value = BASE_PALETTE[color & 0x3F]
    red = (value >> 16) & 0xFF
    green = (value >> 8) & 0xFF
    blue = value & 0xFF

    def attenuate(channel: int) -> int:
        return (channel >> 1) + (channel >> 2)

    if emphasis & 0b110:
        red = attenuate(red)
    if emphasis & 0b101:
        green = attenuate(green)
    if emphasis & 0b011:
        blue = attenuate(blue)
    return red, green, blue


def diagnostic_rgb(x: int, y: int) -> tuple[int, int, int]:
    """Expected board-independent 512x480 centered color-bar diagnostic."""

    region, _, _, _ = scaled_coordinate(x, y)
    if not region:
        return 0, 0, 0
    bars = (
        (255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
        (255, 0, 255), (255, 0, 0), (0, 0, 255), (128, 128, 128),
    )
    return bars[(x - LEFT_BORDER) >> 6]


class FrameHandoffModel:
    """Semantic model of the three-bank complete-frame ownership protocol."""

    def __init__(self) -> None:
        self.write_bank = 1
        self.completed_bank = 0
        self.read_bank = 0
        self.request = 0
        self.acknowledge = 0
        self.display_valid = False

    @property
    def pending(self) -> bool:
        return self.request != self.acknowledge

    def complete_capture(self) -> None:
        if self.pending:
            raise RuntimeError("cannot publish over an unacknowledged frame")
        if self.write_bank == self.read_bank and self.display_valid:
            raise RuntimeError("cannot capture into the displayed bank")
        self.completed_bank = self.write_bank
        self.request ^= 1

    def vga_frame_end(self) -> bool:
        if not self.pending:
            return False
        self.read_bank = self.completed_bank
        self.acknowledge = self.request
        self.display_valid = True
        return True

    def begin_capture(self) -> None:
        unavailable = {self.read_bank}
        if self.pending:
            unavailable.add(self.completed_bank)
        self.write_bank = next(bank for bank in range(3) if bank not in unavailable)
