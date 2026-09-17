"""Independent reference models for the Phase 2A, 2B, and 2C CPU blocks."""

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


class AddressingMode(IntEnum):
    """Opcode-independent addressing-mode encodings used by Phase 2C."""

    IMPLIED = 0
    ACCUMULATOR = 1
    IMMEDIATE = 2
    ZERO_PAGE = 3
    ZERO_PAGE_X = 4
    ZERO_PAGE_Y = 5
    ABSOLUTE = 6
    ABSOLUTE_X = 7
    ABSOLUTE_Y = 8
    INDIRECT = 9
    INDEXED_INDIRECT_X = 10
    INDIRECT_INDEXED_Y = 11
    RELATIVE = 12


@dataclass(frozen=True)
class AddressResult:
    """Address arithmetic results and explicit mode-specific validity."""

    effective_address: int = 0
    effective_address_valid: bool = False
    pointer_low_address: int = 0
    pointer_high_address: int = 0
    pointer_addresses_valid: bool = False
    branch_target: int = 0
    branch_target_valid: bool = False
    immediate_value: int = 0
    immediate_valid: bool = False
    page_cross: bool = False
    page_cross_valid: bool = False
    uses_accumulator: bool = False
    is_implied: bool = False
    mode_valid: bool = True
    result_valid: bool = False


def generate_address(
    mode: AddressingMode,
    *,
    base_address: int = 0,
    operand_byte: int = 0,
    x_index: int = 0,
    y_index: int = 0,
    pointer_low_byte: int = 0,
    pointer_high_byte: int = 0,
    pointer_data_valid: bool = False,
) -> AddressResult:
    """Calculate Phase 2C addresses without performing any memory access.

    ``base_address`` is the absolute operand, indirect pointer, or caller-
    selected post-displacement-PC branch base according to ``mode``. Pointer
    bytes are externally supplied values, keeping bus sequencing out of this
    arithmetic reference model.
    """

    if not isinstance(mode, AddressingMode):
        raise ValueError("mode must be an AddressingMode")
    if not 0 <= base_address <= 0xFFFF:
        raise ValueError("base_address must be a 16-bit value")
    byte_inputs = {
        "operand_byte": operand_byte,
        "x_index": x_index,
        "y_index": y_index,
        "pointer_low_byte": pointer_low_byte,
        "pointer_high_byte": pointer_high_byte,
    }
    for name, value in byte_inputs.items():
        if not 0 <= value <= 0xFF:
            raise ValueError(f"{name} must be an 8-bit value")
    if pointer_data_valid not in (False, True, 0, 1):
        raise ValueError("pointer_data_valid must be zero or one")

    if mode is AddressingMode.IMPLIED:
        return AddressResult(is_implied=True)
    if mode is AddressingMode.ACCUMULATOR:
        return AddressResult(uses_accumulator=True)
    if mode is AddressingMode.IMMEDIATE:
        return AddressResult(
            immediate_value=operand_byte,
            immediate_valid=True,
            result_valid=True,
        )
    if mode is AddressingMode.ZERO_PAGE:
        return AddressResult(
            effective_address=operand_byte,
            effective_address_valid=True,
            result_valid=True,
        )
    if mode is AddressingMode.ZERO_PAGE_X:
        return AddressResult(
            effective_address=(operand_byte + x_index) & 0xFF,
            effective_address_valid=True,
            result_valid=True,
        )
    if mode is AddressingMode.ZERO_PAGE_Y:
        return AddressResult(
            effective_address=(operand_byte + y_index) & 0xFF,
            effective_address_valid=True,
            result_valid=True,
        )
    if mode is AddressingMode.ABSOLUTE:
        return AddressResult(
            effective_address=base_address,
            effective_address_valid=True,
            result_valid=True,
        )
    if mode in (AddressingMode.ABSOLUTE_X, AddressingMode.ABSOLUTE_Y):
        index = x_index if mode is AddressingMode.ABSOLUTE_X else y_index
        total = base_address + index
        return AddressResult(
            effective_address=total & 0xFFFF,
            effective_address_valid=True,
            page_cross=(base_address & 0xFF) + index > 0xFF,
            page_cross_valid=True,
            result_valid=True,
        )

    pointer_value = (pointer_high_byte << 8) | pointer_low_byte
    if mode is AddressingMode.INDIRECT:
        result = AddressResult(
            pointer_low_address=base_address,
            pointer_high_address=(base_address & 0xFF00)
            | ((base_address + 1) & 0xFF),
            pointer_addresses_valid=True,
        )
        if pointer_data_valid:
            return replace(
                result,
                effective_address=pointer_value,
                effective_address_valid=True,
                result_valid=True,
            )
        return result
    if mode is AddressingMode.INDEXED_INDIRECT_X:
        pointer_address = (operand_byte + x_index) & 0xFF
        result = AddressResult(
            pointer_low_address=pointer_address,
            pointer_high_address=(pointer_address + 1) & 0xFF,
            pointer_addresses_valid=True,
        )
        if pointer_data_valid:
            return replace(
                result,
                effective_address=pointer_value,
                effective_address_valid=True,
                result_valid=True,
            )
        return result
    if mode is AddressingMode.INDIRECT_INDEXED_Y:
        result = AddressResult(
            pointer_low_address=operand_byte,
            pointer_high_address=(operand_byte + 1) & 0xFF,
            pointer_addresses_valid=True,
        )
        if pointer_data_valid:
            total = pointer_value + y_index
            return replace(
                result,
                effective_address=total & 0xFFFF,
                effective_address_valid=True,
                page_cross=(pointer_low_byte + y_index) > 0xFF,
                page_cross_valid=True,
                result_valid=True,
            )
        return result

    displacement = operand_byte if operand_byte < 0x80 else operand_byte - 0x100
    target = (base_address + displacement) & 0xFFFF
    return AddressResult(
        branch_target=target,
        branch_target_valid=True,
        page_cross=(base_address >> 8) != (target >> 8),
        page_cross_valid=True,
        result_valid=True,
    )


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
