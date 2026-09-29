#!/usr/bin/env python3
"""Generate deterministic Phase 4F-B storage/Mapper-0 operation vectors."""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# The generator is an executable repository script, so make the repository
# model package importable without requiring installation.
from verification.runtime_cartridge import (  # noqa: E402
    RuntimeCartridgeModel,
    RuntimeTarget,
)


SEED = 0x04FB2026
RANDOM_OPERATIONS = 12_000

OP_PRG_WRITE = 0
OP_CHR_WRITE = 1
OP_CPU_READ = 2
OP_CHR_READ = 3
OP_PPU_WRITE = 4


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT")

    output_path = Path(sys.argv[1])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    random_source = random.Random(SEED)
    model = RuntimeCartridgeModel()
    rows: list[tuple[int, int, int, int, int, int]] = []
    loader_writes = 0
    ppu_writes = 0
    reads = 0
    nrom128_reads = 0
    nrom256_reads = 0

    def add_prg_write(address: int, data: int) -> None:
        nonlocal loader_writes
        assert model.loader_write(RuntimeTarget.PRG, address, data)
        rows.append((OP_PRG_WRITE, 0, 0, address, data, data))
        loader_writes += 1

    def add_chr_write(address: int, data: int) -> None:
        nonlocal loader_writes
        assert model.loader_write(RuntimeTarget.CHR, address, data)
        rows.append((OP_CHR_WRITE, 0, 0, address, data, data))
        loader_writes += 1

    def add_cpu_read(address: int, nrom_256: bool) -> None:
        nonlocal reads, nrom128_reads, nrom256_reads
        expected = model.cpu_read(address, nrom_256=nrom_256)
        rows.append((OP_CPU_READ, int(nrom_256), 0, address, 0, expected))
        reads += 1
        if nrom_256:
            nrom256_reads += 1
        else:
            nrom128_reads += 1

    def add_chr_read(address: int) -> None:
        nonlocal reads
        rows.append((OP_CHR_READ, 0, 0, address, 0, model.ppu_read(address)))
        reads += 1

    # Required boundaries precede the random stream and make coverage stable.
    for address, data in (
        (0x0000, 0xA9),
        (0x0001, 0x42),
        (0x3FFF, 0x31),
        (0x4000, 0x72),
        (0x7FFF, 0xE7),
    ):
        add_prg_write(address, data)
    for address in (0x8000, 0x8001, 0xBFFF, 0xC000, 0xFFFF):
        add_cpu_read(address, False)
        add_cpu_read(address, True)
    for address, data in ((0x0000, 0x10), (0x0420, 0x7E), (0x1FFF, 0xEF)):
        add_chr_write(address, data)
        add_chr_read(address)

    for _ in range(RANDOM_OPERATIONS):
        operation = random_source.randrange(10)
        if operation < 3:
            add_prg_write(
                random_source.randrange(0x8000),
                random_source.randrange(0x100),
            )
        elif operation < 5:
            add_chr_write(
                random_source.randrange(0x2000),
                random_source.randrange(0x100),
            )
        elif operation < 8:
            add_cpu_read(
                random_source.randrange(0x8000, 0x10000),
                bool(random_source.getrandbits(1)),
            )
        elif operation == 8:
            add_chr_read(random_source.randrange(0x2000))
        else:
            address = random_source.randrange(0x2000)
            data = random_source.randrange(0x100)
            chr_is_ram = bool(random_source.getrandbits(1))
            model.ppu_write(address, data, chr_is_ram=chr_is_ram)
            rows.append(
                (OP_PPU_WRITE, 0, int(chr_is_ram), address, data, data)
            )
            ppu_writes += 1

    with output_path.open("w", encoding="ascii") as stream:
        for row in rows:
            stream.write("%d %d %d %04x %02x %02x\n" % row)

    print(
        "Phase 4F-B runtime-cartridge vectors: "
        f"vectors={len(rows)} seed={SEED:08x} "
        f"loader_writes={loader_writes} ppu_writes={ppu_writes} "
        f"reads={reads} nrom128_reads={nrom128_reads} "
        f"nrom256_reads={nrom256_reads}"
    )


if __name__ == "__main__":
    main()
