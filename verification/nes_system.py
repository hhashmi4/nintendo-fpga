"""Independent scheduling, CPU-space decode, and DMA reference logic."""

from dataclasses import dataclass
from enum import IntEnum
from typing import Callable

from verification.nes_bus import CpuTarget, decode_cpu_address


class Scheduler:
    """Three always-enabled PPU ticks for every scheduled CPU slot."""

    def __init__(self) -> None:
        self.phase = 0
        self.fabric_cycles = 0
        self.ppu_ticks = 0
        self.cpu_slots = 0

    def clock(self, *, reset: bool = False) -> tuple[bool, bool]:
        if reset:
            self.phase = 0
            return False, False
        ppu_enable = True
        cpu_slot = self.phase == 2
        self.fabric_cycles += 1
        self.ppu_ticks += 1
        self.cpu_slots += int(cpu_slot)
        self.phase = (self.phase + 1) % 3
        return ppu_enable, cpu_slot


class DmaPhase(IntEnum):
    IDLE = 0
    DUMMY = 1
    ALIGN = 2
    READ = 3
    WRITE = 4


@dataclass(frozen=True)
class DmaResult:
    page: int
    started_odd: bool
    stall_cycles: int
    reads: int
    writes: int
    final_oam_address: int


class OamDmaModel:
    """CPU-slot-level semantic model of the Phase 3J DMA sequencer."""

    def __init__(self) -> None:
        self.oam = bytearray(256)
        self.oam_address = 0
        self.active = False
        self.phase = DmaPhase.IDLE
        self.page = 0
        self.index = 0
        self.data = 0
        self.started_odd = False
        self.stall_cycles = 0
        self.reads = 0
        self.writes = 0

    def trigger(self, page: int, *, cpu_cycle_odd: bool) -> None:
        if self.active:
            raise RuntimeError("DMA cannot be retriggered while active")
        self.active = True
        self.phase = DmaPhase.DUMMY
        self.page = page & 0xFF
        self.index = 0
        self.started_odd = bool(cpu_cycle_odd)
        self.stall_cycles = 0
        self.reads = 0
        self.writes = 0

    def cpu_slot(self, read_cpu: Callable[[int], int]) -> bool:
        """Consume one scheduled CPU slot; return True on completion."""

        if not self.active:
            return False
        self.stall_cycles += 1
        if self.phase == DmaPhase.DUMMY:
            self.phase = DmaPhase.ALIGN if self.started_odd else DmaPhase.READ
        elif self.phase == DmaPhase.ALIGN:
            self.phase = DmaPhase.READ
        elif self.phase == DmaPhase.READ:
            self.data = read_cpu((self.page << 8) | self.index) & 0xFF
            self.reads += 1
            self.phase = DmaPhase.WRITE
        elif self.phase == DmaPhase.WRITE:
            self.oam[self.oam_address] = self.data
            self.oam_address = (self.oam_address + 1) & 0xFF
            self.writes += 1
            if self.index == 0xFF:
                self.active = False
                self.phase = DmaPhase.IDLE
                return True
            self.index += 1
            self.phase = DmaPhase.READ
        else:
            raise AssertionError(self.phase)
        return False

    def run(self, read_cpu: Callable[[int], int]) -> DmaResult:
        while not self.cpu_slot(read_cpu):
            pass
        return DmaResult(
            page=self.page,
            started_odd=self.started_odd,
            stall_cycles=self.stall_cycles,
            reads=self.reads,
            writes=self.writes,
            final_oam_address=self.oam_address,
        )


@dataclass(frozen=True)
class DmcDmaResult:
    acknowledge: bool
    data: int
    cpu_stall: bool
    start: bool
    complete: bool


class DmcDmaModel:
    """CPU-slot model of the DMC halt/dummy/align/read transaction."""

    def __init__(self) -> None:
        self.active = False
        self.phase = DmaPhase.IDLE
        self.address = 0
        self.started_odd = False
        self.elapsed_cpu_cycles = 0

    def reset(self) -> None:
        self.__init__()

    def cpu_slot(
        self,
        *,
        request: bool,
        request_address: int,
        cpu_cycle_odd: bool,
        halt_allowed: bool,
        read_cpu: Callable[[int], int],
    ) -> DmcDmaResult:
        start = False
        complete = False
        acknowledge = False
        data = 0
        stall = self.active or (request and halt_allowed)

        if not self.active:
            if request and halt_allowed:
                self.active = True
                self.phase = DmaPhase.DUMMY
                self.address = request_address & 0xFFFF
                self.started_odd = bool(cpu_cycle_odd)
                self.elapsed_cpu_cycles = 1
                start = True
        else:
            self.elapsed_cpu_cycles += 1
            if self.phase == DmaPhase.DUMMY:
                self.phase = (
                    DmaPhase.ALIGN if self.started_odd else DmaPhase.READ
                )
            elif self.phase == DmaPhase.ALIGN:
                self.phase = DmaPhase.READ
            elif self.phase == DmaPhase.READ:
                data = read_cpu(self.address) & 0xFF
                acknowledge = True
                complete = True
                self.active = False
                self.phase = DmaPhase.IDLE
            else:
                raise AssertionError(self.phase)

        return DmcDmaResult(
            acknowledge=acknowledge,
            data=data,
            cpu_stall=stall,
            start=start,
            complete=complete,
        )


def mirrored_ram_read(ram: bytes | bytearray, address: int) -> int:
    if len(ram) != 2048:
        raise ValueError("NES internal RAM must contain exactly 2048 bytes")
    return ram[address & 0x07FF]


def dma_source_addresses(page: int) -> tuple[int, ...]:
    """Return the exact 256-address sequence produced by an OAM DMA page."""

    base = (page & 0xFF) << 8
    return tuple(base | index for index in range(256))


def dma_cycle_trace(started_odd: bool) -> tuple[DmaPhase, ...]:
    """Return independently expected DMA phases for each stalled CPU slot."""

    trace = [DmaPhase.DUMMY]
    if started_odd:
        trace.append(DmaPhase.ALIGN)
    for _ in range(256):
        trace.extend((DmaPhase.READ, DmaPhase.WRITE))
    return tuple(trace)


def dma_read_cpu_space(
    address: int,
    ram: bytes | bytearray,
    *,
    ppu_read: Callable[[int], int],
    cartridge_read: Callable[[int], int],
) -> int:
    """Apply the project's DMA-source policy to one CPU-space address.

    RAM uses its physical 2 KiB mirror. PPU and cartridge reads delegate to
    their existing owners. APU, DMA, controller, and unmapped I/O deliberately
    return zero rather than emitting CPU peripheral accesses.
    """

    address &= 0xFFFF
    target, physical = decode_cpu_address(address)
    if target == CpuTarget.RAM:
        return mirrored_ram_read(ram, address)
    if target == CpuTarget.PPU:
        return ppu_read(physical) & 0xFF
    if target == CpuTarget.CARTRIDGE:
        return cartridge_read(address) & 0xFF
    return 0


def dmc_read_cpu_space(
    address: int,
    ram: bytes | bytearray,
    *,
    ppu_read: Callable[[int], int],
    cartridge_read: Callable[[int], int],
) -> int:
    """Read through the same centralized CPU-space policy as OAM DMA.

    Programmed DMC addresses are always in cartridge space, but sharing this
    path is intentional: mirrors and any future mapper ownership remain in
    the system decoder rather than being duplicated by the audio channel.
    """

    return dma_read_cpu_space(
        address,
        ram,
        ppu_read=ppu_read,
        cartridge_read=cartridge_read,
    )
