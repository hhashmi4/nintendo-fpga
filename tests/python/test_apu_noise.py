"""Directed Phase 5E tests for Noise and four-channel integration."""

import pytest

from verification.apu import (
    APU_STATUS,
    LENGTH_TABLE,
    NOISE_PERIOD_TABLE,
    ApuFoundationModel,
    ApuInputs,
    NoiseInputs,
    NoiseModel,
    noise_shift_cpu_cycles,
    noise_shift_rate_hz,
)


LONG_FIRST_24 = (
    0x4000, 0x2000, 0x1000, 0x0800, 0x0400, 0x0200,
    0x0100, 0x0080, 0x0040, 0x0020, 0x0010, 0x0008,
    0x0004, 0x0002, 0x4001, 0x6000, 0x3000, 0x1800,
    0x0C00, 0x0600, 0x0300, 0x0180, 0x00C0, 0x0060,
)

SHORT_FIRST_24 = (
    0x4000, 0x2000, 0x1000, 0x0800, 0x0400, 0x0200,
    0x0100, 0x0080, 0x0040, 0x4020, 0x2010, 0x1008,
    0x0804, 0x0402, 0x0201, 0x4100, 0x2080, 0x1040,
    0x4820, 0x2410, 0x1208, 0x0904, 0x0482, 0x0241,
)


def noise_cycle(model: NoiseModel, **kwargs: object):
    values: dict[str, object] = {"cpu_cycle_enable": True, "enable": True}
    values.update(kwargs)
    inputs = NoiseInputs(**values)
    outputs, _ = model.clock(inputs)
    return outputs, model.state()


def noise_write(
    model: NoiseModel, register: int, data: int, *, enable: bool = True
):
    return noise_cycle(
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


def program_noise(
    model: ApuFoundationModel,
    *,
    control: int = 0x1F,
    mode: bool = False,
    period_index: int = 0,
    length_index: int = 0,
) -> None:
    apu_write(model, 0x400C, control)
    apu_write(model, 0x400E, (0x80 if mode else 0) | period_index)
    apu_write(model, 0x400F, length_index << 3)


def shift_sequence(mode: bool, count: int) -> tuple[int, ...]:
    model = NoiseModel()
    model.mode = mode
    states = []
    for _ in range(count):
        model.timer_counter = 0
        noise_cycle(model, timer_tick=True)
        states.append(model.lfsr)
    return tuple(states)


def test_400c_decodes_all_noise_control_fields() -> None:
    model = NoiseModel()
    _, state = noise_write(model, 0, 0xAF)
    assert state.length_halt
    assert not state.constant_volume
    assert state.envelope_period == 15


def test_400d_is_unused_and_preserves_every_noise_register() -> None:
    model = NoiseModel()
    model.length_halt = True
    model.constant_volume = True
    model.envelope_period = 9
    model.envelope_start = True
    model.envelope_divider = 7
    model.envelope_decay = 6
    model.mode = True
    model.period_index = 13
    model.timer_counter = 23
    model.length_counter = 31
    model.lfsr = 0x4567
    before = model.state()
    _, after = noise_write(model, 1, 0xFF, enable=True)
    assert after == before


def test_400e_decodes_mode_and_period_index_without_resetting_timer_or_lfsr() -> None:
    model = NoiseModel()
    model.timer_counter = 42
    model.lfsr = 0x1234
    _, state = noise_write(model, 2, 0x8D)
    assert state.mode
    assert state.period_index == 13
    assert state.timer_counter == 42
    assert state.lfsr == 0x1234


def test_400f_loads_length_and_requests_envelope_restart() -> None:
    model = NoiseModel()
    model.lfsr = 0x1234
    _, state = noise_write(model, 3, 9 << 3)
    assert state.length_counter == LENGTH_TABLE[9]
    assert state.envelope_start
    assert state.lfsr == 0x1234


@pytest.mark.parametrize("index, expected", enumerate(NOISE_PERIOD_TABLE))
def test_all_16_ntsc_noise_period_entries(index: int, expected: int) -> None:
    model = NoiseModel()
    noise_write(model, 2, index)
    assert model.timer_period == expected
    assert noise_shift_cpu_cycles(index) == expected


@pytest.mark.parametrize("index", [0, 1, 5, 8, 11, 15])
def test_timer_reload_and_decrement_for_multiple_periods(index: int) -> None:
    model = NoiseModel()
    model.period_index = index
    _, state = noise_cycle(model, timer_tick=True)
    expected_reload = NOISE_PERIOD_TABLE[index] // 2 - 1
    assert state.timer_counter == expected_reload
    first_lfsr = state.lfsr
    if expected_reload:
        _, state = noise_cycle(model, timer_tick=True)
        assert state.timer_counter == expected_reload - 1
        assert state.lfsr == first_lfsr


def test_period_change_while_running_takes_effect_at_next_reload() -> None:
    model = NoiseModel()
    model.period_index = 15
    model.timer_counter = 2
    noise_write(model, 2, 0)
    assert model.timer_counter == 2
    noise_cycle(model, timer_tick=True)
    noise_cycle(model, timer_tick=True)
    _, state = noise_cycle(model, timer_tick=True)
    assert state.timer_counter == 1


def test_shortest_and_longest_period_have_exact_cpu_spacing() -> None:
    for index in (0, 15):
        model = ApuFoundationModel()
        model.noise.period_index = index
        last_lfsr = model.noise.lfsr
        shifts = []
        for cpu_cycle in range(NOISE_PERIOD_TABLE[index] * 2 + 1):
            apu_cycle(model)
            if model.noise.lfsr != last_lfsr:
                shifts.append(cpu_cycle)
                last_lfsr = model.noise.lfsr
        assert shifts[:3] == [0, NOISE_PERIOD_TABLE[index], 2 * NOISE_PERIOD_TABLE[index]]


def test_normal_mode_first_24_shifts_match_known_sequence() -> None:
    assert shift_sequence(False, len(LONG_FIRST_24)) == LONG_FIRST_24


def test_short_mode_first_24_shifts_match_known_sequence() -> None:
    assert shift_sequence(True, len(SHORT_FIRST_24)) == SHORT_FIRST_24


def test_normal_and_short_modes_diverge_from_same_seed_at_tenth_shift() -> None:
    normal = shift_sequence(False, 10)
    short = shift_sequence(True, 10)
    assert normal[:9] == short[:9]
    assert normal[9] == 0x0020
    assert short[9] == 0x4020


def test_mode_change_uses_new_tap_only_on_following_expiration() -> None:
    model = NoiseModel()
    model.lfsr = 0x0040
    model.timer_counter = 1
    noise_write(model, 2, 0x80)
    assert model.lfsr == 0x0040
    noise_cycle(model, timer_tick=True)
    assert model.lfsr == 0x0040
    noise_cycle(model, timer_tick=True)
    assert model.lfsr == 0x4020


def test_reset_seed_first_shift_and_repeated_shifts_are_deterministic() -> None:
    model = NoiseModel()
    model.lfsr = 0x7777
    noise_cycle(model, reset=True)
    assert model.lfsr == 1
    assert shift_sequence(False, 4) == (0x4000, 0x2000, 0x1000, 0x0800)


@pytest.mark.parametrize("mode", [False, True])
def test_lfsr_never_enters_zero_lock_for_full_relevant_sequence(mode: bool) -> None:
    model = NoiseModel()
    model.mode = mode
    # Long mode is maximal length; short mode has the documented 93-step loop.
    for _ in range(32767 if not mode else 4096):
        model.timer_counter = 0
        noise_cycle(model, timer_tick=True)
        assert model.lfsr != 0


def test_envelope_start_decay_and_divider_clock_on_quarter_frames() -> None:
    model = NoiseModel()
    noise_write(model, 0, 0x02)
    noise_write(model, 3, 0)
    _, state = noise_cycle(model, quarter_frame_tick=True)
    assert not state.envelope_start
    assert (state.envelope_decay, state.envelope_divider) == (15, 2)
    for _ in range(3):
        _, state = noise_cycle(model, quarter_frame_tick=True)
    assert (state.envelope_decay, state.envelope_divider) == (14, 2)


def test_envelope_loop_reloads_decay_at_zero() -> None:
    model = NoiseModel()
    model.length_halt = True
    model.envelope_decay = 0
    model.envelope_divider = 0
    _, state = noise_cycle(model, quarter_frame_tick=True)
    assert state.envelope_decay == 15


def test_constant_volume_and_envelope_volume_are_independent() -> None:
    model = NoiseModel()
    model.length_counter = 1
    model.lfsr = 2
    model.constant_volume = True
    model.envelope_period = 9
    model.envelope_decay = 4
    assert model.evaluate(True).raw_output == 9
    model.constant_volume = False
    assert model.evaluate(True).raw_output == 4


@pytest.mark.parametrize("index, expected", enumerate(LENGTH_TABLE))
def test_all_noise_length_indices_use_shared_table(index: int, expected: int) -> None:
    model = NoiseModel()
    _, state = noise_write(model, 3, index << 3)
    assert state.length_counter == expected


def test_length_decrement_and_halt_follow_half_frame() -> None:
    model = NoiseModel()
    model.length_counter = 3
    _, state = noise_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.length_counter == 2
    noise_write(model, 0, 0x20)
    _, state = noise_cycle(model, quarter_frame_tick=True, half_frame_tick=True)
    assert state.length_counter == 2


def test_4015_disable_clears_length_and_enable_does_not_invent_length() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x08)
    program_noise(model, length_index=1)
    assert model.noise.length_counter == LENGTH_TABLE[1]
    apu_write(model, APU_STATUS, 0)
    assert model.noise.length_counter == 0
    apu_write(model, APU_STATUS, 0x08)
    assert model.noise.length_counter == 0


@pytest.mark.parametrize("mask", range(16))
def test_4015_reports_all_four_channel_status_combinations(mask: int) -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, mask)
    apu_write(model, 0x4003, 0)
    apu_write(model, 0x4007, 0)
    apu_write(model, 0x400B, 0)
    apu_write(model, 0x400F, 0)
    outputs, _ = apu_cycle(model, cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x0F == mask


@pytest.mark.parametrize(
    "lfsr,length,expected", [(1, 1, 0), (2, 1, 11), (2, 0, 0)]
)
def test_lfsr_bit_zero_and_length_gate_raw_output(
    lfsr: int, length: int, expected: int
) -> None:
    model = NoiseModel()
    model.constant_volume = True
    model.envelope_period = 11
    model.lfsr = lfsr
    model.length_counter = length
    assert model.evaluate(True).raw_output == expected


def test_400d_write_through_real_apu_has_no_channel_side_effect() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x0F)
    program_noise(model, mode=True, period_index=9, length_index=7)
    model.noise.timer_counter = 19
    before_noise = model.noise.state()
    before_other_registers = (
        model.pulse1.duty,
        model.pulse1.envelope_period,
        model.pulse1.length_counter,
        model.pulse2.duty,
        model.pulse2.envelope_period,
        model.pulse2.length_counter,
        model.triangle.control_flag,
        model.triangle.linear_reload_value,
        model.triangle.length_counter,
    )
    # Pause the APU timer around the write to isolate decode side effects.
    model.clock(ApuInputs(cpu_cycle_enable=False, cpu_write=True,
                          cpu_address=0x400D, cpu_write_data=0xFF))
    apu_write(model, 0x400D, 0xFF)
    after_noise = model.noise.state()
    assert after_noise == before_noise.__class__(
        **{**before_noise.__dict__, "timer_counter": before_noise.timer_counter - 1}
    )
    assert (
        model.pulse1.duty,
        model.pulse1.envelope_period,
        model.pulse1.length_counter,
        model.pulse2.duty,
        model.pulse2.envelope_period,
        model.pulse2.length_counter,
        model.triangle.control_flag,
        model.triangle.linear_reload_value,
        model.triangle.length_counter,
    ) == before_other_registers


def test_four_channels_run_simultaneously_without_register_crosstalk() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x0F)
    apu_write(model, 0x4000, 0xDF)
    apu_write(model, 0x4002, 8)
    apu_write(model, 0x4003, 0)
    apu_write(model, 0x4004, 0x9B)
    apu_write(model, 0x4006, 11)
    apu_write(model, 0x4007, 8)
    apu_write(model, 0x4008, 0xFF)
    apu_write(model, 0x400A, 2)
    apu_write(model, 0x400B, 16)
    program_noise(model, control=0x1D, mode=True, period_index=0, length_index=4)
    model.triangle.linear_counter = 127
    initial = (
        model.pulse1.duty_position,
        model.pulse2.duty_position,
        model.triangle.sequence_position,
        model.noise.lfsr,
    )
    observed_outputs = set()
    for _ in range(256):
        outputs, _ = apu_cycle(model)
        observed_outputs.add(
            (outputs.pulse1_output, outputs.pulse2_output,
             outputs.triangle_output, outputs.noise_output)
        )
    final = (
        model.pulse1.duty_position,
        model.pulse2.duty_position,
        model.triangle.sequence_position,
        model.noise.lfsr,
    )
    assert final != initial
    assert len(observed_outputs) > 4
    assert all(counter > 0 for counter in (
        model.pulse1.length_counter,
        model.pulse2.length_counter,
        model.triangle.length_counter,
        model.noise.length_counter,
    ))


def test_register_groups_only_mutate_their_owned_channel() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x0F)
    snapshots = []
    for address, data in (
        (0x4000, 0x1A), (0x4004, 0x1B), (0x4008, 0x81), (0x400C, 0x1C)
    ):
        snapshots.append((model.pulse1.state(), model.pulse2.state(),
                          model.triangle.state(), model.noise.state()))
        apu_write(model, address, data)
    assert model.pulse1.envelope_period == 10
    assert model.pulse2.envelope_period == 11
    assert model.triangle.linear_reload_value == 1
    assert model.noise.envelope_period == 12
    assert snapshots[1][1] == snapshots[0][1]
    assert snapshots[2][2] == snapshots[1][2]
    assert snapshots[3][3] == snapshots[2][3]


def test_debugger_pause_freezes_all_noise_state_and_resume_is_exact() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x08)
    program_noise(model, period_index=0, length_index=1)
    before = model.noise.state()
    for _ in range(10_000):
        outputs, _ = model.clock(ApuInputs(cpu_cycle_enable=False))
        assert not outputs.quarter_frame_tick and not outputs.half_frame_tick
    assert model.noise.state() == before
    apu_cycle(model)
    assert model.noise.state() != before


def test_single_debugger_step_accepts_one_write_and_one_timer_action() -> None:
    model = ApuFoundationModel()
    model.channel_enable = 0x08
    for _ in range(99):
        model.clock(ApuInputs(cpu_cycle_enable=False, cpu_write=True,
                              cpu_address=0x400F, cpu_write_data=0))
    assert model.noise.length_counter == 0
    apu_write(model, 0x400F, 0)
    assert model.noise.length_counter == LENGTH_TABLE[0]
    assert model.noise.lfsr == 0x4000


def test_noise_and_other_channels_advance_during_dma_cpu_stall_slots() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x0F)
    program_noise(model, period_index=0, length_index=1)
    model.pulse1.timer_period = 8
    model.pulse2.timer_period = 11
    model.triangle.timer_period = 2
    model.triangle.length_counter = 1
    model.triangle.linear_counter = 1
    before = (model.pulse1.duty_position, model.pulse2.duty_position,
              model.triangle.sequence_position, model.noise.lfsr)
    for _ in range(514):
        apu_cycle(model)  # Complete APU slot with no CPU bus transaction.
    after = (model.pulse1.duty_position, model.pulse2.duty_position,
             model.triangle.sequence_position, model.noise.lfsr)
    assert after != before
    assert model.noise.lfsr != before[3]


def test_reset_while_active_restores_all_deterministic_noise_state() -> None:
    model = ApuFoundationModel()
    apu_write(model, APU_STATUS, 0x08)
    program_noise(model, control=0x2D, mode=True, period_index=15, length_index=1)
    for _ in range(30):
        apu_cycle(model)
    model.clock(ApuInputs(reset=True, cpu_cycle_enable=False))
    assert model.noise.state() == NoiseModel().state()
    assert model.noise.evaluate(False).raw_output == 0


def test_deterministic_constant_volume_waveform_matches_exact_samples() -> None:
    model = NoiseModel()
    model.constant_volume = True
    model.envelope_period = 10
    model.length_counter = 1
    samples = []
    for _ in range(32):
        outputs, _ = noise_cycle(model, timer_tick=True)
        samples.append(outputs.raw_output)
    assert tuple(samples) == (
        0, 10, 10, 10, 10, 10, 10, 10,
        10, 10, 10, 10, 10, 10, 10, 10,
        10, 10, 10, 10, 10, 10, 10, 10,
        10, 10, 10, 10, 10, 0, 0, 10,
    )


@pytest.mark.parametrize("index", [0, 5, 8, 12, 15])
def test_period_frequency_sanity(index: int) -> None:
    expected = 1_789_773.0 / NOISE_PERIOD_TABLE[index]
    assert noise_shift_rate_hz(index) == pytest.approx(expected)


@pytest.mark.parametrize("bad", [-1, 16])
def test_noise_period_helpers_reject_invalid_indices(bad: int) -> None:
    with pytest.raises(ValueError):
        noise_shift_cpu_cycles(bad)
