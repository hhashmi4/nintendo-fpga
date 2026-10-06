"""Directed Phase 5C tests for Pulse 2 and dual-pulse integration."""

import pytest

from verification.apu import (
    APU_STATUS,
    HALF_1,
    LENGTH_TABLE,
    PULSE_DUTY_TABLE,
    QUARTER_1,
    ApuFoundationModel,
    ApuInputs,
    Pulse1Model,
    Pulse2Model,
    PulseInputs,
    pulse_frequency_hz,
    pulse_sequence_cpu_cycles,
)


def pulse_cycle(model: Pulse2Model, **kwargs: object):
    values: dict[str, object] = {"cpu_cycle_enable": True, "enable": True}
    values.update(kwargs)
    inputs = PulseInputs(**values)
    model.clock(inputs)
    return model.evaluate(inputs.enable), model.state()


def pulse_write(model: Pulse2Model, register: int, data: int, *, enable: bool = True):
    return pulse_cycle(
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


def program_pulse2(
    model: Pulse2Model,
    *,
    timer: int = 8,
    duty: int = 3,
    volume: int = 15,
    length_index: int = 0,
) -> None:
    pulse_write(model, 0, (duty << 6) | 0x10 | volume)
    pulse_write(model, 2, timer & 0xFF)
    pulse_write(model, 3, (length_index << 3) | (timer >> 8))


def test_4004_decodes_all_pulse2_control_fields() -> None:
    model = Pulse2Model()
    _, state = pulse_write(model, 0, 0xEF)
    assert state.duty == 3
    assert state.length_halt
    assert not state.constant_volume
    assert state.envelope_period == 15


def test_4005_decodes_all_pulse2_sweep_fields_and_requests_reload() -> None:
    model = Pulse2Model()
    _, state = pulse_write(model, 1, 0xFD)
    assert state.sweep_enabled
    assert state.sweep_period == 7
    assert state.sweep_negate
    assert state.sweep_shift == 5
    assert state.sweep_reload


def test_4006_preserves_pulse2_timer_high_bits() -> None:
    model = Pulse2Model()
    model.timer_period = 0x700
    _, state = pulse_write(model, 2, 0xA5)
    assert state.timer_period == 0x7A5


def test_4007_loads_length_preserves_low_timer_and_restarts_units() -> None:
    model = Pulse2Model()
    model.timer_period = 0x0A5
    model.timer_counter = 0x123
    model.duty_position = 5
    _, state = pulse_write(model, 3, (9 << 3) | 0x03)
    assert state.timer_period == 0x3A5
    assert state.timer_counter == 0x123
    assert state.duty_position == 0
    assert state.envelope_start
    assert state.length_counter == LENGTH_TABLE[9]


@pytest.mark.parametrize("duty", range(4))
def test_pulse2_all_duty_modes_cover_all_eight_positions(duty: int) -> None:
    model = Pulse2Model()
    program_pulse2(model, duty=duty, volume=13)
    for position, expected in enumerate(PULSE_DUTY_TABLE[duty]):
        model.duty_position = position
        assert model.evaluate(True).raw_output == 13 * expected


def test_pulse2_timer_reload_decrement_and_sequence_advance() -> None:
    model = Pulse2Model()
    model.timer_period = 8
    model.timer_counter = 0
    model.duty_position = 0
    _, state = pulse_cycle(model, timer_tick=True)
    assert (state.timer_counter, state.duty_position) == (8, 7)
    for expected in range(7, -1, -1):
        _, state = pulse_cycle(model, timer_tick=True)
        assert (state.timer_counter, state.duty_position) == (expected, 7)
    _, state = pulse_cycle(model, timer_tick=True)
    assert (state.timer_counter, state.duty_position) == (8, 6)


def test_pulse2_constant_volume_and_envelope_decay_loop_restart() -> None:
    model = Pulse2Model()
    program_pulse2(model, duty=3, volume=9)
    model.duty_position = 0
    model.envelope_decay = 2
    assert model.evaluate(True).raw_output == 9

    pulse_write(model, 0, 0x22)
    pulse_write(model, 3, 0x00)
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert not state.envelope_start
    assert (state.envelope_decay, state.envelope_divider) == (15, 2)
    for _ in range(3):
        _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert (state.envelope_decay, state.envelope_divider) == (14, 2)
    model.envelope_decay = 0
    model.envelope_divider = 0
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 15


def test_pulse2_length_half_frame_halt_disable_and_reenable() -> None:
    model = Pulse2Model()
    program_pulse2(model, length_index=3)
    assert model.state().length_counter == LENGTH_TABLE[3]
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.length_counter == LENGTH_TABLE[3] - 1
    pulse_write(model, 0, 0x20)
    before = model.state().length_counter
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.length_counter == before
    _, state = pulse_cycle(model, enable=False)
    assert state.length_counter == 0
    _, state = pulse_cycle(model, enable=True)
    assert state.length_counter == 0


def test_pulse2_positive_sweep_updates_to_target() -> None:
    model = Pulse2Model()
    model.timer_period = 0x100
    model.sweep_enabled = True
    model.sweep_shift = 1
    model.sweep_period = 3
    model.sweep_divider = 0
    assert model.sweep_target() == 0x180
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.timer_period == 0x180


def test_pulse2_negative_sweep_uses_twos_complement_rule() -> None:
    model = Pulse2Model()
    model.timer_period = 0x100
    model.sweep_enabled = True
    model.sweep_negate = True
    model.sweep_shift = 1
    model.sweep_divider = 0
    assert model.sweep_target() == 0x080
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.timer_period == 0x080


def test_pulse1_vs_pulse2_negate_differential_is_exactly_one() -> None:
    pulse1 = Pulse1Model()
    pulse2 = Pulse2Model()
    for pulse in (pulse1, pulse2):
        pulse.timer_period = 0x100
        pulse.sweep_enabled = True
        pulse.sweep_negate = True
        pulse.sweep_shift = 1
        pulse.sweep_divider = 0
    assert pulse2.sweep_target() - pulse1.sweep_target() == 1
    inputs = PulseInputs(
        cpu_cycle_enable=True,
        timer_tick=False,
        enable=True,
        quarter_frame_tick=True,
        half_frame_tick=True,
    )
    pulse1.clock(inputs)
    pulse2.clock(inputs)
    assert pulse1.state().timer_period == 0x07F
    assert pulse2.state().timer_period == 0x080
    assert pulse2.state().timer_period - pulse1.state().timer_period == 1


def test_pulse2_positive_overflow_and_minimum_timer_mute() -> None:
    model = Pulse2Model()
    model.timer_period = 7
    assert model.sweep_mute()
    model.timer_period = 0x556
    model.sweep_shift = 1
    model.sweep_negate = False
    assert model.sweep_target() == 0x801
    assert model.sweep_mute()


@pytest.mark.parametrize(
    "enable,length,position,timer,overflow,expected",
    [
        (False, 1, 0, 8, False, 0),
        (True, 0, 0, 8, False, 0),
        (True, 1, 7, 8, False, 0),
        (True, 1, 0, 7, False, 0),
        (True, 1, 0, 0x600, True, 0),
        (True, 1, 0, 8, False, 11),
    ],
)
def test_pulse2_output_gating(
    enable: bool,
    length: int,
    position: int,
    timer: int,
    overflow: bool,
    expected: int,
) -> None:
    model = Pulse2Model()
    model.length_counter = length
    model.duty = 3
    model.duty_position = position
    model.timer_period = timer
    model.sweep_shift = 1 if overflow else 0
    model.constant_volume = True
    model.envelope_period = 11
    assert model.evaluate(enable).raw_output == expected


def test_4000_through_4003_and_4004_through_4007_are_isolated() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x03)
    pulse2_before = model.pulse2.state()
    for register, data in enumerate((0xDF, 0xB9, 0x34, 0x28)):
        apu_write(model, 0x4000 + register, data)
    pulse2_after = model.pulse2.state()
    assert (
        pulse2_after.duty,
        pulse2_after.timer_period,
        pulse2_after.length_counter,
        pulse2_after.envelope_period,
        pulse2_after.sweep_enabled,
    ) == (
        pulse2_before.duty,
        pulse2_before.timer_period,
        pulse2_before.length_counter,
        pulse2_before.envelope_period,
        pulse2_before.sweep_enabled,
    )

    pulse1_before = model.pulse1.state()
    for register, data in enumerate((0x9A, 0xE9, 0x78, 0x18)):
        apu_write(model, 0x4004 + register, data)
    pulse1_after = model.pulse1.state()
    assert (
        pulse1_after.duty,
        pulse1_after.timer_period,
        pulse1_after.length_counter,
        pulse1_after.envelope_period,
        pulse1_after.sweep_enabled,
    ) == (
        pulse1_before.duty,
        pulse1_before.timer_period,
        pulse1_before.length_counter,
        pulse1_before.envelope_period,
        pulse1_before.sweep_enabled,
    )
    assert model.pulse2.state().duty == 2
    assert model.pulse2.state().timer_period == 0x078


@pytest.mark.parametrize("mask", range(4))
def test_4015_enable_and_status_all_pulse_combinations(mask: int) -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, mask)
    apu_write(model, 0x4003, 0x00)
    apu_write(model, 0x4007, 0x00)
    outputs, _ = apu_cycle(model, cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x03 == mask
    assert model.pulse1.state().length_counter == (LENGTH_TABLE[0] if mask & 1 else 0)
    assert model.pulse2.state().length_counter == (LENGTH_TABLE[0] if mask & 2 else 0)


def test_disabling_one_pulse_does_not_clear_the_other_length() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x03)
    apu_write(model, 0x4003, 0x00)
    apu_write(model, 0x4007, 0x08)
    pulse2_length = model.pulse2.state().length_counter
    apu_write(model, APU_STATUS, 0x02)
    assert model.pulse1.state().length_counter == 0
    assert model.pulse2.state().length_counter == pulse2_length


def test_shared_quarter_tick_clocks_independent_envelopes() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    model.frame_sequence_cycle = QUARTER_1 - 1
    model.pulse1.envelope_start = True
    model.pulse1.envelope_period = 2
    model.pulse2.envelope_start = False
    model.pulse2.envelope_period = 5
    model.pulse2.envelope_decay = 9
    model.pulse2.envelope_divider = 0
    outputs, _ = apu_cycle(model)
    assert outputs.quarter_frame_tick and not outputs.half_frame_tick
    assert (model.pulse1.envelope_decay, model.pulse1.envelope_divider) == (15, 2)
    assert (model.pulse2.envelope_decay, model.pulse2.envelope_divider) == (8, 5)


def test_shared_half_tick_clocks_independent_lengths_and_sweeps() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    model.frame_sequence_cycle = HALF_1 - 1
    model.pulse1.length_counter = 4
    model.pulse2.length_counter = 7
    model.pulse1.timer_period = 0x100
    model.pulse2.timer_period = 0x180
    for pulse in (model.pulse1, model.pulse2):
        pulse.sweep_enabled = True
        pulse.sweep_shift = 1
        pulse.sweep_divider = 0
    outputs, _ = apu_cycle(model)
    assert outputs.quarter_frame_tick and outputs.half_frame_tick
    assert (model.pulse1.length_counter, model.pulse2.length_counter) == (3, 6)
    assert (model.pulse1.timer_period, model.pulse2.timer_period) == (0x180, 0x240)


def test_dual_pulse_exact_simultaneous_waveforms_with_different_periods() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    for pulse, duty, volume, timer in (
        (model.pulse1, 0, 15, 8),
        (model.pulse2, 2, 8, 10),
    ):
        pulse.duty = duty
        pulse.duty_position = 0
        pulse.timer_period = timer
        pulse.timer_counter = 0
        pulse.length_counter = 1
        pulse.constant_volume = True
        pulse.envelope_period = volume

    observed: list[tuple[int, int]] = []
    for slot in range(200):
        apu_cycle(model)
        tick_count = slot // 2 + 1
        expected = []
        for duty, volume, timer in ((0, 15, 8), (2, 8, 10)):
            steps = ((tick_count - 1) // (timer + 1)) + 1
            position = (-steps) & 7
            expected.append(volume * PULSE_DUTY_TABLE[duty][position])
        pair = (
            model.pulse1.evaluate(True).raw_output,
            model.pulse2.evaluate(True).raw_output,
        )
        assert pair == tuple(expected)
        observed.append(pair)
    assert (15, 0) in observed
    assert (0, 8) in observed
    assert (15, 8) in observed


def test_debugger_pause_freezes_both_channels_and_resume_is_deterministic() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    model.pulse1.timer_period = 8
    model.pulse1.timer_counter = 0
    model.pulse1.length_counter = 3
    model.pulse2.timer_period = 10
    model.pulse2.timer_counter = 0
    model.pulse2.length_counter = 4
    pulse1_before = model.pulse1.state()
    pulse2_before = model.pulse2.state()
    apu_before = model.state()
    held = ApuInputs(
        cpu_cycle_enable=False,
        cpu_write=True,
        cpu_address=0x4007,
        cpu_write_data=0xFF,
    )
    for _ in range(4_096):
        model.clock(held)
    assert model.pulse1.state() == pulse1_before
    assert model.pulse2.state() == pulse2_before
    assert model.state() == apu_before
    apu_cycle(model)
    assert model.pulse1.state().duty_position == 7
    assert model.pulse2.state().duty_position == 7


@pytest.mark.parametrize(
    ("address", "selected"), ((0x4003, "pulse1"), (0x4007, "pulse2"))
)
def test_debugger_single_step_accepts_each_pulse_write_once(
    address: int, selected: str
) -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    model.frame_sequence_cycle = QUARTER_1 - 1
    step = ApuInputs(
        cpu_cycle_enable=True,
        cpu_write=True,
        cpu_address=address,
        cpu_write_data=0x08,
    )
    outputs, state = model.clock(step)
    channel = getattr(model, selected)
    assert outputs.quarter_frame_tick
    assert state.frame_sequence_cycle == QUARTER_1
    assert channel.state().length_counter == LENGTH_TABLE[1]

    pulse1_after_step = model.pulse1.state()
    pulse2_after_step = model.pulse2.state()
    apu_after_step = model.state()
    held_while_paused = ApuInputs(
        cpu_cycle_enable=False,
        cpu_write=True,
        cpu_address=address,
        cpu_write_data=0xF8,
    )
    for _ in range(256):
        model.clock(held_while_paused)
    assert model.pulse1.state() == pulse1_after_step
    assert model.pulse2.state() == pulse2_after_step
    assert model.state() == apu_after_step


def test_dma_cpu_slots_continue_both_timers_without_register_writes() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    for pulse, timer in ((model.pulse1, 8), (model.pulse2, 10)):
        pulse.timer_period = timer
        pulse.timer_counter = 0
        pulse.duty_position = 0
        pulse.length_counter = 1
    for _ in range(64):
        apu_cycle(model)
    assert model.pulse1.duty_position == 4
    assert model.pulse2.duty_position == 5
    assert model.pulse1.timer_counter != model.pulse2.timer_counter


def test_reset_clears_both_channels_from_distinct_active_states() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 3
    model.pulse1.timer_period = 0x180
    model.pulse1.length_counter = 7
    model.pulse1.envelope_decay = 4
    model.pulse1.sweep_enabled = True
    model.pulse2.timer_period = 0x250
    model.pulse2.length_counter = 11
    model.pulse2.envelope_decay = 9
    model.pulse2.sweep_reload = True
    model.clock(ApuInputs(reset=True, cpu_cycle_enable=True))
    assert model.pulse1.state() == Pulse1Model().state()
    assert model.pulse2.state() == Pulse2Model().state()
    assert model.state().channel_enable == 0


def test_pulse2_frequency_sanity_uses_the_shared_integer_timer_relation() -> None:
    assert pulse_sequence_cpu_cycles(10) == 176
    assert pulse_frequency_hz(10) == pytest.approx(1_789_773.0 / 176)
