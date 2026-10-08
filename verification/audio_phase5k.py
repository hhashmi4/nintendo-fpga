"""Independent Phase 5K real-time audio reference model.

The model is deliberately organized around mathematical transactions rather
than RTL states.  It supplies fixed FIR coefficients, exact rational sample
scheduling, conditioning, FIFO, I2S, and WM8731 initialization references.
"""

from __future__ import annotations

import cmath
import math
from collections import deque
from dataclasses import dataclass
from typing import Iterable


CPU_RATE_NUMERATOR = 19_687_500
CPU_RATE_DENOMINATOR = 11
SAMPLE_RATE = 48_000
SAMPLE_PHASE_INCREMENT = 352
SAMPLE_PHASE_MODULUS = 13_125
FIR_TAPS = 961
FIR_CUTOFF_HZ = 19_000
FIR_COEFFICIENT_BITS = 18
MIXER_FRACTION_BITS = 20
DC_BLOCK_Q30 = 1_072_337_219
PCM_GAIN_NUMERATOR = 3
PCM_GAIN_DENOMINATOR = 4


def _round_half_away(value: float) -> int:
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def fir_coefficients() -> tuple[int, ...]:
    """Return the normalized, symmetric Q18 Blackman-window FIR."""

    rate = CPU_RATE_NUMERATOR / CPU_RATE_DENOMINATOR
    middle = (FIR_TAPS - 1) / 2
    floating: list[float] = []
    for index in range(FIR_TAPS):
        offset = index - middle
        argument = 2 * FIR_CUTOFF_HZ * offset / rate
        sinc = 1.0 if offset == 0 else math.sin(math.pi * argument) / (
            math.pi * argument
        )
        window = (
            0.42
            - 0.5 * math.cos(2 * math.pi * index / (FIR_TAPS - 1))
            + 0.08 * math.cos(4 * math.pi * index / (FIR_TAPS - 1))
        )
        floating.append(2 * FIR_CUTOFF_HZ / rate * sinc * window)
    scale = (1 << FIR_COEFFICIENT_BITS) / sum(floating)
    fixed = [_round_half_away(value * scale) for value in floating]
    fixed[FIR_TAPS // 2] += (1 << FIR_COEFFICIENT_BITS) - sum(fixed)
    return tuple(fixed)


FIR_COEFFICIENTS = fir_coefficients()


def fir_response(frequency_hz: float) -> float:
    rate = CPU_RATE_NUMERATOR / CPU_RATE_DENOMINATOR
    response = sum(
        coefficient
        * cmath.exp(-2j * math.pi * frequency_hz * index / rate)
        for index, coefficient in enumerate(FIR_COEFFICIENTS)
    )
    return abs(response) / (1 << FIR_COEFFICIENT_BITS)


def sample_schedule(input_ticks: int, initial_phase: int = 0) -> tuple[int, ...]:
    """Return input-tick indices at which exact 48 kHz samples are emitted."""

    phase = initial_phase
    result: list[int] = []
    for tick in range(input_ticks):
        phase += SAMPLE_PHASE_INCREMENT
        if phase >= SAMPLE_PHASE_MODULUS:
            phase -= SAMPLE_PHASE_MODULUS
            result.append(tick)
    return tuple(result)


def round_shift(value: int, bits: int) -> int:
    magnitude = abs(value)
    rounded = (magnitude + (1 << (bits - 1))) >> bits
    return -rounded if value < 0 else rounded


def filter_samples(samples: Iterable[int]) -> tuple[int, ...]:
    """Filter input-tick samples with the causal fixed-point FIR."""

    source = tuple(samples)
    if not source:
        return ()
    history: deque[int] = deque([source[0]] * FIR_TAPS, maxlen=FIR_TAPS)
    output: list[int] = []
    for value in source:
        history.appendleft(value)
        accumulator = sum(
            sample * coefficient
            for sample, coefficient in zip(history, FIR_COEFFICIENTS)
        )
        output.append(round_shift(accumulator, FIR_COEFFICIENT_BITS))
    return tuple(output)


@dataclass
class Conditioner:
    """10 Hz Q30 DC blocker and fixed 0.75 signed-PCM converter."""

    previous_input: int = 0
    previous_output: int = 0
    initialized: bool = False
    clipping_count: int = 0

    def process(self, value: int) -> int:
        if not self.initialized:
            self.previous_input = value
            self.initialized = True
            return 0
        feedback = round_shift(self.previous_output * DC_BLOCK_Q30, 30)
        blocked = value - self.previous_input + feedback
        self.previous_input = value
        self.previous_output = blocked
        pcm = round_shift(blocked * 3, 7)
        if pcm > 32_767:
            self.clipping_count += 1
            return 32_767
        if pcm < -32_768:
            self.clipping_count += 1
            return -32_768
        return pcm


class BoundedFifo:
    def __init__(self, depth: int) -> None:
        if depth <= 0 or depth & (depth - 1):
            raise ValueError("FIFO depth must be a positive power of two")
        self.depth = depth
        self.values: deque[int] = deque()
        self.overruns = 0
        self.underruns = 0

    def write(self, value: int) -> bool:
        if len(self.values) == self.depth:
            self.overruns += 1
            return False
        self.values.append(value)
        return True

    def read(self) -> int:
        if not self.values:
            self.underruns += 1
            return 0
        return self.values.popleft()


def i2s_frame(sample: int) -> tuple[tuple[int, int], ...]:
    """Return 64 (LRCK, DACDAT) values sampled on rising BCLK edges."""

    word = sample & 0xFFFF
    left = [(0, 0)] + [(0, (word >> bit) & 1) for bit in range(15, -1, -1)]
    right = [(1, 0)] + [(1, (word >> bit) & 1) for bit in range(15, -1, -1)]
    left.extend([(0, 0)] * (32 - len(left)))
    right.extend([(1, 0)] * (32 - len(right)))
    return tuple(left + right)


def i2s_bclk_toggles(master_clock_cycles: int) -> tuple[int, ...]:
    """Return 12 MHz clock indices carrying 64/125 BCLK half-edges."""

    phase = 0
    toggles: list[int] = []
    for cycle in range(master_clock_cycles):
        phase += 64
        if phase >= 125:
            phase -= 125
            toggles.append(cycle)
    return tuple(toggles)


WM8731_REGISTER_SEQUENCE = (
    (15, 0x000),  # software reset
    (9, 0x000),   # inactive while clocking registers change
    (5, 0x008),   # DAC soft mute
    (6, 0x007),   # playback only: line/mic/ADC powered down
    (2, 0x1F0),   # -9 dB, zero crossing, simultaneous L/R load
    (4, 0x012),   # DAC selected, microphone input muted
    (7, 0x002),   # 16-bit I2S, slave, normal polarity
    (8, 0x001),   # 12.000 MHz, 250fs, 48 kHz USB mode
    (9, 0x001),   # active
    (5, 0x000),   # release DAC soft mute
)


def wm8731_write_bytes(register: int, value: int) -> tuple[int, int, int]:
    if not 0 <= register <= 0x7F or not 0 <= value <= 0x1FF:
        raise ValueError("WM8731 register/value is out of range")
    return (0x34, (register << 1) | ((value >> 8) & 1), value & 0xFF)


def diagnostic_tone(sample_index: int) -> int:
    """Known 1 kHz, quarter-scale square wave used only for bring-up."""

    return 8_192 if sample_index % 48 < 24 else -8_192
