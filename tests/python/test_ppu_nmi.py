from verification.ppu_nmi import PpuNmiInputs, PpuNmiModel


def tick(model: PpuNmiModel, **kwargs: object):
    return model.clock(PpuNmiInputs(**kwargs))


def begin_vblank(model: PpuNmiModel, *, enable: bool = True):
    tick(model, control_write=True, control_nmi_enable=enable)
    return tick(
        model,
        ppu_enable=True,
        scanline=241,
        dot=1,
        vblank_start=True,
    )


def test_normal_vblank_generates_one_qualified_event() -> None:
    model = PpuNmiModel()
    start = begin_vblank(model)
    assert start.status_vblank and start.nmi_level and not start.nmi_event

    qualified = tick(model, ppu_enable=True, scanline=241, dot=2)
    assert qualified.nmi_event
    for dot in range(3, 40):
        assert not tick(model, ppu_enable=True, scanline=241, dot=dot).nmi_event


def test_vblank_exists_when_nmi_is_disabled() -> None:
    model = PpuNmiModel()
    start = begin_vblank(model, enable=False)
    assert start.status_vblank
    assert not start.nmi_level and not start.nmi_event
    assert not tick(model, ppu_enable=True, scanline=241, dot=2).nmi_event


def test_enable_during_vblank_is_immediate_and_not_level_retriggered() -> None:
    model = PpuNmiModel()
    begin_vblank(model, enable=False)
    assert tick(
        model, control_write=True, control_nmi_enable=True
    ).nmi_event
    assert not tick(
        model, control_write=True, control_nmi_enable=True
    ).nmi_event


def test_disable_and_reenable_can_create_multiple_events() -> None:
    model = PpuNmiModel()
    begin_vblank(model, enable=False)
    for _ in range(4):
        assert tick(
            model, control_write=True, control_nmi_enable=True
        ).nmi_event
        disabled = tick(model, control_write=True, control_nmi_enable=False)
        assert not disabled.nmi_level and not disabled.nmi_event


def test_status_read_returns_old_flag_then_clears_only_condition() -> None:
    model = PpuNmiModel()
    begin_vblank(model, enable=False)
    result = tick(model, status_read=True, scanline=241, dot=20)
    assert result.status_read_bit
    assert not result.status_vblank and not result.nmi_level


def run_boundary_read(offset: int):
    """Exercise coordinates -2 through +2 around the 241:1 set tick."""

    coordinates = ((240, 340), (241, 0), (241, 1), (241, 2), (241, 3))
    model = PpuNmiModel()
    tick(model, control_write=True, control_nmi_enable=True)
    read_bit = None
    event_count = 0

    for position, (scanline, dot) in enumerate(coordinates, start=-2):
        is_read = position == offset
        observation = tick(
            model,
            ppu_enable=True,
            scanline=scanline,
            dot=dot,
            vblank_start=(scanline, dot) == (241, 1),
            status_read=is_read,
        )
        if is_read:
            read_bit = observation.status_read_bit
        event_count += int(observation.nmi_event)

    return read_bit, model.status_vblank, model.nmi_level, event_count


def test_boundary_read_window_is_explicit() -> None:
    assert run_boundary_read(-2) == (False, True, True, 1)
    assert run_boundary_read(-1) == (False, False, False, 0)
    assert run_boundary_read(0) == (False, False, False, 0)
    assert run_boundary_read(1) == (True, False, False, 0)
    assert run_boundary_read(2) == (True, False, False, 1)


def test_pending_ordinary_event_waits_for_enabled_ppu_tick() -> None:
    model = PpuNmiModel()
    begin_vblank(model)
    for _ in range(8):
        stalled = tick(model, ppu_enable=False, scanline=241, dot=2)
        assert stalled.nmi_level and not stalled.nmi_event
    assert tick(model, ppu_enable=True, scanline=241, dot=2).nmi_event


def test_status_read_during_stalled_post_set_coordinate_suppresses() -> None:
    model = PpuNmiModel()
    begin_vblank(model)
    result = tick(
        model,
        ppu_enable=False,
        scanline=241,
        dot=2,
        status_read=True,
    )
    assert result.status_read_bit and result.nmi_suppressed
    assert not result.status_vblank and not result.nmi_event


def test_pre_render_clear_rearms_next_frame() -> None:
    model = PpuNmiModel()
    begin_vblank(model)
    assert tick(model, ppu_enable=True, scanline=241, dot=2).nmi_event
    cleared = tick(
        model,
        ppu_enable=True,
        scanline=261,
        dot=1,
        status_clear=True,
    )
    assert not cleared.status_vblank and not cleared.nmi_level
    begin_vblank(model)
    assert tick(model, ppu_enable=True, scanline=241, dot=2).nmi_event


def test_enable_write_on_vblank_set_uses_ordinary_qualified_event() -> None:
    model = PpuNmiModel()
    started = tick(
        model,
        ppu_enable=True,
        scanline=241,
        dot=1,
        vblank_start=True,
        control_write=True,
        control_nmi_enable=True,
    )
    assert started.status_vblank and started.nmi_enable and started.nmi_level
    assert not started.nmi_event
    assert tick(model, ppu_enable=True, scanline=241, dot=2).nmi_event


def test_pre_render_clear_wins_over_same_edge_enable_write() -> None:
    model = PpuNmiModel()
    begin_vblank(model, enable=False)
    cleared = tick(
        model,
        ppu_enable=True,
        scanline=261,
        dot=1,
        status_clear=True,
        control_write=True,
        control_nmi_enable=True,
    )
    assert cleared.nmi_enable
    assert not cleared.status_vblank
    assert not cleared.nmi_level
    assert not cleared.nmi_event


def test_reset_cannot_emit_spurious_nmi() -> None:
    model = PpuNmiModel()
    begin_vblank(model)
    observation = tick(model, reset=True)
    assert not observation.status_vblank
    assert not observation.nmi_enable
    assert not observation.nmi_level
    assert not observation.nmi_event
