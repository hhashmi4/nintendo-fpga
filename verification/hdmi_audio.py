"""Independent Phase 6D HDMI-audio reference models.

The model is transaction- and sample-oriented.  It does not reproduce RTL
states, pointer encodings, or accumulator implementation details.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable, Mapping

from verification.hdmi_transmitter import RegisterUpdate


SAMPLE_RATE = 48_000
VIDEO_RATE = 60
SAMPLES_PER_720P60_FRAME = SAMPLE_RATE // VIDEO_RATE
SLOT_WIDTH = 32
SAMPLE_WIDTH = 16
BCLK_RATE = SAMPLE_RATE * 2 * SLOT_WIDTH
N_48KHZ = 6_144


class AudioError(IntEnum):
    NONE = 0
    CLOCK_UNLOCKED = 1
    CONFIG_NACK = 2
    CONFIG_TIMEOUT = 3
    CONFIG_VERIFY_FAILED = 4
    FIFO_UNDERRUN = 5
    FIFO_OVERRUN = 6
    LINK_LOST = 7
    RECOVERY_FAILED = 8


# Semantic transcription of the documented ADV7513 fields.  The model uses
# generic masked register updates instead of the RTL lookup implementation.
ADV7513_AUDIO_PROFILE = (
    RegisterUpdate(0x44, 0x68, 0x00, verify=False),
    RegisterUpdate(0x01, 0x0F, 0x00),
    RegisterUpdate(0x02, 0xFF, 0x18),
    RegisterUpdate(0x03, 0xFF, 0x00),
    RegisterUpdate(0x0A, 0xFC, 0x00),
    RegisterUpdate(0x0B, 0xE0, 0x00),
    RegisterUpdate(0x0C, 0xFF, 0xC4),
    RegisterUpdate(0x0E, 0x3F, 0x01),
    RegisterUpdate(0x12, 0xFF, 0x00),
    RegisterUpdate(0x14, 0x0F, 0x02),
    RegisterUpdate(0x15, 0xF0, 0x20),
    RegisterUpdate(0x4A, 0x20, 0x20, verify=False),
    RegisterUpdate(0x73, 0xFF, 0x01),
    RegisterUpdate(0x74, 0xFF, 0x00),
    RegisterUpdate(0x75, 0xFF, 0x00),
    RegisterUpdate(0x76, 0xFF, 0x00),
    RegisterUpdate(0x77, 0xFF, 0x00),
    RegisterUpdate(0x44, 0x68, 0x68),
    RegisterUpdate(0x4A, 0x20, 0x00),
)


def apply_audio_profile(
    initial: Mapping[int, int],
) -> tuple[dict[int, int], tuple[tuple[int, int], ...]]:
    registers = {address: value & 0xFF for address, value in initial.items()}
    writes: list[tuple[int, int]] = []
    for item in ADV7513_AUDIO_PROFILE:
        old = registers.get(item.address, 0)
        new = (old & (~item.mask & 0xFF)) | (item.value & item.mask)
        registers[item.address] = new
        writes.append((item.address, new))
    return registers, tuple(writes)


def verify_audio_profile(registers: Mapping[int, int]) -> bool:
    # Last writer wins for fields touched more than once.
    expected, _ = apply_audio_profile({})
    final_fields: dict[int, tuple[int, int]] = {}
    for item in ADV7513_AUDIO_PROFILE:
        if item.verify:
            mask, value = final_fields.get(item.address, (0, 0))
            final_fields[item.address] = (
                mask | item.mask,
                (value & ~item.mask) | (expected[item.address] & item.mask),
            )
    return all(
        registers.get(address, 0) & mask == value & mask
        for address, (mask, value) in final_fields.items()
    )


def signed16(value: int) -> int:
    if not -32_768 <= value <= 32_767:
        raise ValueError("PCM sample is outside signed 16-bit range")
    return value


def sign_extend_16_to_32(value: int) -> int:
    """Return the mathematical signed 32-bit extension of a PCM sample."""

    value = signed16(value) & 0xFFFF
    return value | (0xFFFF_0000 if value & 0x8000 else 0)


def stereo_pcm(value: int) -> tuple[int, int]:
    sample = signed16(value)
    return sample, sample


def i2s_frame(value: int, *, muted: bool = False) -> tuple[tuple[int, int], ...]:
    """Return LRCLK/data captured on all 64 rising BCLK edges.

    A sixteen-bit word is left-aligned after the one-bit I2S delay.  The
    remaining fifteen captured positions in each 32-bit slot are zero; this is
    padding, not a second numeric conversion.
    """

    word = 0 if muted else signed16(value) & 0xFFFF
    channel = [0] + [(word >> bit) & 1 for bit in range(15, -1, -1)]
    channel.extend([0] * (SLOT_WIDTH - len(channel)))
    return tuple([(0, bit) for bit in channel] + [(1, bit) for bit in channel])


def bclk_half_edges(audio_clock_cycles: int) -> tuple[int, ...]:
    # Independent rational event deadlines (not the RTL phase accumulator).
    clock_hz, edge_hz = 50_000_000, 2 * BCLK_RATE
    count = audio_clock_cycles * edge_hz // clock_hz
    return tuple((n * clock_hz + edge_hz - 1) // edge_hz - 1
                 for n in range(1, count + 1))


def cta_supports_pcm(extension: bytes) -> bool:
    """Capability policy only; outer Phase 6C code validates EDID/checksums."""
    if len(extension) != 128 or extension[0] != 2:
        return False
    if extension[3] & 0x40:
        return True
    end = extension[2] or 4
    position = 4
    while position < min(end, 127):
        header = extension[position]
        length = header & 31
        block = extension[position+1:min(position+1+length, end, 127)]
        if header >> 5 == 1:
            for i in range(0, len(block)-2, 3):
                fmt, rates, widths = block[i:i+3]
                if (fmt >> 3) & 15 == 1 and fmt & 7 >= 1 and rates & 4 and widths & 1:
                    return True
        position += length + 1
    return False


class AudioFifo:
    """Bounded sample queue with explicit flush and fault accounting."""

    def __init__(self, depth: int = 32) -> None:
        if depth < 4 or depth & (depth - 1):
            raise ValueError("depth must be a power of two of at least four")
        self.depth = depth
        self.samples: deque[int] = deque()
        self.overruns = 0
        self.underruns = 0
        self.high_water = 0

    def write(self, value: int) -> bool:
        signed16(value)
        if len(self.samples) == self.depth:
            self.overruns += 1
            return False
        self.samples.append(value)
        self.high_water = max(self.high_water, len(self.samples))
        return True

    def read(self) -> int:
        if not self.samples:
            self.underruns += 1
            return 0
        return self.samples.popleft()

    def flush(self) -> None:
        self.samples.clear()


@dataclass
class LinkModel:
    """Policy-level mute/recovery model independent of RTL sequencing."""

    connected: bool = False
    clock_locked: bool = False
    configured: bool = False
    primed: bool = False
    user_mute: bool = False
    error: AudioError = AudioError.NONE
    reconnects: int = 0
    _previously_connected: bool = False

    @property
    def enabled(self) -> bool:
        return self.connected and self.clock_locked and self.configured and self.primed

    @property
    def muted(self) -> bool:
        return not self.enabled or self.user_mute

    def set_connected(self, connected: bool) -> None:
        if not connected and self.connected:
            self.error = AudioError.LINK_LOST
            self.configured = False
            self.primed = False
            self._previously_connected = True
        elif connected and not self.connected and self._previously_connected:
            self.reconnects += 1
            self._previously_connected = False
        self.connected = connected

    def set_clock_locked(self, locked: bool) -> None:
        if self.clock_locked and not locked:
            self.error = AudioError.CLOCK_UNLOCKED
            self.configured = False
            self.primed = False
        self.clock_locked = locked

    def clear_fault(self) -> None:
        self.error = AudioError.NONE


def serialize_stream(samples: Iterable[int], mute_at: set[int] | None = None) -> tuple[
    tuple[tuple[int, int], ...], ...
]:
    mute_at = mute_at or set()
    return tuple(i2s_frame(value, muted=index in mute_at) for index, value in enumerate(samples))


def random_pcm(seed: int, count: int) -> tuple[int, ...]:
    """Portable 32-bit LCG vectors shared with randomized RTL verification."""

    if not 0 <= seed <= 0xFFFF_FFFF or count < 0:
        raise ValueError("invalid seed/count")
    state = seed
    result: list[int] = []
    for _ in range(count):
        state = (state * 1_664_525 + 1_013_904_223) & 0xFFFF_FFFF
        word = state & 0xFFFF
        result.append(word - 0x1_0000 if word & 0x8000 else word)
    return tuple(result)


def av_consistency(frames: int, samples: int, *, exact_60hz: bool = True) -> int:
    """Return signed sample error; the 800/frame identity is only for 60 Hz."""

    if frames < 0 or samples < 0:
        raise ValueError("counts cannot be negative")
    if not exact_60hz:
        raise ValueError("800 samples/frame is not valid for a non-60 Hz mode")
    return samples - frames * SAMPLES_PER_720P60_FRAME
