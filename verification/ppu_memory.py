"""Independent behavioral model of the Phase 3C PPU address space."""

from dataclasses import dataclass
from enum import IntEnum


class MirroringMode(IntEnum):
    VERTICAL = 0
    HORIZONTAL = 1
    SINGLE_SCREEN_LOWER = 2
    SINGLE_SCREEN_UPPER = 3


class MemoryRegion(IntEnum):
    CHR = 0
    NAMETABLE = 1
    PALETTE = 2


@dataclass(frozen=True)
class AddressTranslation:
    address: int
    region: MemoryRegion
    normalized_nametable_address: int
    logical_nametable: int
    nametable_offset: int
    physical_ciram_page: int
    ciram_address: int
    palette_index: int
    chr_address: int


def canonical_palette_index(address: int) -> int:
    """Map any palette-space alias to one of 32 physical byte indices."""

    index = address & 0x1F
    if index >= 0x10 and index % 4 == 0:
        index -= 0x10
    return index


def normalized_nametable_relative(address: int) -> int:
    """Return the logical offset in the canonical $2000-$2FFF window."""

    address &= 0x3FFF
    if 0x3000 <= address <= 0x3EFF:
        address -= 0x1000
    return (address - 0x2000) & 0x0FFF


def physical_page(logical_page: int, mode: MirroringMode) -> int:
    logical_page &= 3
    if mode == MirroringMode.VERTICAL:
        return logical_page & 1
    if mode == MirroringMode.HORIZONTAL:
        return logical_page >> 1
    if mode == MirroringMode.SINGLE_SCREEN_LOWER:
        return 0
    if mode == MirroringMode.SINGLE_SCREEN_UPPER:
        return 1
    raise ValueError(f"unsupported mirroring mode {mode!r}")


def translate(address: int, mode: MirroringMode) -> AddressTranslation:
    """Classify and translate one address without modeling RTL structure."""

    address &= 0x3FFF
    if address < 0x2000:
        region = MemoryRegion.CHR
    elif address < 0x3F00:
        region = MemoryRegion.NAMETABLE
    else:
        region = MemoryRegion.PALETTE

    relative = normalized_nametable_relative(address)
    logical = (relative >> 10) & 3
    offset = relative & 0x3FF
    page = physical_page(logical, mode)
    return AddressTranslation(
        address=address,
        region=region,
        normalized_nametable_address=relative,
        logical_nametable=logical,
        nametable_offset=offset,
        physical_ciram_page=page,
        ciram_address=(page << 10) | offset,
        palette_index=canonical_palette_index(address),
        chr_address=address & 0x1FFF,
    )


class PpuMemoryModel:
    """Storage-level model with a simulation-only CHR-RAM test device."""

    def __init__(self, mode: MirroringMode = MirroringMode.VERTICAL) -> None:
        self.mode = mode
        self.ciram = bytearray(2048)
        self.palette = bytearray(32)
        self.chr = bytearray(8192)

    def set_mode(self, mode: MirroringMode) -> None:
        self.mode = mode

    def translation(self, address: int) -> AddressTranslation:
        return translate(address, self.mode)

    def read(self, address: int) -> int:
        decoded = self.translation(address)
        if decoded.region == MemoryRegion.CHR:
            return self.chr[decoded.chr_address]
        if decoded.region == MemoryRegion.NAMETABLE:
            return self.ciram[decoded.ciram_address]
        return self.palette[decoded.palette_index]

    def write(self, address: int, data: int) -> MemoryRegion:
        decoded = self.translation(address)
        data &= 0xFF
        if decoded.region == MemoryRegion.CHR:
            self.chr[decoded.chr_address] = data
        elif decoded.region == MemoryRegion.NAMETABLE:
            self.ciram[decoded.ciram_address] = data
        else:
            self.palette[decoded.palette_index] = data
        return decoded.region
