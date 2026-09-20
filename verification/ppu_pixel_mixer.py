"""Independent semantic model for the Phase 3H final PPU pixel mixer."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Sequence


class PixelSource(IntEnum):
    UNIVERSAL = 0
    BACKGROUND = 1
    SPRITE = 2


@dataclass(frozen=True)
class BackgroundPixel:
    valid: bool = True
    x: int = 0
    y: int = 0
    pattern: int = 0
    palette: int = 0
    opaque: bool = False


@dataclass(frozen=True)
class SpriteCandidate:
    valid: bool = True
    x: int = 0
    y: int = 0
    pattern: int = 0
    palette: int = 0
    opaque: bool = False
    behind_background: bool = False
    is_zero: bool = False
    slot: int = 0
    original_index: int = 0


@dataclass(frozen=True)
class FinalPixel:
    valid: bool
    x: int
    y: int
    source: PixelSource
    palette_address: int
    nes_color: int
    emphasis: int
    sprite_zero_hit: bool
    winning_sprite_slot: int
    winning_sprite_zero: bool


def background_palette_address(palette: int, pattern: int) -> int:
    """Address one opaque entry in the background palette region."""

    if not 1 <= (pattern & 3) <= 3:
        raise ValueError("background pattern zero is transparent")
    return 0x3F00 | ((palette & 3) << 2) | (pattern & 3)


def sprite_palette_address(palette: int, pattern: int) -> int:
    """Address one opaque entry in the sprite palette region."""

    if not 1 <= (pattern & 3) <= 3:
        raise ValueError("sprite pattern zero is transparent")
    return 0x3F10 | ((palette & 3) << 2) | (pattern & 3)


def palette_index(address: int) -> int:
    """Canonical Phase 3C palette index, including $3F1x aliases."""

    index = address & 0x1F
    if index & 0x10 and index & 3 == 0:
        index &= 0x0F
    return index


def interpret_color(value: int, grayscale: bool) -> int:
    """Return the six-bit NES color number after PPUMASK grayscale."""

    color = value & 0x3F
    return color & 0x30 if grayscale else color


def mix_pixel(
    *,
    reset: bool,
    ppu_enable: bool,
    visible_pixel: bool,
    x: int,
    y: int,
    background: BackgroundPixel,
    sprite: SpriteCandidate,
    background_enabled: bool,
    sprites_enabled: bool,
    show_background_left: bool,
    show_sprites_left: bool,
    grayscale: bool,
    emphasis: int,
    palette_ram: Sequence[int],
) -> FinalPixel:
    """Select the displayed source and look up one existing palette byte."""

    coordinates_match = (
        background.x == x
        and background.y == y
        and sprite.x == x
        and sprite.y == y
    )
    valid = (
        not reset
        and ppu_enable
        and visible_pixel
        and 0 <= x < 256
        and 0 <= y < 240
        and background.valid
        and sprite.valid
        and coordinates_match
    )
    allow_left_bg = show_background_left or x >= 8
    allow_left_sprite = show_sprites_left or x >= 8
    bg_opaque = (
        valid
        and background_enabled
        and allow_left_bg
        and background.opaque
        and (background.pattern & 3) != 0
    )
    sp_opaque = (
        valid
        and sprites_enabled
        and allow_left_sprite
        and sprite.opaque
        and (sprite.pattern & 3) != 0
    )

    if bg_opaque and (not sp_opaque or sprite.behind_background):
        source = PixelSource.BACKGROUND
        address = background_palette_address(
            background.palette, background.pattern
        )
    elif sp_opaque:
        source = PixelSource.SPRITE
        address = sprite_palette_address(sprite.palette, sprite.pattern)
    else:
        source = PixelSource.UNIVERSAL
        address = 0x3F00

    stored = palette_ram[palette_index(address)]
    zero_hit = (
        bg_opaque
        and sp_opaque
        and sprite.is_zero
        and sprite.original_index == 0
        and x != 255
    )
    return FinalPixel(
        valid=valid,
        x=x if valid else 0,
        y=y if valid else 0,
        source=source,
        palette_address=address,
        nes_color=interpret_color(stored, grayscale),
        emphasis=emphasis & 7,
        sprite_zero_hit=zero_hit,
        winning_sprite_slot=sprite.slot & 7,
        winning_sprite_zero=(
            sp_opaque and sprite.is_zero and sprite.original_index == 0
        ),
    )
