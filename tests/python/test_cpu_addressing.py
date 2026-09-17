"""Exhaustive and boundary verification for Phase 2C address generation."""

import re
from pathlib import Path

import pytest

from verification.cpu import AddressingMode, generate_address


ROOT = Path(__file__).resolve().parents[2]
CPU_PACKAGE = ROOT / "rtl" / "cpu" / "cpu_pkg.sv"


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
INDEX_VALUES = (0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF)
RELATIVE_OFFSETS = (0x00, 0x01, 0x7F, 0x80, 0x81, 0xFE, 0xFF)
HIGH_BYTE_SAMPLES = (0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF)


def test_modes_without_memory_addresses_are_explicit() -> None:
    implied = generate_address(AddressingMode.IMPLIED)
    accumulator = generate_address(AddressingMode.ACCUMULATOR)

    assert implied.is_implied and implied.mode_valid
    assert not implied.result_valid and not implied.effective_address_valid
    assert accumulator.uses_accumulator and accumulator.mode_valid
    assert not accumulator.result_valid and not accumulator.effective_address_valid


def test_immediate_and_zero_page_are_exhaustive() -> None:
    for operand in range(0x100):
        immediate = generate_address(
            AddressingMode.IMMEDIATE, operand_byte=operand
        )
        zero_page = generate_address(
            AddressingMode.ZERO_PAGE, operand_byte=operand
        )
        assert immediate.immediate_value == operand
        assert immediate.immediate_valid and immediate.result_valid
        assert zero_page.effective_address == operand
        assert zero_page.effective_address_valid and zero_page.result_valid


@pytest.mark.parametrize(
    ("mode", "index_name"),
    (
        (AddressingMode.ZERO_PAGE_X, "x_index"),
        (AddressingMode.ZERO_PAGE_Y, "y_index"),
    ),
)
def test_zero_page_indexing_is_exhaustive(
    mode: AddressingMode, index_name: str
) -> None:
    for operand in range(0x100):
        for index in range(0x100):
            result = generate_address(
                mode, operand_byte=operand, **{index_name: index}
            )
            assert result.effective_address == (operand + index) & 0xFF
            assert result.effective_address_valid and result.result_valid
            assert not result.page_cross_valid


def test_zero_page_directed_wrap_examples() -> None:
    assert generate_address(
        AddressingMode.ZERO_PAGE_X, operand_byte=0xFF, x_index=0x01
    ).effective_address == 0x0000
    assert generate_address(
        AddressingMode.ZERO_PAGE_X, operand_byte=0xFE, x_index=0x02
    ).effective_address == 0x0000


def test_absolute_boundaries() -> None:
    for base in BOUNDARY_ADDRESSES:
        result = generate_address(AddressingMode.ABSOLUTE, base_address=base)
        assert result.effective_address == base
        assert result.effective_address_valid and result.result_valid


@pytest.mark.parametrize(
    ("mode", "index_name"),
    (
        (AddressingMode.ABSOLUTE_X, "x_index"),
        (AddressingMode.ABSOLUTE_Y, "y_index"),
    ),
)
def test_absolute_indexed_low_bytes_are_exhaustive_across_upper_partitions(
    mode: AddressingMode, index_name: str
) -> None:
    for high_byte in HIGH_BYTE_SAMPLES:
        for low_byte in range(0x100):
            base = (high_byte << 8) | low_byte
            for index in range(0x100):
                result = generate_address(
                    mode, base_address=base, **{index_name: index}
                )
                assert result.effective_address == (base + index) & 0xFFFF
                assert result.page_cross == (low_byte + index > 0xFF)
                assert result.page_cross_valid and result.result_valid


def test_absolute_indexed_boundaries_and_wrap() -> None:
    for mode, index_name in (
        (AddressingMode.ABSOLUTE_X, "x_index"),
        (AddressingMode.ABSOLUTE_Y, "y_index"),
    ):
        for base in BOUNDARY_ADDRESSES:
            for index in INDEX_VALUES:
                result = generate_address(
                    mode, base_address=base, **{index_name: index}
                )
                assert result.effective_address == (base + index) & 0xFFFF
                assert result.page_cross == ((base & 0xFF) + index > 0xFF)


def test_indirect_pointer_addresses_and_nmos_wrap_are_exhaustive() -> None:
    for pointer in range(0x10000):
        result = generate_address(AddressingMode.INDIRECT, base_address=pointer)
        assert result.pointer_low_address == pointer
        assert result.pointer_high_address == (
            (pointer & 0xFF00) | ((pointer + 1) & 0xFF)
        )
        assert result.pointer_addresses_valid
        assert not result.result_valid


def test_indirect_resolves_only_when_pointer_bytes_are_valid() -> None:
    unresolved = generate_address(
        AddressingMode.INDIRECT,
        base_address=0x12FF,
        pointer_low_byte=0xCD,
        pointer_high_byte=0xAB,
    )
    resolved = generate_address(
        AddressingMode.INDIRECT,
        base_address=0x12FF,
        pointer_low_byte=0xCD,
        pointer_high_byte=0xAB,
        pointer_data_valid=True,
    )
    assert unresolved.pointer_high_address == 0x1200
    assert not unresolved.effective_address_valid
    assert resolved.effective_address == 0xABCD
    assert resolved.effective_address_valid and resolved.result_valid


def test_indexed_indirect_pointer_formation_is_exhaustive() -> None:
    for operand in range(0x100):
        for x_index in range(0x100):
            pointer_address = (operand + x_index) & 0xFF
            result = generate_address(
                AddressingMode.INDEXED_INDIRECT_X,
                operand_byte=operand,
                x_index=x_index,
            )
            assert result.pointer_low_address == pointer_address
            assert result.pointer_high_address == (pointer_address + 1) & 0xFF
            assert result.pointer_addresses_valid
            assert not result.result_valid


def test_indexed_indirect_resolved_target() -> None:
    result = generate_address(
        AddressingMode.INDEXED_INDIRECT_X,
        operand_byte=0xFF,
        x_index=0x02,
        pointer_low_byte=0x34,
        pointer_high_byte=0x12,
        pointer_data_valid=True,
    )
    assert result.pointer_low_address == 0x0001
    assert result.pointer_high_address == 0x0002
    assert result.effective_address == 0x1234
    assert result.result_valid


def test_indirect_indexed_pointer_wrap_is_exhaustive() -> None:
    for operand in range(0x100):
        result = generate_address(
            AddressingMode.INDIRECT_INDEXED_Y, operand_byte=operand
        )
        assert result.pointer_low_address == operand
        assert result.pointer_high_address == (operand + 1) & 0xFF
        assert result.pointer_addresses_valid
        assert not result.result_valid


def test_indirect_indexed_addition_is_exhaustive_across_upper_partitions() -> None:
    for pointer_high in HIGH_BYTE_SAMPLES:
        for pointer_low in range(0x100):
            pointer = (pointer_high << 8) | pointer_low
            for y_index in range(0x100):
                result = generate_address(
                    AddressingMode.INDIRECT_INDEXED_Y,
                    operand_byte=0xFF,
                    y_index=y_index,
                    pointer_low_byte=pointer_low,
                    pointer_high_byte=pointer_high,
                    pointer_data_valid=True,
                )
                assert result.pointer_low_address == 0x00FF
                assert result.pointer_high_address == 0x0000
                assert result.effective_address == (pointer + y_index) & 0xFFFF
                assert result.page_cross == (pointer_low + y_index > 0xFF)
                assert result.page_cross_valid and result.result_valid


def test_relative_low_byte_offset_space_is_exhaustive() -> None:
    for base_low in range(0x100):
        base = 0x7F00 | base_low
        for offset in range(0x100):
            signed_offset = offset if offset < 0x80 else offset - 0x100
            target = (base + signed_offset) & 0xFFFF
            result = generate_address(
                AddressingMode.RELATIVE,
                base_address=base,
                operand_byte=offset,
            )
            assert result.branch_target == target
            assert result.page_cross == ((base >> 8) != (target >> 8))
            assert result.branch_target_valid
            assert result.page_cross_valid and result.result_valid


def test_relative_boundaries_and_examples() -> None:
    for base in BOUNDARY_ADDRESSES:
        for offset in RELATIVE_OFFSETS:
            signed_offset = offset if offset < 0x80 else offset - 0x100
            result = generate_address(
                AddressingMode.RELATIVE,
                base_address=base,
                operand_byte=offset,
            )
            assert result.branch_target == (base + signed_offset) & 0xFFFF

    assert generate_address(
        AddressingMode.RELATIVE, base_address=0x1000, operand_byte=0x05
    ).branch_target == 0x1005
    assert generate_address(
        AddressingMode.RELATIVE, base_address=0x1000, operand_byte=0xFB
    ).branch_target == 0x0FFB
    assert generate_address(
        AddressingMode.RELATIVE, base_address=0x00FE, operand_byte=0x05
    ).branch_target == 0x0103


@pytest.mark.parametrize(
    ("argument", "value"),
    (
        ("base_address", 0x10000),
        ("operand_byte", 0x100),
        ("x_index", -1),
        ("y_index", 0x100),
        ("pointer_low_byte", -1),
        ("pointer_high_byte", 0x100),
        ("pointer_data_valid", 2),
    ),
)
def test_reference_model_rejects_out_of_range_inputs(
    argument: str, value: int
) -> None:
    with pytest.raises(ValueError):
        generate_address(AddressingMode.ZERO_PAGE, **{argument: value})


def test_reference_model_rejects_non_enum_mode() -> None:
    with pytest.raises(ValueError):
        generate_address(13)  # type: ignore[arg-type]


def test_rtl_mode_encodings_match_reference_model() -> None:
    text = CPU_PACKAGE.read_text(encoding="utf-8")
    for mode in AddressingMode:
        match = re.search(
            rf"CPU_ADDR_{mode.name}\s*=\s*4'd(\d+)",
            text,
        )
        assert match, f"RTL mode CPU_ADDR_{mode.name} was not found"
        assert int(match.group(1)) == mode.value
