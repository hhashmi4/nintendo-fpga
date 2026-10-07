#!/usr/bin/env python3
"""Generate complete Phase 5G APU vectors, including the Phase 5H mix."""

from __future__ import annotations

from argparse import ArgumentParser
from pathlib import Path
import random
import sys
from typing import Iterable, TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.apu import (  # noqa: E402
    APU_FRAME_COUNTER,
    APU_STATUS,
    HALF_1,
    QUARTER_1,
    ApuInputs,
    ApuModel,
)


RANDOM_SEED = 0x0057_2026
RANDOM_CYCLES = 600_000

INPUT_WIDTH = 43
EVENT_WIDTH = 86
STATE_WIDTH = 377
POST_WIDTH = EVENT_WIDTH + STATE_WIDTH


def packed(fields: Iterable[tuple[int | bool, int]], width: int) -> int:
    result = 0
    used = 0
    for value, field_width in fields:
        numeric = int(value)
        if not 0 <= numeric < (1 << field_width):
            raise ValueError(f"value {numeric} does not fit {field_width} bits")
        result = (result << field_width) | numeric
        used += field_width
    if used != width:
        raise AssertionError(f"packed {used} bits, expected {width}")
    return result


def pack_inputs(inputs: ApuInputs) -> int:
    return packed(
        (
            (inputs.reset, 1),
            (inputs.cpu_cycle_enable, 1),
            (inputs.cpu_read, 1),
            (inputs.cpu_write, 1),
            (inputs.cpu_address, 16),
            (inputs.cpu_write_data, 8),
            (inputs.channel_active, 5),
            (inputs.dmc_irq_flag, 1),
            (inputs.dmc_mem_acknowledge, 1),
            (inputs.dmc_mem_read_data, 8),
        ),
        INPUT_WIDTH,
    )


def pack_event(outputs) -> int:
    return packed(
        (
            (outputs.cpu_read_data, 8),
            (outputs.irq, 1),
            (outputs.pulse1_output, 4),
            (outputs.pulse2_output, 4),
            (outputs.triangle_output, 4),
            (outputs.noise_output, 4),
            (outputs.dmc_output, 7),
            (outputs.mixed_audio, 20),
            (outputs.quarter_frame_tick, 1),
            (outputs.half_frame_tick, 1),
            (outputs.channel_write, 1),
            (outputs.channel_write_register, 5),
            (outputs.channel_write_data, 8),
            (outputs.dmc_irq_clear, 1),
            (outputs.dmc_mem_request, 1),
            (outputs.dmc_mem_address, 16),
        ),
        EVENT_WIDTH,
    )


def pulse_fields(state) -> tuple[tuple[int | bool, int], ...]:
    return (
        (state.duty, 2),
        (state.duty_position, 3),
        (state.timer_period, 11),
        (state.timer_counter, 11),
        (state.length_counter, 8),
        (state.length_halt, 1),
        (state.constant_volume, 1),
        (state.envelope_period, 4),
        (state.envelope_start, 1),
        (state.envelope_divider, 4),
        (state.envelope_decay, 4),
        (state.sweep_enabled, 1),
        (state.sweep_period, 3),
        (state.sweep_negate, 1),
        (state.sweep_shift, 3),
        (state.sweep_reload, 1),
        (state.sweep_divider, 3),
    )


def pack_state(model: ApuModel) -> int:
    complete = model.complete_state()
    frame = complete.frame
    triangle = complete.triangle
    noise = complete.noise
    dmc = complete.dmc
    fields = (
        (frame.channel_enable, 5),
        (frame.mode_5_step, 1),
        (frame.irq_inhibit, 1),
        (frame.frame_irq_flag, 1),
        (frame.frame_sequence_cycle, 16),
        (frame.cpu_cycle_odd, 1),
        (frame.frame_reset_pending, 1),
        (frame.frame_reset_delay, 3),
        (frame.frame_tick_block, 1),
        *pulse_fields(complete.pulse1),
        *pulse_fields(complete.pulse2),
        (triangle.control_flag, 1),
        (triangle.linear_reload_value, 7),
        (triangle.linear_counter, 7),
        (triangle.linear_reload_flag, 1),
        (triangle.sequence_position, 5),
        (triangle.timer_period, 11),
        (triangle.timer_counter, 11),
        (triangle.length_counter, 8),
        (noise.length_halt, 1),
        (noise.constant_volume, 1),
        (noise.envelope_period, 4),
        (noise.envelope_start, 1),
        (noise.envelope_divider, 4),
        (noise.envelope_decay, 4),
        (noise.mode, 1),
        (noise.period_index, 4),
        (model.noise.timer_period, 12),
        (noise.timer_counter, 11),
        (noise.length_counter, 8),
        (noise.lfsr, 15),
        (dmc.irq_enable, 1),
        (dmc.loop, 1),
        (dmc.rate_index, 4),
        (dmc.sample_address_register, 8),
        (dmc.sample_length_register, 8),
        (dmc.current_address, 16),
        (dmc.bytes_remaining, 12),
        (dmc.sample_buffer, 8),
        (dmc.sample_buffer_empty, 1),
        (dmc.shift_register, 8),
        (dmc.bits_remaining, 4),
        (dmc.silence, 1),
        (dmc.output_level, 7),
        (dmc.timer_counter, 9),
        (dmc.mem_request, 1),
        (dmc.mem_address, 16),
        (dmc.irq_flag, 1),
    )
    return packed(fields, STATE_WIDTH)


class Vectors:
    def __init__(self, stream: TextIO) -> None:
        self.stream = stream
        self.model = ApuModel()
        self.rows = 0
        self.stalls = 0
        self.resets = 0
        self.reads = 0
        self.writes = 0
        self.acknowledgements = 0
        self.quarters = 0
        self.halves = 0
        self.all_active = 0
        self.all_nonzero = 0
        self.status_seen = 0

    def cycle(self, scenario: int, **kwargs: object) -> None:
        inputs = ApuInputs(**kwargs)
        pre = self.model.evaluate(inputs)
        _, state = self.model.clock(inputs)
        post = self.model.evaluate(inputs)
        post_value = (pack_event(post) << STATE_WIDTH) | pack_state(self.model)
        self.stream.write(
            f"{scenario} {pack_inputs(inputs):x} {pack_event(pre):x} "
            f"{post_value:x}\n"
        )
        self.rows += 1
        self.stalls += int(not inputs.cpu_cycle_enable)
        self.resets += int(inputs.reset)
        self.reads += int(inputs.cpu_cycle_enable and inputs.cpu_read)
        self.writes += int(inputs.cpu_cycle_enable and inputs.cpu_write)
        self.acknowledgements += int(
            inputs.cpu_cycle_enable and inputs.dmc_mem_acknowledge
        )
        self.quarters += int(pre.quarter_frame_tick)
        self.halves += int(pre.half_frame_tick)
        active_mask = (
            int(self.model.pulse1.length_counter != 0)
            | (int(self.model.pulse2.length_counter != 0) << 1)
            | (int(self.model.triangle.length_counter != 0) << 2)
            | (int(self.model.noise.length_counter != 0) << 3)
            | (int(self.model.dmc.bytes_remaining != 0) << 4)
        )
        self.all_active += int(active_mask == 0x1F)
        self.all_nonzero += int(
            post.pulse1_output != 0
            and post.pulse2_output != 0
            and post.triangle_output != 0
            and post.noise_output != 0
            and post.dmc_output != 0
        )
        if inputs.cpu_cycle_enable and inputs.cpu_read and (
            inputs.cpu_address == APU_STATUS
        ):
            self.status_seen |= 1 << (pre.cpu_read_data & 0x1F)
        assert state == self.model.state()

    def accepted(self, scenario: int, **kwargs: object) -> None:
        self.cycle(scenario, cpu_cycle_enable=True, **kwargs)

    def write(self, scenario: int, address: int, data: int) -> None:
        self.accepted(
            scenario,
            cpu_write=True,
            cpu_address=address,
            cpu_write_data=data,
        )

    def status(self, scenario: int) -> None:
        self.accepted(scenario, cpu_read=True, cpu_address=APU_STATUS)

    def idle_until_frame_cycle(self, scenario: int, target: int) -> None:
        limit = 50_000
        while self.model.frame_sequence_cycle != target:
            self.accepted(scenario)
            limit -= 1
            if limit == 0:
                raise AssertionError(f"frame cycle {target} not reached")

    def acknowledge(self, scenario: int, data: int | None = None) -> None:
        if not self.model.dmc.mem_request:
            raise AssertionError("DMC acknowledge requested without a request")
        address = self.model.dmc.mem_address
        sample = ((address >> 8) ^ address ^ 0xA5) & 0xFF
        self.accepted(
            scenario,
            dmc_mem_acknowledge=True,
            dmc_mem_read_data=sample if data is None else data,
        )


def program_all(vectors: Vectors, scenario: int) -> None:
    vectors.write(scenario, APU_STATUS, 0x0F)
    for address, data in (
        (0x4000, 0xFF), (0x4001, 0x91),
        (0x4002, 0x08), (0x4003, 0x08),
        (0x4004, 0xBA), (0x4005, 0x99),
        (0x4006, 0x80), (0x4007, 0x08),
        (0x4008, 0xFF), (0x4009, 0xA5),
        (0x400A, 0x06), (0x400B, 0x08),
        (0x400C, 0x3D), (0x400D, 0x5A),
        (0x400E, 0x82), (0x400F, 0x08),
        (0x4010, 0x8F), (0x4011, 0x40),
        (0x4012, 0x40), (0x4013, 0x01),
    ):
        vectors.write(scenario, address, data)
    vectors.write(scenario, APU_STATUS, 0x1F)
    vectors.write(scenario, APU_FRAME_COUNTER, 0x80)
    while vectors.model.frame_reset_pending:
        vectors.accepted(scenario)


def generate(stream: TextIO) -> Vectors:
    vectors = Vectors(stream)
    rng = random.Random(RANDOM_SEED)

    # 1: deterministic reset and complete $4000-$4017 write isolation. The
    # system-owned $4014/$4016 registers and reserved $4009/$400D are present.
    vectors.cycle(1, reset=True)
    vectors.cycle(1, reset=True, cpu_cycle_enable=True)
    for address in range(0x4000, 0x4018):
        vectors.write(1, address, ((address * 37) ^ 0xA5) & 0xFF)
    vectors.status(1)

    # 2: all 32 enable/real-activity status compositions.
    for mask in range(32):
        vectors.cycle(2, reset=True, cpu_cycle_enable=True)
        vectors.write(2, 0x4012, 0x20)
        vectors.write(2, 0x4013, 0x00)
        vectors.write(2, APU_STATUS, mask)
        for address in (0x4003, 0x4007, 0x400B, 0x400F):
            vectors.write(2, address, 0x08)
        vectors.status(2)

    # 3: all five channels active together through multiple frame events and
    # a complete 17-byte DMC sample.
    vectors.cycle(3, reset=True, cpu_cycle_enable=True)
    program_all(vectors, 3)
    for index in range(80_000):
        if vectors.model.dmc.mem_request:
            vectors.acknowledge(3, (index * 37 + 0x53) & 0xFF)
        else:
            vectors.accepted(3)

    # 4: DMC-only IRQ, simultaneous DMC/frame IRQ, frame read-clear while DMC
    # remains, and $4015 write-clear while a frame source can remain.
    vectors.cycle(4, reset=True, cpu_cycle_enable=True)
    vectors.write(4, 0x4010, 0x80)
    vectors.write(4, 0x4013, 0x00)
    vectors.write(4, APU_STATUS, 0x10)
    vectors.acknowledge(4, 0x55)
    vectors.status(4)
    while not vectors.model.frame_irq_flag:
        vectors.accepted(4)
    vectors.status(4)
    vectors.write(4, APU_STATUS, 0x00)
    while not vectors.model.frame_irq_flag:
        vectors.accepted(4)
    vectors.write(4, APU_STATUS, 0x00)
    vectors.status(4)

    # 5: actual channel writes immediately before, on, and after quarter/half
    # events, followed by both $4017 parity delays and a five-step clock.
    vectors.cycle(5, reset=True, cpu_cycle_enable=True)
    program_all(vectors, 5)
    vectors.idle_until_frame_cycle(5, QUARTER_1 - 2)
    vectors.write(5, 0x4003, 0x08)
    vectors.accepted(5)
    vectors.idle_until_frame_cycle(5, HALF_1 - 1)
    vectors.write(5, 0x4001, 0xA2)
    vectors.write(5, 0x400B, 0x20)
    vectors.write(5, APU_FRAME_COUNTER, 0x80)
    while vectors.model.frame_reset_pending:
        vectors.accepted(5)
    if not vectors.model.cpu_cycle_odd:
        vectors.accepted(5)
    vectors.write(5, APU_FRAME_COUNTER, 0x80)
    while vectors.model.frame_reset_pending:
        vectors.accepted(5)

    # 6: debugger-style pause with held bus levels, then exactly one step and
    # deterministic resumed all-channel time.
    for _ in range(10_000):
        vectors.cycle(
            6,
            cpu_cycle_enable=False,
            cpu_write=True,
            cpu_address=0x400F,
            cpu_write_data=0xF8,
        )
    vectors.write(6, 0x400F, 0xF8)
    for _ in range(4_096):
        if vectors.model.dmc.mem_request:
            vectors.acknowledge(6)
        else:
            vectors.accepted(6)

    # 7: functional reset while all sources, frame state, and a held DMC
    # request are live; post-reset state must match power-on deterministically.
    if not vectors.model.dmc.mem_request:
        vectors.write(7, APU_STATUS, 0x00)
        vectors.write(7, APU_STATUS, 0x1F)
    vectors.cycle(7, reset=True, cpu_cycle_enable=True)
    vectors.accepted(7)
    program_all(vectors, 7)

    # 8: dense deterministic traffic across the full system register window.
    for index in range(20_000):
        if vectors.model.dmc.mem_request and index % 7 == 0:
            vectors.acknowledge(8)
        else:
            address = 0x4000 + (index * 11 % 0x18)
            vectors.write(8, address, (index * 73 + 0x31) & 0xFF)

    # 9: substantially larger fixed-seed complete-APU randomized comparison.
    # External compatibility status inputs stay low: all status/IRQ behavior
    # in this closure run comes from the five implemented channels.
    held_read = False
    held_write = False
    held_address = 0x4000
    held_data = 0
    for _ in range(RANDOM_CYCLES):
        reset = rng.randrange(75_000) == 0
        cpu_enable = rng.randrange(6) != 0
        if reset:
            vectors.cycle(9, reset=True, cpu_cycle_enable=cpu_enable)
            held_read = False
            held_write = False
        elif vectors.model.dmc.mem_request and cpu_enable and rng.randrange(4) == 0:
            vectors.acknowledge(9, rng.randrange(256))
            held_read = False
            held_write = False
        else:
            if rng.randrange(8) == 0:
                held_address = rng.choice(
                    list(range(0x4000, 0x4018)) + [0x1234, 0x8000]
                )
                held_data = rng.randrange(256)
                held_write = rng.randrange(4) != 0
                held_read = not held_write
            elif cpu_enable:
                held_read = False
                held_write = False
            vectors.cycle(
                9,
                cpu_cycle_enable=cpu_enable,
                cpu_read=held_read,
                cpu_write=held_write,
                cpu_address=held_address,
                cpu_write_data=held_data,
            )

    # 10: Phase 5H integration closure: long digital silence, simultaneous
    # five-channel activity, then deterministic channel-disable transitions.
    vectors.cycle(10, reset=True, cpu_cycle_enable=True)
    for _ in range(4_096):
        vectors.accepted(10)
    program_all(vectors, 10)
    for _ in range(8_192):
        if vectors.model.dmc.mem_request:
            vectors.acknowledge(10)
        else:
            vectors.accepted(10)
    for enable_mask in (0x1E, 0x1C, 0x18, 0x10, 0x00):
        vectors.write(10, APU_STATUS, enable_mask)
        for _ in range(512):
            if vectors.model.dmc.mem_request:
                vectors.acknowledge(10)
            else:
                vectors.accepted(10)

    return vectors


def main() -> int:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        vectors = generate(stream)
    print(
        "Phase 5G complete APU Python reference: "
        f"rows={vectors.rows} stalls={vectors.stalls} resets={vectors.resets} "
        f"reads={vectors.reads} writes={vectors.writes} "
        f"acks={vectors.acknowledgements} quarter={vectors.quarters} "
        f"half={vectors.halves} all_active={vectors.all_active} "
        f"all_nonzero={vectors.all_nonzero} seed=0x{RANDOM_SEED:08x}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
