"""Functional reference verification for Phase 2D instructions."""

import re
from pathlib import Path

import pytest

from verification.cpu import (
    OPCODE_TABLE,
    AddressingMode,
    CpuPhase2DModel,
    Instruction,
)


ROOT = Path(__file__).resolve().parents[2]
RTL_DECODER = ROOT / "rtl" / "cpu" / "cpu_decoder.sv"
PROGRAM_START = 0x0200
BOUNDARY_VALUES = (0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF)
BOUNDARY_ADDRESSES = (
    0x0000,
    0x0001,
    0x00FE,
    0x00FF,
    0x0100,
    0x7FFF,
    0x8000,
    0xFF00,
    0xFFFE,
    0xFFFF,
)
POINTER_TARGETS = (0x0100, 0x7FFF, 0x8000, 0xFF00, 0xFFFE, 0xFFFF)

EXPECTED_OPCODES = {
    # LDA
    0xA9: (Instruction.LDA, AddressingMode.IMMEDIATE),
    0xA5: (Instruction.LDA, AddressingMode.ZERO_PAGE),
    0xB5: (Instruction.LDA, AddressingMode.ZERO_PAGE_X),
    0xAD: (Instruction.LDA, AddressingMode.ABSOLUTE),
    0xBD: (Instruction.LDA, AddressingMode.ABSOLUTE_X),
    0xB9: (Instruction.LDA, AddressingMode.ABSOLUTE_Y),
    0xA1: (Instruction.LDA, AddressingMode.INDEXED_INDIRECT_X),
    0xB1: (Instruction.LDA, AddressingMode.INDIRECT_INDEXED_Y),
    # LDX
    0xA2: (Instruction.LDX, AddressingMode.IMMEDIATE),
    0xA6: (Instruction.LDX, AddressingMode.ZERO_PAGE),
    0xB6: (Instruction.LDX, AddressingMode.ZERO_PAGE_Y),
    0xAE: (Instruction.LDX, AddressingMode.ABSOLUTE),
    0xBE: (Instruction.LDX, AddressingMode.ABSOLUTE_Y),
    # LDY
    0xA0: (Instruction.LDY, AddressingMode.IMMEDIATE),
    0xA4: (Instruction.LDY, AddressingMode.ZERO_PAGE),
    0xB4: (Instruction.LDY, AddressingMode.ZERO_PAGE_X),
    0xAC: (Instruction.LDY, AddressingMode.ABSOLUTE),
    0xBC: (Instruction.LDY, AddressingMode.ABSOLUTE_X),
    # STA/STX/STY
    0x85: (Instruction.STA, AddressingMode.ZERO_PAGE),
    0x95: (Instruction.STA, AddressingMode.ZERO_PAGE_X),
    0x8D: (Instruction.STA, AddressingMode.ABSOLUTE),
    0x9D: (Instruction.STA, AddressingMode.ABSOLUTE_X),
    0x99: (Instruction.STA, AddressingMode.ABSOLUTE_Y),
    0x81: (Instruction.STA, AddressingMode.INDEXED_INDIRECT_X),
    0x91: (Instruction.STA, AddressingMode.INDIRECT_INDEXED_Y),
    0x86: (Instruction.STX, AddressingMode.ZERO_PAGE),
    0x96: (Instruction.STX, AddressingMode.ZERO_PAGE_Y),
    0x8E: (Instruction.STX, AddressingMode.ABSOLUTE),
    0x84: (Instruction.STY, AddressingMode.ZERO_PAGE),
    0x94: (Instruction.STY, AddressingMode.ZERO_PAGE_X),
    0x8C: (Instruction.STY, AddressingMode.ABSOLUTE),
    # Transfers
    0xAA: (Instruction.TAX, AddressingMode.IMPLIED),
    0xA8: (Instruction.TAY, AddressingMode.IMPLIED),
    0x8A: (Instruction.TXA, AddressingMode.IMPLIED),
    0x98: (Instruction.TYA, AddressingMode.IMPLIED),
    0xBA: (Instruction.TSX, AddressingMode.IMPLIED),
    0x9A: (Instruction.TXS, AddressingMode.IMPLIED),
}


def _operand_bytes(mode: AddressingMode) -> int:
    if mode is AddressingMode.IMPLIED:
        return 0
    if mode in (
        AddressingMode.ABSOLUTE,
        AddressingMode.ABSOLUTE_X,
        AddressingMode.ABSOLUTE_Y,
    ):
        return 2
    return 1


def _expected_nz(status: int, value: int) -> int:
    return (status & ~0x82) | (0x80 if value & 0x80 else 0) | (
        0x02 if value == 0 else 0
    )


def _configure_vector(
    model: CpuPhase2DModel,
    opcode: int,
    instruction: Instruction,
    mode: AddressingMode,
    value: int,
    variant: int,
) -> tuple[int | None, int]:
    """Configure one independent vector and return target and initial status."""

    index = BOUNDARY_VALUES[variant]
    operand = BOUNDARY_VALUES[(variant + 2) % len(BOUNDARY_VALUES)]
    base = BOUNDARY_ADDRESSES[(opcode + variant) % len(BOUNDARY_ADDRESSES)]
    model.a = 0x3C
    model.x = index
    model.y = index
    model.sp = 0x55
    model.status = 0x6D  # V, U, D, I, and C set; N and Z clear.
    initial_status = model.status

    if instruction in (Instruction.TAX, Instruction.TAY):
        model.a = value
    elif instruction is Instruction.TXA:
        model.x = value
    elif instruction is Instruction.TYA:
        model.y = value
    elif instruction is Instruction.TSX:
        model.sp = value
    elif instruction is Instruction.TXS:
        model.x = value

    if mode is AddressingMode.IMPLIED:
        model.load_program(PROGRAM_START, [opcode])
        return None, initial_status

    if mode is AddressingMode.IMMEDIATE:
        model.load_program(PROGRAM_START, [opcode, value])
        return None, initial_status

    if mode in (
        AddressingMode.ZERO_PAGE,
        AddressingMode.ZERO_PAGE_X,
        AddressingMode.ZERO_PAGE_Y,
    ):
        if mode is AddressingMode.ZERO_PAGE:
            target = operand
        elif mode is AddressingMode.ZERO_PAGE_X:
            target = (operand + model.x) & 0xFF
        else:
            target = (operand + model.y) & 0xFF
        model.load_program(PROGRAM_START, [opcode, operand])
    elif mode in (
        AddressingMode.ABSOLUTE,
        AddressingMode.ABSOLUTE_X,
        AddressingMode.ABSOLUTE_Y,
    ):
        if mode is AddressingMode.ABSOLUTE:
            target = base
        elif mode is AddressingMode.ABSOLUTE_X:
            target = (base + model.x) & 0xFFFF
        else:
            target = (base + model.y) & 0xFFFF
        model.load_program(PROGRAM_START, [opcode, base & 0xFF, base >> 8])
    elif mode is AddressingMode.INDEXED_INDIRECT_X:
        target = POINTER_TARGETS[variant]
        pointer_address = (operand + model.x) & 0xFF
        model.memory[pointer_address] = target & 0xFF
        model.memory[(pointer_address + 1) & 0xFF] = target >> 8
        model.load_program(PROGRAM_START, [opcode, operand])
    else:
        target = POINTER_TARGETS[variant]
        pointer_base = (target - model.y) & 0xFFFF
        model.memory[operand] = pointer_base & 0xFF
        model.memory[(operand + 1) & 0xFF] = pointer_base >> 8
        model.load_program(PROGRAM_START, [opcode, operand])

    if instruction in (Instruction.LDA, Instruction.LDX, Instruction.LDY):
        model.memory[target] = value
    elif instruction is Instruction.STA:
        model.a = value
        model.memory[target] = value ^ 0xFF
    elif instruction is Instruction.STX:
        model.x = value
        model.memory[target] = value ^ 0xFF
    elif instruction is Instruction.STY:
        model.y = value
        model.memory[target] = value ^ 0xFF

    return target, initial_status


def test_opcode_matrix_is_exact_and_matches_rtl() -> None:
    assert len(EXPECTED_OPCODES) == 37
    assert set(OPCODE_TABLE) == set(EXPECTED_OPCODES)

    rtl = RTL_DECODER.read_text(encoding="utf-8")
    assert len(re.findall(r"8'h[0-9A-F]{2}:", rtl)) == 37
    for opcode, (instruction, mode) in EXPECTED_OPCODES.items():
        spec = OPCODE_TABLE[opcode]
        assert (spec.instruction, spec.addressing_mode) == (instruction, mode)
        assert spec.operand_bytes == _operand_bytes(mode)
        pattern = (
            rf"8'h{opcode:02X}:.*CPU_INSTR_{instruction.name};"
            rf".*CPU_ADDR_{mode.name};"
        )
        assert re.search(pattern, rtl), f"RTL decode mismatch for {opcode:02X}"


@pytest.mark.parametrize("instruction", list(Instruction)[1:])
def test_every_opcode_with_all_boundary_values(instruction: Instruction) -> None:
    instruction_opcodes = [
        (opcode, mode)
        for opcode, (decoded_instruction, mode) in EXPECTED_OPCODES.items()
        if decoded_instruction is instruction
    ]

    for opcode, mode in instruction_opcodes:
        for variant, value in enumerate(BOUNDARY_VALUES):
            model = CpuPhase2DModel(initial_pc=PROGRAM_START)
            target, initial_status = _configure_vector(
                model, opcode, instruction, mode, value, variant
            )
            initial_registers = (model.a, model.x, model.y, model.sp)

            spec = model.execute_one()

            assert spec is not None
            assert model.pc == PROGRAM_START + 1 + _operand_bytes(mode)
            assert not model.unsupported

            if instruction is Instruction.LDA:
                assert model.a == value
                assert (model.x, model.y, model.sp) == initial_registers[1:]
                assert model.status == _expected_nz(initial_status, value)
            elif instruction is Instruction.LDX:
                assert model.x == value
                assert (model.a, model.y, model.sp) == (
                    initial_registers[0],
                    initial_registers[2],
                    initial_registers[3],
                )
                assert model.status == _expected_nz(initial_status, value)
            elif instruction is Instruction.LDY:
                assert model.y == value
                assert (model.a, model.x, model.sp) == (
                    initial_registers[0],
                    initial_registers[1],
                    initial_registers[3],
                )
                assert model.status == _expected_nz(initial_status, value)
            elif instruction in (Instruction.STA, Instruction.STX, Instruction.STY):
                assert target is not None
                assert model.memory[target] == value
                assert model.writes == [(target, value)]
                assert (model.a, model.x, model.y, model.sp) == initial_registers
                assert model.status == initial_status
            else:
                source = value
                if instruction is Instruction.TAX:
                    expected_registers = (
                        source,
                        source,
                        initial_registers[2],
                        initial_registers[3],
                    )
                elif instruction is Instruction.TAY:
                    expected_registers = (
                        source,
                        initial_registers[1],
                        source,
                        initial_registers[3],
                    )
                elif instruction is Instruction.TXA:
                    expected_registers = (
                        source,
                        source,
                        initial_registers[2],
                        initial_registers[3],
                    )
                elif instruction is Instruction.TYA:
                    expected_registers = (
                        source,
                        initial_registers[1],
                        source,
                        initial_registers[3],
                    )
                elif instruction is Instruction.TSX:
                    expected_registers = (
                        initial_registers[0],
                        source,
                        initial_registers[2],
                        source,
                    )
                else:
                    expected_registers = (
                        initial_registers[0],
                        source,
                        initial_registers[2],
                        source,
                    )
                assert (model.a, model.x, model.y, model.sp) == expected_registers

                expected_status = (
                    initial_status
                    if instruction is Instruction.TXS
                    else _expected_nz(initial_status, source)
                )
                assert model.status == expected_status
                assert not model.writes

            if instruction in (Instruction.LDA, Instruction.LDX, Instruction.LDY):
                assert not model.writes


def test_exact_directed_vector_count_by_instruction() -> None:
    expected = {
        Instruction.LDA: 48,
        Instruction.LDX: 30,
        Instruction.LDY: 30,
        Instruction.STA: 42,
        Instruction.STX: 18,
        Instruction.STY: 18,
        Instruction.TAX: 6,
        Instruction.TAY: 6,
        Instruction.TXA: 6,
        Instruction.TYA: 6,
        Instruction.TSX: 6,
        Instruction.TXS: 6,
    }
    actual = {
        instruction: sum(
            decoded is instruction for decoded, _mode in EXPECTED_OPCODES.values()
        )
        * len(BOUNDARY_VALUES)
        for instruction in list(Instruction)[1:]
    }
    assert actual == expected
    assert sum(actual.values()) == 222


def test_unsupported_opcode_consumes_one_byte_then_traps() -> None:
    model = CpuPhase2DModel(initial_pc=PROGRAM_START)
    model.a, model.x, model.y, model.sp, model.status = (
        0x12,
        0x34,
        0x56,
        0x78,
        0x6D,
    )
    model.load_program(PROGRAM_START, [0x02, 0xA9, 0xFF])

    assert model.execute_one() is None
    assert model.unsupported
    assert model.pc == PROGRAM_START + 1
    assert (model.a, model.x, model.y, model.sp, model.status) == (
        0x12,
        0x34,
        0x56,
        0x78,
        0x6D,
    )
    assert not model.writes

    assert model.execute_one() is None
    assert model.pc == PROGRAM_START + 1


def test_short_program_lifecycle() -> None:
    model = CpuPhase2DModel(initial_pc=PROGRAM_START)
    model.load_program(
        PROGRAM_START,
        [0xA9, 0x80, 0xAA, 0x8D, 0xFF, 0x7F],
    )

    model.execute_one()  # LDA #$80
    model.execute_one()  # TAX
    model.execute_one()  # STA $7FFF

    assert (model.a, model.x) == (0x80, 0x80)
    assert model.status & 0x82 == 0x80
    assert model.pc == PROGRAM_START + 6
    assert model.writes == [(0x7FFF, 0x80)]


def test_initial_pc_validation() -> None:
    with pytest.raises(ValueError):
        CpuPhase2DModel(initial_pc=-1)
    with pytest.raises(ValueError):
        CpuPhase2DModel(initial_pc=0x10000)
