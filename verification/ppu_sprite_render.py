"""Independent semantic model for the Phase 3G sprite renderer."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable, Sequence


class SpriteFetchType(IntEnum):
    NONE = 0
    DUMMY_FIRST = 1
    DUMMY_SECOND = 2
    PATTERN_LOW = 3
    PATTERN_HIGH = 4


@dataclass(frozen=True)
class SpriteMetadata:
    y: int = 0xFF
    tile: int = 0xFF
    attributes: int = 0xFF
    x: int = 0xFF
    original_index: int = 0
    valid: bool = False


@dataclass(frozen=True)
class SpriteAddress:
    row: int
    low: int
    high: int


@dataclass(frozen=True)
class SpritePixel:
    valid: bool
    x: int
    y: int
    pattern: int
    palette: int
    opaque: bool
    behind_background: bool
    is_zero: bool
    slot: int
    original_index: int

    @property
    def palette_index(self) -> int:
        return ((self.palette << 2) | self.pattern) if self.opaque else 0


@dataclass(frozen=True)
class SpriteFetchObservation:
    request: bool
    address: int
    slot: int
    phase: int
    kind: SpriteFetchType
    complete: bool
    load: bool
    relative_row: int
    selected_row: int
    low_address: int
    high_address: int
    decrement_mask: int
    shift_mask: int
    pixel: SpritePixel


def reverse_byte(value: int) -> int:
    """Reverse bit order without sharing the RTL's loop structure."""

    value &= 0xFF
    value = ((value & 0x55) << 1) | ((value >> 1) & 0x55)
    value = ((value & 0x33) << 2) | ((value >> 2) & 0x33)
    return ((value << 4) | (value >> 4)) & 0xFF


def sprite_pattern_address(
    *,
    tile: int,
    relative_row: int,
    size_16: bool,
    pattern_table: int,
    vertical_flip: bool,
) -> SpriteAddress:
    """Return selected row and low/high CHR addresses for one sprite."""

    height = 16 if size_16 else 8
    source_row = relative_row & (height - 1)
    row = (height - 1 - source_row) if vertical_flip else source_row
    if size_16:
        bank = (tile & 1) << 12
        pair = tile & 0xFE
        selected_tile = pair + (row >> 3)
        low = bank | (selected_tile << 4) | (row & 7)
    else:
        low = ((pattern_table & 1) << 12) | ((tile & 0xFF) << 4) | row
    return SpriteAddress(row=row, low=low, high=low | 8)


def pattern_pixels(low: int, high: int, horizontal_flip: bool = False) -> list[int]:
    """Decode an eight-pixel NES planar row in display order."""

    if horizontal_flip:
        low = reverse_byte(low)
        high = reverse_byte(high)
    return [
        (((high >> bit) & 1) << 1) | ((low >> bit) & 1)
        for bit in range(7, -1, -1)
    ]


class SpriteRendererModel:
    """Fetch registers, X counters, shifters, and first-opaque selection."""

    def __init__(self) -> None:
        self.low = [0] * 8
        self.high = [0] * 8
        self.x_counter = [0] * 8
        self.palette = [0] * 8
        self.behind = [False] * 8
        self.original_index = [0] * 8
        self.valid = [False] * 8

    def reset(self) -> None:
        self.__init__()

    @staticmethod
    def fetch_kind(dot: int) -> SpriteFetchType:
        if not 257 <= dot <= 320:
            return SpriteFetchType.NONE
        phase = (dot - 257) & 7
        if phase < 2:
            return SpriteFetchType.DUMMY_FIRST
        if phase < 4:
            return SpriteFetchType.DUMMY_SECOND
        if phase < 6:
            return SpriteFetchType.PATTERN_LOW
        return SpriteFetchType.PATTERN_HIGH

    def _pixel(
        self,
        *,
        visible_pixel: bool,
        pixel_x: int,
        pixel_y: int,
        sprites_enabled: bool,
        show_sprites_left: bool,
    ) -> SpritePixel:
        enabled = (
            visible_pixel
            and sprites_enabled
            and (show_sprites_left or pixel_x >= 8)
        )
        if enabled:
            for slot in range(8):
                pattern = 0
                if self.valid[slot] and self.x_counter[slot] == 0:
                    pattern = (
                        (((self.high[slot] >> 7) & 1) << 1)
                        | ((self.low[slot] >> 7) & 1)
                    )
                if pattern:
                    original = self.original_index[slot]
                    return SpritePixel(
                        True,
                        pixel_x & 0xFF,
                        pixel_y & 0xFF,
                        pattern,
                        self.palette[slot],
                        True,
                        self.behind[slot],
                        original == 0,
                        slot,
                        original,
                    )
        return SpritePixel(
            visible_pixel,
            (pixel_x & 0xFF) if visible_pixel else 0,
            (pixel_y & 0xFF) if visible_pixel else 0,
            0,
            0,
            False,
            False,
            False,
            0,
            0,
        )

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
        sprites_enabled: bool,
        show_sprites_left: bool,
        size_16: bool,
        pattern_table: int,
        nametable_address: int,
        metadata: SpriteMetadata,
        memory_grant: bool,
    ) -> SpriteFetchObservation:
        in_window = scanline < 240 and 257 <= dot <= 320
        offset = (dot - 257) & 0x3F
        slot = offset >> 3
        phase = offset & 7
        kind = self.fetch_kind(dot) if in_window else SpriteFetchType.NONE
        row = (scanline - metadata.y) & 0xFF
        addresses = sprite_pattern_address(
            tile=metadata.tile,
            relative_row=row,
            size_16=size_16,
            pattern_table=pattern_table,
            vertical_flip=bool(metadata.attributes & 0x80),
        )
        if kind == SpriteFetchType.PATTERN_LOW:
            address = addresses.low
        elif kind == SpriteFetchType.PATTERN_HIGH:
            address = addresses.high
        else:
            address = nametable_address & 0x3FFF
        request = (
            not reset
            and ppu_enable
            and rendering_enabled
            and in_window
        )
        complete = request and memory_grant and bool(phase & 1)
        decrement_mask = 0
        shift_mask = 0
        if ppu_enable and visible_pixel:
            for candidate in range(8):
                if self.valid[candidate]:
                    if self.x_counter[candidate]:
                        decrement_mask |= 1 << candidate
                    else:
                        shift_mask |= 1 << candidate
        return SpriteFetchObservation(
            request=request,
            address=address,
            slot=slot,
            phase=phase,
            kind=kind,
            complete=complete,
            load=request and phase == 7,
            relative_row=row & 0xF,
            selected_row=addresses.row,
            low_address=addresses.low,
            high_address=addresses.high,
            decrement_mask=decrement_mask,
            shift_mask=shift_mask,
            pixel=self._pixel(
                visible_pixel=visible_pixel,
                pixel_x=pixel_x,
                pixel_y=pixel_y,
                sprites_enabled=sprites_enabled,
                show_sprites_left=show_sprites_left,
            ),
        )

    def clock(
        self,
        observation: SpriteFetchObservation,
        *,
        reset: bool,
        ppu_enable: bool,
        visible_pixel: bool,
        metadata: SpriteMetadata,
        memory_data: int,
    ) -> None:
        if reset:
            self.reset()
            return
        if not ppu_enable:
            return

        if visible_pixel:
            for slot in range(8):
                if not self.valid[slot]:
                    continue
                if self.x_counter[slot]:
                    self.x_counter[slot] = (self.x_counter[slot] - 1) & 0xFF
                else:
                    self.low[slot] = (self.low[slot] << 1) & 0xFF
                    self.high[slot] = (self.high[slot] << 1) & 0xFF

        slot = observation.slot
        if observation.request and observation.phase == 0:
            self.low[slot] = 0
            self.high[slot] = 0
            self.valid[slot] = False

        flip = bool(metadata.attributes & 0x40)
        if (
            observation.complete
            and observation.phase == 5
            and metadata.valid
        ):
            data = memory_data & 0xFF
            self.low[slot] = reverse_byte(data) if flip else data
        if (
            observation.complete
            and observation.phase == 7
            and metadata.valid
        ):
            data = memory_data & 0xFF
            self.high[slot] = reverse_byte(data) if flip else data

        if observation.load:
            self.x_counter[slot] = metadata.x & 0xFF
            self.palette[slot] = metadata.attributes & 3
            self.behind[slot] = bool(metadata.attributes & 0x20)
            self.original_index[slot] = metadata.original_index & 0x3F
            self.valid[slot] = metadata.valid

    def load_row(
        self,
        slot: int,
        metadata: SpriteMetadata,
        low: int,
        high: int,
    ) -> None:
        """Test helper equivalent to a completed ordinary fetch group."""

        flip = bool(metadata.attributes & 0x40)
        self.low[slot] = reverse_byte(low) if flip else low & 0xFF
        self.high[slot] = reverse_byte(high) if flip else high & 0xFF
        self.x_counter[slot] = metadata.x & 0xFF
        self.palette[slot] = metadata.attributes & 3
        self.behind[slot] = bool(metadata.attributes & 0x20)
        self.original_index[slot] = metadata.original_index & 0x3F
        self.valid[slot] = metadata.valid

    def render_scanline(
        self,
        *,
        y: int,
        sprites_enabled: bool = True,
        show_sprites_left: bool = True,
        stalls: Iterable[int] = (),
    ) -> list[SpritePixel]:
        stall_set = set(stalls)
        pixels: list[SpritePixel] = []
        fabric_cycle = 0
        for x in range(256):
            while fabric_cycle in stall_set:
                observation = self.observe(
                    reset=False,
                    ppu_enable=False,
                    dot=x + 1,
                    scanline=y,
                    visible_pixel=True,
                    pixel_x=x,
                    pixel_y=y,
                    rendering_enabled=True,
                    sprites_enabled=sprites_enabled,
                    show_sprites_left=show_sprites_left,
                    size_16=False,
                    pattern_table=0,
                    nametable_address=0x2000,
                    metadata=SpriteMetadata(),
                    memory_grant=False,
                )
                self.clock(
                    observation,
                    reset=False,
                    ppu_enable=False,
                    visible_pixel=True,
                    metadata=SpriteMetadata(),
                    memory_data=0,
                )
                fabric_cycle += 1
            observation = self.observe(
                reset=False,
                ppu_enable=True,
                dot=x + 1,
                scanline=y,
                visible_pixel=True,
                pixel_x=x,
                pixel_y=y,
                rendering_enabled=True,
                sprites_enabled=sprites_enabled,
                show_sprites_left=show_sprites_left,
                size_16=False,
                pattern_table=0,
                nametable_address=0x2000,
                metadata=SpriteMetadata(),
                memory_grant=False,
            )
            pixels.append(observation.pixel)
            self.clock(
                observation,
                reset=False,
                ppu_enable=True,
                visible_pixel=True,
                metadata=SpriteMetadata(),
                memory_data=0,
            )
            fabric_cycle += 1
        return pixels


def select_scanline_sprites(
    primary_oam: Sequence[int], scanline_being_evaluated: int, size_16: bool
) -> list[SpriteMetadata]:
    """High-level first-eight selection for deterministic frame checking."""

    height = 16 if size_16 else 8
    selected: list[SpriteMetadata] = []
    for index in range(64):
        base = index * 4
        y, tile, attributes, x = primary_oam[base : base + 4]
        if ((scanline_being_evaluated - y) & 0xFF) < height:
            selected.append(
                SpriteMetadata(y, tile, attributes, x, index, True)
            )
            if len(selected) == 8:
                break
    return selected


def render_scene_pixel(
    *,
    primary_oam: Sequence[int],
    chr_memory: Sequence[int],
    x: int,
    y: int,
    size_16: bool,
    pattern_table: int,
    sprites_enabled: bool,
    show_sprites_left: bool,
) -> SpritePixel:
    """Direct full-scene reference, including the Phase 3F line-0 limit."""

    transparent = SpritePixel(True, x, y, 0, 0, False, False, False, 0, 0)
    if y == 0 or not sprites_enabled or (x < 8 and not show_sprites_left):
        return transparent
    selected = select_scanline_sprites(primary_oam, y - 1, size_16)
    for slot, metadata in enumerate(selected):
        offset = x - metadata.x
        if not 0 <= offset < 8:
            continue
        address = sprite_pattern_address(
            tile=metadata.tile,
            relative_row=((y - 1) - metadata.y) & 0xFF,
            size_16=size_16,
            pattern_table=pattern_table,
            vertical_flip=bool(metadata.attributes & 0x80),
        )
        bit = offset if metadata.attributes & 0x40 else 7 - offset
        pattern = (
            (((chr_memory[address.high] >> bit) & 1) << 1)
            | ((chr_memory[address.low] >> bit) & 1)
        )
        if pattern:
            return SpritePixel(
                True,
                x,
                y,
                pattern,
                metadata.attributes & 3,
                True,
                bool(metadata.attributes & 0x20),
                metadata.original_index == 0,
                slot,
                metadata.original_index,
            )
    return transparent
