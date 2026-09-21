#!/usr/bin/env python3
"""Validate and import the selected Phase 4D-B cartridge deterministically."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ines import (  # noqa: E402
    CHR_BANK_SIZE,
    PRG_BANK_SIZE,
    INESError,
    convert_ines,
    load_ines,
    nrom_vector,
)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.nes OUTPUT_PREFIX")

    source = Path(sys.argv[1])
    prefix = Path(sys.argv[2])
    try:
        image = load_ines(source)
    except INESError as error:
        raise SystemExit(f"ERROR: incompatible playable ROM: {error}") from error

    expected = {
        "mapper": 0,
        "PRG ROM bytes": PRG_BANK_SIZE,
        "CHR ROM bytes": CHR_BANK_SIZE,
        "mirroring": "horizontal",
    }
    actual = {
        "mapper": image.mapper,
        "PRG ROM bytes": image.prg_size,
        "CHR ROM bytes": image.chr_size,
        "mirroring": image.mirroring,
    }
    for field, expected_value in expected.items():
        if actual[field] != expected_value:
            raise SystemExit(
                f"ERROR: incompatible playable ROM: {field} is "
                f"{actual[field]!r}, expected {expected_value!r}"
            )
    if image.chr_is_ram:
        raise SystemExit("ERROR: incompatible playable ROM: CHR ROM is required")

    vectors = {
        "NMI": nrom_vector(image.prg_rom, 0xFFFA),
        "reset": nrom_vector(image.prg_rom, 0xFFFC),
        "IRQ/BRK": nrom_vector(image.prg_rom, 0xFFFE),
    }
    for name, address in vectors.items():
        if not 0x8000 <= address <= 0xFFFF:
            raise SystemExit(
                f"ERROR: incompatible playable ROM: {name} vector "
                f"${address:04X} does not point into PRG ROM"
            )

    outputs = convert_ines(source, prefix)
    print(
        "validated playable cartridge: "
        f"mapper=0 prg={image.prg_size} chr={image.chr_size} "
        f"chr_ram=0 mirroring={image.mirroring} "
        f"vectors=NMI:${vectors['NMI']:04X}/RESET:${vectors['reset']:04X}/"
        f"IRQ:${vectors['IRQ/BRK']:04X}"
    )
    for kind, path in outputs.items():
        print(f"{kind}: {path}")


if __name__ == "__main__":
    main()
