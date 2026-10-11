from collections import Counter
from random import Random

import pytest

from verification.shared_video import (
    CANVAS_LEFT,
    CANVAS_RIGHT,
    H_ACTIVE,
    H_SYNC,
    H_TOTAL,
    NES_HEIGHT,
    NES_PIXELS,
    NES_WIDTH,
    PIXELS_PER_OUTPUT_FRAME,
    V_ACTIVE,
    V_SYNC,
    V_TOTAL,
    FramebufferManagerModel,
    memory_options,
    scale_720p,
    simulate_frame_sequence,
    timing_sample,
)


def test_720p_timing_totals_and_frequency() -> None:
    assert (H_ACTIVE, H_TOTAL, V_ACTIVE, V_TOTAL) == (1280, 1650, 720, 750)
    assert PIXELS_PER_OUTPUT_FRAME == 1_237_500
    assert 74_250_000 / PIXELS_PER_OUTPUT_FRAME == 60


def test_720p_timing_directed_boundaries() -> None:
    assert timing_sample(0).frame_start
    assert not timing_sample(H_ACTIVE - 1).hsync
    assert not timing_sample(H_ACTIVE + 109).hsync
    assert timing_sample(H_ACTIVE + 110).hsync
    assert timing_sample(H_ACTIVE + 110 + H_SYNC - 1).hsync
    assert not timing_sample(H_ACTIVE + 110 + H_SYNC).hsync
    assert timing_sample(PIXELS_PER_OUTPUT_FRAME - 1).frame_end
    assert timing_sample(PIXELS_PER_OUTPUT_FRAME).frame_start


def test_720p_timing_exhaustive_counts() -> None:
    samples = (timing_sample(index) for index in range(PIXELS_PER_OUTPUT_FRAME))
    counts = Counter(
        name
        for sample in samples
        for name, asserted in (
            ("active", sample.active_video),
            ("hsync", sample.hsync),
            ("vsync", sample.vsync),
            ("line_start", sample.line_start),
            ("line_end", sample.line_end),
            ("frame_start", sample.frame_start),
            ("frame_end", sample.frame_end),
        )
        if asserted
    )
    assert counts == {
        "active": H_ACTIVE * V_ACTIVE,
        "hsync": H_SYNC * V_TOTAL,
        "vsync": V_SYNC * H_TOTAL,
        "line_start": V_TOTAL,
        "line_end": V_TOTAL,
        "frame_start": 1,
        "frame_end": 1,
    }


def test_normal_scaler_directed_edges_and_borders() -> None:
    assert not scale_720p(CANVAS_LEFT - 1, 0).canvas
    assert scale_720p(CANVAS_LEFT, 0).nes_x == 0
    assert scale_720p(CANVAS_LEFT, 0).nes_y == 0
    assert scale_720p(CANVAS_RIGHT - 1, V_ACTIVE - 1).nes_x == 255
    assert scale_720p(CANVAS_RIGHT - 1, V_ACTIVE - 1).nes_y == 239
    assert not scale_720p(CANVAS_RIGHT, V_ACTIVE - 1).canvas


def test_normal_scaler_exhaustive_coverage_and_monotonicity() -> None:
    hits = Counter()
    for y in range(V_ACTIVE):
        previous_address = -1
        for x in range(CANVAS_LEFT, CANVAS_RIGHT):
            sample = scale_720p(x, y)
            hits[sample.framebuffer_address] += 1
            assert sample.framebuffer_address >= previous_address
            previous_address = sample.framebuffer_address
    assert len(hits) == NES_PIXELS
    assert set(hits.values()) == {9, 12}
    assert sum(hits.values()) == 960 * 720


def test_normal_scaler_pillarbox_pixel_count() -> None:
    border_pixels = sum(
        not scale_720p(x, y).canvas
        for y in range(V_ACTIVE)
        for x in range(H_ACTIVE)
    )
    assert border_pixels == 2 * 160 * 720


def test_developer_layout_exact_game_scale() -> None:
    for source_y in (0, 1, 127, 239):
        for source_x in (0, 1, 127, 255):
            for repeat_y in range(3):
                for repeat_x in range(3):
                    sample = scale_720p(
                        CANVAS_LEFT + source_x * 3 + repeat_x,
                        source_y * 3 + repeat_y,
                        developer_layout=True,
                    )
                    assert (sample.nes_x, sample.nes_y) == (source_x, source_y)
                    assert sample.nes and not sample.panel


def test_developer_layout_panel_bounds_and_coverage() -> None:
    hits = Counter()
    for y in range(V_ACTIVE):
        for x in range(CANVAS_LEFT + 768, CANVAS_RIGHT):
            sample = scale_720p(x, y, developer_layout=True)
            assert sample.panel and not sample.nes
            hits[(sample.panel_x, sample.panel_y)] += 1
    assert len(hits) == 128 * 480
    assert set(hits.values()) == {1, 2, 4}
    assert min(hits) == (512, 0)
    assert max(hits) == (639, 479)


def test_random_scaler_coordinates_are_bounded() -> None:
    random = Random(0x6B)
    for _ in range(20_000):
        x = random.randrange(H_TOTAL)
        y = random.randrange(V_TOTAL)
        developer = bool(random.getrandbits(1))
        sample = scale_720p(x, y, developer)
        if sample.nes:
            assert 0 <= sample.nes_x < NES_WIDTH
            assert 0 <= sample.nes_y < NES_HEIGHT
            assert 0 <= sample.framebuffer_address < NES_PIXELS
        if sample.panel:
            assert 512 <= sample.panel_x < 640
            assert 0 <= sample.panel_y < 480


def test_memory_calculations() -> None:
    options = {(item.name, item.buffers): item for item in memory_options()}
    assert options["indexed6", 1].bits == 368_640
    assert options["indexed6", 2].bits == 737_280
    assert options["indexed9", 3].bits == 1_658_880
    assert options["rgb888", 1].bits == 1_474_560
    assert options["rgb888", 2].bits == 2_949_120
    assert options["rgb888", 3].bits == 4_423_680
    assert options["indexed9", 3].kibibytes == 202.5


def test_framebuffer_never_aliases_bank_roles() -> None:
    model = FramebufferManagerModel()
    assert model.begin_frame()
    model.complete_frame(0)
    assert model.begin_frame()
    model.complete_frame(1)
    assert len(model.owned_banks) == len(set(model.owned_banks))
    assert not model.begin_frame()
    assert model.reader_frame_end()
    assert model.service_writer()
    assert len(model.owned_banks) == len(set(model.owned_banks))


def test_framebuffer_only_displays_completed_frames() -> None:
    model = FramebufferManagerModel()
    assert model.begin_frame()
    for _ in range(10):
        assert not model.reader_frame_end()
    assert model.displayed_frame is None
    model.complete_frame(17)
    assert model.reader_frame_end()
    assert model.displayed_sequence == [17]


def test_framebuffer_freeze_skips_capture_without_side_effects() -> None:
    model = FramebufferManagerModel()
    assert not model.begin_frame(frozen=True)
    assert model.write_bank is None
    assert model.pending is None
    assert model.begin_frame()


@pytest.mark.parametrize(
    ("source_period", "output_period"),
    ((17, 23), (23, 17), (20, 20), (100, 3)),
)
def test_randomized_async_frame_sequencing(
    source_period: int, output_period: int
) -> None:
    for seed in range(20):
        model = simulate_frame_sequence(
            source_period, output_period, duration=20_000, seed=seed
        )
        assert model.displayed_sequence == sorted(model.displayed_sequence)
        assert len(model.displayed_sequence) == len(set(model.displayed_sequence))
        assert set(model.displayed_sequence) <= set(model.captured_sequence)


def test_invalid_frame_sequence_operations_fail_closed() -> None:
    model = FramebufferManagerModel()
    with pytest.raises(RuntimeError, match="not started"):
        model.complete_frame(0)
    assert model.begin_frame()
    assert not model.begin_frame()


def test_sequence_argument_validation() -> None:
    with pytest.raises(ValueError, match="positive"):
        simulate_frame_sequence(0, 1, 10)
