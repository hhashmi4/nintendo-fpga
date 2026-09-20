"""Independent PPU-side VBlank/NMI reference model for Phase 3I.

The model is transaction-oriented: :meth:`clock` observes the old status bit,
then applies one fabric edge containing an optional enabled PPU tick and an
optional accepted CPU register access.  It intentionally expresses behavior in
terms of condition transitions rather than mirroring the RTL process layout.
"""

from dataclasses import dataclass


VBLANK_SCANLINE = 241
VBLANK_SET_DOT = 1
PRE_RENDER_SCANLINE = 261
STATUS_PRE_SUPPRESS_DOT = 0
STATUS_POST_SUPPRESS_DOT = 2


@dataclass(frozen=True)
class PpuNmiInputs:
    reset: bool = False
    ppu_enable: bool = False
    scanline: int = 0
    dot: int = 0
    vblank_start: bool = False
    status_clear: bool = False
    status_read: bool = False
    control_write: bool = False
    control_nmi_enable: bool = False


@dataclass(frozen=True)
class PpuNmiObservation:
    """State visible after an edge plus the pre-edge PPUSTATUS bit."""

    status_read_bit: bool
    status_vblank: bool
    nmi_enable: bool
    nmi_level: bool
    nmi_event: bool
    nmi_suppressed: bool


class PpuNmiModel:
    """Semantic model of the single VBlank latch and PPU NMI condition."""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.status_vblank = False
        self.nmi_enable = False
        self._suppress_next_vblank = False
        self._activation_pending = False
        self.nmi_event = False
        self.nmi_suppressed = False

    @property
    def nmi_level(self) -> bool:
        return self.status_vblank and self.nmi_enable

    def snapshot(self, status_read_bit: bool | None = None) -> PpuNmiObservation:
        return PpuNmiObservation(
            status_read_bit=(
                self.status_vblank
                if status_read_bit is None
                else bool(status_read_bit)
            ),
            status_vblank=self.status_vblank,
            nmi_enable=self.nmi_enable,
            nmi_level=self.nmi_level,
            nmi_event=self.nmi_event,
            nmi_suppressed=self.nmi_suppressed,
        )

    def clock(self, inputs: PpuNmiInputs) -> PpuNmiObservation:
        """Apply one fabric edge using the accepted-access timing contract."""

        returned_status = self.status_vblank
        if inputs.reset:
            self.reset()
            return self.snapshot(returned_status)

        old_level = self.nmi_level
        allow_vblank_set = (
            inputs.vblank_start
            and not inputs.status_read
            and not self._suppress_next_vblank
        )

        next_status = self.status_vblank
        if inputs.status_clear:
            next_status = False
        elif allow_vblank_set:
            next_status = True
        if inputs.status_read:
            next_status = False

        next_enable = (
            inputs.control_nmi_enable
            if inputs.control_write
            else self.nmi_enable
        )
        next_condition = next_status and next_enable
        ordinary_activation = (
            allow_vblank_set and not old_level and next_condition
        )
        immediate_activation = (
            not inputs.vblank_start
            and inputs.control_write
            and not old_level
            and next_condition
        )

        self.nmi_event = False
        self.nmi_suppressed = False

        if inputs.vblank_start:
            self._suppress_next_vblank = False
        elif (
            inputs.status_read
            and inputs.scanline == VBLANK_SCANLINE
            and inputs.dot == STATUS_PRE_SUPPRESS_DOT
        ):
            self._suppress_next_vblank = True

        if inputs.vblank_start and not allow_vblank_set and next_enable:
            self.nmi_suppressed = True

        if inputs.status_clear or inputs.status_read or not next_condition:
            if self._activation_pending and inputs.status_read:
                self.nmi_suppressed = True
            self._activation_pending = False
        elif ordinary_activation:
            self._activation_pending = True
        elif immediate_activation:
            self._activation_pending = False
            self.nmi_event = True
        elif self._activation_pending and inputs.ppu_enable:
            self._activation_pending = False
            self.nmi_event = True

        self.status_vblank = next_status
        self.nmi_enable = next_enable
        return self.snapshot(returned_status)


def timing_events(scanline: int, dot: int, ppu_enable: bool) -> tuple[bool, bool]:
    """Return Phase 3A event levels for one presented PPU coordinate."""

    return (
        ppu_enable and scanline == VBLANK_SCANLINE and dot == VBLANK_SET_DOT,
        ppu_enable and scanline == PRE_RENDER_SCANLINE and dot == 1,
    )
