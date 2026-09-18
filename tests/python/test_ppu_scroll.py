import random

from verification.ppu_registers import (
    PPUADDR,
    PPUCTRL,
    PPUDATA,
    PPUMASK,
    PPUSCROLL,
    PpuBusInputs,
    PpuRegisterModel,
)
from verification.ppu_scroll import (
    HORIZONTAL_INCREMENT_DOTS,
    active_data_increment,
    apply_automatic_scroll,
    attribute_fetch_address,
    copy_horizontal,
    copy_vertical,
    events_for_coordinate,
    increment_coarse_x,
    increment_vertical,
    nametable_fetch_address,
)


SCROLL_SEED = 0x3D5C0011


def write(model: PpuRegisterModel, register: int, data: int, **kwargs: int | bool):
    return model.clock(
        PpuBusInputs(
            cpu_enable=True,
            cpu_bus_valid=True,
            cpu_bus_write=True,
            cpu_address=0x2000 | register,
            cpu_write_data=data,
            **kwargs,
        )
    )


def read(model: PpuRegisterModel, register: int, **kwargs: int | bool):
    return model.clock(
        PpuBusInputs(
            cpu_enable=True,
            cpu_bus_valid=True,
            cpu_address=0x2000 | register,
            **kwargs,
        )
    )


def test_coarse_x_exhaustive_and_unrelated_fields_preserved() -> None:
    unrelated_mask = 0x7FE0
    for high in range(2):
        for coarse_x in range(32):
            address = 0x71A0 | (high << 10) | coarse_x
            result = increment_coarse_x(address)
            assert result & unrelated_mask & ~0x0400 == address & unrelated_mask & ~0x0400
            if coarse_x == 31:
                assert result & 0x1F == 0
                assert bool(result & 0x0400) is (not bool(address & 0x0400))
            else:
                assert result & 0x1F == coarse_x + 1
                assert result & 0x0400 == address & 0x0400


def test_vertical_increment_exhaustive() -> None:
    for fine_y in range(8):
        for coarse_y in range(32):
            for vertical_nt in range(2):
                address = (
                    (fine_y << 12)
                    | (vertical_nt << 11)
                    | (coarse_y << 5)
                    | 0x041B
                )
                result = increment_vertical(address)
                assert result & 0x041F == address & 0x041F
                if fine_y < 7:
                    assert (result >> 12) & 7 == fine_y + 1
                    assert (result >> 5) & 0x1F == coarse_y
                    assert result & 0x0800 == address & 0x0800
                else:
                    assert (result >> 12) & 7 == 0
                    if coarse_y == 29:
                        assert (result >> 5) & 0x1F == 0
                        assert bool(result & 0x0800) is not bool(address & 0x0800)
                    elif coarse_y == 31:
                        assert (result >> 5) & 0x1F == 0
                        assert result & 0x0800 == address & 0x0800
                    else:
                        assert (result >> 5) & 0x1F == coarse_y + 1
                        assert result & 0x0800 == address & 0x0800


def test_row_29_30_31_boundaries() -> None:
    row_29 = increment_vertical(0x7000 | (29 << 5))
    row_30 = increment_vertical(0x7000 | (30 << 5))
    row_31 = increment_vertical(0x7800 | (31 << 5))
    assert ((row_29 >> 5) & 31, bool(row_29 & 0x0800)) == (0, True)
    assert ((row_30 >> 5) & 31, bool(row_30 & 0x0800)) == (31, False)
    assert ((row_31 >> 5) & 31, bool(row_31 & 0x0800)) == (0, True)


def test_horizontal_and_vertical_copy_masks() -> None:
    rng = random.Random(SCROLL_SEED)
    for _ in range(10_000):
        address = rng.randrange(0x8000)
        temporary = rng.randrange(0x8000)
        horizontal = copy_horizontal(address, temporary)
        vertical = copy_vertical(address, temporary)
        assert horizontal & 0x041F == temporary & 0x041F
        assert horizontal & ~0x041F == address & ~0x041F
        assert vertical & 0x7BE0 == temporary & 0x7BE0
        assert vertical & ~0x7BE0 == address & ~0x7BE0


def test_every_coordinate_has_exact_scheduled_events() -> None:
    for scanline in range(262):
        render_line = scanline < 240 or scanline == 261
        for dot in range(341):
            events = events_for_coordinate(
                ppu_enable=True,
                rendering_enabled=True,
                scanline=scanline,
                dot=dot,
            )
            assert events.coarse_x_increment is (
                render_line and dot in HORIZONTAL_INCREMENT_DOTS
            )
            assert events.vertical_increment is (render_line and dot == 256)
            assert events.horizontal_copy is (render_line and dot == 257)
            assert events.vertical_copy is (
                scanline == 261 and 280 <= dot <= 304
            )


def test_rendering_and_ppu_enable_gate_every_automatic_operation() -> None:
    trigger_coordinates = ((0, 8), (239, 256), (261, 257), (261, 280), (261, 336))
    for scanline, dot in trigger_coordinates:
        for rendering, enabled in ((False, False), (False, True), (True, False)):
            result, events = apply_automatic_scroll(
                0x7FFF,
                0,
                ppu_enable=enabled,
                rendering_enabled=rendering,
                scanline=scanline,
                dot=dot,
            )
            assert not events.any
            assert result == 0x7FFF


def test_dot_256_combines_x_then_y_without_lost_fields() -> None:
    address = (7 << 12) | (29 << 5) | (1 << 10) | 31
    result, events = apply_automatic_scroll(
        address,
        0,
        ppu_enable=True,
        rendering_enabled=True,
        scanline=17,
        dot=256,
    )
    assert events.coarse_x_increment and events.vertical_increment
    assert result == increment_vertical(increment_coarse_x(address))
    assert result & 0x1F == 0
    assert not bool(result & 0x0400)
    assert (result >> 5) & 31 == 0
    assert bool(result & 0x0800)


def test_pre_render_vertical_reload_is_repeated_and_observes_new_t() -> None:
    model = PpuRegisterModel()
    model.ppumask = 0x08
    model.v = 0x0412
    model.t = 0x1560
    model.clock(PpuBusInputs(ppu_enable=True, scanline=261, dot=280))
    assert model.v == copy_vertical(0x0412, 0x1560)

    old_vertical = model.v & 0x7BE0
    model.w = True
    write(model, PPUSCROLL, 0xE5, ppu_enable=True, scanline=261, dot=281)
    assert model.v & 0x7BE0 == old_vertical
    model.clock(PpuBusInputs(ppu_enable=True, scanline=261, dot=282))
    assert model.v & 0x7BE0 == model.t & 0x7BE0


def test_ppudata_normal_and_active_render_increment_modes() -> None:
    model = PpuRegisterModel()
    model.v = 0x21FE
    model.ppuctrl = 0x04
    read(model, PPUDATA, scanline=240)
    assert model.v == 0x221E

    model.v = (7 << 12) | (29 << 5) | 31
    model.ppumask = 0x08
    expected = active_data_increment(model.v)
    read(model, PPUDATA, ppu_enable=False, scanline=12, dot=100)
    assert model.v == expected

    model.v = 0x1234
    model.ppumask = 0x10
    model.ppuctrl = 0x04
    expected = active_data_increment(model.v)
    write(model, PPUDATA, 0xA5, scanline=261, dot=310)
    assert model.v == expected


def test_ppudata_has_deterministic_priority_over_dot_256_schedule() -> None:
    model = PpuRegisterModel()
    model.ppumask = 0x18
    model.v = 0x73FF
    before = model.v
    read(model, PPUDATA, ppu_enable=True, scanline=0, dot=256)
    assert model.v == active_data_increment(before)


def test_second_ppuaddr_write_has_priority_over_horizontal_copy() -> None:
    model = PpuRegisterModel()
    model.ppumask = 0x08
    model.t = 0x2A00
    model.w = True
    write(model, PPUADDR, 0x5A, ppu_enable=True, scanline=0, dot=257)
    assert model.v == 0x2A5A


def test_ppuctrl_and_scroll_programming_remain_valid_during_rendering() -> None:
    model = PpuRegisterModel()
    write(model, PPUCTRL, 0x03)
    assert (model.t >> 10) & 3 == 3
    write(model, PPUSCROLL, 0b10110_101)
    write(model, PPUSCROLL, 0b11100_110)
    assert model.t & 0x1F == 0b10110
    assert (model.t >> 5) & 0x1F == 0b11100
    assert (model.t >> 12) & 7 == 0b110
    assert model.x == 0b101


def test_fetch_address_helpers_exhaustive() -> None:
    for address in range(0x8000):
        assert nametable_fetch_address(address) == 0x2000 | (address & 0x0FFF)
        assert attribute_fetch_address(address) == (
            0x23C0
            | (address & 0x0C00)
            | ((address >> 4) & 0x38)
            | ((address >> 2) & 0x07)
        )
