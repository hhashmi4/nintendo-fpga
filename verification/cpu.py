"""Independent reference model for the Phase 2A CPU architectural shell."""

from dataclasses import dataclass, replace
from enum import IntEnum


RESET_A = 0x00
RESET_X = 0x00
RESET_Y = 0x00
RESET_SP = 0xFD
RESET_PC = 0x0000
RESET_STATUS = 0x24
RESET_INSTRUCTION = 0x00


class ExecutionState(IntEnum):
    """Reserved execution-state encodings shared with the Phase 2A RTL."""

    RESET = 0
    FETCH = 1
    DECODE = 2
    EXECUTE = 3
    MEMORY = 4
    WRITEBACK = 5


@dataclass(frozen=True)
class CpuSnapshot:
    """All sequential state implemented by the Phase 2A shell."""

    a: int
    x: int
    y: int
    sp: int
    pc: int
    status: int
    instruction: int
    execution_state: ExecutionState


class CpuPhase2AModel:
    """Model reset, CPU-enable gating, and the placeholder fetch boundary."""

    def __init__(self) -> None:
        self._snapshot = self.reset_snapshot()

    @staticmethod
    def reset_snapshot() -> CpuSnapshot:
        return CpuSnapshot(
            a=RESET_A,
            x=RESET_X,
            y=RESET_Y,
            sp=RESET_SP,
            pc=RESET_PC,
            status=RESET_STATUS,
            instruction=RESET_INSTRUCTION,
            execution_state=ExecutionState.RESET,
        )

    @property
    def snapshot(self) -> CpuSnapshot:
        return self._snapshot

    def tick(self, *, reset: bool, cpu_enable: bool, read_data: int = 0) -> None:
        """Apply one fabric-clock edge using synchronous-reset semantics."""

        if not 0 <= read_data <= 0xFF:
            raise ValueError("read_data must be an 8-bit value")
        if reset:
            self._snapshot = self.reset_snapshot()
        elif cpu_enable and self._snapshot.execution_state is ExecutionState.RESET:
            self._snapshot = replace(
                self._snapshot, execution_state=ExecutionState.FETCH
            )
        elif cpu_enable and self._snapshot.execution_state is ExecutionState.FETCH:
            self._snapshot = replace(self._snapshot, instruction=read_data)

    def bus_outputs(self, *, reset: bool) -> tuple[int, int, bool, bool]:
        """Return address, write data, write-enable, and cycle-valid."""

        address = RESET_PC if reset else self._snapshot.pc
        valid = not reset and self._snapshot.execution_state is ExecutionState.FETCH
        return address, 0x00, False, valid
