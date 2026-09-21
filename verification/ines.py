"""Strict iNES 1.0 import and deterministic FPGA artifact generation."""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path


INES_HEADER_SIZE = 16
TRAINER_SIZE = 512
PRG_BANK_SIZE = 16 * 1024
CHR_BANK_SIZE = 8 * 1024


class INESError(ValueError):
    """Base class for deterministic iNES import failures."""


class UnsupportedINESImage(INESError):
    """The image is well formed but outside the Phase 4B feature set."""


@dataclass(frozen=True)
class INESImage:
    mapper: int
    prg_rom: bytes
    chr_rom: bytes
    mirroring: str
    trainer_present: bool
    trainer: bytes
    chr_is_ram: bool
    prg_ram_bytes: int
    source_sha256: str

    @property
    def prg_size(self) -> int:
        return len(self.prg_rom)

    @property
    def chr_size(self) -> int:
        return len(self.chr_rom)

    @property
    def nrom_mode(self) -> str:
        return "NROM-128" if self.prg_size == PRG_BANK_SIZE else "NROM-256"


def parse_ines(data: bytes) -> INESImage:
    """Parse the strict Mapper 0 subset accepted by Phase 4B."""

    if len(data) < INES_HEADER_SIZE:
        raise INESError("image is shorter than the 16-byte iNES header")
    if data[:4] != b"NES\x1a":
        raise INESError("invalid iNES magic; expected 4e 45 53 1a")

    header = data[:INES_HEADER_SIZE]
    prg_banks = header[4]
    chr_banks = header[5]
    flags6 = header[6]
    flags7 = header[7]

    if flags7 & 0x0C == 0x08:
        raise UnsupportedINESImage("NES 2.0 images are not supported")
    if flags6 & 0x08:
        raise UnsupportedINESImage("four-screen nametable layout is unsupported")
    if flags7 & 0x03:
        raise UnsupportedINESImage("VS/PlayChoice images are unsupported")
    if any(header[12:16]):
        raise INESError("reserved iNES 1.0 header bytes 12-15 must be zero")

    mapper = (flags7 & 0xF0) | (flags6 >> 4)
    if mapper != 0:
        raise UnsupportedINESImage(
            f"mapper {mapper} is unsupported; Phase 4B accepts only Mapper 0"
        )
    if prg_banks not in (1, 2):
        raise UnsupportedINESImage(
            "Mapper 0 requires one or two 16 KiB PRG ROM banks"
        )
    if chr_banks not in (0, 1):
        raise UnsupportedINESImage(
            "Mapper 0 requires zero or one 8 KiB CHR ROM bank"
        )

    trainer_present = bool(flags6 & 0x04)
    trainer_bytes = TRAINER_SIZE if trainer_present else 0
    prg_bytes = prg_banks * PRG_BANK_SIZE
    chr_bytes = chr_banks * CHR_BANK_SIZE
    expected_size = INES_HEADER_SIZE + trainer_bytes + prg_bytes + chr_bytes
    if len(data) != expected_size:
        raise INESError(
            f"image length is {len(data)} bytes; header requires {expected_size}"
        )

    offset = INES_HEADER_SIZE
    trainer = data[offset : offset + trainer_bytes]
    offset += trainer_bytes
    prg_rom = data[offset : offset + prg_bytes]
    offset += prg_bytes
    chr_rom = data[offset : offset + chr_bytes]

    prg_ram_units = header[8]
    # iNES 1.0 specifies one 8 KiB unit when byte 8 is zero for compatibility.
    prg_ram_bytes = (prg_ram_units or 1) * 8 * 1024

    return INESImage(
        mapper=mapper,
        prg_rom=prg_rom,
        chr_rom=chr_rom,
        mirroring="vertical" if flags6 & 0x01 else "horizontal",
        trainer_present=trainer_present,
        trainer=trainer,
        chr_is_ram=chr_banks == 0,
        prg_ram_bytes=prg_ram_bytes,
        source_sha256=sha256(data).hexdigest(),
    )


def load_ines(path: str | Path) -> INESImage:
    return parse_ines(Path(path).read_bytes())


def write_readmemh(data: bytes, path: str | Path) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("".join(f"{value:02x}\n" for value in data), encoding="ascii")


def nrom_vector(prg_rom: bytes, vector_address: int) -> int:
    """Return a little-endian CPU vector from an NROM PRG image."""

    if vector_address not in (0xFFFA, 0xFFFC, 0xFFFE):
        raise ValueError(f"unsupported vector address: {vector_address:#06x}")
    offset = (vector_address - 0x8000) % len(prg_rom)
    return prg_rom[offset] | (prg_rom[offset + 1] << 8)


def convert_ines(path: str | Path, output_prefix: str | Path) -> dict[str, Path]:
    """Validate an iNES image and emit ROM initialization plus metadata."""

    source_path = Path(path)
    prefix = Path(output_prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    image = load_ines(source_path)

    prg_path = prefix.with_suffix(".prg.hex")
    chr_path = prefix.with_suffix(".chr.hex")
    metadata_path = prefix.with_suffix(".json")
    write_readmemh(image.prg_rom, prg_path)
    if image.chr_is_ram:
        if chr_path.exists():
            chr_path.unlink()
    else:
        write_readmemh(image.chr_rom, chr_path)

    metadata = {
        "format": "iNES-1.0",
        "source": source_path.name,
        "source_sha256": image.source_sha256,
        "mapper": image.mapper,
        "nrom_mode": image.nrom_mode,
        "prg_rom_bytes": image.prg_size,
        "prg_rom_sha256": sha256(image.prg_rom).hexdigest(),
        "chr_rom_bytes": image.chr_size,
        "chr_rom_sha256": (
            None if image.chr_is_ram else sha256(image.chr_rom).hexdigest()
        ),
        "chr_is_ram": image.chr_is_ram,
        "chr_ram_bytes": CHR_BANK_SIZE if image.chr_is_ram else 0,
        "prg_ram_bytes": image.prg_ram_bytes,
        "mirroring": image.mirroring,
        "mirroring_mode": 0 if image.mirroring == "vertical" else 1,
        "trainer_present": image.trainer_present,
        "nmi_vector": nrom_vector(image.prg_rom, 0xFFFA),
        "reset_vector": nrom_vector(image.prg_rom, 0xFFFC),
        "irq_brk_vector": nrom_vector(image.prg_rom, 0xFFFE),
    }
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    outputs = {"prg": prg_path, "metadata": metadata_path}
    if not image.chr_is_ram:
        outputs["chr"] = chr_path
    return outputs
