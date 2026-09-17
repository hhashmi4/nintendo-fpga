import re
from collections.abc import Callable
from pathlib import Path

import pytest

from verification.cpu import AluOperation, AluResult, evaluate_alu


ROOT = Path(__file__).resolve().parents[2]
CPU_PACKAGE = ROOT / "rtl" / "cpu" / "cpu_pkg.sv"


def _assert_common(
    actual: AluResult,
    *,
    result: int,
    negative: bool,
    overflow: bool,
    zero: bool,
    carry: bool,
) -> None:
    assert actual.result == result
    assert actual.negative is negative
    assert actual.overflow is overflow
    assert actual.zero is zero
    assert actual.carry is carry


@pytest.mark.parametrize(
    ("operand_a", "operand_b", "carry_in", "expected"),
    [
        (0x00, 0x00, 0, (0x00, False, False, True, False)),
        (0x7F, 0x01, 0, (0x80, True, True, False, False)),
        (0x80, 0x80, 0, (0x00, False, True, True, True)),
        (0xFF, 0x01, 0, (0x00, False, False, True, True)),
        (0xFF, 0xFF, 0, (0xFE, True, False, False, True)),
        (0x00, 0x00, 1, (0x01, False, False, False, False)),
        (0xFF, 0x00, 1, (0x00, False, False, True, True)),
    ],
)
def test_add_boundaries(
    operand_a: int,
    operand_b: int,
    carry_in: int,
    expected: tuple[int, bool, bool, bool, bool],
) -> None:
    actual = evaluate_alu(AluOperation.ADD, operand_a, operand_b, carry_in)
    result, negative, overflow, zero, carry = expected
    _assert_common(
        actual,
        result=result,
        negative=negative,
        overflow=overflow,
        zero=zero,
        carry=carry,
    )


@pytest.mark.parametrize(
    ("operand_a", "operand_b", "carry_in", "expected"),
    [
        (0x00, 0x00, 1, (0x00, False, False, True, True)),
        (0x00, 0x00, 0, (0xFF, True, False, False, False)),
        (0x00, 0x01, 1, (0xFF, True, False, False, False)),
        (0x80, 0x01, 1, (0x7F, False, True, False, True)),
        (0x7F, 0xFF, 1, (0x80, True, True, False, False)),
        (0xFF, 0xFF, 1, (0x00, False, False, True, True)),
        (0xFF, 0xFF, 0, (0xFF, True, False, False, False)),
    ],
)
def test_subtract_boundaries(
    operand_a: int,
    operand_b: int,
    carry_in: int,
    expected: tuple[int, bool, bool, bool, bool],
) -> None:
    actual = evaluate_alu(AluOperation.SUB, operand_a, operand_b, carry_in)
    result, negative, overflow, zero, carry = expected
    _assert_common(
        actual,
        result=result,
        negative=negative,
        overflow=overflow,
        zero=zero,
        carry=carry,
    )


def test_add_exhaustive() -> None:
    for operand_a in range(256):
        for operand_b in range(256):
            for carry_in in (0, 1):
                actual = evaluate_alu(
                    AluOperation.ADD, operand_a, operand_b, carry_in
                )
                expected_result = (operand_a + operand_b + carry_in) & 0xFF
                expected_overflow = bool(
                    (~(operand_a ^ operand_b))
                    & (operand_a ^ expected_result)
                    & 0x80
                )
                _assert_common(
                    actual,
                    result=expected_result,
                    negative=bool(expected_result & 0x80),
                    overflow=expected_overflow,
                    zero=expected_result == 0,
                    carry=operand_a + operand_b + carry_in > 0xFF,
                )


def test_subtract_exhaustive() -> None:
    for operand_a in range(256):
        for operand_b in range(256):
            for carry_in in (0, 1):
                difference = operand_a - operand_b - (1 - carry_in)
                expected_result = difference & 0xFF
                expected_overflow = bool(
                    (operand_a ^ operand_b)
                    & (operand_a ^ expected_result)
                    & 0x80
                )
                actual = evaluate_alu(
                    AluOperation.SUB, operand_a, operand_b, carry_in
                )
                _assert_common(
                    actual,
                    result=expected_result,
                    negative=bool(expected_result & 0x80),
                    overflow=expected_overflow,
                    zero=expected_result == 0,
                    carry=difference >= 0,
                )


@pytest.mark.parametrize(
    ("operation", "operator"),
    [
        (AluOperation.AND, lambda a, b: a & b),
        (AluOperation.OR, lambda a, b: a | b),
        (AluOperation.XOR, lambda a, b: a ^ b),
    ],
)
def test_logic_exhaustive(
    operation: AluOperation, operator: Callable[[int, int], int]
) -> None:
    for operand_a in range(256):
        for operand_b in range(256):
            expected_result = operator(operand_a, operand_b)
            actual = evaluate_alu(operation, operand_a, operand_b)
            _assert_common(
                actual,
                result=expected_result,
                negative=bool(expected_result & 0x80),
                overflow=False,
                zero=expected_result == 0,
                carry=False,
            )


@pytest.mark.parametrize(
    ("operation", "delta"),
    [(AluOperation.INC, 1), (AluOperation.DEC, -1)],
)
def test_increment_decrement_exhaustive(
    operation: AluOperation, delta: int
) -> None:
    for operand in range(256):
        expected_result = (operand + delta) & 0xFF
        actual = evaluate_alu(operation, operand)
        _assert_common(
            actual,
            result=expected_result,
            negative=bool(expected_result & 0x80),
            overflow=False,
            zero=expected_result == 0,
            carry=False,
        )


@pytest.mark.parametrize("operation", [AluOperation.ASL, AluOperation.LSR])
def test_shift_exhaustive(operation: AluOperation) -> None:
    for operand in range(256):
        if operation is AluOperation.ASL:
            expected_result = (operand << 1) & 0xFF
            expected_carry = bool(operand & 0x80)
        else:
            expected_result = operand >> 1
            expected_carry = bool(operand & 0x01)
        actual = evaluate_alu(operation, operand)
        _assert_common(
            actual,
            result=expected_result,
            negative=bool(expected_result & 0x80),
            overflow=False,
            zero=expected_result == 0,
            carry=expected_carry,
        )


@pytest.mark.parametrize("operation", [AluOperation.ROL, AluOperation.ROR])
def test_rotate_exhaustive(operation: AluOperation) -> None:
    for operand in range(256):
        for carry_in in (0, 1):
            if operation is AluOperation.ROL:
                expected_result = ((operand << 1) | carry_in) & 0xFF
                expected_carry = bool(operand & 0x80)
            else:
                expected_result = (operand >> 1) | (carry_in << 7)
                expected_carry = bool(operand & 0x01)
            actual = evaluate_alu(operation, operand, carry_in=carry_in)
            _assert_common(
                actual,
                result=expected_result,
                negative=bool(expected_result & 0x80),
                overflow=False,
                zero=expected_result == 0,
                carry=expected_carry,
            )


def test_compare_exhaustive_and_ignores_carry_in() -> None:
    for operand_a in range(256):
        for operand_b in range(256):
            expected_result = (operand_a - operand_b) & 0xFF
            for carry_in in (0, 1):
                actual = evaluate_alu(
                    AluOperation.CMP, operand_a, operand_b, carry_in
                )
                _assert_common(
                    actual,
                    result=expected_result,
                    negative=bool(expected_result & 0x80),
                    overflow=False,
                    zero=operand_a == operand_b,
                    carry=operand_a >= operand_b,
                )
                assert not actual.result_valid
                assert not actual.v_valid


@pytest.mark.parametrize(
    ("operation", "result_valid", "valids"),
    [
        (AluOperation.ADD, True, (True, True, True, True)),
        (AluOperation.SUB, True, (True, True, True, True)),
        (AluOperation.AND, True, (True, False, True, False)),
        (AluOperation.OR, True, (True, False, True, False)),
        (AluOperation.XOR, True, (True, False, True, False)),
        (AluOperation.ASL, True, (True, False, True, True)),
        (AluOperation.LSR, True, (True, False, True, True)),
        (AluOperation.ROL, True, (True, False, True, True)),
        (AluOperation.ROR, True, (True, False, True, True)),
        (AluOperation.INC, True, (True, False, True, False)),
        (AluOperation.DEC, True, (True, False, True, False)),
        (AluOperation.CMP, False, (True, False, True, True)),
    ],
)
def test_flag_and_result_validity(
    operation: AluOperation,
    result_valid: bool,
    valids: tuple[bool, bool, bool, bool],
) -> None:
    actual = evaluate_alu(operation, 0xA5, 0x5A, True)
    assert actual.result_valid is result_valid
    assert (actual.n_valid, actual.v_valid, actual.z_valid, actual.c_valid) == valids


@pytest.mark.parametrize(
    ("operation", "operand_a", "operand_b", "carry_in"),
    [
        (0, 0, 0, 0),
        (AluOperation.ADD, -1, 0, 0),
        (AluOperation.ADD, 0x100, 0, 0),
        (AluOperation.ADD, 0, -1, 0),
        (AluOperation.ADD, 0, 0, 2),
    ],
)
def test_invalid_arguments_fail(
    operation: object, operand_a: int, operand_b: int, carry_in: int
) -> None:
    with pytest.raises(ValueError):
        evaluate_alu(operation, operand_a, operand_b, carry_in)


def test_rtl_operation_encodings_match_reference_model() -> None:
    text = CPU_PACKAGE.read_text(encoding="utf-8")
    for operation in AluOperation:
        match = re.search(
            rf"CPU_ALU_{operation.name}\s*=\s*4'd(\d+)",
            text,
        )
        assert match, f"RTL operation CPU_ALU_{operation.name} was not found"
        assert int(match.group(1)) == operation.value
