#!/usr/bin/env python3
"""Generate deterministic Phase 5B Pulse 1 RTL/model vectors."""

from argparse import ArgumentParser
from pathlib import Path
import random
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.apu import Pulse1Model, PulseInputs  # noqa: E402


RANDOM_SEED = 0x005B_2026
RANDOM_CYCLES = 210_000


def write_cycle(
    stream: TextIO,
    scenario: int,
    model: Pulse1Model,
    inputs: PulseInputs,
) -> None:
    model.clock(inputs)
    state = model.state()
    outputs = model.evaluate(inputs.enable)
    values = (
        scenario,
        int(inputs.reset),
        int(inputs.cpu_cycle_enable),
        int(inputs.timer_tick),
        int(inputs.enable),
        int(inputs.write),
        inputs.write_register,
        inputs.write_data,
        int(inputs.quarter_frame_tick),
        int(inputs.half_frame_tick),
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
    stream.write(" ".join(str(value) for value in values) + "\n")


class VectorWriter:
    def __init__(self, stream: TextIO) -> None:
        self.stream = stream
        self.model = Pulse1Model()
        self.rows = 0
        self.stalls = 0
        self.resets = 0
        self.writes = 0
        self.quarters = 0
        self.halves = 0
        self.timer_ticks = 0

    def cycle(self, scenario: int, **kwargs: object) -> None:
        inputs = PulseInputs(**kwargs)
        write_cycle(self.stream, scenario, self.model, inputs)
        self.rows += 1
        self.stalls += int(not inputs.cpu_cycle_enable)
        self.resets += int(inputs.reset)
        self.writes += int(inputs.write and inputs.cpu_cycle_enable)
        self.quarters += int(inputs.quarter_frame_tick and inputs.cpu_cycle_enable)
        self.halves += int(inputs.half_frame_tick and inputs.cpu_cycle_enable)
        self.timer_ticks += int(inputs.timer_tick)

    def accepted(self, scenario: int, **kwargs: object) -> None:
        self.cycle(scenario, cpu_cycle_enable=True, enable=True, **kwargs)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rng = random.Random(RANDOM_SEED)
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        vectors = VectorWriter(stream)

        # Scenario 1: reset, all register fields, all duty modes and the full
        # eight-position waveform for each mode.
        vectors.cycle(1, reset=True)
        vectors.cycle(1, reset=True, cpu_cycle_enable=True)
        for duty in range(4):
            vectors.accepted(
                1, write=True, write_register=0, write_data=(duty << 6) | 0x1F
            )
            vectors.accepted(1, write=True, write_register=2, write_data=8)
            vectors.accepted(1, write=True, write_register=3, write_data=0)
            for _ in range(8 * 9 + 1):
                vectors.accepted(1, timer_tick=True)
                vectors.accepted(1, timer_tick=False)

        # Scenario 2: every length-table index plus halt, disable and re-enable
        # behavior. Half ticks deliberately include their quarter tick.
        vectors.cycle(2, reset=True, cpu_cycle_enable=True)
        for index in range(32):
            vectors.accepted(2, write=True, write_register=3, write_data=index << 3)
            vectors.accepted(2, quarter_frame_tick=True, half_frame_tick=True)
        vectors.accepted(2, write=True, write_register=0, write_data=0x20)
        for _ in range(8):
            vectors.accepted(2, quarter_frame_tick=True, half_frame_tick=True)
        vectors.cycle(2, cpu_cycle_enable=True, enable=False)
        vectors.accepted(2)

        # Scenario 3: envelope start/decay/loop and positive/negative/overflow
        # sweep paths, including register rewrites while frame clocks occur.
        vectors.cycle(3, reset=True, cpu_cycle_enable=True)
        for control in (0x02, 0x22, 0x1F, 0x3F):
            vectors.accepted(3, write=True, write_register=0, write_data=control)
            vectors.accepted(3, write=True, write_register=3, write_data=0xF8)
            for _ in range(48):
                vectors.accepted(3, quarter_frame_tick=True)
        for low, high, sweep in (
            (0x00, 0x01, 0xB1),
            (0x00, 0x01, 0xB9),
            (0x55, 0x05, 0x81),
            (0x56, 0x05, 0x81),
            (0x00, 0x06, 0x80),
        ):
            vectors.accepted(3, write=True, write_register=2, write_data=low)
            vectors.accepted(3, write=True, write_register=3, write_data=high)
            vectors.accepted(3, write=True, write_register=1, write_data=sweep)
            for _ in range(16):
                vectors.accepted(3, quarter_frame_tick=True, half_frame_tick=True)

        # Scenario 4: debugger pause. Even hostile held inputs and frame-event
        # levels cannot change state without a complete NES CPU-time slot.
        vectors.cycle(4, reset=True, cpu_cycle_enable=True)
        vectors.accepted(4, write=True, write_register=0, write_data=0xFF)
        vectors.accepted(4, write=True, write_register=2, write_data=0x08)
        vectors.accepted(4, write=True, write_register=3, write_data=0xF8)
        for _ in range(8_192):
            vectors.cycle(
                4,
                cpu_cycle_enable=False,
                enable=True,
                write=True,
                write_register=3,
                write_data=0xFF,
                quarter_frame_tick=True,
                half_frame_tick=True,
            )

        # Scenario 5: OAM DMA still presents CPU-time slots. With no CPU bus
        # writes, the alternating APU phase continues the pulse timer.
        vectors.cycle(5, reset=True, cpu_cycle_enable=True)
        vectors.accepted(5, write=True, write_register=0, write_data=0xDF)
        vectors.accepted(5, write=True, write_register=2, write_data=0x08)
        vectors.accepted(5, write=True, write_register=3, write_data=0xF8)
        for cpu_slot in range(1_024):
            vectors.accepted(5, timer_tick=(cpu_slot & 1) == 0)

        # Scenario 6: fixed-seed randomized model comparison. Timer phase is
        # toggled only by accepted CPU slots, as it is in the APU top level.
        vectors.cycle(6, reset=True, cpu_cycle_enable=True)
        apu_phase = False
        enabled = False
        held_write = False
        held_register = 0
        held_data = 0
        for _ in range(RANDOM_CYCLES):
            reset = rng.randrange(20_000) == 0
            ce = rng.randrange(6) != 0
            if rng.randrange(251) == 0:
                enabled = not enabled
            if rng.randrange(19) == 0:
                held_write = True
                held_register = rng.randrange(4)
                held_data = rng.randrange(256)
            elif ce:
                held_write = False
            quarter = ce and rng.randrange(89) == 0
            half = quarter and rng.randrange(2) == 0
            timer_tick = ce and not apu_phase
            vectors.cycle(
                6,
                reset=reset,
                cpu_cycle_enable=ce,
                timer_tick=timer_tick,
                enable=enabled,
                write=held_write,
                write_register=held_register,
                write_data=held_data,
                quarter_frame_tick=quarter,
                half_frame_tick=half,
            )
            if reset:
                apu_phase = False
            elif ce:
                apu_phase = not apu_phase

    print(
        "Phase 5B Pulse 1 Python reference vectors: "
        f"rows={vectors.rows}, stalls={vectors.stalls}, "
        f"resets={vectors.resets}, writes={vectors.writes}, "
        f"quarter={vectors.quarters}, half={vectors.halves}, "
        f"timer_ticks={vectors.timer_ticks}, seed=0x{RANDOM_SEED:08X}"
    )


if __name__ == "__main__":
    main()
