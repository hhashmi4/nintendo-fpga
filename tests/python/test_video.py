from collections import Counter
from fractions import Fraction

import pytest

from verification.video import (
    BASE_PALETTE,
    FrameHandoffModel,
    H_ACTIVE,
    H_SYNC,
    H_TOTAL,
    LEFT_BORDER,
    NES_CPU_HZ,
    NES_HEIGHT,
    NES_PPU_ENABLE_RATIO,
    NES_PPU_HZ,
    NES_WIDTH,
    PIXEL_CLOCK_HZ,
    V_ACTIVE,
    V_SYNC,
    V_TOTAL,
    VGA_REFRESH_HZ,
    diagnostic_rgb,
    palette_rgb,
    scaled_coordinate,
    vga_frame,
)


def test_vga_rates_are_explicit() -> None:
    assert PIXEL_CLOCK_HZ == 25_200_000
    assert H_TOTAL == 800
    assert V_TOTAL == 525
    assert VGA_REFRESH_HZ == 60


def test_nes_rates_and_exact_three_to_one_ratio() -> None:
    assert NES_PPU_HZ == Fraction(118_125_000, 22)
    assert NES_CPU_HZ == Fraction(39_375_000, 22)
    assert NES_PPU_HZ / NES_CPU_HZ == 3
    assert NES_PPU_ENABLE_RATIO == Fraction(189, 1760)


def test_complete_vga_frame_timing_regions() -> None:
    samples = list(vga_frame())
    assert len(samples) == H_TOTAL * V_TOTAL == 420_000
    assert sum(sample.active for sample in samples) == H_ACTIVE * V_ACTIVE
    assert sum(not sample.hsync_n for sample in samples) == H_SYNC * V_TOTAL
    assert sum(not sample.vsync_n for sample in samples) == V_SYNC * H_TOTAL
    assert samples[0].x == samples[0].y == 0
    assert (samples[-1].x, samples[-1].y) == (799, 524)


def test_scaler_exhaustively_maps_every_visible_coordinate() -> None:
    address_counts: Counter[int] = Counter()
    border = image = 0
    for y in range(V_ACTIVE):
        for x in range(H_ACTIVE):
            region, nes_x, nes_y, address = scaled_coordinate(x, y)
            if region:
                image += 1
                assert 0 <= nes_x < NES_WIDTH
                assert 0 <= nes_y < NES_HEIGHT
                address_counts[address] += 1
            else:
                border += 1

    assert border == 2 * LEFT_BORDER * V_ACTIVE == 61_440
    assert image == 512 * 480 == 245_760
    assert len(address_counts) == NES_WIDTH * NES_HEIGHT == 61_440
    assert set(address_counts.values()) == {4}


def test_scaler_exact_horizontal_boundaries() -> None:
    assert not scaled_coordinate(63, 0)[0]
    assert scaled_coordinate(64, 0) == (True, 0, 0, 0)
    assert scaled_coordinate(65, 1) == (True, 0, 0, 0)
    assert scaled_coordinate(574, 478)[1:3] == (255, 239)
    assert scaled_coordinate(575, 479)[1:3] == (255, 239)
    assert not scaled_coordinate(576, 479)[0]


def test_developer_scaler_is_exactly_two_by_and_left_aligned() -> None:
    address_counts: Counter[int] = Counter()
    for y in range(V_ACTIVE):
        for x in range(512):
            region, nes_x, nes_y, address = scaled_coordinate(
                x, y, left_aligned=True
            )
            assert region
            assert nes_x == x >> 1
            assert nes_y == y >> 1
            address_counts[address] += 1
        assert not scaled_coordinate(512, y, left_aligned=True)[0]
        assert not scaled_coordinate(639, y, left_aligned=True)[0]
    assert len(address_counts) == NES_WIDTH * NES_HEIGHT
    assert set(address_counts.values()) == {4}


def test_palette_has_all_64_entries_and_known_anchors() -> None:
    assert len(BASE_PALETTE) == 64
    assert palette_rgb(0x00) == (0x62, 0x62, 0x62)
    assert palette_rgb(0x20) == (0xFF, 0xFF, 0xFF)
    assert palette_rgb(0x0F) == (0, 0, 0)
    assert palette_rgb(0x3C) == (0xB6, 0xEA, 0xE5)


def test_all_color_and_emphasis_combinations_are_bounded() -> None:
    outputs = [palette_rgb(color, emphasis)
               for emphasis in range(8) for color in range(64)]
    assert len(outputs) == 512
    assert all(0 <= channel <= 255 for rgb in outputs for channel in rgb)
    assert palette_rgb(0x20, 0b001) == (255, 190, 190)
    assert palette_rgb(0x20, 0b111) == (190, 190, 190)


def test_diagnostic_pattern_has_black_borders_and_eight_bars() -> None:
    assert diagnostic_rgb(0, 0) == (0, 0, 0)
    assert diagnostic_rgb(63, 479) == (0, 0, 0)
    assert diagnostic_rgb(64, 0) == (255, 255, 255)
    assert diagnostic_rgb(127, 200) == (255, 255, 255)
    assert diagnostic_rgb(128, 200) == (255, 255, 0)
    assert diagnostic_rgb(575, 479) == (128, 128, 128)
    assert diagnostic_rgb(576, 479) == (0, 0, 0)


def test_frame_handoff_never_presents_partial_bank() -> None:
    model = FrameHandoffModel()
    model.begin_capture()
    model.complete_capture()
    assert model.pending and not model.display_valid
    model.begin_capture()
    assert model.write_bank == 2
    assert model.vga_frame_end()
    assert model.display_valid and model.read_bank == 1
    model.complete_capture()
    assert model.read_bank == 1
    assert model.vga_frame_end()
    assert model.read_bank == 2
    model.begin_capture()
    assert model.write_bank == 0 and model.write_bank != model.read_bank
