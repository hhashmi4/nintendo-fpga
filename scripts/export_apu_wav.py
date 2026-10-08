#!/usr/bin/env python3
"""Convert an actual Phase 5J RTL APU capture to deterministic PCM/WAV."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from verification.apu_audio import (
    CaptureFormatError,
    convert_capture,
    measure_frequency,
    read_capture,
    sha256_bytes,
    wav_bytes,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export real RTL NES APU Q0.20 capture data as mono PCM WAV"
    )
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--metrics-json", type=Path)
    parser.add_argument(
        "--measure-frequency", action="store_true",
        help="include a positive-going zero-crossing frequency estimate",
    )
    args = parser.parse_args()

    try:
        capture_bytes = args.capture.read_bytes()
        capture = read_capture(args.capture)
        result = convert_capture(capture)
        encoded = wav_bytes(result)
    except (OSError, CaptureFormatError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(encoded)
    metrics: dict[str, object] = {
        "scenario": capture.scenario,
        "duration_seconds": result.duration_seconds,
        "sample_count": len(result.samples),
        "sample_rate": result.sample_rate,
        "channels": 1,
        "bits_per_sample": 16,
        "peak": result.peak,
        "rms": result.rms,
        "clipping_count": result.clipping_count,
        "apu_writes": len(capture.writes),
        "dmc_fetches": len(capture.fetches),
        "instructions": capture.instructions,
        "capture_sha256": hashlib.sha256(capture_bytes).hexdigest(),
        "wav_sha256": sha256_bytes(encoded),
    }
    if args.measure_frequency:
        try:
            metrics["measured_frequency_hz"] = measure_frequency(
                result.samples, result.sample_rate
            )
        except ValueError as error:
            print(f"ERROR: cannot measure frequency: {error}", file=sys.stderr)
            return 2
    rendered = json.dumps(metrics, indent=2, sort_keys=True)
    print(rendered)
    if args.metrics_json:
        args.metrics_json.parent.mkdir(parents=True, exist_ok=True)
        args.metrics_json.write_text(rendered + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
