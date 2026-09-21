from verification.nes_system import (
    CpuTarget,
    OamDmaModel,
    Scheduler,
    decode_cpu_address,
    mirrored_ram_read,
)
import random


def test_cpu_decode_is_exhaustive_and_one_hot() -> None:
    counts = {target: 0 for target in CpuTarget}
    for address in range(0x10000):
        target, physical = decode_cpu_address(address)
        counts[target] += 1
        if target == CpuTarget.RAM:
            assert physical == (address & 0x07FF)
        elif target == CpuTarget.PPU:
            assert physical == (address & 7)
        elif target == CpuTarget.CARTRIDGE:
            assert physical == address
    assert counts == {
        CpuTarget.NONE: 0x0008,
        CpuTarget.RAM: 0x2000,
        CpuTarget.PPU: 0x2000,
        CpuTarget.APU: 0x0015,
        CpuTarget.DMA: 0x0001,
        CpuTarget.CONTROLLER: 0x0002,
        CpuTarget.CARTRIDGE: 0xBFE0,
    }


def test_ram_and_ppu_mirrors() -> None:
    for base in range(0x0800):
        assert {decode_cpu_address(base + mirror)[1]
                for mirror in (0, 0x0800, 0x1000, 0x1800)} == {base}
    for register in range(8):
        for address in range(0x2000 + register, 0x4000, 8):
            assert decode_cpu_address(address) == (CpuTarget.PPU, register)


def test_scheduler_has_exact_phase_and_no_drift() -> None:
    scheduler = Scheduler()
    observed = [scheduler.clock() for _ in range(300_000)]
    assert observed[:6] == [
        (True, False), (True, False), (True, True),
        (True, False), (True, False), (True, True),
    ]
    assert scheduler.ppu_ticks == 300_000
    assert scheduler.cpu_slots == 100_000
    assert scheduler.ppu_ticks == 3 * scheduler.cpu_slots


def test_scheduler_reset_restarts_phase_without_tick() -> None:
    scheduler = Scheduler()
    scheduler.clock()
    assert scheduler.clock(reset=True) == (False, False)
    assert [scheduler.clock() for _ in range(3)] == [
        (True, False), (True, False), (True, True)
    ]


def test_dma_even_start_takes_513_cycles_and_copies_256_bytes() -> None:
    model = OamDmaModel()
    model.trigger(0x02, cpu_cycle_odd=False)
    result = model.run(lambda address: (address ^ (address >> 3) ^ 0x5A))
    assert result.stall_cycles == 513
    assert result.reads == result.writes == 256
    assert model.oam == bytes(
        ((0x0200 + index) ^ ((0x0200 + index) >> 3) ^ 0x5A) & 0xFF
        for index in range(256)
    )


def test_dma_odd_start_takes_514_cycles() -> None:
    model = OamDmaModel()
    model.trigger(0x00, cpu_cycle_odd=True)
    result = model.run(lambda address: address)
    assert result.stall_cycles == 514
    assert result.reads == result.writes == 256


def test_dma_respects_ram_mirroring_and_oamaddr_wrap() -> None:
    ram = bytearray((index * 29 + 7) & 0xFF for index in range(2048))
    model = OamDmaModel()
    model.oam_address = 0xFC
    model.trigger(0x0A, cpu_cycle_odd=False)
    result = model.run(lambda address: mirrored_ram_read(ram, address))
    assert result.final_oam_address == 0xFC
    for index in range(256):
        assert model.oam[(0xFC + index) & 0xFF] == ram[(0x0200 + index) & 0x07FF]


def test_dma_never_duplicates_or_skips_an_address() -> None:
    addresses: list[int] = []
    model = OamDmaModel()
    model.trigger(0x7F, cpu_cycle_odd=True)

    def read(address: int) -> int:
        addresses.append(address)
        return len(addresses)

    model.run(read)
    assert addresses == list(range(0x7F00, 0x8000))
    assert model.reads == model.writes == 256


def test_future_io_and_unmapped_regions_are_deterministically_decoded() -> None:
    for address in (*range(0x4000, 0x4014), 0x4015):
        assert decode_cpu_address(address)[0] == CpuTarget.APU
    assert decode_cpu_address(0x4016)[0] == CpuTarget.CONTROLLER
    assert decode_cpu_address(0x4017)[0] == CpuTarget.CONTROLLER
    for address in range(0x4018, 0x4020):
        assert decode_cpu_address(address) == (CpuTarget.NONE, 0)


def test_deterministic_randomized_scheduler_bus_and_dma_reference() -> None:
    seed = 0x3A10_2026
    rng = random.Random(seed)
    scheduler = Scheduler()
    dma = OamDmaModel()
    ram = bytearray(rng.randrange(256) for _ in range(2048))
    expected_oam = bytearray(256)
    cpu_parity = False
    triggers = reads = writes = completions = mismatches = 0

    for _ in range(300_000):
        _, cpu_slot = scheduler.clock()
        if not cpu_slot:
            continue
        cpu_parity = not cpu_parity
        if dma.active:
            old_reads, old_writes = dma.reads, dma.writes
            completed = dma.cpu_slot(lambda address: mirrored_ram_read(ram, address))
            reads += dma.reads - old_reads
            writes += dma.writes - old_writes
            if completed:
                completions += 1
                page_base = dma.page << 8
                for index in range(256):
                    expected_oam[index] = mirrored_ram_read(ram, page_base | index)
                mismatches += sum(a != b for a, b in zip(dma.oam, expected_oam))
        else:
            operation = rng.randrange(1000)
            if operation < 5:
                page = rng.choice((0x00, 0x02, 0x08, 0x0A))
                dma.trigger(page, cpu_cycle_odd=cpu_parity)
                triggers += 1
            elif operation < 205:
                address = rng.randrange(0x2000)
                ram[address & 0x07FF] = rng.randrange(256)
            else:
                address = rng.randrange(0x10000)
                target, _ = decode_cpu_address(address)
                assert isinstance(target, CpuTarget)

    assert scheduler.ppu_ticks == 300_000
    assert scheduler.cpu_slots == 100_000
    assert triggers == 145
    assert completions == 145
    assert reads == writes == 37_120
    assert mismatches == 0
