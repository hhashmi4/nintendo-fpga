"""Strict classic-iNES parsing and Phase 4F-E runtime-image validation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import os
from pathlib import Path
import stat

from .protocol import (
    CHR_ROM_BYTES,
    SUPPORTED_MAPPERS,
    PRG_NROM128_BYTES,
    PRG_NROM256_BYTES,
    Manifest,
    Mirroring,
)


INES_MAGIC = b"NES\x1a"
INES_HEADER_SIZE = 16
TRAINER_SIZE = 512
PRG_BANK_SIZE = 16 * 1024
CHR_BANK_SIZE = 8 * 1024


class INESError(ValueError):
    """Base class for errors that make an image unusable by the loader."""


class INESFormatError(INESError):
    """The input is not a well-formed classic iNES container."""


class UnsupportedINESImage(INESError):
    """The container is understood but unsupported by the runtime hardware."""


class CHRType(Enum):
    ROM = "ROM"
    RAM = "RAM"


@dataclass(frozen=True)
class INESHeader:
    prg_banks: int
    chr_banks: int
    flags6: int
    flags7: int
    prg_ram_units: int
    raw: bytes

    @property
    def nes2(self) -> bool:
        return self.flags7 & 0x0C == 0x08

    @property
    def mapper(self) -> int:
        return (self.flags7 & 0xF0) | (self.flags6 >> 4)

    @property
    def vertical_mirroring(self) -> bool:
        return bool(self.flags6 & 0x01)

    @property
    def battery(self) -> bool:
        return bool(self.flags6 & 0x02)

    @property
    def trainer(self) -> bool:
        return bool(self.flags6 & 0x04)

    @property
    def four_screen(self) -> bool:
        return bool(self.flags6 & 0x08)

    @property
    def console_variant(self) -> bool:
        return bool(self.flags7 & 0x03)

    @property
    def prg_bytes(self) -> int:
        return self.prg_banks * PRG_BANK_SIZE

    @property
    def chr_bytes(self) -> int:
        return self.chr_banks * CHR_BANK_SIZE

    @property
    def prg_ram_bytes(self) -> int:
        # Classic iNES defines zero as one compatibility 8 KiB unit.
        return (self.prg_ram_units or 1) * 8 * 1024


@dataclass(frozen=True)
class ParsedINES:
    """A structurally valid classic-iNES container, before support checks."""

    header: INESHeader
    trainer_bytes: bytes
    prg_bytes: bytes
    chr_bytes: bytes


@dataclass(frozen=True)
class RuntimeImage:
    """A fully validated image; downstream code never reinterprets flags."""

    mapper: int
    mirroring: Mirroring
    chr_type: CHRType
    prg_bytes: bytes
    chr_bytes: bytes

    @property
    def prg_size(self) -> int:
        return len(self.prg_bytes)

    @property
    def chr_size(self) -> int:
        return len(self.chr_bytes)

    @property
    def chr_is_ram(self) -> bool:
        return self.chr_type is CHRType.RAM

    @property
    def nrom_mode(self) -> str:
        return "NROM-128" if self.prg_size == PRG_NROM128_BYTES else "NROM-256"

    def manifest(self) -> Manifest:
        return Manifest(
            mapper=self.mapper,
            prg_bytes=self.prg_size,
            chr_bytes=self.chr_size,
            chr_is_ram=self.chr_is_ram,
            mirroring=self.mirroring,
        )


@dataclass(frozen=True)
class ImageInspection:
    header: INESHeader
    parsed: ParsedINES | None
    runtime_image: RuntimeImage | None
    supported: bool
    reason: str | None

    @property
    def format_name(self) -> str:
        return "NES 2.0" if self.header.nes2 else "iNES 1.0"


def parse_ines_header(data: bytes) -> INESHeader:
    if len(data) < INES_HEADER_SIZE:
        raise INESFormatError(
            f"file is {len(data)} bytes; a 16-byte iNES header is required"
        )
    if data[:4] != INES_MAGIC:
        raise INESFormatError("invalid iNES magic; expected 4e 45 53 1a")
    raw = data[:INES_HEADER_SIZE]
    return INESHeader(
        prg_banks=raw[4],
        chr_banks=raw[5],
        flags6=raw[6],
        flags7=raw[7],
        prg_ram_units=raw[8],
        raw=raw,
    )


def ines_container_size(header: INESHeader) -> int:
    """Return the exact container size declared by a classic iNES header."""

    trainer_size = TRAINER_SIZE if header.trainer else 0
    return INES_HEADER_SIZE + trainer_size + header.prg_bytes + header.chr_bytes


def _validate_classic_header(header: INESHeader) -> None:
    if header.nes2:
        raise UnsupportedINESImage("NES 2.0 images are not supported")
    if header.flags7 & 0x0C:
        raise INESFormatError("reserved classic iNES flags 7 format bits are set")
    if any(header.raw[12:16]):
        raise INESFormatError("reserved iNES 1.0 header bytes 12-15 must be zero")


def _validate_runtime_header(header: INESHeader) -> tuple[CHRType, Mirroring]:
    """Validate support using header metadata without touching ROM payloads."""

    if header.console_variant:
        raise UnsupportedINESImage("VS System and PlayChoice-10 images are unsupported")
    if header.mapper not in SUPPORTED_MAPPERS:
        raise UnsupportedINESImage(
            f"Mapper {header.mapper} is not supported; runtime hardware supports "
            "Mapper 0"
        )
    if header.prg_banks not in (1, 2):
        raise UnsupportedINESImage(
            f"{header.prg_banks} PRG banks are unsupported; Mapper 0 requires "
            "one or two 16 KiB banks"
        )
    if header.chr_banks not in (0, 1):
        raise UnsupportedINESImage(
            f"{header.chr_banks} CHR banks are unsupported; Mapper 0 requires "
            "zero or one 8 KiB bank"
        )
    if header.four_screen:
        raise UnsupportedINESImage("four-screen mirroring is not supported")
    if header.trainer:
        raise UnsupportedINESImage("512-byte iNES trainers are not supported")
    if header.battery:
        raise UnsupportedINESImage("battery-backed PRG RAM is not supported")

    chr_type = CHRType.RAM if header.chr_banks == 0 else CHRType.ROM
    mirroring = (
        Mirroring.VERTICAL if header.vertical_mirroring else Mirroring.HORIZONTAL
    )
    return chr_type, mirroring


def parse_ines(data: bytes) -> ParsedINES:
    """Parse exact classic-iNES boundaries without deciding FPGA support."""

    header = parse_ines_header(data)
    _validate_classic_header(header)

    trainer_size = TRAINER_SIZE if header.trainer else 0
    expected_size = ines_container_size(header)
    if len(data) < expected_size:
        raise INESFormatError(
            f"file is truncated at {len(data)} bytes; header requires "
            f"{expected_size} bytes"
        )
    if len(data) > expected_size:
        raise INESFormatError(
            f"file has {len(data) - expected_size} unexpected trailing bytes; "
            f"header requires exactly {expected_size} bytes"
        )

    offset = INES_HEADER_SIZE
    trainer_bytes = data[offset : offset + trainer_size]
    offset += trainer_size
    prg_bytes = data[offset : offset + header.prg_bytes]
    offset += header.prg_bytes
    chr_bytes = data[offset : offset + header.chr_bytes]
    return ParsedINES(header, trainer_bytes, prg_bytes, chr_bytes)


def validate_runtime_image(parsed: ParsedINES) -> RuntimeImage:
    """Convert a parsed container into the exact Mapper-0 runtime subset."""

    header = parsed.header
    chr_type, mirroring = _validate_runtime_header(header)
    image = RuntimeImage(
        mapper=header.mapper,
        mirroring=mirroring,
        chr_type=chr_type,
        prg_bytes=parsed.prg_bytes,
        chr_bytes=parsed.chr_bytes,
    )
    if image.prg_size not in (PRG_NROM128_BYTES, PRG_NROM256_BYTES):
        raise UnsupportedINESImage("unsupported physical PRG payload size")
    if image.chr_is_ram and image.chr_size != 0:
        raise UnsupportedINESImage("CHR-RAM images must not contain a CHR-ROM payload")
    if not image.chr_is_ram and image.chr_size != CHR_ROM_BYTES:
        raise UnsupportedINESImage("CHR-ROM images require exactly 8 KiB")
    return image


def inspect_ines(data: bytes) -> ImageInspection:
    """Return header details and a support decision for CLI inspection."""

    header = parse_ines_header(data)
    if header.nes2:
        return ImageInspection(header, None, None, False, "NES 2.0 is not supported")
    parsed = parse_ines(data)
    try:
        image = validate_runtime_image(parsed)
    except UnsupportedINESImage as error:
        return ImageInspection(header, parsed, None, False, str(error))
    return ImageInspection(header, parsed, image, True, None)


def inspect_ines_metadata(header_data: bytes, file_size: int) -> ImageInspection:
    """Inspect one header and file size without reading the ROM payload.

    This is the library-scanning counterpart to :func:`inspect_ines`. It uses
    the same parser and support policy, but leaves payload-bearing fields empty.
    """

    header = parse_ines_header(header_data)
    if header.nes2:
        return ImageInspection(header, None, None, False, "NES 2.0 is not supported")
    _validate_classic_header(header)
    expected_size = ines_container_size(header)
    if file_size < expected_size:
        raise INESFormatError(
            f"file is truncated at {file_size} bytes; header requires "
            f"{expected_size} bytes"
        )
    if file_size > expected_size:
        raise INESFormatError(
            f"file has {file_size - expected_size} unexpected trailing bytes; "
            f"header requires exactly {expected_size} bytes"
        )
    try:
        _validate_runtime_header(header)
    except UnsupportedINESImage as error:
        return ImageInspection(header, None, None, False, str(error))
    return ImageInspection(header, None, None, True, None)


def inspect_ines_file(path: str | Path) -> ImageInspection:
    """Read only the header of a regular iNES file for library display."""

    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK | os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    with os.fdopen(descriptor, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode):
            raise INESFormatError("library entry is not a regular file")
        header_data = stream.read(INES_HEADER_SIZE)
    return inspect_ines_metadata(header_data, metadata.st_size)


def load_runtime_image(
    path: str | Path, *, follow_symlinks: bool = True
) -> RuntimeImage:
    if follow_symlinks:
        data = Path(path).read_bytes()
    else:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK | os.O_NOFOLLOW
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode):
                raise INESFormatError("library entry is not a regular file")
            data = stream.read()
    return validate_runtime_image(parse_ines(data))
