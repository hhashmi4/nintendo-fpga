"""Architectural debugger contract; events describe completed CPU operations.

This model does not use RTL execution-state numbers or scheduler phases.
Interrupt entry is not an instruction retirement. Frame completion requires
both crossing the next source boundary and reaching a safe CPU/DMA boundary.
"""
from dataclasses import dataclass
from enum import IntEnum


class State(IntEnum):
    RUNNING = 0
    PAUSE_PENDING = 1
    PAUSED = 2
    STEP_I = 3
    STEP_F = 4


@dataclass
class Debugger:
    state: State = State.RUNNING
    sequence: int = 0
    last_command: int = 0
    result: int = 0
    instruction_steps: int = 0
    frame_steps: int = 0
    frame_crossed: bool = False
    retired: bool = False
    overrun: int = 0
    before: int = 0
    after: int = 0
    boundary: int = 0

    def submit(self, command: int, sequence: int, pc: int = 0) -> tuple[int, int]:
        self.sequence = sequence & 0xFFFF
        if command not in range(4):
            result = 3
        elif self.state not in (State.RUNNING, State.PAUSED):
            result = 2
        elif command >= 2 and self.state != State.PAUSED:
            result = 1
        else:
            result = 0
            self.last_command = command
            if command == 0:
                self.state = State.RUNNING
            elif command == 1 and self.state == State.RUNNING:
                self.state = State.PAUSE_PENDING
            elif command >= 2:
                self.state = State.STEP_I if command == 2 else State.STEP_F
                self.before = pc
                self.boundary = 0
                self.retired = False
                self.frame_crossed = False
                if command == 3:
                    self.overrun = 0
        self.result = result
        return self.state, result

    def advance(self, *, safe: bool, retired: bool = False,
                frame: bool = False, ppu_tick: bool = False, pc: int = 0) -> None:
        if self.state == State.STEP_I:
            self.retired |= retired
        if self.state == State.STEP_F:
            if self.frame_crossed and ppu_tick:
                self.overrun = (self.overrun + 1) & 0xFFFF
            self.frame_crossed |= frame
        reason = {State.PAUSE_PENDING: 1, State.STEP_I: 2, State.STEP_F: 3}
        finished = (self.state == State.PAUSE_PENDING or
                    self.state == State.STEP_I and self.retired or
                    self.state == State.STEP_F and self.frame_crossed)
        if safe and finished:
            self.boundary = reason[self.state]
            self.instruction_steps = (self.instruction_steps +
                                      (self.state == State.STEP_I)) & 0xFFFF
            self.frame_steps = (self.frame_steps +
                                (self.state == State.STEP_F)) & 0xFFFF
            self.after = pc
            self.state = State.PAUSED


@dataclass
class TokenSource:
    """Producer-side token acceptance; held valid must not repeat a request."""
    armed: bool = False
    sequence: int = 0

    def sample(self, valid: bool, ready: bool, command: int):
        if not valid:
            self.armed = True
        elif ready and self.armed:
            self.armed = False
            self.sequence = (self.sequence + 1) & 0xFFFF
            return command, self.sequence
        return None
