"""Semantic NES background-fetch and pixel-pipeline model for Phase 3E."""

from dataclasses import dataclass
from enum import IntEnum


class FetchType(IntEnum):
    NONE = 0
    NAMETABLE = 1
    ATTRIBUTE = 2
    PATTERN_LOW = 3
    PATTERN_HIGH = 4
    NAMETABLE_DUMMY = 5


@dataclass(frozen=True)
class BackgroundObservation:
    memory_request: bool
    memory_address: int
    fetch_phase: int
    fetch_type: FetchType
    fetch_complete: bool
    tile_load: bool
    shifter_shift: bool
    pixel_valid: bool
    x: int
    y: int
    pattern: int
    palette: int
    opaque: bool
    index: int


def attribute_palette(attribute: int, coarse_x: int, coarse_y: int) -> int:
    """Select the two palette bits for one 2x2-tile attribute quadrant."""

    quadrant = (((coarse_y >> 1) & 1) << 1) | ((coarse_x >> 1) & 1)
    return (attribute >> (quadrant * 2)) & 3


def pattern_address(table: int, tile_id: int, fine_y: int, plane: int) -> int:
    """Return one background pattern byte address in cartridge CHR space."""

    return (
        ((table & 1) << 12)
        | ((tile_id & 0xFF) << 4)
        | ((plane & 1) << 3)
        | (fine_y & 7)
    )


def nametable_address(v: int) -> int:
    return 0x2000 | (v & 0x0FFF)


def attribute_address(v: int) -> int:
    return 0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 7)


def rendering_scanline(scanline: int) -> bool:
    return 0 <= scanline < 240 or scanline == 261


def main_fetch_dot(dot: int) -> bool:
    return 1 <= dot <= 256 or 321 <= dot <= 336


def trailing_fetch_dot(dot: int) -> bool:
    return 337 <= dot <= 340


def fetch_type_for_dot(dot: int) -> FetchType:
    if trailing_fetch_dot(dot):
        return FetchType.NAMETABLE_DUMMY
    if not main_fetch_dot(dot):
        return FetchType.NONE
    phase = dot & 7
    if phase in (1, 2):
        return FetchType.NAMETABLE
    if phase in (3, 4):
        return FetchType.ATTRIBUTE
    if phase in (5, 6):
        return FetchType.PATTERN_LOW
    return FetchType.PATTERN_HIGH


def completion_dot(dot: int) -> bool:
    if trailing_fetch_dot(dot):
        return not bool(dot & 1)
    return main_fetch_dot(dot) and (dot & 7) in (0, 2, 4, 6)


def pattern_pixel(low: int, high: int, offset: int) -> int:
    """Decode one MSB-first pixel from two NES planar pattern bytes."""

    bit = 7 - (offset & 7)
    return (((high >> bit) & 1) << 1) | ((low >> bit) & 1)


def shifter_pixel(low: int, high: int, fine_x: int) -> int:
    bit = 15 - (fine_x & 7)
    return (((high >> bit) & 1) << 1) | ((low >> bit) & 1)


class BackgroundModel:
    """Fetch latches and rolling 16-pixel background shift state."""

    def __init__(self) -> None:
        self.next_tile_id = 0
        self.next_tile_attribute = 0
        self.next_tile_pattern_low = 0
        self.next_tile_pattern_high = 0
        self.pattern_low_shift = 0
        self.pattern_high_shift = 0
        self.attribute_low_shift = 0
        self.attribute_high_shift = 0

    def reset(self) -> None:
        self.__init__()

    def _memory_address(
        self,
        fetch_type: FetchType,
        *,
        v: int,
        pattern_table: int,
    ) -> int:
        if fetch_type in (FetchType.NAMETABLE, FetchType.NAMETABLE_DUMMY):
            return nametable_address(v)
        if fetch_type == FetchType.ATTRIBUTE:
            return attribute_address(v)
        if fetch_type == FetchType.PATTERN_LOW:
            return pattern_address(pattern_table, self.next_tile_id, v >> 12, 0)
        if fetch_type == FetchType.PATTERN_HIGH:
            return pattern_address(pattern_table, self.next_tile_id, v >> 12, 1)
        return 0

    def observe(
        self,
        *,
        reset: bool,
        ppu_enable: bool,
        dot: int,
        scanline: int,
        visible_pixel: bool,
        pixel_x: int,
        pixel_y: int,
        rendering_enabled: bool,
        background_enabled: bool,
        show_background_left: bool,
        pattern_table: int,
        fine_x: int,
        v: int,
        memory_grant: bool,
    ) -> BackgroundObservation:
        kind = fetch_type_for_dot(dot)
        request = (
            not reset
            and ppu_enable
            and rendering_enabled
            and rendering_scanline(scanline)
            and kind != FetchType.NONE
        )
        complete = request and memory_grant and completion_dot(dot)
        main = main_fetch_dot(dot)
        load = (
            not reset
            and ppu_enable
            and rendering_enabled
            and rendering_scanline(scanline)
            and main
            and (dot & 7) == 0
        )
        shift = (
            not reset
            and ppu_enable
            and rendering_enabled
            and rendering_scanline(scanline)
            and main
        )

        raw_pattern = shifter_pixel(
            self.pattern_low_shift, self.pattern_high_shift, fine_x
        )
        raw_palette = shifter_pixel(
            self.attribute_low_shift, self.attribute_high_shift, fine_x
        )
        enabled = (
            visible_pixel
            and background_enabled
            and (show_background_left or pixel_x >= 8)
        )
        opaque = enabled and raw_pattern != 0
        pattern = raw_pattern if enabled else 0
        palette = raw_palette if opaque else 0
        return BackgroundObservation(
            memory_request=request,
            memory_address=self._memory_address(
                kind, v=v, pattern_table=pattern_table
            ),
            fetch_phase=dot & 7,
            fetch_type=kind,
            fetch_complete=complete,
            tile_load=load,
            shifter_shift=shift,
            pixel_valid=visible_pixel,
            x=pixel_x if visible_pixel else 0,
            y=pixel_y if visible_pixel else 0,
            pattern=pattern,
            palette=palette,
            opaque=opaque,
            index=((raw_palette << 2) | raw_pattern) if opaque else 0,
        )

    def clock(
        self,
        observation: BackgroundObservation,
        *,
        reset: bool,
        ppu_enable: bool,
        v: int,
        memory_data: int,
    ) -> None:
        if reset:
            self.reset()
            return
        if not ppu_enable:
            return

        old_pattern_low = self.pattern_low_shift
        old_pattern_high = self.pattern_high_shift
        old_attribute_low = self.attribute_low_shift
        old_attribute_high = self.attribute_high_shift

        if observation.shifter_shift:
            self.pattern_low_shift = (old_pattern_low << 1) & 0xFFFF
            self.pattern_high_shift = (old_pattern_high << 1) & 0xFFFF
            self.attribute_low_shift = (old_attribute_low << 1) & 0xFFFF
            self.attribute_high_shift = (old_attribute_high << 1) & 0xFFFF

        if observation.fetch_complete and observation.fetch_type != FetchType.NAMETABLE_DUMMY:
            data = memory_data & 0xFF
            if observation.fetch_type == FetchType.NAMETABLE:
                self.next_tile_id = data
            elif observation.fetch_type == FetchType.ATTRIBUTE:
                self.next_tile_attribute = attribute_palette(
                    data, v & 0x1F, (v >> 5) & 0x1F
                )
            elif observation.fetch_type == FetchType.PATTERN_LOW:
                self.next_tile_pattern_low = data
            elif observation.fetch_type == FetchType.PATTERN_HIGH:
                self.next_tile_pattern_high = data

        if observation.tile_load:
            high_byte = (
                memory_data & 0xFF
                if observation.fetch_complete
                and observation.fetch_type == FetchType.PATTERN_HIGH
                else self.next_tile_pattern_high
            )
            self.pattern_low_shift = (
                ((old_pattern_low >> 7) & 0xFF) << 8
            ) | self.next_tile_pattern_low
            self.pattern_high_shift = (
                ((old_pattern_high >> 7) & 0xFF) << 8
            ) | high_byte
            attr_low = 0xFF if self.next_tile_attribute & 1 else 0x00
            attr_high = 0xFF if self.next_tile_attribute & 2 else 0x00
            self.attribute_low_shift = (
                ((old_attribute_low >> 7) & 0xFF) << 8
            ) | attr_low
            self.attribute_high_shift = (
                ((old_attribute_high >> 7) & 0xFF) << 8
            ) | attr_high
