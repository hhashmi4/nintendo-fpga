"""Final official-opcode and Phase 2J qualification tests."""

import json
from pathlib import Path
import random
import re

from verification.cpu import (
    AddressingMode,
    CpuPhase2JModel,
    Instruction,
    InterruptSource,
    OPCODE_TABLE,
    VECTOR_IRQ_LOW,
    VECTOR_NMI_LOW,
    normalize_status,
)
from verification.cpu_2a03 import (
    OFFICIAL_NMOS6502_OPCODES,
    UNOFFICIAL_OPCODES,
)
from verification.cpu_coverage import OFFICIAL_OPCODE_COVERAGE
from verification.cpu_timing import BusClass, CYCLE_TABLE, instruction_cycles


ROOT = Path(__file__).resolve().parents[2]
START = 0x8000
HANDLER = 0x9000
RANDOM_SEED = 0x2A03_2A0A
RANDOM_VECTORS = 20_000
FULL_OPCODE_RANDOM_SEED = 0x2A03_1510
FULL_OPCODE_VECTORS_PER_BYTE = 32


def _run(model: CpuPhase2JModel, count: int) -> None:
    for _ in range(count):
        assert model.execute_one() is not None
        assert not model.unsupported


def test_all_151_official_bytes_and_only_them_decode_in_python_and_rtl() -> None:
    assert len(Instruction) - 1 == 56
    assert len(OPCODE_TABLE) == 151
    assert set(OPCODE_TABLE) == OFFICIAL_NMOS6502_OPCODES
    assert len(UNOFFICIAL_OPCODES) == 105

    rtl = (ROOT / "rtl/cpu/cpu_decoder.sv").read_text(encoding="utf-8")
    rtl_opcodes = {
        int(value, 16) for value in re.findall(r"8'h([0-9A-Fa-f]{2}):", rtl)
    }
    assert rtl_opcodes == OFFICIAL_NMOS6502_OPCODES
    assert not rtl_opcodes & UNOFFICIAL_OPCODES


def test_machine_readable_official_matrix_is_complete_and_reproducible() -> None:
    report_path = ROOT / "docs/cpu-official-opcodes.json"
    committed = json.loads(report_path.read_text(encoding="utf-8"))
    assert committed == OFFICIAL_OPCODE_COVERAGE
    assert len(committed) == 151
    assert {int(row["opcode"], 16) for row in committed} == OFFICIAL_NMOS6502_OPCODES
    assert all(row["implementation_status"] == "implemented" for row in committed)
    assert all(row["test_status"] == "qualified" for row in committed)
    assert all(1 <= row["bytes"] <= 3 for row in committed)
    assert all(2 <= row["base_cycles"] <= 7 for row in committed)


def test_completed_opcode_decode_modes_and_timing() -> None:
    expected = {
        0x24: (Instruction.BIT, AddressingMode.ZERO_PAGE, 2, 3, BusClass.READ),
        0x2C: (Instruction.BIT, AddressingMode.ABSOLUTE, 3, 4, BusClass.READ),
        0x18: (Instruction.CLC, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0x38: (Instruction.SEC, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0x58: (Instruction.CLI, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0x78: (Instruction.SEI, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0xB8: (Instruction.CLV, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0xD8: (Instruction.CLD, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0xF8: (Instruction.SED, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
        0xEA: (Instruction.NOP, AddressingMode.IMPLIED, 1, 2, BusClass.IMPLIED),
    }
    for opcode, (instruction, mode, length, cycles, bus_class) in expected.items():
        decoded = OPCODE_TABLE[opcode]
        timing = CYCLE_TABLE[opcode]
        assert decoded.instruction is instruction
        assert decoded.addressing_mode is mode
        assert decoded.operand_bytes + 1 == length
        assert timing.base_cycles == cycles
        assert timing.bus_class is bus_class
        assert timing.page_cross_penalty == 0
        assert instruction_cycles(opcode, page_cross=True) == cycles


def test_exhaustive_bit_flag_truth_table() -> None:
    checks = 0
    for accumulator in range(256):
        for operand in range(256):
            original = 0x2D
            expected = (original & ~0xC2) | (operand & 0xC0)
            if (accumulator & operand) == 0:
                expected |= 0x02
            assert expected & 0xC0 == operand & 0xC0
            assert bool(expected & 0x02) is ((accumulator & operand) == 0)
            assert expected & 0x2D == original & 0x2D
            checks += 1
    assert checks == 65_536


def test_bit_zp_and_absolute_execute_without_register_or_unowned_flag_changes() -> None:
    values = (0x00, 0x01, 0x3F, 0x40, 0x80, 0xFF)
    vectors = 0
    for opcode, operand_bytes in ((0x24, [0x80]), (0x2C, [0x80, 0x20])):
        for accumulator in values:
            for operand in values:
                model = CpuPhase2JModel(initial_pc=START, initial_status=0x2D)
                model.a, model.x, model.y = accumulator, 0x5A, 0xA5
                model.load_program(START, [opcode, *operand_bytes])
                model.memory[0x2080 if opcode == 0x2C else 0x0080] = operand
                before = (model.a, model.x, model.y, model.sp, model.status)
                model.execute_one()
                expected = (before[4] & ~0xC2) | (operand & 0xC0)
                if (accumulator & operand) == 0:
                    expected |= 0x02
                assert (model.a, model.x, model.y, model.sp) == before[:4]
                assert model.status == normalize_status(expected)
                assert model.pc == START + len(operand_bytes) + 1
                assert model.writes == []
                vectors += 1
    assert vectors == 72


def test_all_status_inputs_for_flag_controls_and_official_nop() -> None:
    operations = {
        0x18: (0x01, False),
        0x38: (0x01, True),
        0x58: (0x04, False),
        0x78: (0x04, True),
        0xB8: (0x40, False),
        0xD8: (0x08, False),
        0xF8: (0x08, True),
        0xEA: (0x00, False),
    }
    vectors = 0
    for opcode, (mask, set_bit) in operations.items():
        for raw_status in range(256):
            model = CpuPhase2JModel(initial_pc=START, initial_status=raw_status)
            model.load_program(START, [opcode])
            before = model.status
            model.execute_one()
            expected = before | mask if set_bit else before & ~mask
            assert model.status == normalize_status(expected)
            assert (model.a, model.x, model.y, model.sp) == (0, 0, 0, 0xFD)
            assert model.pc == START + 1 and model.writes == []
            vectors += 1
    assert vectors == 2_048


def test_cli_and_sei_interrupt_poll_with_old_i() -> None:
    # CLI clears I architecturally, but the immediately following poll uses
    # old I=1. One NOP executes before the asserted IRQ is admitted.
    cli = CpuPhase2JModel(initial_pc=START, initial_status=0x24)
    cli.load_program(START, [0x58, 0xEA])
    cli.memory[VECTOR_IRQ_LOW] = HANDLER & 0xFF
    cli.memory[VECTOR_IRQ_LOW + 1] = HANDLER >> 8
    cli.execute_one()
    cli.sample_interrupt_inputs(nmi=False, irq=True)
    assert not (cli.status & 0x04)
    assert cli.service_pending_interrupt() is InterruptSource.NONE
    cli.execute_one()
    assert cli.service_pending_interrupt() is InterruptSource.IRQ

    # SEI sets I architecturally, but the following poll uses old I=0 and
    # admits an IRQ already sampled during the instruction.
    sei = CpuPhase2JModel(initial_pc=START, initial_status=0x20)
    sei.load_program(START, [0x78])
    sei.memory[VECTOR_IRQ_LOW] = HANDLER & 0xFF
    sei.memory[VECTOR_IRQ_LOW + 1] = HANDLER >> 8
    sei.execute_one()
    sei.sample_interrupt_inputs(nmi=False, irq=True)
    assert sei.status & 0x04
    assert sei.service_pending_interrupt() is InterruptSource.IRQ


def test_sed_and_cld_wrap_binary_adc_sbc_without_decimal_adjustment() -> None:
    model = CpuPhase2JModel(initial_pc=START)
    model.load_program(
        START,
        [
            0xF8,             # SED
            0x18,             # CLC
            0xA9, 0x49,       # LDA #$49
            0x69, 0x51,       # ADC #$51 => $9A, not BCD $00
            0x38,             # SEC
            0xE9, 0x01,       # SBC #$01 => $99
            0xD8,             # CLD
        ],
    )
    _run(model, 4)
    assert model.a == 0x9A and model.status & 0x08
    _run(model, 2)
    assert model.a == 0x99 and model.status & 0x08
    _run(model, 1)
    assert not model.status & 0x08


def test_all_105_unofficial_bytes_retain_deterministic_trap_policy() -> None:
    for opcode in UNOFFICIAL_OPCODES:
        model = CpuPhase2JModel(initial_pc=START)
        model.load_program(START, [opcode])
        assert model.execute_one() is None
        assert model.unsupported
        assert model.pc == START + 1
        assert model.writes == []


def test_deterministic_randomized_completed_instruction_vectors() -> None:
    rng = random.Random(RANDOM_SEED)
    opcodes = (0x18, 0x24, 0x2C, 0x38, 0x58, 0x78, 0xB8, 0xD8, 0xEA, 0xF8)
    counts = {opcode: 0 for opcode in opcodes}
    for _ in range(RANDOM_VECTORS):
        opcode = rng.choice(opcodes)
        accumulator = rng.randrange(256)
        raw_status = rng.randrange(256)
        operand = rng.randrange(256)
        model = CpuPhase2JModel(initial_pc=START, initial_status=raw_status)
        model.a = accumulator
        if opcode == 0x24:
            model.load_program(START, [opcode, 0x80])
            model.memory[0x0080] = operand
        elif opcode == 0x2C:
            model.load_program(START, [opcode, 0x80, 0x20])
            model.memory[0x2080] = operand
        else:
            model.load_program(START, [opcode])
        before = (model.a, model.x, model.y, model.sp, model.status)
        spec = model.execute_one()
        assert spec is not None and not model.unsupported and model.writes == []
        assert (model.a, model.x, model.y, model.sp) == before[:4]
        if opcode in (0x24, 0x2C):
            expected = (before[4] & ~0xC2) | (operand & 0xC0)
            if (accumulator & operand) == 0:
                expected |= 0x02
            assert model.status == normalize_status(expected)
        counts[opcode] += 1
    assert sum(counts.values()) == RANDOM_VECTORS
    assert all(counts[opcode] > 1_800 for opcode in opcodes)


def test_every_official_opcode_executes_from_randomized_architectural_state() -> None:
    """Smoke every official byte under varied state and flat-memory contents."""

    rng = random.Random(FULL_OPCODE_RANDOM_SEED)
    vectors = 0
    for opcode in sorted(OFFICIAL_NMOS6502_OPCODES):
        for _ in range(FULL_OPCODE_VECTORS_PER_BYTE):
            operand_low = rng.randrange(256)
            operand_high = rng.randrange(256)
            model = CpuPhase2JModel(
                initial_pc=START,
                initial_status=rng.randrange(256),
            )
            model.a = rng.randrange(256)
            model.x = rng.randrange(256)
            model.y = rng.randrange(256)
            model.sp = rng.randrange(256)

            absolute = operand_low | (operand_high << 8)
            candidate_addresses = {
                operand_low,
                (operand_low + model.x) & 0xFF,
                (operand_low + model.y) & 0xFF,
                absolute,
                (absolute + model.x) & 0xFFFF,
                (absolute + model.y) & 0xFFFF,
                0x0100 | model.sp,
                0x0100 | ((model.sp + 1) & 0xFF),
                VECTOR_NMI_LOW,
                VECTOR_NMI_LOW + 1,
                VECTOR_IRQ_LOW,
                VECTOR_IRQ_LOW + 1,
            }
            for address in candidate_addresses:
                model.memory[address] = rng.randrange(256)
            for _ in range(8):
                model.memory[rng.randrange(0x10000)] = rng.randrange(256)
            model.load_program(START, [opcode, operand_low, operand_high])

            spec = model.execute_one()
            assert spec is not None and not model.unsupported
            assert all(0 <= value <= 0xFF for value in (
                model.a, model.x, model.y, model.sp, model.status
            ))
            assert 0 <= model.pc <= 0xFFFF
            assert model.status == normalize_status(model.status)
            assert all(
                0 <= address <= 0xFFFF and 0 <= value <= 0xFF
                for address, value in model.writes
            )
            vectors += 1

    assert vectors == 151 * FULL_OPCODE_VECTORS_PER_BYTE == 4_832


def test_ten_multi_instruction_interaction_programs() -> None:
    completed = 0

    # 1: arithmetic chain; 2: compare plus branch.
    arithmetic = CpuPhase2JModel(initial_pc=START)
    arithmetic.load_program(START, [0x18, 0xA9, 0x7F, 0x69, 0x01, 0xE9, 0x01])
    _run(arithmetic, 4)
    assert arithmetic.a == 0x7E  # SBC consumes C=0 as an incoming borrow.
    completed += 1
    compare = CpuPhase2JModel(initial_pc=START)
    compare.load_program(START, [0xA9, 0x44, 0xC9, 0x44, 0xF0, 0x02, 0xA9, 0x00, 0xEA])
    _run(compare, 4)
    assert compare.a == 0x44 and compare.pc == START + 9
    completed += 1

    # 3: nested JSR/RTS.
    calls = CpuPhase2JModel(initial_pc=START)
    calls.load_program(START, [0x20, 0x10, 0x80, 0xEA])
    calls.load_program(0x8010, [0x20, 0x20, 0x80, 0x60])
    calls.load_program(0x8020, [0xE8, 0x60])
    _run(calls, 6)
    assert calls.x == 1 and calls.pc == START + 4 and calls.sp == 0xFD
    completed += 1

    # 4: stack values; 5: BIT plus branch; 6: flag set/clear sequence.
    stack = CpuPhase2JModel(initial_pc=START)
    stack.load_program(START, [0xA9, 0x80, 0x48, 0xA9, 0x00, 0x68])
    _run(stack, 4)
    assert stack.a == 0x80 and stack.status & 0x80 and stack.sp == 0xFD
    completed += 1
    bit_branch = CpuPhase2JModel(initial_pc=START)
    bit_branch.load_program(START, [0xA9, 0x40, 0x24, 0x10, 0x70, 0x02, 0xA9, 0x00, 0xEA])
    bit_branch.memory[0x10] = 0x40
    _run(bit_branch, 4)
    assert bit_branch.a == 0x40 and bit_branch.pc == START + 9
    completed += 1
    flags = CpuPhase2JModel(initial_pc=START)
    flags.load_program(START, [0x38, 0xF8, 0x78, 0x18, 0xD8, 0x58, 0xB8])
    _run(flags, 7)
    assert flags.status == 0x20
    completed += 1

    # 7: D-wrapped binary arithmetic; 8: RMW then load/branch.
    decimal = CpuPhase2JModel(initial_pc=START)
    decimal.load_program(START, [0xF8, 0x18, 0xA9, 0x49, 0x69, 0x51, 0xD8])
    _run(decimal, 5)
    assert decimal.a == 0x9A and not decimal.status & 0x08
    completed += 1
    rmw = CpuPhase2JModel(initial_pc=START)
    rmw.memory[0x10] = 0xFF
    rmw.load_program(START, [0xE6, 0x10, 0xA5, 0x10, 0xF0, 0x01, 0xEA, 0xEA])
    _run(rmw, 4)
    assert rmw.memory[0x10] == 0 and rmw.a == 0 and rmw.pc == START + 8
    completed += 1

    # 9: BRK/RTI round trip; 10: IRQ/RTI round trip.
    brk = CpuPhase2JModel(initial_pc=START)
    brk.load_program(START, [0x00, 0xEA, 0xEA])
    brk.load_program(HANDLER, [0x40])
    brk.memory[VECTOR_IRQ_LOW] = HANDLER & 0xFF
    brk.memory[VECTOR_IRQ_LOW + 1] = HANDLER >> 8
    _run(brk, 2)
    assert brk.pc == START + 2 and brk.sp == 0xFD
    completed += 1
    irq = CpuPhase2JModel(initial_pc=START, initial_status=0x20)
    irq.load_program(HANDLER, [0x40])
    irq.memory[VECTOR_IRQ_LOW] = HANDLER & 0xFF
    irq.memory[VECTOR_IRQ_LOW + 1] = HANDLER >> 8
    irq.sample_interrupt_inputs(nmi=False, irq=True)
    assert irq.service_pending_interrupt() is InterruptSource.IRQ
    _run(irq, 1)
    assert irq.pc == START and irq.sp == 0xFD
    completed += 1

    assert completed == 10


def test_nmi_round_trip_remains_available_to_completed_model() -> None:
    model = CpuPhase2JModel(initial_pc=START)
    model.load_program(HANDLER, [0x40])
    model.memory[VECTOR_NMI_LOW] = HANDLER & 0xFF
    model.memory[VECTOR_NMI_LOW + 1] = HANDLER >> 8
    model.sample_interrupt_inputs(nmi=True, irq=False)
    assert model.service_pending_interrupt() is InterruptSource.NMI
    _run(model, 1)
    assert model.pc == START and model.sp == 0xFD
