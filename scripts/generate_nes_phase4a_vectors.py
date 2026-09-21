#!/usr/bin/env python3
"""Generate exhaustive read/write decode vectors for the Phase 4A RTL test."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.nes_bus import decode_cpu_access  # noqa: E402


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT")

    output = Path(sys.argv[1])
    rows = 0
    with output.open("w", encoding="ascii") as stream:
        for write in (False, True):
            for address in range(0x10000):
                decoded = decode_cpu_access(address, write=write)
                stream.write(
                    f"{address:04x} {int(write)} {int(decoded.target)} "
                    f"{decoded.ram_address:03x} {decoded.ppu_register:x}\n"
                )
                rows += 1

    print(
        "Phase 4A CPU bus vectors: "
        f"rows={rows}, addresses=65536, directions=2"
    )


if __name__ == "__main__":
    main()
