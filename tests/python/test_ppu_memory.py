import random

import pytest

from verification.ppu_memory import (
    MemoryRegion,
    MirroringMode,
    PpuMemoryModel,
    canonical_palette_index,
    physical_page,
    translate,
)


RANDOM_SEED = 0x3C0FFEE1


def test_all_14_bit_addresses_are_classified_and_translated() -> None:
    region_counts = {
        MemoryRegion.CHR: 0,
        MemoryRegion.NAMETABLE: 0,
        MemoryRegion.PALETTE: 0,
    }
    for address in range(0x4000):
        for mode in MirroringMode:
            decoded = translate(address, mode)
            assert decoded.address == address
            assert 0 <= decoded.chr_address <= 0x1FFF
            assert 0 <= decoded.normalized_nametable_address <= 0xFFF
            assert 0 <= decoded.logical_nametable <= 3
            assert 0 <= decoded.nametable_offset <= 0x3FF
            assert 0 <= decoded.physical_ciram_page <= 1
            assert 0 <= decoded.ciram_address <= 0x7FF
            assert 0 <= decoded.palette_index <= 0x1F
        region_counts[translate(address, MirroringMode.VERTICAL).region] += 1

    assert region_counts == {
        MemoryRegion.CHR: 0x2000,
        MemoryRegion.NAMETABLE: 0x1F00,
        MemoryRegion.PALETTE: 0x0100,
    }


@pytest.mark.parametrize(
    ("address", "region"),
    (
        (0x0000, MemoryRegion.CHR),
        (0x1FFF, MemoryRegion.CHR),
        (0x2000, MemoryRegion.NAMETABLE),
        (0x23FF, MemoryRegion.NAMETABLE),
        (0x2400, MemoryRegion.NAMETABLE),
        (0x27FF, MemoryRegion.NAMETABLE),
        (0x2800, MemoryRegion.NAMETABLE),
        (0x2BFF, MemoryRegion.NAMETABLE),
        (0x2C00, MemoryRegion.NAMETABLE),
        (0x2FFF, MemoryRegion.NAMETABLE),
        (0x3000, MemoryRegion.NAMETABLE),
        (0x33FF, MemoryRegion.NAMETABLE),
        (0x3400, MemoryRegion.NAMETABLE),
        (0x37FF, MemoryRegion.NAMETABLE),
        (0x3800, MemoryRegion.NAMETABLE),
        (0x3BFF, MemoryRegion.NAMETABLE),
        (0x3C00, MemoryRegion.NAMETABLE),
        (0x3EFF, MemoryRegion.NAMETABLE),
        (0x3F00, MemoryRegion.PALETTE),
        (0x3F1F, MemoryRegion.PALETTE),
        (0x3F20, MemoryRegion.PALETTE),
        (0x3FFF, MemoryRegion.PALETTE),
    ),
)
def test_directed_region_boundaries(address: int, region: MemoryRegion) -> None:
    assert translate(address, MirroringMode.VERTICAL).region == region


def test_all_3000_addresses_mirror_2000_side() -> None:
    for address in range(0x3000, 0x3F00):
        for mode in MirroringMode:
            mirrored = translate(address, mode)
            canonical = translate(address - 0x1000, mode)
            assert mirrored.normalized_nametable_address == (
                canonical.normalized_nametable_address
            )
            assert mirrored.logical_nametable == canonical.logical_nametable
            assert mirrored.nametable_offset == canonical.nametable_offset
            assert mirrored.ciram_address == canonical.ciram_address


def test_logical_pages_and_offsets_at_boundaries() -> None:
    for page in range(4):
        start = translate(0x2000 + page * 0x400, MirroringMode.VERTICAL)
        end = translate(0x23FF + page * 0x400, MirroringMode.VERTICAL)
        assert (start.logical_nametable, start.nametable_offset) == (page, 0)
        assert (end.logical_nametable, end.nametable_offset) == (page, 0x3FF)


def test_mirroring_page_patterns() -> None:
    expected = {
        MirroringMode.VERTICAL: [0, 1, 0, 1],
        MirroringMode.HORIZONTAL: [0, 0, 1, 1],
        MirroringMode.SINGLE_SCREEN_LOWER: [0, 0, 0, 0],
        MirroringMode.SINGLE_SCREEN_UPPER: [1, 1, 1, 1],
    }
    for mode, pages in expected.items():
        assert [physical_page(page, mode) for page in range(4)] == pages


def test_storage_aliases_for_every_mirroring_mode() -> None:
    for mode in MirroringMode:
        model = PpuMemoryModel(mode)
        for logical_page, signature in enumerate((0x11, 0x22, 0x33, 0x44)):
            model.write(0x2000 + logical_page * 0x400, signature)

        expected_by_physical: dict[int, int] = {}
        for logical_page, signature in enumerate((0x11, 0x22, 0x33, 0x44)):
            expected_by_physical[physical_page(logical_page, mode)] = signature
        for logical_page in range(4):
            assert model.read(0x2000 + logical_page * 0x400) == expected_by_physical[
                physical_page(logical_page, mode)
            ]


def test_dynamic_mirroring_changes_mapping_without_clearing_ciram() -> None:
    model = PpuMemoryModel(MirroringMode.VERTICAL)
    model.write(0x2000, 0xA1)
    model.write(0x2400, 0xB2)
    before = bytes(model.ciram)

    model.set_mode(MirroringMode.HORIZONTAL)
    assert model.read(0x2000) == 0xA1
    assert model.read(0x2400) == 0xA1
    assert model.read(0x2800) == 0xB2
    assert bytes(model.ciram) == before


def test_nametable_3000_read_and_write_aliases() -> None:
    model = PpuMemoryModel(MirroringMode.VERTICAL)
    model.write(0x3000, 0x5A)
    assert model.read(0x2000) == 0x5A
    assert model.read(0x2800) == 0x5A
    assert model.read(0x3000) == 0x5A
    assert model.read(0x3800) == 0x5A


def test_exhaustive_palette_canonical_mapping_and_alias_writes() -> None:
    expected_special = {0x10: 0x00, 0x14: 0x04, 0x18: 0x08, 0x1C: 0x0C}
    for address in range(0x3F00, 0x4000):
        index = canonical_palette_index(address)
        assert 0 <= index < 32
        assert index == canonical_palette_index(address - 0x20)
        if address & 0x1F in expected_special:
            assert index == expected_special[address & 0x1F]

    model = PpuMemoryModel()
    for alias, canonical in ((0x3F10, 0x3F00), (0x3F14, 0x3F04),
                             (0x3F18, 0x3F08), (0x3F1C, 0x3F0C)):
        model.write(alias, 0x80 | (alias & 0x0F))
        assert model.read(canonical) == model.read(alias)
        model.write(canonical, alias & 0xFF)
        assert model.read(alias) == (alias & 0xFF)
    model.write(0x3F30, 0xCC)
    assert model.read(0x3F00) == 0xCC
    assert model.read(0x3F10) == 0xCC
    assert model.read(0x3F20) == 0xCC


def test_chr_ram_device_read_write_semantics() -> None:
    model = PpuMemoryModel()
    for address in (0x0000, 0x0123, 0x1000, 0x1FFF):
        model.write(address, address ^ 0xA5)
        assert model.read(address) == ((address ^ 0xA5) & 0xFF)


def test_deterministic_random_memory_operations() -> None:
    rng = random.Random(RANDOM_SEED)
    model = PpuMemoryModel()
    reference_chr = bytearray(8192)
    reference_ciram = bytearray(2048)
    reference_palette = bytearray(32)

    for _ in range(100_000):
        mode = MirroringMode(rng.randrange(4))
        model.set_mode(mode)
        address = rng.randrange(0x4000)
        decoded = translate(address, mode)
        if rng.randrange(2):
            data = rng.randrange(256)
            model.write(address, data)
            if decoded.region == MemoryRegion.CHR:
                reference_chr[decoded.chr_address] = data
            elif decoded.region == MemoryRegion.NAMETABLE:
                reference_ciram[decoded.ciram_address] = data
            else:
                reference_palette[decoded.palette_index] = data
        else:
            expected = (
                reference_chr[decoded.chr_address]
                if decoded.region == MemoryRegion.CHR
                else reference_ciram[decoded.ciram_address]
                if decoded.region == MemoryRegion.NAMETABLE
                else reference_palette[decoded.palette_index]
            )
            assert model.read(address) == expected
