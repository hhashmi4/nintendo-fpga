"""Independent Mapper 0/NROM address and memory reference model."""

from __future__ import annotations

from dataclasses import dataclass, field

from verification.ines import CHR_BANK_SIZE, PRG_BANK_SIZE


def map_prg_address(cpu_address: int, prg_size: int) -> int | None:
    address = cpu_address & 0xFFFF
    if address < 0x8000:
        return None
    if prg_size == PRG_BANK_SIZE:
        return address & 0x3FFF
    if prg_size == 2 * PRG_BANK_SIZE:
        return address & 0x7FFF
    raise ValueError("Mapper 0 PRG size must be 16 KiB or 32 KiB")


def map_chr_address(ppu_address: int) -> int | None:
    address = ppu_address & 0x3FFF
    return address if address < 0x2000 else None


def map_ciram_address(ppu_address: int, mirroring: str) -> int:
    address = ppu_address & 0x3FFF
    if 0x3000 <= address <= 0x3EFF:
        address -= 0x1000
    if not 0x2000 <= address <= 0x2FFF:
        raise ValueError("address is outside the PPU nametable region")
    normalized = address - 0x2000
    logical_page = (normalized >> 10) & 0x03
    offset = normalized & 0x03FF
    if mirroring == "vertical":
        physical_page = logical_page & 0x01
    elif mirroring == "horizontal":
        physical_page = (logical_page >> 1) & 0x01
    else:
        raise ValueError("mirroring must be horizontal or vertical")
    return (physical_page << 10) | offset


@dataclass
class Mapper0Model:
    prg_rom: bytes
    chr_rom: bytes = b""
    prg_ram_enabled: bool = False
    prg_ram: bytearray = field(default_factory=lambda: bytearray(8 * 1024))
    chr_ram: bytearray = field(default_factory=lambda: bytearray(CHR_BANK_SIZE))

    def __post_init__(self) -> None:
        if len(self.prg_rom) not in (PRG_BANK_SIZE, 2 * PRG_BANK_SIZE):
            raise ValueError("Mapper 0 PRG ROM must be 16 KiB or 32 KiB")
        if len(self.chr_rom) not in (0, CHR_BANK_SIZE):
            raise ValueError("Mapper 0 CHR ROM must be zero or 8 KiB")

    @property
    def chr_is_ram(self) -> bool:
        return not self.chr_rom

    def cpu_read(self, address: int) -> int:
        address &= 0xFFFF
        prg_index = map_prg_address(address, len(self.prg_rom))
        if prg_index is not None:
            return self.prg_rom[prg_index]
        if self.prg_ram_enabled and 0x6000 <= address <= 0x7FFF:
            return self.prg_ram[address & 0x1FFF]
        return 0

    def cpu_write(self, address: int, value: int) -> None:
        address &= 0xFFFF
        if self.prg_ram_enabled and 0x6000 <= address <= 0x7FFF:
            self.prg_ram[address & 0x1FFF] = value & 0xFF

    def ppu_read(self, address: int) -> int:
        chr_index = map_chr_address(address)
        if chr_index is None:
            return 0
        return (
            self.chr_ram[chr_index]
            if self.chr_is_ram
            else self.chr_rom[chr_index]
        )

    def ppu_write(self, address: int, value: int) -> None:
        chr_index = map_chr_address(address)
        if self.chr_is_ram and chr_index is not None:
            self.chr_ram[chr_index] = value & 0xFF
