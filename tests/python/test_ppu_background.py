from verification.ppu_background import (
    BackgroundModel,
    FetchType,
    attribute_address,
    attribute_palette,
    completion_dot,
    fetch_type_for_dot,
    main_fetch_dot,
    nametable_address,
    pattern_address,
    pattern_pixel,
    rendering_scanline,
    trailing_fetch_dot,
)


def test_attribute_quadrants_exhaustive() -> None:
    for attribute in range(256):
        for coarse_y_bit_1 in range(2):
            for coarse_x_bit_1 in range(2):
                coarse_x = coarse_x_bit_1 << 1
                coarse_y = coarse_y_bit_1 << 1
                shift = ((coarse_y_bit_1 << 1) | coarse_x_bit_1) * 2
                assert attribute_palette(attribute, coarse_x, coarse_y) == (
                    attribute >> shift
                ) & 3


def test_pattern_addresses_exhaustive() -> None:
    seen = 0
    for table in range(2):
        for tile_id in range(256):
            for fine_y in range(8):
                for plane in range(2):
                    expected = (
                        table * 0x1000
                        + tile_id * 16
                        + fine_y
                        + plane * 8
                    )
                    actual = pattern_address(table, tile_id, fine_y, plane)
                    assert actual == expected
                    assert 0 <= actual < 0x2000
                    seen += 1
    assert seen == 8192


def test_pattern_bit_orientation() -> None:
    patterns = (0x80, 0x40, 0x01, 0xFF, 0xAA, 0x55, 0x81)
    for low in patterns:
        expected = [(low >> bit) & 1 for bit in range(7, -1, -1)]
        assert [pattern_pixel(low, 0, x) for x in range(8)] == expected
        assert [pattern_pixel(0, low, x) for x in range(8)] == [
            value << 1 for value in expected
        ]
        assert [pattern_pixel(low, low, x) for x in range(8)] == [
            value * 3 for value in expected
        ]


def test_fetch_windows_and_types_all_coordinates() -> None:
    for scanline in range(262):
        for dot in range(341):
            kind = fetch_type_for_dot(dot)
            if main_fetch_dot(dot):
                assert kind in {
                    FetchType.NAMETABLE,
                    FetchType.ATTRIBUTE,
                    FetchType.PATTERN_LOW,
                    FetchType.PATTERN_HIGH,
                }
            elif trailing_fetch_dot(dot):
                assert kind == FetchType.NAMETABLE_DUMMY
            else:
                assert kind == FetchType.NONE
            assert rendering_scanline(scanline) is (
                scanline < 240 or scanline == 261
            )


def test_fetch_pair_order_and_completion() -> None:
    expected = (
        FetchType.NAMETABLE,
        FetchType.NAMETABLE,
        FetchType.ATTRIBUTE,
        FetchType.ATTRIBUTE,
        FetchType.PATTERN_LOW,
        FetchType.PATTERN_LOW,
        FetchType.PATTERN_HIGH,
        FetchType.PATTERN_HIGH,
    )
    assert tuple(fetch_type_for_dot(dot) for dot in range(1, 9)) == expected
    assert [dot for dot in range(1, 9) if completion_dot(dot)] == [2, 4, 6, 8]
    assert [dot for dot in range(337, 341) if completion_dot(dot)] == [338, 340]


def test_address_helpers() -> None:
    for v in range(0x8000):
        assert nametable_address(v) == 0x2000 | (v & 0x0FFF)
        assert attribute_address(v) == (
            0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 7)
        )


def test_ppumask_and_left_edge_output() -> None:
    model = BackgroundModel()
    model.pattern_low_shift = 0xFFFF
    model.attribute_low_shift = 0xFFFF

    off = model.observe(
        reset=False,
        ppu_enable=True,
        dot=1,
        scanline=0,
        visible_pixel=True,
        pixel_x=0,
        pixel_y=0,
        rendering_enabled=False,
        background_enabled=False,
        show_background_left=False,
        pattern_table=0,
        fine_x=0,
        v=0,
        memory_grant=False,
    )
    assert off.pixel_valid and not off.opaque and off.pattern == off.palette == 0

    clipped = model.observe(
        reset=False,
        ppu_enable=True,
        dot=1,
        scanline=0,
        visible_pixel=True,
        pixel_x=7,
        pixel_y=0,
        rendering_enabled=True,
        background_enabled=True,
        show_background_left=False,
        pattern_table=0,
        fine_x=0,
        v=0,
        memory_grant=True,
    )
    assert not clipped.opaque and clipped.index == 0

    shown = model.observe(
        reset=False,
        ppu_enable=True,
        dot=9,
        scanline=0,
        visible_pixel=True,
        pixel_x=8,
        pixel_y=0,
        rendering_enabled=True,
        background_enabled=True,
        show_background_left=False,
        pattern_table=0,
        fine_x=0,
        v=0,
        memory_grant=True,
    )
    assert shown.pattern == 1 and shown.palette == 1
    assert shown.opaque and shown.index == 5


def test_sprite_only_keeps_fetches_but_background_is_transparent() -> None:
    model = BackgroundModel()
    model.pattern_low_shift = 0x8000
    observation = model.observe(
        reset=False,
        ppu_enable=True,
        dot=1,
        scanline=0,
        visible_pixel=True,
        pixel_x=0,
        pixel_y=0,
        rendering_enabled=True,
        background_enabled=False,
        show_background_left=True,
        pattern_table=0,
        fine_x=0,
        v=0,
        memory_grant=True,
    )
    assert observation.memory_request
    assert not observation.opaque and observation.pattern == 0


def test_stall_does_not_change_state() -> None:
    model = BackgroundModel()
    model.pattern_low_shift = 0xA55A
    model.next_tile_id = 0x77
    before = model.__dict__.copy()
    observation = model.observe(
        reset=False,
        ppu_enable=False,
        dot=8,
        scanline=0,
        visible_pixel=False,
        pixel_x=0,
        pixel_y=0,
        rendering_enabled=True,
        background_enabled=True,
        show_background_left=True,
        pattern_table=0,
        fine_x=0,
        v=0,
        memory_grant=False,
    )
    assert not observation.memory_request
    assert not observation.shifter_shift and not observation.tile_load
    model.clock(observation, reset=False, ppu_enable=False, v=0, memory_data=0xFF)
    assert model.__dict__ == before


def test_nonvisible_coordinates_never_claim_pixel_validity() -> None:
    model = BackgroundModel()
    observation = model.observe(
        reset=False,
        ppu_enable=True,
        dot=321,
        scanline=261,
        visible_pixel=False,
        pixel_x=0,
        pixel_y=0,
        rendering_enabled=True,
        background_enabled=True,
        show_background_left=True,
        pattern_table=1,
        fine_x=7,
        v=0x7FFF,
        memory_grant=True,
    )
    assert observation.memory_request
    assert not observation.pixel_valid
    assert not observation.opaque and observation.index == 0
