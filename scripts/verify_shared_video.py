#!/usr/bin/env python3
"""Compare compact Phase 6B RTL results with the independent Python model."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from verification.shared_video import (
    CANVAS_LEFT,
    CANVAS_RIGHT,
    H_ACTIVE,
    H_SYNC,
    H_TOTAL,
    PIXELS_PER_OUTPUT_FRAME,
    V_ACTIVE,
    V_SYNC,
    V_TOTAL,
    scale_720p,
)


def main(path: Path) -> None:
    rows = {parts[0]: tuple(map(int, parts[1:])) for parts in (
        line.split() for line in path.read_text(encoding="ascii").splitlines()
    )}

    expected_timing = (
        PIXELS_PER_OUTPUT_FRAME,
        H_ACTIVE * V_ACTIVE,
        H_SYNC * V_TOTAL,
        V_SYNC * H_TOTAL,
        V_TOTAL,
        V_TOTAL,
        1,
        1,
    )
    assert rows["TIMING"] == expected_timing

    normal_pixels = 0
    border_pixels = 0
    normal_checksum = 0
    developer_nes_pixels = 0
    developer_panel_pixels = 0
    panel_checksum = 0
    for y in range(V_ACTIVE):
        for x in range(H_ACTIVE):
            normal = scale_720p(x, y)
            if normal.nes:
                normal_pixels += 1
                normal_checksum += normal.framebuffer_address
            else:
                border_pixels += 1
            developer = scale_720p(x, y, developer_layout=True)
            if developer.nes:
                developer_nes_pixels += 1
            elif developer.panel:
                developer_panel_pixels += 1
                panel_checksum += developer.panel_y * 640 + developer.panel_x

    assert rows["SCALER"] == (
        normal_pixels,
        border_pixels,
        normal_checksum,
        developer_nes_pixels,
        developer_panel_pixels,
        panel_checksum,
    )
    assert rows["PIPELINE"] == (
        2,
        2,
        2 * (CANVAS_RIGHT - CANVAS_LEFT) * V_ACTIVE + 768 * V_ACTIVE,
        3 * (H_ACTIVE - (CANVAS_RIGHT - CANVAS_LEFT)) * V_ACTIVE,
        192 * V_ACTIVE,
    )
    print(
        "Phase 6B RTL/model comparison passed: "
        f"{PIXELS_PER_OUTPUT_FRAME:,} timing pixels, "
        f"{normal_pixels:,} scaled game pixels, 2 atomic frame swaps"
    )


if __name__ == "__main__":
    main(Path(sys.argv[1]))
