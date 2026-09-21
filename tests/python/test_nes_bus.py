from collections import Counter

from verification.nes_bus import CpuTarget, decode_cpu_access


def test_full_address_space_read_decode() -> None:
    counts = Counter(
        decode_cpu_access(address).target for address in range(0x10000)
    )
    assert counts == {
        CpuTarget.NONE: 0x0008,
        CpuTarget.RAM: 0x2000,
        CpuTarget.PPU: 0x2000,
        CpuTarget.APU: 0x0015,
        CpuTarget.DMA: 0x0001,
        CpuTarget.CONTROLLER: 0x0002,
        CpuTarget.CARTRIDGE: 0xBFE0,
    }


def test_full_address_space_write_decode() -> None:
    counts = Counter(
        decode_cpu_access(address, write=True).target
        for address in range(0x10000)
    )
    assert counts == {
        CpuTarget.NONE: 0x0008,
        CpuTarget.RAM: 0x2000,
        CpuTarget.PPU: 0x2000,
        CpuTarget.APU: 0x0016,
        CpuTarget.DMA: 0x0001,
        CpuTarget.CONTROLLER: 0x0001,
        CpuTarget.CARTRIDGE: 0xBFE0,
    }


def test_ram_mirrors_and_boundaries() -> None:
    for physical in range(0x0800):
        aliases = [physical + offset for offset in (0, 0x0800, 0x1000, 0x1800)]
        assert {
            decode_cpu_access(address).physical_address for address in aliases
        } == {physical}
    assert decode_cpu_access(0x0000).physical_address == 0x000
    assert decode_cpu_access(0x07FF).physical_address == 0x7FF
    assert decode_cpu_access(0x0800).physical_address == 0x000
    assert decode_cpu_access(0x1FFF).physical_address == 0x7FF


def test_ppu_register_mirrors_and_boundaries() -> None:
    for register in range(8):
        for address in range(0x2000 + register, 0x4000, 8):
            decoded = decode_cpu_access(address)
            assert decoded.target == CpuTarget.PPU
            assert decoded.ppu_register == register
            assert decoded.physical_address == register
    assert decode_cpu_access(0x2000).ppu_register == 0
    assert decode_cpu_access(0x2007).ppu_register == 7
    assert decode_cpu_access(0x2008).ppu_register == 0
    assert decode_cpu_access(0x3FFF).ppu_register == 7


def test_io_decode_and_direction_sensitive_4017() -> None:
    assert decode_cpu_access(0x4014).target == CpuTarget.DMA
    assert decode_cpu_access(0x4016).target == CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4016, write=True).target == CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4017).target == CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4017, write=True).target == CpuTarget.APU
    for address in range(0x4018, 0x4020):
        assert decode_cpu_access(address).target == CpuTarget.NONE


def test_cartridge_region_boundaries() -> None:
    for address in (0x4020, 0x6000, 0x7FFF, 0x8000, 0xFFFF):
        decoded = decode_cpu_access(address)
        assert decoded.target == CpuTarget.CARTRIDGE
        assert decoded.physical_address == address


def test_decode_is_always_exactly_one_enumerated_target() -> None:
    for write in (False, True):
        for address in range(0x10000):
            assert isinstance(
                decode_cpu_access(address, write=write).target, CpuTarget
            )
