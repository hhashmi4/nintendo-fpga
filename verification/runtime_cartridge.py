"""Independent Phase 4F-B runtime-cartridge behavioral model."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum


PRG_STORAGE_BYTES = 32 * 1024
CHR_STORAGE_BYTES = 8 * 1024


class RuntimeTarget(IntEnum):
    PRG = 1
    CHR = 2


@dataclass
class RuntimeCartridgeModel:
    """Byte-store and Mapper-0 oracle, intentionally free of RTL timing."""

    prg: bytearray = field(
        default_factory=lambda: bytearray(PRG_STORAGE_BYTES)
    )
    chr: bytearray = field(
        default_factory=lambda: bytearray(CHR_STORAGE_BYTES)
    )

    def loader_write(
        self,
        target: RuntimeTarget | int,
        address: int,
        data: int,
        *,
        reset: bool = False,
    ) -> bool:
        """Accept one validated storage write, returning its acceptance."""

        if reset or not 0 <= data <= 0xFF:
            return False
        try:
            selected = RuntimeTarget(target)
        except ValueError:
            return False
        if selected is RuntimeTarget.PRG and 0 <= address < len(self.prg):
            self.prg[address] = data
            return True
        if selected is RuntimeTarget.CHR and 0 <= address < len(self.chr):
            self.chr[address] = data
            return True
        return False

    @staticmethod
    def map_prg_address(cpu_address: int, *, nrom_256: bool) -> int | None:
        """Translate a CPU cartridge address to the physical PRG byte."""

        if not 0x8000 <= cpu_address <= 0xFFFF:
            return None
        if nrom_256:
            return cpu_address - 0x8000
        return (cpu_address - 0x8000) & 0x3FFF

    def cpu_read(self, cpu_address: int, *, nrom_256: bool) -> int:
        mapped = self.map_prg_address(cpu_address, nrom_256=nrom_256)
        return 0 if mapped is None else self.prg[mapped]

    def ppu_read(self, chr_address: int) -> int:
        if not 0 <= chr_address < len(self.chr):
            return 0
        return self.chr[chr_address]

    def ppu_write(
        self,
        chr_address: int,
        data: int,
        *,
        chr_is_ram: bool,
        reset: bool = False,
    ) -> bool:
        if (
            reset
            or not chr_is_ram
            or not 0 <= chr_address < len(self.chr)
            or not 0 <= data <= 0xFF
        ):
            return False
        self.chr[chr_address] = data
        return True

    def collision_read(
        self,
        *,
        target: RuntimeTarget,
        address: int,
        data: int,
    ) -> int:
        """Model the documented loader/read same-cycle write-first result."""

        if not self.loader_write(target, address, data):
            raise ValueError("invalid collision write")
        if target is RuntimeTarget.PRG:
            return self.prg[address]
        return self.chr[address]
