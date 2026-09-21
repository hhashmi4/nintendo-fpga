from hashlib import sha256
from pathlib import Path

from scripts.generate_phase4b_fixtures import (
    make_ines,
    playable_demo_chr,
    playable_demo_prg,
)
from verification.ines import parse_ines, nrom_vector


ROOT = Path(__file__).resolve().parents[2]
ROM = ROOT / "roms" / "phase4db_playable_nrom128.nes"
EXPECTED_SHA256 = "307007ec66a59b6893b9c6530db563b9c1950d5372492eeaf98a7e299b0667a9"


def test_committed_playable_rom_is_reproducible() -> None:
    generated = make_ines(
        playable_demo_prg(), playable_demo_chr(), vertical=False
    )
    assert ROM.read_bytes() == generated
    assert sha256(generated).hexdigest() == EXPECTED_SHA256


def test_playable_rom_metadata_and_vectors() -> None:
    image = parse_ines(ROM.read_bytes())
    assert image.mapper == 0
    assert image.nrom_mode == "NROM-128"
    assert image.prg_size == 16 * 1024
    assert image.chr_size == 8 * 1024
    assert not image.chr_is_ram
    assert image.mirroring == "horizontal"
    assert nrom_vector(image.prg_rom, 0xFFFA) == 0x9000
    assert nrom_vector(image.prg_rom, 0xFFFC) == 0x8000
    assert nrom_vector(image.prg_rom, 0xFFFE) == 0x9100
