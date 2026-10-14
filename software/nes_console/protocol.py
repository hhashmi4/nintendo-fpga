"""Console v1.0 wire contract, separate from loader v1.0/diagnostic v1.3."""

from dataclasses import dataclass
from enum import IntEnum

PHYSICAL_BASE = 0xFF202000
SPAN_BYTES = 32
MAGIC = 0x4E455343
VERSION = 0x00010000
REG_MAGIC, REG_VERSION, REG_CAPABILITIES, REG_BRIDGE = range(0, 16, 4)
REG_COMMAND, REG_RESPONSE, REG_RESULT, REG_COMPLETED = range(16, 32, 4)


class State(IntEnum):
    INITIALIZING = 0
    MENU = 1
    LOADING = 2
    STARTING = 3
    GAME = 4
    RETURNING = 5
    ERROR = 6
    DEVELOPER = 7


class Source(IntEnum):
    SYSTEM = 0
    GAME = 1
    DEVELOPER = 2


class Command(IntEnum):
    STATUS = 0
    MENU = 1
    LAUNCH = 2
    DEVELOPER = 3
    PREPARE_LOAD = 4
    REPORT_ERROR = 5


class Result(IntEnum):
    OK = 0
    STALE = 1
    INVALID = 2
    UNAVAILABLE = 3


@dataclass(frozen=True)
class Status:
    state: State
    input_owner: Source
    video_source: Source
    game_available: bool
    runtime_active: bool
    loader_state: int
    error: int
    epoch: int

    @classmethod
    def decode(cls, word: int) -> "Status":
        return cls(State(word & 15), Source((word >> 4) & 3),
                   Source((word >> 6) & 3), bool(word & 256),
                   bool(word & 512), (word >> 10) & 3,
                   (word >> 12) & 15, (word >> 16) & 65535)


def request_word(command: Command, epoch: int) -> int:
    if not isinstance(command, Command):
        raise ValueError("command must be a Command")
    if not 0 <= epoch <= 65535:
        raise ValueError("epoch must fit 16 bits")
    return epoch << 16 | command


def allowed(command: Command, state: State) -> bool:
    """Software precondition only; the FPGA must independently arbitrate."""
    if command in (Command.STATUS, Command.MENU, Command.DEVELOPER,
                   Command.REPORT_ERROR):
        return True
    if command == Command.PREPARE_LOAD:
        return state in (State.MENU, State.ERROR, State.DEVELOPER)
    return command == Command.LAUNCH and state in (State.MENU, State.DEVELOPER)
