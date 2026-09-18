"""Behavioral NES rendering-time scroll/address model for Phase 3D.

The helpers describe field semantics rather than mirroring RTL statement
structure. Addresses use the canonical ``yyy NN YYYYY XXXXX`` 15-bit layout.
"""

from dataclasses import dataclass


VISIBLE_SCANLINES = range(240)
PRE_RENDER_SCANLINE = 261
HORIZONTAL_INCREMENT_DOTS = frozenset((*range(8, 257, 8), 328, 336))


@dataclass(frozen=True)
class ScrollEvents:
    coarse_x_increment: bool
    vertical_increment: bool
    horizontal_copy: bool
    vertical_copy: bool

    @property
    def any(self) -> bool:
        return (
            self.coarse_x_increment
            or self.vertical_increment
            or self.horizontal_copy
            or self.vertical_copy
        )


def is_rendering_scanline(scanline: int) -> bool:
    return 0 <= scanline < 240 or scanline == PRE_RENDER_SCANLINE


def active_render_period(rendering_enabled: bool, scanline: int) -> bool:
    return rendering_enabled and is_rendering_scanline(scanline)


def increment_coarse_x(address: int) -> int:
    """Increment coarse X and toggle horizontal nametable on 31 -> 0."""

    address &= 0x7FFF
    coarse_x = address & 0x1F
    if coarse_x == 31:
        return (address & ~0x1F) ^ 0x0400
    return (address & ~0x1F) | (coarse_x + 1)


def increment_vertical(address: int) -> int:
    """Apply the PPU fine/coarse-Y increment, including rows 29 and 31."""

    address &= 0x7FFF
    fine_y = (address >> 12) & 7
    if fine_y < 7:
        return address + 0x1000

    result = address & ~0x7000
    coarse_y = (result >> 5) & 0x1F
    if coarse_y == 29:
        result &= ~0x03E0
        result ^= 0x0800
    elif coarse_y == 31:
        result &= ~0x03E0
    else:
        result = (result & ~0x03E0) | ((coarse_y + 1) << 5)
    return result


def copy_horizontal(address: int, temporary: int) -> int:
    return ((address & ~0x041F) | (temporary & 0x041F)) & 0x7FFF


def copy_vertical(address: int, temporary: int) -> int:
    return ((address & ~0x7BE0) | (temporary & 0x7BE0)) & 0x7FFF


def events_for_coordinate(
    *,
    ppu_enable: bool,
    rendering_enabled: bool,
    scanline: int,
    dot: int,
) -> ScrollEvents:
    eligible = ppu_enable and active_render_period(rendering_enabled, scanline)
    return ScrollEvents(
        coarse_x_increment=eligible and dot in HORIZONTAL_INCREMENT_DOTS,
        vertical_increment=eligible and dot == 256,
        horizontal_copy=eligible and dot == 257,
        vertical_copy=(
            ppu_enable
            and rendering_enabled
            and scanline == PRE_RENDER_SCANLINE
            and 280 <= dot <= 304
        ),
    )


def apply_automatic_scroll(
    address: int,
    temporary: int,
    *,
    ppu_enable: bool,
    rendering_enabled: bool,
    scanline: int,
    dot: int,
) -> tuple[int, ScrollEvents]:
    """Apply all operations consumed by one enabled PPU coordinate."""

    events = events_for_coordinate(
        ppu_enable=ppu_enable,
        rendering_enabled=rendering_enabled,
        scanline=scanline,
        dot=dot,
    )
    result = address & 0x7FFF
    if events.coarse_x_increment:
        result = increment_coarse_x(result)
    if events.vertical_increment:
        result = increment_vertical(result)
    if events.horizontal_copy:
        result = copy_horizontal(result, temporary)
    if events.vertical_copy:
        result = copy_vertical(result, temporary)
    return result, events


def active_data_increment(address: int) -> int:
    """Rendering-time $2007 increment: one horizontal and one vertical step."""

    return increment_vertical(increment_coarse_x(address))


def nametable_fetch_address(address: int) -> int:
    return 0x2000 | (address & 0x0FFF)


def attribute_fetch_address(address: int) -> int:
    return (
        0x23C0
        | (address & 0x0C00)
        | ((address >> 4) & 0x0038)
        | ((address >> 2) & 0x0007)
    )
