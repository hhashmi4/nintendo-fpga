"""Independent mathematical and hardware-equivalent NES APU mixer models.

The exact model uses :class:`fractions.Fraction` throughout.  The quantized
model mirrors ``rtl/apu/nes_apu_mixer.sv`` and deliberately shares no emitted
lookup-table data with the RTL.
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from functools import lru_cache
from math import sqrt


MIXER_OUTPUT_BITS = 20
MIXER_SCALE = 1 << MIXER_OUTPUT_BITS
MIXER_MAX = MIXER_SCALE - 1

TND_DRIVE_FRACTION_BITS = 12
TND_DRIVE_SCALE = 1 << TND_DRIVE_FRACTION_BITS
TND_TRIANGLE_WEIGHT = 11_271
TND_NOISE_WEIGHT = 7_575
TND_SEGMENT_FRACTION_BITS = 11
TND_SEGMENT_SCALE = 1 << TND_SEGMENT_FRACTION_BITS
TND_LAST_SEGMENT = 392


def _check_channel(value: int, maximum: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{name} must be an integer")
    if not 0 <= value <= maximum:
        raise ValueError(f"{name} must be in 0..{maximum}")


def _round_fraction(value: Fraction, scale: int = 1) -> int:
    """Round a non-negative rational to nearest, with exact halves upward."""

    if value < 0:
        raise ValueError("mixer values must be non-negative")
    numerator = value.numerator * scale
    denominator = value.denominator
    return (2 * numerator + denominator) // (2 * denominator)


def reference_pulse_mix(pulse1: int, pulse2: int) -> Fraction:
    """Return the high-precision pulse contribution in normalized units."""

    _check_channel(pulse1, 15, "pulse1")
    _check_channel(pulse2, 15, "pulse2")
    return _reference_pulse_sum(pulse1 + pulse2)


def _reference_pulse_sum(pulse_sum: int) -> Fraction:
    if pulse_sum == 0:
        return Fraction(0)
    return Fraction(2_397 * pulse_sum, 25 * (8_128 + 100 * pulse_sum))


def reference_tnd_mix(triangle: int, noise: int, dmc: int) -> Fraction:
    """Return the high-precision triangle/noise/DMC contribution."""

    _check_channel(triangle, 15, "triangle")
    _check_channel(noise, 15, "noise")
    _check_channel(dmc, 127, "dmc")
    conductance = (
        Fraction(triangle, 8_227)
        + Fraction(noise, 12_241)
        + Fraction(dmc, 22_638)
    )
    if conductance == 0:
        return Fraction(0)
    return Fraction(15_979, 100) * conductance / (1 + 100 * conductance)


def reference_mix(
    pulse1: int, pulse2: int, triangle: int, noise: int, dmc: int
) -> Fraction:
    """Return the documented nonlinear NES mixer result in normalized units."""

    return reference_pulse_mix(pulse1, pulse2) + reference_tnd_mix(
        triangle, noise, dmc
    )


@lru_cache(maxsize=None)
def pulse_lut_value(pulse_sum: int) -> int:
    """Return one Q0.20 pulse lookup-table entry."""

    _check_channel(pulse_sum, 30, "pulse_sum")
    if pulse_sum == 0:
        return 0
    return _round_fraction(_reference_pulse_sum(pulse_sum), MIXER_SCALE)


@lru_cache(maxsize=None)
def tnd_node_value(node_index: int) -> int:
    """Return a Q0.20 TND transfer value at a half-DMC-unit node."""

    _check_channel(node_index, TND_LAST_SEGMENT + 1, "node_index")
    drive = Fraction(node_index, 2)
    transfer = Fraction(15_979, 100) * drive / (22_638 + 100 * drive)
    return _round_fraction(transfer, MIXER_SCALE)


@lru_cache(maxsize=None)
def tnd_segment_value(segment_index: int) -> tuple[int, int]:
    """Return the Q0.20 base and delta for one TND interpolation segment."""

    _check_channel(segment_index, TND_LAST_SEGMENT, "segment_index")
    base = tnd_node_value(segment_index)
    delta = tnd_node_value(segment_index + 1) - base
    return base, delta


def quantized_pulse_mix(pulse1: int, pulse2: int) -> int:
    _check_channel(pulse1, 15, "pulse1")
    _check_channel(pulse2, 15, "pulse2")
    return pulse_lut_value(pulse1 + pulse2)


def quantized_tnd_mix(triangle: int, noise: int, dmc: int) -> int:
    """Mirror the synthesizable Q12-drive, half-unit interpolated TND path."""

    _check_channel(triangle, 15, "triangle")
    _check_channel(noise, 15, "noise")
    _check_channel(dmc, 127, "dmc")
    drive_q12 = (
        dmc * TND_DRIVE_SCALE
        + triangle * TND_TRIANGLE_WEIGHT
        + noise * TND_NOISE_WEIGHT
    )
    segment_index, fraction = divmod(drive_q12, TND_SEGMENT_SCALE)
    if segment_index > TND_LAST_SEGMENT:
        raise AssertionError("legal TND inputs exceeded the lookup table")
    base, delta = tnd_segment_value(segment_index)
    interpolation = (
        delta * fraction + TND_SEGMENT_SCALE // 2
    ) // TND_SEGMENT_SCALE
    return base + interpolation


def quantized_mix_components(
    pulse1: int, pulse2: int, triangle: int, noise: int, dmc: int
) -> tuple[int, int, int]:
    """Return the pulse, TND, and saturated Q0.20 mixed values."""

    pulse = quantized_pulse_mix(pulse1, pulse2)
    tnd = quantized_tnd_mix(triangle, noise, dmc)
    return pulse, tnd, min(pulse + tnd, MIXER_MAX)


def quantized_mix(
    pulse1: int, pulse2: int, triangle: int, noise: int, dmc: int
) -> int:
    return quantized_mix_components(pulse1, pulse2, triangle, noise, dmc)[2]


@dataclass(frozen=True)
class MixerErrorReport:
    equivalence_classes: int
    weighted_input_combinations: int
    maximum_absolute_lsb: float
    mean_absolute_lsb: float
    rms_lsb: float
    maximum_relative: float
    maximum_absolute_input: tuple[int, int, int, int]
    maximum_relative_input: tuple[int, int, int, int]
    saturated_equivalence_classes: int


def exhaustive_error_report(relative_floor: Fraction = Fraction(1, 10_000)) -> MixerErrorReport:
    """Analyze every separable mixer equivalence class.

    The four-value locations are ``(pulse_sum, triangle, noise, dmc)``.  Mean
    and RMS weight each pulse sum by the number of P1/P2 pairs producing it,
    so they describe all 8,388,608 legal five-channel input combinations.
    """

    pulse_reference = [_reference_pulse_sum(value) for value in range(31)]
    pulse_quantized = [pulse_lut_value(value) for value in range(31)]
    tnd_entries: list[tuple[int, int, int, Fraction, int]] = []
    for triangle in range(16):
        for noise in range(16):
            for dmc in range(128):
                tnd_entries.append(
                    (
                        triangle,
                        noise,
                        dmc,
                        reference_tnd_mix(triangle, noise, dmc),
                        quantized_tnd_mix(triangle, noise, dmc),
                    )
                )

    maximum_absolute = -1.0
    maximum_relative = -1.0
    maximum_absolute_input = (0, 0, 0, 0)
    maximum_relative_input = (0, 0, 0, 0)
    weighted_absolute_sum = 0.0
    weighted_squared_sum = 0.0
    weighted_count = 0
    saturated = 0

    for pulse_sum in range(31):
        multiplicity = pulse_sum + 1 if pulse_sum <= 15 else 31 - pulse_sum
        pulse_exact = pulse_reference[pulse_sum]
        pulse_fixed = pulse_quantized[pulse_sum]
        for triangle, noise, dmc, tnd_exact, tnd_fixed in tnd_entries:
            exact = pulse_exact + tnd_exact
            raw_fixed = pulse_fixed + tnd_fixed
            fixed = min(raw_fixed, MIXER_MAX)
            if raw_fixed > MIXER_MAX:
                saturated += 1
            error_lsb = abs(float(exact * MIXER_SCALE - fixed))
            weighted_absolute_sum += error_lsb * multiplicity
            weighted_squared_sum += error_lsb * error_lsb * multiplicity
            weighted_count += multiplicity
            if error_lsb > maximum_absolute:
                maximum_absolute = error_lsb
                maximum_absolute_input = (pulse_sum, triangle, noise, dmc)
            if exact >= relative_floor:
                relative = abs(float(exact - Fraction(fixed, MIXER_SCALE))) / float(exact)
                if relative > maximum_relative:
                    maximum_relative = relative
                    maximum_relative_input = (pulse_sum, triangle, noise, dmc)

    return MixerErrorReport(
        equivalence_classes=31 * 16 * 16 * 128,
        weighted_input_combinations=weighted_count,
        maximum_absolute_lsb=maximum_absolute,
        mean_absolute_lsb=weighted_absolute_sum / weighted_count,
        rms_lsb=sqrt(weighted_squared_sum / weighted_count),
        maximum_relative=maximum_relative,
        maximum_absolute_input=maximum_absolute_input,
        maximum_relative_input=maximum_relative_input,
        saturated_equivalence_classes=saturated,
    )
