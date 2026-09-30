"""Physical-transport-neutral loader interface and deterministic mock."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable

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
