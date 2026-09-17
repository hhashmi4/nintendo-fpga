"""Independent reference models for the Phase 2A through 2D CPU blocks."""

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
    """Execution-state encodings shared with the evolving CPU RTL."""

    RESET = 0
    FETCH = 1
    DECODE = 2
    OPERAND_LOW = 3
    OPERAND_HIGH = 4
    ADDRESS = 5
    POINTER_LOW = 6
    POINTER_HIGH = 7
    MEMORY_READ = 8
    MEMORY_WRITE = 9
    WRITEBACK = 10
    TRANSFER = 11
    TRAP = 12


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


class Instruction(IntEnum):
    """Instruction identifiers implemented by the Phase 2D decoder."""

    INVALID = 0
    LDA = 1
    LDX = 2
    LDY = 3
    STA = 4
    STX = 5
    STY = 6
    TAX = 7
    TAY = 8
    TXA = 9
    TYA = 10
    TSX = 11
    TXS = 12


@dataclass(frozen=True)
class OpcodeSpec:
    """Architectural decode information, independent of RTL sequencing."""

    instruction: Instruction
    addressing_mode: AddressingMode
    operand_bytes: int


def _opcode(
    instruction: Instruction,
    addressing_mode: AddressingMode,
) -> OpcodeSpec:
    if addressing_mode is AddressingMode.IMPLIED:
        operand_bytes = 0
    elif addressing_mode in (
        AddressingMode.ABSOLUTE,
        AddressingMode.ABSOLUTE_X,
        AddressingMode.ABSOLUTE_Y,
    ):
        operand_bytes = 2
    else:
        operand_bytes = 1
    return OpcodeSpec(instruction, addressing_mode, operand_bytes)


OPCODE_TABLE = {
    # Loads
    0xA9: _opcode(Instruction.LDA, AddressingMode.IMMEDIATE),
    0xA5: _opcode(Instruction.LDA, AddressingMode.ZERO_PAGE),
    0xB5: _opcode(Instruction.LDA, AddressingMode.ZERO_PAGE_X),
    0xAD: _opcode(Instruction.LDA, AddressingMode.ABSOLUTE),
    0xBD: _opcode(Instruction.LDA, AddressingMode.ABSOLUTE_X),
    0xB9: _opcode(Instruction.LDA, AddressingMode.ABSOLUTE_Y),
    0xA1: _opcode(Instruction.LDA, AddressingMode.INDEXED_INDIRECT_X),
    0xB1: _opcode(Instruction.LDA, AddressingMode.INDIRECT_INDEXED_Y),
    0xA2: _opcode(Instruction.LDX, AddressingMode.IMMEDIATE),
    0xA6: _opcode(Instruction.LDX, AddressingMode.ZERO_PAGE),
    0xB6: _opcode(Instruction.LDX, AddressingMode.ZERO_PAGE_Y),
    0xAE: _opcode(Instruction.LDX, AddressingMode.ABSOLUTE),
    0xBE: _opcode(Instruction.LDX, AddressingMode.ABSOLUTE_Y),
    0xA0: _opcode(Instruction.LDY, AddressingMode.IMMEDIATE),
    0xA4: _opcode(Instruction.LDY, AddressingMode.ZERO_PAGE),
    0xB4: _opcode(Instruction.LDY, AddressingMode.ZERO_PAGE_X),
    0xAC: _opcode(Instruction.LDY, AddressingMode.ABSOLUTE),
    0xBC: _opcode(Instruction.LDY, AddressingMode.ABSOLUTE_X),
    # Stores
    0x85: _opcode(Instruction.STA, AddressingMode.ZERO_PAGE),
    0x95: _opcode(Instruction.STA, AddressingMode.ZERO_PAGE_X),
    0x8D: _opcode(Instruction.STA, AddressingMode.ABSOLUTE),
    0x9D: _opcode(Instruction.STA, AddressingMode.ABSOLUTE_X),
    0x99: _opcode(Instruction.STA, AddressingMode.ABSOLUTE_Y),
    0x81: _opcode(Instruction.STA, AddressingMode.INDEXED_INDIRECT_X),
    0x91: _opcode(Instruction.STA, AddressingMode.INDIRECT_INDEXED_Y),
    0x86: _opcode(Instruction.STX, AddressingMode.ZERO_PAGE),
    0x96: _opcode(Instruction.STX, AddressingMode.ZERO_PAGE_Y),
    0x8E: _opcode(Instruction.STX, AddressingMode.ABSOLUTE),
    0x84: _opcode(Instruction.STY, AddressingMode.ZERO_PAGE),
    0x94: _opcode(Instruction.STY, AddressingMode.ZERO_PAGE_X),
    0x8C: _opcode(Instruction.STY, AddressingMode.ABSOLUTE),
    # Transfers
    0xAA: _opcode(Instruction.TAX, AddressingMode.IMPLIED),
    0xA8: _opcode(Instruction.TAY, AddressingMode.IMPLIED),
    0x8A: _opcode(Instruction.TXA, AddressingMode.IMPLIED),
    0x98: _opcode(Instruction.TYA, AddressingMode.IMPLIED),
    0xBA: _opcode(Instruction.TSX, AddressingMode.IMPLIED),
    0x9A: _opcode(Instruction.TXS, AddressingMode.IMPLIED),
}


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


class CpuPhase2DModel:
    """Functional load/store/transfer model without RTL microcycle mimicry."""

    def __init__(self, *, initial_pc: int = RESET_PC) -> None:
        if not 0 <= initial_pc <= 0xFFFF:
            raise ValueError("initial_pc must be a 16-bit value")
        self.a = RESET_A
        self.x = RESET_X
        self.y = RESET_Y
        self.sp = RESET_SP
        self.pc = initial_pc
        self.status = RESET_STATUS
        self.instruction = RESET_INSTRUCTION
        self.memory = bytearray(0x10000)
        self.writes: list[tuple[int, int]] = []
        self.unsupported = False
        self.last_effective_address = 0
        self.last_page_cross = False
        self.last_page_cross_valid = False

    def load_program(self, address: int, data: bytes | list[int]) -> None:
        """Place bytes in generic test memory without changing the PC."""

        for offset, value in enumerate(data):
            self.memory[(address + offset) & 0xFFFF] = value

    def _read(self, address: int) -> int:
        return self.memory[address & 0xFFFF]

    def _write(self, address: int, value: int) -> None:
        wrapped_address = address & 0xFFFF
        wrapped_value = value & 0xFF
        self.memory[wrapped_address] = wrapped_value
        self.writes.append((wrapped_address, wrapped_value))

    def _fetch_byte(self) -> int:
        value = self._read(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return value

    def _update_nz(self, value: int) -> None:
        self.status &= ~0x82
        if value & 0x80:
            self.status |= 0x80
        if value == 0:
            self.status |= 0x02

    def _resolve_address(
        self,
        mode: AddressingMode,
        operand_low: int,
        operand_high: int,
    ) -> AddressResult:
        base_address = (operand_high << 8) | operand_low
        unresolved = generate_address(
            mode,
            base_address=base_address,
            operand_byte=operand_low,
            x_index=self.x,
            y_index=self.y,
        )
        if mode not in (
            AddressingMode.INDEXED_INDIRECT_X,
            AddressingMode.INDIRECT_INDEXED_Y,
        ):
            return unresolved

        pointer_low = self._read(unresolved.pointer_low_address)
        pointer_high = self._read(unresolved.pointer_high_address)
        return generate_address(
            mode,
            base_address=base_address,
            operand_byte=operand_low,
            x_index=self.x,
            y_index=self.y,
            pointer_low_byte=pointer_low,
            pointer_high_byte=pointer_high,
            pointer_data_valid=True,
        )

    def execute_one(self) -> OpcodeSpec | None:
        """Execute one supported instruction or enter the unsupported trap."""

        if self.unsupported:
            return None

        self.instruction = self._fetch_byte()
        spec = OPCODE_TABLE.get(self.instruction)
        if spec is None:
            self.unsupported = True
            return None

        operand_low = self._fetch_byte() if spec.operand_bytes else 0
        operand_high = self._fetch_byte() if spec.operand_bytes == 2 else 0

        if spec.instruction in (
            Instruction.TAX,
            Instruction.TAY,
            Instruction.TXA,
            Instruction.TYA,
            Instruction.TSX,
            Instruction.TXS,
        ):
            self._execute_transfer(spec.instruction)
            return spec

        if spec.addressing_mode is AddressingMode.IMMEDIATE:
            value = operand_low
        else:
            address = self._resolve_address(
                spec.addressing_mode, operand_low, operand_high
            )
            if not address.effective_address_valid:
                raise RuntimeError("implemented mode did not resolve an address")
            self.last_effective_address = address.effective_address
            self.last_page_cross = address.page_cross
            self.last_page_cross_valid = address.page_cross_valid
            if spec.instruction in (
                Instruction.STA,
                Instruction.STX,
                Instruction.STY,
            ):
                value = 0
            else:
                value = self._read(address.effective_address)

        if spec.instruction is Instruction.LDA:
            self.a = value
            self._update_nz(value)
        elif spec.instruction is Instruction.LDX:
            self.x = value
            self._update_nz(value)
        elif spec.instruction is Instruction.LDY:
            self.y = value
            self._update_nz(value)
        elif spec.instruction is Instruction.STA:
            self._write(self.last_effective_address, self.a)
        elif spec.instruction is Instruction.STX:
            self._write(self.last_effective_address, self.x)
        elif spec.instruction is Instruction.STY:
            self._write(self.last_effective_address, self.y)
        else:
            raise RuntimeError("decoder classified an unsupported instruction")

        return spec

    def _execute_transfer(self, instruction: Instruction) -> None:
        if instruction is Instruction.TAX:
            self.x = self.a
            self._update_nz(self.x)
        elif instruction is Instruction.TAY:
            self.y = self.a
            self._update_nz(self.y)
        elif instruction is Instruction.TXA:
            self.a = self.x
            self._update_nz(self.a)
        elif instruction is Instruction.TYA:
            self.a = self.y
            self._update_nz(self.a)
        elif instruction is Instruction.TSX:
            self.x = self.sp
            self._update_nz(self.x)
        elif instruction is Instruction.TXS:
            self.sp = self.x
        else:
            raise RuntimeError("invalid transfer instruction")


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
