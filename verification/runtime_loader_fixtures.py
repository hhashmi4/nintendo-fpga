"""Deterministic, project-owned iNES fixtures for Phase 4F-E tests."""

from __future__ import annotations

from pathlib import Path


INES_HEADER_SIZE = 16
TRAINER_SIZE = 512
PRG_BANK_SIZE = 16 * 1024
CHR_BANK_SIZE = 8 * 1024


def make_ines(
    *,
    prg_banks: int = 1,
    chr_banks: int = 1,
    flags6: int = 0,
    flags7: int = 0,
    prg_ram_units: int = 0,
    trainer: bool = False,
    trailing: bytes = b"",
) -> bytes:
    """Build an original synthetic image with deterministic byte patterns."""

    if trainer:
        flags6 |= 0x04
    header = bytearray(b"NES\x1a")
    header.extend((prg_banks, chr_banks, flags6, flags7, prg_ram_units, 0))
    header.extend(b"\x00" * 6)
    trainer_data = bytes(
        (index * 3 + 0x5A) & 0xFF for index in range(TRAINER_SIZE)
    )
    prg = bytes(
        (index * 13 + prg_banks * 7 + 1) & 0xFF
        for index in range(prg_banks * PRG_BANK_SIZE)
    )
    chr_data = bytes(
        (index * 5 + chr_banks * 11 + 3) & 0xFF
        for index in range(chr_banks * CHR_BANK_SIZE)
    )
    trainer_payload = trainer_data if trainer else b""
    return bytes(header) + trainer_payload + prg + chr_data + trailing


def valid_runtime_images() -> dict[str, bytes]:
    return {
        "nrom128_chrrom_horizontal.nes": make_ines(),
        "nrom128_chrrom_vertical.nes": make_ines(flags6=0x01),
        "nrom256_chrrom_horizontal.nes": make_ines(prg_banks=2),
        "nrom128_chrram_vertical.nes": make_ines(chr_banks=0, flags6=0x01),
    }


def write_valid_runtime_images(output_dir: str | Path) -> list[Path]:
    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, payload in valid_runtime_images().items():
        path = destination / name
        path.write_bytes(payload)
        paths.append(path)
    return paths


def game_library_files() -> dict[str, bytes]:
    """Return a mixed, original library fixture with no third-party ROM data."""

    supported = make_ines()
    chrram = make_ines(prg_banks=2, chr_banks=0, flags6=0x01)
    return {
        "Alpha Test.nes": supported,
        "Beta CHR-RAM.NES": chrram,
        "Duplicate.nes": supported,
        "Duplicate.NES": chrram,
        "Unicode 星.nEs": supported,
        "Unsupported Mapper 2.nes": make_ines(flags6=0x20),
        "Corrupt Header.nes": b"NOT-AN-INES-FILE",
        "Truncated Payload.nes": supported[:-7],
        "notes.txt": b"generated library fixture; not a ROM\n",
    }


def write_game_library(output_dir: str | Path) -> dict[str, Path]:
    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for name, payload in game_library_files().items():
        path = destination / name
        path.write_bytes(payload)
        paths[name] = path
    return paths
