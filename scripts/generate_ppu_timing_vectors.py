#!/usr/bin/env python3
"""Generate deterministic Python-reference vectors for the PPU RTL testbench."""

from argparse import ArgumentParser
from pathlib import Path
import sys
from typing import Callable, TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_timing import PpuTimingModel  # noqa: E402


STALL_SEED = 0x003A5EED


class XorShift32:
    def __init__(self, seed: int) -> None:
        if seed == 0:
            raise ValueError("xorshift seed must be nonzero")
        self.state = seed & 0xFFFF_FFFF

    def next(self) -> int:
        value = self.state
        value ^= (value << 13) & 0xFFFF_FFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFF_FFFF
        self.state = value & 0xFFFF_FFFF
        return self.state


def write_row(
    stream: TextIO,
    scenario: int,
    reset: bool,
    enabled: bool,
    rendering: bool,
    model: PpuTimingModel,
) -> None:
    sample = model.snapshot()
    stream.write(
        f"{scenario} {int(reset)} {int(enabled)} {int(rendering)} "
        f"{sample.dot} {sample.scanline} {int(sample.frame_odd)} "
        f"{int(sample.vblank)}\n"
    )


def write_scenario(
    stream: TextIO,
    *,
    scenario: int,
    frames: int,
    rendering: bool,
    enable_source: Callable[[], bool],
) -> tuple[int, int]:
    model = PpuTimingModel()
    rows = 0
    disabled = 0
    for _ in range(2):
        write_row(stream, scenario, True, False, rendering, model)
        model.clock(reset=True, ppu_enable=False, rendering_enabled=rendering)
        rows += 1

    completed = 0
    while completed < frames:
        enabled = enable_source()
        write_row(stream, scenario, False, enabled, rendering, model)
        ending = model.frame_end(rendering, enabled)
        model.clock(ppu_enable=enabled, rendering_enabled=rendering)
        completed += int(ending)
        rows += 1
        disabled += int(not enabled)

    # Preserve one post-wrap observation in the same scenario. Reset is high
    # only to exclude this bookkeeping row from frame/event statistics; the
    # state is already 0:0 as a consequence of the final terminal tick.
    write_row(stream, scenario, True, False, rendering, model)
    model.clock(reset=True, ppu_enable=False, rendering_enabled=rendering)
    rows += 1
    return rows, disabled


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    rng = XorShift32(STALL_SEED)
    totals: list[tuple[int, int]] = []
    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        totals.append(
            write_scenario(
                stream,
                scenario=1,
                frames=2,
                rendering=False,
                enable_source=lambda: True,
            )
        )
        totals.append(
            write_scenario(
                stream,
                scenario=2,
                frames=4,
                rendering=True,
                enable_source=lambda: True,
            )
        )
        totals.append(
            write_scenario(
                stream,
                scenario=3,
                frames=6,
                rendering=True,
                enable_source=lambda: rng.next() % 100 < 67,
            )
        )

    print(
        "PPU Python reference vectors: "
        f"rows={sum(rows for rows, _ in totals)}, "
        f"random_stalls={totals[2][1]}, seed=0x{STALL_SEED:08X}"
    )


if __name__ == "__main__":
    main()
