import pytest

from verification.runtime_cartridge import (
    CHR_STORAGE_BYTES,
    PRG_STORAGE_BYTES,
    RuntimeCartridgeModel,
    RuntimeTarget,
)


def test_storage_sizes_and_deterministic_model_initial_state():
    model = RuntimeCartridgeModel()
    assert len(model.prg) == 32768
    assert len(model.chr) == 8192
    assert not any(model.prg)
    assert not any(model.chr)


@pytest.mark.parametrize("address", [0, 1, 0x3FFF, 0x4000, 0x7FFF])
def test_prg_loader_boundaries(address):
    model = RuntimeCartridgeModel()
    assert model.loader_write(RuntimeTarget.PRG, address, address & 0xFF)
    assert model.prg[address] == address & 0xFF


@pytest.mark.parametrize("address", [0, 1, 0x0420, 0x1000, 0x1FFF])
def test_chr_loader_boundaries(address):
    model = RuntimeCartridgeModel()
    assert model.loader_write(RuntimeTarget.CHR, address, address & 0xFF)
    assert model.ppu_read(address) == address & 0xFF


def test_nrom128_mirrors_both_16k_cpu_windows():
    model = RuntimeCartridgeModel()
    for offset, value in ((0, 0xA9), (1, 0x42), (0x3FFF, 0xE7)):
        model.loader_write(RuntimeTarget.PRG, offset, value)
        assert model.cpu_read(0x8000 + offset, nrom_256=False) == value
        assert model.cpu_read(0xC000 + offset, nrom_256=False) == value


def test_nrom256_keeps_lower_and_upper_banks_independent():
    model = RuntimeCartridgeModel()
    model.loader_write(RuntimeTarget.PRG, 0, 0x11)
    model.loader_write(RuntimeTarget.PRG, 0x4000, 0x22)
    model.loader_write(RuntimeTarget.PRG, 0x7FFF, 0x33)
    assert model.cpu_read(0x8000, nrom_256=True) == 0x11
    assert model.cpu_read(0xC000, nrom_256=True) == 0x22
    assert model.cpu_read(0xFFFF, nrom_256=True) == 0x33


def test_overwrite_and_prg_chr_isolation():
    model = RuntimeCartridgeModel()
    model.loader_write(RuntimeTarget.PRG, 0x0420, 0x15)
    model.loader_write(RuntimeTarget.CHR, 0x0420, 0x26)
    model.loader_write(RuntimeTarget.PRG, 0x0420, 0x37)
    assert model.prg[0x0420] == 0x37
    assert model.chr[0x0420] == 0x26


def test_chr_rom_ignores_ppu_writes_and_chr_ram_accepts_them():
    model = RuntimeCartridgeModel()
    model.loader_write(RuntimeTarget.CHR, 0x1234, 0x5A)
    assert not model.ppu_write(0x1234, 0xA5, chr_is_ram=False)
    assert model.ppu_read(0x1234) == 0x5A
    assert model.ppu_write(0x1234, 0xA5, chr_is_ram=True)
    assert model.ppu_read(0x1234) == 0xA5


def test_invalid_or_reset_writes_are_harmless():
    model = RuntimeCartridgeModel()
    assert not model.loader_write(RuntimeTarget.PRG, PRG_STORAGE_BYTES, 0x11)
    assert not model.loader_write(RuntimeTarget.CHR, CHR_STORAGE_BYTES, 0x22)
    assert not model.loader_write(0, 0, 0x33)
    assert not model.loader_write(RuntimeTarget.PRG, 0, 0x44, reset=True)
    assert model.prg[0] == 0
    assert model.chr[0] == 0


def test_loader_read_collisions_are_write_first():
    model = RuntimeCartridgeModel()
    assert (
        model.collision_read(
            target=RuntimeTarget.PRG, address=0x1111, data=0xC3
        )
        == 0xC3
    )
    assert (
        model.collision_read(
            target=RuntimeTarget.CHR, address=0x0777, data=0x3C
        )
        == 0x3C
    )
