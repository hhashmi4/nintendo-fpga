#!/usr/bin/env python3
"""Deterministic completeness and counter-reset vectors from independent models."""
from pathlib import Path
from random import Random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verification.system_integration import FrameAdmission, FaultCounterObserver


def generate(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    random = Random(0x60072026)
    model = FrameAdmission()
    rows = 0
    with (output / "frames.txt").open("w") as stream:
        def emit(reset=0, start=0, valid=0, x=0, y=0, frozen=0):
            nonlocal model, rows
            if reset:
                model = FrameAdmission()
                complete = False
            else:
                complete = model.sample(start=bool(start), valid=bool(valid),
                                        x=x, y=y, frozen=bool(frozen))
            stream.write(f"{reset} {start} {valid} {frozen} {x} {y} "
                         f"{int(complete)} {model.captured} "
                         f"{int(model.sequence_error)} {int(model.range_error)}\n")
            rows += 1

        for epoch in range(4):
            for _ in range(10):
                emit(reset=1)
            for _ in range(10):
                emit()
            # A terminal coordinate alone is not proof of a complete frame.
            emit(start=1, valid=1)
            emit(valid=1, x=255, y=239)
            for _ in range(8):
                emit(start=1)
                for _ in range(random.randrange(2, 30)):
                    emit(valid=1, x=random.randrange(256), y=random.randrange(256))
                emit(valid=1, x=255, y=239)
            # Recover without global reset; sticky fault history remains.
            emit(start=1, valid=1)
            emit(start=1)  # interrupted source frame, then a fresh complete one
            for index in range(61440):
                emit(valid=1, x=index % 256, y=index // 256)
                if random.randrange(64) == 0:
                    emit()
            for _ in range(30):
                emit()
    observers = [FaultCounterObserver(), FaultCounterObserver()]
    counts = [0, 0]
    with (output / "counters.txt").open("w") as stream:
        for row in range(10000):
            expected = 0
            for index in range(2):
                counts[index] = (0 if row % 17 == 0 else
                                 min(0xFFFFFFFF, counts[index] + random.randrange(4)))
                expected |= int(observers[index].observe(counts[index])) << index
            stream.write(f"{counts[0]:08x} {counts[1]:08x} {expected:x}\n")
    print(f"Phase 6G vectors: seed=60072026 framebuffer_cycles={rows} counter_cycles=10000")


if __name__ == "__main__":
    generate(Path("build/phase6g/vectors"))
