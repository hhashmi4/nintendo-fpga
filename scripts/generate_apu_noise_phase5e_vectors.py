#!/usr/bin/env python3
"""Generate deterministic Phase 5E four-channel APU RTL/model vectors."""

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


RANDOM_SEED = 0x005E_2026
RANDOM_CYCLES = 350_000


def write_cycle(
    stream: TextIO,
    scenario: int,
    model: ApuFoundationModel,
    inputs: ApuInputs,
) -> bool:
    lfsr_shift = (
        not inputs.reset
        and inputs.cpu_cycle_enable
        and not model.cpu_cycle_odd
        and model.noise.timer_counter == 0
    )
    outputs, state = model.clock(inputs)
    noise_state = model.noise.state()
    noise_outputs = model.noise.evaluate(bool(model.channel_enable & 0x08))
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
        outputs.noise_output,
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
        int(noise_outputs.active),
        noise_outputs.raw_output,
        int(noise_state.length_halt),
        int(noise_state.constant_volume),
        noise_state.envelope_period,
        int(noise_state.envelope_start),
        noise_state.envelope_divider,
        noise_state.envelope_decay,
        int(noise_state.mode),
        noise_state.period_index,
        model.noise.timer_period,
        noise_state.timer_counter,
        noise_state.length_counter,
        noise_state.lfsr,
        int(lfsr_shift),
    )
    stream.write(" ".join(str(value) for value in values) + "\n")
    return lfsr_shift


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
        self.noise_writes = 0
        self.status_reads = 0
        self.quarters = 0
        self.halves = 0
        self.lfsr_shifts = 0

    def cycle(self, scenario: int, **kwargs: object) -> None:
        inputs = ApuInputs(**kwargs)
        outputs = self.model.evaluate(inputs)
        shifted = write_cycle(self.stream, scenario, self.model, inputs)
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
        self.noise_writes += int(
            outputs.channel_write
            and 0x0C <= outputs.channel_write_register <= 0x0F
        )
        self.status_reads += int(
            inputs.cpu_cycle_enable
            and inputs.cpu_read
            and inputs.cpu_address == APU_STATUS
        )
        self.quarters += int(outputs.quarter_frame_tick)
        self.halves += int(outputs.half_frame_tick)
        self.lfsr_shifts += int(shifted)

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
    timer: int,
    length_index: int = 0,
) -> None:
    vectors.write(scenario, 0x4008, 0xFF)
    vectors.write(scenario, 0x400A, timer & 0xFF)
    vectors.write(
        scenario,
        0x400B,
        (length_index << 3) | ((timer >> 8) & 0x07),
    )


def program_noise(
    vectors: VectorWriter,
    scenario: int,
    *,
    control: int,
    mode: bool,
    period_index: int,
    length_index: int = 0,
) -> None:
    vectors.write(scenario, 0x400C, control)
    vectors.write(
        scenario, 0x400E, (0x80 if mode else 0) | period_index
    )
    vectors.write(scenario, 0x400F, length_index << 3)


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

        # 1: reset, all three decoded registers, ignored $400D, all sixteen
        # NTSC periods, and every shared length-table entry.
        vectors.cycle(1, reset=True)
        vectors.cycle(1, reset=True, cpu_cycle_enable=True)
        vectors.write(1, APU_STATUS, 0x08)
        vectors.write(1, 0x400C, 0xAF)
        vectors.write(1, 0x400D, 0xFF)
        for index in range(16):
            vectors.write(1, 0x400E, index | ((index & 1) << 7))
        for index in range(32):
            vectors.write(1, 0x400F, index << 3)

        # 2: deterministic long-mode sequence and exact raw waveform.
        vectors.cycle(2, reset=True, cpu_cycle_enable=True)
        vectors.write(2, APU_STATUS, 0x08)
        program_noise(
            vectors, 2, control=0x3A, mode=False, period_index=0
        )
        for _ in range(256):
            vectors.accepted(2)

        # 3: short-mode sequence from the same seed, then live tap changes.
        vectors.cycle(3, reset=True, cpu_cycle_enable=True)
        vectors.write(3, APU_STATUS, 0x08)
        program_noise(
            vectors, 3, control=0x3B, mode=True, period_index=0
        )
        for _ in range(256):
            vectors.accepted(3)
        vectors.write(3, 0x400E, 0x00)
        for _ in range(128):
            vectors.accepted(3)
        vectors.write(3, 0x400E, 0x80)
        for _ in range(128):
            vectors.accepted(3)

        # 4: envelope restart/decay/loop and half-frame length/halt behavior.
        vectors.cycle(4, reset=True, cpu_cycle_enable=True)
        vectors.write(4, APU_STATUS, 0x08)
        program_noise(
            vectors, 4, control=0x02, mode=False,
            period_index=5, length_index=3,
        )
        for _ in range(8):
            force_five_step_tick(vectors, 4)
        vectors.write(4, 0x400C, 0x22)
        for _ in range(20):
            force_five_step_tick(vectors, 4)

        # 5: all implemented P1/P2/T/N enable and status combinations.
        vectors.cycle(5, reset=True, cpu_cycle_enable=True)
        for mask in range(16):
            vectors.write(5, APU_STATUS, mask)
            vectors.write(5, 0x4003, 0)
            vectors.write(5, 0x4007, 0)
            vectors.write(5, 0x400B, 0)
            vectors.write(5, 0x400F, 0)
            vectors.accepted(5, cpu_read=True, cpu_address=APU_STATUS)

        # 6: four simultaneous independent channels with distinct periods.
        vectors.cycle(6, reset=True, cpu_cycle_enable=True)
        vectors.write(6, APU_STATUS, 0x0F)
        program_pulse(vectors, 6, 0x4000, duty=3, volume=15, timer=8)
        program_pulse(vectors, 6, 0x4004, duty=2, volume=9, timer=10)
        program_triangle(vectors, 6, timer=6, length_index=1)
        program_noise(
            vectors, 6, control=0x3D, mode=True,
            period_index=2, length_index=1,
        )
        force_five_step_tick(vectors, 6)
        for _ in range(8_192):
            vectors.accepted(6)

        # 7: debugger pause freezes all NES Noise state despite a held write;
        # one resumed slot accepts it exactly once.
        for _ in range(8_192):
            vectors.cycle(
                7,
                cpu_cycle_enable=False,
                cpu_write=True,
                cpu_address=0x400F,
                cpu_write_data=0xF8,
            )
        vectors.accepted(
            7, cpu_write=True, cpu_address=0x400F, cpu_write_data=0xF8
        )
        vectors.accepted(7)

        # 8: OAM-DMA-like slots continue every channel and frame sequencer.
        for _ in range(4_096):
            vectors.accepted(8)

        # 9: active reset and post-reset status/readback determinism.
        vectors.cycle(9, reset=True, cpu_cycle_enable=True)
        vectors.accepted(9, cpu_read=True, cpu_address=APU_STATUS)

        # 10: substantial fixed-seed top-level randomized comparison. Bus
        # strobes can remain held through pauses to stress exactly-once rules.
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
                        rng.choice((0x400C, 0x400D, 0x400E, 0x400F)),
                        APU_STATUS,
                        APU_FRAME_COUNTER,
                        rng.randrange(0x4010, 0x4014),
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
                10,
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
        "Phase 5E four-channel APU Python reference vectors: "
        f"rows={vectors.rows}, stalls={vectors.stalls}, "
        f"resets={vectors.resets}, pulse1_writes={vectors.pulse1_writes}, "
        f"pulse2_writes={vectors.pulse2_writes}, "
        f"triangle_writes={vectors.triangle_writes}, "
        f"noise_writes={vectors.noise_writes}, "
        f"status_reads={vectors.status_reads}, quarter={vectors.quarters}, "
        f"half={vectors.halves}, lfsr_shifts={vectors.lfsr_shifts}, "
        f"seed=0x{RANDOM_SEED:08X}"
    )


if __name__ == "__main__":
    main()
