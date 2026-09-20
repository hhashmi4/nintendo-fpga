import itertools

import pytest

from verification.ppu_pixel_mixer import (
    BackgroundPixel,
    PixelSource,
    SpriteCandidate,
    background_palette_address,
    interpret_color,
    mix_pixel,
    palette_index,
    sprite_palette_address,
)


PALETTE = [(index * 11 + 7) & 0xFF for index in range(32)]


def background(*, opaque: bool, x: int = 20, pattern: int = 1, palette: int = 2):
    return BackgroundPixel(True, x, 30, pattern, palette, opaque)


def sprite(
    *,
    opaque: bool,
    x: int = 20,
    pattern: int = 2,
    palette: int = 1,
    behind: bool = False,
    zero: bool = False,
    original: int = 7,
):
    return SpriteCandidate(
        True, x, 30, pattern, palette, opaque, behind, zero, 3, original
    )


def mix(bg: BackgroundPixel, sp: SpriteCandidate, **overrides):
    arguments = dict(
        reset=False,
        ppu_enable=True,
        visible_pixel=True,
        x=bg.x,
        y=bg.y,
        background=bg,
        sprite=sp,
        background_enabled=True,
        sprites_enabled=True,
        show_background_left=True,
        show_sprites_left=True,
        grayscale=False,
        emphasis=5,
        palette_ram=PALETTE,
    )
    arguments.update(overrides)
    return mix_pixel(**arguments)


def test_all_transparency_priority_and_zero_identity_combinations() -> None:
    for bg_opaque, sp_opaque, behind, is_zero in itertools.product(
        (False, True), repeat=4
    ):
        original = 0 if is_zero else 9
        result = mix(
            background(opaque=bg_opaque),
            sprite(
                opaque=sp_opaque,
                behind=behind,
                zero=is_zero,
                original=original,
            ),
        )
        if not bg_opaque and not sp_opaque:
            assert result.source == PixelSource.UNIVERSAL
            assert result.palette_address == 0x3F00
        elif bg_opaque and (not sp_opaque or behind):
            assert result.source == PixelSource.BACKGROUND
            assert 0x3F01 <= result.palette_address <= 0x3F0F
        else:
            assert result.source == PixelSource.SPRITE
            assert 0x3F11 <= result.palette_address <= 0x3F1F
        assert result.sprite_zero_hit == (
            bg_opaque and sp_opaque and is_zero
        )


def test_behind_sprite_wins_over_transparent_background() -> None:
    result = mix(
        background(opaque=False),
        sprite(opaque=True, behind=True),
    )
    assert result.source == PixelSource.SPRITE


def test_palette_addresses_exhaustive() -> None:
    assert {
        background_palette_address(palette, pattern)
        for palette in range(4)
        for pattern in range(1, 4)
    } == {
        0x3F01, 0x3F02, 0x3F03,
        0x3F05, 0x3F06, 0x3F07,
        0x3F09, 0x3F0A, 0x3F0B,
        0x3F0D, 0x3F0E, 0x3F0F,
    }
    assert {
        sprite_palette_address(palette, pattern)
        for palette in range(4)
        for pattern in range(1, 4)
    } == {
        0x3F11, 0x3F12, 0x3F13,
        0x3F15, 0x3F16, 0x3F17,
        0x3F19, 0x3F1A, 0x3F1B,
        0x3F1D, 0x3F1E, 0x3F1F,
    }
    with pytest.raises(ValueError):
        background_palette_address(0, 0)
    with pytest.raises(ValueError):
        sprite_palette_address(0, 0)


def test_palette_aliases_remain_phase3c_compatible() -> None:
    aliases = ((0x3F00, 0x3F10), (0x3F04, 0x3F14),
               (0x3F08, 0x3F18), (0x3F0C, 0x3F1C))
    for base, alias in aliases:
        assert palette_index(base) == palette_index(alias)


@pytest.mark.parametrize("value", (0x00, 0x01, 0x0F, 0x10, 0x21,
                                    0x2A, 0x30, 0x3F, 0xFF))
def test_grayscale_masks_output_without_changing_storage(value: int) -> None:
    assert interpret_color(value, False) == value & 0x3F
    assert interpret_color(value, True) == value & 0x30


def test_zero_hit_x255_priority_and_original_identity() -> None:
    bg = background(opaque=True)
    behind_zero = sprite(
        opaque=True, behind=True, zero=True, original=0
    )
    result = mix(bg, behind_zero)
    assert result.source == PixelSource.BACKGROUND
    assert result.sprite_zero_hit

    at_254 = mix(
        BackgroundPixel(True, 254, 30, 1, 0, True),
        SpriteCandidate(True, 254, 30, 1, 0, True, False, True, 0, 0),
        x=254,
    )
    at_255 = mix(
        BackgroundPixel(True, 255, 30, 1, 0, True),
        SpriteCandidate(True, 255, 30, 1, 0, True, False, True, 0, 0),
        x=255,
    )
    assert at_254.sprite_zero_hit
    assert not at_255.sprite_zero_hit
    assert at_255.source == PixelSource.SPRITE

    wrong_identity = mix(
        bg, sprite(opaque=True, zero=True, original=4)
    )
    assert not wrong_identity.sprite_zero_hit


def test_left_edge_all_enable_combinations() -> None:
    for x in range(8):
        bg = BackgroundPixel(True, x, 30, 1, 0, True)
        sp = SpriteCandidate(True, x, 30, 1, 0, True, False, True, 0, 0)
        for bg_left, sp_left in itertools.product((False, True), repeat=2):
            result = mix(
                bg,
                sp,
                x=x,
                show_background_left=bg_left,
                show_sprites_left=sp_left,
            )
            assert result.sprite_zero_hit == (bg_left and sp_left)

    result = mix(
        BackgroundPixel(True, 8, 30, 1, 0, True),
        SpriteCandidate(True, 8, 30, 1, 0, True, False, True, 0, 0),
        x=8,
        show_background_left=False,
        show_sprites_left=False,
    )
    assert result.sprite_zero_hit


def test_stall_and_nonvisible_cycles_never_emit_pixel_or_hit() -> None:
    bg = background(opaque=True)
    sp = sprite(opaque=True, zero=True, original=0)
    for ppu_enable, visible in ((False, True), (True, False), (False, False)):
        result = mix(
            bg, sp, ppu_enable=ppu_enable, visible_pixel=visible
        )
        assert not result.valid
        assert not result.sprite_zero_hit


def test_mismatched_upstream_coordinates_are_invalid() -> None:
    result = mix(
        background(opaque=True),
        SpriteCandidate(True, 21, 30, 1, 0, True),
    )
    assert not result.valid
    assert not result.sprite_zero_hit
