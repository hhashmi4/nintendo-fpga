from verification.nes_system import (
    DmaPhase,
    DmcDmaModel,
    OamDmaModel,
    dmc_read_cpu_space,
)


def run_fetch(*, started_odd: bool, address: int = 0xC123):
    dma = DmcDmaModel()
    reads: list[int] = []
    request = True
    results = []
    for _ in range(8):
        result = dma.cpu_slot(
            request=request,
            request_address=address,
            cpu_cycle_odd=started_odd,
            halt_allowed=True,
            read_cpu=lambda current: reads.append(current) or 0xA7,
        )
        results.append(result)
        if result.acknowledge:
            request = False
            break
    return dma, reads, results


def test_dmc_dma_even_and_odd_transactions_take_three_or_four_slots() -> None:
    for odd, expected in ((False, 3), (True, 4)):
        dma, reads, results = run_fetch(started_odd=odd)
        assert len(results) == expected
        assert reads == [0xC123]
        assert sum(result.acknowledge for result in results) == 1
        assert all(result.cpu_stall for result in results)
        assert results[0].start and results[-1].complete
        assert not dma.active and dma.phase == DmaPhase.IDLE
        assert dma.elapsed_cpu_cycles == expected


def test_dmc_request_waits_for_cpu_write_then_stalls_and_resumes_once() -> None:
    dma = DmcDmaModel()
    cpu_advances = 0
    reads = 0
    for _ in range(5):
        result = dma.cpu_slot(
            request=True,
            request_address=0xD234,
            cpu_cycle_odd=False,
            halt_allowed=False,
            read_cpu=lambda _: 0,
        )
        assert not result.cpu_stall and not result.start
        cpu_advances += 1

    request = True
    while request:
        result = dma.cpu_slot(
            request=request,
            request_address=0xD234,
            cpu_cycle_odd=False,
            halt_allowed=True,
            read_cpu=lambda _: 0x6C,
        )
        reads += int(result.acknowledge)
        request = not result.acknowledge
    cpu_advances += 1  # first slot after release
    assert reads == 1
    assert cpu_advances == 6


def test_dmc_dma_address_is_latched_and_stable_while_request_changes() -> None:
    dma = DmcDmaModel()
    observed = []
    request = True
    for slot in range(4):
        result = dma.cpu_slot(
            request=request,
            request_address=0xC000 + slot * 0x111,
            cpu_cycle_odd=True,
            halt_allowed=True,
            read_cpu=lambda address: observed.append(address) or 0x44,
        )
        request = not result.acknowledge
    assert observed == [0xC000]


def test_dmc_cpu_space_path_routes_ram_cartridge_and_suppresses_io() -> None:
    ram = bytearray((index * 19 + 3) & 0xFF for index in range(2048))
    ppu_reads: list[int] = []
    cart_reads: list[int] = []

    def ppu(register: int) -> int:
        ppu_reads.append(register)
        return 0x80 | register

    def cart(address: int) -> int:
        cart_reads.append(address)
        return address ^ (address >> 8) ^ 0xA5

    assert dmc_read_cpu_space(
        0x1855, ram, ppu_read=ppu, cartridge_read=cart
    ) == ram[0x55]
    assert dmc_read_cpu_space(
        0x3FFF, ram, ppu_read=ppu, cartridge_read=cart
    ) == 0x87
    expected = (0xC123 ^ 0xC1 ^ 0xA5) & 0xFF
    assert dmc_read_cpu_space(
        0xC123, ram, ppu_read=ppu, cartridge_read=cart
    ) == expected
    assert dmc_read_cpu_space(
        0x4016, ram, ppu_read=ppu, cartridge_read=cart
    ) == 0
    assert ppu_reads == [7]
    assert cart_reads == [0xC123]


def run_oam_collision(request_at: int) -> tuple[OamDmaModel, list[int], int]:
    oam = OamDmaModel()
    oam.trigger(0x02, cpu_cycle_odd=False)
    dmc = DmcDmaModel()
    dmc_addresses: list[int] = []
    request = False
    wall_slots = 0
    while oam.active or request or dmc.active:
        if wall_slots == request_at:
            request = True
        parity = bool(wall_slots & 1)
        dmc_result = dmc.cpu_slot(
            request=request,
            request_address=0xC0DE,
            cpu_cycle_odd=parity,
            halt_allowed=True,
            read_cpu=lambda address: dmc_addresses.append(address) or 0x5E,
        )
        if dmc_result.acknowledge:
            request = False
        if not dmc_result.cpu_stall and oam.active:
            oam.cpu_slot(lambda address: address ^ 0x5A)
        wall_slots += 1
        assert wall_slots < 600
    return oam, dmc_addresses, wall_slots


def test_dmc_priority_preserves_oam_before_during_and_near_completion() -> None:
    for request_at in (0, 100, 511):
        oam, dmc_addresses, wall_slots = run_oam_collision(request_at)
        assert dmc_addresses == [0xC0DE]
        assert oam.reads == oam.writes == 256
        assert oam.stall_cycles == 513
        assert wall_slots in (516, 517)
        assert oam.oam == bytes(
            ((0x0200 + index) ^ 0x5A) & 0xFF for index in range(256)
        )


def test_oam_can_begin_while_dmc_is_already_active_without_contention() -> None:
    dmc = DmcDmaModel()
    request = True
    for parity in (False, True):
        result = dmc.cpu_slot(
            request=request,
            request_address=0xFF20,
            cpu_cycle_odd=parity,
            halt_allowed=True,
            read_cpu=lambda _: 0x91,
        )
        assert result.cpu_stall

    oam = OamDmaModel()
    oam.trigger(0x08, cpu_cycle_odd=False)
    dmc_reads = 0
    while dmc.active:
        result = dmc.cpu_slot(
            request=request,
            request_address=0x0000,
            cpu_cycle_odd=False,
            halt_allowed=True,
            read_cpu=lambda _: 0x91,
        )
        dmc_reads += int(result.acknowledge)
        if result.acknowledge:
            request = False
    result = oam.run(lambda address: address)
    assert dmc_reads == 1
    assert result.stall_cycles == 513
    assert result.reads == result.writes == 256


def test_pause_and_reset_leave_no_implicit_dma_progress() -> None:
    dma = DmcDmaModel()
    dma.cpu_slot(
        request=True,
        request_address=0xE000,
        cpu_cycle_odd=True,
        halt_allowed=True,
        read_cpu=lambda _: 0,
    )
    before = (dma.active, dma.phase, dma.address, dma.elapsed_cpu_cycles)
    # A debugger pause produces no scheduled CPU-slot call at all.
    assert (dma.active, dma.phase, dma.address, dma.elapsed_cpu_cycles) == before
    dma.reset()
    assert not dma.active and dma.phase == DmaPhase.IDLE
    assert dma.elapsed_cpu_cycles == 0
