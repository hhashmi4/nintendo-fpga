"""Independent executable model of the Phase 5M diagnostic semantics."""

from __future__ import annotations

from dataclasses import dataclass

from .mmio_registers import FAULT_NAMES, TRACE_DEPTH


UINT32_MASK = 0xFFFF_FFFF
UNAVAILABLE_WORD = UINT32_MASK


def increment_u32(value: int, amount: int = 1) -> int:
    """Hardware counters wrap modulo 2**32."""

    return (value + amount) & UINT32_MASK


@dataclass(frozen=True)
class TraceEvent:
    timestamp: int
    code: int
    payload: int


class FaultLatch:
    def __init__(self) -> None:
        self.flags = 0
        self.last_code = 0

    def observe(self, code: int) -> None:
        if code not in FAULT_NAMES:
            raise ValueError(f"unknown fault code {code}")
        self.flags |= 1 << (code - 1)
        self.last_code = code

    def clear(self, mask: int) -> None:
        self.flags &= ~mask & UINT32_MASK
        if self.flags == 0:
            self.last_code = 0


class TraceBuffer:
    """Circular trace model; ordered() returns oldest-to-newest events."""

    def __init__(self, depth: int = TRACE_DEPTH) -> None:
        if depth <= 0:
            raise ValueError("trace depth must be positive")
        self.depth = depth
        self.entries: list[TraceEvent | None] = [None] * depth
        self.write_index = 0
        self.count = 0
        self.overflow = 0
        self.armed = False
        self.triggered = False
        self.frozen = False

    def clear(self) -> None:
        self.entries = [None] * self.depth
        self.write_index = 0
        self.count = 0
        self.overflow = 0
        self.triggered = False
        self.frozen = False

    def arm(self) -> None:
        self.armed = True
        self.triggered = False
        self.frozen = False

    def add(self, timestamp: int, code: int, payload: int = 0) -> None:
        if not self.armed or self.frozen:
            return
        self.entries[self.write_index] = TraceEvent(
            timestamp & UINT32_MASK, code & 0xFF, payload & 0xFF_FFFF
        )
        self.write_index = (self.write_index + 1) % self.depth
        if self.count < self.depth:
            self.count += 1
        else:
            self.overflow = increment_u32(self.overflow)

    def trigger(self) -> None:
        self.armed = False
        self.triggered = True
        self.frozen = True

    def freeze(self) -> None:
        self.armed = False
        self.frozen = True

    def ordered(self) -> tuple[TraceEvent, ...]:
        if self.count == 0:
            return ()
        start = 0 if self.count < self.depth else self.write_index
        result: list[TraceEvent] = []
        for offset in range(self.count):
            entry = self.entries[(start + offset) % self.depth]
            if entry is not None:
                result.append(entry)
        return tuple(result)


class SnapshotModel:
    """Live words and an atomic, stable copied snapshot."""

    def __init__(self) -> None:
        self.live: dict[str, int | None] = {}
        self.captured: dict[str, int | None] = {}
        self.sequence = 0

    def set(self, name: str, value: int | None) -> None:
        self.live[name] = None if value is None else value & UINT32_MASK

    def capture(self) -> None:
        self.captured = dict(self.live)
        self.sequence = increment_u32(self.sequence)

    def encoded(self, name: str) -> int:
        value = self.captured.get(name)
        return UNAVAILABLE_WORD if value is None else value


class DiagnosticReferenceModel:
    """Composition used by fault-injection and RTL comparison tests."""

    def __init__(self, trace_depth: int = TRACE_DEPTH) -> None:
        self.counters: dict[str, int] = {}
        self.faults = FaultLatch()
        self.trace = TraceBuffer(trace_depth)
        self.snapshot = SnapshotModel()

    def tick(self, name: str, amount: int = 1) -> int:
        value = increment_u32(self.counters.get(name, 0), amount)
        self.counters[name] = value
        return value

    def capture(self) -> dict[str, int]:
        for name, value in self.counters.items():
            self.snapshot.set(name, value)
        self.snapshot.set("fault_flags", self.faults.flags)
        self.snapshot.set("last_fault", self.faults.last_code)
        self.snapshot.set("trace_count", self.trace.count)
        self.snapshot.set("trace_overflow", self.trace.overflow)
        self.snapshot.capture()
        return {
            name: self.snapshot.encoded(name) for name in self.snapshot.captured
        }
