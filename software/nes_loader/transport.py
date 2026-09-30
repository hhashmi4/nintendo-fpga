"""Physical-transport-neutral loader interface and deterministic mock."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
import time

from .mmio import RawMmio
from .mmio_registers import (
    CONTROL_CLEAR_SUBMIT_REJECTED,
    ERROR_CODE_MASK,
    ERROR_CODE_SHIFT,
    ERROR_RESPONSE_FAILED,
    ERROR_SUBMIT_REJECTED,
    MANIFEST_CHR_IS_RAM_SHIFT,
    MANIFEST_MAPPER_SHIFT,
    MANIFEST_MIRRORING_SHIFT,
    MANIFEST_VALID_SHIFT,
    MMIO_CAPABILITIES,
    MMIO_MAGIC,
    MMIO_VERSION_MAJOR,
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
    STATUS_LOADER_ERROR,
    STATUS_NES_HELD_RESET,
    STATUS_RUNTIME_ACTIVE,
    STATUS_STATE_MASK,
    STATUS_STATE_SHIFT,
    STATUS_SUBMIT_REJECTED,
)

from .protocol import (
    CHR_LAST_ADDRESS,
    PRG_LAST_ADDRESS,
    Command,
    LoaderCommand,
    LoaderErrorCode,
    LoaderState,
    Manifest,
    RuntimeStatus,
    Target,
    manifest_error,
)


class TransportError(RuntimeError):
    """A command or status operation failed."""


class TransportTimeout(TransportError):
    """A bounded command/status wait expired."""


class TransportProtocolError(TransportError):
    """The endpoint reported a Phase 4F protocol error."""


class TransportIdentityError(TransportError):
    """The mapped endpoint is absent or contract-incompatible."""


class RuntimeLoaderTransport(ABC):
    """Logical interface that Phase 4F-F can implement over a real bridge."""

    @abstractmethod
    def send(self, command: LoaderCommand, *, timeout_s: float) -> None:
        """Hold one command stable until accepted or the timeout expires."""

    @abstractmethod
    def read_status(self) -> RuntimeStatus:
        """Return one coherent snapshot of the software-visible status."""

    @abstractmethod
    def wait_for_image_valid(self, *, timeout_s: float) -> RuntimeStatus:
        """Wait for staged validity, a loader error, or timeout."""

    @abstractmethod
    def wait_for_active(self, *, timeout_s: float) -> RuntimeStatus:
        """Wait for active runtime execution/reset release or timeout."""


class MmioRuntimeLoaderTransport(RuntimeLoaderTransport):
    """Production Phase 4F-F transport over the versioned MMIO register bank."""

    def __init__(
        self,
        mmio: RawMmio,
        *,
        poll_interval_s: float = 0.0001,
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if poll_interval_s <= 0:
            raise ValueError("poll_interval_s must be positive")
        self.mmio = mmio
        self.poll_interval_s = poll_interval_s
        self._monotonic = monotonic
        self._sleep = sleep
        self._verify_identity()

    def _verify_identity(self) -> None:
        magic = self.mmio.read32(REG_MAGIC)
        if magic != MMIO_MAGIC:
            raise TransportIdentityError(
                f"FPGA loader bridge magic mismatch: expected 0x{MMIO_MAGIC:08x}, "
                f"read 0x{magic:08x}"
            )
        version = self.mmio.read32(REG_VERSION)
        major = version >> 16
        if major != MMIO_VERSION_MAJOR:
            raise TransportIdentityError(
                f"FPGA loader bridge major version {major} is incompatible with "
                f"software major version {MMIO_VERSION_MAJOR}"
            )
        capabilities = self.mmio.read32(REG_CAPABILITIES)
        missing = MMIO_CAPABILITIES & ~capabilities
        if missing:
            raise TransportIdentityError(
                f"FPGA loader bridge lacks required capabilities 0x{missing:08x}"
            )

    def _validate_timeout(self, timeout_s: float) -> float:
        if timeout_s < 0:
            raise ValueError("timeouts must be non-negative")
        return self._monotonic() + timeout_s

    def _pause(self, deadline: float) -> None:
        remaining = deadline - self._monotonic()
        if remaining > 0:
            self._sleep(min(self.poll_interval_s, remaining))

    @staticmethod
    def _error_message(stage: str, code: LoaderErrorCode) -> str:
        label = code.name.lower().replace("_", " ")
        return f"FPGA rejected {stage}: {label} ({code.name}, error {int(code)})"

    def _read_error(self) -> tuple[LoaderErrorCode, bool, bool]:
        word = self.mmio.read32(REG_ERROR)
        value = (word & ERROR_CODE_MASK) >> ERROR_CODE_SHIFT
        try:
            code = LoaderErrorCode(value)
        except ValueError as error:
            raise TransportProtocolError(
                f"FPGA loader bridge returned unknown error code {value}"
            ) from error
        return code, bool(word & ERROR_RESPONSE_FAILED), bool(
            word & ERROR_SUBMIT_REJECTED
        )

    def _wait_ready(self, command: LoaderCommand, deadline: float) -> None:
        while True:
            word = self.mmio.read32(REG_STATUS)
            if word & STATUS_SUBMIT_REJECTED:
                self.mmio.write32(REG_CONTROL, CONTROL_CLEAR_SUBMIT_REJECTED)
                raise TransportProtocolError(
                    "FPGA loader bridge rejected an MMIO command submission"
                )
            if word & STATUS_BRIDGE_READY:
                return
            if word & STATUS_LOADER_ERROR and command.command is not Command.BEGIN:
                code, _failed, _rejected = self._read_error()
                raise TransportProtocolError(self._error_message(command.stage, code))
            if self._monotonic() >= deadline:
                raise TransportTimeout(f"{command.stage} command readiness timed out")
            self._pause(deadline)

    @staticmethod
    def _manifest_word(manifest: Manifest) -> int:
        return (
            (1 << MANIFEST_VALID_SHIFT)
            | (int(manifest.chr_is_ram) << MANIFEST_CHR_IS_RAM_SHIFT)
            | (int(manifest.mirroring) << MANIFEST_MIRRORING_SHIFT)
            | (manifest.mapper << MANIFEST_MAPPER_SHIFT)
        )

    def send(self, command: LoaderCommand, *, timeout_s: float) -> None:
        deadline = self._validate_timeout(timeout_s)
        self._wait_ready(command, deadline)

        self.mmio.write32(REG_TARGET, int(command.target))
        self.mmio.write32(REG_ADDRESS, command.address & 0xFFFF)
        self.mmio.write32(REG_WRITE_DATA, command.data & 0xFF)
        if command.command is Command.BEGIN:
            if command.manifest is None:
                raise TransportProtocolError("BEGIN requires a manifest")
            self.mmio.write32(REG_MANIFEST, self._manifest_word(command.manifest))
            self.mmio.write32(REG_MANIFEST_PRG_BYTES, command.manifest.prg_bytes)
            self.mmio.write32(REG_MANIFEST_CHR_BYTES, command.manifest.chr_bytes)

        before = self.mmio.read32(REG_COMPLETED_COUNT)
        self.mmio.write32(REG_COMMAND, int(command.command))
        while True:
            status_word = self.mmio.read32(REG_STATUS)
            if status_word & STATUS_SUBMIT_REJECTED:
                self.mmio.write32(REG_CONTROL, CONTROL_CLEAR_SUBMIT_REJECTED)
                raise TransportProtocolError(
                    f"FPGA loader bridge rejected {command.stage} submission"
                )
            completed = self.mmio.read32(REG_COMPLETED_COUNT)
            if completed != before and not (status_word & STATUS_COMMAND_PENDING):
                break
            if self._monotonic() >= deadline:
                raise TransportTimeout(f"{command.stage} command acceptance timed out")
            self._pause(deadline)

        code, failed, rejected = self._read_error()
        if rejected:
            self.mmio.write32(REG_CONTROL, CONTROL_CLEAR_SUBMIT_REJECTED)
            raise TransportProtocolError(
                f"FPGA loader bridge rejected {command.stage} submission"
            )
        if failed:
            raise TransportProtocolError(self._error_message(command.stage, code))

    def read_status(self) -> RuntimeStatus:
        word = self.mmio.read32(REG_STATUS)
        state_value = (word & STATUS_STATE_MASK) >> STATUS_STATE_SHIFT
        try:
            state = LoaderState(state_value)
        except ValueError as error:
            raise TransportProtocolError(
                f"FPGA loader bridge returned unknown loader state {state_value}"
            ) from error
        code, _failed, rejected = self._read_error()
        if rejected or word & STATUS_SUBMIT_REJECTED:
            self.mmio.write32(REG_CONTROL, CONTROL_CLEAR_SUBMIT_REJECTED)
            raise TransportProtocolError(
                "FPGA loader bridge reports a rejected MMIO submission"
            )
        return RuntimeStatus(
            state=state,
            error_code=code,
            image_valid=bool(word & STATUS_IMAGE_VALID),
            runtime_active=bool(word & STATUS_RUNTIME_ACTIVE),
            activation_in_progress=bool(word & STATUS_ACTIVATION_IN_PROGRESS),
            nes_hold_reset=bool(word & STATUS_NES_HELD_RESET),
        )

    def _wait(
        self,
        predicate: Callable[[RuntimeStatus], bool],
        timeout_s: float,
        stage: str,
    ) -> RuntimeStatus:
        deadline = self._validate_timeout(timeout_s)
        while True:
            status = self.read_status()
            if status.state is LoaderState.ERROR:
                raise TransportProtocolError(
                    f"FPGA reported {stage} error: "
                    f"{status.error_code.name.lower().replace('_', ' ')} "
                    f"({status.error_code.name}, error {int(status.error_code)})"
                )
            if predicate(status):
                return status
            if self._monotonic() >= deadline:
                raise TransportTimeout(f"{stage} timed out")
            self._pause(deadline)

    def wait_for_image_valid(self, *, timeout_s: float) -> RuntimeStatus:
        return self._wait(
            lambda status: status.image_valid,
            timeout_s,
            "image validation",
        )

    def wait_for_active(self, *, timeout_s: float) -> RuntimeStatus:
        return self._wait(
            lambda status: (
                status.runtime_active
                and not status.activation_in_progress
                and not status.nes_hold_reset
            ),
            timeout_s,
            "activation",
        )


DelayFunction = Callable[[int, LoaderCommand], int]


class MockRuntimeLoaderTransport(RuntimeLoaderTransport):
    """Deterministic behavioral endpoint enforcing the merged FPGA contract.

    Poll counts model ready/status latency without sleeping, making timeout and
    backpressure tests fast and repeatable.
    """

    def __init__(
        self,
        *,
        poll_interval_s: float = 0.001,
        command_delay_polls: int | DelayFunction = 0,
        validation_delay_polls: int = 0,
        activation_delay_polls: int = 4,
        fail_at_command: int | None = None,
        validation_error: LoaderErrorCode | None = None,
    ) -> None:
        if poll_interval_s <= 0:
            raise ValueError("poll_interval_s must be positive")
        for name, value in (
            ("validation_delay_polls", validation_delay_polls),
            ("activation_delay_polls", activation_delay_polls),
        ):
            if value < 0:
                raise ValueError(f"{name} must be non-negative")
        if isinstance(command_delay_polls, int) and command_delay_polls < 0:
            raise ValueError("command_delay_polls must be non-negative")
        if validation_error is LoaderErrorCode.NONE:
            validation_error = None

        self.poll_interval_s = poll_interval_s
        self.command_delay_polls = command_delay_polls
        self.validation_delay_polls = validation_delay_polls
        self.activation_delay_polls = activation_delay_polls
        self.fail_at_command = fail_at_command
        self.validation_error = validation_error

        self.commands: list[LoaderCommand] = []
        self.image_valid_waits = 0
        self.active_waits = 0
        self.prg = bytearray()
        self.chr = bytearray()
        self._state = LoaderState.IDLE
        self._error = LoaderErrorCode.NONE
        self._staged_manifest: Manifest | None = None
        self._active_manifest: Manifest | None = None
        self._next_prg_address = 0
        self._next_chr_address = 0
        self._image_valid = False
        self._runtime_active = False
        self._activation_in_progress = False
        self._hold_reset = False
        self._validation_polls_remaining: int | None = None
        self._activation_polls_remaining: int | None = None

    def _poll_budget(self, timeout_s: float) -> int:
        if timeout_s < 0:
            raise ValueError("timeouts must be non-negative")
        return int(timeout_s / self.poll_interval_s)

    def _command_delay(self, index: int, command: LoaderCommand) -> int:
        delay = self.command_delay_polls
        polls = delay(index, command) if callable(delay) else delay
        if polls < 0:
            raise ValueError("command delay function returned a negative value")
        return polls

    def send(self, command: LoaderCommand, *, timeout_s: float) -> None:
        index = len(self.commands)
        if self.fail_at_command == index:
            raise TransportError(
                f"simulated transport failure before {command.stage} acceptance"
            )
        delay = self._command_delay(index, command)
        if delay > self._poll_budget(timeout_s):
            raise TransportTimeout(f"{command.stage} command acceptance timed out")
        for _ in range(delay):
            self._advance_status()

        self.commands.append(command)
        self._accept(command)
        if self._state is LoaderState.ERROR:
            raise TransportProtocolError(
                f"FPGA rejected {command.stage}: {self._error.name} "
                f"(error {int(self._error)})"
            )

    def read_status(self) -> RuntimeStatus:
        return RuntimeStatus(
            state=self._state,
            error_code=self._error,
            image_valid=self._image_valid,
            runtime_active=self._runtime_active,
            activation_in_progress=self._activation_in_progress,
            nes_hold_reset=self._hold_reset,
            staged_manifest=self._staged_manifest,
            active_manifest=self._active_manifest,
        )

    def wait_for_image_valid(self, *, timeout_s: float) -> RuntimeStatus:
        self.image_valid_waits += 1
        return self._wait(
            lambda status: status.image_valid,
            timeout_s,
            "image validation",
        )

    def wait_for_active(self, *, timeout_s: float) -> RuntimeStatus:
        self.active_waits += 1
        return self._wait(
            lambda status: (
                status.runtime_active
                and not status.activation_in_progress
                and not status.nes_hold_reset
            ),
            timeout_s,
            "activation",
        )

    def _wait(
        self,
        predicate: Callable[[RuntimeStatus], bool],
        timeout_s: float,
        stage: str,
    ) -> RuntimeStatus:
        budget = self._poll_budget(timeout_s)
        for poll in range(budget + 1):
            status = self.read_status()
            if status.state is LoaderState.ERROR:
                raise TransportProtocolError(
                    f"FPGA reported {stage} error: {status.error_code.name} "
                    f"(error {int(status.error_code)})"
                )
            if predicate(status):
                return status
            if poll < budget:
                self._advance_status()
        raise TransportTimeout(f"{stage} timed out")

    def _set_error(self, error: LoaderErrorCode) -> None:
        self._state = LoaderState.ERROR
        self._error = error
        self._image_valid = False
        self._validation_polls_remaining = None

    def _accept(self, item: LoaderCommand) -> None:
        if self._state is LoaderState.ERROR and item.command is not Command.BEGIN:
            return
        if item.command is Command.BEGIN:
            self._begin(item)
        elif item.command is Command.WRITE:
            self._write(item)
        elif item.command is Command.COMMIT:
            self._commit(item)
        elif item.command is Command.ACTIVATE:
            self._activate(item)
        else:
            self._set_error(LoaderErrorCode.BAD_COMMAND)

    def _canonical_nonwrite(self, item: LoaderCommand) -> bool:
        return item.target is Target.NONE and item.address == 0 and item.data == 0

    def _begin(self, item: LoaderCommand) -> None:
        if self._state is LoaderState.LOADING:
            self._set_error(LoaderErrorCode.BEGIN_BUSY)
            return

        self._hold_reset = True
        self._image_valid = False
        self._staged_manifest = None
        self._next_prg_address = 0
        self._next_chr_address = 0
        self._validation_polls_remaining = None
        self.prg = bytearray()
        self.chr = bytearray()
        if item.manifest is None or not self._canonical_nonwrite(item):
            self._set_error(LoaderErrorCode.INVALID_MANIFEST)
            return
        error = manifest_error(item.manifest)
        if error is not LoaderErrorCode.NONE:
            self._set_error(error)
            return
        self._staged_manifest = item.manifest
        self._state = LoaderState.LOADING
        self._error = LoaderErrorCode.NONE

    def _write(self, item: LoaderCommand) -> None:
        if self._state is not LoaderState.LOADING:
            self._set_error(LoaderErrorCode.WRONG_STATE)
            return
        if item.target not in (Target.PRG, Target.CHR):
            self._set_error(LoaderErrorCode.BAD_TARGET)
            return
        physical_last = (
            PRG_LAST_ADDRESS if item.target is Target.PRG else CHR_LAST_ADDRESS
        )
        if item.address < 0 or item.address > physical_last:
            self._set_error(LoaderErrorCode.BAD_ADDRESS)
            return
        manifest = self._staged_manifest
        if manifest is None:
            self._set_error(LoaderErrorCode.INVALID_MANIFEST)
            return
        if item.target is Target.PRG:
            expected = self._next_prg_address
            declared_size = manifest.prg_bytes
            destination = self.prg
        else:
            if manifest.chr_is_ram:
                self._set_error(LoaderErrorCode.BAD_TARGET)
                return
            expected = self._next_chr_address
            declared_size = manifest.chr_bytes
            destination = self.chr
        if item.address >= declared_size:
            self._set_error(LoaderErrorCode.BAD_ADDRESS)
            return
        if item.address != expected:
            self._set_error(LoaderErrorCode.UNEXPECTED_ADDRESS)
            return
        destination.append(item.data & 0xFF)
        if item.target is Target.PRG:
            self._next_prg_address += 1
        else:
            self._next_chr_address += 1

    def _commit(self, item: LoaderCommand) -> None:
        if self._state is not LoaderState.LOADING:
            self._set_error(LoaderErrorCode.WRONG_STATE)
            return
        manifest = self._staged_manifest
        if manifest is None:
            self._set_error(LoaderErrorCode.INVALID_MANIFEST)
        elif self._next_prg_address != manifest.prg_bytes:
            self._set_error(LoaderErrorCode.PRG_INCOMPLETE)
        elif self._next_chr_address != manifest.chr_bytes:
            self._set_error(LoaderErrorCode.CHR_INCOMPLETE)
        else:
            self._state = LoaderState.READY
            self._error = LoaderErrorCode.NONE
            self._validation_polls_remaining = self.validation_delay_polls
            if self.validation_delay_polls == 0:
                self._complete_validation()

    def _complete_validation(self) -> None:
        self._validation_polls_remaining = None
        if self.validation_error is not None:
            self._set_error(self.validation_error)
        else:
            self._image_valid = True

    def _activate(self, item: LoaderCommand) -> None:
        if (
            not self._canonical_nonwrite(item)
            or self._state is not LoaderState.READY
            or not self._image_valid
            or self._staged_manifest is None
        ):
            self._set_error(LoaderErrorCode.ACTIVATE_INVALID)
            return
        self._runtime_active = True
        self._active_manifest = self._staged_manifest
        self._activation_in_progress = True
        self._hold_reset = True
        self._activation_polls_remaining = self.activation_delay_polls
        if self.activation_delay_polls == 0:
            self._complete_activation()

    def _complete_activation(self) -> None:
        self._activation_polls_remaining = None
        self._activation_in_progress = False
        self._hold_reset = False

    def _advance_status(self) -> None:
        if self._validation_polls_remaining is not None:
            if self._validation_polls_remaining <= 1:
                self._complete_validation()
            else:
                self._validation_polls_remaining -= 1
        if self._activation_polls_remaining is not None:
            if self._activation_polls_remaining <= 1:
                self._complete_activation()
            else:
                self._activation_polls_remaining -= 1
