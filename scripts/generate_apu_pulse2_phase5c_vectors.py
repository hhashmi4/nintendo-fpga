#!/usr/bin/env python3
"""Generate deterministic Phase 5C dual-pulse APU RTL/model vectors."""

from argparse import ArgumentParser
from pathlib import Path
import random
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.apu import (  # noqa: E402
    APU_FRAME_COUNTER,
    APU_STATUS,
    ApuFoundationModel,
    ApuInputs,
    PulseModel,
)


RANDOM_SEED = 0x005C_2026
RANDOM_CYCLES = 260_000


def pulse_values(pulse: PulseModel, enable: bool) -> tuple[int, ...]:
    state = pulse.state()
    outputs = pulse.evaluate(enable)
    return (
        int(outputs.active),
        outputs.raw_output,
        state.duty,
        state.duty_position,
        state.timer_period,
        state.timer_counter,
        state.length_counter,
        int(state.length_halt),
        int(state.constant_volume),
        state.envelope_period,
        int(state.envelope_start),
        state.envelope_divider,
        state.envelope_decay,
        int(state.sweep_enabled),
        state.sweep_period,
        int(state.sweep_negate),
        state.sweep_shift,
        int(state.sweep_reload),
        state.sweep_divider,
        outputs.sweep_target,
        int(outputs.sweep_mute),
    )


def write_cycle(
    stream: TextIO,
    scenario: int,
    model: ApuFoundationModel,
    inputs: ApuInputs,
) -> None:
    outputs, state = model.clock(inputs)
    pulse1 = pulse_values(model.pulse1, bool(state.channel_enable & 0x01))
    pulse2 = pulse_values(model.pulse2, bool(state.channel_enable & 0x02))
    values = (
        scenario,
        int(inputs.reset),
        int(inputs.cpu_cycle_enable),
        int(inputs.cpu_read),
        int(inputs.cpu_write),
        inputs.cpu_address,
        inputs.cpu_write_data,
        inputs.channel_active,
        int(inputs.dmc_irq_flag),
        outputs.cpu_read_data,
        int(outputs.irq),
        outputs.pulse1_output,
        outputs.pulse2_output,
        int(outputs.quarter_frame_tick),
        int(outputs.half_frame_tick),
        int(outputs.channel_write),
        outputs.channel_write_register,
        outputs.channel_write_data,
        int(outputs.dmc_irq_clear),
        state.channel_enable,
        int(state.mode_5_step),
        int(state.irq_inhibit),
        int(state.frame_irq_flag),
        state.frame_sequence_cycle,
        int(state.cpu_cycle_odd),
        int(state.frame_reset_pending),
        state.frame_reset_delay,
        int(state.frame_tick_block),
        *pulse1,
        *pulse2,
    )
    stream.write(" ".join(str(value) for value in values) + "\n")


class VectorWriter:
    def __init__(self, stream: TextIO) -> None:
        self.stream = stream
        self.model = ApuFoundationModel()
        self.rows = 0
        self.stalls = 0
        self.resets = 0
        self.pulse1_writes = 0
        self.pulse2_writes = 0
        self.status_reads = 0
        self.quarters = 0
        self.halves = 0

    def cycle(self, scenario: int, **kwargs: object) -> None:
        inputs = ApuInputs(**kwargs)
        outputs = self.model.evaluate(inputs)
        write_cycle(self.stream, scenario, self.model, inputs)
        self.rows += 1
        self.stalls += int(not inputs.cpu_cycle_enable)
        self.resets += int(inputs.reset)
        self.pulse1_writes += int(
            outputs.channel_write and outputs.channel_write_register <= 0x03
        )
        self.pulse2_writes += int(
            outputs.channel_write
            and 0x04 <= outputs.channel_write_register <= 0x07
        )
        self.status_reads += int(
            inputs.cpu_cycle_enable
            and inputs.cpu_read
            and inputs.cpu_address == APU_STATUS
        )
        self.quarters += int(outputs.quarter_frame_tick)
        self.halves += int(outputs.half_frame_tick)

    def accepted(self, scenario: int, **kwargs: object) -> None:
        self.cycle(scenario, cpu_cycle_enable=True, **kwargs)

    def write(self, scenario: int, address: int, data: int) -> None:
        self.accepted(
            scenario,
            cpu_write=True,
            cpu_address=address,
            cpu_write_data=data,
        )


def program_tone(
    vectors: VectorWriter,
    scenario: int,
    base: int,
    *,
    duty: int,
    volume: int,
    timer: int,
    length_index: int = 0,
) -> None:
    vectors.write(scenario, base, (duty << 6) | 0x10 | volume)
    vectors.write(scenario, base + 2, timer & 0xFF)
    vectors.write(
        scenario,
        base + 3,
        (length_index << 3) | ((timer >> 8) & 0x07),
    )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rng = random.Random(RANDOM_SEED)
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        vectors = VectorWriter(stream)

        # Scenario 1: reset and Pulse 2 register/duty integration through the
        # real APU top. Each duty runs long enough to visit all eight states.
        vectors.cycle(1, reset=True)
        vectors.cycle(1, reset=True, cpu_cycle_enable=True)
        vectors.write(1, APU_STATUS, 0x03)
        program_tone(vectors, 1, 0x4000, duty=3, volume=6, timer=13)
        for duty in range(4):
            program_tone(vectors, 1, 0x4004, duty=duty, volume=15, timer=8)
            for _ in range(160):
                vectors.accepted(1)

        # Scenario 2: exact simultaneous raw waveforms with distinct duties,
        # amplitudes, timer periods, phases and length-table selections.
        vectors.cycle(2, reset=True, cpu_cycle_enable=True)
        vectors.write(2, APU_STATUS, 0x03)
        program_tone(vectors, 2, 0x4000, duty=0, volume=15, timer=8)
        program_tone(
            vectors, 2, 0x4004, duty=2, volume=8, timer=10, length_index=1
        )
        for _ in range(1_024):
            vectors.accepted(2)

        # Scenario 3: different envelopes and lengths consume repeated shared
        # quarter/half clocks generated by delayed five-step applications.
        vectors.cycle(3, reset=True, cpu_cycle_enable=True)
        vectors.write(3, APU_STATUS, 0x03)
        vectors.write(3, 0x4000, 0xC2)
        vectors.write(3, 0x4004, 0xE5)
        vectors.write(3, 0x4002, 0x20)
        vectors.write(3, 0x4006, 0x30)
        vectors.write(3, 0x4003, 0x08)
        vectors.write(3, 0x4007, 0x28)
        for _ in range(48):
            vectors.write(3, APU_FRAME_COUNTER, 0x80)
            for _ in range(4):
                vectors.accepted(3)

        # Scenario 4: channel-specific negative sweep followed by positive and
        # overflow cases. The first half clock leaves periods exactly one apart.
        vectors.cycle(4, reset=True, cpu_cycle_enable=True)
        vectors.write(4, APU_STATUS, 0x03)
        for base in (0x4000, 0x4004):
            program_tone(vectors, 4, base, duty=3, volume=12, timer=0x100)
            vectors.write(4, base + 1, 0x89)
        vectors.write(4, APU_FRAME_COUNTER, 0x80)
        for _ in range(5):
            vectors.accepted(4)
        for base in (0x4000, 0x4004):
            vectors.write(4, base + 1, 0x81)
        for _ in range(20):
            vectors.write(4, APU_FRAME_COUNTER, 0x80)
            for _ in range(4):
                vectors.accepted(4)
        vectors.write(4, 0x4006, 0x56)
        vectors.write(4, 0x4007, 0x05)
        vectors.write(4, 0x4005, 0x81)
        for _ in range(64):
            vectors.accepted(4)

        # Scenario 5: all enable/status combinations and independent clearing.
        vectors.cycle(5, reset=True, cpu_cycle_enable=True)
        for mask in range(4):
            vectors.write(5, APU_STATUS, mask)
            vectors.write(5, 0x4003, 0x00)
            vectors.write(5, 0x4007, 0x08)
            vectors.accepted(5, cpu_read=True, cpu_address=APU_STATUS)
        vectors.write(5, APU_STATUS, 0x03)
        vectors.write(5, 0x4003, 0x00)
        vectors.write(5, 0x4007, 0x08)
        vectors.write(5, APU_STATUS, 0x01)
        vectors.accepted(5, cpu_read=True, cpu_address=APU_STATUS)
        vectors.write(5, APU_STATUS, 0x02)
        vectors.accepted(5, cpu_read=True, cpu_address=APU_STATUS)

        # Scenario 6: debugger pause cannot duplicate hostile held Pulse 2
        # writes or advance either channel's timer/frame-controlled state.
        vectors.cycle(6, reset=True, cpu_cycle_enable=True)
        vectors.write(6, APU_STATUS, 0x03)
        program_tone(vectors, 6, 0x4000, duty=3, volume=15, timer=8)
        program_tone(vectors, 6, 0x4004, duty=1, volume=9, timer=11)
        for _ in range(8_192):
            vectors.cycle(
                6,
                cpu_cycle_enable=False,
                cpu_write=True,
                cpu_address=0x4007,
                cpu_write_data=0xFF,
            )
        vectors.accepted(6)

        # Scenario 7: OAM DMA supplies complete CPU-time slots but no CPU bus
        # traffic. Both independent timers continue on their shared APU phase.
        vectors.cycle(7, reset=True, cpu_cycle_enable=True)
        vectors.write(7, APU_STATUS, 0x03)
        program_tone(vectors, 7, 0x4000, duty=3, volume=14, timer=8)
        program_tone(vectors, 7, 0x4004, duty=2, volume=7, timer=12)
        for _ in range(2_048):
            vectors.accepted(7)

        # Scenario 8: reset while channels have intentionally divergent state.
        for _ in range(4):
            vectors.write(8, APU_FRAME_COUNTER, 0x80)
            for _ in range(4):
                vectors.accepted(8)
        vectors.cycle(8, reset=True, cpu_cycle_enable=True)
        vectors.accepted(8, cpu_read=True, cpu_address=APU_STATUS)

        # Scenario 9: fixed-seed top-level randomized comparison. Addresses are
        # weighted toward both pulse banks while retaining status/control,
        # unrelated APU registers, pauses, resets and external future status.
        held_read = False
        held_write = False
        held_address = 0
        held_data = 0
        for _ in range(RANDOM_CYCLES):
            reset = rng.randrange(50_000) == 0
            ce = rng.randrange(6) != 0
            if rng.randrange(11) == 0:
                held_address = rng.choice(
                    [
                        rng.randrange(0x4000, 0x4004),
                        rng.randrange(0x4004, 0x4008),
                        APU_STATUS,
                        APU_FRAME_COUNTER,
                        rng.randrange(0x4008, 0x4014),
                        0x4014,
                        0x4016,
                        0x8000,
                    ]
                )
                held_data = rng.randrange(256)
                held_write = rng.randrange(3) != 0
                held_read = not held_write
            elif ce:
                held_read = False
                held_write = False
            vectors.cycle(
                9,
                reset=reset,
                cpu_cycle_enable=ce,
                cpu_read=held_read,
                cpu_write=held_write,
                cpu_address=held_address,
                cpu_write_data=held_data,
                channel_active=rng.randrange(32),
                dmc_irq_flag=bool(rng.randrange(2)),
            )

    print(
        "Phase 5C dual-pulse APU Python reference vectors: "
        f"rows={vectors.rows}, stalls={vectors.stalls}, "
        f"resets={vectors.resets}, pulse1_writes={vectors.pulse1_writes}, "
        f"pulse2_writes={vectors.pulse2_writes}, "
        f"status_reads={vectors.status_reads}, quarter={vectors.quarters}, "
        f"half={vectors.halves}, seed=0x{RANDOM_SEED:08X}"
    )


if __name__ == "__main__":
    main()
