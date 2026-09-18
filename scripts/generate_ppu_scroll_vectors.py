#!/usr/bin/env python3
"""Generate deterministic standalone Phase 3D scroll-unit vectors."""

from argparse import ArgumentParser
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_scroll import (  # noqa: E402
    active_data_increment,
    active_render_period,
    apply_automatic_scroll,
    attribute_fetch_address,
    is_rendering_scanline,
    nametable_fetch_address,
)


RANDOM_SEED = 0x3D5EED01
RANDOM_CASES = 20_000


class XorShift32:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFF_FFFF

    def next(self) -> int:
        value = self.state
        value ^= (value << 13) & 0xFFFF_FFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFF_FFFF
        self.state = value & 0xFFFF_FFFF
        return self.state


def row(
    scenario: int,
    address: int,
    temporary: int,
    ppu_enable: bool,
    rendering_enabled: bool,
    dot: int,
    scanline: int,
) -> str:
    automatic, events = apply_automatic_scroll(
        address,
        temporary,
        ppu_enable=ppu_enable,
        rendering_enabled=rendering_enabled,
        scanline=scanline,
        dot=dot,
    )
    values = (
        scenario,
        address & 0x7FFF,
        temporary & 0x7FFF,
        int(ppu_enable),
        int(rendering_enabled),
        dot,
        scanline,
        int(is_rendering_scanline(scanline)),
        int(active_render_period(rendering_enabled, scanline)),
        int(events.coarse_x_increment),
        int(events.vertical_increment),
        int(events.horizontal_copy),
        int(events.vertical_copy),
        int(events.any),
        automatic,
        active_data_increment(address),
        nametable_fetch_address(address),
        attribute_fetch_address(address),
    )
    return " ".join(str(value) for value in values) + "\n"


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    counts = [0, 0, 0, 0]
    rng = XorShift32(RANDOM_SEED)
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        # Coarse-X wrap/toggle coverage: every X and horizontal NT value.
        for horizontal_nt in range(2):
            for coarse_x in range(32):
                address = 0x79E0 | (horizontal_nt << 10) | coarse_x
                stream.write(row(1, address, 0x2468, True, True, 8, 0))
                counts[0] += 1

        # Exhaustive fine-Y/coarse-Y/vertical-NT combinations. Dot 256 also
        # checks that the simultaneous X increment is retained.
        for fine_y in range(8):
            for coarse_y in range(32):
                for vertical_nt in range(2):
                    address = (
                        (fine_y << 12)
                        | (vertical_nt << 11)
                        | (coarse_y << 5)
                        | 0x041F
                    )
                    stream.write(row(2, address, 0x1357, True, True, 256, 239))
                    counts[1] += 1

        # Exhaust every address helper input and keep automatic updates idle.
        for address in range(0x8000):
            stream.write(row(3, address, address ^ 0x5A5A, True, False, 0, 240))
            counts[2] += 1

        # Random transfers plus neighboring/timing/gating coordinates.
        coordinates = (
            (0, 7), (0, 8), (0, 9), (239, 255), (239, 256),
            (239, 257), (239, 258), (240, 256), (260, 257),
            (261, 279), (261, 280), (261, 304), (261, 305),
            (261, 327), (261, 328), (261, 329), (261, 335),
            (261, 336), (261, 337),
        )
        for _ in range(RANDOM_CASES):
            address = rng.next() & 0x7FFF
            temporary = rng.next() & 0x7FFF
            scanline, dot = coordinates[rng.next() % len(coordinates)]
            ppu_enable = bool(rng.next() & 1)
            rendering_enabled = bool(rng.next() & 1)
            stream.write(
                row(
                    4,
                    address,
                    temporary,
                    ppu_enable,
                    rendering_enabled,
                    dot,
                    scanline,
                )
            )
            counts[3] += 1

    print(
        "PPU scroll Python reference vectors: "
        f"rows={sum(counts)}, coarse_x={counts[0]}, vertical={counts[1]}, "
        f"address_helpers={counts[2]}, random={counts[3]}, "
        f"seed=0x{RANDOM_SEED:08X}"
    )


if __name__ == "__main__":
    main()
