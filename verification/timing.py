"""Reference calculations for the Phase 1 platform timing model."""

from fractions import Fraction
from typing import Iterator

BOARD_CLOCK_HZ = 50_000_000

# Provisional NTSC engineering target. Historical/region-specific oscillator
# details still require validation before this becomes a console-accuracy spec.
NTSC_MASTER_HZ = Fraction(945_000_000, 44)
NTSC_PPU_HZ = NTSC_MASTER_HZ / 4
NTSC_CPU_HZ = NTSC_MASTER_HZ / 12

MASTER_ENABLE_RATIO = NTSC_MASTER_HZ / BOARD_CLOCK_HZ
PPU_ENABLE_RATIO = NTSC_PPU_HZ / BOARD_CLOCK_HZ
MASTER_TICKS_PER_PPU_TICK = 4
PPU_TICKS_PER_CPU_TICK = 3


def fractional_enable_pattern(
    cycles: int,
    numerator: int = MASTER_ENABLE_RATIO.numerator,
    denominator: int = MASTER_ENABLE_RATIO.denominator,
) -> Iterator[bool]:
    """Yield the deterministic accumulator-overflow pattern used by the RTL."""

    if cycles < 0:
        raise ValueError("cycles must be non-negative")
    if not 0 < numerator < denominator:
        raise ValueError("enable ratio must be strictly between zero and one")

    accumulator = 0
    for _ in range(cycles):
        accumulator += numerator
        enabled = accumulator >= denominator
        if enabled:
            accumulator -= denominator
        yield enabled


def divided_enable_pattern(
    source_pattern: Iterator[bool], divisor: int
) -> Iterator[bool]:
    """Enable on every ``divisor``-th asserted source enable."""

    if divisor <= 0:
        raise ValueError("divisor must be positive")

    phase = 0
    for source_enabled in source_pattern:
        divided_enabled = False
        if source_enabled:
            phase += 1
            if phase == divisor:
                phase = 0
                divided_enabled = True
        yield divided_enabled


def ppu_enable_pattern(master_pattern: Iterator[bool]) -> Iterator[bool]:
    """Derive PPU enables from every fourth nominal master enable."""

    return divided_enable_pattern(master_pattern, MASTER_TICKS_PER_PPU_TICK)


def cpu_enable_pattern(master_pattern: Iterator[bool]) -> Iterator[bool]:
    """Derive CPU/APU enables from every twelfth nominal master enable."""

    return divided_enable_pattern(
        master_pattern,
        MASTER_TICKS_PER_PPU_TICK * PPU_TICKS_PER_CPU_TICK,
    )
