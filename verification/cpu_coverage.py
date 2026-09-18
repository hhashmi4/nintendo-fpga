"""Machine-readable completed-official-opcode qualification metadata."""

from dataclasses import asdict

from verification.cpu import AddressingMode, Instruction, OPCODE_TABLE
from verification.cpu_2a03 import OFFICIAL_NMOS6502_OPCODES
from verification.cpu_timing import BusClass, CYCLE_TABLE


NZ = {
    Instruction.LDA, Instruction.LDX, Instruction.LDY,
    Instruction.TAX, Instruction.TAY, Instruction.TXA, Instruction.TYA,
    Instruction.TSX, Instruction.INX, Instruction.INY, Instruction.DEX,
    Instruction.DEY, Instruction.INC, Instruction.DEC,
    Instruction.AND, Instruction.ORA, Instruction.EOR, Instruction.PLA,
}
NZC = {
    Instruction.CMP, Instruction.CPX, Instruction.CPY,
    Instruction.ASL, Instruction.LSR, Instruction.ROL, Instruction.ROR,
}


def flag_effects(instruction: Instruction) -> str:
    """Return concise architectural flag ownership for an instruction."""

    if instruction in {Instruction.ADC, Instruction.SBC}:
        return "N,V,Z,C"
    if instruction is Instruction.BIT:
        return "N,V,Z"
    if instruction in NZ:
        return "N,Z"
    if instruction in NZC:
        return "N,Z,C"
    if instruction is Instruction.CLC:
        return "C=0"
    if instruction is Instruction.SEC:
        return "C=1"
    if instruction is Instruction.CLI:
        return "I=0 (delayed IRQ poll)"
    if instruction is Instruction.SEI:
        return "I=1 (delayed IRQ poll)"
    if instruction is Instruction.CLV:
        return "V=0"
    if instruction is Instruction.CLD:
        return "D=0"
    if instruction is Instruction.SED:
        return "D=1"
    if instruction in {Instruction.PLP, Instruction.RTI}:
        return "N,V,D,I,Z,C restored; B/U normalized"
    if instruction in {Instruction.BRK}:
        return "I=1"
    return "none"


def functional_class(instruction: Instruction, bus_class: BusClass) -> str:
    """Classify an opcode independently of its mnemonic spelling."""

    if instruction in {Instruction.LDA, Instruction.LDX, Instruction.LDY}:
        return "load"
    if instruction in {Instruction.STA, Instruction.STX, Instruction.STY}:
        return "store"
    if instruction in {
        Instruction.TAX, Instruction.TAY, Instruction.TXA,
        Instruction.TYA, Instruction.TSX, Instruction.TXS,
    }:
        return "transfer"
    if instruction in {Instruction.ADC, Instruction.SBC}:
        return "arithmetic"
    if instruction in {Instruction.AND, Instruction.ORA, Instruction.EOR, Instruction.BIT}:
        return "logic"
    if instruction in {Instruction.CMP, Instruction.CPX, Instruction.CPY}:
        return "compare"
    if bus_class is BusClass.RMW:
        return "read-modify-write"
    if instruction in {Instruction.INX, Instruction.INY, Instruction.DEX, Instruction.DEY}:
        return "register-update"
    if bus_class is BusClass.BRANCH:
        return "branch"
    if bus_class is BusClass.JUMP:
        return "jump"
    if bus_class is BusClass.STACK:
        return "stack"
    if bus_class is BusClass.INTERRUPT:
        return "interrupt"
    if instruction in {
        Instruction.CLC, Instruction.SEC, Instruction.CLI, Instruction.SEI,
        Instruction.CLV, Instruction.CLD, Instruction.SED,
    }:
        return "flag-control"
    if instruction is Instruction.NOP:
        return "nop"
    return "shift-rotate"


def official_opcode_coverage() -> list[dict[str, object]]:
    """Return one qualification record for every official opcode byte."""

    if set(OPCODE_TABLE) != OFFICIAL_NMOS6502_OPCODES:
        raise RuntimeError("implemented and authoritative official opcode sets differ")
    rows: list[dict[str, object]] = []
    for opcode in sorted(OFFICIAL_NMOS6502_OPCODES):
        decoded = OPCODE_TABLE[opcode]
        timing = CYCLE_TABLE[opcode]
        row = asdict(timing)
        row.update(
            {
                "opcode": f"{opcode:02X}",
                "instruction": decoded.instruction.name,
                "addressing_mode": AddressingMode(decoded.addressing_mode).name,
                "bytes": decoded.operand_bytes + 1,
                "functional_class": functional_class(
                    decoded.instruction, timing.bus_class
                ),
                "flag_effects": flag_effects(decoded.instruction),
                "implementation_status": "implemented",
                "test_status": "qualified",
            }
        )
        row["bus_class"] = timing.bus_class.value
        rows.append(row)
    return rows


OFFICIAL_OPCODE_COVERAGE = official_opcode_coverage()
