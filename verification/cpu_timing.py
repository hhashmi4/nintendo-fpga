"""Independent NMOS 6502/Ricoh 2A03 cycle and bus-timing reference."""

from dataclasses import dataclass
from enum import Enum

from verification.cpu import (
    AddressingMode,
    BRANCH_INSTRUCTIONS,
    Instruction,
    MEMORY_RMW_INSTRUCTIONS,
    OPCODE_TABLE,
)


class BusClass(str, Enum):
    READ = "read"
    WRITE = "write"
    RMW = "rmw"
    BRANCH = "branch"
    JUMP = "jump"
    STACK = "stack"
    INTERRUPT = "interrupt"
    IMPLIED = "implied"


@dataclass(frozen=True)
class CycleSpec:
    opcode: int
    mnemonic: str
    addressing_mode: AddressingMode
    base_cycles: int
    page_cross_penalty: int
    branch_taken_penalty: int
    branch_page_cross_penalty: int
    bus_class: BusClass


@dataclass(frozen=True)
class BusAccess:
    address: int
    write: bool = False
    data: int | None = None
    purpose: str = "read"


READ_INSTRUCTIONS = {
    Instruction.LDA,
    Instruction.LDX,
    Instruction.LDY,
    Instruction.ADC,
    Instruction.SBC,
    Instruction.AND,
    Instruction.ORA,
    Instruction.EOR,
    Instruction.CMP,
    Instruction.CPX,
    Instruction.CPY,
}
STORE_INSTRUCTIONS = {Instruction.STA, Instruction.STX, Instruction.STY}
REGISTER_IMPLIED = {
    Instruction.TAX,
    Instruction.TAY,
    Instruction.TXA,
    Instruction.TYA,
    Instruction.TSX,
    Instruction.TXS,
    Instruction.INX,
    Instruction.INY,
    Instruction.DEX,
    Instruction.DEY,
}


def _cycle_spec(opcode: int) -> CycleSpec:
    decoded = OPCODE_TABLE[opcode]
    instruction = decoded.instruction
    mode = decoded.addressing_mode
    page_penalty = 0
    taken_penalty = 0
    branch_page_penalty = 0

    if instruction in BRANCH_INSTRUCTIONS:
        cycles, bus_class = 2, BusClass.BRANCH
        taken_penalty = 1
        branch_page_penalty = 1
    elif instruction in STORE_INSTRUCTIONS:
        cycles = {
            AddressingMode.ZERO_PAGE: 3,
            AddressingMode.ZERO_PAGE_X: 4,
            AddressingMode.ZERO_PAGE_Y: 4,
            AddressingMode.ABSOLUTE: 4,
            AddressingMode.ABSOLUTE_X: 5,
            AddressingMode.ABSOLUTE_Y: 5,
            AddressingMode.INDEXED_INDIRECT_X: 6,
            AddressingMode.INDIRECT_INDEXED_Y: 6,
        }[mode]
        bus_class = BusClass.WRITE
    elif instruction in MEMORY_RMW_INSTRUCTIONS and mode is not AddressingMode.ACCUMULATOR:
        cycles = {
            AddressingMode.ZERO_PAGE: 5,
            AddressingMode.ZERO_PAGE_X: 6,
            AddressingMode.ABSOLUTE: 6,
            AddressingMode.ABSOLUTE_X: 7,
        }[mode]
        bus_class = BusClass.RMW
    elif instruction in READ_INSTRUCTIONS:
        cycles = {
            AddressingMode.IMMEDIATE: 2,
            AddressingMode.ZERO_PAGE: 3,
            AddressingMode.ZERO_PAGE_X: 4,
            AddressingMode.ZERO_PAGE_Y: 4,
            AddressingMode.ABSOLUTE: 4,
            AddressingMode.ABSOLUTE_X: 4,
            AddressingMode.ABSOLUTE_Y: 4,
            AddressingMode.INDEXED_INDIRECT_X: 6,
            AddressingMode.INDIRECT_INDEXED_Y: 5,
        }[mode]
        page_penalty = int(
            mode
            in {
                AddressingMode.ABSOLUTE_X,
                AddressingMode.ABSOLUTE_Y,
                AddressingMode.INDIRECT_INDEXED_Y,
            }
        )
        bus_class = BusClass.READ
    elif instruction in REGISTER_IMPLIED or mode is AddressingMode.ACCUMULATOR:
        cycles, bus_class = 2, BusClass.IMPLIED
    elif instruction is Instruction.JMP:
        cycles = 3 if mode is AddressingMode.ABSOLUTE else 5
        bus_class = BusClass.JUMP
    elif instruction is Instruction.JSR:
        cycles, bus_class = 6, BusClass.JUMP
    elif instruction is Instruction.RTS:
        cycles, bus_class = 6, BusClass.STACK
    elif instruction in {Instruction.PHA, Instruction.PHP}:
        cycles, bus_class = 3, BusClass.STACK
    elif instruction in {Instruction.PLA, Instruction.PLP}:
        cycles, bus_class = 4, BusClass.STACK
    elif instruction is Instruction.BRK:
        cycles, bus_class = 7, BusClass.INTERRUPT
    elif instruction is Instruction.RTI:
        cycles, bus_class = 6, BusClass.INTERRUPT
    else:  # pragma: no cover - construction must cover all implemented bytes
        raise ValueError(f"no timing rule for implemented opcode {opcode:02X}")

    return CycleSpec(
        opcode=opcode,
        mnemonic=instruction.name,
        addressing_mode=mode,
        base_cycles=cycles,
        page_cross_penalty=page_penalty,
        branch_taken_penalty=taken_penalty,
        branch_page_cross_penalty=branch_page_penalty,
        bus_class=bus_class,
    )


CYCLE_TABLE = {opcode: _cycle_spec(opcode) for opcode in OPCODE_TABLE}


def instruction_cycles(
    opcode: int,
    *,
    page_cross: bool = False,
    branch_taken: bool = False,
) -> int:
    """Return the documented cycle count for one implemented opcode."""

    spec = CYCLE_TABLE[opcode]
    cycles = spec.base_cycles
    if spec.bus_class is BusClass.BRANCH:
        if branch_taken:
            cycles += spec.branch_taken_penalty
            if page_cross:
                cycles += spec.branch_page_cross_penalty
    elif page_cross:
        cycles += spec.page_cross_penalty
    return cycles


def page_cross(base: int, index: int) -> bool:
    return ((base & 0xFF) + (index & 0xFF)) > 0xFF


def branch_trace(opcode_pc: int, offset: int, *, taken: bool) -> list[BusAccess]:
    """Model the observable 2/3/4-cycle relative-branch bus sequence."""

    opcode_pc &= 0xFFFF
    offset &= 0xFF
    base = (opcode_pc + 2) & 0xFFFF
    displacement = offset if offset < 0x80 else offset - 0x100
    target = (base + displacement) & 0xFFFF
    trace = [
        BusAccess(opcode_pc, purpose="opcode"),
        BusAccess((opcode_pc + 1) & 0xFFFF, purpose="displacement"),
    ]
    if taken:
        trace.append(BusAccess(base, purpose="taken-dummy"))
        if (base >> 8) != (target >> 8):
            trace.append(
                BusAccess(
                    (base & 0xFF00) | (target & 0xFF),
                    purpose="page-correction-dummy",
                )
            )
    return trace


def absolute_indexed_trace(
    opcode_pc: int,
    base: int,
    index: int,
    *,
    write_data: int | None = None,
) -> list[BusAccess]:
    """Model absolute-indexed read or store, including the tentative read."""

    opcode_pc &= 0xFFFF
    base &= 0xFFFF
    index &= 0xFF
    target = (base + index) & 0xFFFF
    tentative = (base & 0xFF00) | (target & 0xFF)
    trace = [
        BusAccess(opcode_pc, purpose="opcode"),
        BusAccess((opcode_pc + 1) & 0xFFFF, purpose="operand-low"),
        BusAccess((opcode_pc + 2) & 0xFFFF, purpose="operand-high"),
        BusAccess(tentative, purpose="indexed-tentative"),
    ]
    if write_data is not None:
        trace.append(BusAccess(target, True, write_data & 0xFF, "store"))
    elif tentative != target:
        trace.append(BusAccess(target, purpose="page-corrected-read"))
    return trace


def rmw_tail(address: int, original: int, modified: int) -> list[BusAccess]:
    """Return the NMOS read/original-write/modified-write RMW tail."""

    address &= 0xFFFF
    return [
        BusAccess(address, purpose="rmw-read"),
        BusAccess(address, True, original & 0xFF, "rmw-original-write"),
        BusAccess(address, True, modified & 0xFF, "rmw-final-write"),
    ]


def reset_trace(pc: int = 0, sp: int = 0) -> list[BusAccess]:
    """Return the deterministic seven-cycle reset bus sequence."""

    pc &= 0xFFFF
    sp &= 0xFF
    return [
        BusAccess(pc, purpose="reset-dummy-1"),
        BusAccess(pc, purpose="reset-dummy-2"),
        BusAccess(0x0100 | sp, purpose="reset-stack-1"),
        BusAccess(0x0100 | ((sp - 1) & 0xFF), purpose="reset-stack-2"),
        BusAccess(0x0100 | ((sp - 2) & 0xFF), purpose="reset-stack-3"),
        BusAccess(0xFFFC, purpose="reset-vector-low"),
        BusAccess(0xFFFD, purpose="reset-vector-high"),
    ]


def hardware_interrupt_trace(
    pc: int,
    sp: int,
    status: int,
    vector_low: int,
) -> list[BusAccess]:
    """Return IRQ/NMI entry bus activity; B is clear and U is high."""

    pc &= 0xFFFF
    sp &= 0xFF
    pushed_status = (status | 0x20) & ~0x10
    return [
        BusAccess(pc, purpose="discarded-opcode"),
        BusAccess(pc, purpose="interrupt-dummy"),
        BusAccess(0x0100 | sp, True, pc >> 8, "push-pch"),
        BusAccess(0x0100 | ((sp - 1) & 0xFF), True, pc & 0xFF, "push-pcl"),
        BusAccess(
            0x0100 | ((sp - 2) & 0xFF), True, pushed_status, "push-status"
        ),
        BusAccess(vector_low & 0xFFFF, purpose="vector-low"),
        BusAccess((vector_low + 1) & 0xFFFF, purpose="vector-high"),
    ]
