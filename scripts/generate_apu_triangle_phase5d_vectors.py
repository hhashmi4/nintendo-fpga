#!/usr/bin/env python3
"""Generate deterministic Phase 5D three-channel APU RTL/model vectors."""

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
)


RANDOM_SEED = 0x005D_2026
RANDOM_CYCLES = 300_000


def write_cycle(
    stream: TextIO,
    scenario: int,
    model: ApuFoundationModel,
    inputs: ApuInputs,
) -> None:
    outputs, state = model.clock(inputs)
    triangle_state = model.triangle.state()
    triangle_outputs = model.triangle.evaluate()
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
        outputs.triangle_output,
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
        int(triangle_outputs.active),
        triangle_outputs.raw_output,
        int(triangle_state.control_flag),
        triangle_state.linear_reload_value,
        triangle_state.linear_counter,
        int(triangle_state.linear_reload_flag),
        triangle_state.sequence_position,
        triangle_state.timer_period,
        triangle_state.timer_counter,
        triangle_state.length_counter,
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
        self.triangle_writes = 0
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
        self.triangle_writes += int(
            outputs.channel_write
            and 0x08 <= outputs.channel_write_register <= 0x0B
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


def program_pulse(
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


def program_triangle(
    vectors: VectorWriter,
    scenario: int,
    *,
    control: bool,
    reload_value: int,
    timer: int,
    length_index: int = 0,
) -> None:
    vectors.write(
        scenario,
        0x4008,
        (0x80 if control else 0) | reload_value,
    )
    vectors.write(scenario, 0x400A, timer & 0xFF)
    vectors.write(
        scenario,
        0x400B,
        (length_index << 3) | ((timer >> 8) & 0x07),
    )


def force_five_step_tick(vectors: VectorWriter, scenario: int) -> None:
    vectors.write(scenario, APU_FRAME_COUNTER, 0x80)
    for _ in range(5):
        vectors.accepted(scenario)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rng = random.Random(RANDOM_SEED)
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        vectors = VectorWriter(stream)

        # 1: register decode, reserved $4009, all length indices, and both
        # timer-byte boundaries through the real top-level bus decoder.
        vectors.cycle(1, reset=True)
        vectors.cycle(1, reset=True, cpu_cycle_enable=True)
        vectors.write(1, APU_STATUS, 0x04)
        vectors.write(1, 0x4008, 0xD5)
        vectors.write(1, 0x4009, 0xFF)
        vectors.write(1, 0x400A, 0xA5)
        for index in range(32):
            vectors.write(1, 0x400B, (index << 3) | 0x07)

        # 2: period-zero waveform visits every descending/ascending value and
        # wraps twice. The shared five-step event first loads the linear unit.
        vectors.cycle(2, reset=True, cpu_cycle_enable=True)
        vectors.write(2, APU_STATUS, 0x04)
        program_triangle(
            vectors, 2, control=True, reload_value=127, timer=0
        )
        force_five_step_tick(vectors, 2)
        for _ in range(65):
            vectors.accepted(2)

        # 3: control=0 reload/clear/decrement, then control=1 persistent reload
        # and length halt, all driven by the existing frame sequencer.
        vectors.cycle(3, reset=True, cpu_cycle_enable=True)
        vectors.write(3, APU_STATUS, 0x04)
        program_triangle(
            vectors, 3, control=False, reload_value=5, timer=3,
            length_index=3,
        )
        for _ in range(3):
            force_five_step_tick(vectors, 3)
        vectors.write(3, 0x4008, 0x80 | 9)
        vectors.write(3, 0x400B, 0x18)
        for _ in range(4):
            force_five_step_tick(vectors, 3)

        # 4: all P1/P2/T enable/status combinations and independent clearing.
        vectors.cycle(4, reset=True, cpu_cycle_enable=True)
        for mask in range(8):
            vectors.write(4, APU_STATUS, mask)
            vectors.write(4, 0x4003, 0)
            vectors.write(4, 0x4007, 0)
            vectors.write(4, 0x400B, 0)
            vectors.accepted(4, cpu_read=True, cpu_address=APU_STATUS)

        # 5: simultaneous, independent Pulse 1, Pulse 2, and Triangle tones.
        vectors.cycle(5, reset=True, cpu_cycle_enable=True)
        vectors.write(5, APU_STATUS, 0x07)
        program_pulse(vectors, 5, 0x4000, duty=3, volume=15, timer=8)
        program_pulse(vectors, 5, 0x4004, duty=2, volume=9, timer=10)
        program_triangle(
            vectors, 5, control=True, reload_value=127, timer=6,
            length_index=1,
        )
        force_five_step_tick(vectors, 5)
        for _ in range(4_096):
            vectors.accepted(5)

        # 6: debugger pause freezes NES time and cannot duplicate a held write.
        for _ in range(8_192):
            vectors.cycle(
                6,
                cpu_cycle_enable=False,
                cpu_write=True,
                cpu_address=0x400B,
                cpu_write_data=0xFF,
            )
        vectors.accepted(6)

        # 7: OAM-DMA-like CPU slots continue all channel and frame timing.
        for _ in range(2_048):
            vectors.accepted(7)

        # 8: deterministic reset from a live nonzero sequencer/counter state.
        vectors.cycle(8, reset=True, cpu_cycle_enable=True)
        vectors.accepted(8, cpu_read=True, cpu_address=APU_STATUS)

        # 9: substantial fixed-seed top-level randomized comparison. Held bus
        # strobes across pauses stress exactly-once writes and step semantics.
        held_read = False
        held_write = False
        held_address = 0
        held_data = 0
        for _ in range(RANDOM_CYCLES):
            reset = rng.randrange(55_000) == 0
            ce = rng.randrange(6) != 0
            if rng.randrange(9) == 0:
                held_address = rng.choice(
                    [
                        rng.randrange(0x4000, 0x4004),
                        rng.randrange(0x4004, 0x4008),
                        rng.choice((0x4008, 0x4009, 0x400A, 0x400B)),
                        APU_STATUS,
                        APU_FRAME_COUNTER,
                        rng.randrange(0x400C, 0x4014),
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
        "Phase 5D three-channel APU Python reference vectors: "
        f"rows={vectors.rows}, stalls={vectors.stalls}, "
        f"resets={vectors.resets}, pulse1_writes={vectors.pulse1_writes}, "
        f"pulse2_writes={vectors.pulse2_writes}, "
        f"triangle_writes={vectors.triangle_writes}, "
        f"status_reads={vectors.status_reads}, quarter={vectors.quarters}, "
        f"half={vectors.halves}, seed=0x{RANDOM_SEED:08X}"
    )


if __name__ == "__main__":
    main()
