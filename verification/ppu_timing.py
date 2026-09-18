"""Independent behavioral reference for Phase 3A NTSC PPU timing."""

from dataclasses import dataclass


DOTS_PER_SCANLINE = 341
SCANLINES_PER_FRAME = 262
VISIBLE_WIDTH = 256
VISIBLE_HEIGHT = 240
NORMAL_FRAME_TICKS = DOTS_PER_SCANLINE * SCANLINES_PER_FRAME
ODD_RENDERED_FRAME_TICKS = NORMAL_FRAME_TICKS - 1
VBLANK_START = (241, 1)
VBLANK_END = (261, 1)


@dataclass(frozen=True)
class PpuTimingSnapshot:
    """Externally observable timing state at one PPU coordinate."""

    dot: int
    scanline: int
    frame_odd: bool
    vblank: bool


class PpuTimingModel:
    """Behavioral frame-position model, deliberately expressed linearly.

    ``cycle_in_frame`` is converted to scanline/dot coordinates for
    observation. This differs from the RTL's pair of nested counters while
    retaining the same externally visible state transition contract.
    """

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.cycle_in_frame = 0
        self.frame_odd = False
        self._vblank = False

    @property
    def scanline(self) -> int:
        return self.cycle_in_frame // DOTS_PER_SCANLINE

    @property
    def dot(self) -> int:
        return self.cycle_in_frame % DOTS_PER_SCANLINE

    @property
    def vblank(self) -> bool:
        return self._vblank

    def snapshot(self) -> PpuTimingSnapshot:
        return PpuTimingSnapshot(
            dot=self.dot,
            scanline=self.scanline,
            frame_odd=self.frame_odd,
            vblank=self.vblank,
        )

    def visible_pixel(self, ppu_enable: bool = True) -> bool:
        return (
            ppu_enable
            and self.scanline < VISIBLE_HEIGHT
            and 1 <= self.dot <= VISIBLE_WIDTH
        )

    @property
    def pixel(self) -> tuple[int, int] | None:
        if self.scanline < VISIBLE_HEIGHT and 1 <= self.dot <= VISIBLE_WIDTH:
            return self.dot - 1, self.scanline
        return None

    def frame_start(self, ppu_enable: bool = True) -> bool:
        return ppu_enable and (self.scanline, self.dot) == (0, 0)

    def frame_end(
        self, rendering_enabled: bool, ppu_enable: bool = True
    ) -> bool:
        return ppu_enable and self._terminal(rendering_enabled)

    def vblank_start(self, ppu_enable: bool = True) -> bool:
        return ppu_enable and (self.scanline, self.dot) == VBLANK_START

    def vblank_end(self, ppu_enable: bool = True) -> bool:
        return ppu_enable and (self.scanline, self.dot) == VBLANK_END

    def _terminal(self, rendering_enabled: bool) -> bool:
        final_dot = (
            339 if rendering_enabled and self.frame_odd else DOTS_PER_SCANLINE - 1
        )
        return self.scanline == SCANLINES_PER_FRAME - 1 and self.dot == final_dot

    def clock(
        self,
        *,
        reset: bool = False,
        ppu_enable: bool = True,
        rendering_enabled: bool = False,
    ) -> None:
        """Apply one fabric-clock edge to the behavioral timing state."""

        if reset:
            self.reset()
            return
        if not ppu_enable:
            return

        if self._terminal(rendering_enabled):
            self.cycle_in_frame = 0
            self.frame_odd = not self.frame_odd
        else:
            self.cycle_in_frame += 1

        coordinate = (self.scanline, self.dot)
        if coordinate == VBLANK_START:
            self._vblank = True
        elif coordinate == VBLANK_END:
            self._vblank = False


def capture_frame(
    model: PpuTimingModel, *, rendering_enabled: bool
) -> list[PpuTimingSnapshot]:
    """Capture one complete enabled-tick frame and leave the model at dot 0."""

    samples: list[PpuTimingSnapshot] = []
    starting_parity = model.frame_odd
    while True:
        samples.append(model.snapshot())
        model.clock(rendering_enabled=rendering_enabled)
        if model.cycle_in_frame == 0 and model.frame_odd != starting_parity:
            return samples
