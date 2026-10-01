"""Directed Phase 5B tests for the independent Pulse 1 model."""

import math

import pytest

from verification.apu import (
    APU_STATUS,
    LENGTH_TABLE,
    PULSE_DUTY_TABLE,
    ApuFoundationModel,
    ApuInputs,
    Pulse1Model,
    PulseInputs,
    pulse_frequency_hz,
    pulse_sequence_cpu_cycles,
)


def pulse_cycle(model: Pulse1Model, **kwargs: object):
    """Clock one accepted CPU slot, with the channel enabled by default."""

    values: dict[str, object] = {
        "cpu_cycle_enable": True,
        "enable": True,
    }
    values.update(kwargs)
    inputs = PulseInputs(**values)
    _, state = model.clock(inputs)
    return model.evaluate(inputs.enable), state


def pulse_write(model: Pulse1Model, register: int, data: int, *, enable: bool = True):
    return pulse_cycle(
        model,
        enable=enable,
        write=True,
        write_register=register,
        write_data=data,
    )


def program_tone(
    model: Pulse1Model,
    *,
    timer: int = 8,
    duty: int = 0,
    volume: int = 15,
    length_index: int = 0,
) -> None:
    pulse_write(model, 0, (duty << 6) | 0x10 | volume)
    pulse_write(model, 2, timer & 0xFF)
    pulse_write(model, 3, (length_index << 3) | (timer >> 8))


@pytest.mark.parametrize("duty", range(4))
def test_all_four_duty_modes_cover_all_eight_positions(duty: int) -> None:
    model = Pulse1Model()
    program_tone(model, duty=duty)
    for position, expected in enumerate(PULSE_DUTY_TABLE[duty]):
        model.duty_position = position
        assert model.evaluate(True).raw_output == 15 * expected


def test_timer_low_write_preserves_high_bits() -> None:
    model = Pulse1Model()
    model.timer_period = 0x700
    _, state = pulse_write(model, 2, 0xA5)
    assert state.timer_period == 0x7A5


def test_timer_high_write_preserves_low_bits_and_restarts_sequence() -> None:
    model = Pulse1Model()
    model.timer_period = 0x0A5
    model.timer_counter = 0x123
    model.duty_position = 5
    _, state = pulse_write(model, 3, 0x03)
    assert state.timer_period == 0x3A5
    assert state.timer_counter == 0x123
    assert state.duty_position == 0
    assert state.envelope_start


def test_timer_reload_decrement_and_waveform_advance() -> None:
    model = Pulse1Model()
    model.timer_period = 8
    model.timer_counter = 0
    model.duty_position = 0
    _, state = pulse_cycle(model, timer_tick=True)
    assert state.timer_counter == 8
    assert state.duty_position == 7
    for expected in range(7, -1, -1):
        _, state = pulse_cycle(model, timer_tick=True)
        assert state.timer_counter == expected
        assert state.duty_position == 7
    _, state = pulse_cycle(model, timer_tick=True)
    assert state.timer_counter == 8
    assert state.duty_position == 6


def test_timer_does_not_move_on_between_apu_cpu_cycle() -> None:
    model = Pulse1Model()
    model.timer_period = 99
    model.timer_counter = 31
    model.duty_position = 4
    _, state = pulse_cycle(model, timer_tick=False)
    assert state.timer_counter == 31
    assert state.duty_position == 4


def test_timer_period_below_eight_mutes_and_eight_is_valid() -> None:
    model = Pulse1Model()
    model.length_counter = 1
    model.constant_volume = True
    model.envelope_period = 12
    model.duty = 3
    model.duty_position = 0
    model.timer_period = 7
    assert model.evaluate(True).sweep_mute
    assert model.evaluate(True).raw_output == 0
    model.timer_period = 8
    assert not model.evaluate(True).sweep_mute
    assert model.evaluate(True).raw_output == 12


@pytest.mark.parametrize("index, expected", enumerate(LENGTH_TABLE))
def test_all_length_table_indices_load_exact_values(index: int, expected: int) -> None:
    model = Pulse1Model()
    _, state = pulse_write(model, 3, index << 3)
    assert state.length_counter == expected


def test_length_counter_half_frame_decrement_and_halt() -> None:
    model = Pulse1Model()
    model.length_counter = 3
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.length_counter == 2
    pulse_write(model, 0, 0x20)
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.length_counter == 2


def test_disable_clears_length_and_reenable_does_not_invent_activity() -> None:
    model = Pulse1Model()
    program_tone(model)
    assert model.evaluate(True).active
    _, state = pulse_cycle(model, enable=False)
    assert state.length_counter == 0
    outputs, state = pulse_cycle(model, enable=True)
    assert state.length_counter == 0
    assert not outputs.active and outputs.raw_output == 0


def test_constant_volume_uses_low_register_nibble() -> None:
    model = Pulse1Model()
    program_tone(model, duty=3, volume=9)
    model.duty_position = 0
    model.envelope_decay = 2
    assert model.evaluate(True).raw_output == 9


def test_envelope_start_first_clock_divider_and_decay() -> None:
    model = Pulse1Model()
    pulse_write(model, 0, 0x02)
    pulse_write(model, 3, 0x00)
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert not state.envelope_start
    assert state.envelope_decay == 15 and state.envelope_divider == 2
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 15 and state.envelope_divider == 1
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 15 and state.envelope_divider == 0
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 14 and state.envelope_divider == 2


def test_envelope_loops_at_zero_only_when_loop_flag_is_set() -> None:
    model = Pulse1Model()
    model.length_halt = True
    model.envelope_period = 4
    model.envelope_decay = 0
    model.envelope_divider = 0
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 15 and state.envelope_divider == 4

    model.length_halt = False
    model.envelope_decay = 0
    model.envelope_divider = 0
    _, state = pulse_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 0 and state.envelope_divider == 4


def test_register_zero_rewrite_does_not_restart_envelope_but_high_write_does() -> None:
    model = Pulse1Model()
    model.envelope_start = False
    model.envelope_decay = 7
    pulse_write(model, 0, 0x03)
    assert not model.state().envelope_start
    assert model.state().envelope_decay == 7
    pulse_write(model, 3, 0x00)
    assert model.state().envelope_start


def test_disabled_sweep_does_not_change_timer() -> None:
    model = Pulse1Model()
    model.timer_period = 0x100
    model.sweep_enabled = False
    model.sweep_shift = 1
    model.sweep_divider = 0
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.timer_period == 0x100


def test_positive_sweep_updates_to_target() -> None:
    model = Pulse1Model()
    model.timer_period = 0x100
    model.sweep_enabled = True
    model.sweep_shift = 1
    model.sweep_period = 3
    model.sweep_divider = 0
    assert model.sweep_target() == 0x180
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.timer_period == 0x180
    assert state.sweep_divider == 3


def test_negative_sweep_uses_pulse1_ones_complement_quirk() -> None:
    model = Pulse1Model()
    model.timer_period = 0x100
    model.sweep_enabled = True
    model.sweep_negate = True
    model.sweep_shift = 1
    model.sweep_divider = 0
    assert model.sweep_target() == 0x07F
    assert model.sweep_target() != 0x080  # Pulse 2's later two's-complement rule.
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.timer_period == 0x07F


def test_sweep_write_reload_occurs_on_next_half_frame() -> None:
    model = Pulse1Model()
    model.timer_period = 0x100
    model.sweep_divider = 2
    pulse_write(model, 1, 0xB1)  # enabled, period 3, positive, shift 1
    assert model.state().sweep_reload
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert not state.sweep_reload
    assert state.sweep_divider == 3
    assert state.timer_period == 0x100


def test_sweep_shift_zero_never_updates_period() -> None:
    model = Pulse1Model()
    model.timer_period = 0x100
    model.sweep_enabled = True
    model.sweep_shift = 0
    model.sweep_divider = 0
    _, state = pulse_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.timer_period == 0x100


def test_sweep_target_boundary_and_positive_overflow_mute() -> None:
    model = Pulse1Model()
    model.timer_period = 0x555
    model.sweep_shift = 1
    assert model.sweep_target() == 0x7FF
    assert not model.sweep_mute()
    model.timer_period = 0x556
    assert model.sweep_target() == 0x801
    assert model.sweep_mute()


def test_positive_target_overflow_mutes_even_when_sweep_is_disabled() -> None:
    model = Pulse1Model()
    model.timer_period = 0x600
    model.sweep_shift = 1
    model.sweep_enabled = False
    model.length_counter = 1
    model.constant_volume = True
    model.envelope_period = 15
    model.duty = 3
    assert model.evaluate(True).sweep_mute
    assert model.evaluate(True).raw_output == 0


@pytest.mark.parametrize(
    "enable,length,duty_position,timer,expected",
    [
        (False, 1, 0, 8, 0),
        (True, 0, 0, 8, 0),
        (True, 1, 7, 8, 0),
        (True, 1, 0, 7, 0),
        (True, 1, 0, 8, 11),
    ],
)
def test_output_gating(
    enable: bool,
    length: int,
    duty_position: int,
    timer: int,
    expected: int,
) -> None:
    model = Pulse1Model()
    model.length_counter = length
    model.duty = 3
    model.duty_position = duty_position
    model.timer_period = timer
    model.constant_volume = True
    model.envelope_period = 11
    assert model.evaluate(enable).raw_output == expected


def test_exact_constant_volume_waveform_over_one_sequence() -> None:
    model = Pulse1Model()
    program_tone(model, timer=8, duty=0, volume=15)
    model.timer_counter = 0
    samples = [model.evaluate(True).raw_output]
    for _ in range(8):
        pulse_cycle(model, timer_tick=True)
        samples.append(model.evaluate(True).raw_output)
        for _ in range(8):
            pulse_cycle(model, timer_tick=True)
    assert samples == [0, 15, 0, 0, 0, 0, 0, 0, 0]


def test_reset_clears_every_pulse_state_during_active_envelope_and_sweep() -> None:
    model = Pulse1Model()
    program_tone(model, timer=0x180, duty=3)
    model.envelope_decay = 7
    model.sweep_enabled = True
    model.sweep_shift = 2
    _, state = model.clock(PulseInputs(reset=True, cpu_cycle_enable=True, enable=True))
    assert state == Pulse1Model().state()
    assert not model.evaluate(False).active
    assert model.evaluate(False).raw_output == 0


def test_debugger_pause_freezes_every_pulse_state_for_thousands_of_clocks() -> None:
    model = Pulse1Model()
    program_tone(model, timer=8, duty=3)
    model.envelope_start = True
    model.sweep_reload = True
    before = model.state()
    paused = PulseInputs(
        cpu_cycle_enable=False,
        timer_tick=False,
        enable=True,
        write=True,
        write_register=3,
        write_data=0xFF,
        quarter_frame_tick=True,
        half_frame_tick=True,
    )
    for _ in range(4_096):
        _, state = model.clock(paused)
        assert state == before


def test_debugger_single_step_accepts_a_held_register_write_exactly_once() -> None:
    model = Pulse1Model()
    held_write = PulseInputs(
        cpu_cycle_enable=False,
        enable=True,
        write=True,
        write_register=3,
        write_data=0x00,
    )
    for _ in range(64):
        model.clock(held_write)
    assert model.state().length_counter == 0
    pulse_write(model, 3, 0x00)
    assert model.state().length_counter == LENGTH_TABLE[0]
    pulse_cycle(model, quarter_frame_tick=True)
    assert not model.state().envelope_start
    for _ in range(64):
        model.clock(held_write)
    assert not model.state().envelope_start
    assert model.state().length_counter == LENGTH_TABLE[0]


def test_oam_dma_cpu_time_continues_pulse_timer_without_cpu_bus_activity() -> None:
    model = Pulse1Model()
    program_tone(model, timer=8, duty=3)
    model.timer_counter = 0
    model.duty_position = 0
    # DMA stalls instruction execution, but these are still accepted NES CPU
    # time slots. Alternate APU and between-APU timer phases for 20 slots.
    for cpu_slot in range(20):
        pulse_cycle(model, timer_tick=(cpu_slot % 2 == 0))
    assert model.state().duty_position == 6
    assert model.state().timer_counter == 8


def test_status_bit_tracks_real_length_not_enable_mask() -> None:
    model = ApuFoundationModel()

    def apu_cycle(**kwargs: object):
        return model.clock(ApuInputs(cpu_cycle_enable=True, **kwargs))

    apu_cycle(cpu_write=True, cpu_address=APU_STATUS, cpu_write_data=0x01)
    outputs, _ = apu_cycle(cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x01 == 0
    apu_cycle(cpu_write=True, cpu_address=0x4003, cpu_write_data=0x00)
    outputs, _ = apu_cycle(cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x01 == 1
    apu_cycle(cpu_write=True, cpu_address=APU_STATUS, cpu_write_data=0x00)
    outputs, _ = apu_cycle(cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x01 == 0
    apu_cycle(cpu_write=True, cpu_address=APU_STATUS, cpu_write_data=0x01)
    outputs, _ = apu_cycle(cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x01 == 0


@pytest.mark.parametrize(
    "timer, cpu_cycles",
    [(8, 144), (100, 1_616), (0x7FF, 32_768)],
)
def test_pulse_period_and_frequency_sanity(timer: int, cpu_cycles: int) -> None:
    assert pulse_sequence_cpu_cycles(timer) == cpu_cycles
    expected = 1_789_773.0 / cpu_cycles
    assert math.isclose(pulse_frequency_hz(timer), expected, rel_tol=1e-12)


def test_invalid_timer_period_for_frequency_helper_is_rejected() -> None:
    with pytest.raises(ValueError):
        pulse_sequence_cpu_cycles(-1)
    with pytest.raises(ValueError):
        pulse_sequence_cpu_cycles(0x800)
