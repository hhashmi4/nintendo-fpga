"""Offline and explicitly selected real-MMIO diagnostic transports."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from software.nes_loader.mmio import DevMemMmio, RawMmio

from . import mmio_registers as regs
from .model import DiagnosticReferenceModel


class DiagnosticBackendError(RuntimeError):
    """Base class for transport errors safe to show to a CLI user."""


class MissingHardwareError(DiagnosticBackendError):
    pass


class DiagnosticPermissionError(DiagnosticBackendError):
    pass


class MalformedMmioReadError(DiagnosticBackendError):
    pass


class DiagnosticBackend(ABC):
    backend_type: str
    hardware_available: bool

    @abstractmethod
    def read32(self, offset: int) -> int:
        pass

    @abstractmethod
    def write32(self, offset: int, value: int) -> None:
        pass

    @abstractmethod
    def close(self) -> None:
        pass

    def __enter__(self) -> DiagnosticBackend:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


INJECTION_CODES = {
    "codec-nack": regs.FAULT_CODEC_INIT_NACK,
    "audio-underrun": regs.FAULT_AUDIO_FIFO_UNDERRUN,
    "audio-overrun": regs.FAULT_AUDIO_FIFO_OVERRUN,
    "loader-timeout": regs.FAULT_LOADER_TIMEOUT,
    "invalid-cartridge": regs.FAULT_INVALID_CARTRIDGE,
    "cpu-stall": regs.FAULT_CPU_STALL_TIMEOUT,
    "missing-video-heartbeat": regs.FAULT_VIDEO_HEARTBEAT_TIMEOUT,
    "dma-timeout": regs.FAULT_DMA_TRANSACTION_TIMEOUT,
    "clock-unlock": regs.FAULT_CLOCK_UNLOCKED,
}


class OfflineDiagnosticBackend(DiagnosticBackend):
    backend_type = "offline-simulation"
    hardware_available = False

    def __init__(self, injections: tuple[str, ...] = ()) -> None:
        self.model = DiagnosticReferenceModel()
        self.words = {offset: 0 for offset in regs.REGISTER_OFFSETS.values()}
        self.words.update({
            regs.REG_MAGIC: regs.MMIO_MAGIC,
            regs.REG_VERSION: regs.MMIO_VERSION,
            regs.REG_BUILD_ID: regs.MMIO_BUILD_ID,
            regs.REG_CAPABILITIES: regs.MMIO_CAPABILITIES,
            regs.REG_AVAILABILITY: regs.MMIO_AVAILABILITY & ~regs.AVAILABLE_USBC_POWER,
            regs.REG_CPU_INSTRUCTIONS: 0xFFFF_FFFF,
            regs.REG_AUDIO_STATUS: 1 << 5,  # muted; not a physical result
            regs.REG_FAULT_CLEAR_MASK: 0xFFFF_FFFF,
        })
        self.trace: list[tuple[int, int, int]] = []
        self.trace_index = 0
        self.closed = False
        for injection in injections:
            if injection == "unsupported-version":
                self.words[regs.REG_VERSION] = 0x0002_0000
                continue
            try:
                self.inject_fault(INJECTION_CODES[injection])
            except KeyError as exc:
                raise ValueError(f"unknown fault injection {injection!r}") from exc

    def _check(self, offset: int) -> None:
        if self.closed:
            raise DiagnosticBackendError("diagnostic backend is closed")
        if offset < 0 or offset % 4 or offset + 4 > regs.MMIO_SPAN_BYTES:
            raise MalformedMmioReadError(
                f"invalid 32-bit diagnostic MMIO offset 0x{offset:x}"
            )

    def inject_fault(self, code: int) -> None:
        self.model.faults.observe(code)
        self.words[regs.REG_FAULT_FLAGS] = self.model.faults.flags
        self.words[regs.REG_LAST_FAULT] = self.model.faults.last_code
        self.words[regs.REG_SYSTEM_STATUS] |= 1 << 5

    def read32(self, offset: int) -> int:
        self._check(offset)
        if offset == regs.REG_TRACE_TIMESTAMP:
            return self._trace_entry()[0]
        if offset == regs.REG_TRACE_EVENT:
            return self._trace_entry()[1]
        if offset == regs.REG_TRACE_PAYLOAD:
            return self._trace_entry()[2]
        return self.words.get(offset, 0) & 0xFFFF_FFFF

    def _trace_entry(self) -> tuple[int, int, int]:
        if self.trace_index >= len(self.trace):
            return (0, 0, 0)
        return self.trace[self.trace_index]

    def write32(self, offset: int, value: int) -> None:
        self._check(offset)
        value &= 0xFFFF_FFFF
        if offset == regs.REG_FAULT_CLEAR_MASK:
            self.words[offset] = value
        elif offset == regs.REG_TRACE_INDEX:
            self.trace_index = value & 0xF
            self.words[offset] = self.trace_index
        elif offset == regs.REG_CONTROL:
            if value & regs.CONTROL_FAULT_CLEAR:
                self.model.faults.clear(self.words[regs.REG_FAULT_CLEAR_MASK])
                self.words[regs.REG_FAULT_FLAGS] = self.model.faults.flags
                self.words[regs.REG_LAST_FAULT] = self.model.faults.last_code
                if self.model.faults.flags == 0:
                    self.words[regs.REG_SYSTEM_STATUS] &= ~(1 << 5)
            if value & regs.CONTROL_TRACE_CLEAR:
                self.trace.clear()
                self.words[regs.REG_TRACE_STATUS] = 0
                self.words[regs.REG_TRACE_OVERFLOW] = 0
            if value & regs.CONTROL_TRACE_ARM:
                self.words[regs.REG_TRACE_STATUS] = 1
            if value & regs.CONTROL_TRACE_TRIGGER:
                self.words[regs.REG_TRACE_STATUS] = 0b110
            if value & regs.CONTROL_TRACE_FREEZE:
                self.words[regs.REG_TRACE_STATUS] |= 0b100
                self.words[regs.REG_TRACE_STATUS] &= ~1
            if value & regs.CONTROL_SNAPSHOT:
                self.words[regs.REG_SNAPSHOT_SEQUENCE] = (
                    self.words[regs.REG_SNAPSHOT_SEQUENCE] + 1
                ) & 0xFFFF_FFFF
                self.words[regs.REG_CONTROL_STATUS] = 0b010
            self.words[regs.REG_CONTROL] = value
        else:
            self.words[offset] = value

    def close(self) -> None:
        self.closed = True


class MmioDiagnosticBackend(DiagnosticBackend):
    backend_type = "real-mmio"
    hardware_available = True

    def __init__(self, raw_mmio: RawMmio) -> None:
        self.raw_mmio = raw_mmio

    @classmethod
    def open(cls, device: str = "/dev/mem") -> MmioDiagnosticBackend:
        if not Path(device).exists():
            raise MissingHardwareError(
                f"diagnostic MMIO device {device!r} is not present"
            )
        try:
            return cls(
                DevMemMmio(
                    regs.MMIO_PHYSICAL_BASE,
                    regs.MMIO_SPAN_BYTES,
                    device=device,
                )
            )
        except PermissionError as exc:
            raise DiagnosticPermissionError(
                f"permission denied opening diagnostic MMIO device {device!r}"
            ) from exc
        except OSError as exc:
            raise DiagnosticBackendError(
                f"could not map diagnostic MMIO device {device!r}: {exc}"
            ) from exc

    def read32(self, offset: int) -> int:
        try:
            value = self.raw_mmio.read32(offset)
        except (OSError, ValueError) as exc:
            raise MalformedMmioReadError(
                f"diagnostic MMIO read failed at 0x{offset:03x}: {exc}"
            ) from exc
        if not isinstance(value, int) or not 0 <= value <= 0xFFFF_FFFF:
            raise MalformedMmioReadError(
                f"malformed diagnostic MMIO value at 0x{offset:03x}"
            )
        return value

    def write32(self, offset: int, value: int) -> None:
        try:
            self.raw_mmio.write32(offset, value)
        except (OSError, ValueError) as exc:
            raise DiagnosticBackendError(
                f"diagnostic MMIO write failed at 0x{offset:03x}: {exc}"
            ) from exc

    def close(self) -> None:
        self.raw_mmio.close()
