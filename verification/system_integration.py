"""Phase 6G architectural contracts, independent of RTL state encodings.

Frame admission is expressed as completeness of an ordered pixel transaction;
reset invalidates content, while display time continues. Counter observations
are saturating event totals within an epoch, not free-running wrapping timers.
"""

from dataclasses import dataclass
from fractions import Fraction


@dataclass
class FrameAdmission:
    active: bool = False
    pixels: int = 0
    damaged: bool = False
    captured: int = 0
    sequence_error: bool = False
    range_error: bool = False

    def sample(self, *, start=False, valid=False, x=0, y=0, frozen=False):
        if start and not frozen:
            self.sequence_error |= self.active
            self.active, self.pixels, self.damaged = True, 0, False
        if not valid or not self.active:
            return False
        in_order = (x, y) == (self.pixels % 256, self.pixels // 256)
        in_range = 0 <= x < 256 and 0 <= y < 240
        self.sequence_error |= not in_order
        self.range_error |= not in_range
        self.damaged |= not (in_order and in_range)
        self.pixels += 1
        if (x, y) != (255, 239):
            return False
        self.active = False
        complete = not self.damaged and self.pixels == 256 * 240
        self.captured = (self.captured + int(complete)) & 0xFFFF
        return complete


@dataclass
class FaultCounterObserver:
    previous: int = 0

    def observe(self, count: int) -> bool:
        if not 0 <= count <= 0xFFFFFFFF:
            raise ValueError("counter must be unsigned 32-bit")
        event = count > self.previous
        self.previous = count
        return event


@dataclass
class FrameEnable:
    """Enable is already synchronized; a new link starts at frame origin."""

    running: bool = False

    def sample(self, enabled: bool, frame_start: bool, reset=False) -> bool:
        if reset or not enabled:
            self.running = False
        elif frame_start:
            self.running = True
        return self.running


def samples_per_video_frame(pixel_hz: Fraction | int) -> Fraction:
    if pixel_hz <= 0:
        raise ValueError("pixel frequency must be positive")
    return Fraction(48_000 * 1650 * 750, pixel_hz)


def audio_sample_count(cpu_ticks: int) -> int:
    """Exact rational 48 kHz schedule; excludes the bounded FIR latency."""
    if cpu_ticks < 0:
        raise ValueError("tick count must be nonnegative")
    return cpu_ticks * 352 // 13_125
