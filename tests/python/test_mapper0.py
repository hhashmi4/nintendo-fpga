import pytest

from verification.ines import CHR_BANK_SIZE, PRG_BANK_SIZE
from verification.mapper0 import (
    Mapper0Model,
    map_chr_address,
    map_ciram_address,
    map_prg_address,
)


def test_nrom128_prg_translation_is_exhaustively_mirrored() -> None:
    for address in range(0x8000, 0x10000):
        assert map_prg_address(address, PRG_BANK_SIZE) == (address & 0x3FFF)
    for offset in range(PRG_BANK_SIZE):
        assert map_prg_address(0x8000 + offset, PRG_BANK_SIZE) == offset
        assert map_prg_address(0xC000 + offset, PRG_BANK_SIZE) == offset


def test_nrom256_prg_translation_is_exhaustively_linear() -> None:
    for address in range(0x8000, 0x10000):
        assert map_prg_address(address, 2 * PRG_BANK_SIZE) == address - 0x8000


def test_prg_boundaries_and_vector_bytes() -> None:
    prg = bytearray((index * 17 + 9) & 0xFF for index in range(PRG_BANK_SIZE))
    prg[0x3FFA:0x4000] = bytes((0x34, 0x12, 0x78, 0x56, 0xBC, 0x9A))
    mapper = Mapper0Model(bytes(prg), bytes(CHR_BANK_SIZE))
    assert mapper.cpu_read(0x8000) == prg[0]
    assert mapper.cpu_read(0xBFFF) == prg[0x3FFF]
    assert mapper.cpu_read(0xC000) == prg[0]
    assert mapper.cpu_read(0xFFFA) == 0x34
    assert mapper.cpu_read(0xFFFB) == 0x12
    assert mapper.cpu_read(0xFFFC) == 0x78
    assert mapper.cpu_read(0xFFFD) == 0x56
    assert mapper.cpu_read(0xFFFE) == 0xBC
    assert mapper.cpu_read(0xFFFF) == 0x9A


def test_nrom256_vector_bytes_use_the_upper_prg_bank() -> None:
    prg = bytearray(2 * PRG_BANK_SIZE)
    prg[0x7FFA:0x8000] = bytes((0x21, 0x43, 0x65, 0x87, 0xA9, 0xCB))
    mapper = Mapper0Model(bytes(prg), bytes(CHR_BANK_SIZE))
    assert [mapper.cpu_read(address) for address in range(0xFFFA, 0x10000)] == [
        0x21,
        0x43,
        0x65,
        0x87,
        0xA9,
        0xCB,
    ]


def test_prg_ram_architecture_and_disabled_response() -> None:
    disabled = Mapper0Model(bytes(PRG_BANK_SIZE))
    assert disabled.cpu_read(0x6000) == disabled.cpu_read(0x7FFF) == 0
    enabled = Mapper0Model(bytes(PRG_BANK_SIZE), prg_ram_enabled=True)
    enabled.cpu_write(0x6000, 0x36)
    enabled.cpu_write(0x7FFF, 0xA9)
    assert enabled.cpu_read(0x6000) == 0x36
    assert enabled.cpu_read(0x7FFF) == 0xA9


def test_chr_rom_and_chr_ram_boundaries() -> None:
    chr_rom = bytes((index * 29 + 1) & 0xFF for index in range(CHR_BANK_SIZE))
    rom_mapper = Mapper0Model(bytes(PRG_BANK_SIZE), chr_rom)
    for address in (0x0000, 0x0FFF, 0x1000, 0x1FFF):
        assert map_chr_address(address) == address
        assert rom_mapper.ppu_read(address) == chr_rom[address]
        rom_mapper.ppu_write(address, 0xFF)
        assert rom_mapper.ppu_read(address) == chr_rom[address]

    ram_mapper = Mapper0Model(bytes(PRG_BANK_SIZE))
    for index, address in enumerate((0x0000, 0x0FFF, 0x1000, 0x1FFF)):
        ram_mapper.ppu_write(address, 0x40 + index)
        assert ram_mapper.ppu_read(address) == 0x40 + index


@pytest.mark.parametrize("mirroring", ["horizontal", "vertical"])
def test_nametable_mirroring_is_exhaustive(mirroring: str) -> None:
    for logical_page in range(4):
        for offset in range(0x400):
            address = 0x2000 + logical_page * 0x400 + offset
            if mirroring == "vertical":
                expected_page = logical_page & 1
            else:
                expected_page = logical_page >> 1
            assert map_ciram_address(address, mirroring) == (
                expected_page * 0x400 + offset
            )
            if address <= 0x2EFF:
                assert map_ciram_address(address + 0x1000, mirroring) == (
                    expected_page * 0x400 + offset
                )


def test_invalid_mapper0_sizes_are_rejected() -> None:
    with pytest.raises(ValueError):
        map_prg_address(0x8000, 8192)
    with pytest.raises(ValueError):
        Mapper0Model(bytes(8192))
