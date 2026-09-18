import random

from verification.ppu_registers import (
    OAMADDR,
    OAMDATA,
    PPUADDR,
    PPUCTRL,
    PPUDATA,
    PPUMASK,
    PPUSCROLL,
    PPUSTATUS,
    PpuBusInputs,
    PpuRegisterModel,
)


INTERLEAVE_SEED = 0x3B200506


def transaction(
    model: PpuRegisterModel,
    register: int,
    *,
    write: bool,
    data: int = 0,
    mirror: int = 0,
    **inputs: int | bool,
):
    return model.clock(
        PpuBusInputs(
            cpu_enable=True,
            cpu_bus_valid=True,
            cpu_bus_write=write,
            cpu_address=0x2000 + 8 * mirror + register,
            cpu_write_data=data,
            **inputs,
        )
    )


def set_vram_address(model: PpuRegisterModel, address: int) -> None:
    transaction(model, PPUADDR, write=True, data=(address >> 8) & 0x3F)
    transaction(model, PPUADDR, write=True, data=address & 0xFF)


def test_exhaustive_cpu_address_mirroring_and_boundaries() -> None:
    model = PpuRegisterModel()
    counts = [0] * 8
    for address in range(0x2000, 0x4000):
        selected, register = model.decode(address)
        assert selected
        assert register == address & 7
        counts[register] += 1
    assert counts == [1024] * 8

    for address in (0x0000, 0x1FFF, 0x4000, 0x4014, 0xFFFF):
        assert model.decode(address)[0] is False


def test_ppuctrl_all_bits_decoding_increment_and_nametable_copy() -> None:
    model = PpuRegisterModel()
    model.t = 0x55AA
    for bit in range(8):
        transaction(model, PPUCTRL, write=True, data=1 << bit)
        assert model.ppuctrl == 1 << bit
        assert model.vram_increment == (32 if bit == 2 else 1)
        assert (model.t >> 10) & 3 == ((1 << bit) & 3)
        assert model.t & ~(3 << 10) == 0x55AA & ~(3 << 10)
    transaction(model, PPUCTRL, write=True, data=0xFF)
    assert model.ppuctrl == 0xFF


def test_ppumask_all_bits_and_rendering_enable() -> None:
    model = PpuRegisterModel()
    for bit in range(8):
        transaction(model, PPUMASK, write=True, data=1 << bit)
        assert model.ppumask == 1 << bit
        assert model.rendering_enabled is (bit in (3, 4))
    transaction(model, PPUMASK, write=True, data=0x18)
    assert model.rendering_enabled
    transaction(model, PPUMASK, write=True, data=0)
    assert not model.rendering_enabled


def test_ppustatus_events_open_bus_and_read_side_effects() -> None:
    model = PpuRegisterModel()
    transaction(model, PPUMASK, write=True, data=0x1B)
    transaction(model, PPUSCROLL, write=True, data=0x55)
    assert model.w

    model.clock(
        PpuBusInputs(
            vblank_start_event=True,
            sprite_zero_hit_set=True,
            sprite_overflow_set=True,
        )
    )
    result = transaction(model, PPUSTATUS, write=False)
    assert result.cpu_read_data == 0xF5
    assert model.io_latch == 0xF5
    assert not model.status_vblank
    assert model.status_sprite_zero_hit
    assert model.status_sprite_overflow
    assert not model.w

    model.clock(PpuBusInputs(status_clear_event=True))
    assert model.status == 0


def test_write_only_reads_retain_latch_and_do_not_change_state() -> None:
    model = PpuRegisterModel()
    transaction(model, PPUCTRL, write=True, data=0xA6)
    before = model.__dict__.copy()
    for register in (PPUCTRL, PPUMASK, OAMADDR, PPUSCROLL, PPUADDR):
        observed = transaction(model, register, write=False)
        assert observed.cpu_read_data == 0xA6
        assert model.__dict__ == before


def test_oamaddr_and_oamdata_external_interface() -> None:
    model = PpuRegisterModel()
    transaction(model, OAMADDR, write=True, data=0xFF)
    write = PpuBusInputs(
        cpu_enable=True,
        cpu_bus_valid=True,
        cpu_bus_write=True,
        cpu_address=0x3FFC,
        cpu_write_data=0x63,
    )
    observed = model.observe(write)
    assert observed.oam_write_enable
    assert model.oam_addr == 0xFF
    model.clock(write)
    assert model.oam_addr == 0x00

    observed = transaction(model, OAMDATA, write=False, oam_read_data=0x9C)
    assert observed.cpu_read_data == 0x9C
    assert model.io_latch == 0x9C
    assert model.oam_addr == 0x00


def test_ppuscroll_fields_and_unrelated_t_bits() -> None:
    model = PpuRegisterModel()
    model.t = 0x0C00
    transaction(model, PPUSCROLL, write=True, data=0b10101_110)
    assert model.t == 0x0C15
    assert model.x == 6
    assert model.w

    transaction(model, PPUSCROLL, write=True, data=0b11010_011)
    assert model.t & 0x001F == 0x15
    assert (model.t >> 5) & 0x1F == 0x1A
    assert (model.t >> 10) & 3 == 3
    assert (model.t >> 12) & 7 == 3
    assert not model.w


def test_ppuaddr_new_low_byte_is_copied_and_bit14_is_forced_low() -> None:
    model = PpuRegisterModel()
    model.t = 0x7FFF
    transaction(model, PPUADDR, write=True, data=0xFF)
    assert model.t == 0x3FFF
    assert model.w
    transaction(model, PPUADDR, write=True, data=0x34)
    assert model.t == 0x3F34
    assert model.v == 0x3F34
    assert not model.w


def test_shared_scroll_address_toggle_and_status_reset() -> None:
    model = PpuRegisterModel()

    transaction(model, PPUSCROLL, write=True, data=0x2D)
    transaction(model, PPUADDR, write=True, data=0x88)
    assert model.v == model.t
    assert model.v & 0xFF == 0x88
    assert not model.w

    transaction(model, PPUADDR, write=True, data=0x21)
    transaction(model, PPUSCROLL, write=True, data=0x57)
    assert not model.w
    assert (model.t >> 5) & 0x1F == 0x0A
    assert (model.t >> 12) & 7 == 7

    transaction(model, PPUSCROLL, write=True, data=0xFF)
    assert model.w
    transaction(model, PPUSTATUS, write=False)
    assert not model.w
    transaction(model, PPUADDR, write=True, data=0x3A)
    assert model.w
    transaction(model, PPUSTATUS, write=False)
    assert not model.w


def test_randomized_2002_2005_2006_interleaving_invariants() -> None:
    rng = random.Random(INTERLEAVE_SEED)
    model = PpuRegisterModel()
    for _ in range(20_000):
        register = rng.choice((PPUSTATUS, PPUSCROLL, PPUADDR))
        before_w = model.w
        data = rng.randrange(256)
        transaction(model, register, write=register != PPUSTATUS, data=data)
        if register == PPUSTATUS:
            assert not model.w
        else:
            assert model.w is (not before_w)
        assert 0 <= model.v <= 0x7FFF
        assert 0 <= model.t <= 0x7FFF
        assert 0 <= model.x <= 7


def test_ppudata_buffer_palette_refill_increments_and_writes() -> None:
    model = PpuRegisterModel()
    model.read_buffer = 0x12
    set_vram_address(model, 0x2345)
    result = transaction(model, PPUDATA, write=False, memory_read_data=0xA5)
    assert result.cpu_read_data == 0x12
    assert result.memory_read_request
    assert result.memory_address == 0x2345
    assert result.memory_buffer_address == 0x2345
    assert model.read_buffer == 0xA5
    assert model.v == 0x2346

    set_vram_address(model, 0x3F1C)
    result = transaction(
        model,
        PPUDATA,
        write=False,
        memory_read_data=0x67,
        memory_buffer_read_data=0x89,
    )
    assert result.cpu_read_data == 0x67
    assert result.memory_buffer_address == 0x2F1C
    assert model.read_buffer == 0x89
    assert model.v == 0x3F1D

    transaction(model, PPUCTRL, write=True, data=0x04)
    model.v = 0x7FE1
    write = PpuBusInputs(
        cpu_enable=True,
        cpu_bus_valid=True,
        cpu_bus_write=True,
        cpu_address=0x2007,
        cpu_write_data=0xDE,
    )
    result = model.observe(write)
    assert result.memory_write_request and not result.memory_read_request
    assert result.memory_address == 0x3FE1
    model.clock(write)
    assert model.v == 0x0001


def test_stalls_invalid_cycles_and_outside_addresses_have_no_cpu_effects() -> None:
    model = PpuRegisterModel()
    transaction(model, PPUCTRL, write=True, data=0x04)
    transaction(model, PPUMASK, write=True, data=0x18)
    set_vram_address(model, 0x2456)
    before = model.__dict__.copy()

    rejected = (
        PpuBusInputs(
            cpu_enable=False,
            cpu_bus_valid=True,
            cpu_bus_write=True,
            cpu_address=0x2007,
            cpu_write_data=0xAA,
        ),
        PpuBusInputs(
            cpu_enable=True,
            cpu_bus_valid=False,
            cpu_bus_write=True,
            cpu_address=0x2004,
            cpu_write_data=0xBB,
        ),
        PpuBusInputs(
            cpu_enable=True,
            cpu_bus_valid=True,
            cpu_bus_write=True,
            cpu_address=0x4014,
            cpu_write_data=0xCC,
        ),
    )
    for inputs in rejected:
        observed = model.clock(inputs)
        assert not observed.accepted
        assert not observed.oam_write_enable
        assert not observed.memory_read_request
        assert not observed.memory_write_request
        assert model.__dict__ == before
