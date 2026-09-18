from collections import Counter
import random
import re
from pathlib import Path

from verification.ppu_timing import (
    DOTS_PER_SCANLINE,
    NORMAL_FRAME_TICKS,
    ODD_RENDERED_FRAME_TICKS,
    SCANLINES_PER_FRAME,
    VBLANK_END,
    VBLANK_START,
    VISIBLE_HEIGHT,
    VISIBLE_WIDTH,
    PpuTimingModel,
    capture_frame,
)


ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl" / "ppu" / "ppu_timing.sv"
STALL_SEED = 0x003A5EED


def test_rtl_contains_ntsc_timing_boundaries() -> None:
    text = RTL.read_text(encoding="utf-8")
    values = {
        name: int(value)
        for name, value in re.findall(
            r"localparam\s+logic\s+\[8:0\]\s+(\w+)\s*=\s*9'd(\d+)", text
        )
    }
    assert values == {
        "LAST_DOT": 340,
        "ODD_FRAME_LAST_DOT": 339,
        "LAST_SCANLINE": 261,
    }


def test_normal_frame_geometry_coordinates_and_regions() -> None:
    model = PpuTimingModel()
    frame = capture_frame(model, rendering_enabled=False)

    assert len(frame) == NORMAL_FRAME_TICKS == 89_342
    assert DOTS_PER_SCANLINE == 341
    assert SCANLINES_PER_FRAME == 262
    assert Counter(sample.scanline for sample in frame) == {
        scanline: DOTS_PER_SCANLINE for scanline in range(SCANLINES_PER_FRAME)
    }
    assert min(sample.dot for sample in frame) == 0
    assert max(sample.dot for sample in frame) == 340
    assert min(sample.scanline for sample in frame) == 0
    assert max(sample.scanline for sample in frame) == 261

    visible = [
        (sample.dot - 1, sample.scanline)
        for sample in frame
        if sample.scanline < VISIBLE_HEIGHT and 1 <= sample.dot <= VISIBLE_WIDTH
    ]
    assert len(visible) == VISIBLE_WIDTH * VISIBLE_HEIGHT == 61_440
    assert {x for x, _ in visible} == set(range(256))
    assert {y for _, y in visible} == set(range(240))


def test_required_region_and_dot_boundaries() -> None:
    model = PpuTimingModel()
    frame = capture_frame(model, rendering_enabled=False)
    transitions = {
        (
            (current.scanline, current.dot),
            (following.scanline, following.dot),
        )
        for current, following in zip(frame, frame[1:] + frame[:1])
    }

    for pair in (
        ((239, 340), (240, 0)),
        ((240, 340), (241, 0)),
        ((260, 340), (261, 0)),
        ((261, 340), (0, 0)),
        ((0, 339), (0, 340)),
        ((0, 340), (1, 0)),
        ((0, 0), (0, 1)),
        ((0, 1), (0, 2)),
        ((0, 256), (0, 257)),
        ((0, 257), (0, 258)),
    ):
        assert pair in transitions


def test_vblank_level_and_events_are_exact() -> None:
    model = PpuTimingModel()
    starts: list[tuple[int, int]] = []
    ends: list[tuple[int, int]] = []
    levels: dict[tuple[int, int], bool] = {}

    for _ in range(NORMAL_FRAME_TICKS):
        coordinate = (model.scanline, model.dot)
        levels[coordinate] = model.vblank
        if model.vblank_start():
            starts.append(coordinate)
        if model.vblank_end():
            ends.append(coordinate)
        model.clock(rendering_enabled=False)

    assert starts == [VBLANK_START] == [(241, 1)]
    assert ends == [VBLANK_END] == [(261, 1)]
    assert not levels[(241, 0)]
    assert levels[(241, 1)]
    assert levels[(261, 0)]
    assert not levels[(261, 1)]


def test_frame_parity_lengths_and_odd_frame_skip() -> None:
    disabled = PpuTimingModel()
    disabled_lengths = [
        len(capture_frame(disabled, rendering_enabled=False)) for _ in range(4)
    ]
    assert disabled_lengths == [NORMAL_FRAME_TICKS] * 4

    rendered = PpuTimingModel()
    frames = [capture_frame(rendered, rendering_enabled=True) for _ in range(4)]
    assert [len(frame) for frame in frames] == [
        NORMAL_FRAME_TICKS,
        ODD_RENDERED_FRAME_TICKS,
        NORMAL_FRAME_TICKS,
        ODD_RENDERED_FRAME_TICKS,
    ]
    assert [frame[0].frame_odd for frame in frames] == [False, True, False, True]
    assert (frames[0][-1].scanline, frames[0][-1].dot) == (261, 340)
    assert (frames[1][-1].scanline, frames[1][-1].dot) == (261, 339)
    assert not any(
        sample.scanline == 261 and sample.dot == 340 for sample in frames[1]
    )


def test_deterministic_random_stalls_preserve_enabled_sequence() -> None:
    rng = random.Random(STALL_SEED)
    stalled = PpuTimingModel()
    continuous = PpuTimingModel()
    completed_frames = 0
    fabric_cycles = 0
    disabled_cycles = 0

    while completed_frames < 12:
        enabled = rng.randrange(100) < 67
        before = stalled.snapshot()
        assert before == continuous.snapshot()

        if not enabled:
            disabled_cycles += 1
            assert not stalled.visible_pixel(False)
            assert not stalled.frame_start(False)
            assert not stalled.frame_end(True, False)
            assert not stalled.vblank_start(False)
            assert not stalled.vblank_end(False)

        frame_end = stalled.frame_end(True, enabled)
        stalled.clock(ppu_enable=enabled, rendering_enabled=True)
        if enabled:
            continuous.clock(rendering_enabled=True)
        else:
            assert stalled.snapshot() == before
        completed_frames += int(frame_end)
        fabric_cycles += 1

    assert continuous.snapshot() == stalled.snapshot()
    assert fabric_cycles > 1_500_000
    assert disabled_cycles > 500_000
