"""Visual specification checks independent of RTL expectations."""
import pytest
from verification.console_video import PALETTE, screen_lines, visual_fixtures, console_pixels
from verification.debug_renderer import FONT_5X8


def luminance(rgb):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return sum(k * channel((rgb >> s) & 255) for k, s in zip((.2126, .7152, .0722), (16, 8, 0)))


@pytest.mark.parametrize('foreground', ['text', 'muted', 'success', 'warning', 'error'])
@pytest.mark.parametrize('background', ['bg', 'surface', 'purple'])
def test_text_contrast(foreground, background):
    assert (luminance(PALETTE[foreground]) + .05) / (luminance(PALETTE[background]) + .05) >= 4.5


@pytest.mark.parametrize('fixture', visual_fixtures())
def test_text_stays_inside_safe_area_and_supported_font(fixture):
    status, focus, splash, phase = fixture
    for x, y, line, color in screen_lines(status, 0xA5, True, focus):
        assert x >= 32 and x + len(line)*16 <= 608
        assert 32 <= y < 448 and color in PALETTE
        assert all(c in FONT_5X8 for c in line)
        if status & 15 == 7:
            assert x + len(line)*16 <= 512, 'do not overlap the real debugger panel'


def test_invalid_status_is_black():
    assert not any(console_pixels(0, 0, True, valid=False))


@pytest.mark.parametrize('focus', [False, True])
def test_focus_and_disabled_action_geometry(focus):
    pixels = console_pixels(0x10001, 0, True, focus=focus)
    assert pixels[(204 + 48 * focus)*640+44] == PALETTE['text']
    assert pixels[(204 + 48 * focus)*640+48] == PALETTE['purple']
    assert pixels[352*640+32] == PALETTE['bg']


@pytest.mark.parametrize('phase', [0, 8, 16, 24])
def test_activity_has_one_lit_dot(phase):
    pixels=console_pixels(0x10402, 0, True, phase=phase)
    assert [pixels[184*640+56+n*16] for n in range(4)].count(PALETTE['text']) == 1
