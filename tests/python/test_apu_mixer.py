from __future__ import annotations

from fractions import Fraction
from pathlib import Path
import subprocess
import sys

import pytest

from verification.apu_mixer import (
    MIXER_MAX,
    MIXER_SCALE,
    TND_LAST_SEGMENT,
    exhaustive_error_report,
    pulse_lut_value,
    quantized_mix,
    quantized_tnd_mix,
    reference_mix,
    tnd_segment_value,
)


@pytest.mark.parametrize(
    ("channels", "expected_nonzero"),
    [
        ((0, 0, 0, 0, 0), False),
        ((1, 0, 0, 0, 0), True),
        ((0, 1, 0, 0, 0), True),
        ((0, 0, 1, 0, 0), True),
        ((0, 0, 0, 1, 0), True),
        ((0, 0, 0, 0, 1), True),
        ((15, 15, 15, 15, 127), True),
        ((1, 1, 1, 1, 1), True),
    ],
)
def test_directed_outputs(channels, expected_nonzero):
    result = quantized_mix(*channels)
    assert (result != 0) is expected_nonzero
    assert 0 <= result <= MIXER_MAX


def test_maximum_is_defined_full_scale():
    maximum_reference = reference_mix(15, 15, 15, 15, 127)
    assert Fraction(999_999, 1_000_000) < maximum_reference < 1
    assert quantized_mix(15, 15, 15, 15, 127) == MIXER_MAX


def test_all_pulse_pairs_are_symmetric_and_match_lut():
    for pulse1 in range(16):
        for pulse2 in range(16):
            actual = quantized_mix(pulse1, pulse2, 0, 0, 0)
            assert actual == pulse_lut_value(pulse1 + pulse2)
            assert actual == quantized_mix(pulse2, pulse1, 0, 0, 0)


def test_every_tnd_input_is_in_range_and_monotonic():
    for triangle in range(16):
        for noise in range(16):
            previous = -1
            for dmc in range(128):
                actual = quantized_tnd_mix(triangle, noise, dmc)
                assert actual >= previous
                previous = actual
    for noise in range(16):
        for dmc in range(128):
            assert all(
                quantized_tnd_mix(triangle, noise, dmc)
                <= quantized_tnd_mix(triangle + 1, noise, dmc)
                for triangle in range(15)
            )
    for triangle in range(16):
        for dmc in range(128):
            assert all(
                quantized_tnd_mix(triangle, noise, dmc)
                <= quantized_tnd_mix(triangle, noise + 1, dmc)
                for noise in range(15)
            )


def test_pulse_path_is_monotonic():
    assert all(pulse_lut_value(value) < pulse_lut_value(value + 1) for value in range(30))


def test_lut_boundaries_and_deterministic_rounding():
    assert pulse_lut_value(0) == 0
    assert pulse_lut_value(1) == 12_219
    assert pulse_lut_value(15) == 156_633
    assert pulse_lut_value(30) == 271_039
    assert tnd_segment_value(0)[0] == 0
    assert tnd_segment_value(0) == (0, 3_693)
    assert tnd_segment_value(TND_LAST_SEGMENT) == (777_503, 1_062)
    for index in range(TND_LAST_SEGMENT + 1):
        base, delta = tnd_segment_value(index)
        assert 0 <= base <= MIXER_MAX
        assert 0 <= delta < (1 << 12)


@pytest.mark.parametrize(
    ("channels", "expected"),
    [
        ((15, 0, 0, 0, 0), 156_633),
        ((0, 15, 0, 0, 0), 156_633),
        ((0, 0, 15, 0, 0), 258_384),
        ((0, 0, 0, 15, 0), 182_903),
        ((0, 0, 0, 0, 127), 602_159),
        ((0, 0, 15, 15, 0), 391_467),
        ((0, 0, 15, 0, 127), 714_417),
        ((0, 0, 0, 15, 127), 680_285),
        ((15, 15, 15, 15, 127), MIXER_MAX),
    ],
)
def test_directed_quantized_codes(channels, expected):
    assert quantized_mix(*channels) == expected


def test_generated_lut_is_current():
    root = Path(__file__).resolve().parents[2]
    subprocess.run(
        [sys.executable, "scripts/generate_apu_mixer_luts.py", "--check"],
        cwd=root,
        check=True,
    )


def test_complete_domain_error_budget():
    report = exhaustive_error_report()
    assert report.equivalence_classes == 1_015_808
    assert report.weighted_input_combinations == 8_388_608
    assert report.maximum_absolute_lsb <= 4.0
    assert report.mean_absolute_lsb <= 1.0
    assert report.rms_lsb <= 1.1
    assert report.maximum_relative <= 0.0002
    assert report.saturated_equivalence_classes == 1
    assert MIXER_SCALE == 1_048_576


@pytest.mark.parametrize(
    ("channels", "name"),
    [
        ((-1, 0, 0, 0, 0), "pulse1"),
        ((0, 16, 0, 0, 0), "pulse2"),
        ((0, 0, 16, 0, 0), "triangle"),
        ((0, 0, 0, 16, 0), "noise"),
        ((0, 0, 0, 0, 128), "dmc"),
    ],
)
def test_invalid_inputs_are_rejected(channels, name):
    with pytest.raises(ValueError, match=name):
        quantized_mix(*channels)
