from verification.debug_renderer import (
    FONT_5X8,
    SUPPORTED_CHARACTERS,
    build_character_grid,
    build_panel_character_grid,
    hex_value,
    pad_text,
    render_combined_frame,
    render_frame,
    render_panel,
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


def test_phase4ec_compact_panel_layout() -> None:
    grid, _ = build_panel_character_grid()
    rows = ["".join(row) for row in grid]
    assert rows[0][1:9] == "OVERVIEW"
    assert rows[0][12:15] == "1/5"
    assert rows[1][1:6] == "VALID"
    assert rows[3][1:8] == "PC 80A5"
    assert rows[4][1:15] == "A 03 X 10 Y 20"
    assert rows[9][1:12] == "SL08E DT0DD"
    assert rows[16][1:13] == "CHR12F0 MIRH"
    assert rows[19][1:9] == "A--TU--R"
    assert rows[27][1:11] == "ID0000012C"


def test_phase4ec_panel_and_combined_frame_shapes() -> None:
    panel = render_panel()
    assert len(panel) == 128 * 480 * 3
    game = bytes((index & 0xFF for index in range(512 * 480 * 3)))
    combined = render_combined_frame(game)
    assert len(combined) == 640 * 480 * 3
    for y in (0, 239, 479):
        combined_row = y * 640 * 3
        game_row = y * 512 * 3
        panel_row = y * 128 * 3
        assert combined[combined_row:combined_row + 512 * 3] == \
            game[game_row:game_row + 512 * 3]
        assert combined[combined_row + 512 * 3:(y + 1) * 640 * 3] == \
            panel[panel_row:(y + 1) * 128 * 3]


def test_phase4ed_all_page_layouts_and_health() -> None:
    expected_titles = ("OVERVIEW", "CPU/BUS", "PPU/CART", "DMA/PAD", "SYSTEM")
    expected_content = (
        (3, "PC 80A5"),
        (7, "ADDR 2002"),
        (16, "PRG 40A5:4C"),
        (6, "DAT 5A  OAM A5"),
        (12, "MISS  00000000"),
    )
    for page, title in enumerate(expected_titles):
        grid, _ = build_panel_character_grid(page=page)
        rows = ["".join(row) for row in grid]
        assert rows[0][1:1 + len(title)] == title
        assert rows[0][12:15] == f"{page + 1}/5"
        row, content = expected_content[page]
        assert content in rows[row]
        invalid, _ = build_panel_character_grid(page=page, valid=False)
        stale, _ = build_panel_character_grid(page=page, stale=True)
        assert "INVALID" in "".join(invalid[1])
        assert "STALE" in "".join(stale[1])


def test_phase4ed_page_validation_and_distinct_frames() -> None:
    game = bytes(512 * 480 * 3)
    frames = [render_combined_frame(game, page=page) for page in range(5)]
    assert len(set(frames)) == 5
    try:
        build_panel_character_grid(page=5)
    except ValueError as error:
        assert "0..4" in str(error)
    else:
        raise AssertionError("invalid page did not raise ValueError")
