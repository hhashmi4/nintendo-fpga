#!/usr/bin/env python3
"""Compare compact Phase 6C RTL artifacts with independent Python models."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from verification.hdmi_transmitter import (  # noqa: E402
    ADV7513_720P_PROFILE,
    HdmiError,
    measure_720p_frame,
)


def rows(path: Path) -> dict[str, int]:
    return {
        key: int(value)
        for key, value in (
            line.split("=", 1)
            for line in path.read_text(encoding="ascii").splitlines()
        )
    }


def main(controller_path: Path, rgb_path: Path) -> None:
    controller = rows(controller_path)
    assert controller == {
        "profile_writes": len(ADV7513_720P_PROFILE),
        "edid_bytes": 256,
        "frames_counted": 3,
        "bounded_nacks": 3,
        "final_error": int(HdmiError.HDMI_TX_NOT_DETECTED),
    }

    measured = measure_720p_frame()
    rgb = rows(rgb_path)
    assert rgb == {
        "frames": 10,
        "frame_pixels": measured.frame_pixels,
        "active_pixels": measured.active_pixels,
        "hsync_pixels": measured.hsync_pixels,
        "vsync_pixels": measured.vsync_lines * measured.line_pixels,
        "pillar_pixels": 2 * 160 * 720,
    }
    print(
        "Phase 6C RTL/model comparison passed: "
        f"{rgb['frames']} exact frames, {controller['profile_writes']} "
        "profile writes, 256 EDID bytes, bounded fault recovery"
    )


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
