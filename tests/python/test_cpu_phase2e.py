"""Instruction-level reference verification for the Phase 2E subset."""

import random
import re
from pathlib import Path

import pytest

from verification.cpu import (
    OPCODE_TABLE,
    AddressingMode,
    CpuPhase2EModel,
    Instruction,
)


ROOT = Path(__file__).resolve().parents[2]
RTL_DECODER = ROOT / "rtl" / "cpu" / "cpu_decoder.sv"
PROGRAM_START = 0x4000
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
RANDOM_SEED = 0x2E6502
RANDOM_VECTORS_PER_ARITHMETIC_INSTRUCTION = 1024


EXPECTED_PHASE2E = {
    Instruction.ADC: (
        (0x69, AddressingMode.IMMEDIATE),
        (0x65, AddressingMode.ZERO_PAGE),
        (0x75, AddressingMode.ZERO_PAGE_X),
        (0x6D, AddressingMode.ABSOLUTE),
        (0x7D, AddressingMode.ABSOLUTE_X),
        (0x79, AddressingMode.ABSOLUTE_Y),
        (0x61, AddressingMode.INDEXED_INDIRECT_X),
        (0x71, AddressingMode.INDIRECT_INDEXED_Y),
    ),
    Instruction.SBC: (
        (0xE9, AddressingMode.IMMEDIATE),
        (0xE5, AddressingMode.ZERO_PAGE),
        (0xF5, AddressingMode.ZERO_PAGE_X),
        (0xED, AddressingMode.ABSOLUTE),
        (0xFD, AddressingMode.ABSOLUTE_X),
        (0xF9, AddressingMode.ABSOLUTE_Y),
        (0xE1, AddressingMode.INDEXED_INDIRECT_X),
        (0xF1, AddressingMode.INDIRECT_INDEXED_Y),
    ),
    Instruction.AND: (
        (0x29, AddressingMode.IMMEDIATE),
        (0x25, AddressingMode.ZERO_PAGE),
        (0x35, AddressingMode.ZERO_PAGE_X),
        (0x2D, AddressingMode.ABSOLUTE),
        (0x3D, AddressingMode.ABSOLUTE_X),
        (0x39, AddressingMode.ABSOLUTE_Y),
        (0x21, AddressingMode.INDEXED_INDIRECT_X),
        (0x31, AddressingMode.INDIRECT_INDEXED_Y),
    ),
    Instruction.ORA: (
        (0x09, AddressingMode.IMMEDIATE),
        (0x05, AddressingMode.ZERO_PAGE),
        (0x15, AddressingMode.ZERO_PAGE_X),
        (0x0D, AddressingMode.ABSOLUTE),
        (0x1D, AddressingMode.ABSOLUTE_X),
        (0x19, AddressingMode.ABSOLUTE_Y),
        (0x01, AddressingMode.INDEXED_INDIRECT_X),
        (0x11, AddressingMode.INDIRECT_INDEXED_Y),
    ),
    Instruction.EOR: (
        (0x49, AddressingMode.IMMEDIATE),
        (0x45, AddressingMode.ZERO_PAGE),
        (0x55, AddressingMode.ZERO_PAGE_X),
        (0x4D, AddressingMode.ABSOLUTE),
        (0x5D, AddressingMode.ABSOLUTE_X),
        (0x59, AddressingMode.ABSOLUTE_Y),
        (0x41, AddressingMode.INDEXED_INDIRECT_X),
        (0x51, AddressingMode.INDIRECT_INDEXED_Y),
    ),
    Instruction.CMP: (
        (0xC9, AddressingMode.IMMEDIATE),
        (0xC5, AddressingMode.ZERO_PAGE),
        (0xD5, AddressingMode.ZERO_PAGE_X),
        (0xCD, AddressingMode.ABSOLUTE),
        (0xDD, AddressingMode.ABSOLUTE_X),
        (0xD9, AddressingMode.ABSOLUTE_Y),
        (0xC1, AddressingMode.INDEXED_INDIRECT_X),
        (0xD1, AddressingMode.INDIRECT_INDEXED_Y),
    ),
    Instruction.CPX: (
        (0xE0, AddressingMode.IMMEDIATE),
        (0xE4, AddressingMode.ZERO_PAGE),
        (0xEC, AddressingMode.ABSOLUTE),
    ),
    Instruction.CPY: (
        (0xC0, AddressingMode.IMMEDIATE),
        (0xC4, AddressingMode.ZERO_PAGE),
        (0xCC, AddressingMode.ABSOLUTE),
    ),
    Instruction.INX: ((0xE8, AddressingMode.IMPLIED),),
    Instruction.INY: ((0xC8, AddressingMode.IMPLIED),),
    Instruction.DEX: ((0xCA, AddressingMode.IMPLIED),),
    Instruction.DEY: ((0x88, AddressingMode.IMPLIED),),
    Instruction.INC: (
        (0xE6, AddressingMode.ZERO_PAGE),
        (0xF6, AddressingMode.ZERO_PAGE_X),
        (0xEE, AddressingMode.ABSOLUTE),
        (0xFE, AddressingMode.ABSOLUTE_X),
    ),
    Instruction.DEC: (
        (0xC6, AddressingMode.ZERO_PAGE),
        (0xD6, AddressingMode.ZERO_PAGE_X),
        (0xCE, AddressingMode.ABSOLUTE),
        (0xDE, AddressingMode.ABSOLUTE_X),
    ),
    Instruction.ASL: (
        (0x0A, AddressingMode.ACCUMULATOR),
        (0x06, AddressingMode.ZERO_PAGE),
        (0x16, AddressingMode.ZERO_PAGE_X),
        (0x0E, AddressingMode.ABSOLUTE),
        (0x1E, AddressingMode.ABSOLUTE_X),
    ),
    Instruction.LSR: (
        (0x4A, AddressingMode.ACCUMULATOR),
        (0x46, AddressingMode.ZERO_PAGE),
        (0x56, AddressingMode.ZERO_PAGE_X),
        (0x4E, AddressingMode.ABSOLUTE),
        (0x5E, AddressingMode.ABSOLUTE_X),
    ),
    Instruction.ROL: (
        (0x2A, AddressingMode.ACCUMULATOR),
        (0x26, AddressingMode.ZERO_PAGE),
        (0x36, AddressingMode.ZERO_PAGE_X),
        (0x2E, AddressingMode.ABSOLUTE),
        (0x3E, AddressingMode.ABSOLUTE_X),
    ),
    Instruction.ROR: (
        (0x6A, AddressingMode.ACCUMULATOR),
        (0x66, AddressingMode.ZERO_PAGE),
        (0x76, AddressingMode.ZERO_PAGE_X),
        (0x6E, AddressingMode.ABSOLUTE),
        (0x7E, AddressingMode.ABSOLUTE_X),
    ),
}

PHASE2E_OPCODES = {
    opcode: (instruction, mode)
    for instruction, opcode_modes in EXPECTED_PHASE2E.items()
    for opcode, mode in opcode_modes
}


def _operand_bytes(mode: AddressingMode) -> int:
    if mode in (AddressingMode.IMPLIED, AddressingMode.ACCUMULATOR):
        return 0
    if mode in (
        AddressingMode.ABSOLUTE,
        AddressingMode.ABSOLUTE_X,
        AddressingMode.ABSOLUTE_Y,
    ):
        return 2
    return 1


def _replace_flags(
    status: int,
    *,
    negative: bool | None = None,
    overflow: bool | None = None,
    zero: bool | None = None,
    carry: bool | None = None,
) -> int:
    for value, mask in (
        (negative, 0x80),
        (overflow, 0x40),
        (zero, 0x02),
        (carry, 0x01),
    ):
        if value is not None:
            status = (status | mask) if value else (status & ~mask)
    return status


def _install_operand(
    model: CpuPhase2EModel,
    *,
    opcode: int,
    mode: AddressingMode,
    value: int,
    index: int,
    base: int,
    zp_operand: int,
    pointer_target: int,
) -> int | None:
    """Install one instruction and its externally visible operand data."""

    model.x = index
    model.y = index
    target: int | None
    if mode in (AddressingMode.IMPLIED, AddressingMode.ACCUMULATOR):
        target = None
        program = [opcode]
    elif mode is AddressingMode.IMMEDIATE:
        target = None
        program = [opcode, value]
    elif mode is AddressingMode.ZERO_PAGE:
        target = zp_operand
        program = [opcode, zp_operand]
    elif mode is AddressingMode.ZERO_PAGE_X:
        target = (zp_operand + index) & 0xFF
        program = [opcode, zp_operand]
    elif mode is AddressingMode.ABSOLUTE:
        target = base
        program = [opcode, base & 0xFF, base >> 8]
    elif mode is AddressingMode.ABSOLUTE_X:
        target = (base + index) & 0xFFFF
        program = [opcode, base & 0xFF, base >> 8]
    elif mode is AddressingMode.ABSOLUTE_Y:
        target = (base + index) & 0xFFFF
        program = [opcode, base & 0xFF, base >> 8]
    elif mode is AddressingMode.INDEXED_INDIRECT_X:
        target = pointer_target
        pointer_address = (zp_operand + index) & 0xFF
        model.memory[pointer_address] = target & 0xFF
        model.memory[(pointer_address + 1) & 0xFF] = target >> 8
        program = [opcode, zp_operand]
    elif mode is AddressingMode.INDIRECT_INDEXED_Y:
        target = pointer_target
        pointer_base = (target - index) & 0xFFFF
        model.memory[zp_operand] = pointer_base & 0xFF
        model.memory[(zp_operand + 1) & 0xFF] = pointer_base >> 8
        program = [opcode, zp_operand]
    else:
        raise AssertionError(f"unexpected Phase 2E mode {mode}")

    model.load_program(PROGRAM_START, program)
    if target is not None:
        model.memory[target] = value
    return target


def _directed_inputs(
    instruction: Instruction, variant: int
) -> tuple[int, int, int]:
    if instruction is Instruction.ADC:
        return (
            (0x00, 0x00, 0),
            (0x00, 0x00, 1),
            (0x7F, 0x01, 0),
            (0x80, 0x80, 0),
            (0xFF, 0x01, 0),
            (0xFF, 0xFF, 1),
        )[variant]
    if instruction is Instruction.SBC:
        return (
            (0x00, 0x00, 1),
            (0x00, 0x00, 0),
            (0x00, 0x01, 1),
            (0x80, 0x01, 1),
            (0x7F, 0xFF, 1),
            (0xFF, 0xFF, 1),
        )[variant]
    if instruction in (Instruction.CMP, Instruction.CPX, Instruction.CPY):
        return (
            (0x00, 0x01, 0),
            (0x01, 0x01, 1),
            (0x02, 0x01, 0),
            (0x7F, 0x80, 1),
            (0x80, 0x7F, 0),
            (0xFF, 0xFF, 1),
        )[variant]
    return (BOUNDARY_VALUES[(variant + 1) % 6], BOUNDARY_VALUES[variant], variant & 1)


def _expected_operation(
    instruction: Instruction,
    lhs: int,
    operand: int,
    carry_in: int,
) -> tuple[int, dict[str, bool | None]]:
    flags: dict[str, bool | None] = {
        "negative": None,
        "overflow": None,
        "zero": None,
        "carry": None,
    }
    if instruction is Instruction.ADC:
        total = lhs + operand + carry_in
        result = total & 0xFF
        flags["overflow"] = bool((~(lhs ^ operand) & (lhs ^ result)) & 0x80)
        flags["carry"] = total > 0xFF
    elif instruction is Instruction.SBC:
        difference = lhs - operand - (1 - carry_in)
        result = difference & 0xFF
        flags["overflow"] = bool(((lhs ^ operand) & (lhs ^ result)) & 0x80)
        flags["carry"] = difference >= 0
    elif instruction is Instruction.AND:
        result = lhs & operand
    elif instruction is Instruction.ORA:
        result = lhs | operand
    elif instruction is Instruction.EOR:
        result = lhs ^ operand
    elif instruction in (Instruction.CMP, Instruction.CPX, Instruction.CPY):
        result = (lhs - operand) & 0xFF
        flags["carry"] = lhs >= operand
    elif instruction in (Instruction.INX, Instruction.INY, Instruction.INC):
        result = (lhs + 1) & 0xFF
    elif instruction in (Instruction.DEX, Instruction.DEY, Instruction.DEC):
        result = (lhs - 1) & 0xFF
    elif instruction is Instruction.ASL:
        result = (lhs << 1) & 0xFF
        flags["carry"] = bool(lhs & 0x80)
    elif instruction is Instruction.LSR:
        result = lhs >> 1
        flags["carry"] = bool(lhs & 0x01)
    elif instruction is Instruction.ROL:
        result = ((lhs << 1) | carry_in) & 0xFF
        flags["carry"] = bool(lhs & 0x80)
    elif instruction is Instruction.ROR:
        result = (lhs >> 1) | (carry_in << 7)
        flags["carry"] = bool(lhs & 0x01)
    else:
        raise AssertionError(f"no expected semantics for {instruction}")

    flags["negative"] = bool(result & 0x80)
    flags["zero"] = result == 0
    return result, flags


def test_phase2e_opcode_matrix_is_exact_and_matches_rtl() -> None:
    assert len(PHASE2E_OPCODES) == 86
    assert len(OPCODE_TABLE) == 123
    assert 0xEB not in OPCODE_TABLE  # unofficial SBC must remain unsupported

    rtl = RTL_DECODER.read_text(encoding="utf-8")
    rtl_opcodes = {int(value, 16) for value in re.findall(r"8'h([0-9A-F]{2}):", rtl)}
    assert len(rtl_opcodes) == 123
    assert rtl_opcodes == set(OPCODE_TABLE)

    for opcode, (instruction, mode) in PHASE2E_OPCODES.items():
        spec = OPCODE_TABLE[opcode]
        assert (spec.instruction, spec.addressing_mode) == (instruction, mode)
        assert spec.operand_bytes == _operand_bytes(mode)


@pytest.mark.parametrize("instruction", tuple(EXPECTED_PHASE2E))
def test_every_phase2e_opcode_with_six_directed_vectors(
    instruction: Instruction,
) -> None:
    for opcode, mode in EXPECTED_PHASE2E[instruction]:
        for variant in range(6):
            lhs, operand, carry_in = _directed_inputs(instruction, variant)
            model = CpuPhase2EModel(initial_pc=PROGRAM_START)
            model.status = 0x6C | carry_in  # V/U/D/I set; selected C.
            index = BOUNDARY_VALUES[variant]
            target = _install_operand(
                model,
                opcode=opcode,
                mode=mode,
                value=operand,
                index=index,
                base=BOUNDARY_ADDRESSES[(opcode + variant) % 10],
                zp_operand=BOUNDARY_VALUES[(variant + 2) % 6],
                pointer_target=BOUNDARY_ADDRESSES[(variant + 4) % 10],
            )

            if instruction in (
                Instruction.ADC,
                Instruction.SBC,
                Instruction.AND,
                Instruction.ORA,
                Instruction.EOR,
                Instruction.CMP,
            ):
                model.a = lhs
            elif instruction in (Instruction.CPX, Instruction.INX, Instruction.DEX):
                model.x = lhs
            elif instruction in (Instruction.CPY, Instruction.INY, Instruction.DEY):
                model.y = lhs
            elif mode is AddressingMode.ACCUMULATOR:
                model.a = operand

            operation_lhs = (
                operand
                if instruction in (
                    Instruction.INC,
                    Instruction.DEC,
                    Instruction.ASL,
                    Instruction.LSR,
                    Instruction.ROL,
                    Instruction.ROR,
                )
                and mode is not AddressingMode.ACCUMULATOR
                else lhs
            )
            if mode is AddressingMode.ACCUMULATOR:
                operation_lhs = operand

            before = (model.a, model.x, model.y, model.sp, model.status)
            result, flags = _expected_operation(
                instruction, operation_lhs, operand, carry_in
            )
            expected_status = _replace_flags(before[4], **flags)

            spec = model.execute_one()

            assert spec is not None
            assert model.pc == PROGRAM_START + 1 + _operand_bytes(mode)
            assert model.status == expected_status
            assert model.sp == before[3]
            assert not model.unsupported

            if instruction in (
                Instruction.ADC,
                Instruction.SBC,
                Instruction.AND,
                Instruction.ORA,
                Instruction.EOR,
            ):
                assert (model.a, model.x, model.y) == (result, before[1], before[2])
                assert not model.writes
            elif instruction in (Instruction.CMP, Instruction.CPX, Instruction.CPY):
                assert (model.a, model.x, model.y) == before[:3]
                assert not model.writes
            elif instruction in (Instruction.INX, Instruction.DEX):
                assert (model.a, model.x, model.y) == (before[0], result, before[2])
                assert not model.writes
            elif instruction in (Instruction.INY, Instruction.DEY):
                assert (model.a, model.x, model.y) == (before[0], before[1], result)
                assert not model.writes
            elif mode is AddressingMode.ACCUMULATOR:
                assert (model.a, model.x, model.y) == (result, before[1], before[2])
                assert not model.writes
            else:
                assert target is not None
                assert (model.a, model.x, model.y) == before[:3]
                assert model.memory[target] == result
                assert model.writes == [(target, result)]

            if target is not None:
                assert model.last_effective_address == target


def test_exact_directed_vector_count_by_instruction() -> None:
    actual = {
        instruction: len(opcode_modes) * len(BOUNDARY_VALUES)
        for instruction, opcode_modes in EXPECTED_PHASE2E.items()
    }
    assert sum(actual.values()) == 516
    assert actual[Instruction.ADC] == 48
    assert actual[Instruction.SBC] == 48
    assert actual[Instruction.CMP] == 48
    assert actual[Instruction.INC] == 24
    assert actual[Instruction.DEC] == 24
    assert actual[Instruction.ASL] == 30
    assert actual[Instruction.LSR] == 30
    assert actual[Instruction.ROL] == 30
    assert actual[Instruction.ROR] == 30


@pytest.mark.parametrize("instruction", (Instruction.ADC, Instruction.SBC))
def test_randomized_arithmetic_instruction_execution(
    instruction: Instruction,
) -> None:
    rng = random.Random(RANDOM_SEED + int(instruction))
    opcode_modes = EXPECTED_PHASE2E[instruction]

    for _ in range(RANDOM_VECTORS_PER_ARITHMETIC_INSTRUCTION):
        opcode, mode = rng.choice(opcode_modes)
        lhs = rng.randrange(256)
        operand = rng.randrange(256)
        carry_in = rng.randrange(2)
        index = rng.randrange(256)
        base = rng.randrange(0x10000)
        pointer_target = rng.randrange(0x10000)
        if pointer_target in range(PROGRAM_START, PROGRAM_START + 3):
            pointer_target ^= 0x8000

        model = CpuPhase2EModel(initial_pc=PROGRAM_START)
        model.status = (rng.randrange(256) | 0x20) & ~0x10
        model.status = (model.status & ~0x01) | carry_in
        _install_operand(
            model,
            opcode=opcode,
            mode=mode,
            value=operand,
            index=index,
            base=base,
            zp_operand=rng.randrange(256),
            pointer_target=pointer_target,
        )
        model.a = lhs
        before_status = model.status
        result, flags = _expected_operation(instruction, lhs, operand, carry_in)

        model.execute_one()

        assert model.a == result
        assert model.status == _replace_flags(before_status, **flags)
        assert model.pc == PROGRAM_START + 1 + _operand_bytes(mode)
        assert not model.writes


def test_decimal_flag_does_not_change_adc_or_sbc() -> None:
    for opcode in (0x69, 0xE9):
        results = []
        for decimal in (0, 1):
            model = CpuPhase2EModel(initial_pc=PROGRAM_START)
            model.a = 0x79
            model.status = 0x20 | (decimal << 3) | 0x01
            model.load_program(PROGRAM_START, [opcode, 0x01])
            model.execute_one()
            results.append((model.a, model.status & 0xC3))
        assert results[0] == results[1]


@pytest.mark.parametrize("opcode", (0x02, 0xEB, 0xD0, 0x4C, 0x48))
def test_unimplemented_and_unofficial_opcodes_trap(opcode: int) -> None:
    model = CpuPhase2EModel(initial_pc=PROGRAM_START)
    model.load_program(PROGRAM_START, [opcode])
    assert model.execute_one() is None
    assert model.unsupported
    assert model.pc == PROGRAM_START + 1
    assert not model.writes
