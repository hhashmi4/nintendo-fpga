"""Independent Phase 2G reset and interrupt reference verification."""

from __future__ import annotations

import random
import re
from pathlib import Path

import pytest

from verification.cpu import (
    AddressingMode,
    CpuPhase2FModel,
    CpuPhase2GModel,
    Instruction,
    InterruptSource,
    OPCODE_TABLE,
    RESET_A,
    RESET_INSTRUCTION,
    RESET_PC,
    RESET_SP,
    POST_RESET_SP,
    RESET_STATUS,
    RESET_X,
    RESET_Y,
    VECTOR_IRQ_LOW,
    VECTOR_NMI_LOW,
    VECTOR_RESET_LOW,
    normalize_status,
    status_for_interrupt,
    status_for_php,
)


PROGRAM_START = 0x8000
NMI_HANDLER = 0x9000
IRQ_HANDLER = 0xA000
INTERRUPT_RANDOM_SEED = 0x2A03_2601
INTERRUPT_RANDOM_VECTORS = 4096
ROUND_TRIP_RANDOM_SEED = 0x6502_2602
ROUND_TRIP_RANDOM_VECTORS = 2048


def _set_vector(model: CpuPhase2GModel, vector_low: int, target: int) -> None:
    model.memory[vector_low] = target & 0xFF
    model.memory[vector_low + 1] = target >> 8


def _status_without_i(value: int) -> int:
    return normalize_status(value) & ~0x04


def test_phase2g_opcode_matrix_matches_rtl() -> None:
    assert OPCODE_TABLE[0x00].instruction is Instruction.BRK
    assert OPCODE_TABLE[0x00].addressing_mode is AddressingMode.IMPLIED
    assert OPCODE_TABLE[0x40].instruction is Instruction.RTI
    assert OPCODE_TABLE[0x40].addressing_mode is AddressingMode.IMPLIED
    assert len(OPCODE_TABLE) == 151

    rtl_text = Path("rtl/cpu/cpu_decoder.sv").read_text(encoding="utf-8")
    rtl_opcodes = {
        int(value, 16)
        for value in re.findall(r"8'h([0-9A-Fa-f]{2}):", rtl_text)
    }
    assert rtl_opcodes == set(OPCODE_TABLE)


@pytest.mark.parametrize("target", (0x0000, 0x0200, 0x8000, 0xFFFF))
def test_reset_fetches_vector_and_restores_deterministic_state(target: int) -> None:
    model = CpuPhase2GModel(initial_pc=0x3456, initial_status=0xFF)
    model.a, model.x, model.y, model.sp = 1, 2, 3, 4
    model.instruction = 0xEA
    model.unsupported = True
    _set_vector(model, VECTOR_RESET_LOW, target)
    model.reads.clear()

    assert model.reset_from_vector() == target
    assert model.reads == [
        0x0100,
        0x01FF,
        0x01FE,
        VECTOR_RESET_LOW,
        VECTOR_RESET_LOW + 1,
    ]
    assert (model.a, model.x, model.y) == (RESET_A, RESET_X, RESET_Y)
    assert model.sp == POST_RESET_SP
    assert model.status == RESET_STATUS
    assert model.instruction == RESET_INSTRUCTION
    assert not model.unsupported
    assert model.writes == []


@pytest.mark.parametrize("sp", (0x00, 0x01, 0x02, 0xFD, 0xFE, 0xFF))
@pytest.mark.parametrize("source", (InterruptSource.NMI, InterruptSource.IRQ))
def test_hardware_interrupt_stack_and_vector_order(
    sp: int, source: InterruptSource
) -> None:
    status = _status_without_i(0xCB)
    model = CpuPhase2GModel(initial_pc=0x7FFF, initial_status=status)
    model.sp = sp
    _set_vector(model, VECTOR_NMI_LOW, NMI_HANDLER)
    _set_vector(model, VECTOR_IRQ_LOW, IRQ_HANDLER)
    model.reads.clear()
    if source is InterruptSource.NMI:
        model.sample_interrupt_inputs(nmi=True, irq=False)
        expected_vector = VECTOR_NMI_LOW
        expected_pc = NMI_HANDLER
    else:
        model.sample_interrupt_inputs(nmi=False, irq=True)
        expected_vector = VECTOR_IRQ_LOW
        expected_pc = IRQ_HANDLER

    assert model.service_pending_interrupt() is source
    assert model.pc == expected_pc
    assert model.sp == ((sp - 3) & 0xFF)
    assert model.writes == [
        (0x0100 | sp, 0x7F),
        (0x0100 | ((sp - 1) & 0xFF), 0xFF),
        (0x0100 | ((sp - 2) & 0xFF), status_for_interrupt(status)),
    ]
    assert model.reads == [expected_vector, expected_vector + 1]
    assert model.status & 0x04


def test_irq_masking_and_acceptance_after_i_clears() -> None:
    model = CpuPhase2GModel(initial_pc=PROGRAM_START, initial_status=0x24)
    _set_vector(model, VECTOR_IRQ_LOW, IRQ_HANDLER)
    model.sample_interrupt_inputs(nmi=False, irq=True)
    assert model.service_pending_interrupt() is InterruptSource.NONE
    assert model.pc == PROGRAM_START
    assert model.writes == []

    model.status &= ~0x04
    assert model.service_pending_interrupt() is InterruptSource.IRQ
    assert model.pc == IRQ_HANDLER


def test_nmi_is_edge_latched_not_retriggered_by_held_level() -> None:
    model = CpuPhase2GModel(initial_pc=PROGRAM_START)
    _set_vector(model, VECTOR_NMI_LOW, NMI_HANDLER)
    model.sample_interrupt_inputs(nmi=True, irq=False)
    assert model.service_pending_interrupt() is InterruptSource.NMI

    model.pc = 0x8123
    model.sample_interrupt_inputs(nmi=True, irq=False)
    assert model.service_pending_interrupt() is InterruptSource.NONE

    model.sample_interrupt_inputs(nmi=False, irq=False)
    model.sample_interrupt_inputs(nmi=True, irq=False)
    assert model.service_pending_interrupt() is InterruptSource.NMI


def test_nmi_priority_then_pending_level_irq_after_rti() -> None:
    status = _status_without_i(0xC9)
    model = CpuPhase2GModel(initial_pc=PROGRAM_START, initial_status=status)
    _set_vector(model, VECTOR_NMI_LOW, NMI_HANDLER)
    _set_vector(model, VECTOR_IRQ_LOW, IRQ_HANDLER)
    model.memory[NMI_HANDLER] = 0x40
    model.sample_interrupt_inputs(nmi=True, irq=True)

    assert model.service_pending_interrupt() is InterruptSource.NMI
    assert model.pc == NMI_HANDLER
    assert model.service_pending_interrupt() is InterruptSource.NONE
    model.execute_one()  # RTI restores the pre-NMI I=0 status.
    assert model.pc == PROGRAM_START
    assert not (model.status & 0x04)
    assert model.service_pending_interrupt() is InterruptSource.IRQ
    assert model.pc == IRQ_HANDLER


def test_all_status_bytes_have_explicit_b_u_stack_policy() -> None:
    for raw_status in range(0x100):
        normalized = normalize_status(raw_status)
        assert status_for_interrupt(raw_status) == normalized
        assert status_for_interrupt(raw_status) & 0x30 == 0x20
        assert status_for_php(raw_status) & 0x30 == 0x30

        model = CpuPhase2GModel(initial_pc=PROGRAM_START, initial_status=raw_status)
        model.sp = 0xFD
        _set_vector(model, VECTOR_NMI_LOW, NMI_HANDLER)
        model.sample_interrupt_inputs(nmi=True, irq=False)
        model.service_pending_interrupt()
        assert model.memory[0x01FB] == normalized


@pytest.mark.parametrize("sp", (0x00, 0x01, 0x02, 0xFD, 0xFE, 0xFF))
@pytest.mark.parametrize("status", (0x00, 0x01, 0x04, 0x08, 0x40, 0x80, 0xCB, 0xFF))
def test_brk_pc_status_and_rti_round_trip(sp: int, status: int) -> None:
    start = 0x80FE
    internal_status = normalize_status(status)
    model = CpuPhase2GModel(initial_pc=start, initial_status=status)
    model.sp = sp
    model.load_program(start, [0x00, 0xA5])
    _set_vector(model, VECTOR_IRQ_LOW, IRQ_HANDLER)
    model.memory[IRQ_HANDLER] = 0x40
    model.reads.clear()

    spec = model.execute_one()
    assert spec is not None and spec.instruction is Instruction.BRK
    return_pc = (start + 2) & 0xFFFF
    assert model.pc == IRQ_HANDLER
    assert model.sp == ((sp - 3) & 0xFF)
    assert model.writes == [
        (0x0100 | sp, return_pc >> 8),
        (0x0100 | ((sp - 1) & 0xFF), return_pc & 0xFF),
        (0x0100 | ((sp - 2) & 0xFF), status_for_php(internal_status)),
    ]
    assert model.reads == [start, start + 1, VECTOR_IRQ_LOW, VECTOR_IRQ_LOW + 1]

    model.execute_one()
    assert model.pc == return_pc
    assert model.sp == sp
    assert model.status == internal_status


@pytest.mark.parametrize("pc", (0x0000, 0x0001, 0x7FFF, 0x8000, 0xFFFF))
@pytest.mark.parametrize("sp", (0x00, 0xFD, 0xFF))
def test_hardware_interrupt_rti_round_trip_has_no_increment(pc: int, sp: int) -> None:
    status = _status_without_i(0xCB)
    model = CpuPhase2GModel(initial_pc=pc, initial_status=status)
    model.sp = sp
    _set_vector(model, VECTOR_NMI_LOW, NMI_HANDLER)
    model.memory[NMI_HANDLER] = 0x40
    model.sample_interrupt_inputs(nmi=True, irq=False)
    model.service_pending_interrupt()
    model.execute_one()
    assert model.pc == pc
    assert model.sp == sp
    assert model.status == status


def test_randomized_interrupt_entry_and_round_trips() -> None:
    rng = random.Random(INTERRUPT_RANDOM_SEED)
    for _ in range(INTERRUPT_RANDOM_VECTORS):
        pc = rng.randrange(0x10000)
        sp = rng.randrange(0x100)
        status = _status_without_i(rng.randrange(0x100))
        nmi = bool(rng.getrandbits(1))
        irq = bool(rng.getrandbits(1))
        if not nmi and not irq:
            irq = True
        nmi_vector = rng.randrange(0x10000)
        irq_vector = rng.randrange(0x10000)
        model = CpuPhase2GModel(initial_pc=pc, initial_status=status)
        model.sp = sp
        _set_vector(model, VECTOR_NMI_LOW, nmi_vector)
        _set_vector(model, VECTOR_IRQ_LOW, irq_vector)
        model.sample_interrupt_inputs(nmi=nmi, irq=irq)
        source = model.service_pending_interrupt()
        expected_source = InterruptSource.NMI if nmi else InterruptSource.IRQ
        assert source is expected_source
        assert model.pc == (nmi_vector if nmi else irq_vector)
        assert model.sp == ((sp - 3) & 0xFF)
        assert model.memory[0x0100 | sp] == pc >> 8
        assert model.memory[0x0100 | ((sp - 1) & 0xFF)] == (pc & 0xFF)
        assert model.memory[0x0100 | ((sp - 2) & 0xFF)] == status

    round_trip_rng = random.Random(ROUND_TRIP_RANDOM_SEED)
    for _ in range(ROUND_TRIP_RANDOM_VECTORS):
        pc = round_trip_rng.randrange(0x10000)
        sp = round_trip_rng.randrange(0x100)
        status = _status_without_i(round_trip_rng.randrange(0x100))
        handler = round_trip_rng.randrange(0x10000)
        model = CpuPhase2GModel(initial_pc=pc, initial_status=status)
        model.sp = sp
        _set_vector(model, VECTOR_NMI_LOW, handler)
        model.memory[handler] = 0x40
        model.sample_interrupt_inputs(nmi=True, irq=False)
        model.service_pending_interrupt()
        model.execute_one()
        assert (model.pc, model.sp, model.status) == (pc, sp, status)


def test_phase2f_boundary_still_rejects_brk_and_rti() -> None:
    for opcode in (0x00, 0x40):
        model = CpuPhase2FModel(initial_pc=PROGRAM_START)
        model.load_program(PROGRAM_START, [opcode])
        assert model.execute_one() is None
        assert model.unsupported
        assert model.writes == []


def test_reference_constants_are_intentionally_fixed() -> None:
    assert (RESET_A, RESET_X, RESET_Y) == (0, 0, 0)
    assert (RESET_SP, POST_RESET_SP, RESET_PC, RESET_STATUS, RESET_INSTRUCTION) == (
        0x00,
        0xFD,
        0x0000,
        0x24,
        0x00,
    )
    assert (VECTOR_NMI_LOW, VECTOR_RESET_LOW, VECTOR_IRQ_LOW) == (
        0xFFFA,
        0xFFFC,
        0xFFFE,
    )
