#!/usr/bin/env python3
"""Generate deterministic Phase 5A APU model-comparison vectors."""

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
    FIVE_STEP_END,
    FOUR_STEP_END,
    QUARTER_1,
    ApuFoundationModel,
    ApuInputs,
)


RANDOM_SEED = 0x005A_2026


def write_cycle(
    stream: TextIO,
    scenario: int,
    model: ApuFoundationModel,
    inputs: ApuInputs,
) -> None:
    outputs, state = model.clock(inputs)
    stream.write(
        f"{scenario:d} {int(inputs.reset):d} "
        f"{int(inputs.cpu_cycle_enable):d} {int(inputs.cpu_read):d} "
        f"{int(inputs.cpu_write):d} {inputs.cpu_address:04x} "
        f"{inputs.cpu_write_data:02x} {inputs.channel_active:02x} "
        f"{int(inputs.dmc_irq_flag):d} "
        f"{outputs.cpu_read_data:02x} {int(outputs.irq):d} "
        f"{outputs.pulse1_output:01x} "
        f"{int(outputs.quarter_frame_tick):d} "
        f"{int(outputs.half_frame_tick):d} "
        f"{int(outputs.channel_write):d} "
        f"{outputs.channel_write_register:02x} "
        f"{outputs.channel_write_data:02x} "
        f"{int(outputs.dmc_irq_clear):d} "
        f"{state.channel_enable:02x} {int(state.mode_5_step):d} "
        f"{int(state.irq_inhibit):d} {int(state.frame_irq_flag):d} "
        f"{state.frame_sequence_cycle:04x} "
        f"{int(state.cpu_cycle_odd):d} "
        f"{int(state.frame_reset_pending):d} "
        f"{state.frame_reset_delay:d} "
        f"{int(state.frame_tick_block):d}\n"
    )


def enabled(**kwargs: object) -> ApuInputs:
    return ApuInputs(cpu_cycle_enable=True, **kwargs)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    model = ApuFoundationModel()
    rng = random.Random(RANDOM_SEED)
    rows = 0
    stalls = 0
    resets = 0
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        # Scenario 1: deterministic reset plus complete channel-register and
        # status/control decode, including a held bus during disabled slots.
        for _ in range(2):
            write_cycle(stream, 1, model, ApuInputs(reset=True))
            rows += 1
            resets += 1
        for address in range(0x4000, 0x4014):
            write_cycle(
                stream,
                1,
                model,
                enabled(
                    cpu_write=True,
                    cpu_address=address,
                    cpu_write_data=(address * 37) & 0xFF,
                ),
            )
            rows += 1
        held = ApuInputs(
            cpu_cycle_enable=False,
            cpu_write=True,
            cpu_address=APU_STATUS,
            cpu_write_data=0x1F,
        )
        for _ in range(257):
            write_cycle(stream, 1, model, held)
            rows += 1
            stalls += 1
        for inputs in (
            enabled(cpu_write=True, cpu_address=APU_STATUS, cpu_write_data=0x15),
            enabled(
                cpu_read=True,
                cpu_address=APU_STATUS,
                channel_active=0x0A,
                dmc_irq_flag=True,
            ),
            enabled(cpu_read=True, cpu_address=0x4000, channel_active=0x1F),
        ):
            write_cycle(stream, 1, model, inputs)
            rows += 1

        # Scenario 2: full natural 4-step sequence with pseudo-random fabric
        # stalls. These stalls represent debugger pause gaps, not NES time.
        write_cycle(stream, 2, model, ApuInputs(reset=True))
        rows += 1
        resets += 1
        accepted = 0
        while accepted < FOUR_STEP_END + 8:
            ce = rng.randrange(5) != 0
            inputs = ApuInputs(
                cpu_cycle_enable=ce,
                cpu_read=accepted == FOUR_STEP_END + 1,
                cpu_address=APU_STATUS,
                channel_active=accepted & 0x1F,
            )
            write_cycle(stream, 2, model, inputs)
            rows += 1
            accepted += int(ce)
            stalls += int(not ce)

        # Scenario 3: parity-dependent 5-step application and a complete
        # 5-step sequence. Its $4017 inhibit bit is deliberately clear.
        write_cycle(stream, 3, model, ApuInputs(reset=True))
        rows += 1
        resets += 1
        write_cycle(stream, 3, model, enabled())  # odd write parity
        rows += 1
        write_cycle(
            stream,
            3,
            model,
            enabled(
                cpu_write=True,
                cpu_address=APU_FRAME_COUNTER,
                cpu_write_data=0x80,
            ),
        )
        rows += 1
        for _ in range(4):
            write_cycle(stream, 3, model, enabled())
            rows += 1
        for _ in range(FIVE_STEP_END + 2):
            write_cycle(stream, 3, model, enabled())
            rows += 1

        # Scenario 4: a natural quarter-frame event immediately before the
        # delayed 5-step application. The application must not double-clock
        # the controlled units on adjacent CPU cycles.
        write_cycle(stream, 4, model, ApuInputs(reset=True))
        rows += 1
        resets += 1
        for _ in range(QUARTER_1 - 3):
            write_cycle(stream, 4, model, enabled())
            rows += 1
        write_cycle(
            stream,
            4,
            model,
            enabled(
                cpu_write=True,
                cpu_address=APU_FRAME_COUNTER,
                cpu_write_data=0x80,
            ),
        )
        rows += 1
        for _ in range(3):
            write_cycle(stream, 4, model, enabled())
            rows += 1

        # Scenario 5: broad randomized bus/control/reset/enable interaction.
        for _ in range(60_000):
            address = rng.choice(
                [
                    rng.randrange(0x3FF0, 0x4030),
                    APU_STATUS,
                    APU_FRAME_COUNTER,
                    0x4014,
                    0x4016,
                    0x8000,
                ]
            )
            inputs = ApuInputs(
                reset=rng.randrange(8_000) == 0,
                cpu_cycle_enable=rng.randrange(6) != 0,
                cpu_read=rng.randrange(8) == 0,
                cpu_write=rng.randrange(7) == 0,
                cpu_address=address,
                cpu_write_data=rng.randrange(256),
                channel_active=rng.randrange(32),
                dmc_irq_flag=bool(rng.randrange(2)),
            )
            write_cycle(stream, 5, model, inputs)
            rows += 1
            stalls += int(not inputs.cpu_cycle_enable)
            resets += int(inputs.reset)

    print(
        "Phase 5A APU Python reference vectors: "
        f"rows={rows}, stalls={stalls}, resets={resets}, "
        f"seed=0x{RANDOM_SEED:08X}"
    )


if __name__ == "__main__":
    main()
