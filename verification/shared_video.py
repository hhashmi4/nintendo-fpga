"""Independent Phase 6B shared-video reference models.

These models intentionally express the timing, scaling, and ownership rules in
Python rather than translating RTL statements one-for-one. They are used to
generate expectations for directed and randomized verification.
"""

from __future__ import annotations

from dataclasses import dataclass
from random import Random
from typing import Iterable


NES_WIDTH = 256
NES_HEIGHT = 240
NES_PIXELS = NES_WIDTH * NES_HEIGHT

H_ACTIVE = 1280
H_FRONT = 110
H_SYNC = 40
H_BACK = 220
H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK
V_ACTIVE = 720
V_FRONT = 5
V_SYNC = 5
V_BACK = 20
V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK
PIXELS_PER_OUTPUT_FRAME = H_TOTAL * V_TOTAL

CANVAS_LEFT = 160
CANVAS_WIDTH = 960
CANVAS_RIGHT = CANVAS_LEFT + CANVAS_WIDTH
DEVELOPER_GAME_WIDTH = 768
DEVELOPER_PANEL_LEFT = CANVAS_LEFT + DEVELOPER_GAME_WIDTH


@dataclass(frozen=True)
class TimingSample:
    x: int
    y: int
    active_video: bool
    hsync: bool
    vsync: bool
    line_start: bool
    line_end: bool
    frame_start: bool
    frame_end: bool


@dataclass(frozen=True)
class ScaleSample:
    canvas: bool
    nes: bool
    panel: bool
    nes_x: int = 0
    nes_y: int = 0
    panel_x: int = 512
    panel_y: int = 0

    @property
    def framebuffer_address(self) -> int:
        return self.nes_y * NES_WIDTH + self.nes_x


def timing_sample(pixel_index: int) -> TimingSample:
    """Return the 720p timing state for a wrapping linear pixel index."""

    position = pixel_index % PIXELS_PER_OUTPUT_FRAME
    y, x = divmod(position, H_TOTAL)
    active = x < H_ACTIVE and y < V_ACTIVE
    hsync = H_ACTIVE + H_FRONT <= x < H_ACTIVE + H_FRONT + H_SYNC
    vsync = V_ACTIVE + V_FRONT <= y < V_ACTIVE + V_FRONT + V_SYNC
    return TimingSample(
        x=x,
        y=y,
        active_video=active,
        hsync=hsync,
        vsync=vsync,
        line_start=x == 0,
        line_end=x == H_TOTAL - 1,
        frame_start=x == 0 and y == 0,
        frame_end=x == H_TOTAL - 1 and y == V_TOTAL - 1,
    )


def iter_timing_frame() -> Iterable[TimingSample]:
    return map(timing_sample, range(PIXELS_PER_OUTPUT_FRAME))


def scale_720p(x: int, y: int, developer_layout: bool = False) -> ScaleSample:
    """Map an output coordinate to an NES pixel or Developer Mode panel pixel."""

    active = 0 <= x < H_ACTIVE and 0 <= y < V_ACTIVE
    canvas = active and CANVAS_LEFT <= x < CANVAS_RIGHT
    if not canvas:
        return ScaleSample(canvas=False, nes=False, panel=False)

    relative_x = x - CANVAS_LEFT
    if not developer_layout:
        return ScaleSample(
            canvas=True,
            nes=True,
            panel=False,
            nes_x=(relative_x * NES_WIDTH) // CANVAS_WIDTH,
            nes_y=y // 3,
        )

    if relative_x < DEVELOPER_GAME_WIDTH:
        return ScaleSample(
            canvas=True,
            nes=True,
            panel=False,
            nes_x=relative_x // 3,
            nes_y=y // 3,
        )

    panel_relative_x = relative_x - DEVELOPER_GAME_WIDTH
    return ScaleSample(
        canvas=True,
        nes=False,
        panel=True,
        panel_x=512 + (panel_relative_x * 2) // 3,
        panel_y=(y * 2) // 3,
    )


@dataclass(frozen=True)
class MemoryOption:
    name: str
    bits_per_pixel: int
    buffers: int

    @property
    def bits(self) -> int:
        return NES_PIXELS * self.bits_per_pixel * self.buffers

    @property
    def kibibytes(self) -> float:
        return self.bits / 8 / 1024


def memory_options() -> tuple[MemoryOption, ...]:
    return tuple(
        MemoryOption(name, depth, buffers)
        for name, depth in (
            ("indexed6", 6),
            ("indexed9", 9),
            ("rgb888", 24),
        )
        for buffers in (1, 2, 3)
    )


class FramebufferManagerModel:
    """Transaction model of the three-bank frame ownership protocol.

    A bank can be written, pending publication, or displayed, never more than
    one at once. Only completed frame identifiers cross to the reader model.
    """

    def __init__(self) -> None:
        self.read_bank = 0
        self.write_bank: int | None = None
        self.pending: tuple[int, int] | None = None
        self.queued: tuple[int, int] | None = None
        self.displayed_frame: int | None = None
        self.displayed_sequence: list[int] = []
        self.captured_sequence: list[int] = []

    def _free_bank(self) -> int:
        excluded = {self.read_bank}
        if self.pending is not None:
            excluded.add(self.pending[0])
        if self.queued is not None:
            excluded.add(self.queued[0])
        return next(bank for bank in range(3) if bank not in excluded)

    def begin_frame(self, *, frozen: bool = False) -> bool:
        if frozen or self.write_bank is not None or self.queued is not None:
            return False
        self.write_bank = self._free_bank()
        return True

    def complete_frame(self, frame_id: int) -> None:
        if self.write_bank is None:
            raise RuntimeError("cannot publish a frame that was not started")
        completed = (self.write_bank, frame_id)
        self.write_bank = None
        if self.pending is None:
            self.pending = completed
            self.captured_sequence.append(frame_id)
        elif self.queued is None:
            self.queued = completed
        else:
            raise RuntimeError("all framebuffer banks are owned")

    def service_writer(self) -> bool:
        if self.pending is None and self.queued is not None:
            self.pending = self.queued
            self.queued = None
            self.captured_sequence.append(self.pending[1])
            return True
        return False

    def reader_frame_end(self) -> bool:
        if self.pending is None:
            return False
        self.read_bank, self.displayed_frame = self.pending
        self.pending = None
        self.displayed_sequence.append(self.displayed_frame)
        return True

    @property
    def owned_banks(self) -> tuple[int, ...]:
        banks = [self.read_bank]
        if self.write_bank is not None:
            banks.append(self.write_bank)
        if self.pending is not None:
            banks.append(self.pending[0])
        if self.queued is not None:
            banks.append(self.queued[0])
        return tuple(banks)


def simulate_frame_sequence(
    source_period: int,
    output_period: int,
    duration: int,
    *,
    seed: int = 0,
) -> FramebufferManagerModel:
    """Exercise asynchronous producer/consumer phase with small random jitter."""

    if min(source_period, output_period, duration) <= 0:
        raise ValueError("periods and duration must be positive")
    random = Random(seed)
    model = FramebufferManagerModel()
    next_source = random.randrange(source_period)
    next_output = random.randrange(output_period)
    frame_id = 0
    for tick in range(duration):
        if tick == next_source:
            model.service_writer()
            if model.begin_frame():
                model.complete_frame(frame_id)
                frame_id += 1
            next_source += source_period + random.randrange(-1, 2)
        if tick == next_output:
            model.reader_frame_end()
            next_output += output_period + random.randrange(-1, 2)
        assert len(model.owned_banks) == len(set(model.owned_banks))
    return model
