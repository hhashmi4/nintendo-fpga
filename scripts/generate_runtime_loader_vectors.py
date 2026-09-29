#!/usr/bin/env python3
"""Generate deterministic model-based Phase 4F-A loader cycle vectors."""

from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.runtime_loader import Command, RuntimeLoader, Target  # noqa: E402


SEED = 0x4FA2026
CYCLES = 4096


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT")

    random_source = random.Random(SEED)
    model = RuntimeLoader()
    pending = None
    accepted_writes = 0
    output_path = Path(sys.argv[1])

    with output_path.open("w", encoding="ascii") as stream:
        for cycle in range(CYCLES):
            reset = cycle < 2 or random_source.randrange(197) == 0
            storage_ready = bool(random_source.randrange(3))

            if reset:
                pending = None
                valid, command, target, address, data = (
                    True,
                    Command.WRITE,
                    Target.PRG,
                    0x1234,
                    0xA5,
                )
            elif pending is not None:
                valid, command, target, address, data = pending
            else:
                valid = random_source.randrange(5) != 0
                command = Command(random_source.randrange(4))
                target = Target(random_source.randrange(4))
                address = random_source.randrange(0x10000)
                data = random_source.randrange(0x100)

            inputs = dict(
                reset=reset,
                valid=valid,
                command=command,
                target=target,
                address=address,
                data=data,
                storage_ready=storage_ready,
            )
            outputs = model.clock(**inputs)
            if outputs.write_valid and not outputs.command_accepted:
                pending = (valid, command, target, address, data)
            elif outputs.command_accepted or not valid:
                pending = None
            if outputs.write_valid and outputs.command_accepted:
                accepted_writes += 1

            fields = (
                int(reset),
                int(valid),
                int(command),
                int(target),
                address,
                data,
                int(storage_ready),
                int(outputs.command_ready),
                int(outputs.command_accepted),
                int(outputs.write_valid),
                int(outputs.write_target),
                outputs.write_address,
                outputs.write_data,
                int(outputs.state),
                int(outputs.busy),
                int(outputs.completed),
                int(outputs.error),
                int(outputs.error_code),
                int(outputs.nes_hold_reset),
            )
            stream.write(
                "%d %d %d %d %04x %02x %d %d %d %d %d %04x %02x "
                "%d %d %d %d %d %d\n" % fields
            )

    print(
        "Phase 4F-A loader vectors: "
        f"cycles={CYCLES} seed={SEED:08x} accepted_writes={accepted_writes}"
    )


if __name__ == "__main__":
    main()
