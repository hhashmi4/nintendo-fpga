"""Directed Phase 5D tests for Triangle and three-channel integration."""

import pytest

from verification.apu import (
    APU_STATUS,
    HALF_1,
    LENGTH_TABLE,
    PULSE_DUTY_TABLE,
    QUARTER_1,
    TRIANGLE_SEQUENCE,
    ApuFoundationModel,
    ApuInputs,
    TriangleInputs,
    TriangleModel,
    triangle_frequency_hz,
    triangle_sequence_cpu_cycles,
)


def triangle_cycle(model: TriangleModel, **kwargs: object):
    values: dict[str, object] = {"cpu_cycle_enable": True, "enable": True}
    values.update(kwargs)
    inputs = TriangleInputs(**values)
    model.clock(inputs)
    return model.evaluate(), model.state()


def triangle_write(
    model: TriangleModel, register: int, data: int, *, enable: bool = True
):
    return triangle_cycle(
        model,
        enable=enable,
        write=True,
        write_register=register,
        write_data=data,
    )


def apu_cycle(model: ApuFoundationModel, **kwargs: object):
    return model.clock(ApuInputs(cpu_cycle_enable=True, **kwargs))


def apu_write(model: ApuFoundationModel, address: int, data: int) -> None:
    apu_cycle(model, cpu_write=True, cpu_address=address, cpu_write_data=data)


def program_triangle(
    model: ApuFoundationModel,
    *,
    timer: int = 2,
    reload_value: int = 127,
    control: bool = True,
    length_index: int = 0,
) -> None:
    apu_write(
        model,
        0x4008,
        (0x80 if control else 0) | reload_value,
    )
    apu_write(model, 0x400A, timer & 0xFF)
    apu_write(model, 0x400B, (length_index << 3) | (timer >> 8))


def test_4008_decodes_control_and_linear_reload_value() -> None:
    model = TriangleModel()
    _, state = triangle_write(model, 0, 0xD5)
    assert state.control_flag
    assert state.linear_reload_value == 0x55


def test_400a_preserves_triangle_timer_high_bits() -> None:
    model = TriangleModel()
    model.timer_period = 0x700
    _, state = triangle_write(model, 2, 0xA5)
    assert state.timer_period == 0x7A5


def test_400b_sets_high_timer_length_and_reload_flag_without_phase_reset() -> None:
    model = TriangleModel()
    model.timer_period = 0x0A5
    model.timer_counter = 0x123
    model.sequence_position = 19
    _, state = triangle_write(model, 3, (9 << 3) | 0x03)
    assert state.timer_period == 0x3A5
    assert state.timer_counter == 0x122
    assert state.sequence_position == 19
    assert state.length_counter == LENGTH_TABLE[9]
    assert state.linear_reload_flag


def test_4009_is_reserved_and_does_not_change_triangle_register_state() -> None:
    model = TriangleModel()
    model.control_flag = True
    model.linear_reload_value = 43
    model.linear_counter = 17
    model.linear_reload_flag = True
    model.sequence_position = 12
    model.timer_period = 0x456
    model.timer_counter = 22
    model.length_counter = 31
    before = model.state()
    _, after = triangle_write(model, 1, 0xFF)
    assert after == before.__class__(
        **{**before.__dict__, "timer_counter": before.timer_counter - 1}
    )


@pytest.mark.parametrize("position, expected", enumerate(TRIANGLE_SEQUENCE))
def test_all_32_triangle_dac_positions(position: int, expected: int) -> None:
    model = TriangleModel()
    model.sequence_position = position
    assert model.evaluate().raw_output == expected


def test_timer_reloads_decrements_and_advances_once_per_period() -> None:
    model = TriangleModel()
    model.timer_period = 3
    model.timer_counter = 0
    model.length_counter = 1
    model.linear_counter = 1
    _, state = triangle_cycle(model)
    assert (state.timer_counter, state.sequence_position) == (3, 1)
    for expected in (2, 1, 0):
        _, state = triangle_cycle(model)
        assert (state.timer_counter, state.sequence_position) == (expected, 1)
    _, state = triangle_cycle(model)
    assert (state.timer_counter, state.sequence_position) == (3, 2)


def test_triangle_timer_clocks_on_every_cpu_slot_not_every_other_slot() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x04
    model.triangle.timer_period = 7
    model.triangle.timer_counter = 7
    for expected in range(6, -1, -1):
        apu_cycle(model)
        assert model.triangle.timer_counter == expected


def test_linear_reload_occurs_once_on_quarter_frame_and_then_decrements() -> None:
    model = TriangleModel()
    triangle_write(model, 0, 6)
    triangle_write(model, 3, 0)
    _, state = triangle_cycle(model, quarter_frame_tick=True)
    assert state.linear_counter == 6
    assert not state.linear_reload_flag
    _, state = triangle_cycle(model, quarter_frame_tick=True)
    assert state.linear_counter == 5


def test_control_zero_clears_reload_flag_after_quarter_frame() -> None:
    model = TriangleModel()
    triangle_write(model, 0, 0x23)
    triangle_write(model, 3, 0)
    _, state = triangle_cycle(model, quarter_frame_tick=True)
    assert state.linear_counter == 0x23
    assert not state.linear_reload_flag


def test_control_one_preserves_reload_flag_and_reloads_each_quarter_frame() -> None:
    model = TriangleModel()
    triangle_write(model, 0, 0x80 | 7)
    triangle_write(model, 3, 0)
    for _ in range(3):
        model.linear_counter = 1
        _, state = triangle_cycle(model, quarter_frame_tick=True)
        assert state.linear_counter == 7
        assert state.linear_reload_flag


def test_zero_linear_counter_does_not_underflow() -> None:
    model = TriangleModel()
    _, state = triangle_cycle(model, quarter_frame_tick=True)
    assert state.linear_counter == 0


@pytest.mark.parametrize("index, expected", enumerate(LENGTH_TABLE))
def test_all_triangle_length_indices_use_shared_table(index: int, expected: int) -> None:
    model = TriangleModel()
    _, state = triangle_write(model, 3, index << 3)
    assert state.length_counter == expected


def test_length_decrements_on_half_frame_and_control_halts_it() -> None:
    model = TriangleModel()
    model.length_counter = 3
    _, state = triangle_cycle(
        model, quarter_frame_tick=True, half_frame_tick=True
    )
    assert state.length_counter == 2
    triangle_write(model, 0, 0x80)
    _, state = triangle_cycle(
        model, quarter_frame_tick=True, half_frame_tick=True
    )
    assert state.length_counter == 2


def test_coincident_quarter_and_half_updates_both_triangle_counters_once() -> None:
    model = TriangleModel()
    model.length_counter = 4
    model.linear_counter = 5
    _, state = triangle_cycle(
        model, quarter_frame_tick=True, half_frame_tick=True
    )
    assert (state.length_counter, state.linear_counter) == (3, 4)


def test_disabled_400b_does_not_load_length_but_sets_reload_flag() -> None:
    model = TriangleModel()
    _, state = triangle_write(model, 3, 0xF8, enable=False)
    assert state.length_counter == 0
    assert state.linear_reload_flag


def test_4015_triangle_disable_clears_length_and_enable_does_not_reload() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x04)
    program_triangle(model, length_index=1)
    assert model.triangle.length_counter == LENGTH_TABLE[1]
    apu_write(model, APU_STATUS, 0x00)
    assert model.triangle.length_counter == 0
    apu_write(model, APU_STATUS, 0x04)
    assert model.triangle.length_counter == 0


@pytest.mark.parametrize("mask", range(8))
def test_4015_reports_all_pulse_and_triangle_status_combinations(mask: int) -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, mask)
    apu_write(model, 0x4003, 0)
    apu_write(model, 0x4007, 0)
    apu_write(model, 0x400B, 0)
    outputs, _ = apu_cycle(model, cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x07 == mask


@pytest.mark.parametrize("length, linear", [(0, 1), (1, 0)])
def test_either_zero_counter_stops_sequencer_but_timer_continues(
    length: int, linear: int
) -> None:
    model = TriangleModel()
    model.timer_period = 2
    model.timer_counter = 0
    model.sequence_position = 9
    model.length_counter = length
    model.linear_counter = linear
    _, state = triangle_cycle(model)
    assert state.timer_counter == 2
    assert state.sequence_position == 9


def test_stopped_triangle_holds_nonzero_dac_value_instead_of_forcing_zero() -> None:
    model = TriangleModel()
    model.sequence_position = 5
    model.length_counter = 0
    model.linear_counter = 0
    held = TRIANGLE_SEQUENCE[5]
    for _ in range(100):
        outputs, state = triangle_cycle(model)
        assert outputs.raw_output == held
        assert state.sequence_position == 5


@pytest.mark.parametrize("timer", [0, 1, 2, 7, 8])
def test_small_triangle_periods_advance_without_pulse_mute_rule(timer: int) -> None:
    model = TriangleModel()
    model.timer_period = timer
    model.length_counter = 1
    model.linear_counter = 1
    observed = []
    for _ in range(2 * (timer + 1)):
        triangle_cycle(model)
        observed.append(model.evaluate().raw_output)
    assert model.sequence_position == 2
    assert observed[-1] == TRIANGLE_SEQUENCE[2]


def test_three_channels_run_simultaneously_with_independent_periods() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x07
    for pulse, duty, volume, timer in (
        (model.pulse1, 3, 15, 8),
        (model.pulse2, 2, 9, 10),
    ):
        pulse.duty = duty
        pulse.constant_volume = True
        pulse.envelope_period = volume
        pulse.timer_period = timer
        pulse.length_counter = 20
    model.triangle.timer_period = 3
    model.triangle.length_counter = 20
    model.triangle.linear_counter = 20
    for _ in range(200):
        apu_cycle(model)
    assert model.pulse1.duty_position != 0
    assert model.pulse2.duty_position != 0
    assert model.triangle.sequence_position != 0
    assert model.pulse1.evaluate(True).raw_output in (0, 15)
    assert model.pulse2.evaluate(True).raw_output in (0, 9)
    assert model.triangle.evaluate().raw_output in TRIANGLE_SEQUENCE


def test_pulse_and_triangle_register_banks_are_isolated() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x07
    triangle_before = model.triangle.state()
    for address, data in zip(range(0x4000, 0x4008), range(0x80, 0x88)):
        apu_write(model, address, data)
    after_pulses = model.triangle.state()
    assert after_pulses.control_flag == triangle_before.control_flag
    assert after_pulses.linear_reload_value == triangle_before.linear_reload_value
    assert after_pulses.timer_period == triangle_before.timer_period
    pulse1_before = model.pulse1.state()
    pulse2_before = model.pulse2.state()
    for address, data in ((0x4008, 0xD5), (0x4009, 0xFF), (0x400A, 0x56), (0x400B, 0x23)):
        apu_write(model, address, data)
    assert model.pulse1.state() == pulse1_before.__class__(
        **{**pulse1_before.__dict__, "timer_counter": model.pulse1.timer_counter,
           "duty_position": model.pulse1.duty_position}
    )
    assert model.pulse2.state() == pulse2_before.__class__(
        **{**pulse2_before.__dict__, "timer_counter": model.pulse2.timer_counter,
           "duty_position": model.pulse2.duty_position}
    )


def test_debugger_pause_freezes_all_triangle_state_and_ignores_held_write() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x04
    model.triangle.timer_period = 9
    model.triangle.timer_counter = 4
    model.triangle.sequence_position = 7
    model.triangle.linear_counter = 11
    model.triangle.length_counter = 13
    model.triangle.linear_reload_flag = True
    before = model.triangle.state()
    apu_before = model.state()
    held = ApuInputs(
        cpu_cycle_enable=False,
        cpu_write=True,
        cpu_address=0x400B,
        cpu_write_data=0xFF,
    )
    for _ in range(4_096):
        model.clock(held)
    assert model.triangle.state() == before
    assert model.state() == apu_before


def test_debugger_step_accepts_triangle_write_and_frame_tick_exactly_once() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x04
    model.frame_sequence_cycle = QUARTER_1 - 1
    outputs, _ = model.clock(
        ApuInputs(
            cpu_cycle_enable=True,
            cpu_write=True,
            cpu_address=0x400B,
            cpu_write_data=0x08,
        )
    )
    assert outputs.quarter_frame_tick
    assert model.triangle.length_counter == LENGTH_TABLE[1]
    assert model.triangle.linear_reload_flag
    after = model.triangle.state()
    for _ in range(100):
        model.clock(ApuInputs(cpu_cycle_enable=False))
    assert model.triangle.state() == after


def test_dma_cpu_slots_continue_all_three_channel_timers() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x07
    for pulse, timer in ((model.pulse1, 8), (model.pulse2, 10)):
        pulse.timer_period = timer
        pulse.length_counter = 1
    model.triangle.timer_period = 6
    model.triangle.length_counter = 1
    model.triangle.linear_counter = 1
    for _ in range(500):
        apu_cycle(model)
    assert model.pulse1.duty_position != 0
    assert model.pulse2.duty_position != 0
    assert model.triangle.sequence_position != 0


def test_reset_clears_every_triangle_register_counter_flag_and_phase() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x04
    triangle = model.triangle
    triangle.control_flag = True
    triangle.linear_reload_value = 99
    triangle.linear_counter = 71
    triangle.linear_reload_flag = True
    triangle.sequence_position = 23
    triangle.timer_period = 0x7AB
    triangle.timer_counter = 0x456
    triangle.length_counter = 88
    model.clock(ApuInputs(reset=True, cpu_cycle_enable=True))
    assert model.triangle.state() == TriangleModel().state()
    assert model.triangle.evaluate().raw_output == 15
    assert model.state().channel_enable == 0


def test_real_frame_quarter_and_half_events_update_triangle() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x04
    model.triangle.linear_counter = 5
    model.triangle.length_counter = 7
    model.frame_sequence_cycle = HALF_1 - 1
    outputs, _ = apu_cycle(model)
    assert outputs.quarter_frame_tick and outputs.half_frame_tick
    assert model.triangle.linear_counter == 4
    assert model.triangle.length_counter == 6


@pytest.mark.parametrize("timer", [0, 1, 2, 31, 254, 0x7FF])
def test_triangle_frequency_sanity_uses_cpu_rate_and_32_steps(timer: int) -> None:
    expected_cycles = 32 * (timer + 1)
    assert triangle_sequence_cpu_cycles(timer) == expected_cycles
    assert triangle_frequency_hz(timer) == pytest.approx(
        1_789_773.0 / expected_cycles
    )


def test_exact_waveform_descends_bottom_turns_ascends_and_wraps() -> None:
    model = TriangleModel()
    model.timer_period = 0
    model.length_counter = 1
    model.linear_counter = 1
    observed = [model.evaluate().raw_output]
    for _ in range(32):
        triangle_cycle(model)
        observed.append(model.evaluate().raw_output)
    assert observed == list(TRIANGLE_SEQUENCE) + [TRIANGLE_SEQUENCE[0]]
    assert observed[14:19] == [1, 0, 0, 1, 2]
    assert observed[-2:] == [15, 15]
