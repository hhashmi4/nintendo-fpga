#!/usr/bin/env python3
"""Verify a real playable-ROM 512x480 game plus 128x480 panel frame."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.debug_renderer import DemoSnapshot, render_panel
from verification.video import palette_rgb


def load_snapshot(path: Path) -> DemoSnapshot:
    values: dict[str, int] = {}
    with path.open(encoding="ascii") as source:
        for line in source:
            key, value = line.split()
            values[key] = int(value, 16)
    return DemoSnapshot(
        pc=values["pc"], a=values["a"], x=values["x"], y=values["y"],
        sp=values["sp"], status=values["status"], opcode=values["opcode"],
        bus_owner=values["bus_owner"], stalled=bool(values["stalled"]),
        scanline=values["scanline"], dot=values["dot"],
        frame_odd=bool(values["frame_odd"]), ctrl=values["ctrl"],
        mask=values["mask"], ppu_status=values["ppu_status"],
        nmi_level=bool(values["nmi_level"]), vblank=bool(values["vblank"]),
        sprite_zero_hit=bool(values["sprite_zero_hit"]),
        mapper=values["mapper"], nrom_256=bool(values["nrom_256"]),
        prg_address=values["prg_address"], chr_address=values["chr_address"],
        mirroring=values["mirroring"], pad1=values["pad1"],
        dma_active=bool(values["dma_active"]), dma_page=values["dma_page"],
        dma_index=values["dma_index"], snapshot_id=values["snapshot_id"],
        source_frame=values["source_frame"], nmi_count=values["nmi_count"],
        dma_count=values["dma_count"],
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()

    snapshot = load_snapshot(args.metadata)
    panel = render_panel(snapshot)
    panel_stride = 128 * 3
    observed_frame = bytearray()
    mismatches = 0
    count = 0
    game_pixels = 0
    panel_pixels = 0

    with args.trace.open(encoding="ascii") as source:
        for line_number, line in enumerate(source, start=1):
            x_text, y_text, pixel_text, rgb_text = line.split()
            x, y = int(x_text), int(y_text)
            expected_x = count % 640
            expected_y = count // 640
            if x != expected_x or y != expected_y:
                raise SystemExit(
                    f"raster mismatch at line {line_number}: "
                    f"observed=({x},{y}) expected=({expected_x},{expected_y})"
                )
            pixel = int(pixel_text, 16)
            observed = tuple(bytes.fromhex(rgb_text))
            if x < 512:
                expected = palette_rgb(pixel & 0x3F, (pixel >> 6) & 0x07)
                game_pixels += 1
            else:
                offset = y * panel_stride + (x - 512) * 3
                expected = tuple(panel[offset:offset + 3])
                panel_pixels += 1
            if observed != expected:
                mismatches += 1
                if mismatches <= 10:
                    print(
                        f"line {line_number}: ({x},{y}) pixel={pixel:03x} "
                        f"observed={observed} expected={expected}",
                        file=sys.stderr,
                    )
            observed_frame.extend(observed)
            count += 1

    if count != 640 * 480 or mismatches:
        raise SystemExit(
            f"playable combined frame failed: pixels={count} mismatches={mismatches}"
        )

    args.artifact.parent.mkdir(parents=True, exist_ok=True)
    header = b"P6\n640 480\n255\n"
    artifact = header + observed_frame
    args.artifact.write_bytes(artifact)
    pixel_hash = hashlib.sha256(observed_frame).hexdigest()
    artifact_hash = hashlib.sha256(artifact).hexdigest()
    print(
        "PASS: Phase 4E-C playable combined-frame comparison "
        f"pixels={count} game={game_pixels} panel={panel_pixels} "
        f"mismatches=0 pixel_sha256={pixel_hash}"
    )
    print(
        f"playable combined frame: {args.artifact} "
        f"bytes={args.artifact.stat().st_size} sha256={artifact_hash}"
    )


if __name__ == "__main__":
    main()
