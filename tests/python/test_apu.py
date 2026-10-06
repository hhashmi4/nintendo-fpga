"""Phase 5A APU foundation reference-model tests."""

import random

from verification.apu import (
    APU_FRAME_COUNTER,
    APU_STATUS,
    FIVE_STEP_END,
    FIVE_STEP_HALF,
    FOUR_STEP_END,
    FOUR_STEP_HALF,
    FOUR_STEP_IRQ_1,
    HALF_1,
    QUARTER_1,
    QUARTER_3,
    ApuFoundationModel,
    ApuInputs,
)


def cycle(model: ApuFoundationModel, **kwargs: object):
    return model.clock(ApuInputs(cpu_cycle_enable=True, **kwargs))


def test_reset_is_fully_deterministic_at_an_arbitrary_sequence_position() -> None:
    model = ApuFoundationModel()
    cycle(model, cpu_write=True, cpu_address=APU_STATUS, cpu_write_data=0x1F)
    for _ in range(12_345):
        cycle(model)
    cycle(model, cpu_write=True, cpu_address=APU_FRAME_COUNTER, cpu_write_data=0x80)
    outputs, state = model.clock(
        ApuInputs(
            reset=True,
            cpu_cycle_enable=True,
            cpu_read=True,
            cpu_write=True,
            cpu_address=APU_STATUS,
            cpu_write_data=0xFF,
            channel_active=0x1F,
            dmc_irq_flag=True,
        )
    )
    assert outputs.cpu_read_data == 0
    assert not outputs.irq
    assert not outputs.channel_write and not outputs.dmc_irq_clear
    assert not outputs.quarter_frame_tick and not outputs.half_frame_tick
    assert state.channel_enable == 0
    assert not state.mode_5_step and not state.irq_inhibit
    assert not state.frame_irq_flag
    assert state.frame_sequence_cycle == 0
    assert not state.cpu_cycle_odd
    assert not state.frame_reset_pending and state.frame_reset_delay == 0
    assert not state.frame_tick_block


def test_channel_write_decode_and_status_enable_are_distinct_from_active() -> None:
    model = ApuFoundationModel()
    outputs, state = cycle(
        model, cpu_write=True, cpu_address=0x400C, cpu_write_data=0xA5
    )
    assert outputs.channel_write
    assert outputs.channel_write_register == 0x0C
    assert outputs.channel_write_data == 0xA5
    assert state.channel_enable == 0

    outputs, state = cycle(
        model, cpu_write=True, cpu_address=APU_STATUS, cpu_write_data=0x15
    )
    assert not outputs.channel_write and outputs.dmc_irq_clear
    assert state.channel_enable == 0x15
    outputs, _ = cycle(
        model, cpu_read=True, cpu_address=APU_STATUS, channel_active=0x0A
    )
    assert outputs.cpu_read_data == 0x08


def test_unaccepted_bus_levels_do_not_repeat_writes_or_advance_time() -> None:
    model = ApuFoundationModel()
    held = ApuInputs(
        cpu_cycle_enable=False,
        cpu_write=True,
        cpu_address=APU_STATUS,
        cpu_write_data=0x1F,
    )
    before = model.state()
    for _ in range(2_000):
        outputs, state = model.clock(held)
        assert not outputs.channel_write and not outputs.dmc_irq_clear
        assert not outputs.quarter_frame_tick and not outputs.half_frame_tick
        assert state == before
    _, state = model.clock(
        ApuInputs(
            cpu_cycle_enable=True,
            cpu_write=True,
            cpu_address=APU_STATUS,
            cpu_write_data=0x1F,
        )
    )
    assert state.channel_enable == 0x1F
    assert state.frame_sequence_cycle == 1


def test_four_step_schedule_ticks_and_latches_irq_on_exact_cpu_cycles() -> None:
    model = ApuFoundationModel()
    quarter_cycles = []
    half_cycles = []
    irq_cycles = []
    for cpu_cycle in range(1, FOUR_STEP_END + 1):
        outputs, state = cycle(model)
        if outputs.quarter_frame_tick:
            quarter_cycles.append(cpu_cycle)
        if outputs.half_frame_tick:
            half_cycles.append(cpu_cycle)
        if outputs.irq:
            irq_cycles.append(cpu_cycle)
        if cpu_cycle < FOUR_STEP_END:
            assert state.frame_sequence_cycle == cpu_cycle
    assert quarter_cycles == [QUARTER_1, HALF_1, QUARTER_3, FOUR_STEP_HALF]
    assert half_cycles == [HALF_1, FOUR_STEP_HALF]
    assert irq_cycles == [FOUR_STEP_IRQ_1, FOUR_STEP_HALF, FOUR_STEP_END]
    assert model.state().frame_sequence_cycle == 0
    assert model.state().frame_irq_flag


def test_status_read_reports_and_clears_frame_irq_but_not_external_dmc_irq() -> None:
    model = ApuFoundationModel()
    model.frame_irq_flag = True
    outputs, state = cycle(
        model,
        cpu_read=True,
        cpu_address=APU_STATUS,
        channel_active=0x12,
        dmc_irq_flag=True,
    )
    assert outputs.cpu_read_data == 0xD0
    assert outputs.irq
    assert not state.frame_irq_flag

    outputs, _ = cycle(
        model,
        cpu_read=True,
        cpu_address=APU_STATUS,
        dmc_irq_flag=True,
    )
    assert outputs.cpu_read_data == 0x80
    assert not outputs.irq


def test_irq_set_same_cycle_as_status_read_is_reported_and_not_cleared() -> None:
    model = ApuFoundationModel()
    model.frame_sequence_cycle = FOUR_STEP_IRQ_1 - 1
    outputs, state = cycle(model, cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data == 0x40
    assert outputs.irq
    assert state.frame_irq_flag


def test_frame_irq_inhibit_is_immediate_and_five_step_has_no_frame_irq() -> None:
    model = ApuFoundationModel()
    model.frame_irq_flag = True
    _, state = cycle(
        model,
        cpu_write=True,
        cpu_address=APU_FRAME_COUNTER,
        cpu_write_data=0xC0,
    )
    assert state.irq_inhibit and not state.frame_irq_flag
    assert not state.mode_5_step

    expected_delay = 3
    for remaining in (expected_delay - 1, expected_delay - 2):
        outputs, state = cycle(model)
        assert not outputs.quarter_frame_tick and not outputs.half_frame_tick
        assert not state.mode_5_step
        assert state.frame_reset_delay == remaining
    outputs, state = cycle(model)
    assert outputs.quarter_frame_tick and outputs.half_frame_tick
    assert state.mode_5_step and state.frame_sequence_cycle == 0

    quarter_cycles = []
    half_cycles = []
    for cpu_cycle in range(1, FIVE_STEP_END + 1):
        outputs, _ = cycle(model)
        assert not outputs.irq
        if outputs.quarter_frame_tick:
            quarter_cycles.append(cpu_cycle)
        if outputs.half_frame_tick:
            half_cycles.append(cpu_cycle)
    assert quarter_cycles == [QUARTER_1, HALF_1, QUARTER_3, FIVE_STEP_HALF]
    assert half_cycles == [HALF_1, FIVE_STEP_HALF]
    assert model.state().frame_sequence_cycle == 0


def test_frame_counter_write_delay_tracks_cpu_cycle_parity() -> None:
    even = ApuFoundationModel()
    _, state = cycle(
        even, cpu_write=True, cpu_address=APU_FRAME_COUNTER, cpu_write_data=0x80
    )
    assert state.frame_reset_delay == 3
    for _ in range(2):
        outputs, state = cycle(even)
        assert not outputs.quarter_frame_tick
        assert not state.mode_5_step
    outputs, state = cycle(even)
    assert outputs.quarter_frame_tick and outputs.half_frame_tick
    assert state.mode_5_step

    odd = ApuFoundationModel()
    cycle(odd)  # Move the write to an odd/between-APU CPU cycle.
    _, state = cycle(
        odd, cpu_write=True, cpu_address=APU_FRAME_COUNTER, cpu_write_data=0x80
    )
    assert state.frame_reset_delay == 4
    for _ in range(3):
        outputs, state = cycle(odd)
        assert not outputs.quarter_frame_tick
        assert not state.mode_5_step
    outputs, state = cycle(odd)
    assert outputs.quarter_frame_tick and outputs.half_frame_tick
    assert state.mode_5_step


def test_five_step_application_does_not_double_clock_after_natural_tick() -> None:
    model = ApuFoundationModel()
    model.frame_sequence_cycle = QUARTER_1 - 3
    model.cpu_cycle_odd = False

    outputs, _ = cycle(
        model,
        cpu_write=True,
        cpu_address=APU_FRAME_COUNTER,
        cpu_write_data=0x80,
    )
    assert not outputs.quarter_frame_tick
    outputs, _ = cycle(model)
    assert not outputs.quarter_frame_tick
    outputs, state = cycle(model)
    assert outputs.quarter_frame_tick and not outputs.half_frame_tick
    assert state.frame_tick_block

    outputs, state = cycle(model)
    assert not outputs.quarter_frame_tick and not outputs.half_frame_tick
    assert state.mode_5_step and state.frame_sequence_cycle == 0
    assert not state.frame_tick_block


def test_randomized_model_invariants_cover_pauses_reads_writes_and_resets() -> None:
    rng = random.Random(0x5A2026)
    model = ApuFoundationModel()
    accepted_cycles = 0
    for _ in range(100_000):
        address = rng.choice(
            [rng.randrange(0x4000, 0x4018), APU_STATUS, APU_FRAME_COUNTER, 0x1234]
        )
        inputs = ApuInputs(
            reset=rng.randrange(4_000) == 0,
            cpu_cycle_enable=rng.randrange(5) != 0,
            cpu_read=rng.randrange(9) == 0,
            cpu_write=rng.randrange(7) == 0,
            cpu_address=address,
            cpu_write_data=rng.randrange(256),
            channel_active=rng.randrange(32),
            dmc_irq_flag=bool(rng.randrange(2)),
        )
        before = model.state()
        outputs, state = model.clock(inputs)
        assert not outputs.half_frame_tick or outputs.quarter_frame_tick
        assert 0 <= state.frame_sequence_cycle <= FIVE_STEP_END
        assert 0 <= state.channel_enable <= 0x1F
        assert 0 <= state.frame_reset_delay <= 4
        if inputs.reset:
            assert state.frame_sequence_cycle == 0
            assert state.channel_enable == 0
        elif not inputs.cpu_cycle_enable:
            assert state == before
            assert not outputs.channel_write and not outputs.dmc_irq_clear
            assert not outputs.quarter_frame_tick and not outputs.half_frame_tick
        else:
            accepted_cycles += 1
    assert accepted_cycles > 75_000
