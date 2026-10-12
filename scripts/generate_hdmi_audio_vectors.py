#!/usr/bin/env python3
"""Generate deterministic Phase 6D PCM vectors outside the source tree."""

from __future__ import annotations

import argparse
import struct
import wave
import bisect
import hashlib
import json
from collections import deque
from pathlib import Path

from verification.hdmi_audio import random_pcm, i2s_frame
from verification.apu_audio import read_capture, validate_mixer_events
from verification.audio_phase5k import (
    Conditioner, FIR_COEFFICIENTS, FIR_TAPS, round_shift, sample_schedule,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x6D48_0001)
    parser.add_argument("--count", type=int, default=256)
    parser.add_argument("--wav", type=Path)
    parser.add_argument("--offset", type=int)
    parser.add_argument("--capture", type=Path)
    arguments = parser.parse_args()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    provenance = f"seed=0x{arguments.seed:08x}"
    if arguments.capture is not None:
        capture = read_capture(arguments.capture)
        validate_mixer_events(capture)
        if capture.scenario != "melody" or not capture.writes or not capture.instructions:
            raise ValueError("expected a CPU-driven melody capture")
        start = max(0, capture.events[1].cycle - FIR_TAPS)
        event_cycles = [event.cycle for event in capture.events]
        mixed = [capture.events[bisect.bisect_right(event_cycles, start + i)-1].mixed
                 for i in range(20_000)]
        history = deque([mixed[0]] * FIR_TAPS, maxlen=FIR_TAPS)
        conditioner = Conditioner()
        schedule = set(sample_schedule(len(mixed)))
        output = []
        for tick, value in enumerate(mixed):
            history.appendleft(value)
            if tick in schedule:
                filtered = round_shift(sum(a*b for a, b in zip(history, FIR_COEFFICIENTS)), 18)
                output.append(conditioner.process(filtered))
        samples = tuple(output)
        arguments.output.with_name("phase6d_melody_mixed.hex").write_text(
            "".join(f"{sample:05x}\n" for sample in mixed), encoding="ascii")
        metadata = dict(capture=str(arguments.capture),
            capture_sha256=hashlib.sha256(arguments.capture.read_bytes()).hexdigest(),
            cpu_instructions=capture.instructions, apu_writes=len(capture.writes),
            input_cycle_offset=start, input_ticks=len(mixed), expected_pcm=len(samples),
            model="Phase5K causal Q18 FIR and fixed-point conditioner")
        arguments.output.with_suffix(".json").write_text(json.dumps(metadata, indent=2)+"\n")
        provenance = f"capture={arguments.capture} start={start} ticks={len(mixed)}"
    elif arguments.wav is None:
        samples = random_pcm(arguments.seed, arguments.count)
    else:
        with wave.open(str(arguments.wav), "rb") as source:
            if source.getnchannels() != 1 or source.getsampwidth() != 2:
                raise ValueError("source WAV must be mono signed 16-bit PCM")
            if source.getframerate() != 48_000:
                raise ValueError("source WAV must be 48 kHz")
            encoded = source.readframes(source.getnframes())
        all_samples = struct.unpack(f"<{len(encoded) // 2}h", encoded)
        if arguments.offset is None:
            first_active = next(
                (index for index, sample in enumerate(all_samples) if sample), 0
            )
            offset = max(0, first_active - 64)
        else:
            offset = arguments.offset
        samples = tuple(all_samples[offset : offset + arguments.count])
        if len(samples) != arguments.count:
            raise ValueError("source WAV does not contain the requested range")
        provenance = f"wav={arguments.wav} offset={offset}"
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        "".join(f"{sample & 0xffff:04x}\n" for sample in samples),
        encoding="ascii",
    )
    if arguments.wav is None and arguments.capture is None:
        frames = [i2s_frame(sample, muted=(sample & 31) == 13) for sample in samples]
        arguments.output.with_name("phase6d_random_i2s.hex").write_text(
            "".join(f"{sum(bit << (63-i) for i, (_, bit) in enumerate(frame)):016x}\n"
                    for frame in frames), encoding="ascii")
    print(
        f"Phase 6D vectors: {provenance} "
        f"samples={len(samples)} output={arguments.output}"
    )


if __name__ == "__main__":
    main()
