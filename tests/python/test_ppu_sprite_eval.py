from verification.ppu_sprite_eval import (
    EvaluationPhase,
    SpriteEvaluationModel,
    oam_address,
    relative_sprite_row,
    sprite_height,
    sprite_in_range,
)


def _fill_out_of_range(model: SpriteEvaluationModel, scanline: int) -> None:
    for sprite in range(64):
        base = sprite * 4
        model.primary_oam[base : base + 4] = [
            (scanline + 64) & 0xFF,
            0x80,
            0x80,
            0x80,
        ]


def _put_sprite(
    model: SpriteEvaluationModel,
    index: int,
    y: int,
    tile: int | None = None,
    attributes: int | None = None,
    x: int | None = None,
) -> None:
    base = index * 4
    model.primary_oam[base : base + 4] = [
        y & 0xFF,
        (tile if tile is not None else 0x40 + index) & 0xFF,
        (attributes if attributes is not None else 0x80 + index) & 0xFF,
        (x if x is not None else 0xC0 + index) & 0xFF,
    ]


def test_range_arithmetic_exhaustive_122880_cases() -> None:
    cases = 0
    for size_16 in (False, True):
        height = 16 if size_16 else 8
        assert sprite_height(size_16) == height
        for scanline in range(240):
            for sprite_y in range(256):
                expected_row = (scanline - sprite_y) & 0xFF
                assert relative_sprite_row(scanline, sprite_y) == expected_row
                assert sprite_in_range(scanline, sprite_y, size_16) is (
                    expected_row < height
                )
                cases += 1
    assert cases == 122_880


def test_oam_byte_mapping_exhaustive() -> None:
    seen = set()
    for sprite in range(64):
        for byte in range(4):
            address = oam_address(sprite, byte)
            assert address == sprite * 4 + byte
            seen.add(address)
    assert seen == set(range(256))


def test_primary_oam_cpu_access_and_active_render_policy() -> None:
    model = SpriteEvaluationModel()
    for address in range(256):
        observation = model.observe(
            reset=False,
            ppu_enable=False,
            dot=300,
            scanline=240,
            rendering_enabled=False,
            sprite_size_16=False,
            cpu_oam_addr=address,
            cpu_write_data=address ^ 0xA5,
            cpu_write_enable=True,
            cpu_access=True,
        )
        assert observation.cpu_write_commit and not observation.cpu_collision
        model.clock(
            observation,
            reset=False,
            ppu_enable=False,
            dot=300,
            scanline=240,
            rendering_enabled=False,
            sprite_size_16=False,
            cpu_oam_addr=address,
            cpu_write_data=address ^ 0xA5,
        )
    assert model.primary_oam == [address ^ 0xA5 for address in range(256)]

    blocked = model.observe(
        reset=False,
        ppu_enable=True,
        dot=100,
        scanline=20,
        rendering_enabled=True,
        sprite_size_16=False,
        cpu_oam_addr=0xFF,
        cpu_write_data=0x11,
        cpu_write_enable=True,
        cpu_access=True,
    )
    assert blocked.cpu_collision and not blocked.cpu_write_commit


def test_secondary_clear_two_dot_cadence_and_stalls() -> None:
    model = SpriteEvaluationModel()
    model.secondary_oam[:] = list(range(32))
    observations = model.run_visible_scanline(30, stalls={2, 17, 64})
    clear_writes = [item for item in observations if item.secondary_clear_write]
    assert len(clear_writes) == 32
    assert [item.secondary_write_address for item in clear_writes] == list(range(32))
    assert all(item.secondary_write_data == 0xFF for item in clear_writes)
    assert model.secondary_oam == [0xFF] * 32


def test_no_sprites_and_single_sprite_indices() -> None:
    scanline = 80
    empty = SpriteEvaluationModel()
    _fill_out_of_range(empty, scanline)
    empty.run_visible_scanline(scanline)
    assert empty.selected_count == 0
    assert empty.secondary_oam == [0xFF] * 32
    assert not empty.sprite_zero_selected
    assert empty.done

    for index in (0, 1, 31, 63):
        model = SpriteEvaluationModel()
        _fill_out_of_range(model, scanline)
        _put_sprite(model, index, scanline)
        expected = tuple(model.primary_oam[index * 4 : index * 4 + 4])
        model.run_visible_scanline(scanline)
        assert model.selected_sprites() == [(index, expected)]
        assert model.sprite_zero_selected is (index == 0)


def test_first_eight_oam_priority_and_sprite_zero_identity() -> None:
    scanline = 50
    in_range = (1, 3, 4, 9, 12, 20, 21, 23, 24, 30)
    model = SpriteEvaluationModel()
    _fill_out_of_range(model, scanline)
    for index in in_range:
        _put_sprite(model, index, scanline)
    model.run_visible_scanline(scanline)
    assert [item[0] for item in model.selected_sprites()] == list(in_range[:8])
    assert model.selected_count == 8
    assert not model.sprite_zero_selected

    zero = SpriteEvaluationModel()
    _fill_out_of_range(zero, scanline)
    for index in (0, 2, 5, 8, 11, 14, 17, 20, 23):
        _put_sprite(zero, index, scanline)
    zero.run_visible_scanline(scanline)
    assert zero.sprite_zero_selected
    assert zero.secondary_indices[0] == 0


def test_eight_vs_sixteen_pixel_boundaries() -> None:
    scanline = 100
    for relative_row, expected_8, expected_16 in (
        (7, True, True),
        (8, False, True),
        (15, False, True),
        (16, False, False),
    ):
        y = (scanline - relative_row) & 0xFF
        assert sprite_in_range(scanline, y, False) is expected_8
        assert sprite_in_range(scanline, y, True) is expected_16


def test_overflow_true_and_diagonal_false_positive() -> None:
    scanline = 90
    true_overflow = SpriteEvaluationModel()
    _fill_out_of_range(true_overflow, scanline)
    for index in range(9):
        _put_sprite(true_overflow, index, scanline)
    true_pulses = _run_and_count_overflow(true_overflow, scanline)
    assert true_pulses == 1
    assert true_overflow.selected_count == 8
    assert true_overflow.phase == EvaluationPhase.DONE
    assert any(
        before == EvaluationPhase.OVERFLOW_SCAN
        for before in _phase_trace(true_overflow.primary_oam, scanline)
    )

    false_positive = SpriteEvaluationModel()
    _fill_out_of_range(false_positive, scanline)
    for index in range(8):
        _put_sprite(false_positive, index, scanline)
    # Sprite 8 Y is out, so the diagonal scan moves to sprite 9 byte 1. That
    # non-Y byte is deliberately in range and falsely raises overflow.
    _put_sprite(false_positive, 9, (scanline + 64) & 0xFF, tile=scanline)
    pulses = _run_and_count_overflow(false_positive, scanline)
    assert pulses == 1
    assert false_positive.selected_count == 8


def test_diagonal_false_negative_vector() -> None:
    scanline = 120
    model = SpriteEvaluationModel()
    _fill_out_of_range(model, scanline)
    for index in range(8):
        _put_sprite(model, index, scanline)
    # First post-full Y is out, advancing to m=1. Sprite 9 is truly in range,
    # but its Y is skipped and its out-of-range tile byte is tested instead.
    _put_sprite(model, 9, scanline, tile=0xF0)
    pulses = _run_and_count_overflow(model, scanline)
    assert pulses == 0
    assert sum(
        sprite_in_range(scanline, model.primary_oam[index * 4], False)
        for index in range(64)
    ) == 9


def test_overflow_tail_advances_m_and_n_before_done() -> None:
    scanline = 90

    ordinary = SpriteEvaluationModel()
    _fill_out_of_range(ordinary, scanline)
    for index in range(9):
        _put_sprite(ordinary, index, scanline)
    assert _run_until_first_done(ordinary, scanline) == (9, 0)

    diagonal = SpriteEvaluationModel()
    _fill_out_of_range(diagonal, scanline)
    for index in range(8):
        _put_sprite(diagonal, index, scanline)
    _put_sprite(diagonal, 9, (scanline + 64) & 0xFF, tile=scanline)
    assert _run_until_first_done(diagonal, scanline) == (10, 1)


def test_rendering_enable_and_scanline_eligibility() -> None:
    for scanline in (240, 241, 260, 261):
        model = SpriteEvaluationModel()
        model.secondary_oam[:] = [0x5A] * 32
        for dot in range(1, 258):
            signals = dict(
                reset=False,
                ppu_enable=True,
                dot=dot,
                scanline=scanline,
                rendering_enabled=True,
                sprite_size_16=False,
                cpu_oam_addr=0,
                cpu_write_data=0,
                cpu_write_enable=False,
                cpu_access=False,
            )
            observation = model.observe(**signals)
            model.clock(observation, **{
                key: signals[key]
                for key in (
                    "reset", "ppu_enable", "dot", "scanline",
                    "rendering_enabled", "sprite_size_16", "cpu_oam_addr",
                    "cpu_write_data",
                )
            })
        assert model.secondary_oam == [0x5A] * 32
        assert model.phase == EvaluationPhase.IDLE

    disabled = SpriteEvaluationModel()
    disabled.secondary_oam[:] = [0x33] * 32
    for dot in range(1, 258):
        signals = dict(
            reset=False,
            ppu_enable=True,
            dot=dot,
            scanline=10,
            rendering_enabled=False,
            sprite_size_16=False,
            cpu_oam_addr=0,
            cpu_write_data=0,
            cpu_write_enable=False,
            cpu_access=False,
        )
        observation = disabled.observe(**signals)
        disabled.clock(observation, **{
            key: signals[key]
            for key in (
                "reset", "ppu_enable", "dot", "scanline",
                "rendering_enabled", "sprite_size_16", "cpu_oam_addr",
                "cpu_write_data",
            )
        })
    assert disabled.secondary_oam == [0x33] * 32


def test_ppu_enable_stalls_preserve_enabled_tick_sequence() -> None:
    scanline = 33
    baseline = SpriteEvaluationModel()
    stalled = SpriteEvaluationModel()
    for model in (baseline, stalled):
        _fill_out_of_range(model, scanline)
        for index in (0, 2, 7, 9, 13, 20, 31, 40, 62):
            _put_sprite(model, index, scanline)
    baseline.run_visible_scanline(scanline)
    stalled.run_visible_scanline(scanline, stalls=set(range(1, 258, 7)))
    assert stalled.secondary_oam == baseline.secondary_oam
    assert stalled.secondary_indices == baseline.secondary_indices
    assert stalled.selected_count == baseline.selected_count
    assert stalled.sprite_zero_selected == baseline.sprite_zero_selected
    assert (stalled.n, stalled.m, stalled.phase, stalled.done) == (
        baseline.n, baseline.m, baseline.phase, baseline.done
    )


def test_full_frame_240_visible_line_results_for_8x8_and_8x16() -> None:
    for size_16 in (False, True):
        model = SpriteEvaluationModel()
        for index in range(64):
            _put_sprite(
                model,
                index,
                (index * 4 - 1) & 0xFF,
                tile=index,
                attributes=index ^ 0xA5,
                x=index * 3,
            )
        checked = 0
        for scanline in range(240):
            model.run_visible_scanline(scanline, sprite_size_16=size_16)
            expected = [
                index
                for index in range(64)
                if sprite_in_range(
                    scanline, model.primary_oam[index * 4], size_16
                )
            ][:8]
            assert [item[0] for item in model.selected_sprites()] == expected
            checked += 1
        assert checked == 240


def _run_and_count_overflow(model: SpriteEvaluationModel, scanline: int) -> int:
    pulses = 0
    for dot in range(1, 258):
        signals = dict(
            reset=False,
            ppu_enable=True,
            dot=dot,
            scanline=scanline,
            rendering_enabled=True,
            sprite_size_16=False,
            cpu_oam_addr=0,
            cpu_write_data=0,
            cpu_write_enable=False,
            cpu_access=False,
        )
        observation = model.observe(**signals)
        model.clock(observation, **{
            key: signals[key]
            for key in (
                "reset", "ppu_enable", "dot", "scanline",
                "rendering_enabled", "sprite_size_16", "cpu_oam_addr",
                "cpu_write_data",
            )
        })
        pulses += int(model.overflow_set)
    return pulses


def _phase_trace(primary_oam: list[int], scanline: int) -> list[EvaluationPhase]:
    model = SpriteEvaluationModel()
    model.primary_oam[:] = primary_oam
    result = []
    for dot in range(1, 258):
        result.append(model.phase)
        signals = dict(
            reset=False,
            ppu_enable=True,
            dot=dot,
            scanline=scanline,
            rendering_enabled=True,
            sprite_size_16=False,
            cpu_oam_addr=0,
            cpu_write_data=0,
            cpu_write_enable=False,
            cpu_access=False,
        )
        observation = model.observe(**signals)
        model.clock(observation, **{
            key: signals[key]
            for key in (
                "reset", "ppu_enable", "dot", "scanline",
                "rendering_enabled", "sprite_size_16", "cpu_oam_addr",
                "cpu_write_data",
            )
        })
    return result


def _run_until_first_done(
    model: SpriteEvaluationModel, scanline: int
) -> tuple[int, int]:
    for dot in range(1, 257):
        signals = dict(
            reset=False,
            ppu_enable=True,
            dot=dot,
            scanline=scanline,
            rendering_enabled=True,
            sprite_size_16=False,
            cpu_oam_addr=0,
            cpu_write_data=0,
            cpu_write_enable=False,
            cpu_access=False,
        )
        observation = model.observe(**signals)
        was_done = model.done
        model.clock(observation, **{
            key: signals[key]
            for key in (
                "reset", "ppu_enable", "dot", "scanline",
                "rendering_enabled", "sprite_size_16", "cpu_oam_addr",
                "cpu_write_data",
            )
        })
        if model.done and not was_done:
            return model.n, model.m
    raise AssertionError("evaluation did not enter DONE by dot 256")
