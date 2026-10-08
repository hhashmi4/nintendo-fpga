"""Phase 5J deterministic capture, filtering, PCM, and legal-ROM tests."""

from __future__ import annotations

import io
import struct
import wave
from dataclasses import replace
from pathlib import Path

import pytest

from scripts.generate_apu_audio_phase5j_roms import (
    DMC_SAMPLE_ADDRESS,
    PRG_SIZE,
    SCENARIOS,
    ines,
    program_for,
)
from verification.apu_audio import (
    ApuCapture,
    AudioEvent,
    CaptureFormatError,
    DEFAULT_SAMPLE_RATE,
    convert_capture,
    fir_response,
    measure_frequency,
    pcm_sample_count,
    read_capture,
    sha256_bytes,
    validate_mixer_events,
    wav_bytes,
)
from verification.apu_audio_fir import (
    FIR_COEFFICIENTS,
    FIR_COEFFICIENT_BITS,
    FIR_TAP_COUNT,
)
from verification.apu_mixer import quantized_mix


CPU_RATE = 19_687_500 / 11


def capture_with_events(
    events: list[AudioEvent], cpu_cycles: int, scenario: str = "synthetic"
) -> ApuCapture:
    return ApuCapture(
        scenario=scenario,
        cpu_cycles=cpu_cycles,
        audio_start_cycle=0,
        events=tuple(events),
        writes=(),
        fetches=(),
        pauses=(),
        resets=(),
        instructions=1,
        metadata={},
    )


def event(cycle: int, pulse1: int = 0, triangle: int = 15) -> AudioEvent:
    return AudioEvent(
        cycle=cycle,
        mixed=quantized_mix(pulse1, 0, triangle, 0, 0),
        pulse1=pulse1,
        pulse2=0,
        triangle=triangle,
        noise=0,
        dmc=0,
        flags=0,
    )


def test_exact_rational_sample_counts() -> None:
    assert pcm_sample_count(178_977) == 4_800
    assert pcm_sample_count(894_886) == 24_000
    assert pcm_sample_count(1_789_773) == 48_000
    assert pcm_sample_count(19_687_500) == 528_000


def test_fixed_fir_is_symmetric_unity_gain_and_rejects_aliases() -> None:
    assert len(FIR_COEFFICIENTS) == FIR_TAP_COUNT == 3_073
    assert FIR_COEFFICIENTS == FIR_COEFFICIENTS[::-1]
    assert sum(FIR_COEFFICIENTS) == 1 << FIR_COEFFICIENT_BITS
    assert fir_response(0) == pytest.approx(1.0, abs=1e-12)
    assert fir_response(20_000) > 0.999
    assert 0.49 < fir_response(22_000) < 0.51
    assert fir_response(24_000) < 5e-5


def test_unsigned_digital_silence_converts_to_exact_centered_pcm() -> None:
    # The disabled triangle sequencer rests at 15 in the established RTL. The
    # steady-state DC initialization must still make audible silence exact zero.
    capture = capture_with_events([event(0)], 178_977, "silence")
    result = convert_capture(capture)
    assert len(result.samples) == 4_800
    assert set(result.samples) == {0}
    assert result.peak == 0
    assert result.rms == 0.0
    assert result.clipping_count == 0


def test_rational_resampler_preserves_known_pulse_frequency() -> None:
    timer = 253
    half_period = 8 * (timer + 1)
    cpu_cycles = 447_443
    events = [event(0)]
    level = 15
    for cycle in range(499, cpu_cycles, half_period):
        events.append(event(cycle, pulse1=level))
        level = 0 if level else 15
    result = convert_capture(capture_with_events(events, cpu_cycles, "pulse1"))
    expected = CPU_RATE / (16 * (timer + 1))
    assert measure_frequency(result.samples, result.sample_rate) == pytest.approx(
        expected, rel=0.001
    )
    assert result.clipping_count == 0


def test_pcm_and_wav_encoding_are_byte_deterministic() -> None:
    capture = capture_with_events(
        [event(0), event(2_000, 15), event(4_000), event(6_000, 15)],
        8_000,
    )
    first = convert_capture(capture)
    second = convert_capture(capture)
    assert first == second
    encoded = wav_bytes(first)
    assert encoded == wav_bytes(second)
    assert sha256_bytes(encoded) == sha256_bytes(wav_bytes(second))
    with wave.open(io.BytesIO(encoded), "rb") as stream:
        assert stream.getnchannels() == 1
        assert stream.getsampwidth() == 2
        assert stream.getframerate() == DEFAULT_SAMPLE_RATE
        assert stream.getnframes() == len(first.samples)
        payload = stream.readframes(stream.getnframes())
    assert struct.unpack(f"<{len(first.samples)}h", payload) == first.samples


def test_capture_parser_accepts_evidence_records_and_validates_mixer(
    tmp_path: Path,
) -> None:
    mixed = quantized_mix(0, 0, 15, 0, 0)
    path = tmp_path / "valid.apucap"
    path.write_text(
        "\n".join(
            (
                "NESAPU_CAPTURE_V1",
                "scenario=unit",
                "cpu_rate_num=19687500",
                "cpu_rate_den=11",
                "cpu_cycles=4",
                "mixer_q_bits=20",
                "mixer_latency_fabric_cycles=1",
                "pause_policy=omit",
                "BEGIN",
                "W 2 0x8000 0x4015 0x01",
                "F 3 0xe000 0x55",
                "S 4",
                f"A 0 {mixed} 0 0 15 0 0 0",
                "P 1 96",
                "R 2 1",
                "R 2 0",
                "I 2",
                "END 4 1 1 1",
                "",
            )
        ),
        encoding="ascii",
    )
    capture = read_capture(path)
    assert capture.scenario == "unit"
    assert capture.instructions == 2
    assert capture.writes[0].address == 0x4015
    assert capture.fetches[0].data == 0x55
    assert capture.pauses[0].fabric_cycles == 96
    assert [item.asserted for item in capture.resets] == [True, False]
    validate_mixer_events(capture)


@pytest.mark.parametrize(
    "replacement",
    (
        "cpu_rate_den=12",
        "mixer_latency_fabric_cycles=0",
        "A 0 1 0 0 0 0 0 0",
        "END 4 2 0 0",
    ),
)
def test_capture_parser_rejects_malformed_or_inconsistent_input(
    tmp_path: Path, replacement: str
) -> None:
    mixed = quantized_mix(0, 0, 15, 0, 0)
    valid = "\n".join(
        (
            "NESAPU_CAPTURE_V1",
            "scenario=bad",
            "cpu_rate_num=19687500",
            "cpu_rate_den=11",
            "cpu_cycles=4",
            "mixer_q_bits=20",
            "mixer_latency_fabric_cycles=1",
            "pause_policy=omit",
            "BEGIN",
            "S 0",
            f"A 0 {mixed} 0 0 15 0 0 0",
            "I 1",
            "END 4 1 0 0",
        )
    )
    if replacement.startswith("A "):
        broken = valid.replace(f"A 0 {mixed} 0 0 15 0 0 0", replacement)
    elif replacement.startswith("END "):
        broken = valid.replace("END 4 1 0 0", replacement)
    else:
        key = replacement.split("=", 1)[0]
        original = next(
            line for line in valid.splitlines() if line.startswith(key + "=")
        )
        broken = valid.replace(original, replacement)
    path = tmp_path / "bad.apucap"
    path.write_text(broken + "\n", encoding="ascii")
    if replacement.startswith("A "):
        capture = read_capture(path)
        with pytest.raises(CaptureFormatError):
            validate_mixer_events(capture)
    else:
        with pytest.raises(CaptureFormatError):
            read_capture(path)


@pytest.mark.parametrize("scenario", SCENARIOS)
def test_generated_audio_roms_are_original_valid_nrom128(scenario: str) -> None:
    prg, metadata = program_for(scenario)
    rom = ines(prg)
    assert len(prg) == PRG_SIZE
    assert rom[:16] == b"NES\x1a\x01\x00" + bytes(10)
    assert rom[16:] == prg
    assert prg[0x3FFC:0x3FFE] == b"\x00\x80"
    assert metadata["scenario"] == scenario
    sample_offset = DMC_SAMPLE_ADDRESS & 0x3FFF
    assert prg[sample_offset : sample_offset + 17].hex() == metadata["dmc_sample_hex"]


def test_mixer_mismatch_is_rejected_before_conversion() -> None:
    capture = capture_with_events([event(0)], 100)
    corrupt = replace(capture.events[0], mixed=capture.events[0].mixed + 1)
    with pytest.raises(CaptureFormatError):
        convert_capture(replace(capture, events=(corrupt,)))
