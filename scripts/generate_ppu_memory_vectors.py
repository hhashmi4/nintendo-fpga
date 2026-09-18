#!/usr/bin/env python3
"""Generate deterministic standalone Phase 3C PPU-memory vectors."""

from argparse import ArgumentParser
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_memory import (  # noqa: E402
    MemoryRegion,
    MirroringMode,
    PpuMemoryModel,
    translate,
)


RANDOM_SEED = 0x3C5EED01
RANDOM_ACCESSES = 100_000


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


def buffer_read(model: PpuMemoryModel, primary_address: int, address: int) -> int:
    if model.translation(primary_address).region != MemoryRegion.PALETTE:
        return 0
    decoded = model.translation(address)
    if decoded.region == MemoryRegion.NAMETABLE:
        return model.ciram[decoded.ciram_address]
    return 0


def emit(
    stream: TextIO,
    model: PpuMemoryModel,
    *,
    scenario: int,
    reset: bool = False,
    mode: MirroringMode = MirroringMode.VERTICAL,
    valid: bool = False,
    write: bool = False,
    address: int = 0,
    data: int = 0,
    buffer_address: int = 0x2000,
) -> tuple[bool, MemoryRegion]:
    model.set_mode(mode)
    decoded = translate(address, mode)
    pre_read = model.read(address)
    pre_buffer = buffer_read(model, address, buffer_address)
    accepted = not reset and valid
    chr_read = accepted and not write and decoded.region == MemoryRegion.CHR
    chr_write = accepted and write and decoded.region == MemoryRegion.CHR
    ciram_write = accepted and write and decoded.region == MemoryRegion.NAMETABLE
    palette_write = accepted and write and decoded.region == MemoryRegion.PALETTE

    if accepted and write:
        model.write(address, data)
    post_read = model.read(address)
    post_buffer = buffer_read(model, address, buffer_address)

    values = (
        scenario,
        int(reset),
        int(mode),
        int(valid),
        int(write),
        address & 0x3FFF,
        data & 0xFF,
        buffer_address & 0x3FFF,
        pre_read,
        pre_buffer,
        int(decoded.region),
        decoded.normalized_nametable_address,
        decoded.logical_nametable,
        decoded.nametable_offset,
        decoded.physical_ciram_page,
        decoded.ciram_address,
        decoded.palette_index,
        decoded.chr_address,
        int(chr_read),
        int(chr_write),
        data & 0xFF,
        int(ciram_write),
        int(palette_write),
        post_read,
        post_buffer,
    )
    stream.write(" ".join(str(value) for value in values) + "\n")
    return accepted, decoded.region


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    model = PpuMemoryModel()
    random_counts = {
        "reads": 0,
        "writes": 0,
        "chr": 0,
        "nametable": 0,
        "palette": 0,
    }
    mode_counts = [0, 0, 0, 0]
    directed_rows = 0
    rng = XorShift32(RANDOM_SEED)

    with args.output.open("w", encoding="ascii", newline="\n") as stream:
        emit(stream, model, scenario=1, reset=True)
        emit(stream, model, scenario=1, reset=True)
        for mode in MirroringMode:
            for address in range(0x4000):
                emit(
                    stream,
                    model,
                    scenario=1,
                    mode=mode,
                    address=address,
                    buffer_address=(address ^ 0x1555) & 0x3FFF,
                )

        directed: list[tuple[MirroringMode, bool, int, int, int]] = []
        for mode in MirroringMode:
            for page, value in enumerate((0x11, 0x22, 0x33, 0x44)):
                directed.append((mode, True, 0x2000 + page * 0x400, value, 0x2F00))
            for page in range(4):
                directed.append((mode, False, 0x2000 + page * 0x400, 0, 0x2F00))
        for address in (0x3000, 0x33FF, 0x3800, 0x3EFF):
            directed.append((MirroringMode.VERTICAL, True, address, address, 0x2F00))
            directed.append((MirroringMode.VERTICAL, False, address - 0x1000, 0, 0x2F00))
        for address in (0x3F00, 0x3F10, 0x3F04, 0x3F14,
                        0x3F18, 0x3F1C, 0x3F20, 0x3F30, 0x3FFF):
            directed.append((MirroringMode.HORIZONTAL, True, address, address, 0x2F00))
            directed.append((MirroringMode.HORIZONTAL, False, address, 0, 0x2F00))
        for address in (0x0000, 0x0123, 0x1000, 0x1FFF):
            directed.append((MirroringMode.VERTICAL, True, address, address ^ 0xA5, 0x2000))
            directed.append((MirroringMode.VERTICAL, False, address, 0, 0x2000))

        for mode, write, address, data, buffer_address in directed:
            emit(
                stream,
                model,
                scenario=2,
                mode=mode,
                valid=True,
                write=write,
                address=address,
                data=data,
                buffer_address=buffer_address,
            )
            directed_rows += 1

        for _ in range(RANDOM_ACCESSES):
            mode = MirroringMode(rng.next() & 3)
            address = rng.next() & 0x3FFF
            write = bool(rng.next() & 1)
            data = rng.next() & 0xFF
            buffer_address = rng.next() & 0x3FFF
            accepted, region = emit(
                stream,
                model,
                scenario=3,
                mode=mode,
                valid=True,
                write=write,
                address=address,
                data=data,
                buffer_address=buffer_address,
            )
            assert accepted
            random_counts["writes" if write else "reads"] += 1
            random_counts[MemoryRegion(region).name.lower()] += 1
            mode_counts[int(mode)] += 1

    print(
        "PPU memory Python reference vectors: "
        f"rows={2 + 4 * 0x4000 + directed_rows + RANDOM_ACCESSES}, "
        f"all_addresses={4 * 0x4000}, palette_addresses=256, "
        f"directed={directed_rows}, seed=0x{RANDOM_SEED:08X}, "
        f"random={RANDOM_ACCESSES}, reads={random_counts['reads']}, "
        f"writes={random_counts['writes']}, chr={random_counts['chr']}, "
        f"nametable={random_counts['nametable']}, "
        f"palette={random_counts['palette']}, modes={mode_counts}"
    )


if __name__ == "__main__":
    main()
