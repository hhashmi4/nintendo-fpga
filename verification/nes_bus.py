"""Independent NES CPU system-bus reference model for Phase 4A."""

from dataclasses import dataclass
from enum import IntEnum


class CpuTarget(IntEnum):
    NONE = 0
    RAM = 1
    PPU = 2
    APU = 3
    DMA = 4
    CONTROLLER = 5
    CARTRIDGE = 6


@dataclass(frozen=True)
class CpuBusDecode:
    target: CpuTarget
    physical_address: int
    ram_address: int
    ppu_register: int


def decode_cpu_access(address: int, *, write: bool = False) -> CpuBusDecode:
    """Return the owning target and normalized sub-address for one access."""

    address &= 0xFFFF
    if address <= 0x1FFF:
        target = CpuTarget.RAM
        physical = address & 0x07FF
    elif address <= 0x3FFF:
        target = CpuTarget.PPU
        physical = address & 0x0007
    elif address <= 0x4013 or address == 0x4015:
        target = CpuTarget.APU
        physical = address
    elif address == 0x4014:
        target = CpuTarget.DMA
        physical = 0
    elif address == 0x4016:
        target = CpuTarget.CONTROLLER
        physical = 0
    elif address == 0x4017:
        target = CpuTarget.APU if write else CpuTarget.CONTROLLER
        physical = address if write else 1
    elif address >= 0x4020:
        target = CpuTarget.CARTRIDGE
        physical = address
    else:
        target = CpuTarget.NONE
        physical = 0

    return CpuBusDecode(
        target=target,
        physical_address=physical,
        ram_address=address & 0x07FF,
        ppu_register=address & 0x0007,
    )


def decode_cpu_address(
    address: int, *, write: bool = False
) -> tuple[CpuTarget, int]:
    """Compatibility tuple used by the retained Phase 3J reference tests."""

    decoded = decode_cpu_access(address, write=write)
    return decoded.target, decoded.physical_address
