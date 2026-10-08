"""Deterministic Phase 5J NES APU capture, resampling, and PCM helpers."""

from __future__ import annotations

import bisect
import hashlib
import math
import struct
from dataclasses import dataclass
from pathlib import Path

from verification.apu_audio_fir import (
    FIR_COEFFICIENT_BITS,
    FIR_COEFFICIENTS,
    FIR_CUTOFF_HZ,
    FIR_TAP_COUNT,
)
from verification.apu_mixer import quantized_mix


CAPTURE_MAGIC = "NESAPU_CAPTURE_V1"
CPU_RATE_NUMERATOR = 19_687_500
CPU_RATE_DENOMINATOR = 11
DEFAULT_SAMPLE_RATE = 48_000
PCM_BITS = 16
MIXER_FRACTION_BITS = 20
DC_BLOCK_HZ = 10
DC_BLOCK_Q30 = 1_072_337_219
PCM_GAIN_NUMERATOR = 3
PCM_GAIN_DENOMINATOR = 4
MAX_CAPTURE_CYCLES = 20_000_000
MAX_CAPTURE_BYTES = 256 * 1024 * 1024


class CaptureFormatError(ValueError):
    """Raised when an RTL audio capture is malformed or inconsistent."""


@dataclass(frozen=True)
class AudioEvent:
    cycle: int
    mixed: int
    pulse1: int
    pulse2: int
    triangle: int
    noise: int
    dmc: int
    flags: int


@dataclass(frozen=True)
class ApuWrite:
    cycle: int
    pc: int
    address: int
    data: int


@dataclass(frozen=True)
class DmcFetch:
    cycle: int
    address: int
    data: int


@dataclass(frozen=True)
class PauseEvent:
    cycle: int
    fabric_cycles: int


@dataclass(frozen=True)
class ResetEvent:
    cycle: int
    asserted: bool


@dataclass(frozen=True)
class ApuCapture:
    scenario: str
    cpu_cycles: int
    audio_start_cycle: int
    events: tuple[AudioEvent, ...]
    writes: tuple[ApuWrite, ...]
    fetches: tuple[DmcFetch, ...]
    pauses: tuple[PauseEvent, ...]
    resets: tuple[ResetEvent, ...]
    instructions: int
    metadata: dict[str, str]


@dataclass(frozen=True)
class PcmResult:
    samples: tuple[int, ...]
    sample_rate: int
    clipping_count: int

    @property
    def duration_seconds(self) -> float:
        return len(self.samples) / self.sample_rate

    @property
    def peak(self) -> int:
        return max((abs(value) for value in self.samples), default=0)

    @property
    def rms(self) -> float:
        if not self.samples:
            return 0.0
        return math.sqrt(
            sum(value * value for value in self.samples) / len(self.samples)
        )


def _integer(text: str, *, name: str, minimum: int, maximum: int) -> int:
    try:
        value = int(text, 0)
    except ValueError as error:
        raise CaptureFormatError(f"{name} is not an integer: {text!r}") from error
    if not minimum <= value <= maximum:
        raise CaptureFormatError(
            f"{name} must be in {minimum}..{maximum}, got {value}"
        )
    return value


def read_capture(path: Path) -> ApuCapture:
    """Parse and strictly validate the bounded text capture emitted by RTL."""

    try:
        if path.stat().st_size > MAX_CAPTURE_BYTES:
            raise CaptureFormatError(
                f"capture exceeds the {MAX_CAPTURE_BYTES}-byte safety limit"
            )
        lines = path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeError) as error:
        raise CaptureFormatError(f"cannot read capture {path}: {error}") from error
    if not lines or lines[0] != CAPTURE_MAGIC:
        raise CaptureFormatError(f"{path} does not start with {CAPTURE_MAGIC}")

    metadata: dict[str, str] = {}
    events: list[AudioEvent] = []
    writes: list[ApuWrite] = []
    fetches: list[DmcFetch] = []
    pauses: list[PauseEvent] = []
    resets: list[ResetEvent] = []
    audio_start_cycle: int | None = None
    end_fields: list[str] | None = None
    instructions = 0
    instruction_record_seen = False
    in_records = False

    for line_number, raw_line in enumerate(lines[1:], 2):
        line = raw_line.strip()
        if not line:
            continue
        if not in_records:
            if line == "BEGIN":
                in_records = True
                continue
            if "=" not in line:
                raise CaptureFormatError(
                    f"line {line_number}: expected key=value or BEGIN"
                )
            key, value = line.split("=", 1)
            if not key or key in metadata:
                raise CaptureFormatError(
                    f"line {line_number}: invalid or duplicate metadata key"
                )
            metadata[key] = value
            continue

        fields = line.split()
        kind = fields[0]
        if end_fields is not None:
            raise CaptureFormatError(
                f"line {line_number}: record appears after END"
            )
        try:
            if kind == "S" and len(fields) == 2:
                if audio_start_cycle is not None:
                    raise CaptureFormatError("duplicate audio start record")
                audio_start_cycle = _integer(
                    fields[1], name="audio start cycle", minimum=0,
                    maximum=MAX_CAPTURE_CYCLES * 4,
                )
            elif kind == "A" and len(fields) == 9:
                event = AudioEvent(
                    cycle=_integer(fields[1], name="event cycle", minimum=0,
                                   maximum=MAX_CAPTURE_CYCLES),
                    mixed=_integer(fields[2], name="mixed", minimum=0,
                                   maximum=(1 << MIXER_FRACTION_BITS) - 1),
                    pulse1=_integer(fields[3], name="pulse1", minimum=0,
                                    maximum=15),
                    pulse2=_integer(fields[4], name="pulse2", minimum=0,
                                    maximum=15),
                    triangle=_integer(fields[5], name="triangle", minimum=0,
                                      maximum=15),
                    noise=_integer(fields[6], name="noise", minimum=0,
                                   maximum=15),
                    dmc=_integer(fields[7], name="dmc", minimum=0, maximum=127),
                    flags=_integer(fields[8], name="flags", minimum=0,
                                   maximum=255),
                )
                if events and event.cycle <= events[-1].cycle:
                    raise CaptureFormatError("audio event cycles must increase")
                events.append(event)
            elif kind == "W" and len(fields) == 5:
                writes.append(
                    ApuWrite(
                        cycle=_integer(fields[1], name="write cycle", minimum=0,
                                       maximum=MAX_CAPTURE_CYCLES * 4),
                        pc=_integer(fields[2], name="write PC", minimum=0,
                                    maximum=0xFFFF),
                        address=_integer(fields[3], name="write address", minimum=0,
                                         maximum=0xFFFF),
                        data=_integer(fields[4], name="write data", minimum=0,
                                      maximum=0xFF),
                    )
                )
            elif kind == "F" and len(fields) == 4:
                fetches.append(
                    DmcFetch(
                        cycle=_integer(fields[1], name="fetch cycle", minimum=0,
                                       maximum=MAX_CAPTURE_CYCLES * 4),
                        address=_integer(fields[2], name="fetch address", minimum=0,
                                         maximum=0xFFFF),
                        data=_integer(fields[3], name="fetch data", minimum=0,
                                      maximum=0xFF),
                    )
                )
            elif kind == "P" and len(fields) == 3:
                pauses.append(
                    PauseEvent(
                        cycle=_integer(fields[1], name="pause cycle", minimum=0,
                                       maximum=MAX_CAPTURE_CYCLES),
                        fabric_cycles=_integer(
                            fields[2], name="pause fabric cycles", minimum=1,
                            maximum=1_000_000,
                        ),
                    )
                )
            elif kind == "R" and len(fields) == 3:
                resets.append(
                    ResetEvent(
                        cycle=_integer(fields[1], name="reset cycle", minimum=0,
                                       maximum=MAX_CAPTURE_CYCLES),
                        asserted=bool(_integer(fields[2], name="reset state", minimum=0,
                                               maximum=1)),
                    )
                )
            elif kind == "I" and len(fields) == 2:
                if instruction_record_seen:
                    raise CaptureFormatError("duplicate instruction-count record")
                instructions = _integer(
                    fields[1], name="instructions", minimum=1,
                    maximum=MAX_CAPTURE_CYCLES * 4,
                )
                instruction_record_seen = True
            elif kind == "END" and len(fields) == 5:
                if end_fields is not None:
                    raise CaptureFormatError("duplicate END record")
                end_fields = fields
            else:
                raise CaptureFormatError(
                    f"line {line_number}: unknown or malformed {kind!r} record"
                )
        except CaptureFormatError as error:
            raise CaptureFormatError(f"line {line_number}: {error}") from error

    required = {
        "scenario", "cpu_rate_num", "cpu_rate_den", "cpu_cycles",
        "mixer_q_bits", "mixer_latency_fabric_cycles", "pause_policy",
    }
    missing = sorted(required - metadata.keys())
    if missing:
        raise CaptureFormatError(f"missing metadata: {', '.join(missing)}")
    if metadata["cpu_rate_num"] != str(CPU_RATE_NUMERATOR):
        raise CaptureFormatError(
            "capture CPU-rate numerator does not match NTSC policy"
        )
    if metadata["cpu_rate_den"] != str(CPU_RATE_DENOMINATOR):
        raise CaptureFormatError(
            "capture CPU-rate denominator does not match NTSC policy"
        )
    if metadata["mixer_q_bits"] != str(MIXER_FRACTION_BITS):
        raise CaptureFormatError("capture mixer format is not Q0.20")
    if metadata["mixer_latency_fabric_cycles"] != "1":
        raise CaptureFormatError("capture does not declare the one-cycle mixer latency")
    if metadata["pause_policy"] != "omit":
        raise CaptureFormatError("unsupported paused-time policy")
    cpu_cycles = _integer(
        metadata["cpu_cycles"], name="cpu_cycles", minimum=1,
        maximum=MAX_CAPTURE_CYCLES,
    )
    if audio_start_cycle is None or not events or events[0].cycle != 0:
        raise CaptureFormatError(
            "capture needs an S record and an A record at cycle zero"
        )
    if any(event.cycle >= cpu_cycles for event in events):
        raise CaptureFormatError("audio event lies outside declared duration")
    if end_fields is None:
        raise CaptureFormatError("capture has no END record")
    end_cycles = _integer(end_fields[1], name="END cycles", minimum=1,
                          maximum=MAX_CAPTURE_CYCLES)
    end_records = tuple(
        _integer(value, name="END count", minimum=0, maximum=MAX_CAPTURE_CYCLES)
        for value in end_fields[2:]
    )
    if end_cycles != cpu_cycles:
        raise CaptureFormatError("END cycle count disagrees with metadata")
    if end_records != (len(events), len(writes), len(fetches)):
        raise CaptureFormatError("END record counts disagree with parsed records")

    if not instruction_record_seen:
        raise CaptureFormatError("capture has no instruction-count record")
    return ApuCapture(
        scenario=metadata["scenario"], cpu_cycles=cpu_cycles,
        audio_start_cycle=audio_start_cycle, events=tuple(events),
        writes=tuple(writes), fetches=tuple(fetches), pauses=tuple(pauses),
        resets=tuple(resets), instructions=instructions, metadata=metadata,
    )


def validate_mixer_events(capture: ApuCapture) -> None:
    """Check every captured Q0.20 change against the independent mixer model."""

    for event in capture.events:
        expected = quantized_mix(
            event.pulse1, event.pulse2, event.triangle, event.noise, event.dmc
        )
        if event.mixed != expected:
            raise CaptureFormatError(
                f"cycle {event.cycle}: mixer {event.mixed:#x} != {expected:#x}"
            )


def _round_divide(numerator: int, denominator: int) -> int:
    if denominator <= 0:
        raise ValueError("denominator must be positive")
    if numerator < 0:
        return -_round_divide(-numerator, denominator)
    return (2 * numerator + denominator) // (2 * denominator)


class _EventFir:
    def __init__(self, capture: ApuCapture):
        self.cycles = [event.cycle for event in capture.events]
        self.values = [event.mixed for event in capture.events]
        prefix = [0]
        for coefficient in FIR_COEFFICIENTS:
            prefix.append(prefix[-1] + coefficient)
        self.prefix = prefix
        self.last_cycle = capture.cpu_cycles - 1
        self.middle = FIR_TAP_COUNT // 2
        self.cache: dict[int, int] = {}

    def value_at(self, cycle: int) -> int:
        if cycle <= 0:
            return self.values[0]
        if cycle >= self.last_cycle:
            cycle = self.last_cycle
        return self.values[bisect.bisect_right(self.cycles, cycle) - 1]

    def filtered_at(self, center: int) -> int:
        cached = self.cache.get(center)
        if cached is not None:
            return cached
        low = center - self.middle
        high = center + self.middle
        position = low
        total = 0
        while position <= high:
            clipped = min(max(position, 0), self.last_cycle)
            event_index = bisect.bisect_right(self.cycles, clipped) - 1
            event_index = max(event_index, 0)
            if position < 0:
                segment_end = min(high, -1)
                value = self.values[0]
            elif position >= self.last_cycle:
                segment_end = high
                value = self.value_at(self.last_cycle)
            else:
                next_change = (
                    self.cycles[event_index + 1]
                    if event_index + 1 < len(self.cycles)
                    else self.last_cycle + 1
                )
                segment_end = min(high, next_change - 1, self.last_cycle - 1)
                value = self.values[event_index]
            first_tap = position - low
            last_tap = segment_end - low
            total += value * (
                self.prefix[last_tap + 1] - self.prefix[first_tap]
            )
            position = segment_end + 1
        result = _round_divide(total, 1 << FIR_COEFFICIENT_BITS)
        self.cache[center] = result
        return result


def pcm_sample_count(cpu_cycles: int, sample_rate: int = DEFAULT_SAMPLE_RATE) -> int:
    """Return the nearest whole output-sample duration using exact integers."""

    if cpu_cycles <= 0 or sample_rate <= 0:
        raise ValueError("cycle count and sample rate must be positive")
    return _round_divide(
        cpu_cycles * sample_rate * CPU_RATE_DENOMINATOR,
        CPU_RATE_NUMERATOR,
    )


def convert_capture(
    capture: ApuCapture, sample_rate: int = DEFAULT_SAMPLE_RATE
) -> PcmResult:
    """Low-pass, rationally resample, DC-block, gain, round, and saturate."""

    if sample_rate != DEFAULT_SAMPLE_RATE:
        raise ValueError("Phase 5J supports the fixed 48 kHz output policy")
    validate_mixer_events(capture)
    event_filter = _EventFir(capture)
    output_count = pcm_sample_count(capture.cpu_cycles, sample_rate)
    position_denominator = CPU_RATE_DENOMINATOR * sample_rate
    # Treat the capture's constant left extension as pre-existing steady state.
    # This makes digital silence exactly centered instead of manufacturing a
    # high-pass start-up transient from the unsigned mixer DC level.
    previous_input = event_filter.filtered_at(0)
    previous_highpass = 0
    samples: list[int] = []
    clipping_count = 0

    for output_index in range(output_count):
        position_numerator = output_index * CPU_RATE_NUMERATOR
        base, fraction = divmod(position_numerator, position_denominator)
        filtered = event_filter.filtered_at(base)
        if fraction:
            following = event_filter.filtered_at(base + 1)
            filtered = _round_divide(
                filtered * (position_denominator - fraction)
                + following * fraction,
                position_denominator,
            )
        highpass = filtered - previous_input + _round_divide(
            DC_BLOCK_Q30 * previous_highpass, 1 << 30
        )
        previous_input = filtered
        previous_highpass = highpass
        pcm = _round_divide(
            highpass * 32_767 * PCM_GAIN_NUMERATOR,
            (1 << MIXER_FRACTION_BITS) * PCM_GAIN_DENOMINATOR,
        )
        if pcm > 32_767:
            pcm = 32_767
            clipping_count += 1
        elif pcm < -32_768:
            pcm = -32_768
            clipping_count += 1
        samples.append(pcm)
    return PcmResult(tuple(samples), sample_rate, clipping_count)


def wav_bytes(result: PcmResult) -> bytes:
    """Encode deterministic mono signed-16-bit little-endian PCM RIFF/WAVE."""

    data = struct.pack(f"<{len(result.samples)}h", *result.samples)
    byte_rate = result.sample_rate * 2
    header = b"".join(
        (
            b"RIFF", struct.pack("<I", 36 + len(data)), b"WAVE",
            b"fmt ", struct.pack("<IHHIIHH", 16, 1, 1, result.sample_rate,
                                  byte_rate, 2, PCM_BITS),
            b"data", struct.pack("<I", len(data)),
        )
    )
    return header + data


def write_wav(path: Path, result: PcmResult) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(wav_bytes(result))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def measure_frequency(samples: tuple[int, ...], sample_rate: int) -> float:
    """Measure a tonal fundamental from positive-going PCM zero crossings."""

    if len(samples) < sample_rate // 20:
        raise ValueError("at least 50 ms of PCM is required")
    start = min(sample_rate // 50, len(samples) // 4)
    crossings: list[float] = []
    for index in range(max(start, 1), len(samples)):
        before = samples[index - 1]
        after = samples[index]
        if before < 0 <= after and after != before:
            crossings.append(index - 1 + (-before) / (after - before))
    if len(crossings) < 3:
        raise ValueError("not enough zero crossings for a frequency estimate")
    periods = sorted(
        right - left for left, right in zip(crossings, crossings[1:])
    )
    middle = len(periods) // 2
    if len(periods) % 2:
        median_period = periods[middle]
    else:
        median_period = (periods[middle - 1] + periods[middle]) / 2.0
    return sample_rate / median_period


def fir_response(frequency_hz: int) -> float:
    """Return the FIR magnitude at one frequency for verification/reporting."""

    angular = (
        2.0 * math.pi * frequency_hz * CPU_RATE_DENOMINATOR
        / CPU_RATE_NUMERATOR
    )
    real = 0.0
    imaginary = 0.0
    scale = 1 << FIR_COEFFICIENT_BITS
    for index, coefficient in enumerate(FIR_COEFFICIENTS):
        phase = angular * (index - FIR_TAP_COUNT // 2)
        real += coefficient * math.cos(phase) / scale
        imaginary -= coefficient * math.sin(phase) / scale
    return math.hypot(real, imaginary)


__all__ = [
    "ApuCapture", "CaptureFormatError", "DC_BLOCK_HZ", "DEFAULT_SAMPLE_RATE",
    "FIR_CUTOFF_HZ", "FIR_TAP_COUNT", "PcmResult", "convert_capture",
    "fir_response", "measure_frequency", "pcm_sample_count", "read_capture",
    "sha256_bytes", "validate_mixer_events", "wav_bytes", "write_wav",
]
