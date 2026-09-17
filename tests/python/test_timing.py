import re
from fractions import Fraction
from pathlib import Path

import pytest

from verification.timing import (
    BOARD_CLOCK_HZ,
    MASTER_ENABLE_RATIO,
    MASTER_TICKS_PER_PPU_TICK,
    NTSC_CPU_HZ,
    NTSC_MASTER_HZ,
    NTSC_PPU_HZ,
    PPU_ENABLE_RATIO,
    PPU_TICKS_PER_CPU_TICK,
    cpu_enable_pattern,
    divided_enable_pattern,
    fractional_enable_pattern,
    ppu_enable_pattern,
)


ROOT = Path(__file__).resolve().parents[2]
SV_CONFIG = ROOT / "rtl" / "platform" / "platform_config_pkg.sv"


def _sv_integer(name: str) -> int:
    text = SV_CONFIG.read_text(encoding="utf-8")
    match = re.search(
        rf"localparam\s+int\s+unsigned\s+{name}\s*=\s*([\d_]+)\s*;", text
    )
    assert match, f"SystemVerilog constant {name} was not found"
    return int(match.group(1).replace("_", ""))


def test_nominal_ntsc_relationships() -> None:
    assert NTSC_MASTER_HZ == Fraction(945_000_000, 44)
    assert NTSC_PPU_HZ == NTSC_MASTER_HZ / 4
    assert NTSC_CPU_HZ == NTSC_MASTER_HZ / 12
    assert NTSC_PPU_HZ / NTSC_CPU_HZ == PPU_TICKS_PER_CPU_TICK


def test_enable_ratio_is_exactly_reduced() -> None:
    assert MASTER_ENABLE_RATIO == Fraction(189, 440)
    assert PPU_ENABLE_RATIO == Fraction(189, 1760)
    assert MASTER_ENABLE_RATIO == NTSC_MASTER_HZ / BOARD_CLOCK_HZ
    assert PPU_ENABLE_RATIO == NTSC_PPU_HZ / BOARD_CLOCK_HZ


def test_rtl_constants_match_reference_model() -> None:
    assert _sv_integer("BOARD_CLOCK_HZ") == BOARD_CLOCK_HZ
    rtl_master = Fraction(
        _sv_integer("NTSC_MASTER_HZ_NUMERATOR"),
        _sv_integer("NTSC_MASTER_HZ_DENOMINATOR"),
    )
    assert rtl_master == NTSC_MASTER_HZ

    reduction = _sv_integer("TIMING_REDUCTION_HZ")
    rtl_master_numerator = _sv_integer("NTSC_MASTER_HZ_NUMERATOR") // reduction
    rtl_master_denominator = (
        _sv_integer("NTSC_MASTER_HZ_DENOMINATOR")
        * (_sv_integer("BOARD_CLOCK_HZ") // reduction)
    )
    assert (
        Fraction(rtl_master_numerator, rtl_master_denominator)
        == MASTER_ENABLE_RATIO
    )


def test_one_accumulator_period_has_expected_enable_counts() -> None:
    cycles = MASTER_ENABLE_RATIO.denominator * MASTER_TICKS_PER_PPU_TICK
    master_pattern = list(fractional_enable_pattern(cycles))
    ppu_pattern = list(ppu_enable_pattern(iter(master_pattern)))
    cpu_pattern = list(cpu_enable_pattern(iter(master_pattern)))

    assert (
        sum(master_pattern)
        == MASTER_ENABLE_RATIO.numerator * MASTER_TICKS_PER_PPU_TICK
    )
    assert sum(ppu_pattern) == PPU_ENABLE_RATIO.numerator
    assert sum(cpu_pattern) == PPU_ENABLE_RATIO.numerator // PPU_TICKS_PER_CPU_TICK
    assert all(not ppu or master for ppu, master in zip(ppu_pattern, master_pattern))
    assert all(not cpu or ppu for cpu, ppu in zip(cpu_pattern, ppu_pattern))


def test_enable_pattern_is_repeatable() -> None:
    first = list(fractional_enable_pattern(MASTER_ENABLE_RATIO.denominator * 2))
    period = MASTER_ENABLE_RATIO.denominator
    assert first[:period] == first[period:]


def test_invalid_pattern_arguments_fail() -> None:
    with pytest.raises(ValueError):
        list(fractional_enable_pattern(-1))
    with pytest.raises(ValueError):
        list(fractional_enable_pattern(1, 0, 10))
    with pytest.raises(ValueError):
        list(fractional_enable_pattern(1, 10, 10))
    with pytest.raises(ValueError):
        list(divided_enable_pattern(iter([True]), 0))
