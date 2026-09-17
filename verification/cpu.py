"""Independent reference models for the Phase 2A shell and Phase 2B ALU."""

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


class AluOperation(IntEnum):
    """Operation encodings used by the reusable Phase 2B ALU."""

    ADD = 0
    SUB = 1
    AND = 2
    OR = 3
    XOR = 4
    ASL = 5
    LSR = 6
    ROL = 7
    ROR = 8
    INC = 9
    DEC = 10
    CMP = 11


@dataclass(frozen=True)
class AluResult:
    """ALU values plus explicit result/flag ownership information."""

    result: int
    result_valid: bool
    negative: bool
    overflow: bool
    zero: bool
    carry: bool
    n_valid: bool
    v_valid: bool
    z_valid: bool
    c_valid: bool


def _signed_byte(value: int) -> int:
    return value if value < 0x80 else value - 0x100


def evaluate_alu(
    operation: AluOperation,
    operand_a: int,
    operand_b: int = 0,
    carry_in: int | bool = False,
) -> AluResult:
    """Evaluate binary 2A03 ALU behavior without any decimal adjustment."""

    if not isinstance(operation, AluOperation):
        raise ValueError("operation must be an AluOperation")
    if not 0 <= operand_a <= 0xFF:
        raise ValueError("operand_a must be an 8-bit value")
    if not 0 <= operand_b <= 0xFF:
        raise ValueError("operand_b must be an 8-bit value")
    if carry_in not in (False, True, 0, 1):
        raise ValueError("carry_in must be zero or one")

    carry_value = int(carry_in)
    result_valid = operation is not AluOperation.CMP
    n_valid = True
    v_valid = operation in (AluOperation.ADD, AluOperation.SUB)
    z_valid = True
    c_valid = operation in (
        AluOperation.ADD,
        AluOperation.SUB,
        AluOperation.ASL,
        AluOperation.LSR,
        AluOperation.ROL,
        AluOperation.ROR,
        AluOperation.CMP,
    )
    overflow = False
    carry = False

    if operation is AluOperation.ADD:
        mathematical_result = operand_a + operand_b + carry_value
        result = mathematical_result & 0xFF
        carry = mathematical_result > 0xFF
        signed_result = (
            _signed_byte(operand_a) + _signed_byte(operand_b) + carry_value
        )
        overflow = not -128 <= signed_result <= 127
    elif operation is AluOperation.SUB:
        borrow = 1 - carry_value
        mathematical_result = operand_a - operand_b - borrow
        result = mathematical_result & 0xFF
        carry = mathematical_result >= 0
        signed_result = (
            _signed_byte(operand_a) - _signed_byte(operand_b) - borrow
        )
        overflow = not -128 <= signed_result <= 127
    elif operation is AluOperation.AND:
        result = operand_a & operand_b
    elif operation is AluOperation.OR:
        result = operand_a | operand_b
    elif operation is AluOperation.XOR:
        result = operand_a ^ operand_b
    elif operation is AluOperation.ASL:
        result = (operand_a << 1) & 0xFF
        carry = bool(operand_a & 0x80)
    elif operation is AluOperation.LSR:
        result = operand_a >> 1
        carry = bool(operand_a & 0x01)
    elif operation is AluOperation.ROL:
        result = ((operand_a << 1) | carry_value) & 0xFF
        carry = bool(operand_a & 0x80)
    elif operation is AluOperation.ROR:
        result = (operand_a >> 1) | (carry_value << 7)
        carry = bool(operand_a & 0x01)
    elif operation is AluOperation.INC:
        result = (operand_a + 1) & 0xFF
    elif operation is AluOperation.DEC:
        result = (operand_a - 1) & 0xFF
    else:
        result = (operand_a - operand_b) & 0xFF
        carry = operand_a >= operand_b

    return AluResult(
        result=result,
        result_valid=result_valid,
        negative=bool(result & 0x80),
        overflow=overflow,
        zero=result == 0,
        carry=carry,
        n_valid=n_valid,
        v_valid=v_valid,
        z_valid=z_valid,
        c_valid=c_valid,
    )


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
