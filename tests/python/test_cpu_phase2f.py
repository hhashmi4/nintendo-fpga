"""Independent Phase 2F control-flow and stack reference tests."""

from __future__ import annotations

import random
import re
from collections import Counter
from pathlib import Path

import pytest

from verification.cpu import (
    AddressingMode,
    CpuPhase2FModel,
    Instruction,
    OPCODE_TABLE,
    normalize_status,
    status_for_php,
)


PROGRAM_START = 0x8000
BRANCH_RANDOM_SEED = 0x2F_BA_6502
BRANCH_RANDOM_VECTORS = 4096
JSR_RANDOM_SEED = 0x2F_5A_6502
JSR_RANDOM_VECTORS = 1024
STACK_RANDOM_SEED = 0x2F_57_6502
STACK_RANDOM_VECTORS = 1024

PHASE2F_OPCODES = {
    0x4C: (Instruction.JMP, AddressingMode.ABSOLUTE),
    0x6C: (Instruction.JMP, AddressingMode.INDIRECT),
    0x20: (Instruction.JSR, AddressingMode.ABSOLUTE),
    0x60: (Instruction.RTS, AddressingMode.IMPLIED),
    0x90: (Instruction.BCC, AddressingMode.RELATIVE),
    0xB0: (Instruction.BCS, AddressingMode.RELATIVE),
    0xF0: (Instruction.BEQ, AddressingMode.RELATIVE),
    0x30: (Instruction.BMI, AddressingMode.RELATIVE),
    0xD0: (Instruction.BNE, AddressingMode.RELATIVE),
    0x10: (Instruction.BPL, AddressingMode.RELATIVE),
    0x50: (Instruction.BVC, AddressingMode.RELATIVE),
    0x70: (Instruction.BVS, AddressingMode.RELATIVE),
    0x48: (Instruction.PHA, AddressingMode.IMPLIED),
    0x68: (Instruction.PLA, AddressingMode.IMPLIED),
    0x08: (Instruction.PHP, AddressingMode.IMPLIED),
    0x28: (Instruction.PLP, AddressingMode.IMPLIED),
}

BRANCH_CASES = {
    0x90: (0x01, False),  # BCC: C clear
    0xB0: (0x01, True),   # BCS: C set
    0xF0: (0x02, True),   # BEQ: Z set
    0x30: (0x80, True),   # BMI: N set
    0xD0: (0x02, False),  # BNE: Z clear
    0x10: (0x80, False),  # BPL: N clear
    0x50: (0x40, False),  # BVC: V clear
    0x70: (0x40, True),   # BVS: V set
}

BOUNDARY_TARGETS = (
    0x0000,
    0x0001,
    0x00FE,
    0x00FF,
    0x0100,
    0x7FFF,
    0x8000,
    0xFFFE,
    0xFFFF,
)


def _branch_condition(opcode: int, status: int) -> bool:
    mask, sense = BRANCH_CASES[opcode]
    return bool(status & mask) is sense


def test_phase2f_opcode_matrix_matches_rtl() -> None:
    assert len(PHASE2F_OPCODES) == 16
    assert len(OPCODE_TABLE) == 139

    rtl_text = Path("rtl/cpu/cpu_decoder.sv").read_text(encoding="utf-8")
    rtl_opcodes = {int(value, 16) for value in re.findall(r"8'h([0-9A-Fa-f]{2}):", rtl_text)}
    assert rtl_opcodes == set(OPCODE_TABLE)

    for opcode, (instruction, mode) in PHASE2F_OPCODES.items():
        spec = OPCODE_TABLE[opcode]
        assert spec.instruction is instruction
        assert spec.addressing_mode is mode


@pytest.mark.parametrize("opcode", tuple(BRANCH_CASES))
@pytest.mark.parametrize(
    ("start", "offset"),
    (
        (0x1000, 0x00),
        (0x1000, 0x01),
        (0x1000, 0x7F),
        (0x1000, 0x80),
        (0x1000, 0xFB),
        (0x00FC, 0x05),
        (0x0000, 0xFE),
        (0xFFFE, 0x01),
    ),
)
@pytest.mark.parametrize("taken", (False, True))
def test_all_branches_directed(opcode: int, start: int, offset: int, taken: bool) -> None:
    mask, sense = BRANCH_CASES[opcode]
    status = 0x24
    desired_bit = sense if taken else not sense
    status = (status | mask) if desired_bit else (status & ~mask)
    status = normalize_status(status)

    model = CpuPhase2FModel(initial_pc=start, initial_status=status)
    model.load_program(start, [opcode, offset])
    before_status = model.status
    model.execute_one()

    base = (start + 2) & 0xFFFF
    displacement = offset if offset < 0x80 else offset - 0x100
    target = (base + displacement) & 0xFFFF
    assert model.pc == (target if taken else base)
    assert model.status == before_status
    assert model.last_effective_address == target
    assert model.last_page_cross == ((base >> 8) != (target >> 8))
    assert model.last_page_cross_valid
    assert model.writes == []


def test_randomized_branches() -> None:
    rng = random.Random(BRANCH_RANDOM_SEED)
    opcodes = tuple(BRANCH_CASES)
    for _ in range(BRANCH_RANDOM_VECTORS):
        opcode = rng.choice(opcodes)
        start = rng.randrange(0x10000)
        offset = rng.randrange(0x100)
        status = normalize_status(rng.randrange(0x100))
        model = CpuPhase2FModel(initial_pc=start, initial_status=status)
        model.load_program(start, [opcode, offset])
        model.execute_one()

        base = (start + 2) & 0xFFFF
        signed_offset = offset if offset < 0x80 else offset - 0x100
        expected_target = (base + signed_offset) & 0xFFFF
        expected_pc = expected_target if _branch_condition(opcode, status) else base
        assert model.pc == expected_pc
        assert model.status == status


@pytest.mark.parametrize("target", BOUNDARY_TARGETS)
def test_jmp_absolute_directed(target: int) -> None:
    model = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=0xED)
    model.load_program(PROGRAM_START, [0x4C, target & 0xFF, target >> 8])
    before_status = model.status
    model.execute_one()
    assert model.pc == target
    assert model.status == before_status
    assert model.sp == 0xFD
    assert model.writes == []


@pytest.mark.parametrize(
    ("pointer", "high_address", "target"),
    (
        (0x1234, 0x1235, 0x8000),
        (0x12FF, 0x1200, 0xBEEF),
        (0xFFFF, 0xFF00, 0x0001),
    ),
)
def test_jmp_indirect_pointer_bus_addresses(
    pointer: int, high_address: int, target: int
) -> None:
    model = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=0xED)
    model.load_program(PROGRAM_START, [0x6C, pointer & 0xFF, pointer >> 8])
    model.memory[pointer] = target & 0xFF
    model.memory[high_address] = target >> 8
    before_status = model.status
    model.execute_one()
    assert model.pc == target
    assert model.status == before_status
    assert model.writes == []


@pytest.mark.parametrize("sp", (0xFD, 0x00, 0xFF))
@pytest.mark.parametrize("value", (0x00, 0x01, 0x7F, 0x80, 0xFF))
def test_pha_and_pla_stack_semantics(sp: int, value: int) -> None:
    push = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=0xED)
    push.a = value
    push.sp = sp
    push.load_program(PROGRAM_START, [0x48])
    before_status = push.status
    push.execute_one()
    assert push.memory[0x0100 | sp] == value
    assert push.writes == [(0x0100 | sp, value)]
    assert push.sp == ((sp - 1) & 0xFF)
    assert push.status == before_status
    assert push.pc == PROGRAM_START + 1

    pull = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=0x6D)
    pull.sp = sp
    pull.memory[0x0100 | ((sp + 1) & 0xFF)] = value
    pull.load_program(PROGRAM_START, [0x68])
    preserved = pull.status & ~0x82
    pull.execute_one()
    assert pull.a == value
    assert pull.sp == ((sp + 1) & 0xFF)
    assert pull.status & ~0x82 == preserved
    assert bool(pull.status & 0x80) == bool(value & 0x80)
    assert bool(pull.status & 0x02) == (value == 0)
    assert pull.writes == []


def test_php_and_plp_all_status_bytes() -> None:
    for raw_status in range(0x100):
        push = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=raw_status)
        push.load_program(PROGRAM_START, [0x08])
        internal = push.status
        push.execute_one()
        assert push.memory[0x01FD] == status_for_php(raw_status)
        assert push.memory[0x01FD] & 0x30 == 0x30
        assert push.status == internal
        assert push.sp == 0xFC

        pull = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=0x24)
        pull.sp = 0xFC
        pull.memory[0x01FD] = raw_status
        pull.load_program(PROGRAM_START, [0x28])
        pull.execute_one()
        assert pull.status == normalize_status(raw_status)
        assert pull.status & 0x10 == 0
        assert pull.status & 0x20 == 0x20
        assert pull.sp == 0xFD
        assert pull.writes == []


@pytest.mark.parametrize("target", BOUNDARY_TARGETS)
@pytest.mark.parametrize("sp", (0xFD, 0x00, 0xFF))
def test_jsr_return_address_and_push_order(target: int, sp: int) -> None:
    start = 0x7FFE
    model = CpuPhase2FModel(initial_pc=start, initial_status=0xED)
    model.sp = sp
    model.load_program(start, [0x20, target & 0xFF, target >> 8])
    before_status = model.status
    model.execute_one()

    return_address = (start + 2) & 0xFFFF
    assert model.pc == target
    assert model.sp == ((sp - 2) & 0xFF)
    assert model.writes == [
        (0x0100 | sp, return_address >> 8),
        (0x0100 | ((sp - 1) & 0xFF), return_address & 0xFF),
    ]
    assert model.status == before_status


@pytest.mark.parametrize("stored_return", BOUNDARY_TARGETS)
@pytest.mark.parametrize("sp", (0xFB, 0xFE, 0xFF))
def test_rts_pull_order_and_increment(stored_return: int, sp: int) -> None:
    model = CpuPhase2FModel(initial_pc=PROGRAM_START, initial_status=0xED)
    model.sp = sp
    low_address = 0x0100 | ((sp + 1) & 0xFF)
    high_address = 0x0100 | ((sp + 2) & 0xFF)
    model.memory[low_address] = stored_return & 0xFF
    model.memory[high_address] = stored_return >> 8
    model.load_program(PROGRAM_START, [0x60])
    before_status = model.status
    model.execute_one()
    assert model.pc == ((stored_return + 1) & 0xFFFF)
    assert model.sp == ((sp + 2) & 0xFF)
    assert model.status == before_status
    assert model.writes == []


def test_jsr_rts_round_trip() -> None:
    caller = 0x8000
    subroutine = 0x90FF
    model = CpuPhase2FModel(initial_pc=caller, initial_status=0xED)
    model.load_program(caller, [0x20, subroutine & 0xFF, subroutine >> 8])
    model.load_program(subroutine, [0x60])
    model.execute_one()
    assert model.pc == subroutine
    assert model.sp == 0xFB
    model.execute_one()
    assert model.pc == caller + 3
    assert model.sp == 0xFD


def test_randomized_jsr_and_stack_status() -> None:
    jsr_rng = random.Random(JSR_RANDOM_SEED)
    for _ in range(JSR_RANDOM_VECTORS):
        start = jsr_rng.randrange(0x10000)
        target = jsr_rng.randrange(0x10000)
        sp = jsr_rng.randrange(0x100)
        model = CpuPhase2FModel(initial_pc=start)
        model.sp = sp
        model.load_program(start, [0x20, target & 0xFF, target >> 8])
        model.execute_one()
        return_address = (start + 2) & 0xFFFF
        assert model.pc == target
        assert model.writes[0] == (0x0100 | sp, return_address >> 8)
        assert model.writes[1] == (
            0x0100 | ((sp - 1) & 0xFF),
            return_address & 0xFF,
        )

    stack_rng = random.Random(STACK_RANDOM_SEED)
    for _ in range(STACK_RANDOM_VECTORS):
        raw_status = stack_rng.randrange(0x100)
        sp = stack_rng.randrange(0x100)
        model = CpuPhase2FModel(initial_pc=PROGRAM_START)
        model.sp = sp
        model.memory[0x0100 | ((sp + 1) & 0xFF)] = raw_status
        model.load_program(PROGRAM_START, [0x28])
        model.execute_one()
        assert model.status == normalize_status(raw_status)


def test_directed_vector_accounting() -> None:
    counts = Counter(instruction for instruction, _mode in PHASE2F_OPCODES.values())
    assert counts == {
        Instruction.JMP: 2,
        Instruction.JSR: 1,
        Instruction.RTS: 1,
        Instruction.BCC: 1,
        Instruction.BCS: 1,
        Instruction.BEQ: 1,
        Instruction.BMI: 1,
        Instruction.BNE: 1,
        Instruction.BPL: 1,
        Instruction.BVC: 1,
        Instruction.BVS: 1,
        Instruction.PHA: 1,
        Instruction.PLA: 1,
        Instruction.PHP: 1,
        Instruction.PLP: 1,
    }


def test_unsupported_opcode_still_traps_functional_model() -> None:
    model = CpuPhase2FModel(initial_pc=PROGRAM_START)
    model.load_program(PROGRAM_START, [0x00])  # BRK remains Phase 2F-excluded.
    assert model.execute_one() is None
    assert model.unsupported
    assert model.pc == PROGRAM_START + 1
    assert model.writes == []
