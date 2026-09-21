from __future__ import annotations

import json
from pathlib import Path

import pytest

from verification.ines import (
    CHR_BANK_SIZE,
    INESError,
    PRG_BANK_SIZE,
    TRAINER_SIZE,
    UnsupportedINESImage,
    convert_ines,
    parse_ines,
)


def make_image(
    *,
    prg_banks: int = 1,
    chr_banks: int = 1,
    flags6: int = 0,
    flags7: int = 0,
    trainer: bool = False,
) -> bytes:
    if trainer:
        flags6 |= 0x04
    header = bytearray(b"NES\x1a")
    header.extend((prg_banks, chr_banks, flags6, flags7, 1, 0))
    header.extend(b"\x00" * 6)
    trainer_data = bytes((index ^ 0x5A) & 0xFF for index in range(TRAINER_SIZE))
    prg = bytes((index * 13 + 7) & 0xFF for index in range(prg_banks * PRG_BANK_SIZE))
    chr_data = bytes((index * 5 + 3) & 0xFF for index in range(chr_banks * CHR_BANK_SIZE))
    return bytes(header) + (trainer_data if trainer else b"") + prg + chr_data


def test_parse_nrom128_horizontal_and_nrom256_vertical() -> None:
    nrom128 = parse_ines(make_image())
    assert nrom128.mapper == 0
    assert nrom128.nrom_mode == "NROM-128"
    assert nrom128.prg_size == PRG_BANK_SIZE
    assert nrom128.chr_size == CHR_BANK_SIZE
    assert nrom128.mirroring == "horizontal"
    assert not nrom128.chr_is_ram

    nrom256 = parse_ines(make_image(prg_banks=2, flags6=0x01))
    assert nrom256.nrom_mode == "NROM-256"
    assert nrom256.prg_size == 2 * PRG_BANK_SIZE
    assert nrom256.mirroring == "vertical"


def test_trainer_is_skipped_before_prg() -> None:
    image_data = make_image(trainer=True)
    image = parse_ines(image_data)
    assert image.trainer_present
    assert len(image.trainer) == TRAINER_SIZE
    assert image.prg_rom[0] == 7


def test_zero_chr_banks_selects_8k_chr_ram() -> None:
    image = parse_ines(make_image(chr_banks=0))
    assert image.chr_is_ram
    assert image.chr_rom == b""


@pytest.mark.parametrize(
    ("mutation", "exception"),
    [
        (lambda image: b"BAD!" + image[4:], INESError),
        (lambda image: image[:7] + bytes((0x08,)) + image[8:], UnsupportedINESImage),
        (lambda image: image[:6] + bytes((0x10,)) + image[7:], UnsupportedINESImage),
        (lambda image: image[:-1], INESError),
        (lambda image: image + b"\x00", INESError),
    ],
)
def test_rejects_malformed_or_unsupported_images(mutation, exception) -> None:
    with pytest.raises(exception):
        parse_ines(mutation(make_image()))


def test_rejects_invalid_mapper0_bank_counts_and_four_screen() -> None:
    with pytest.raises(UnsupportedINESImage):
        parse_ines(make_image(prg_banks=3))
    with pytest.raises(UnsupportedINESImage):
        parse_ines(make_image(chr_banks=2))
    with pytest.raises(UnsupportedINESImage):
        parse_ines(make_image(flags6=0x08))


def test_rejects_nes2_console_variants_and_nonzero_reserved_bytes() -> None:
    with pytest.raises(UnsupportedINESImage, match="NES 2.0"):
        parse_ines(make_image(flags7=0x08))
    with pytest.raises(UnsupportedINESImage, match="VS/PlayChoice"):
        parse_ines(make_image(flags7=0x01))
    image = bytearray(make_image())
    image[12] = 1
    with pytest.raises(INESError, match="reserved"):
        parse_ines(bytes(image))


def test_conversion_is_reproducible_and_records_metadata(tmp_path: Path) -> None:
    source = tmp_path / "owned.nes"
    source.write_bytes(make_image(flags6=0x01))
    first = convert_ines(source, tmp_path / "one" / "cart")
    second = convert_ines(source, tmp_path / "two" / "cart")
    assert first["prg"].read_bytes() == second["prg"].read_bytes()
    assert first["chr"].read_bytes() == second["chr"].read_bytes()
    first_metadata = json.loads(first["metadata"].read_text())
    second_metadata = json.loads(second["metadata"].read_text())
    assert first_metadata == second_metadata
    assert first_metadata["mapper"] == 0
    assert first_metadata["prg_rom_bytes"] == PRG_BANK_SIZE
    assert first_metadata["chr_rom_bytes"] == CHR_BANK_SIZE
    assert first_metadata["mirroring"] == "vertical"
    assert not first_metadata["chr_is_ram"]


def test_chr_ram_conversion_omits_chr_rom_artifact(tmp_path: Path) -> None:
    source = tmp_path / "chrram.nes"
    source.write_bytes(make_image(chr_banks=0))
    outputs = convert_ines(source, tmp_path / "cart")
    metadata = json.loads(outputs["metadata"].read_text())
    assert "chr" not in outputs
    assert metadata["chr_is_ram"]
    assert metadata["chr_ram_bytes"] == CHR_BANK_SIZE
