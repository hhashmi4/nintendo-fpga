import random

from verification.cpu import AddressingMode, BRANCH_INSTRUCTIONS, OPCODE_TABLE
from verification.cpu_timing import (
    BusClass,
    CYCLE_TABLE,
    absolute_indexed_trace,
    branch_trace,
    hardware_interrupt_trace,
    instruction_cycles,
    page_cross,
    reset_trace,
    rmw_tail,
)


def test_cycle_table_covers_every_implemented_official_opcode() -> None:
    assert len(OPCODE_TABLE) == 151
    assert set(CYCLE_TABLE) == set(OPCODE_TABLE)
    for opcode, timing in CYCLE_TABLE.items():
        decoded = OPCODE_TABLE[opcode]
        assert timing.opcode == opcode
        assert timing.mnemonic == decoded.instruction.name
        assert timing.addressing_mode is decoded.addressing_mode
        assert 2 <= timing.base_cycles <= 7


def test_canonical_fixed_cycle_classes() -> None:
    expected = {
        0xA9: 2,  # LDA immediate
        0xA5: 3,  # LDA zp
        0xB5: 4,  # LDA zp,X
        0xAD: 4,  # LDA abs
        0xA1: 6,  # LDA (zp,X)
        0x85: 3,  # STA zp
        0x9D: 5,  # STA abs,X, fixed even without a crossing
        0x91: 6,  # STA (zp),Y, fixed
        0xE6: 5,  # INC zp
        0xF6: 6,  # INC zp,X
        0xEE: 6,  # INC abs
        0xFE: 7,  # INC abs,X
        0x4C: 3,
        0x6C: 5,
        0x20: 6,
        0x60: 6,
        0x48: 3,
        0x68: 4,
        0x00: 7,
        0x40: 6,
    }
    assert {opcode: CYCLE_TABLE[opcode].base_cycles for opcode in expected} == expected


def test_exhaustive_indexed_low_byte_page_cross_relationships() -> None:
    checks = 0
    penalty_opcodes = [
        opcode
        for opcode, timing in CYCLE_TABLE.items()
        if timing.page_cross_penalty
    ]
    assert len(penalty_opcodes) == 23
    for low in range(256):
        for index in range(256):
            crossing = low + index > 0xFF
            assert page_cross(0xA500 | low, index) is crossing
            for opcode in penalty_opcodes:
                assert instruction_cycles(opcode, page_cross=crossing) == (
                    CYCLE_TABLE[opcode].base_cycles + int(crossing)
                )
            checks += 1
    assert checks == 65_536


def test_stores_and_rmw_never_inherit_read_page_penalty() -> None:
    for opcode, timing in CYCLE_TABLE.items():
        if timing.bus_class in {BusClass.WRITE, BusClass.RMW}:
            assert timing.page_cross_penalty == 0
            assert instruction_cycles(opcode, page_cross=True) == timing.base_cycles


def test_exhaustive_branch_low_byte_offset_and_taken_matrix() -> None:
    branch_opcodes = [
        opcode
        for opcode, decoded in OPCODE_TABLE.items()
        if decoded.instruction in BRANCH_INSTRUCTIONS
    ]
    assert len(branch_opcodes) == 8
    relationships = 0
    for pc_low in range(256):
        opcode_pc = 0x8000 | pc_low
        for offset in range(256):
            not_taken = branch_trace(opcode_pc, offset, taken=False)
            taken = branch_trace(opcode_pc, offset, taken=True)
            base = (opcode_pc + 2) & 0xFFFF
            signed = offset if offset < 0x80 else offset - 0x100
            target = (base + signed) & 0xFFFF
            crossing = (base >> 8) != (target >> 8)
            assert len(not_taken) == 2
            assert len(taken) == 3 + int(crossing)
            for opcode in branch_opcodes:
                assert instruction_cycles(opcode, branch_taken=False) == 2
                assert instruction_cycles(
                    opcode, branch_taken=True, page_cross=crossing
                ) == len(taken)
            relationships += 1
    assert relationships == 65_536


def test_indexed_read_and_store_tentative_bus_addresses() -> None:
    no_cross = absolute_indexed_trace(0x8000, 0x1200, 1)
    crossing = absolute_indexed_trace(0x8000, 0x12FF, 1)
    store = absolute_indexed_trace(0x8000, 0x12FF, 1, write_data=0x5A)
    assert [event.address for event in no_cross] == [0x8000, 0x8001, 0x8002, 0x1201]
    assert [event.address for event in crossing] == [0x8000, 0x8001, 0x8002, 0x1200, 0x1300]
    assert [event.address for event in store] == [0x8000, 0x8001, 0x8002, 0x1200, 0x1300]
    assert not store[-2].write and store[-1].write and store[-1].data == 0x5A


def test_nmos_rmw_has_original_and_modified_writes() -> None:
    trace = rmw_tail(0x2345, 0x7F, 0x80)
    assert [(event.write, event.data) for event in trace] == [
        (False, None),
        (True, 0x7F),
        (True, 0x80),
    ]


def test_reset_and_interrupt_seven_cycle_sequences() -> None:
    reset = reset_trace()
    irq = hardware_interrupt_trace(0x8123, 0xFD, 0xFF, 0xFFFE)
    assert len(reset) == len(irq) == 7
    assert [event.address for event in reset] == [
        0x0000,
        0x0000,
        0x0100,
        0x01FF,
        0x01FE,
        0xFFFC,
        0xFFFD,
    ]
    assert [event.address for event in irq] == [
        0x8123,
        0x8123,
        0x01FD,
        0x01FC,
        0x01FB,
        0xFFFE,
        0xFFFF,
    ]
    assert irq[4].data == 0xEF  # U high, B clear


def test_deterministic_randomized_full_address_traces() -> None:
    rng = random.Random(0x2A03)
    for _ in range(10_000):
        pc = rng.randrange(0x10000)
        base = rng.randrange(0x10000)
        index = rng.randrange(0x100)
        trace = absolute_indexed_trace(pc, base, index)
        assert len(trace) == 4 + int(page_cross(base, index))
        assert trace[-1].address == (base + index) & 0xFFFF


def test_cycle_table_mode_and_class_are_test_consumable() -> None:
    assert CYCLE_TABLE[0xBD].addressing_mode is AddressingMode.ABSOLUTE_X
    assert CYCLE_TABLE[0xBD].bus_class is BusClass.READ
    assert CYCLE_TABLE[0x9D].bus_class is BusClass.WRITE
    assert CYCLE_TABLE[0x1E].bus_class is BusClass.RMW
