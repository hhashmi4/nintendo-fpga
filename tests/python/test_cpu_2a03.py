"""Focused Ricoh 2A03 compatibility audit independent of RTL microstates."""

from pathlib import Path
import re

from verification.cpu import (
    AddressingMode,
    AluOperation,
    CpuPhase2GModel,
    InterruptSource,
    OPCODE_TABLE,
    POST_RESET_SP,
    RESET_STATUS,
    VECTOR_IRQ_LOW,
    generate_address,
    evaluate_alu,
    normalize_status,
    status_for_interrupt,
    status_for_php,
)
from verification.cpu_2a03 import (
    MISSING_OFFICIAL_OPCODES,
    OFFICIAL_NMOS6502_OPCODES,
    UNOFFICIAL_OPCODES,
    NmiEdgeLatch,
    adc_2a03,
    sbc_2a03,
)
from verification.cpu_timing import (
    BusClass,
    CYCLE_TABLE,
    instruction_cycles,
    page_cross,
    reset_trace,
    rmw_tail,
)


PROGRAM = 0x8000
HANDLER = 0x9000


def _set_irq_vector(model: CpuPhase2GModel) -> None:
    model.memory[VECTOR_IRQ_LOW] = HANDLER & 0xFF
    model.memory[VECTOR_IRQ_LOW + 1] = HANDLER >> 8


def test_exhaustive_adc_is_binary_for_both_decimal_flag_states() -> None:
    checks = 0
    for a in range(256):
        for b in range(256):
            for carry in (0, 1):
                d0 = adc_2a03(a, b, carry, decimal=False)
                d1 = adc_2a03(a, b, carry, decimal=True)
                rtl_reference = evaluate_alu(AluOperation.ADD, a, b, carry)
                assert d0 == d1
                assert (
                    d0.result,
                    d0.negative,
                    d0.overflow,
                    d0.zero,
                    d0.carry,
                ) == (
                    rtl_reference.result,
                    rtl_reference.negative,
                    rtl_reference.overflow,
                    rtl_reference.zero,
                    rtl_reference.carry,
                )
                checks += 1
    assert checks == 131_072


def test_exhaustive_sbc_is_binary_for_both_decimal_flag_states() -> None:
    checks = 0
    for a in range(256):
        for b in range(256):
            for carry in (0, 1):
                d0 = sbc_2a03(a, b, carry, decimal=False)
                d1 = sbc_2a03(a, b, carry, decimal=True)
                rtl_reference = evaluate_alu(AluOperation.SUB, a, b, carry)
                assert d0 == d1
                assert (
                    d0.result,
                    d0.negative,
                    d0.overflow,
                    d0.zero,
                    d0.carry,
                ) == (
                    rtl_reference.result,
                    rtl_reference.negative,
                    rtl_reference.overflow,
                    rtl_reference.zero,
                    rtl_reference.carry,
                )
                checks += 1
    assert checks == 131_072


def test_decimal_directed_boundaries_cover_overflow_zero_negative_and_wrap() -> None:
    adc_cases = {
        (0x00, 0x00, 0): (0x00, False, False, True, False),
        (0x7F, 0x01, 0): (0x80, True, True, False, False),
        (0x80, 0x80, 0): (0x00, False, True, True, True),
        (0xFF, 0x01, 0): (0x00, False, False, True, True),
        (0xFF, 0xFF, 1): (0xFF, True, False, False, True),
    }
    sbc_cases = {
        (0x00, 0x00, 1): (0x00, False, False, True, True),
        (0x00, 0x01, 1): (0xFF, True, False, False, False),
        (0x80, 0x01, 1): (0x7F, False, True, False, True),
        (0x7F, 0xFF, 1): (0x80, True, True, False, False),
        (0xFF, 0xFF, 0): (0xFF, True, False, False, False),
    }
    for operands, expected in adc_cases.items():
        for decimal in (False, True):
            result = adc_2a03(*operands, decimal=decimal)
            assert (
                result.result,
                result.negative,
                result.overflow,
                result.zero,
                result.carry,
            ) == expected
    for operands, expected in sbc_cases.items():
        for decimal in (False, True):
            result = sbc_2a03(*operands, decimal=decimal)
            assert (
                result.result,
                result.negative,
                result.overflow,
                result.zero,
                result.carry,
            ) == expected


def test_all_status_bytes_follow_nonpersistent_b_and_forced_u_policy() -> None:
    for raw in range(256):
        internal = normalize_status(raw)
        php_or_brk = status_for_php(raw)
        hardware = status_for_interrupt(raw)
        assert internal & 0x30 == 0x20
        assert php_or_brk & 0x30 == 0x30
        assert hardware & 0x30 == 0x20
        assert (internal ^ raw) & ~0x30 == 0
        assert (php_or_brk ^ raw) & ~0x30 == 0
        assert (hardware ^ raw) & ~0x30 == 0


def test_plp_irq_poll_uses_old_i_but_rti_uses_restored_i() -> None:
    # I=1 -> PLP I=0: one ordinary instruction still executes before IRQ.
    delayed = CpuPhase2GModel(initial_pc=PROGRAM, initial_status=0x24)
    delayed.load_program(PROGRAM, [0x28, 0xAA])  # PLP; TAX
    delayed.memory[0x01FE] = 0x20
    _set_irq_vector(delayed)
    delayed.execute_one()
    delayed.sample_interrupt_inputs(nmi=False, irq=True)
    assert not (delayed.status & 0x04)
    assert delayed.service_pending_interrupt() is InterruptSource.NONE
    assert delayed.execute_one() is not None
    assert delayed.service_pending_interrupt() is InterruptSource.IRQ

    # I=0 -> PLP I=1: the already-completed old-I poll still accepts IRQ.
    admitted = CpuPhase2GModel(initial_pc=PROGRAM, initial_status=0x20)
    admitted.load_program(PROGRAM, [0x28])
    admitted.memory[0x01FE] = 0x24
    _set_irq_vector(admitted)
    admitted.execute_one()
    admitted.sample_interrupt_inputs(nmi=False, irq=True)
    assert admitted.status & 0x04
    assert admitted.service_pending_interrupt() is InterruptSource.IRQ

    # RTI restores I before its final boundary and has no PLP-style delay.
    immediate = CpuPhase2GModel(initial_pc=PROGRAM, initial_status=0x24)
    immediate.load_program(PROGRAM, [0x40])
    immediate.memory[0x01FE] = 0x20
    immediate.memory[0x01FF] = 0x34
    immediate.memory[0x0100] = 0x12
    _set_irq_vector(immediate)
    immediate.execute_one()
    immediate.sample_interrupt_inputs(nmi=False, irq=True)
    assert immediate.pc == 0x1234 and not (immediate.status & 0x04)
    assert immediate.service_pending_interrupt() is InterruptSource.IRQ


def test_nmi_is_one_shot_for_a_held_level_and_rearms_after_a_new_edge() -> None:
    latch = NmiEdgeLatch()
    latch.sample(True)
    assert latch.accept()
    for _ in range(32):
        latch.sample(True)
        assert not latch.accept()
    latch.sample(False)
    latch.sample(True)
    assert latch.accept()


def test_reset_bus_and_architectural_state_match_2a03_policy() -> None:
    trace = reset_trace()
    assert len(trace) == 7
    assert [event.address for event in trace] == [
        0x0000,
        0x0000,
        0x0100,
        0x01FF,
        0x01FE,
        0xFFFC,
        0xFFFD,
    ]
    assert not any(event.write for event in trace)
    assert POST_RESET_SP == 0xFD
    assert RESET_STATUS == 0x24


def test_indirect_jmp_wraps_high_byte_within_pointer_page() -> None:
    unresolved = generate_address(AddressingMode.INDIRECT, base_address=0x12FF)
    assert unresolved.pointer_low_address == 0x12FF
    assert unresolved.pointer_high_address == 0x1200
    resolved = generate_address(
        AddressingMode.INDIRECT,
        base_address=0x12FF,
        pointer_low_byte=0xCD,
        pointer_high_byte=0xAB,
        pointer_data_valid=True,
    )
    assert resolved.effective_address == 0xABCD


def test_every_memory_rmw_opcode_has_nmos_read_double_write_class() -> None:
    rmw_opcodes = {
        opcode
        for opcode, timing in CYCLE_TABLE.items()
        if timing.bus_class is BusClass.RMW
    }
    assert len(rmw_opcodes) == 24
    for opcode in rmw_opcodes:
        trace = rmw_tail(0x2345, opcode, opcode ^ 0xFF)
        assert [(event.write, event.data) for event in trace] == [
            (False, None),
            (True, opcode),
            (True, opcode ^ 0xFF),
        ]


def test_page_cross_penalties_are_restricted_to_read_and_branch_classes() -> None:
    penalty_opcodes = 0
    for opcode, timing in CYCLE_TABLE.items():
        if timing.page_cross_penalty:
            assert timing.bus_class is BusClass.READ
            assert instruction_cycles(opcode, page_cross=True) == timing.base_cycles + 1
            penalty_opcodes += 1
        elif timing.bus_class in {BusClass.WRITE, BusClass.RMW}:
            assert instruction_cycles(opcode, page_cross=True) == timing.base_cycles
    assert penalty_opcodes == 23
    for low in range(256):
        for index in range(256):
            assert page_cross(0xA500 | low, index) is (low + index > 0xFF)


def test_official_opcode_audit_is_complete_after_phase2j() -> None:
    assert len(OFFICIAL_NMOS6502_OPCODES) == 151
    assert len(OPCODE_TABLE) == 151
    assert MISSING_OFFICIAL_OPCODES == set()
    assert set(OPCODE_TABLE) == OFFICIAL_NMOS6502_OPCODES
    assert len(UNOFFICIAL_OPCODES) == 105

    rtl_text = Path("rtl/cpu/cpu_decoder.sv").read_text(encoding="utf-8")
    rtl_opcodes = {
        int(value, 16)
        for value in re.findall(r"8'h([0-9A-Fa-f]{2}):", rtl_text)
    }
    assert rtl_opcodes == set(OPCODE_TABLE)
    assert not (rtl_opcodes & UNOFFICIAL_OPCODES)
