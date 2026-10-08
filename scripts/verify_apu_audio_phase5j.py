#!/usr/bin/env python3
"""Validate real Phase 5J RTL captures and emit deterministic WAV metrics."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from verification.apu_audio import (  # noqa: E402
    AudioEvent,
    CPU_RATE_DENOMINATOR,
    CPU_RATE_NUMERATOR,
    convert_capture,
    measure_frequency,
    read_capture,
    sha256_bytes,
    validate_mixer_events,
    wav_bytes,
)


ALL_SCENARIOS = (
    "pulse1", "pulse2", "triangle", "noise", "dmc", "combined",
    "silence", "silence_transition", "melody",
)
CHANNEL_ATTRIBUTE = {
    "pulse1": "pulse1",
    "pulse2": "pulse2",
    "triangle": "triangle",
    "noise": "noise",
    "dmc": "dmc",
}
EXPECTED_WRITE_ADDRESSES = {
    "pulse1": {0x4000, 0x4002, 0x4003, 0x4015},
    "pulse2": {0x4004, 0x4006, 0x4007, 0x4015},
    "triangle": {0x4008, 0x400A, 0x400B, 0x4015},
    "noise": {0x400C, 0x400E, 0x400F, 0x4015},
    "dmc": {0x4010, 0x4011, 0x4012, 0x4013, 0x4015},
}
TONE_TIMERS = {"pulse1": 253, "pulse2": 169, "triangle": 126}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def expected_frequency(scenario: str) -> float:
    timer = TONE_TIMERS[scenario]
    divisor = 32 if scenario == "triangle" else 16
    return (
        CPU_RATE_NUMERATOR
        / CPU_RATE_DENOMINATOR
        / (divisor * (timer + 1))
    )


def validate_channel_activity(
    scenario: str, events: tuple[AudioEvent, ...]
) -> None:
    varied = {
        channel: len({getattr(event, attribute) for event in events}) > 1
        for channel, attribute in CHANNEL_ATTRIBUTE.items()
    }
    if scenario in CHANNEL_ATTRIBUTE:
        require(varied[scenario], f"{scenario}: selected channel did not vary")
    if scenario == "combined":
        require(all(varied.values()), "combined: not all five channels varied")
    if scenario == "silence":
        require(not any(varied.values()), "silence: a raw channel changed")
    if scenario in ("silence_transition", "melody"):
        require(varied["pulse1"], f"{scenario}: pulse 1 did not vary")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-dir", type=Path, default=Path("build/audio"))
    parser.add_argument(
        "--rom-reference", type=Path,
        default=Path("build/sim/phase5j_rom_reference.json"),
    )
    parser.add_argument("--metrics", type=Path)
    parser.add_argument(
        "--scenarios", default=",".join(ALL_SCENARIOS),
        help="comma-separated scenario subset",
    )
    parser.add_argument(
        "--determinism-copy", type=Path,
        help="second combined capture that must match byte-for-byte",
    )
    args = parser.parse_args()

    scenarios = tuple(item for item in args.scenarios.split(",") if item)
    unknown = sorted(set(scenarios) - set(ALL_SCENARIOS))
    if unknown:
        parser.error(f"unknown scenario(s): {', '.join(unknown)}")
    reference = json.loads(args.rom_reference.read_text(encoding="utf-8"))
    report: dict[str, dict[str, object]] = {}

    for scenario in scenarios:
        capture_path = args.capture_dir / f"phase5j_{scenario}.apucap"
        capture_bytes = capture_path.read_bytes()
        capture = read_capture(capture_path)
        require(capture.scenario == scenario, f"{scenario}: metadata name mismatch")
        require(capture.instructions > 0, f"{scenario}: no CPU instructions")
        require(capture.writes, f"{scenario}: no CPU-driven APU writes")
        require(
            all(0x8000 <= write.pc <= 0xFFFF for write in capture.writes),
            f"{scenario}: APU write lacks a ROM PC",
        )
        write_addresses = {write.address for write in capture.writes}
        expected_writes = EXPECTED_WRITE_ADDRESSES.get(scenario)
        if expected_writes is not None:
            require(
                expected_writes <= write_addresses,
                f"{scenario}: missing expected APU register writes",
            )

        validate_mixer_events(capture)
        validate_channel_activity(scenario, capture.events)
        result = convert_capture(capture)
        encoded = wav_bytes(result)
        wav_path = args.capture_dir / f"phase5j_{scenario}.wav"
        wav_path.write_bytes(encoded)
        expected_samples = (
            2 * capture.cpu_cycles * result.sample_rate * CPU_RATE_DENOMINATOR
            + CPU_RATE_NUMERATOR
        ) // (2 * CPU_RATE_NUMERATOR)
        require(
            len(result.samples) == expected_samples,
            f"{scenario}: rational sample count mismatch",
        )
        require(result.clipping_count == 0, f"{scenario}: PCM clipped")

        metrics: dict[str, object] = {
            "duration_seconds": len(result.samples) / result.sample_rate,
            "sample_count": len(result.samples),
            "sample_rate": result.sample_rate,
            "peak": result.peak,
            "rms": result.rms,
            "clipping_count": result.clipping_count,
            "instructions": capture.instructions,
            "apu_writes": len(capture.writes),
            "dmc_fetches": len(capture.fetches),
            "mixer_events": len(capture.events),
            "mixer_mismatches": 0,
            "pause_events": len(capture.pauses),
            "reset_events": len(capture.resets),
            "capture_sha256": hashlib.sha256(capture_bytes).hexdigest(),
            "wav_sha256": sha256_bytes(encoded),
        }
        if scenario in TONE_TIMERS:
            expected_hz = expected_frequency(scenario)
            measured_hz = measure_frequency(result.samples, result.sample_rate)
            error_percent = abs(measured_hz - expected_hz) * 100.0 / expected_hz
            require(
                error_percent <= 0.25,
                f"{scenario}: frequency error {error_percent:.3f}%",
            )
            metrics.update(
                expected_frequency_hz=expected_hz,
                measured_frequency_hz=measured_hz,
                frequency_error_percent=error_percent,
            )

        if scenario in ("dmc", "combined"):
            sample = bytes.fromhex(reference[scenario]["dmc_sample_hex"])
            require(
                len(capture.fetches) >= len(sample),
                f"{scenario}: insufficient DMC ROM fetches",
            )
            first = capture.fetches[: len(sample)]
            require(
                bytes(fetch.data for fetch in first) == sample,
                f"{scenario}: DMC bytes differ from generated ROM",
            )
            require(
                tuple(fetch.address for fetch in first)
                == tuple(0xE000 + index for index in range(len(sample))),
                f"{scenario}: DMC fetch addresses are not E000..E010",
            )

        if scenario == "combined":
            require(
                len(capture.pauses) == 1
                and capture.pauses[0].fabric_cycles == 96,
                "combined: debugger pause evidence is missing",
            )
        if scenario == "silence":
            require(
                set(result.samples) == {0},
                "silence: PCM is not exactly centered zero",
            )
        if scenario == "silence_transition":
            require(
                [event.asserted for event in capture.resets] == [True, False],
                "silence_transition: reset evidence is missing",
            )
            require(
                capture.events[0].pulse1 == 0
                and capture.events[-1].pulse1 == 0
                and any(event.pulse1 for event in capture.events),
                "silence_transition: expected silence/tone/silence sequence missing",
            )
        if scenario == "melody":
            timer_low_writes = [
                write for write in capture.writes if write.address == 0x4002
            ]
            require(
                len(timer_low_writes) >= 12
                and len({write.data for write in timer_low_writes}) >= 5,
                "melody: CPU did not program the original note sequence",
            )

        report[scenario] = metrics

    if args.determinism_copy is not None:
        first_path = args.capture_dir / "phase5j_combined.apucap"
        first_bytes = first_path.read_bytes()
        second_bytes = args.determinism_copy.read_bytes()
        require(first_bytes == second_bytes, "repeated RTL capture bytes differ")
        first_capture = read_capture(first_path)
        second_capture = read_capture(args.determinism_copy)
        require(
            convert_capture(first_capture) == convert_capture(second_capture),
            "repeated PCM samples differ",
        )
        require(
            wav_bytes(convert_capture(first_capture))
            == wav_bytes(convert_capture(second_capture)),
            "repeated WAV bytes differ",
        )
        report["determinism"] = {
            "capture_sha256": hashlib.sha256(first_bytes).hexdigest(),
            "wav_sha256": sha256_bytes(wav_bytes(convert_capture(first_capture))),
            "identical_capture": True,
            "identical_pcm": True,
            "identical_wav": True,
        }

    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    metrics_path = args.metrics or args.capture_dir / "phase5j_metrics.json"
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_path.write_text(rendered, encoding="utf-8")
    for scenario in scenarios:
        item = report[scenario]
        frequency = item.get("measured_frequency_hz")
        frequency_text = "" if frequency is None else f" freq={frequency:.3f}Hz"
        print(
            f"{scenario:18s} {item['duration_seconds']:.3f}s "
            f"{item['sample_count']:6d} samples peak={item['peak']:5d} "
            f"rms={item['rms']:.2f}{frequency_text}"
        )
    print(f"PASS: Phase 5J RTL audio validation ({len(scenarios)} scenarios)")
    print(f"Metrics: {metrics_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2) from error
