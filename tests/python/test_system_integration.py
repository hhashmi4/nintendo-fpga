"""Phase 6G completeness, reset epochs, event accounting and A/V contracts."""

from fractions import Fraction
from random import Random

import pytest

from verification.system_integration import (
    FaultCounterObserver, FrameAdmission, FrameEnable, audio_sample_count,
    samples_per_video_frame,
)


@pytest.mark.parametrize("bad", [1, 2, 255, 256, 32768, 61438, 61439])
def test_partial_frame_with_terminal_pixel_is_never_published(bad):
    frame = FrameAdmission()
    frame.sample(start=True, valid=True)
    frame.sample(valid=True, x=bad % 256, y=bad // 256)
    assert not frame.sample(valid=True, x=255, y=239)
    assert frame.captured == 0 and frame.sequence_error


@pytest.mark.parametrize("seed", [0x6A, 0x6007, 0x2026])
def test_complete_frame_recovers_after_random_damage(seed):
    random = Random(seed)
    frame = FrameAdmission()
    for _ in range(100):
        frame.sample(start=True)
        for _ in range(random.randrange(1, 30)):
            frame.sample(valid=True, x=random.randrange(256), y=random.randrange(256))
        assert not frame.sample(valid=True, x=255, y=239)
    frame.sample(start=True)
    published = [frame.sample(valid=True, x=i % 256, y=i // 256)
                 for i in range(61440)]
    assert sum(published) == 1 and published[-1] and frame.captured == 1
    assert frame.sequence_error and frame.range_error  # sticky until reset


def test_interrupted_frame_restarts_at_next_origin():
    frame = FrameAdmission()
    frame.sample(start=True, valid=True)
    frame.sample(start=True, valid=True)
    assert frame.sequence_error and frame.pixels == 1 and not frame.damaged
    for i in range(1, 61440):
        published = frame.sample(valid=True, x=i % 256, y=i // 256)
    assert published and frame.captured == 1


def test_freeze_finishes_current_frame_but_rejects_new_capture():
    frame = FrameAdmission()
    frame.sample(start=True, valid=True, frozen=True)
    assert not frame.active
    frame.sample(start=True, valid=True)
    for i in range(1, 61440):
        published = frame.sample(valid=True, x=i % 256, y=i // 256, frozen=True)
    assert published


@pytest.mark.parametrize("count", [1, 2, 3, 15, 255, 65535, 0xFFFFFFFF])
def test_counter_reset_is_not_a_new_fault(count):
    observer = FaultCounterObserver()
    assert observer.observe(count)
    assert not observer.observe(count)
    assert not observer.observe(0)
    assert observer.observe(1)


@pytest.mark.parametrize("seed", [7, 6007, 2026])
def test_random_fault_epochs(seed):
    random = Random(seed)
    observer = FaultCounterObserver()
    count = 0
    for _ in range(10000):
        reset = random.randrange(20) == 0
        increment = random.randrange(4)
        new = 0 if reset else min(0xFFFFFFFF, count + increment)
        assert observer.observe(new) == (not reset and new != count)
        count = new


@pytest.mark.parametrize("origin", range(8))
def test_hotplug_waits_for_frame_origin(origin):
    model = FrameEnable()
    for pixel in range(origin, 16):
        assert model.sample(True, pixel % 8 == 0) == (pixel >= (origin + 7) // 8 * 8)
    assert not model.sample(False, False)
    assert not model.sample(True, False)
    assert model.sample(True, True)
    assert not model.sample(True, True, reset=True)


def test_nominal_and_fitted_av_cadence():
    assert samples_per_video_frame(74_250_000) == 800
    fitted = samples_per_video_frame(Fraction(50_000_000 * 49, 33))
    assert fitted == Fraction(39204, 49)
    assert fitted > 800  # video rate cannot reset or retime the PCM producer
    assert audio_sample_count(13_125 * 10000) == 352 * 10000


@pytest.mark.parametrize("bad", [-1, 1 << 32])
def test_invalid_fault_counter_rejected(bad):
    with pytest.raises(ValueError):
        FaultCounterObserver().observe(bad)
