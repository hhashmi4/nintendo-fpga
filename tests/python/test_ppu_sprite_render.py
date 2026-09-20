from verification.ppu_sprite_render import (
    SpriteMetadata,
    SpriteRendererModel,
    pattern_pixels,
    render_scene_pixel,
    reverse_byte,
    select_scanline_sprites,
    sprite_pattern_address,
)


def test_exhaustive_8x8_pattern_addresses() -> None:
    cases = 0
    for table in range(2):
        for tile in range(256):
            for relative_row in range(8):
                for flip in (False, True):
                    result = sprite_pattern_address(
                        tile=tile,
                        relative_row=relative_row,
                        size_16=False,
                        pattern_table=table,
                        vertical_flip=flip,
                    )
                    row = 7 - relative_row if flip else relative_row
                    expected = (table << 12) + tile * 16 + row
                    assert result.row == row
                    assert result.low == expected
                    assert result.high == expected + 8
                    assert result.high <= 0x1FFF
                    cases += 2
    assert cases == 16_384


def test_exhaustive_8x16_pattern_addresses() -> None:
    cases = 0
    for tile in range(256):
        for relative_row in range(16):
            for flip in (False, True):
                result = sprite_pattern_address(
                    tile=tile,
                    relative_row=relative_row,
                    size_16=True,
                    pattern_table=1 - (tile & 1),
                    vertical_flip=flip,
                )
                row = 15 - relative_row if flip else relative_row
                selected_tile = (tile & 0xFE) + (row >> 3)
                expected = ((tile & 1) << 12) + selected_tile * 16 + (row & 7)
                assert result.row == row
                assert result.low == expected
                assert result.high == expected + 8
                assert result.high <= 0x1FFF
                cases += 2
    assert cases == 16_384


def test_8x16_bank_ignores_ppuctrl_pattern_table() -> None:
    for tile in (0x00, 0x01, 0x7E, 0x7F, 0xFE, 0xFF):
        for relative_row in range(16):
            first = sprite_pattern_address(
                tile=tile,
                relative_row=relative_row,
                size_16=True,
                pattern_table=0,
                vertical_flip=False,
            )
            second = sprite_pattern_address(
                tile=tile,
                relative_row=relative_row,
                size_16=True,
                pattern_table=1,
                vertical_flip=False,
            )
            assert first == second
            assert (first.low >> 12) == (tile & 1)


def test_horizontal_flip_bytes_and_pixels() -> None:
    for value in (0x80, 0x40, 0x01, 0x81, 0xAA, 0x55, 0xFF):
        assert reverse_byte(reverse_byte(value)) == value
        assert pattern_pixels(value, 0, True) == list(
            reversed(pattern_pixels(value, 0, False))
        )
    for low, high in ((0x81, 0x00), (0xC0, 0x25), (0xA5, 0x5A)):
        assert pattern_pixels(low, high, True) == list(
            reversed(pattern_pixels(low, high, False))
        )


def _loaded_model(x: int, *, flip: bool = False) -> SpriteRendererModel:
    model = SpriteRendererModel()
    model.load_row(
        0,
        SpriteMetadata(0, 1, 0x41 if flip else 0x01, x, 0, True),
        0xA5,
        0x3C,
    )
    return model


def test_single_sprite_positions_and_partial_right_edge() -> None:
    expected_row = pattern_pixels(0xA5, 0x3C)
    for start_x in (0, 1, 7, 8, 100, 248, 255):
        pixels = _loaded_model(start_x).render_scanline(y=20)
        for x, pixel in enumerate(pixels):
            offset = x - start_x
            expected = expected_row[offset] if 0 <= offset < 8 else 0
            assert pixel.pattern == expected
            assert pixel.opaque is (expected != 0)
            if pixel.opaque:
                assert pixel.palette == 1
                assert pixel.original_index == 0
                assert pixel.is_zero


def test_horizontal_flip_does_not_move_x() -> None:
    normal = _loaded_model(100).render_scanline(y=8)
    flipped = _loaded_model(100, flip=True).render_scanline(y=8)
    assert [p.pattern for p in normal[100:108]] == pattern_pixels(0xA5, 0x3C)
    assert [p.pattern for p in flipped[100:108]] == pattern_pixels(
        0xA5, 0x3C, True
    )
    assert all(not p.opaque for p in flipped[:100])


def test_every_x_counter_and_stalls() -> None:
    for start_x in range(256):
        model = SpriteRendererModel()
        model.load_row(
            0, SpriteMetadata(0, 0, 0, start_x, 7, True), 0xFF, 0
        )
        pixels = model.render_scanline(y=2)
        opaque_x = [pixel.x for pixel in pixels if pixel.opaque]
        assert opaque_x[0] == start_x
    baseline = SpriteRendererModel()
    stalled = SpriteRendererModel()
    metadata = SpriteMetadata(0, 0, 0, 19, 2, True)
    baseline.load_row(0, metadata, 0xFF, 0)
    stalled.load_row(0, metadata, 0xFF, 0)
    assert baseline.render_scanline(y=3) == stalled.render_scanline(
        y=3, stalls={0, 1, 2, 7, 31, 100}
    )
    held = _loaded_model(3)
    observation = held.observe(
        reset=False,
        ppu_enable=False,
        dot=1,
        scanline=3,
        visible_pixel=True,
        pixel_x=0,
        pixel_y=3,
        rendering_enabled=True,
        sprites_enabled=True,
        show_sprites_left=True,
        size_16=False,
        pattern_table=0,
        nametable_address=0x2000,
        metadata=SpriteMetadata(),
        memory_grant=False,
    )
    assert observation.decrement_mask == 0
    assert observation.shift_mask == 0


def test_eight_overlapping_first_opaque_wins() -> None:
    model = SpriteRendererModel()
    for slot in range(8):
        low = 0 if slot < 4 else (0x80 >> (slot - 4))
        model.load_row(
            slot,
            SpriteMetadata(0, slot, slot & 3, 12, slot + 8, True),
            low,
            0,
        )
    pixels = model.render_scanline(y=5)
    assert pixels[12].slot == 4
    assert pixels[12].original_index == 12
    assert pixels[13].slot == 5
    assert pixels[14].slot == 6
    assert pixels[15].slot == 7


def test_transparent_earlier_slot_and_metadata() -> None:
    model = SpriteRendererModel()
    model.load_row(
        0, SpriteMetadata(0, 0, 0x23, 8, 0, True), 0x00, 0x00
    )
    model.load_row(
        1, SpriteMetadata(0, 1, 0x21, 8, 17, True), 0x80, 0x80
    )
    pixel = model.render_scanline(y=4)[8]
    assert pixel.opaque
    assert pixel.pattern == 3
    assert pixel.palette == 1
    assert pixel.behind_background
    assert not pixel.is_zero
    assert pixel.slot == 1
    assert pixel.original_index == 17


def test_ppumask_enable_and_left_clipping_independent_of_background() -> None:
    disabled = _loaded_model(0).render_scanline(
        y=1, sprites_enabled=False, show_sprites_left=True
    )
    assert not any(pixel.opaque for pixel in disabled)
    clipped = _loaded_model(0).render_scanline(
        y=1, sprites_enabled=True, show_sprites_left=False
    )
    assert not any(pixel.opaque for pixel in clipped[:8])
    enabled = _loaded_model(0).render_scanline(
        y=1, sprites_enabled=True, show_sprites_left=True
    )
    assert any(pixel.opaque for pixel in enabled[:8])


def test_fetch_cadence_addresses_and_invalid_transparency() -> None:
    model = SpriteRendererModel()
    metadata = SpriteMetadata(20, 0x35, 0x82, 44, 3, True)
    kinds = []
    completes = []
    for dot in range(257, 321):
        observation = model.observe(
            reset=False,
            ppu_enable=True,
            dot=dot,
            scanline=23,
            visible_pixel=False,
            pixel_x=0,
            pixel_y=23,
            rendering_enabled=True,
            sprites_enabled=True,
            show_sprites_left=True,
            size_16=False,
            pattern_table=1,
            nametable_address=0x23AB,
            metadata=metadata if observation_slot(dot) == 0 else SpriteMetadata(),
            memory_grant=True,
        )
        kinds.append(int(observation.kind))
        completes.append(observation.complete)
        data = 0x80 if observation.kind.value == 3 else 0x40
        model.clock(
            observation,
            reset=False,
            ppu_enable=True,
            visible_pixel=False,
            metadata=metadata if observation.slot == 0 else SpriteMetadata(),
            memory_data=data,
        )
    assert kinds[:8] == [1, 1, 2, 2, 3, 3, 4, 4]
    assert completes[:8] == [False, True, False, True, False, True, False, True]
    assert model.valid[0]
    assert all(not value for value in model.valid[1:])
    assert all(value == 0 for value in model.low[1:])
    assert all(value == 0 for value in model.high[1:])


def observation_slot(dot: int) -> int:
    return (dot - 257) >> 3


def test_vertical_flip_unique_rows_and_8x16_half_exchange() -> None:
    for size_16 in (False, True):
        height = 16 if size_16 else 8
        for row in range(height):
            normal = sprite_pattern_address(
                tile=0x7F,
                relative_row=row,
                size_16=size_16,
                pattern_table=0,
                vertical_flip=False,
            )
            flipped = sprite_pattern_address(
                tile=0x7F,
                relative_row=row,
                size_16=size_16,
                pattern_table=0,
                vertical_flip=True,
            )
            assert normal.row == row
            assert flipped.row == height - 1 - row
            if size_16:
                assert ((normal.low >> 4) & 1) != ((flipped.low >> 4) & 1)


def test_scanline_selection_and_direct_scene_priority() -> None:
    oam = [0xF0, 0, 0, 0] * 64
    for index in range(10):
        oam[index * 4 : index * 4 + 4] = [9, index, index & 3, 30]
    selected = select_scanline_sprites(oam, 10, False)
    assert [sprite.original_index for sprite in selected] == list(range(8))

    chr_memory = [0] * 8192
    chr_memory[0] = 0x00
    chr_memory[17] = 0x80
    pixel = render_scene_pixel(
        primary_oam=oam,
        chr_memory=chr_memory,
        x=30,
        y=11,
        size_16=False,
        pattern_table=0,
        sprites_enabled=True,
        show_sprites_left=True,
    )
    assert pixel.opaque and pixel.slot == 1 and pixel.original_index == 1


def test_first_visible_line_is_transparent_by_architecture() -> None:
    oam = [0, 0, 0, 0] * 64
    chr_memory = [0xFF] * 8192
    for x in range(256):
        assert not render_scene_pixel(
            primary_oam=oam,
            chr_memory=chr_memory,
            x=x,
            y=0,
            size_16=False,
            pattern_table=0,
            sprites_enabled=True,
            show_sprites_left=True,
        ).opaque
