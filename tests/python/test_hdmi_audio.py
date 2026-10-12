"""Phase 6D HDMI-audio independent model and policy tests."""

from __future__ import annotations

import random

import pytest

from verification.hdmi_audio import (
    ADV7513_AUDIO_PROFILE,
    BCLK_RATE,
    N_48KHZ,
    SAMPLE_RATE,
    SAMPLES_PER_720P60_FRAME,
    AudioError,
    AudioFifo,
    LinkModel,
    apply_audio_profile,
    av_consistency,
    bclk_half_edges,
    cta_supports_pcm,
    i2s_frame,
    random_pcm,
    serialize_stream,
    sign_extend_16_to_32,
    stereo_pcm,
    verify_audio_profile,
)


@pytest.mark.parametrize("sample", (0, 1, -1, 0x1234, -0x1234, 32767, -32768))
def test_stereo_i2s_alignment_bit_order_and_padding(sample: int) -> None:
    frame = i2s_frame(sample)
    assert len(frame) == 64
    assert frame[0] == (0, 0) and frame[32] == (1, 0)
    left = sum(frame[index][1] << (16 - index) for index in range(1, 17))
    right = sum(frame[index][1] << (48 - index) for index in range(33, 49))
    assert left == right == sample & 0xFFFF
    assert all(bit == 0 for _, bit in frame[17:32])
    assert all(bit == 0 for _, bit in frame[49:64])


def test_mono_duplication_has_no_gain_or_channel_swap() -> None:
    for sample in (-32768, -17, 0, 29, 32767):
        assert stereo_pcm(sample) == (sample, sample)


def test_signed_extension_boundaries_are_exact() -> None:
    assert sign_extend_16_to_32(0) == 0
    assert sign_extend_16_to_32(32767) == 0x00007FFF
    assert sign_extend_16_to_32(-1) == 0xFFFFFFFF
    assert sign_extend_16_to_32(-32768) == 0xFFFF8000
    with pytest.raises(ValueError):
        sign_extend_16_to_32(32768)


def test_mute_serializes_zero_without_consuming_a_different_sample() -> None:
    frames = serialize_stream((0x1234, -1, 0x5678), {1})
    assert frames[0] == i2s_frame(0x1234)
    assert frames[1] == i2s_frame(0)
    assert frames[2] == i2s_frame(0x5678)


def test_exact_clock_ratios() -> None:
    assert BCLK_RATE == 3_072_000
    edges = bclk_half_edges(50_000 * 20)
    assert len(edges) == 122_880
    gaps = [b - a for a, b in zip(edges, edges[1:])]
    assert set(gaps) == {8, 9}
    assert all(0.4 <= a / (a + b) <= 0.6 for a, b in zip(gaps, gaps[1:]))
    assert len(edges) // 2 // 64 == 960


def test_fifo_empty_full_wrap_overrun_underrun_and_flush() -> None:
    fifo = AudioFifo(4)
    assert fifo.read() == 0 and fifo.underruns == 1
    for value in range(4):
        assert fifo.write(value)
    assert not fifo.write(4) and fifo.overruns == 1
    assert [fifo.read() for _ in range(4)] == list(range(4))
    for value in range(20):
        assert fifo.write(value)
        assert fifo.read() == value
    fifo.write(7)
    fifo.flush()
    assert not fifo.samples


def test_documented_audio_profile_order_fields_and_readback() -> None:
    configured, writes = apply_audio_profile({0x0B: 0x1F, 0x44: 0x97})
    assert len(ADV7513_AUDIO_PROFILE) == 19
    assert writes[0][0] == 0x44 and writes[-1][0] == 0x4A
    assert ((configured[0x01] & 0x0F) << 16 | configured[0x02] << 8 | configured[0x03]) == N_48KHZ
    assert configured[0x0B] & 0xE0 == 0
    assert configured[0x0C] == 0xC4
    assert configured[0x14] & 0x0F == 2
    assert configured[0x15] >> 4 == 2
    assert configured[0x73] & 7 == 1
    assert configured[0x44] & 0x68 == 0x68
    assert configured[0x4A] & 0x20 == 0
    assert verify_audio_profile(configured)


def test_audio_profile_verify_detects_corruption_and_preserves_video_bits() -> None:
    initial = {0x44: 0x97, 0x0B: 0x1F}
    configured, _ = apply_audio_profile(initial)
    assert configured[0x44] & ~0x68 == initial[0x44] & ~0x68
    assert configured[0x0B] & ~0xE0 == initial[0x0B] & ~0xE0
    configured[0x15] ^= 0x10
    assert not verify_audio_profile(configured)


def test_startup_disconnect_reconnect_user_mute_and_fault_clear() -> None:
    link = LinkModel()
    assert link.muted and not link.enabled
    link.set_connected(True)
    link.set_clock_locked(True)
    link.configured = link.primed = True
    assert link.enabled and not link.muted
    link.user_mute = True
    assert link.muted
    link.user_mute = False
    link.set_connected(False)
    assert link.error is AudioError.LINK_LOST and link.muted
    link.set_connected(True)
    assert link.reconnects == 1
    link.clear_fault()
    assert link.error is AudioError.NONE


def test_clock_unlock_fails_closed() -> None:
    link = LinkModel(True, True, True, True)
    link.set_clock_locked(False)
    assert link.error is AudioError.CLOCK_UNLOCKED
    assert link.muted and not link.configured


def test_720p60_audio_video_consistency_is_not_a_frame_restart() -> None:
    assert SAMPLES_PER_720P60_FRAME == 800
    assert av_consistency(10_000, 8_000_000) == 0
    assert av_consistency(10, 7_999) == -1
    with pytest.raises(ValueError):
        av_consistency(1, 800, exact_60hz=False)


def test_seeded_random_fifo_and_i2s_sequence() -> None:
    seed = 0x6D48_0000
    randomizer = random.Random(seed)
    fifo = AudioFifo(32)
    expected: list[int] = []
    observed: list[int] = []
    for cycle in range(100_000):
        if randomizer.randrange(17) < 8:
            sample = randomizer.randrange(-32768, 32768)
            if fifo.write(sample):
                expected.append(sample)
        if randomizer.randrange(17) < 8 and fifo.samples:
            sample = fifo.read()
            observed.append(sample)
            frame = i2s_frame(sample)
            assert frame[1][1] == ((sample >> 15) & 1)
        if cycle and cycle % 20_000 == 0:
            # A reconnect flush discards only samples still queued, never an
            # already-observed sample or a future producer sample.
            pending = len(fifo.samples)
            del expected[len(observed) : len(observed) + pending]
            fifo.flush()
    while fifo.samples:
        observed.append(fifo.read())
    assert observed == expected
    assert fifo.overruns >= 0 and fifo.underruns == 0


def test_seeded_rtl_vector_algorithm_is_reproducible() -> None:
    vectors = random_pcm(0x6D48_0001, 256)
    assert vectors[:4] == (22892, -31269, 382, 15045)
    assert len(set(vectors)) == 256
    assert min(vectors) < -32_000 and max(vectors) > 32_000


def test_sample_rate_constant() -> None:
    assert SAMPLE_RATE == 48_000


def test_cta_audio_capability_basic_and_explicit_sad() -> None:
    extension = bytearray(128)
    extension[:4] = bytes((2, 3, 4, 0))
    assert not cta_supports_pcm(extension)
    extension[3] = 0x40
    assert cta_supports_pcm(extension)
    extension[3] = 0
    extension[2] = 8
    extension[4:8] = bytes((0x23, 0x09, 4, 1))
    assert cta_supports_pcm(extension)
    for index, value in ((5, 0x11), (6, 2), (7, 4)):
        invalid = extension.copy()
        invalid[index] = value
        assert not cta_supports_pcm(invalid)


def test_cta_audio_rejects_empty_and_truncated_descriptors() -> None:
    extension = bytearray(128)
    extension[:8] = bytes((2, 3, 0, 0, 0x23, 0x09, 4, 1))
    assert not cta_supports_pcm(extension)
    extension[2] = 7
    assert not cta_supports_pcm(extension)
    extension = bytearray(128)
    extension[:4] = bytes((2, 3, 255, 0))
    extension[124:] = bytes((0x23, 0x09, 4, 1))
    assert not cta_supports_pcm(extension)
