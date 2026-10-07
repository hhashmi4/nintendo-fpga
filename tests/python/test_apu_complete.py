"""Phase 5G complete pre-mixer APU interaction and closure tests."""

from __future__ import annotations

from copy import deepcopy
import random

import pytest

from verification.apu import (
    APU_FRAME_COUNTER,
    APU_STATUS,
    FIVE_STEP_HALF,
    FOUR_STEP_HALF,
    FOUR_STEP_IRQ_1,
    HALF_1,
    QUARTER_1,
    ApuInputs,
    ApuModel,
)
from verification.nes_bus import CpuTarget, decode_cpu_access
from verification.nes_system import DmaPhase, DmcDmaModel, OamDmaModel
from verification.runtime_cartridge import RuntimeCartridgeModel, RuntimeTarget


def cycle(apu: ApuModel, **kwargs: object):
    return apu.clock(ApuInputs(cpu_cycle_enable=True, **kwargs))


def write(apu: ApuModel, address: int, data: int):
    return cycle(
        apu,
        cpu_write=True,
        cpu_address=address,
        cpu_write_data=data,
    )


def read_status(apu: ApuModel):
    return cycle(apu, cpu_read=True, cpu_address=APU_STATUS)


def apply_five_step_tick(apu: ApuModel) -> None:
    write(apu, APU_FRAME_COUNTER, 0x80)
    while apu.frame_reset_pending:
        cycle(apu)


def program_all_channels(apu: ApuModel) -> None:
    """Load five distinct, sustained sources without using a mixer."""

    write(apu, APU_STATUS, 0x0F)

    # Pulse 1: duty 3, halted length, constant 15, positive sweep.
    write(apu, 0x4000, 0xFF)
    write(apu, 0x4001, 0x91)
    write(apu, 0x4002, 0x08)
    write(apu, 0x4003, 0x08)

    # Pulse 2: duty 2, halted length, constant 10, negate sweep.
    write(apu, 0x4004, 0xBA)
    write(apu, 0x4005, 0x99)
    write(apu, 0x4006, 0x80)
    write(apu, 0x4007, 0x08)

    # Triangle: control/reload held, a period distinct from both pulses.
    write(apu, 0x4008, 0xFF)
    write(apu, 0x4009, 0xA5)  # reserved and intentionally ignored
    write(apu, 0x400A, 0x06)
    write(apu, 0x400B, 0x08)

    # Noise: halted length, constant 13, short-mode period index 2.
    write(apu, 0x400C, 0x3D)
    write(apu, 0x400D, 0x5A)  # reserved and intentionally ignored
    write(apu, 0x400E, 0x82)
    write(apu, 0x400F, 0x08)

    # DMC: terminal IRQ enabled, fastest rate, 17 bytes from $D000.
    write(apu, 0x4010, 0x8F)
    write(apu, 0x4011, 0x40)
    write(apu, 0x4012, 0x40)
    write(apu, 0x4013, 0x01)
    write(apu, APU_STATUS, 0x1F)
    apply_five_step_tick(apu)


def service_dmc(apu: ApuModel, data: int = 0xA5) -> bool:
    if not apu.dmc.mem_request:
        return False
    cycle(apu, dmc_mem_acknowledge=True, dmc_mem_read_data=data)
    return True


@pytest.mark.parametrize("mask", range(32))
def test_all_32_4015_enable_combinations_report_real_activity(mask: int) -> None:
    apu = ApuModel()
    write(apu, 0x4012, 0x20)
    write(apu, 0x4013, 0x00)
    write(apu, APU_STATUS, mask)
    for address in (0x4003, 0x4007, 0x400B, 0x400F):
        write(apu, address, 0x08)
    outputs, _ = read_status(apu)
    assert outputs.cpu_read_data & 0x1F == mask


def test_4015_enable_is_not_active_and_dmc_restart_is_reader_state() -> None:
    apu = ApuModel()
    write(apu, APU_STATUS, 0x0F)
    outputs, _ = read_status(apu)
    assert outputs.cpu_read_data & 0x0F == 0

    write(apu, 0x4013, 0)
    write(apu, APU_STATUS, 0x1F)
    outputs, _ = read_status(apu)
    assert outputs.cpu_read_data & 0x1F == 0x10
    assert apu.dmc.bytes_remaining == 1 and apu.dmc.mem_request


def test_all_channel_status_composition_uses_internal_owners() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    outputs, _ = read_status(apu)
    assert outputs.cpu_read_data & 0x1F == 0x1F
    assert outputs.cpu_read_data & 0x20 == 0


def test_frame_irq_only_status_and_module_irq() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    outputs = apu.evaluate(ApuInputs(cpu_cycle_enable=True, cpu_read=True,
                                    cpu_address=APU_STATUS))
    assert outputs.cpu_read_data == 0x40 and outputs.irq


def test_dmc_irq_only_status_and_module_irq() -> None:
    apu = ApuModel()
    apu.dmc.irq_flag = True
    outputs = apu.evaluate(ApuInputs(cpu_cycle_enable=True, cpu_read=True,
                                    cpu_address=APU_STATUS))
    assert outputs.cpu_read_data == 0x80 and outputs.irq


def test_simultaneous_frame_and_dmc_irqs_hold_module_irq() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    outputs, _ = read_status(apu)
    assert outputs.cpu_read_data & 0xC0 == 0xC0 and outputs.irq
    assert not apu.frame_irq_flag and apu.dmc.irq_flag
    assert apu.evaluate(ApuInputs()).irq


def test_4015_read_clears_frame_irq_only_and_repeated_read_is_stable() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    first, _ = read_status(apu)
    second, _ = read_status(apu)
    assert first.cpu_read_data & 0xC0 == 0xC0
    assert second.cpu_read_data & 0xC0 == 0x80
    assert second.irq and apu.dmc.irq_flag


def test_4015_write_clears_dmc_irq_only_and_preserves_frame_irq() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    outputs, _ = write(apu, APU_STATUS, 0)
    assert outputs.irq
    assert apu.frame_irq_flag and not apu.dmc.irq_flag
    assert apu.evaluate(ApuInputs()).irq


def test_each_irq_source_requires_its_own_clear_mechanism() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    read_status(apu)
    assert not apu.frame_irq_flag and apu.dmc.irq_flag
    write(apu, APU_STATUS, 0)
    assert not apu.frame_irq_flag and not apu.dmc.irq_flag
    assert not apu.evaluate(ApuInputs()).irq


def test_4017_four_step_half_frame_clocks_real_channels() -> None:
    apu = ApuModel()
    write(apu, APU_STATUS, 0x0F)
    for address in (0x4003, 0x4007, 0x400B, 0x400F):
        write(apu, address, 0x18)  # shared length table value 2
    before = (
        apu.pulse1.length_counter,
        apu.pulse2.length_counter,
        apu.triangle.length_counter,
        apu.noise.length_counter,
    )
    assert before == (2, 2, 2, 2)
    apu.frame_sequence_cycle = FOUR_STEP_HALF - 1
    outputs, _ = cycle(apu)
    assert outputs.quarter_frame_tick and outputs.half_frame_tick
    assert (
        apu.pulse1.length_counter,
        apu.pulse2.length_counter,
        apu.triangle.length_counter,
        apu.noise.length_counter,
    ) == (1, 1, 1, 1)


def test_4017_five_step_immediate_tick_clocks_all_controlled_units() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    apu.pulse1.envelope_start = True
    apu.pulse2.envelope_start = True
    apu.noise.envelope_start = True
    apu.triangle.linear_reload_flag = True
    write(apu, APU_FRAME_COUNTER, 0x80)
    ticks = []
    while apu.frame_reset_pending:
        outputs, _ = cycle(apu)
        ticks.append((outputs.quarter_frame_tick, outputs.half_frame_tick))
    assert ticks.count((True, True)) == 1
    assert not apu.pulse1.envelope_start
    assert not apu.pulse2.envelope_start
    assert not apu.noise.envelope_start
    assert apu.triangle.linear_counter == apu.triangle.linear_reload_value


def test_4017_irq_inhibit_is_immediate_and_suppresses_terminal_irq() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    apu.frame_sequence_cycle = FOUR_STEP_IRQ_1 - 1
    outputs, _ = write(apu, APU_FRAME_COUNTER, 0x40)
    assert outputs.irq  # pre-edge state still exposes the already-set latch
    assert not apu.frame_irq_flag and apu.irq_inhibit
    assert not apu.evaluate(ApuInputs()).irq
    for _ in range(FOUR_STEP_HALF + 8):
        outputs, _ = cycle(apu)
        assert not outputs.irq


def test_4017_reset_delay_is_three_or_four_cycles_from_cpu_parity() -> None:
    for initial_odd, expected in ((False, 3), (True, 4)):
        apu = ApuModel()
        apu.cpu_cycle_odd = initial_odd
        write(apu, APU_FRAME_COUNTER, 0x80)
        assert apu.frame_reset_delay == expected
        observed = 0
        while apu.frame_reset_pending:
            outputs, _ = cycle(apu)
            observed += 1
        assert observed == expected
        assert outputs.quarter_frame_tick and outputs.half_frame_tick


@pytest.mark.parametrize("event_cycle", [QUARTER_1, HALF_1])
def test_frame_event_write_collision_orders_before_same_and_after(
    event_cycle: int,
) -> None:
    def prepared() -> ApuModel:
        apu = ApuModel()
        write(apu, APU_STATUS, 0x01)
        write(apu, 0x4000, 0x03)
        apu.pulse1.envelope_start = False
        apu.pulse1.envelope_decay = 7
        apu.pulse1.envelope_divider = 0
        return apu

    before = prepared()
    before.frame_sequence_cycle = event_cycle - 2
    write(before, 0x4003, 0x08)
    event, _ = cycle(before)
    assert event.quarter_frame_tick
    assert not before.pulse1.envelope_start
    assert before.pulse1.envelope_decay == 15

    same = prepared()
    same.frame_sequence_cycle = event_cycle - 1
    event, _ = write(same, 0x4003, 0x08)
    assert event.quarter_frame_tick
    assert same.pulse1.envelope_start

    after = prepared()
    after.frame_sequence_cycle = event_cycle - 1
    event, _ = cycle(after)
    assert event.quarter_frame_tick
    write(after, 0x4003, 0x08)
    assert after.pulse1.envelope_start


def test_half_frame_collisions_cover_length_sweep_and_triangle_reload() -> None:
    apu = ApuModel()
    write(apu, APU_STATUS, 0x05)
    write(apu, 0x4000, 0x00)
    write(apu, 0x4001, 0x91)
    write(apu, 0x4003, 0x18)
    write(apu, 0x4008, 0x07)
    write(apu, 0x400B, 0x18)
    apu.pulse1.sweep_reload = False
    apu.pulse1.sweep_divider = 0
    apu.triangle.linear_reload_flag = False
    apu.frame_sequence_cycle = HALF_1 - 1
    outputs, _ = write(apu, 0x4001, 0xA2)
    assert outputs.half_frame_tick
    assert apu.pulse1.length_counter == 1
    assert apu.pulse1.sweep_reload  # same-cycle write wins for next half tick

    # Use the next non-adjacent half-frame collision; the frame sequencer's
    # deliberate adjacent-event suppression remains set after the first one.
    apu.frame_tick_block = False
    apu.frame_sequence_cycle = HALF_1 - 1
    outputs, _ = write(apu, 0x400B, 0x20)
    assert outputs.half_frame_tick
    assert apu.triangle.length_counter == 40
    assert apu.triangle.linear_reload_flag


def test_all_five_channels_run_simultaneously_with_distinct_state() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    seen = [set() for _ in range(5)]
    simultaneous_nonzero = 0
    fetches = 0
    for index in range(40_000):
        if apu.dmc.mem_request:
            outputs, _ = cycle(
                apu,
                dmc_mem_acknowledge=True,
                dmc_mem_read_data=(index * 37 + 0x53) & 0xFF,
            )
            fetches += 1
        else:
            outputs, _ = cycle(apu)
        values = (
            outputs.pulse1_output,
            outputs.pulse2_output,
            outputs.triangle_output,
            outputs.noise_output,
            outputs.dmc_output,
        )
        for observed, value in zip(seen, values, strict=True):
            observed.add(value)
        simultaneous_nonzero += int(all(values))
    assert fetches >= 9 and simultaneous_nonzero > 20
    assert all(len(observed) >= 2 for observed in seen)


def test_all_channels_disabled_clears_activity_not_persistent_dacs() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    write(apu, APU_STATUS, 0)
    outputs, _ = read_status(apu)
    assert outputs.cpu_read_data & 0x1F == 0
    assert apu.pulse1.length_counter == 0
    assert apu.pulse2.length_counter == 0
    assert apu.triangle.length_counter == 0
    assert apu.noise.length_counter == 0
    assert apu.dmc.bytes_remaining == 0 and not apu.dmc.mem_request
    assert outputs.pulse1_output == outputs.pulse2_output == 0
    assert outputs.noise_output == 0
    assert 0 <= outputs.triangle_output <= 15
    assert outputs.dmc_output == 0x40


def test_rapid_enable_disable_never_invents_length_or_duplicates_dmc() -> None:
    apu = ApuModel()
    write(apu, 0x4013, 0)
    starts = 0
    for mask in (0x1F, 0, 0x0F, 0x10, 0x10, 0, 0x1F, 0):
        before = apu.dmc.bytes_remaining
        write(apu, APU_STATUS, mask)
        starts += int(before == 0 and bool(mask & 0x10))
        assert bool(apu.channel_enable & 0x10) == bool(mask & 0x10)
        assert apu.dmc.bytes_remaining in (0, 1)
    assert starts == 3
    assert all(
        channel.length_counter == 0
        for channel in (apu.pulse1, apu.pulse2, apu.triangle, apu.noise)
    )


def test_reset_all_active_clears_every_complete_apu_state() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    service_dmc(apu)
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    outputs, state = apu.clock(ApuInputs(reset=True, cpu_cycle_enable=True))
    fresh = ApuModel()
    assert apu.complete_state() == fresh.complete_state()
    assert not outputs.irq
    assert state == fresh.state()


def test_reset_with_frame_and_dmc_irqs_clears_both_sources() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    assert apu.evaluate(ApuInputs()).irq
    apu.clock(ApuInputs(reset=True, cpu_cycle_enable=True))
    assert not apu.frame_irq_flag and not apu.dmc.irq_flag
    assert not apu.evaluate(ApuInputs()).irq


def test_reset_with_pending_dmc_request_and_oam_boundary_is_deterministic() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    assert apu.dmc.mem_request
    oam = OamDmaModel()
    oam.trigger(0x02, cpu_cycle_odd=True)
    for _ in range(512):
        oam.cpu_slot(lambda address: address ^ 0xA5)
    assert oam.active
    apu.clock(ApuInputs(reset=True))
    oam.__init__()
    assert apu.complete_state() == ApuModel().complete_state()
    assert not oam.active and oam.phase == DmaPhase.IDLE


def test_reset_while_debugger_paused_overrides_cpu_time_freeze() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    apu.clock(ApuInputs(reset=True, cpu_cycle_enable=False))
    assert apu.complete_state() == ApuModel().complete_state()


def test_pause_all_active_freezes_complete_state_and_pending_irq() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    apu.frame_irq_flag = True
    frozen = apu.complete_state()
    held = ApuInputs(
        cpu_cycle_enable=False,
        cpu_write=True,
        cpu_address=0x4003,
        cpu_write_data=0xF8,
    )
    for _ in range(10_000):
        outputs, _ = apu.clock(held)
        assert apu.complete_state() == frozen
        assert outputs.irq


def test_single_step_all_active_accepts_one_write_and_one_time_slot() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    expected = deepcopy(apu)
    held = ApuInputs(
        cpu_cycle_enable=False,
        cpu_write=True,
        cpu_address=0x4003,
        cpu_write_data=0xF8,
    )
    for _ in range(2_000):
        apu.clock(held)
    apu.clock(ApuInputs(**{**held.__dict__, "cpu_cycle_enable": True}))
    write(expected, 0x4003, 0xF8)
    assert apu.complete_state() == expected.complete_state()


def test_oam_dma_all_active_keeps_apu_cpu_time_running() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    expected = deepcopy(apu)
    oam = OamDmaModel()
    oam.trigger(0x02, cpu_cycle_odd=False)
    slots = 0
    while oam.active:
        oam.cpu_slot(lambda address: address ^ 0x6D)
        cycle(apu)
        cycle(expected)
        slots += 1
    assert slots == 513 and oam.reads == oam.writes == 256
    assert apu.complete_state() == expected.complete_state()
    assert apu.frame_sequence_cycle != 0


def run_oam_collision(request_at: int) -> tuple[bytes, list[int], int]:
    oam = OamDmaModel()
    oam.trigger(0x03, cpu_cycle_odd=False)
    dmc = DmcDmaModel()
    request = False
    reads: list[int] = []
    wall_slot = 0
    while oam.active or request or dmc.active or wall_slot <= request_at:
        if wall_slot == request_at:
            request = True
        result = dmc.cpu_slot(
            request=request,
            request_address=0xC0DE,
            cpu_cycle_odd=bool(wall_slot & 1),
            halt_allowed=True,
            read_cpu=lambda address: reads.append(address) or 0x5E,
        )
        if result.acknowledge:
            request = False
        if not result.cpu_stall and oam.active:
            oam.cpu_slot(lambda address: address ^ 0xA7)
        wall_slot += 1
        assert wall_slot < 700
    return bytes(oam.oam), reads, wall_slot


@pytest.mark.parametrize("request_at", [0, 1, 2, 3, 100, 101, 511, 512, 513, 514])
def test_dmc_oam_collision_at_every_critical_phase(request_at: int) -> None:
    oam, reads, wall_slots = run_oam_collision(request_at)
    assert reads == [0xC0DE]
    assert oam == bytes(((0x0300 + index) ^ 0xA7) & 0xFF
                        for index in range(256))
    assert wall_slots >= 516


def test_oam_start_while_dmc_pending_acknowledged_or_buffer_empty() -> None:
    for pre_slots in (0, 1, 2):
        dmc = DmcDmaModel()
        request = True
        reads = 0
        for slot in range(pre_slots):
            result = dmc.cpu_slot(
                request=request,
                request_address=0xD123,
                cpu_cycle_odd=bool(slot & 1),
                halt_allowed=True,
                read_cpu=lambda _: 0x77,
            )
            reads += int(result.acknowledge)
            request &= not result.acknowledge
        oam = OamDmaModel()
        oam.trigger(0x04, cpu_cycle_odd=False)
        while dmc.active or request:
            result = dmc.cpu_slot(
                request=request,
                request_address=0xD123,
                cpu_cycle_odd=False,
                halt_allowed=True,
                read_cpu=lambda _: 0x77,
            )
            reads += int(result.acknowledge)
            request &= not result.acknowledge
        oam.run(lambda address: address)
        assert reads == 1 and oam.reads == oam.writes == 256


def test_dmc_stall_never_duplicates_controller_read_side_effect() -> None:
    dma = DmcDmaModel()
    request = True
    cpu_read_pending = True
    controller_shift = 0xA5
    controller_reads = 0
    for slot in range(8):
        result = dma.cpu_slot(
            request=request,
            request_address=0xC000,
            cpu_cycle_odd=bool(slot & 1),
            halt_allowed=True,
            read_cpu=lambda _: 0x5A,
        )
        if cpu_read_pending and not result.cpu_stall:
            controller_shift >>= 1
            controller_reads += 1
            cpu_read_pending = False
        if result.acknowledge:
            request = False
    assert controller_reads == 1
    assert controller_shift == (0xA5 >> 1)


def test_nrom128_dmc_fetch_uses_mirrored_upper_window() -> None:
    cart = RuntimeCartridgeModel()
    for address in range(0x4000):
        cart.loader_write(RuntimeTarget.PRG, address, (address * 13 + 7) & 0xFF)
    for address in (0x8000, 0xBFFF, 0xC000, 0xFFFF):
        assert cart.cpu_read(address, nrom_256=False) == cart.prg[
            (address - 0x8000) & 0x3FFF
        ]


def test_nrom256_dmc_fetch_keeps_banks_independent() -> None:
    cart = RuntimeCartridgeModel()
    cart.loader_write(RuntimeTarget.PRG, 0x0000, 0x11)
    cart.loader_write(RuntimeTarget.PRG, 0x4000, 0x22)
    cart.loader_write(RuntimeTarget.PRG, 0x7FFF, 0x33)
    assert cart.cpu_read(0x8000, nrom_256=True) == 0x11
    assert cart.cpu_read(0xC000, nrom_256=True) == 0x22
    assert cart.cpu_read(0xFFFF, nrom_256=True) == 0x33


def test_runtime_replacement_cancels_all_old_audio_state() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    service_dmc(apu)
    apu.frame_irq_flag = True
    apu.dmc.irq_flag = True
    apu.clock(ApuInputs(reset=True, cpu_cycle_enable=True))
    assert apu.complete_state() == ApuModel().complete_state()
    assert apu.noise.lfsr == 1
    assert not apu.dmc.mem_request and not apu.evaluate(ApuInputs()).irq


def test_unused_register_and_system_owner_isolation() -> None:
    assert decode_cpu_access(0x4014, write=True).target == CpuTarget.DMA
    assert decode_cpu_access(0x4016, write=True).target == CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4017).target == CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4017, write=True).target == CpuTarget.APU

    for address in (0x4009, 0x400D, 0x4014, 0x4016):
        tested = ApuModel()
        control = deepcopy(tested)
        write(tested, address, 0xFF)
        cycle(control)
        assert tested.complete_state() == control.complete_state()


def test_4015_status_read_preserves_every_channel_activity_source() -> None:
    apu = ApuModel()
    program_all_channels(apu)
    before = (
        apu.pulse1.length_counter,
        apu.pulse2.length_counter,
        apu.triangle.length_counter,
        apu.noise.length_counter,
        apu.dmc.bytes_remaining,
    )
    outputs, _ = read_status(apu)
    after = (
        apu.pulse1.length_counter,
        apu.pulse2.length_counter,
        apu.triangle.length_counter,
        apu.noise.length_counter,
        apu.dmc.bytes_remaining,
    )
    assert outputs.cpu_read_data & 0x1F == 0x1F
    assert after == before


def test_4017_adjacent_natural_event_suppresses_double_clock() -> None:
    apu = ApuModel()
    write(apu, APU_STATUS, 0x01)
    write(apu, 0x4000, 0x03)
    write(apu, 0x4003, 0x18)
    apu.frame_sequence_cycle = QUARTER_1 - 3
    apu.cpu_cycle_odd = False
    write(apu, APU_FRAME_COUNTER, 0x80)
    cycle(apu)
    natural, _ = cycle(apu)
    assert natural.quarter_frame_tick and not natural.half_frame_tick
    decay_after_natural = apu.pulse1.envelope_decay
    applied, _ = cycle(apu)
    assert apu.mode_5_step
    assert not applied.quarter_frame_tick and not applied.half_frame_tick
    assert apu.pulse1.envelope_decay == decay_after_natural


def test_every_4000_4013_write_changes_only_its_owned_channel() -> None:
    owners = (
        (range(0x4000, 0x4004), "pulse1"),
        (range(0x4004, 0x4008), "pulse2"),
        (range(0x4008, 0x400C), "triangle"),
        (range(0x400C, 0x4010), "noise"),
        (range(0x4010, 0x4014), "dmc"),
    )
    for addresses, owner in owners:
        for address in addresses:
            tested = ApuModel()
            control = deepcopy(tested)
            write(tested, address, 0xA5)
            cycle(control)
            tested_state = tested.complete_state()
            control_state = control.complete_state()
            for name in ("pulse1", "pulse2", "triangle", "noise", "dmc"):
                if name != owner:
                    assert getattr(tested_state, name) == getattr(control_state, name)
            if address not in (0x4009, 0x400D):
                assert getattr(tested_state, owner) != getattr(control_state, owner)


def test_dense_register_write_stress_accepts_each_write_once() -> None:
    rng = random.Random(0x5_600D)
    stepped = ApuModel()
    direct = ApuModel()
    addresses = list(range(0x4000, 0x4018))
    for _ in range(4_000):
        address = rng.choice(addresses)
        data = rng.randrange(256)
        held = ApuInputs(
            cpu_cycle_enable=False,
            cpu_write=True,
            cpu_address=address,
            cpu_write_data=data,
        )
        frozen = stepped.complete_state()
        for _ in range(rng.randrange(4)):
            stepped.clock(held)
            assert stepped.complete_state() == frozen
        stepped.clock(ApuInputs(**{**held.__dict__, "cpu_cycle_enable": True}))
        write(direct, address, data)
        if stepped.dmc.mem_request:
            stepped.clock(ApuInputs(
                cpu_cycle_enable=True,
                dmc_mem_acknowledge=True,
                dmc_mem_read_data=0x6C,
            ))
            direct.clock(ApuInputs(
                cpu_cycle_enable=True,
                dmc_mem_acknowledge=True,
                dmc_mem_read_data=0x6C,
            ))
        assert stepped.complete_state() == direct.complete_state()


def test_complete_apu_long_run_invariants_are_stable() -> None:
    rng = random.Random(0x0057_2026)
    apu = ApuModel()
    program_all_channels(apu)
    fetches = 0
    for _ in range(100_000):
        if apu.dmc.mem_request and rng.randrange(4) == 0:
            cycle(apu, dmc_mem_acknowledge=True,
                  dmc_mem_read_data=rng.randrange(256))
            fetches += 1
        elif rng.randrange(500) == 0:
            write(apu, rng.randrange(0x4000, 0x4014), rng.randrange(256))
        else:
            cycle(apu)
        state = apu.complete_state()
        assert 0 <= state.pulse1.timer_period <= 0x7FF
        assert 0 <= state.pulse2.timer_period <= 0x7FF
        assert 0 <= state.triangle.timer_period <= 0x7FF
        assert state.noise.lfsr != 0
        assert 0 <= state.dmc.output_level <= 127
        assert 1 <= state.dmc.bits_remaining <= 8
    assert fetches > 10
