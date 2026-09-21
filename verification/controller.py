"""Independent reference model for the standard NES controller protocol."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum


class Button(IntEnum):
    A = 0
    B = 1
    SELECT = 2
    START = 3
    UP = 4
    DOWN = 5
    LEFT = 6
    RIGHT = 7


@dataclass
class ControllerPortModel:
    """Model the shared strobe and independent serial ports.

    A one bit in ``buttons`` means pressed. Read values place the serial
    response on D0 and return deterministic zeroes on D7:D1.
    """

    controller1_buttons: int = 0
    controller2_buttons: int = 0
    strobe: bool = False
    controller1_shift: int = 0
    controller2_shift: int = 0
    controller1_index: int = 0
    controller2_index: int = 0

    def reset(self) -> None:
        self.strobe = False
        self.controller1_shift = 0
        self.controller2_shift = 0
        self.controller1_index = 0
        self.controller2_index = 0

    def set_buttons(self, controller1: int, controller2: int) -> None:
        self.controller1_buttons = controller1 & 0xFF
        self.controller2_buttons = controller2 & 0xFF

    def write_4016(self, value: int) -> None:
        next_strobe = bool(value & 1)
        if self.strobe and not next_strobe:
            self.controller1_shift = self.controller1_buttons
            self.controller2_shift = self.controller2_buttons
            self.controller1_index = 0
            self.controller2_index = 0
        self.strobe = next_strobe

    def read(self, port: int) -> int:
        if port not in (0, 1):
            raise ValueError("controller port must be 0 ($4016) or 1 ($4017)")

        buttons = (
            self.controller2_buttons if port else self.controller1_buttons
        )
        shift = self.controller2_shift if port else self.controller1_shift
        serial = (buttons if self.strobe else shift) & 1

        if not self.strobe:
            shifted = ((shift >> 1) | 0x80) & 0xFF
            if port:
                self.controller2_shift = shifted
                self.controller2_index = min(self.controller2_index + 1, 8)
            else:
                self.controller1_shift = shifted
                self.controller1_index = min(self.controller1_index + 1, 8)
        return serial

    def read_4016(self) -> int:
        return self.read(0)

    def read_4017(self) -> int:
        return self.read(1)


def serial_bits(buttons: int) -> list[int]:
    """Return A, B, Select, Start, Up, Down, Left, Right."""

    return [((buttons & 0xFF) >> bit) & 1 for bit in range(8)]
