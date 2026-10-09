"""Structured register access and decoding for the Phase 5M interface."""

from __future__ import annotations

import time
from typing import Any

from .backend import DiagnosticBackend, DiagnosticBackendError
from . import mmio_registers as regs


class UnsupportedDiagnosticInterface(DiagnosticBackendError):
    pass


class DiagnosticTimeout(DiagnosticBackendError):
    pass


SNAPSHOT_REGISTERS = tuple(
    name
    for name in regs.REGISTER_OFFSETS
    if name not in {
        "MAGIC",
        "VERSION",
        "BUILD_ID",
        "CAPABILITIES",
        "CONTROL",
        "CONTROL_STATUS",
        "SNAPSHOT_SEQUENCE",
        "AVAILABILITY",
        "FAULT_CLEAR_MASK",
        "MMIO_HEARTBEAT",
        "TRACE_INDEX",
        "TRACE_TIMESTAMP",
        "TRACE_EVENT",
        "TRACE_PAYLOAD",
    }
)


class DiagnosticClient:
    def __init__(self, backend: DiagnosticBackend, *, timeout_s: float = 0.25):
        if timeout_s <= 0:
            raise ValueError("diagnostic timeout must be positive")
        self.backend = backend
        self.timeout_s = timeout_s

    def validate_interface(self) -> dict[str, int]:
        magic = self.backend.read32(regs.REG_MAGIC)
        if magic != regs.MMIO_MAGIC:
            raise DiagnosticBackendError(
                f"diagnostic magic mismatch: 0x{magic:08x}"
            )
        version = self.backend.read32(regs.REG_VERSION)
        major = version >> 16
        minor = version & 0xFFFF
        if major != regs.MMIO_VERSION_MAJOR:
            raise UnsupportedDiagnosticInterface(
                f"unsupported diagnostic interface {major}.{minor}; "
                f"expected {regs.MMIO_VERSION_MAJOR}.x"
            )
        return {
            "magic": magic,
            "version": version,
            "build_id": self.backend.read32(regs.REG_BUILD_ID),
            "capabilities": self.backend.read32(regs.REG_CAPABILITIES),
            "availability": self.backend.read32(regs.REG_AVAILABILITY),
        }

    def _command(self, value: int, *, expect_snapshot: bool = False) -> None:
        prior_sequence = self.backend.read32(regs.REG_SNAPSHOT_SEQUENCE)
        self.backend.write32(regs.REG_CONTROL, value)
        deadline = time.monotonic() + self.timeout_s
        while time.monotonic() < deadline:
            control_status = self.backend.read32(regs.REG_CONTROL_STATUS)
            if control_status & 0b100:
                raise DiagnosticBackendError("diagnostic command was rejected")
            if not control_status & 1:
                if not expect_snapshot:
                    return
                sequence = self.backend.read32(regs.REG_SNAPSHOT_SEQUENCE)
                if sequence != prior_sequence and control_status & 0b010:
                    return
            time.sleep(0.001)
        raise DiagnosticTimeout("diagnostic command timed out")

    def snapshot(self) -> dict[str, int]:
        identity = self.validate_interface()
        self._command(regs.CONTROL_SNAPSHOT, expect_snapshot=True)
        values = {
            name.lower(): self.backend.read32(offset)
            for name, offset in regs.REGISTER_OFFSETS.items()
            if name in SNAPSHOT_REGISTERS
        }
        values.update(identity)
        values["snapshot_sequence"] = self.backend.read32(
            regs.REG_SNAPSHOT_SEQUENCE
        )
        values["mmio_heartbeat"] = self.backend.read32(regs.REG_MMIO_HEARTBEAT)
        return values

    @staticmethod
    def decode_faults(flags: int) -> list[dict[str, int | str]]:
        return [
            {"code": code, "name": name, "bit": code - 1}
            for code, name in regs.FAULT_NAMES.items()
            if flags & (1 << (code - 1))
        ]

    def faults(self, snapshot: dict[str, int] | None = None) -> list[dict[str, Any]]:
        current = snapshot if snapshot is not None else self.snapshot()
        return self.decode_faults(current["fault_flags"])

    def clear_faults(self, mask: int = 0xFFFF_FFFF) -> None:
        self.backend.write32(regs.REG_FAULT_CLEAR_MASK, mask & 0xFFFF_FFFF)
        self._command(regs.CONTROL_FAULT_CLEAR)

    def trace(self, snapshot: dict[str, int] | None = None) -> list[dict[str, int | str]]:
        current = snapshot if snapshot is not None else self.snapshot()
        status = current["trace_status"]
        count = (status >> 3) & 0x1F
        write_index = (status >> 8) & 0xF
        count = min(count, regs.TRACE_DEPTH)
        oldest = write_index if count == regs.TRACE_DEPTH else 0
        result: list[dict[str, int | str]] = []
        for order in range(count):
            physical_index = (oldest + order) % regs.TRACE_DEPTH
            self.backend.write32(regs.REG_TRACE_INDEX, physical_index)
            code = self.backend.read32(regs.REG_TRACE_EVENT) & 0xFF
            result.append({
                "order": order,
                "physical_index": physical_index,
                "timestamp": self.backend.read32(regs.REG_TRACE_TIMESTAMP),
                "code": code,
                "name": regs.EVENT_NAMES.get(code, f"UNKNOWN_{code}"),
                "payload": self.backend.read32(regs.REG_TRACE_PAYLOAD) & 0xFF_FFFF,
            })
        return result

    @staticmethod
    def interpreted_status(snapshot: dict[str, int]) -> dict[str, Any]:
        system = snapshot["system_status"]
        clocks = snapshot["clock_status"]
        cpu = snapshot["cpu_status"]
        video = snapshot["video_status"]
        audio = snapshot["audio_status"]
        loader = snapshot["loader_status"]
        dma = snapshot["dma_status"]
        cartridge = snapshot["cartridge_status"]
        availability = snapshot["availability"]
        return {
            "system": {
                "reset": bool(system & 1),
                "nes_reset": bool(system & 2),
                "debugger_paused": bool(system & 4),
                "cartridge_present": bool(system & 8),
                "runtime_active": bool(system & 16),
                "fault_present": bool(system & 32),
            },
            "clocks": {
                "video_pll_locked": bool(clocks & 1),
                "audio_pll_locked": bool(clocks & 2),
                "video_pll_seen": bool(clocks & 4),
                "audio_pll_seen": bool(clocks & 8),
            },
            "cpu": {
                "reset": bool(cpu & 1),
                "stalled": bool(cpu & 2),
                "irq": bool(cpu & 4),
                "debugger_paused": bool(cpu & 8),
                "pc": snapshot["cpu_pc"] & 0xFFFF,
                "instruction_retirement": (
                    snapshot["cpu_instructions"]
                    if availability & regs.AVAILABLE_CPU_INSTRUCTIONS
                    else None
                ),
            },
            "ppu": {
                "dot": snapshot["ppu_status"] & 0x1FF,
                "scanline": (snapshot["ppu_status"] >> 9) & 0x1FF,
                "frames": snapshot["ppu_frames"],
            },
            "video": {
                "pll_locked": bool(video & 1),
                "active": bool(video & 16),
                "frames": snapshot["vga_frames"],
            },
            "audio": {
                "pll_locked": bool(audio & 1),
                "codec_busy": bool(audio & 4),
                "codec_done": bool(audio & 8),
                "codec_error": bool(audio & 16),
                "muted": bool(audio & 32),
                "fifo_occupancy": snapshot["audio_fifo"] & 0xFFFF,
            },
            "loader": {
                "state": loader & 0x3,
                "busy": bool(loader & 0x4),
                "image_valid": bool(loader & 0x8),
                "runtime_active": bool(loader & 0x10),
                "error": bool(loader & 0x40),
                "error_code": (loader >> 7) & 0xF,
            },
            "dma": {
                "cpu_stalled": bool(dma & 1),
                "oam_active": bool(dma & 2),
                "dmc_request": bool(dma & 4),
                "bus_owner": (dma >> 3) & 0x7,
            },
            "cartridge": {
                "present": bool(cartridge & 1),
                "mapper": (cartridge >> 1) & 0xFF,
                "nrom_256": bool(cartridge & (1 << 9)),
                "chr_is_ram": bool(cartridge & (1 << 10)),
                "mirroring": (cartridge >> 11) & 0x3,
            },
        }
