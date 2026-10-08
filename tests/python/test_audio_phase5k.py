"""Phase 5K independent real-time audio architecture tests."""

from __future__ import annotations

import math

import pytest

from verification.audio_phase5k import (
    BoundedFifo,
    Conditioner,
    DC_BLOCK_Q30,
    FIR_COEFFICIENT_BITS,
    FIR_COEFFICIENTS,
    FIR_TAPS,
    SAMPLE_PHASE_INCREMENT,
    SAMPLE_PHASE_MODULUS,
    WM8731_REGISTER_SEQUENCE,
    diagnostic_tone,
    filter_samples,
    fir_response,
    i2s_bclk_toggles,
    i2s_frame,
    round_shift,
    sample_schedule,
    wm8731_write_bytes,
)


def test_exact_48khz_rational_schedule_has_no_drift() -> None:
    assert len(sample_schedule(13_125)) == 352
    assert len(sample_schedule(13_125 * 10)) == 3_520
    schedule = sample_schedule(13_125 * 100)
    gaps = [right - left for left, right in zip(schedule, schedule[1:])]
    assert set(gaps) == {37, 38}
    assert schedule[-1] < 13_125 * 100


def test_scheduler_phase_ratio_is_reduced_and_exact() -> None:
    assert math.gcd(SAMPLE_PHASE_INCREMENT, SAMPLE_PHASE_MODULUS) == 1
    assert SAMPLE_PHASE_INCREMENT / SAMPLE_PHASE_MODULUS == pytest.approx(
        48_000 / (19_687_500 / 11), abs=1e-15
    )


def test_realtime_fir_is_symmetric_normalized_and_bounded() -> None:
    assert len(FIR_COEFFICIENTS) == FIR_TAPS == 961
    assert FIR_COEFFICIENTS == FIR_COEFFICIENTS[::-1]
    assert sum(FIR_COEFFICIENTS) == 1 << FIR_COEFFICIENT_BITS
    assert max(abs(value) for value in FIR_COEFFICIENTS) < (1 << 18)


def test_realtime_fir_frequency_response() -> None:
    assert fir_response(0) == pytest.approx(1.0, abs=1e-12)
    assert fir_response(10_000) > 0.999
    assert fir_response(16_000) > 0.96
    assert 0.48 < fir_response(19_000) < 0.52
    assert fir_response(24_000) < 0.00025


def test_fir_impulse_and_step_dc_gain() -> None:
    impulse_sum = sum(FIR_COEFFICIENTS)
    assert round_shift(impulse_sum, FIR_COEFFICIENT_BITS) == 1
    constant = 0x45678
    steady = round_shift(
        constant * sum(FIR_COEFFICIENTS), FIR_COEFFICIENT_BITS
    )
    assert steady == constant


def test_fir_causal_impulse_and_step_responses() -> None:
    prefix = [0] * FIR_TAPS
    impulse_scale = 1 << FIR_COEFFICIENT_BITS
    impulse = filter_samples(prefix + [impulse_scale] + [0] * FIR_TAPS)
    assert impulse[FIR_TAPS : 2 * FIR_TAPS] == FIR_COEFFICIENTS

    step_value = 0x34567
    step = filter_samples(prefix + [step_value] * (FIR_TAPS + 1))
    assert step[-1] == step_value
    assert max(abs(value) for value in step) < (1 << 20)


def test_dc_blocker_initializes_unsigned_silence_to_zero() -> None:
    conditioner = Conditioner()
    assert [conditioner.process(0x34567) for _ in range(8)] == [0] * 8
    assert conditioner.previous_output == 0


def test_dc_blocker_coefficient_is_ten_hertz_at_48khz() -> None:
    coefficient = DC_BLOCK_Q30 / (1 << 30)
    corner = -48_000 * math.log(coefficient) / (2 * math.pi)
    assert corner == pytest.approx(10.0, rel=0.001)


def test_gain_rounding_signed_range_and_saturation() -> None:
    positive = Conditioner()
    positive.process(0)
    assert positive.process(1 << 20) == 24_576
    negative = Conditioner()
    negative.process(1 << 20)
    assert negative.process(0) == -24_576
    clipping = Conditioner()
    clipping.process(0)
    assert clipping.process(1 << 24) == 32_767
    assert clipping.clipping_count == 1


def test_fifo_full_empty_overrun_and_underrun() -> None:
    fifo = BoundedFifo(4)
    assert fifo.read() == 0
    assert fifo.underruns == 1
    assert all(fifo.write(value) for value in range(4))
    assert not fifo.write(4)
    assert fifo.overruns == 1
    assert [fifo.read() for _ in range(4)] == list(range(4))


def test_fifo_long_run_has_no_loss_or_duplication() -> None:
    fifo = BoundedFifo(16)
    expected = list(range(20_000))
    observed: list[int] = []
    for value in expected:
        assert fifo.write(value)
        if len(fifo.values) >= 4:
            observed.append(fifo.read())
    while fifo.values:
        observed.append(fifo.read())
    assert observed == expected
    assert fifo.overruns == fifo.underruns == 0


@pytest.mark.parametrize("sample", (0, 1, -1, 0x1234, -0x1234, 32767, -32768))
def test_i2s_stereo_framing_alignment_and_word_length(sample: int) -> None:
    frame = i2s_frame(sample)
    assert len(frame) == 64
    assert [lrck for lrck, _ in frame[:32]] == [0] * 32
    assert [lrck for lrck, _ in frame[32:]] == [1] * 32
    assert frame[0][1] == frame[32][1] == 0
    left = sum(frame[index][1] << (16 - index) for index in range(1, 17))
    right = sum(
        frame[index][1] << (48 - index) for index in range(33, 49)
    )
    assert left == right == (sample & 0xFFFF)
    assert all(data == 0 for _, data in frame[17:32])
    assert all(data == 0 for _, data in frame[49:64])


def test_usb_mode_i2s_clocks_are_exact_and_bounded() -> None:
    toggles = i2s_bclk_toggles(250 * 10_000)
    assert len(toggles) == 128 * 10_000
    assert set(right - left for left, right in zip(toggles, toggles[1:])) == {
        1,
        2,
    }
    assert toggles[127] < 250
    assert toggles[128] >= 250


def test_codec_register_sequence_has_safe_order_and_verified_format() -> None:
    assert WM8731_REGISTER_SEQUENCE[0] == (15, 0)
    assert WM8731_REGISTER_SEQUENCE[1] == (9, 0)
    assert WM8731_REGISTER_SEQUENCE[2] == (5, 0x008)
    assert (7, 0x002) in WM8731_REGISTER_SEQUENCE
    assert (8, 0x001) in WM8731_REGISTER_SEQUENCE
    assert WM8731_REGISTER_SEQUENCE[-2:] == ((9, 1), (5, 0))


def test_codec_two_wire_bytes_are_not_generic_i2c_guesses() -> None:
    assert wm8731_write_bytes(7, 0x002) == (0x34, 0x0E, 0x02)
    assert wm8731_write_bytes(2, 0x1F0) == (0x34, 0x05, 0xF0)
    with pytest.raises(ValueError):
        wm8731_write_bytes(128, 0)


def test_diagnostic_tone_is_exact_1khz_and_quarter_scale() -> None:
    values = [diagnostic_tone(index) for index in range(96)]
    assert values[:24] == [8192] * 24
    assert values[24:48] == [-8192] * 24
    assert values[:48] == values[48:]
