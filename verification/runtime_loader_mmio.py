"""Faithful register-level Phase 4F-F MMIO device model."""

from __future__ import annotations

from software.nes_loader.mmio import FakeMmio
from software.nes_loader.mmio_registers import (
    CONTROL_CLEAR_SUBMIT_REJECTED,
    ERROR_RESPONSE_FAILED,
    ERROR_STATE_SHIFT,
    ERROR_SUBMIT_REJECTED,
    MANIFEST_CHR_IS_RAM_SHIFT,
    MANIFEST_MAPPER_MASK,
    MANIFEST_MAPPER_SHIFT,
    MANIFEST_MIRRORING_MASK,
    MANIFEST_MIRRORING_SHIFT,
    MANIFEST_VALID_SHIFT,
    MMIO_CAPABILITIES,
    MMIO_MAGIC,
    MMIO_SPAN_BYTES,
    MMIO_VERSION,
    REG_ADDRESS,
    REG_CAPABILITIES,
    REG_COMMAND,
    REG_COMPLETED_COUNT,
    REG_CONTROL,
    REG_ERROR,
    REG_MAGIC,
    REG_MANIFEST,
    REG_MANIFEST_CHR_BYTES,
    REG_MANIFEST_PRG_BYTES,
    REG_STATUS,
    REG_TARGET,
    REG_VERSION,
    REG_WRITE_DATA,
    STATUS_ACTIVATION_IN_PROGRESS,
    STATUS_BRIDGE_READY,
    STATUS_COMMAND_PENDING,
    STATUS_IMAGE_VALID,
    STATUS_LOADER_BUSY,
    STATUS_LOADER_ERROR,
    STATUS_LOADER_READY,
    STATUS_NES_HELD_RESET,
    STATUS_RUNTIME_ACTIVE,
    STATUS_STATE_SHIFT,
    STATUS_SUBMIT_REJECTED,
)
from software.nes_loader.protocol import (
    Command,
    LoaderCommand,
    LoaderErrorCode,
    LoaderState,
    Manifest,
    Mirroring,
    Target,
)
from software.nes_loader.transport import (
    MockRuntimeLoaderTransport,
    TransportProtocolError,
)


class SimulatedRuntimeLoaderMmio(FakeMmio):
    """Register-accurate MMIO front end backed by the loader reference model."""

    def __init__(
        self,
        *,
        magic: int = MMIO_MAGIC,
        version: int = MMIO_VERSION,
        capabilities: int = MMIO_CAPABILITIES,
        command_delay_reads: int = 0,
        validation_delay_polls: int = 0,
        activation_delay_polls: int = 0,
    ) -> None:
        if command_delay_reads < 0:
            raise ValueError("command_delay_reads must be non-negative")
        super().__init__(
            MMIO_SPAN_BYTES,
            read_hook=self._read_register,
            write_hook=self._write_register,
        )
        self.words[REG_MAGIC // 4] = magic
        self.words[REG_VERSION // 4] = version
        self.words[REG_CAPABILITIES // 4] = capabilities
        self.command_delay_reads = command_delay_reads
        self.endpoint = MockRuntimeLoaderTransport(
            validation_delay_polls=validation_delay_polls,
            activation_delay_polls=activation_delay_polls,
        )
        self.pending: LoaderCommand | None = None
        self.pending_reads = 0
        self.completed_count = 0
        self.last_response_error = False
        self.last_response_code = LoaderErrorCode.NONE
        self.last_response_state = LoaderState.IDLE
        self.submit_rejected = False
        self.submissions = 0

    def _decode_manifest(self) -> Manifest | None:
        word = self.words[REG_MANIFEST // 4]
        if not (word & (1 << MANIFEST_VALID_SHIFT)):
            return None
        mapper = (word & MANIFEST_MAPPER_MASK) >> MANIFEST_MAPPER_SHIFT
        mirroring_value = (
            word & MANIFEST_MIRRORING_MASK
        ) >> MANIFEST_MIRRORING_SHIFT
        try:
            mirroring = Mirroring(mirroring_value)
        except ValueError:
            mirroring = mirroring_value  # type: ignore[assignment]
        return Manifest(
            mapper=mapper,
            prg_bytes=self.words[REG_MANIFEST_PRG_BYTES // 4] & 0xFFFF,
            chr_bytes=self.words[REG_MANIFEST_CHR_BYTES // 4] & 0xFFFF,
            chr_is_ram=bool(word & (1 << MANIFEST_CHR_IS_RAM_SHIFT)),
            mirroring=mirroring,
        )

    def _decode_command(self, value: int) -> LoaderCommand:
        command = Command(value & 0x3)
        target = Target(self.words[REG_TARGET // 4] & 0x3)
        address = self.words[REG_ADDRESS // 4] & 0xFFFF
        data = self.words[REG_WRITE_DATA // 4] & 0xFF
        manifest = self._decode_manifest() if command is Command.BEGIN else None
        return LoaderCommand(command, target, address, data, manifest)

    def _write_register(self, offset: int, value: int) -> None:
        if offset == REG_CONTROL:
            if value & CONTROL_CLEAR_SUBMIT_REJECTED:
                self.submit_rejected = False
            return
        if offset != REG_COMMAND:
            return
        if self.pending is not None or value & ~0x3:
            self.submit_rejected = True
            return
        self.pending = self._decode_command(value)
        self.pending_reads = self.command_delay_reads
        self.submissions += 1

    def _complete_pending(self) -> None:
        if self.pending is None:
            return
        if self.pending_reads:
            self.pending_reads -= 1
            return
        command = self.pending
        self.pending = None
        self.last_response_error = False
        self.last_response_code = LoaderErrorCode.NONE
        try:
            self.endpoint.send(command, timeout_s=1.0)
        except TransportProtocolError:
            status = self.endpoint.read_status()
            self.last_response_error = True
            self.last_response_code = status.error_code
        self.last_response_state = self.endpoint.read_status().state
        self.completed_count = (self.completed_count + 1) & 0xFFFFFFFF

    def _status_word(self) -> int:
        status = self.endpoint.read_status()
        word = int(status.state) << STATUS_STATE_SHIFT
        if self.pending is None and not self.submit_rejected:
            word |= STATUS_BRIDGE_READY
        if self.pending is not None:
            word |= STATUS_COMMAND_PENDING
        if status.state.name == "LOADING":
            word |= STATUS_LOADER_BUSY
        word |= STATUS_LOADER_READY
        if status.image_valid:
            word |= STATUS_IMAGE_VALID
        if status.runtime_active:
            word |= STATUS_RUNTIME_ACTIVE
        if status.nes_hold_reset:
            word |= STATUS_NES_HELD_RESET
        if status.state.name == "ERROR":
            word |= STATUS_LOADER_ERROR
        if status.activation_in_progress:
            word |= STATUS_ACTIVATION_IN_PROGRESS
        if self.submit_rejected:
            word |= STATUS_SUBMIT_REJECTED
        return word

    def _read_register(self, offset: int, value: int) -> int:
        if offset == REG_STATUS:
            self._complete_pending()
            self.endpoint._advance_status()
            return self._status_word()
        if offset == REG_COMPLETED_COUNT:
            return self.completed_count
        if offset == REG_ERROR:
            return (
                int(self.last_response_code)
                | (int(self.submit_rejected) * ERROR_SUBMIT_REJECTED)
                | (int(self.last_response_error) * ERROR_RESPONSE_FAILED)
                | (int(self.last_response_state) << ERROR_STATE_SHIFT)
            )
        return value
