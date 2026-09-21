from verification.debug_renderer import (
    FONT_5X8,
    SUPPORTED_CHARACTERS,
    build_character_grid,
    hex_value,
    pad_text,
    render_frame,
)


def test_complete_supported_font_is_deterministic() -> None:
    assert set(FONT_5X8) == set(SUPPORTED_CHARACTERS)
    for character in SUPPORTED_CHARACTERS:
        rows = FONT_5X8[character]
        assert len(rows) == 8
        assert all(len(row) == 5 and set(row) <= {"0", "1"} for row in rows)
        assert rows[-1] == "00000"


def test_heavily_used_glyphs_and_punctuation() -> None:
    assert FONT_5X8["A"][3] == "11111"
    assert FONT_5X8["F"][0] == "11111"
    assert FONT_5X8["0"][2] == "10011"
    assert FONT_5X8["-"][3] == "11111"
    assert FONT_5X8["="][2:5] == ("11111", "00000", "11111")
    assert FONT_5X8[":"][1] == FONT_5X8[":"][4] == "00110"


def test_hex_formatting_for_8_16_and_32_bits() -> None:
    assert [hex_value(value, 1) for value in range(16)] == list("0123456789ABCDEF")
    assert hex_value(0x3F, 2) == "3F"
    assert hex_value(0x80A5, 4) == "80A5"
    assert hex_value(0x12C, 8) == "0000012C"
    assert hex_value(0x1234, 2) == "34"


def test_layout_contains_expected_sections_and_values() -> None:
    grid, _ = build_character_grid()
    rows = ["".join(row) for row in grid]
    assert "FPGA CONSOLE - DEVELOPER MODE" in rows[0]
    assert "SNAP=0000012C" in rows[1]
    assert rows[4][1:8] == "PC=80A5"
    assert rows[6][53:61] == "NROM=128"
    assert rows[17][1:12] == "P1=A--TU--R"
    assert rows[22][27:40] == "RD=100 WR=100"


def test_controller_compaction_and_full_frame_shape() -> None:
    assert pad_text(0x00) == "--------"
    assert pad_text(0xFF) == "ABSTUDLR"
    assert pad_text(0x99) == "A--TU--R"
    pixels = render_frame()
    assert len(pixels) == 640 * 480 * 3
    assert pixels[:3] == bytes((0x10, 0x28, 0x44))
