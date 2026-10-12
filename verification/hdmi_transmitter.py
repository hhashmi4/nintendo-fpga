"""Independent Phase 6C HDMI-transmitter reference models.

The models operate on transactions, EDID structures, and elapsed control
cycles.  They intentionally do not mirror RTL states or clock phases.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable, Mapping

from verification.shared_video import (
    H_ACTIVE,
    H_TOTAL,
    PIXELS_PER_OUTPUT_FRAME,
    V_ACTIVE,
    V_TOTAL,
    timing_sample,
)


ADV7513_MAIN_ADDRESS = 0x39
ADV7513_EDID_ADDRESS = 0x3F


class HdmiError(IntEnum):
    NONE = 0
    HDMI_TX_NOT_DETECTED = 1
    HDMI_TX_I2C_NACK = 2
    HDMI_TX_I2C_TIMEOUT = 3
    HDMI_HPD_TIMEOUT = 4
    HDMI_EDID_INVALID = 5
    HDMI_MODE_UNSUPPORTED = 6
    HDMI_PIXEL_CLOCK_UNLOCKED = 7
    HDMI_CONFIG_VERIFY_FAILED = 8
    HDMI_RECOVERY_FAILED = 9


class StartupState(IntEnum):
    RESET = 0
    WAIT_CLOCK = 1
    WAIT_HPD = 2
    CONFIGURE = 3
    VERIFY_CONFIG = 4
    CHECK_DISPLAY_CAPABILITY = 5
    ENABLE_VIDEO = 6
    RUNNING = 7
    FAULT = 8
    RECOVERY = 9


@dataclass(frozen=True)
class RegisterUpdate:
    address: int
    mask: int
    value: int
    verify: bool = True


# Same documented contract as the RTL table, represented independently as
# semantic masked updates rather than encoded lookup cases.
ADV7513_720P_PROFILE = (
    RegisterUpdate(0x41, 0x40, 0x00),
    RegisterUpdate(0x98, 0xFF, 0x03),
    RegisterUpdate(0x9A, 0xE0, 0xE0),
    RegisterUpdate(0x9C, 0xFF, 0x30),
    RegisterUpdate(0x9D, 0x03, 0x01),
    RegisterUpdate(0xA2, 0xFF, 0xA4),
    RegisterUpdate(0xA3, 0xFF, 0xA4),
    RegisterUpdate(0xE0, 0xFF, 0xD0),
    RegisterUpdate(0xF9, 0xFF, 0x00),
    RegisterUpdate(0x0B, 0x80, 0x00),
    RegisterUpdate(0x0C, 0x3C, 0x00),
    RegisterUpdate(0x15, 0x0F, 0x00),
    RegisterUpdate(0x16, 0xC1, 0x00),
    RegisterUpdate(0x17, 0x62, 0x02),
    RegisterUpdate(0x18, 0x80, 0x00),
    RegisterUpdate(0x3B, 0x7E, 0x40),
    RegisterUpdate(0x3C, 0x3F, 0x04),
    RegisterUpdate(0xAF, 0x82, 0x02),
    RegisterUpdate(0x4A, 0xC0, 0xC0, verify=False),
    RegisterUpdate(0x55, 0x7F, 0x11),
    RegisterUpdate(0x56, 0xFF, 0xA9),
    RegisterUpdate(0x57, 0x0F, 0x00),
    RegisterUpdate(0x44, 0x10, 0x10),
    RegisterUpdate(0x4A, 0xC0, 0x80),
)


def i2c_register_events(
    device: int, register: int, *, read: bool, data: int = 0
) -> tuple[tuple[str, int | None], ...]:
    """Return the protocol-level bus events for a one-byte register access."""

    prefix: list[tuple[str, int | None]] = [
        ("START", None),
        ("WRITE", device << 1),
        ("ACK", None),
        ("WRITE", register),
        ("ACK", None),
    ]
    if read:
        prefix.extend(
            (
                ("REPEATED_START", None),
                ("WRITE", (device << 1) | 1),
                ("ACK", None),
                ("READ", None),
                ("NACK", None),
            )
        )
    else:
        prefix.extend((("WRITE", data), ("ACK", None)))
    prefix.append(("STOP", None))
    return tuple(prefix)


def apply_profile(
    initial: Mapping[int, int],
    profile: Iterable[RegisterUpdate] = ADV7513_720P_PROFILE,
) -> tuple[dict[int, int], tuple[tuple[int, int], ...]]:
    """Apply ordered read/modify/write operations to an abstract register map."""

    registers = {address: value & 0xFF for address, value in initial.items()}
    writes: list[tuple[int, int]] = []
    for update in profile:
        old = registers.get(update.address, 0)
        new = (old & (~update.mask & 0xFF)) | (update.value & update.mask)
        registers[update.address] = new
        writes.append((update.address, new))
    return registers, tuple(writes)


def verify_profile(
    registers: Mapping[int, int],
    profile: Iterable[RegisterUpdate] = ADV7513_720P_PROFILE,
) -> bool:
    return all(
        not item.verify
        or registers.get(item.address, 0) & item.mask == item.value & item.mask
        for item in profile
    )


class HpdDebouncer:
    """Candidate-duration debounce model with symmetric connect/disconnect."""

    def __init__(self, stable_cycles: int) -> None:
        if stable_cycles < 1:
            raise ValueError("stable_cycles must be positive")
        self.stable_cycles = stable_cycles
        self.output = False
        self._candidate_cycles = 0

    def sample(self, raw: bool) -> bool:
        if raw == self.output:
            self._candidate_cycles = 0
        else:
            self._candidate_cycles += 1
            if self._candidate_cycles >= self.stable_cycles:
                self.output = raw
                self._candidate_cycles = 0
        return self.output


def _dtd_is_720p(block: bytes, offset: int) -> bool:
    dtd = block[offset : offset + 18]
    if len(dtd) != 18:
        return False
    pixel_clock = int.from_bytes(dtd[0:2], "little")
    h_active = dtd[2] | ((dtd[4] >> 4) << 8)
    h_blank = dtd[3] | ((dtd[4] & 0x0F) << 8)
    v_active = dtd[5] | ((dtd[7] >> 4) << 8)
    v_blank = dtd[6] | ((dtd[7] & 0x0F) << 8)
    return (
        pixel_clock == 7425
        and h_active == 1280
        and h_active + h_blank == 1650
        and v_active == 720
        and v_active + v_blank == 750
    )


@dataclass(frozen=True)
class EdidResult:
    available: bool
    valid: bool
    supports_720p60: bool
    reason: str


def validate_edid(data: bytes | None) -> EdidResult:
    if data is None:
        return EdidResult(False, False, False, "unavailable")
    if len(data) < 128:
        return EdidResult(True, False, False, "short base block")
    base = data[:128]
    if base[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
        return EdidResult(True, False, False, "invalid header")
    if sum(base) & 0xFF:
        return EdidResult(True, False, False, "invalid base checksum")

    supported = any(_dtd_is_720p(base, offset) for offset in (54, 72, 90, 108))
    extension_count = base[126]
    if extension_count:
        if len(data) < 256:
            return EdidResult(True, False, False, "missing first extension")
        extension = data[128:256]
        if sum(extension) & 0xFF:
            return EdidResult(True, False, False, "invalid extension checksum")
        if extension[0] != 0x02:
            return EdidResult(True, False, supported, "unsupported extension")
        dtd_offset = extension[2] or 127
        cursor = 4
        while cursor < min(dtd_offset, 127):
            header = extension[cursor]
            tag, length = header >> 5, header & 0x1F
            payload = extension[cursor + 1 : cursor + 1 + length]
            if len(payload) != length:
                return EdidResult(True, False, False, "truncated data block")
            if tag == 2 and any(value & 0x7F == 4 for value in payload):
                supported = True
            cursor += 1 + length
        for offset in range(dtd_offset, 127, 18):
            supported |= _dtd_is_720p(extension, offset)
    return EdidResult(True, True, supported, "ok")


@dataclass(frozen=True)
class VideoMeasurements:
    pixel_clock_hz: int
    line_pixels: int
    frame_pixels: int
    active_pixels: int
    hsync_pixels: int
    vsync_lines: int
    frames_per_second: float


def measure_720p_frame(pixel_clock_hz: int = 74_250_000) -> VideoMeasurements:
    samples = tuple(timing_sample(index) for index in range(PIXELS_PER_OUTPUT_FRAME))
    return VideoMeasurements(
        pixel_clock_hz=pixel_clock_hz,
        line_pixels=H_TOTAL,
        frame_pixels=len(samples),
        active_pixels=sum(sample.active_video for sample in samples),
        hsync_pixels=sum(sample.hsync for sample in samples),
        vsync_lines=sum(samples[y * H_TOTAL].vsync for y in range(V_TOTAL)),
        frames_per_second=pixel_clock_hz / len(samples),
    )


def transmitter_samples(
    pixels: Iterable[tuple[int, bool, bool, bool]], *, enabled: bool
) -> tuple[tuple[int, bool, bool, bool], ...]:
    """Model transmitter rising-edge samples half a cycle after FPGA launch."""

    return tuple(
        (rgb if enabled and de else 0, hsync, vsync, enabled and de)
        for rgb, hsync, vsync, de in pixels
    )


class StartupModel:
    """Transaction-level startup/recovery policy model used for fault tests."""

    def __init__(self, max_recoveries: int = 3) -> None:
        self.state = StartupState.RESET
        self.error = HdmiError.NONE
        self.recoveries = 0
        self.recovery_attempts = 0
        self.max_recoveries = max_recoveries
        self.video_enabled = False

    def advance(
        self,
        *,
        clock_locked: bool = True,
        hpd: bool = True,
        config_ok: bool = True,
        verify_ok: bool = True,
        edid: EdidResult | None = None,
    ) -> StartupState:
        if self.state is StartupState.RESET:
            self.state = StartupState.WAIT_CLOCK
        elif self.state is StartupState.WAIT_CLOCK:
            if clock_locked:
                self.state = StartupState.WAIT_HPD
            else:
                self._fault(HdmiError.HDMI_PIXEL_CLOCK_UNLOCKED)
        elif self.state is StartupState.WAIT_HPD:
            if hpd:
                self.state = StartupState.CONFIGURE
        elif self.state is StartupState.CONFIGURE:
            if not hpd:
                self.recovery_attempts += 1
                self.recoveries += 1
                self.state = StartupState.RECOVERY
            elif config_ok:
                self.state = StartupState.VERIFY_CONFIG
            else:
                self._fault(HdmiError.HDMI_TX_I2C_NACK)
        elif self.state is StartupState.VERIFY_CONFIG:
            if verify_ok:
                self.state = StartupState.CHECK_DISPLAY_CAPABILITY
            else:
                self._fault(HdmiError.HDMI_CONFIG_VERIFY_FAILED)
        elif self.state is StartupState.CHECK_DISPLAY_CAPABILITY:
            if edid is None or not edid.valid:
                self._fault(HdmiError.HDMI_EDID_INVALID)
            elif not edid.supports_720p60:
                self._fault(HdmiError.HDMI_MODE_UNSUPPORTED)
            else:
                self.state = StartupState.ENABLE_VIDEO
        elif self.state is StartupState.ENABLE_VIDEO:
            self.video_enabled = True
            self.recovery_attempts = 0
            self.state = StartupState.RUNNING
        elif self.state is StartupState.RUNNING:
            if not hpd:
                self.video_enabled = False
                self.recovery_attempts += 1
                self.recoveries += 1
                self.state = StartupState.RECOVERY
            elif not clock_locked:
                self._fault(HdmiError.HDMI_PIXEL_CLOCK_UNLOCKED)
        elif self.state is StartupState.FAULT:
            if self.recovery_attempts >= self.max_recoveries:
                self.error = HdmiError.HDMI_RECOVERY_FAILED
            else:
                self.recovery_attempts += 1
                self.recoveries += 1
                self.state = StartupState.RECOVERY
        elif self.state is StartupState.RECOVERY:
            self.state = StartupState.WAIT_CLOCK
        return self.state

    def _fault(self, error: HdmiError) -> None:
        self.error = error
        self.video_enabled = False
        self.state = StartupState.FAULT
