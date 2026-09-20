"""Semantic primary/secondary OAM and sprite-evaluation model for Phase 3F."""

from dataclasses import dataclass
from enum import IntEnum


class EvaluationPhase(IntEnum):
    IDLE = 0
    CLEAR = 1
    EVALUATE_Y = 2
    COPY_SPRITE = 3
    OVERFLOW_SCAN = 4
    OVERFLOW_TAIL = 5
    DONE = 6


@dataclass(frozen=True)
class OamObservation:
    cpu_read_data: int
    cpu_write_commit: bool
    cpu_collision: bool
    primary_read_address: int
    primary_read_data: int
    secondary_clear_write: bool
    secondary_evaluation_write: bool
    secondary_write_address: int
    secondary_write_data: int
    evaluated_relative_row: int
    evaluated_in_range: bool


def sprite_height(sprite_size_16: bool) -> int:
    return 16 if sprite_size_16 else 8


def relative_sprite_row(scanline: int, sprite_y: int) -> int:
    """Apply the PPU's eight-bit scanline-minus-OAM-Y range arithmetic."""

    return (scanline - sprite_y) & 0xFF


def sprite_in_range(scanline: int, sprite_y: int, sprite_size_16: bool) -> bool:
    return relative_sprite_row(scanline, sprite_y) < sprite_height(sprite_size_16)


def oam_address(sprite_index: int, byte_index: int) -> int:
    return ((sprite_index & 0x3F) << 2) | (byte_index & 3)


class SpriteEvaluationModel:
    """Two-dot OAM evaluator with the documented diagonal overflow scan."""

    def __init__(self) -> None:
        self.primary_oam = [0] * 256
        self.secondary_oam = [0] * 32
        self.secondary_indices = [0] * 8
        self.selected_count = 0
        self.sprite_zero_selected = False
        self.overflow_set = False
        self.phase = EvaluationPhase.IDLE
        self.n = 0
        self.m = 0
        self.read_latch = 0
        self.secondary_destination = 0
        self.overflow_tail_remaining = 0
        self.done = False

    def reset_state(self) -> None:
        """Reset registers without assigning architectural RAM contents."""

        self.selected_count = 0
        self.sprite_zero_selected = False
        self.overflow_set = False
        self.phase = EvaluationPhase.IDLE
        self.n = 0
        self.m = 0
        self.read_latch = 0
        self.secondary_destination = 0
        self.overflow_tail_remaining = 0
        self.done = False

    def observe(
        self,
        *,
        reset: bool,
        ppu_enable: bool,
        dot: int,
        scanline: int,
        rendering_enabled: bool,
        sprite_size_16: bool,
        cpu_oam_addr: int = 0,
        cpu_write_data: int = 0,
        cpu_write_enable: bool = False,
        cpu_access: bool = False,
    ) -> OamObservation:
        visible = 0 <= scanline < 240
        evaluation_window = (
            rendering_enabled and visible and 65 <= dot <= 256
        )
        internal_owner = rendering_enabled and (visible or scanline == 261)
        primary_address = oam_address(self.n, self.m) if evaluation_window else (
            cpu_oam_addr & 0xFF
        )
        primary_data = self.primary_oam[primary_address]
        if rendering_enabled and visible and 1 <= dot <= 64:
            cpu_read_data = 0xFF
        else:
            cpu_read_data = primary_data

        row = relative_sprite_row(scanline, self.read_latch)
        in_range = row < sprite_height(sprite_size_16)
        clear_write = (
            not reset
            and ppu_enable
            and rendering_enabled
            and visible
            and 1 <= dot <= 64
            and dot % 2 == 0
        )
        evaluation_write = (
            not reset
            and ppu_enable
            and evaluation_window
            and dot % 2 == 0
            and self.phase in {
                EvaluationPhase.EVALUATE_Y,
                EvaluationPhase.COPY_SPRITE,
            }
            and (
                self.phase == EvaluationPhase.COPY_SPRITE
                or in_range
            )
            and self.selected_count < 8
        )
        return OamObservation(
            cpu_read_data=cpu_read_data,
            cpu_write_commit=cpu_write_enable and not internal_owner,
            cpu_collision=cpu_access and internal_owner,
            primary_read_address=primary_address,
            primary_read_data=primary_data,
            secondary_clear_write=clear_write,
            secondary_evaluation_write=evaluation_write,
            secondary_write_address=(dot // 2 - 1) if clear_write else (
                self.secondary_destination
            ),
            secondary_write_data=0xFF if clear_write else self.read_latch,
            evaluated_relative_row=row,
            evaluated_in_range=in_range,
        )

    def clock(
        self,
        observation: OamObservation,
        *,
        reset: bool,
        ppu_enable: bool,
        dot: int,
        scanline: int,
        rendering_enabled: bool,
        sprite_size_16: bool,
        cpu_oam_addr: int = 0,
        cpu_write_data: int = 0,
    ) -> None:
        if observation.cpu_write_commit:
            self.primary_oam[cpu_oam_addr & 0xFF] = cpu_write_data & 0xFF

        if reset:
            self.reset_state()
            return

        self.overflow_set = False
        visible = 0 <= scanline < 240
        evaluation_window = (
            rendering_enabled and visible and 65 <= dot <= 256
        )

        if ppu_enable and rendering_enabled and visible:
            if dot == 1:
                self.selected_count = 0
                self.sprite_zero_selected = False
                self.phase = EvaluationPhase.CLEAR
                self.n = 0
                self.m = 0
                self.secondary_destination = 0
                self.overflow_tail_remaining = 0
                self.done = False

            if observation.secondary_clear_write:
                self.secondary_oam[observation.secondary_write_address] = 0xFF

            if dot == 64:
                self.phase = EvaluationPhase.EVALUATE_Y

            if evaluation_window and dot % 2 == 1:
                self.read_latch = observation.primary_read_data

            if observation.secondary_evaluation_write:
                self.secondary_oam[observation.secondary_write_address] = (
                    observation.secondary_write_data
                )
                self.secondary_destination = (
                    self.secondary_destination + 1
                ) & 0x1F

            if evaluation_window and dot % 2 == 0 and not self.done:
                self._process_evaluation(
                    observation.evaluated_in_range, sprite_size_16
                )
            elif (
                evaluation_window
                and dot % 2 == 0
                and self.phase == EvaluationPhase.DONE
            ):
                self.m = 0
                self.n = (self.n + 1) & 0x3F

        if (
            ppu_enable
            and dot == 257
            and visible
            and rendering_enabled
        ):
            self.done = True
            self.phase = EvaluationPhase.DONE

    def _process_evaluation(
        self, evaluated_in_range: bool, sprite_size_16: bool
    ) -> None:
        del sprite_size_16  # The semantic comparison was made in observe().
        if self.phase == EvaluationPhase.EVALUATE_Y:
            if evaluated_in_range:
                self.secondary_indices[self.selected_count] = self.n
                if self.n == 0:
                    self.sprite_zero_selected = True
                self.m = 1
                self.phase = EvaluationPhase.COPY_SPRITE
            elif self.n == 63:
                self.done = True
                self.phase = EvaluationPhase.DONE
                self.m = 0
            else:
                self.n += 1
        elif self.phase == EvaluationPhase.COPY_SPRITE:
            if self.m == 3:
                self.selected_count += 1
                self.m = 0
                if self.n == 63:
                    self.done = True
                    self.phase = EvaluationPhase.DONE
                else:
                    self.n += 1
                    self.phase = (
                        EvaluationPhase.OVERFLOW_SCAN
                        if self.selected_count == 8
                        else EvaluationPhase.EVALUATE_Y
                    )
            else:
                self.m += 1
        elif self.phase == EvaluationPhase.OVERFLOW_SCAN:
            if evaluated_in_range:
                self.overflow_set = True
                self.overflow_tail_remaining = 3
                self.phase = EvaluationPhase.OVERFLOW_TAIL
                if self._increment_linear():
                    self.overflow_tail_remaining = 0
                    self.phase = EvaluationPhase.DONE
                    self.done = True
            elif self.n == 63:
                self.done = True
                self.phase = EvaluationPhase.DONE
                self.m = 0
            else:
                # The bug: both fields increment independently without carry.
                self.n += 1
                self.m = (self.m + 1) & 3
        elif self.phase == EvaluationPhase.OVERFLOW_TAIL:
            wrapped = self._increment_linear()
            if self.overflow_tail_remaining == 1 or wrapped:
                self.overflow_tail_remaining = 0
                self.phase = EvaluationPhase.DONE
                self.done = True
            else:
                self.overflow_tail_remaining -= 1
        else:
            self.done = True
            self.phase = EvaluationPhase.DONE

    def _increment_linear(self) -> bool:
        """Advance within OAM and report a 63-to-0 sprite-index wrap."""

        if self.m == 3:
            self.m = 0
            wrapped = self.n == 63
            self.n = (self.n + 1) & 0x3F
            return wrapped
        else:
            self.m += 1
            return False

    def step(self, **signals: int | bool) -> OamObservation:
        observation = self.observe(**signals)
        self.clock(observation, **{
            key: signals[key]
            for key in (
                "reset",
                "ppu_enable",
                "dot",
                "scanline",
                "rendering_enabled",
                "sprite_size_16",
                "cpu_oam_addr",
                "cpu_write_data",
            )
            if key in signals
        })
        return observation

    def run_visible_scanline(
        self,
        scanline: int,
        *,
        sprite_size_16: bool = False,
        stalls: set[int] | None = None,
    ) -> list[OamObservation]:
        observations = []
        stalls = stalls or set()
        for dot in range(1, 258):
            for enabled in ((False, True) if dot in stalls else (True,)):
                signals = dict(
                    reset=False,
                    ppu_enable=enabled,
                    dot=dot,
                    scanline=scanline,
                    rendering_enabled=True,
                    sprite_size_16=sprite_size_16,
                    cpu_oam_addr=0,
                    cpu_write_data=0,
                    cpu_write_enable=False,
                    cpu_access=False,
                )
                observation = self.observe(**signals)
                self.clock(observation, **{
                    key: signals[key]
                    for key in (
                        "reset",
                        "ppu_enable",
                        "dot",
                        "scanline",
                        "rendering_enabled",
                        "sprite_size_16",
                        "cpu_oam_addr",
                        "cpu_write_data",
                    )
                })
                observations.append(observation)
        return observations

    def selected_sprites(self) -> list[tuple[int, tuple[int, int, int, int]]]:
        result = []
        for slot in range(self.selected_count):
            base = slot * 4
            result.append(
                (
                    self.secondary_indices[slot],
                    tuple(self.secondary_oam[base : base + 4]),
                )
            )
        return result
