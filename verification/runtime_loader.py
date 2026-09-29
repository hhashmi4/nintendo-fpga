"""Independent Phase 4F-A runtime-loader protocol reference model."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum


class Command(IntEnum):
    BEGIN = 0
    WRITE = 1
    COMMIT = 2
    RESERVED = 3


class Target(IntEnum):
    NONE = 0
    PRG = 1
    CHR = 2
    RESERVED = 3


class State(IntEnum):
    IDLE = 0
    LOADING = 1
    READY = 2
    ERROR = 3


class Error(IntEnum):
    NONE = 0
    WRONG_STATE = 1
    BEGIN_BUSY = 2
    BAD_COMMAND = 3
    BAD_TARGET = 4
    BAD_ADDRESS = 5
    EMPTY_LOAD = 6


PRG_LAST_ADDRESS = 0x7FFF
CHR_LAST_ADDRESS = 0x1FFF


def legal_address(target: int, address: int) -> bool:
    address &= 0xFFFF
    if target == Target.PRG:
        return address <= PRG_LAST_ADDRESS
    if target == Target.CHR:
        return address <= CHR_LAST_ADDRESS
    return False


@dataclass(frozen=True)
class Outputs:
    command_ready: bool
    command_accepted: bool
    write_valid: bool
    write_target: int
    write_address: int
    write_data: int
    state: State
    busy: bool
    completed: bool
    error: bool
    error_code: Error
    nes_hold_reset: bool


@dataclass
class RuntimeLoader:
    state: State = State.IDLE
    error_code: Error = Error.NONE
    write_seen: bool = False

    def reset(self) -> None:
        self.state = State.IDLE
        self.error_code = Error.NONE
        self.write_seen = False

    def evaluate(
        self,
        *,
        reset: bool = False,
        valid: bool = False,
        command: int = Command.BEGIN,
        target: int = Target.NONE,
        address: int = 0,
        data: int = 0,
        storage_ready: bool = False,
    ) -> Outputs:
        legal_write = (
            not reset
            and valid
            and command == Command.WRITE
            and self.state == State.LOADING
            and target in (Target.PRG, Target.CHR)
            and legal_address(target, address)
        )
        command_ready = not reset and (not legal_write or storage_ready)
        visible_state = State.IDLE if reset else self.state
        return Outputs(
            command_ready=command_ready,
            command_accepted=valid and command_ready,
            write_valid=legal_write,
            write_target=int(target),
            write_address=address & 0xFFFF,
            write_data=data & 0xFF,
            state=visible_state,
            busy=not reset and self.state == State.LOADING,
            completed=not reset and self.state == State.READY,
            error=not reset and self.state == State.ERROR,
            error_code=Error.NONE if reset else self.error_code,
            nes_hold_reset=reset or self.state != State.READY,
        )

    def clock(self, **inputs: int | bool) -> Outputs:
        outputs = self.evaluate(**inputs)
        if inputs.get("reset", False):
            self.reset()
            return outputs
        if not outputs.command_accepted:
            return outputs

        command = int(inputs.get("command", Command.BEGIN))
        target = int(inputs.get("target", Target.NONE))
        address = int(inputs.get("address", 0)) & 0xFFFF

        if self.state == State.ERROR and command != Command.BEGIN:
            return outputs
        if command == Command.BEGIN:
            if self.state == State.LOADING:
                self.state = State.ERROR
                self.error_code = Error.BEGIN_BUSY
            else:
                self.state = State.LOADING
                self.error_code = Error.NONE
                self.write_seen = False
        elif command == Command.WRITE:
            if self.state != State.LOADING:
                self.state = State.ERROR
                self.error_code = Error.WRONG_STATE
            elif target not in (Target.PRG, Target.CHR):
                self.state = State.ERROR
                self.error_code = Error.BAD_TARGET
            elif not legal_address(target, address):
                self.state = State.ERROR
                self.error_code = Error.BAD_ADDRESS
            else:
                self.write_seen = True
        elif command == Command.COMMIT:
            if self.state != State.LOADING:
                self.state = State.ERROR
                self.error_code = Error.WRONG_STATE
            elif not self.write_seen:
                self.state = State.ERROR
                self.error_code = Error.EMPTY_LOAD
            else:
                self.state = State.READY
                self.error_code = Error.NONE
        else:
            self.state = State.ERROR
            self.error_code = Error.BAD_COMMAND
        return outputs
