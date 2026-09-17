import re
from pathlib import Path

import pytest

from verification.cpu import (
    RESET_A,
    RESET_INSTRUCTION,
    RESET_PC,
    RESET_SP,
    RESET_STATUS,
    RESET_X,
    RESET_Y,
    CpuPhase2AModel,
    ExecutionState,
)


ROOT = Path(__file__).resolve().parents[2]
CPU_PACKAGE = ROOT / "rtl" / "cpu" / "cpu_pkg.sv"


def _sv_hex(name: str) -> tuple[int, int]:
    text = CPU_PACKAGE.read_text(encoding="utf-8")
    match = re.search(
        rf"localparam\s+logic\s+\[(\d+):0\]\s+{name}\s*=\s*"
        rf"(\d+)'h([0-9a-fA-F_]+)\s*;",
        text,
    )
    assert match, f"SystemVerilog constant {name} was not found"
    declared_width = int(match.group(1)) + 1
    literal_width = int(match.group(2))
    assert declared_width == literal_width
    return declared_width, int(match.group(3).replace("_", ""), 16)


def test_reset_values_are_independently_defined() -> None:
    model = CpuPhase2AModel()
    state = model.snapshot

    assert (state.a, state.x, state.y) == (0x00, 0x00, 0x00)
    assert state.sp == 0xFD
    assert state.pc == 0x0000
    assert state.status == 0x24
    assert state.instruction == 0x00
    assert state.execution_state is ExecutionState.RESET


def test_status_reset_represents_nvubdizc() -> None:
    status = CpuPhase2AModel().snapshot.status

    assert status & 0x80 == 0  # N
    assert status & 0x40 == 0  # V
    assert status & 0x20       # U is represented high
    assert status & 0x10 == 0  # B is not persistent state
    assert status & 0x08 == 0  # D stored for compatibility, initially clear
    assert status & 0x04       # I
    assert status & 0x02 == 0  # Z
    assert status & 0x01 == 0  # C


def test_cpu_enable_gates_all_sequential_progress() -> None:
    model = CpuPhase2AModel()
    original = model.snapshot

    for read_data in (0x00, 0xA9, 0xFF, 0x5A):
        model.tick(reset=False, cpu_enable=False, read_data=read_data)
        assert model.snapshot == original


def test_fetch_boundary_and_sampling_are_enable_gated() -> None:
    model = CpuPhase2AModel()

    model.tick(reset=False, cpu_enable=True, read_data=0xA9)
    assert model.snapshot.execution_state is ExecutionState.FETCH
    assert model.snapshot.instruction == RESET_INSTRUCTION

    model.tick(reset=False, cpu_enable=False, read_data=0x5A)
    assert model.snapshot.instruction == RESET_INSTRUCTION

    model.tick(reset=False, cpu_enable=True, read_data=0x5A)
    assert model.snapshot.instruction == 0x5A
    assert model.snapshot.pc == RESET_PC


def test_bus_is_deterministic_and_read_only() -> None:
    model = CpuPhase2AModel()

    assert model.bus_outputs(reset=True) == (RESET_PC, 0x00, False, False)
    assert model.bus_outputs(reset=False) == (RESET_PC, 0x00, False, False)
    model.tick(reset=False, cpu_enable=True)
    assert model.bus_outputs(reset=False) == (RESET_PC, 0x00, False, True)


def test_repeated_reset_is_identical() -> None:
    model = CpuPhase2AModel()
    expected = model.snapshot

    model.tick(reset=False, cpu_enable=True)
    model.tick(reset=False, cpu_enable=True, read_data=0xC3)
    assert model.snapshot != expected
    model.tick(reset=True, cpu_enable=True, read_data=0xFF)
    assert model.snapshot == expected


def test_invalid_read_data_is_rejected() -> None:
    model = CpuPhase2AModel()
    with pytest.raises(ValueError):
        model.tick(reset=False, cpu_enable=True, read_data=-1)
    with pytest.raises(ValueError):
        model.tick(reset=False, cpu_enable=True, read_data=0x100)


def test_rtl_reset_constants_match_reference_model() -> None:
    expected = {
        "CPU_RESET_A": (8, RESET_A),
        "CPU_RESET_X": (8, RESET_X),
        "CPU_RESET_Y": (8, RESET_Y),
        "CPU_RESET_SP": (8, RESET_SP),
        "CPU_RESET_PC": (16, RESET_PC),
        "CPU_RESET_STATUS": (8, RESET_STATUS),
        "CPU_RESET_IR": (8, RESET_INSTRUCTION),
    }

    for name, value in expected.items():
        assert _sv_hex(name) == value
