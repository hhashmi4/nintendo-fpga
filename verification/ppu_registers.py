"""Behavioral reference model for the Phase 3B CPU-facing PPU registers.

The model describes programmer-visible transactions and deliberately avoids
mirroring the RTL's sequential case statement.  A transaction is observed
before its accepting edge and then applied atomically by :meth:`clock`.
"""

from dataclasses import dataclass


PPU_REGISTER_FIRST = 0x2000
PPU_REGISTER_LAST = 0x3FFF

PPUCTRL = 0
PPUMASK = 1
PPUSTATUS = 2
OAMADDR = 3
OAMDATA = 4
PPUSCROLL = 5
PPUADDR = 6
PPUDATA = 7


@dataclass(frozen=True)
class PpuBusInputs:
    """Inputs presented during one fabric-clock interval."""

    reset: bool = False
    cpu_enable: bool = False
    cpu_bus_valid: bool = False
    cpu_bus_write: bool = False
    cpu_address: int = 0
    cpu_write_data: int = 0
    vblank_start_event: bool = False
    status_clear_event: bool = False
    sprite_zero_hit_set: bool = False
    sprite_overflow_set: bool = False
    oam_read_data: int = 0
    memory_read_data: int = 0
    memory_buffer_read_data: int = 0


@dataclass(frozen=True)
class PpuBusObservation:
    """Combinational results produced before a transaction commits."""

    selected: bool
    register_index: int
    accepted: bool
    cpu_read_data: int
    oam_write_enable: bool
    memory_read_request: bool
    memory_write_request: bool
    memory_address: int
    memory_buffer_address: int


class PpuRegisterModel:
    """Semantic model of the CPU-programmable PPU register state."""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.ppuctrl = 0
        self.ppumask = 0
        self.status_vblank = False
        self.status_sprite_zero_hit = False
        self.status_sprite_overflow = False
        self.oam_addr = 0
        self.v = 0
        self.t = 0
        self.x = 0
        self.w = False
        self.read_buffer = 0
        self.io_latch = 0

    @staticmethod
    def decode(address: int) -> tuple[bool, int]:
        address &= 0xFFFF
        return PPU_REGISTER_FIRST <= address <= PPU_REGISTER_LAST, address & 7

    @property
    def rendering_enabled(self) -> bool:
        return bool(self.ppumask & 0x18)

    @property
    def vram_increment(self) -> int:
        return 32 if self.ppuctrl & 0x04 else 1

    @property
    def status(self) -> int:
        return (
            (int(self.status_vblank) << 7)
            | (int(self.status_sprite_zero_hit) << 6)
            | (int(self.status_sprite_overflow) << 5)
        )

    def observe(self, inputs: PpuBusInputs) -> PpuBusObservation:
        selected, register = self.decode(inputs.cpu_address)
        accepted = (
            not inputs.reset
            and inputs.cpu_enable
            and inputs.cpu_bus_valid
            and selected
        )
        memory_address = self.v & 0x3FFF
        palette = memory_address >= 0x3F00

        read_data = self.io_latch
        if selected and register == PPUSTATUS:
            read_data = self.status | (self.io_latch & 0x1F)
        elif selected and register == OAMDATA:
            read_data = inputs.oam_read_data
        elif selected and register == PPUDATA:
            read_data = inputs.memory_read_data if palette else self.read_buffer

        return PpuBusObservation(
            selected=selected,
            register_index=register,
            accepted=accepted,
            cpu_read_data=read_data,
            oam_write_enable=accepted
            and inputs.cpu_bus_write
            and register == OAMDATA,
            memory_read_request=accepted
            and not inputs.cpu_bus_write
            and register == PPUDATA,
            memory_write_request=accepted
            and inputs.cpu_bus_write
            and register == PPUDATA,
            memory_address=memory_address,
            memory_buffer_address=(
                (memory_address - 0x1000) & 0x3FFF if palette else memory_address
            ),
        )

    def clock(self, inputs: PpuBusInputs) -> PpuBusObservation:
        """Consume one edge and return its pre-edge bus observation."""

        observation = self.observe(inputs)
        if inputs.reset:
            self.reset()
            return observation

        # The pre-render clear owns all status flags on its event edge.  This
        # deterministic ordering intentionally does not claim later NMI-race
        # compatibility.
        if inputs.status_clear_event:
            self.status_vblank = False
            self.status_sprite_zero_hit = False
            self.status_sprite_overflow = False
        else:
            self.status_vblank |= inputs.vblank_start_event
            self.status_sprite_zero_hit |= inputs.sprite_zero_hit_set
            self.status_sprite_overflow |= inputs.sprite_overflow_set

        if not observation.accepted:
            return observation

        data = inputs.cpu_write_data & 0xFF
        register = observation.register_index
        if inputs.cpu_bus_write:
            self.io_latch = data
            if register == PPUCTRL:
                self.ppuctrl = data
                self.t = (self.t & ~(0x3 << 10)) | ((data & 0x03) << 10)
            elif register == PPUMASK:
                self.ppumask = data
            elif register == OAMADDR:
                self.oam_addr = data
            elif register == OAMDATA:
                self.oam_addr = (self.oam_addr + 1) & 0xFF
            elif register == PPUSCROLL:
                if not self.w:
                    self.t = (self.t & ~0x001F) | (data >> 3)
                    self.x = data & 0x07
                else:
                    self.t = (
                        (self.t & ~0x73E0)
                        | ((data >> 3) << 5)
                        | ((data & 0x07) << 12)
                    )
                self.w = not self.w
            elif register == PPUADDR:
                if not self.w:
                    self.t = (self.t & 0x00FF) | ((data & 0x3F) << 8)
                    self.w = True
                else:
                    self.t = (self.t & 0x7F00) | data
                    self.v = self.t
                    self.w = False
            elif register == PPUDATA:
                self.v = (self.v + self.vram_increment) & 0x7FFF
            return observation

        if register == PPUSTATUS:
            self.io_latch = observation.cpu_read_data
            self.status_vblank = False
            self.w = False
        elif register == OAMDATA:
            self.io_latch = observation.cpu_read_data
        elif register == PPUDATA:
            self.io_latch = observation.cpu_read_data
            self.read_buffer = (
                inputs.memory_buffer_read_data
                if observation.memory_address >= 0x3F00
                else inputs.memory_read_data
            ) & 0xFF
            self.v = (self.v + self.vram_increment) & 0x7FFF
        return observation
