#!/usr/bin/env python3
"""Compare Phase 5M RTL results with the independent Python model."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from software.nes_debug.model import DiagnosticReferenceModel
from software.nes_debug.mmio_registers import EVENT_NMI, TRACE_DEPTH


def parse_metrics(path: Path) -> dict[str, int]:
    result: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        name, value = line.split("=", 1)
        result[name] = int(value, 0)
    return result


def expected_metrics() -> dict[str, int]:
    model = DiagnosticReferenceModel()
    model.counters["cpu_rollover"] = 0xFFFF_FFFE
    model.tick("cpu_rollover")
    model.tick("cpu_rollover")
    model.trace.arm()
    for event_index in range(18):
        model.trace.add(event_index, EVENT_NMI, 0x9000 + event_index)
    ordered_trace = model.trace.ordered()
    return {
        "cpu_rollover": model.counters["cpu_rollover"],
        "trace_count": model.trace.count,
        "trace_overflow": model.trace.overflow,
        "trace_write_index": model.trace.write_index,
        "trace_depth": TRACE_DEPTH,
        "trace_oldest_payload": ordered_trace[0].payload,
        "trace_newest_payload": ordered_trace[-1].payload,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("metrics", type=Path)
    args = parser.parse_args()
    actual = parse_metrics(args.metrics)
    expected = expected_metrics()
    if actual != expected:
        raise SystemExit(f"RTL/model mismatch: actual={actual}, expected={expected}")
    print(
        "Phase 5M independent model comparison passed: "
        f"{len(expected)} metrics"
    )


if __name__ == "__main__":
    main()
