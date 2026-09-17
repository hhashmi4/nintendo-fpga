"""Independent reference models for the Phase 2A through 2G CPU blocks."""

from dataclasses import dataclass, replace
from enum import IntEnum


RESET_A = 0x00
RESET_X = 0x00
RESET_Y = 0x00
RESET_SP = 0xFD
RESET_PC = 0x0000
RESET_STATUS = 0x24
RESET_INSTRUCTION = 0x00
STATUS_BREAK_MASK = 0x10
STATUS_UNUSED_MASK = 0x20
VECTOR_NMI_LOW = 0xFFFA
VECTOR_RESET_LOW = 0xFFFC
VECTOR_IRQ_LOW = 0xFFFE


def normalize_status(value: int) -> int:
    """Return the persistent 2A03 status policy: B clear and U set."""

    if not 0 <= value <= 0xFF:
        raise ValueError("status must be an 8-bit value")
    return (value | STATUS_UNUSED_MASK) & ~STATUS_BREAK_MASK


def status_for_php(value: int) -> int:
    """Synthesize the PHP stack byte without making B persistent."""

    return normalize_status(value) | STATUS_BREAK_MASK


def status_for_interrupt(value: int) -> int:
    """Synthesize a hardware IRQ/NMI stack byte (B=0, U=1)."""

    return normalize_status(value)


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
    ALU_EXECUTE = 13
    RMW_WRITE = 14
    BRANCH_DECIDE = 15
    STACK_PUSH = 16
    STACK_PULL = 17
    STACK_READ = 18
    JSR_PUSH_HIGH = 19
    JSR_PUSH_LOW = 20
    RTS_PULL = 21
    RTS_PULL_LOW = 22
    RTS_PULL_HIGH = 23
    RTS_COMPLETE = 24
    RESET_VECTOR_LOW = 25
    RESET_VECTOR_HIGH = 26
    INTERRUPT_PUSH_HIGH = 27
    INTERRUPT_PUSH_LOW = 28
    INTERRUPT_PUSH_STATUS = 29
    INTERRUPT_VECTOR_LOW = 30
    INTERRUPT_VECTOR_HIGH = 31
    BRK_PADDING = 32
    RTI_PULL = 33
    RTI_PULL_STATUS = 34
    RTI_PULL_LOW = 35
    RTI_PULL_HIGH = 36
    RTI_COMPLETE = 37


class InterruptSource(IntEnum):
    """Phase 2G interrupt-source metadata."""

    NONE = 0
    RESET = 1
    NMI = 2
    IRQ = 3
    BRK = 4


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
    """Instruction identifiers implemented through the Phase 2G decoder."""

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
    ADC = 13
    SBC = 14
    AND = 15
    ORA = 16
    EOR = 17
    CMP = 18
    CPX = 19
    CPY = 20
    INX = 21
    INY = 22
    DEX = 23
    DEY = 24
    INC = 25
    DEC = 26
    ASL = 27
    LSR = 28
    ROL = 29
    ROR = 30
    JMP = 31
    JSR = 32
    RTS = 33
    BCC = 34
    BCS = 35
    BEQ = 36
    BMI = 37
    BNE = 38
    BPL = 39
    BVC = 40
    BVS = 41
    PHA = 42
    PLA = 43
    PHP = 44
    PLP = 45
    BRK = 46
    RTI = 47


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
    if addressing_mode in (
        AddressingMode.IMPLIED,
        AddressingMode.ACCUMULATOR,
    ):
        operand_bytes = 0
    elif addressing_mode in (
        AddressingMode.ABSOLUTE,
        AddressingMode.ABSOLUTE_X,
        AddressingMode.ABSOLUTE_Y,
        AddressingMode.INDIRECT,
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
    # Arithmetic and logic
    0x69: _opcode(Instruction.ADC, AddressingMode.IMMEDIATE),
    0x65: _opcode(Instruction.ADC, AddressingMode.ZERO_PAGE),
    0x75: _opcode(Instruction.ADC, AddressingMode.ZERO_PAGE_X),
    0x6D: _opcode(Instruction.ADC, AddressingMode.ABSOLUTE),
    0x7D: _opcode(Instruction.ADC, AddressingMode.ABSOLUTE_X),
    0x79: _opcode(Instruction.ADC, AddressingMode.ABSOLUTE_Y),
    0x61: _opcode(Instruction.ADC, AddressingMode.INDEXED_INDIRECT_X),
    0x71: _opcode(Instruction.ADC, AddressingMode.INDIRECT_INDEXED_Y),
    0xE9: _opcode(Instruction.SBC, AddressingMode.IMMEDIATE),
    0xE5: _opcode(Instruction.SBC, AddressingMode.ZERO_PAGE),
    0xF5: _opcode(Instruction.SBC, AddressingMode.ZERO_PAGE_X),
    0xED: _opcode(Instruction.SBC, AddressingMode.ABSOLUTE),
    0xFD: _opcode(Instruction.SBC, AddressingMode.ABSOLUTE_X),
    0xF9: _opcode(Instruction.SBC, AddressingMode.ABSOLUTE_Y),
    0xE1: _opcode(Instruction.SBC, AddressingMode.INDEXED_INDIRECT_X),
    0xF1: _opcode(Instruction.SBC, AddressingMode.INDIRECT_INDEXED_Y),
    0x29: _opcode(Instruction.AND, AddressingMode.IMMEDIATE),
    0x25: _opcode(Instruction.AND, AddressingMode.ZERO_PAGE),
    0x35: _opcode(Instruction.AND, AddressingMode.ZERO_PAGE_X),
    0x2D: _opcode(Instruction.AND, AddressingMode.ABSOLUTE),
    0x3D: _opcode(Instruction.AND, AddressingMode.ABSOLUTE_X),
    0x39: _opcode(Instruction.AND, AddressingMode.ABSOLUTE_Y),
    0x21: _opcode(Instruction.AND, AddressingMode.INDEXED_INDIRECT_X),
    0x31: _opcode(Instruction.AND, AddressingMode.INDIRECT_INDEXED_Y),
    0x09: _opcode(Instruction.ORA, AddressingMode.IMMEDIATE),
    0x05: _opcode(Instruction.ORA, AddressingMode.ZERO_PAGE),
    0x15: _opcode(Instruction.ORA, AddressingMode.ZERO_PAGE_X),
    0x0D: _opcode(Instruction.ORA, AddressingMode.ABSOLUTE),
    0x1D: _opcode(Instruction.ORA, AddressingMode.ABSOLUTE_X),
    0x19: _opcode(Instruction.ORA, AddressingMode.ABSOLUTE_Y),
    0x01: _opcode(Instruction.ORA, AddressingMode.INDEXED_INDIRECT_X),
    0x11: _opcode(Instruction.ORA, AddressingMode.INDIRECT_INDEXED_Y),
    0x49: _opcode(Instruction.EOR, AddressingMode.IMMEDIATE),
    0x45: _opcode(Instruction.EOR, AddressingMode.ZERO_PAGE),
    0x55: _opcode(Instruction.EOR, AddressingMode.ZERO_PAGE_X),
    0x4D: _opcode(Instruction.EOR, AddressingMode.ABSOLUTE),
    0x5D: _opcode(Instruction.EOR, AddressingMode.ABSOLUTE_X),
    0x59: _opcode(Instruction.EOR, AddressingMode.ABSOLUTE_Y),
    0x41: _opcode(Instruction.EOR, AddressingMode.INDEXED_INDIRECT_X),
    0x51: _opcode(Instruction.EOR, AddressingMode.INDIRECT_INDEXED_Y),
    # Compare
    0xC9: _opcode(Instruction.CMP, AddressingMode.IMMEDIATE),
    0xC5: _opcode(Instruction.CMP, AddressingMode.ZERO_PAGE),
    0xD5: _opcode(Instruction.CMP, AddressingMode.ZERO_PAGE_X),
    0xCD: _opcode(Instruction.CMP, AddressingMode.ABSOLUTE),
    0xDD: _opcode(Instruction.CMP, AddressingMode.ABSOLUTE_X),
    0xD9: _opcode(Instruction.CMP, AddressingMode.ABSOLUTE_Y),
    0xC1: _opcode(Instruction.CMP, AddressingMode.INDEXED_INDIRECT_X),
    0xD1: _opcode(Instruction.CMP, AddressingMode.INDIRECT_INDEXED_Y),
    0xE0: _opcode(Instruction.CPX, AddressingMode.IMMEDIATE),
    0xE4: _opcode(Instruction.CPX, AddressingMode.ZERO_PAGE),
    0xEC: _opcode(Instruction.CPX, AddressingMode.ABSOLUTE),
    0xC0: _opcode(Instruction.CPY, AddressingMode.IMMEDIATE),
    0xC4: _opcode(Instruction.CPY, AddressingMode.ZERO_PAGE),
    0xCC: _opcode(Instruction.CPY, AddressingMode.ABSOLUTE),
    # Register and memory increment/decrement
    0xE8: _opcode(Instruction.INX, AddressingMode.IMPLIED),
    0xC8: _opcode(Instruction.INY, AddressingMode.IMPLIED),
    0xCA: _opcode(Instruction.DEX, AddressingMode.IMPLIED),
    0x88: _opcode(Instruction.DEY, AddressingMode.IMPLIED),
    0xE6: _opcode(Instruction.INC, AddressingMode.ZERO_PAGE),
    0xF6: _opcode(Instruction.INC, AddressingMode.ZERO_PAGE_X),
    0xEE: _opcode(Instruction.INC, AddressingMode.ABSOLUTE),
    0xFE: _opcode(Instruction.INC, AddressingMode.ABSOLUTE_X),
    0xC6: _opcode(Instruction.DEC, AddressingMode.ZERO_PAGE),
    0xD6: _opcode(Instruction.DEC, AddressingMode.ZERO_PAGE_X),
    0xCE: _opcode(Instruction.DEC, AddressingMode.ABSOLUTE),
    0xDE: _opcode(Instruction.DEC, AddressingMode.ABSOLUTE_X),
    # Shift and rotate
    0x0A: _opcode(Instruction.ASL, AddressingMode.ACCUMULATOR),
    0x06: _opcode(Instruction.ASL, AddressingMode.ZERO_PAGE),
    0x16: _opcode(Instruction.ASL, AddressingMode.ZERO_PAGE_X),
    0x0E: _opcode(Instruction.ASL, AddressingMode.ABSOLUTE),
    0x1E: _opcode(Instruction.ASL, AddressingMode.ABSOLUTE_X),
    0x4A: _opcode(Instruction.LSR, AddressingMode.ACCUMULATOR),
    0x46: _opcode(Instruction.LSR, AddressingMode.ZERO_PAGE),
    0x56: _opcode(Instruction.LSR, AddressingMode.ZERO_PAGE_X),
    0x4E: _opcode(Instruction.LSR, AddressingMode.ABSOLUTE),
    0x5E: _opcode(Instruction.LSR, AddressingMode.ABSOLUTE_X),
    0x2A: _opcode(Instruction.ROL, AddressingMode.ACCUMULATOR),
    0x26: _opcode(Instruction.ROL, AddressingMode.ZERO_PAGE),
    0x36: _opcode(Instruction.ROL, AddressingMode.ZERO_PAGE_X),
    0x2E: _opcode(Instruction.ROL, AddressingMode.ABSOLUTE),
    0x3E: _opcode(Instruction.ROL, AddressingMode.ABSOLUTE_X),
    0x6A: _opcode(Instruction.ROR, AddressingMode.ACCUMULATOR),
    0x66: _opcode(Instruction.ROR, AddressingMode.ZERO_PAGE),
    0x76: _opcode(Instruction.ROR, AddressingMode.ZERO_PAGE_X),
    0x6E: _opcode(Instruction.ROR, AddressingMode.ABSOLUTE),
    0x7E: _opcode(Instruction.ROR, AddressingMode.ABSOLUTE_X),
    # Jumps and subroutines
    0x4C: _opcode(Instruction.JMP, AddressingMode.ABSOLUTE),
    0x6C: _opcode(Instruction.JMP, AddressingMode.INDIRECT),
    0x20: _opcode(Instruction.JSR, AddressingMode.ABSOLUTE),
    0x60: _opcode(Instruction.RTS, AddressingMode.IMPLIED),
    # Conditional branches
    0x90: _opcode(Instruction.BCC, AddressingMode.RELATIVE),
    0xB0: _opcode(Instruction.BCS, AddressingMode.RELATIVE),
    0xF0: _opcode(Instruction.BEQ, AddressingMode.RELATIVE),
    0x30: _opcode(Instruction.BMI, AddressingMode.RELATIVE),
    0xD0: _opcode(Instruction.BNE, AddressingMode.RELATIVE),
    0x10: _opcode(Instruction.BPL, AddressingMode.RELATIVE),
    0x50: _opcode(Instruction.BVC, AddressingMode.RELATIVE),
    0x70: _opcode(Instruction.BVS, AddressingMode.RELATIVE),
    # Explicit stack operations
    0x48: _opcode(Instruction.PHA, AddressingMode.IMPLIED),
    0x68: _opcode(Instruction.PLA, AddressingMode.IMPLIED),
    0x08: _opcode(Instruction.PHP, AddressingMode.IMPLIED),
    0x28: _opcode(Instruction.PLP, AddressingMode.IMPLIED),
    # Software interrupt and interrupt return
    0x00: _opcode(Instruction.BRK, AddressingMode.IMPLIED),
    0x40: _opcode(Instruction.RTI, AddressingMode.IMPLIED),
}


INSTRUCTION_ALU_OPERATION = {
    Instruction.ADC: AluOperation.ADD,
    Instruction.SBC: AluOperation.SUB,
    Instruction.AND: AluOperation.AND,
    Instruction.ORA: AluOperation.OR,
    Instruction.EOR: AluOperation.XOR,
    Instruction.CMP: AluOperation.CMP,
    Instruction.CPX: AluOperation.CMP,
    Instruction.CPY: AluOperation.CMP,
    Instruction.INX: AluOperation.INC,
    Instruction.INY: AluOperation.INC,
    Instruction.DEX: AluOperation.DEC,
    Instruction.DEY: AluOperation.DEC,
    Instruction.INC: AluOperation.INC,
    Instruction.DEC: AluOperation.DEC,
    Instruction.ASL: AluOperation.ASL,
    Instruction.LSR: AluOperation.LSR,
    Instruction.ROL: AluOperation.ROL,
    Instruction.ROR: AluOperation.ROR,
}

COMPARE_INSTRUCTIONS = {
    Instruction.CMP,
    Instruction.CPX,
    Instruction.CPY,
}

MEMORY_RMW_INSTRUCTIONS = {
    Instruction.INC,
    Instruction.DEC,
    Instruction.ASL,
    Instruction.LSR,
    Instruction.ROL,
    Instruction.ROR,
}

BRANCH_INSTRUCTIONS = {
    Instruction.BCC,
    Instruction.BCS,
    Instruction.BEQ,
    Instruction.BMI,
    Instruction.BNE,
    Instruction.BPL,
    Instruction.BVC,
    Instruction.BVS,
}

CONTROL_STACK_INSTRUCTIONS = BRANCH_INSTRUCTIONS | {
    Instruction.JMP,
    Instruction.JSR,
    Instruction.RTS,
    Instruction.PHA,
    Instruction.PLA,
    Instruction.PHP,
    Instruction.PLP,
    Instruction.BRK,
    Instruction.RTI,
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
    """Functional Phase 2D model and shared base for later CPU phases."""

    def __init__(
        self,
        *,
        initial_pc: int = RESET_PC,
        initial_status: int = RESET_STATUS,
    ) -> None:
        if not 0 <= initial_pc <= 0xFFFF:
            raise ValueError("initial_pc must be a 16-bit value")
        self.a = RESET_A
        self.x = RESET_X
        self.y = RESET_Y
        self.sp = RESET_SP
        self.pc = initial_pc
        self.status = normalize_status(initial_status)
        self.instruction = RESET_INSTRUCTION
        self.memory = bytearray(0x10000)
        self.writes: list[tuple[int, int]] = []
        self.reads: list[int] = []
        self.unsupported = False
        self.last_effective_address = 0
        self.last_page_cross = False
        self.last_page_cross_valid = False

    def load_program(self, address: int, data: bytes | list[int]) -> None:
        """Place bytes in generic test memory without changing the PC."""

        for offset, value in enumerate(data):
            self.memory[(address + offset) & 0xFFFF] = value

    def _read(self, address: int) -> int:
        wrapped_address = address & 0xFFFF
        self.reads.append(wrapped_address)
        return self.memory[wrapped_address]

    def _write(self, address: int, value: int) -> None:
        wrapped_address = address & 0xFFFF
        wrapped_value = value & 0xFF
        self.memory[wrapped_address] = wrapped_value
        self.writes.append((wrapped_address, wrapped_value))

    def _fetch_byte(self) -> int:
        value = self._read(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return value

    def _push(self, value: int) -> None:
        """Write at $0100|S, then decrement the wrapping 8-bit S."""

        self._write(0x0100 | self.sp, value)
        self.sp = (self.sp - 1) & 0xFF

    def _pull(self) -> int:
        """Increment wrapping 8-bit S, then read from $0100|S."""

        self.sp = (self.sp + 1) & 0xFF
        return self._read(0x0100 | self.sp)

    def _update_nz(self, value: int) -> None:
        self.status &= ~0x82
        if value & 0x80:
            self.status |= 0x80
        if value == 0:
            self.status |= 0x02

    def _apply_alu_flags(self, result: AluResult) -> None:
        """Apply exactly the status fields owned by an ALU operation."""

        flag_updates = (
            (result.n_valid, 0x80, result.negative),
            (result.v_valid, 0x40, result.overflow),
            (result.z_valid, 0x02, result.zero),
            (result.c_valid, 0x01, result.carry),
        )
        for valid, mask, value in flag_updates:
            if valid:
                if value:
                    self.status |= mask
                else:
                    self.status &= ~mask

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
        if spec is None or not self._instruction_supported(spec.instruction):
            self.unsupported = True
            return None

        operand_low = self._fetch_byte() if spec.operand_bytes else 0
        operand_high = self._fetch_byte() if spec.operand_bytes == 2 else 0

        if spec.instruction in CONTROL_STACK_INSTRUCTIONS:
            self._execute_control_stack(spec, operand_low, operand_high)
            return spec

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

        if spec.addressing_mode in (
            AddressingMode.IMPLIED,
            AddressingMode.ACCUMULATOR,
        ):
            self._execute_alu_instruction(spec.instruction)
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
        elif spec.instruction in INSTRUCTION_ALU_OPERATION:
            self._execute_alu_instruction(
                spec.instruction,
                operand=value,
                address=self.last_effective_address
                if spec.addressing_mode is not AddressingMode.IMMEDIATE
                else None,
            )
        else:
            raise RuntimeError("decoder classified an unsupported instruction")

        return spec

    def _instruction_supported(self, instruction: Instruction) -> bool:
        """Keep the historical Phase 2D unsupported-opcode boundary."""

        return instruction <= Instruction.TXS

    def _execute_control_stack(
        self,
        spec: OpcodeSpec,
        operand_low: int,
        operand_high: int,
    ) -> None:
        """Execute Phase 2F behavior independently of RTL microstates."""

        instruction = spec.instruction

        if instruction in BRANCH_INSTRUCTIONS:
            branch = generate_address(
                AddressingMode.RELATIVE,
                base_address=self.pc,
                operand_byte=operand_low,
            )
            self.last_effective_address = branch.branch_target
            self.last_page_cross = branch.page_cross
            self.last_page_cross_valid = branch.page_cross_valid
            conditions = {
                Instruction.BCC: not bool(self.status & 0x01),
                Instruction.BCS: bool(self.status & 0x01),
                Instruction.BEQ: bool(self.status & 0x02),
                Instruction.BMI: bool(self.status & 0x80),
                Instruction.BNE: not bool(self.status & 0x02),
                Instruction.BPL: not bool(self.status & 0x80),
                Instruction.BVC: not bool(self.status & 0x40),
                Instruction.BVS: bool(self.status & 0x40),
            }
            if conditions[instruction]:
                self.pc = branch.branch_target
            return

        if instruction is Instruction.JMP:
            pointer_or_target = (operand_high << 8) | operand_low
            if spec.addressing_mode is AddressingMode.ABSOLUTE:
                self.pc = pointer_or_target
            elif spec.addressing_mode is AddressingMode.INDIRECT:
                pointer = generate_address(
                    AddressingMode.INDIRECT,
                    base_address=pointer_or_target,
                )
                low = self._read(pointer.pointer_low_address)
                high = self._read(pointer.pointer_high_address)
                resolved = generate_address(
                    AddressingMode.INDIRECT,
                    base_address=pointer_or_target,
                    pointer_low_byte=low,
                    pointer_high_byte=high,
                    pointer_data_valid=True,
                )
                self.pc = resolved.effective_address
            else:
                raise RuntimeError("JMP used an unsupported addressing mode")
            self.last_effective_address = self.pc
            return

        if instruction is Instruction.JSR:
            target = (operand_high << 8) | operand_low
            return_address = (self.pc - 1) & 0xFFFF
            self._push(return_address >> 8)
            self._push(return_address & 0xFF)
            self.pc = target
            self.last_effective_address = target
            return

        if instruction is Instruction.RTS:
            low = self._pull()
            high = self._pull()
            self.pc = (((high << 8) | low) + 1) & 0xFFFF
            return

        if instruction is Instruction.PHA:
            self._push(self.a)
            return
        if instruction is Instruction.PHP:
            self._push(status_for_php(self.status))
            return
        if instruction is Instruction.PLA:
            self.a = self._pull()
            self._update_nz(self.a)
            return
        if instruction is Instruction.PLP:
            self.status = normalize_status(self._pull())
            return

        if instruction is Instruction.BRK:
            # The opcode fetch already advanced PC once. BRK performs one
            # additional padding/signature-byte read before stacking PC+2.
            self._fetch_byte()
            self._enter_interrupt(InterruptSource.BRK, self.pc)
            return

        if instruction is Instruction.RTI:
            self.status = normalize_status(self._pull())
            low = self._pull()
            high = self._pull()
            self.pc = (high << 8) | low
            return

        raise RuntimeError("unhandled Phase 2F control/stack instruction")

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

    def _execute_alu_instruction(
        self,
        instruction: Instruction,
        *,
        operand: int | None = None,
        address: int | None = None,
    ) -> None:
        """Execute one Phase 2E ALU-backed architectural operation."""

        operation = INSTRUCTION_ALU_OPERATION.get(instruction)
        if operation is None:
            raise RuntimeError("instruction has no Phase 2E ALU operation")

        if instruction in (
            Instruction.ADC,
            Instruction.SBC,
            Instruction.AND,
            Instruction.ORA,
            Instruction.EOR,
            Instruction.CMP,
        ):
            operand_a = self.a
            operand_b = operand
        elif instruction is Instruction.CPX:
            operand_a = self.x
            operand_b = operand
        elif instruction is Instruction.CPY:
            operand_a = self.y
            operand_b = operand
        elif instruction in (Instruction.INX, Instruction.DEX):
            operand_a = self.x
            operand_b = 0
        elif instruction in (Instruction.INY, Instruction.DEY):
            operand_a = self.y
            operand_b = 0
        elif instruction in (
            Instruction.ASL,
            Instruction.LSR,
            Instruction.ROL,
            Instruction.ROR,
        ) and operand is None:
            operand_a = self.a
            operand_b = 0
        else:
            operand_a = operand
            operand_b = 0

        if operand_a is None or operand_b is None:
            raise RuntimeError("ALU instruction requires an operand")

        alu_result = evaluate_alu(
            operation,
            operand_a,
            operand_b,
            self.status & 0x01,
        )
        self._apply_alu_flags(alu_result)

        if instruction in COMPARE_INSTRUCTIONS:
            if alu_result.result_valid:
                raise RuntimeError("compare unexpectedly advertised writeback")
            return
        if not alu_result.result_valid:
            raise RuntimeError("ALU instruction did not produce a result")

        if instruction in (
            Instruction.ADC,
            Instruction.SBC,
            Instruction.AND,
            Instruction.ORA,
            Instruction.EOR,
        ):
            self.a = alu_result.result
        elif instruction in (Instruction.INX, Instruction.DEX):
            self.x = alu_result.result
        elif instruction in (Instruction.INY, Instruction.DEY):
            self.y = alu_result.result
        elif instruction in (
            Instruction.ASL,
            Instruction.LSR,
            Instruction.ROL,
            Instruction.ROR,
        ) and operand is None:
            self.a = alu_result.result
        elif instruction in MEMORY_RMW_INSTRUCTIONS:
            if address is None:
                raise RuntimeError("memory RMW instruction requires an address")
            self._write(address, alu_result.result)
        else:
            raise RuntimeError("unhandled Phase 2E ALU destination")


class CpuPhase2EModel(CpuPhase2DModel):
    """Named Phase 2E entry point retaining Phase 2D compatibility."""

    def _instruction_supported(self, instruction: Instruction) -> bool:
        """Keep the historical Phase 2E unsupported-opcode boundary."""

        return instruction <= Instruction.ROR


class CpuPhase2FModel(CpuPhase2EModel):
    """Named Phase 2F entry point for control-flow and stack behavior."""

    def _instruction_supported(self, instruction: Instruction) -> bool:
        return instruction <= Instruction.PLP


class CpuPhase2GModel(CpuPhase2FModel):
    """Functional reset/interrupt model independent of RTL microstates."""

    def __init__(
        self,
        *,
        initial_pc: int = RESET_PC,
        initial_status: int = RESET_STATUS,
    ) -> None:
        super().__init__(initial_pc=initial_pc, initial_status=initial_status)
        self.nmi_pending = False
        self.nmi_level = False
        self.irq_level = False
        self.last_interrupt_source = InterruptSource.NONE

    def _instruction_supported(self, instruction: Instruction) -> bool:
        return instruction <= Instruction.RTI

    def reset_from_vector(self) -> int:
        """Apply deterministic reset state, then fetch $FFFC/$FFFD."""

        self.a = RESET_A
        self.x = RESET_X
        self.y = RESET_Y
        self.sp = RESET_SP
        self.pc = RESET_PC
        self.status = normalize_status(RESET_STATUS)
        self.instruction = RESET_INSTRUCTION
        self.unsupported = False
        self.nmi_pending = False
        self.nmi_level = False
        self.irq_level = False
        self.last_interrupt_source = InterruptSource.RESET
        low = self._read(VECTOR_RESET_LOW)
        high = self._read(VECTOR_RESET_LOW + 1)
        self.pc = (high << 8) | low
        return self.pc

    def sample_interrupt_inputs(self, *, nmi: bool, irq: bool) -> None:
        """Edge-capture logical NMI and retain logical IRQ as a level."""

        nmi_value = bool(nmi)
        if nmi_value and not self.nmi_level:
            self.nmi_pending = True
        self.nmi_level = nmi_value
        self.irq_level = bool(irq)

    def service_pending_interrupt(self) -> InterruptSource:
        """Service RESET-external priority at an instruction boundary."""

        if self.nmi_pending:
            self.nmi_pending = False
            source = InterruptSource.NMI
        elif self.irq_level and not (self.status & 0x04):
            source = InterruptSource.IRQ
        else:
            return InterruptSource.NONE
        self._enter_interrupt(source, self.pc)
        return source

    def _enter_interrupt(
        self,
        source: InterruptSource,
        return_pc: int,
    ) -> None:
        """Push a frame and load the selected vector."""

        if source not in (
            InterruptSource.NMI,
            InterruptSource.IRQ,
            InterruptSource.BRK,
        ):
            raise ValueError("source is not an entry-capable interrupt")
        self.last_interrupt_source = source
        self._push((return_pc >> 8) & 0xFF)
        self._push(return_pc & 0xFF)
        pushed_status = (
            status_for_php(self.status)
            if source is InterruptSource.BRK
            else status_for_interrupt(self.status)
        )
        self._push(pushed_status)
        self.status |= 0x04
        vector_low = (
            VECTOR_NMI_LOW
            if source is InterruptSource.NMI
            else VECTOR_IRQ_LOW
        )
        low = self._read(vector_low)
        high = self._read(vector_low + 1)
        self.pc = (high << 8) | low


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
    """Model deterministic reset, vector reads, and CPU-enable gating."""

    def __init__(self) -> None:
        self._snapshot = self.reset_snapshot()
        self._reset_vector_low = 0

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
            self._reset_vector_low = 0
        elif cpu_enable and self._snapshot.execution_state is ExecutionState.RESET:
            self._snapshot = replace(
                self._snapshot,
                execution_state=ExecutionState.RESET_VECTOR_LOW,
            )
        elif (
            cpu_enable
            and self._snapshot.execution_state is ExecutionState.RESET_VECTOR_LOW
        ):
            self._reset_vector_low = read_data
            self._snapshot = replace(
                self._snapshot,
                execution_state=ExecutionState.RESET_VECTOR_HIGH,
            )
        elif (
            cpu_enable
            and self._snapshot.execution_state is ExecutionState.RESET_VECTOR_HIGH
        ):
            self._snapshot = replace(
                self._snapshot,
                pc=(read_data << 8) | self._reset_vector_low,
                execution_state=ExecutionState.FETCH,
            )
        elif cpu_enable and self._snapshot.execution_state is ExecutionState.FETCH:
            self._snapshot = replace(
                self._snapshot,
                instruction=read_data,
                pc=(self._snapshot.pc + 1) & 0xFFFF,
                execution_state=ExecutionState.DECODE,
            )

    def bus_outputs(self, *, reset: bool) -> tuple[int, int, bool, bool]:
        """Return address, write data, write-enable, and cycle-valid."""

        state = self._snapshot.execution_state
        if reset:
            address = RESET_PC
        elif state is ExecutionState.RESET_VECTOR_LOW:
            address = VECTOR_RESET_LOW
        elif state is ExecutionState.RESET_VECTOR_HIGH:
            address = VECTOR_RESET_LOW + 1
        else:
            address = self._snapshot.pc
        valid = not reset and state in (
            ExecutionState.RESET_VECTOR_LOW,
            ExecutionState.RESET_VECTOR_HIGH,
            ExecutionState.FETCH,
        )
        return address, 0x00, False, valid
