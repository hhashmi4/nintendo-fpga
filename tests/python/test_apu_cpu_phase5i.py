"""Independent directed checks for Phase 5I CPU/APU system integration."""

from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import subprocess
import sys

from verification.apu import APU_STATUS, ApuInputs, ApuModel
from verification.apu_mixer import quantized_mix
from verification.cpu import (
    CpuPhase2JModel,
    InterruptSource,
    VECTOR_IRQ_LOW,
    VECTOR_NMI_LOW,
    normalize_status,
    status_for_interrupt,
    status_for_php,
)
from verification.nes_bus import CpuTarget, decode_cpu_access
from verification.nes_system import ApuIrqSources, DmcDmaModel, OamDmaModel


PRG_SIZE = 16 * 1024
RESET = 0x8000
IRQ_HANDLER = 0x9000
NMI_HANDLER = 0x9200


def apu_cycle(apu: ApuModel, **kwargs: object):
    return apu.clock(ApuInputs(cpu_cycle_enable=True, **kwargs))


def apu_write(apu: ApuModel, address: int, data: int) -> None:
    apu_cycle(apu, cpu_write=True, cpu_address=address, cpu_write_data=data)


def set_vector(cpu: CpuPhase2JModel, vector: int, target: int) -> None:
    cpu.memory[vector] = target & 0xFF
    cpu.memory[vector + 1] = target >> 8


def irq_cpu(*, status: int = 0x20) -> CpuPhase2JModel:
    cpu = CpuPhase2JModel(initial_pc=0x8123, initial_status=status)
    set_vector(cpu, VECTOR_IRQ_LOW, IRQ_HANDLER)
    return cpu


def program_five_channels(apu: ApuModel) -> None:
    apu_write(apu, APU_STATUS, 0x0F)
    for address, value in (
        (0x4000, 0x3F), (0x4002, 0x08), (0x4003, 0x08),
        (0x4004, 0xBF), (0x4006, 0x0A), (0x4007, 0x08),
        (0x4008, 0xFF), (0x400A, 0x02), (0x400B, 0x08),
        (0x400C, 0x3F), (0x400E, 0x00), (0x400F, 0x08),
        (0x4010, 0x4F), (0x4011, 0x40), (0x4012, 0xC0),
        (0x4013, 0x01),
    ):
        apu_write(apu, address, value)
    apu_write(apu, APU_STATUS, 0x1F)


def test_cpu_apu_register_writes_decode_without_stealing_system_registers() -> None:
    assert all(
        decode_cpu_access(address, write=True).target is CpuTarget.APU
        for address in (*range(0x4000, 0x4014), 0x4015, 0x4017)
    )
    assert decode_cpu_access(0x4014, write=True).target is CpuTarget.DMA
    assert decode_cpu_access(0x4016, write=True).target is CpuTarget.CONTROLLER


def test_4015_reads_report_both_sources_and_clear_only_frame() -> None:
    sources = ApuIrqSources(frame=True, dmc=True)
    assert sources.read_4015(0x15) == 0xD5
    assert not sources.frame and sources.dmc and sources.line


def test_frame_irq_entry_uses_hardware_irq_path() -> None:
    sources = ApuIrqSources(frame=True)
    cpu = irq_cpu()
    cpu.sample_interrupt_inputs(nmi=False, irq=sources.line)
    assert cpu.service_pending_interrupt() is InterruptSource.IRQ
    assert cpu.pc == IRQ_HANDLER and cpu.memory[0x01FB] & 0x10 == 0


def test_dmc_irq_entry_uses_hardware_irq_path() -> None:
    sources = ApuIrqSources(dmc=True)
    cpu = irq_cpu()
    cpu.sample_interrupt_inputs(nmi=False, irq=sources.line)
    assert cpu.service_pending_interrupt() is InterruptSource.IRQ
    assert cpu.pc == IRQ_HANDLER and cpu.status & 0x04


def test_both_irq_sources_hold_line_until_independently_cleared() -> None:
    sources = ApuIrqSources(frame=True, dmc=True)
    assert sources.read_4015() == 0xC0 and sources.line
    sources.write_4015()
    assert not sources.line


def test_irq_masked_by_cpu_i_flag() -> None:
    cpu = irq_cpu(status=0x24)
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    assert cpu.service_pending_interrupt() is InterruptSource.NONE
    assert cpu.pc == 0x8123 and cpu.writes == []


def test_irq_pending_while_masked_remains_level_sensitive() -> None:
    sources = ApuIrqSources(frame=True)
    cpu = irq_cpu(status=0x24)
    for _ in range(4):
        cpu.sample_interrupt_inputs(nmi=False, irq=sources.line)
        assert cpu.service_pending_interrupt() is InterruptSource.NONE
    assert sources.line


def test_irq_unmask_accepts_pending_level_after_cli_delay() -> None:
    cpu = irq_cpu(status=0x24)
    cpu.load_program(0x8123, [0x58, 0xEA])  # CLI; NOP
    cpu.execute_one()
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    assert cpu.service_pending_interrupt() is InterruptSource.NONE
    cpu.execute_one()
    assert cpu.service_pending_interrupt() is InterruptSource.IRQ


def test_nmi_priority_when_apu_irq_is_already_pending() -> None:
    cpu = irq_cpu()
    set_vector(cpu, VECTOR_NMI_LOW, NMI_HANDLER)
    cpu.sample_interrupt_inputs(nmi=True, irq=True)
    assert cpu.service_pending_interrupt() is InterruptSource.NMI
    assert cpu.pc == NMI_HANDLER


def test_irq_after_nmi_rti_preserves_pending_level() -> None:
    cpu = irq_cpu()
    set_vector(cpu, VECTOR_NMI_LOW, NMI_HANDLER)
    cpu.memory[NMI_HANDLER] = 0x40
    cpu.sample_interrupt_inputs(nmi=True, irq=True)
    assert cpu.service_pending_interrupt() is InterruptSource.NMI
    cpu.execute_one()
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    assert cpu.service_pending_interrupt() is InterruptSource.IRQ


def test_brk_distinction_sets_b_while_hardware_irq_clears_it() -> None:
    brk = irq_cpu()
    brk.load_program(0x8123, [0x00, 0xEA])
    brk.execute_one()
    irq = irq_cpu()
    irq.sample_interrupt_inputs(nmi=False, irq=True)
    irq.service_pending_interrupt()
    assert brk.memory[0x01FB] == status_for_php(0x20)
    assert irq.memory[0x01FB] == status_for_interrupt(0x20)


def test_rti_restores_pc_status_and_stack_pointer() -> None:
    cpu = irq_cpu(status=0xC1)
    cpu.memory[IRQ_HANDLER] = 0x40
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    cpu.service_pending_interrupt()
    cpu.execute_one()
    assert cpu.pc == 0x8123 and cpu.sp == 0xFD
    assert cpu.status == normalize_status(0xC1)


def test_irq_stack_pc_and_status_bytes_are_ordered() -> None:
    cpu = irq_cpu(status=0x61)
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    cpu.service_pending_interrupt()
    assert cpu.writes == [
        (0x01FD, 0x81),
        (0x01FC, 0x23),
        (0x01FB, status_for_interrupt(0x61)),
    ]


def test_irq_vector_fetch_is_fffe_then_ffff() -> None:
    cpu = irq_cpu()
    cpu.reads.clear()
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    cpu.service_pending_interrupt()
    assert cpu.reads == [0xFFFE, 0xFFFF]


def test_dmc_stall_during_cpu_read_is_three_or_four_slots() -> None:
    for odd, expected in ((False, 3), (True, 4)):
        dma = DmcDmaModel()
        results = []
        while not results or not results[-1].complete:
            results.append(
                dma.cpu_slot(
                    request=True,
                    request_address=0xF000,
                    cpu_cycle_odd=odd,
                    halt_allowed=True,
                    read_cpu=lambda address: address & 0xFF,
                )
            )
        assert len(results) == expected and sum(r.acknowledge for r in results) == 1


def test_dmc_stall_near_cpu_write_waits_until_write_finishes() -> None:
    dma = DmcDmaModel()
    result = dma.cpu_slot(
        request=True, request_address=0xF000, cpu_cycle_odd=False,
        halt_allowed=False, read_cpu=lambda _: 0x53,
    )
    assert not result.start and not result.cpu_stall and not dma.active


def test_dmc_stall_during_irq_entry_does_not_mutate_cpu_frame() -> None:
    cpu = irq_cpu()
    cpu.sample_interrupt_inputs(nmi=False, irq=True)
    cpu.service_pending_interrupt()
    frame = (cpu.pc, cpu.sp, cpu.status, tuple(cpu.writes))
    dma = DmcDmaModel()
    for _ in range(3):
        dma.cpu_slot(
            request=True, request_address=0xF000, cpu_cycle_odd=False,
            halt_allowed=True, read_cpu=lambda _: 0x53,
        )
    assert (cpu.pc, cpu.sp, cpu.status, tuple(cpu.writes)) == frame


def test_dmc_during_oam_dma_holds_and_resumes_oam_exactly() -> None:
    oam = OamDmaModel()
    oam.trigger(0x02, cpu_cycle_odd=False)
    oam.cpu_slot(lambda address: address & 0xFF)
    held = (oam.phase, oam.index, oam.stall_cycles, oam.reads, oam.writes)
    dmc = DmcDmaModel()
    while True:
        result = dmc.cpu_slot(
            request=True, request_address=0xF000, cpu_cycle_odd=False,
            halt_allowed=True, read_cpu=lambda _: 0x53,
        )
        if result.complete:
            break
    assert (oam.phase, oam.index, oam.stall_cycles, oam.reads, oam.writes) == held
    completed = oam.run(lambda address: address & 0xFF)
    assert completed.reads == completed.writes == 256


def test_controller_read_during_dmc_is_not_owned_by_apu() -> None:
    assert decode_cpu_access(0x4016).target is CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4017).target is CpuTarget.CONTROLLER
    assert decode_cpu_access(0x4017, write=True).target is CpuTarget.APU


def test_debugger_pause_freezes_complete_apu_and_pending_irq() -> None:
    apu = ApuModel()
    apu.frame_irq_flag = True
    before = deepcopy(apu.complete_state())
    for _ in range(64):
        outputs, _ = apu.clock(ApuInputs(cpu_cycle_enable=False))
        assert outputs.irq
    assert apu.complete_state() == before


def test_debugger_step_accepts_one_apu_write_exactly_once() -> None:
    apu = ApuModel()
    apu_write(apu, APU_STATUS, 0x1F)
    state = deepcopy(apu.complete_state())
    for _ in range(32):
        apu.clock(
            ApuInputs(
                cpu_cycle_enable=False, cpu_write=True,
                cpu_address=APU_STATUS, cpu_write_data=0,
            )
        )
    assert apu.channel_enable == 0x1F and apu.complete_state() == state


def test_runtime_replacement_resets_irq_and_dma_state() -> None:
    sources = ApuIrqSources(frame=True, dmc=True)
    dma = DmcDmaModel()
    dma.cpu_slot(
        request=True, request_address=0xF000, cpu_cycle_odd=True,
        halt_allowed=True, read_cpu=lambda _: 0x53,
    )
    sources.reset()
    dma.reset()
    assert not sources.line and not dma.active


def test_all_five_channels_are_active_during_cpu_programmed_operation() -> None:
    apu = ApuModel()
    program_five_channels(apu)
    outputs, _ = apu_cycle(apu, cpu_read=True, cpu_address=APU_STATUS)
    assert outputs.cpu_read_data & 0x1F == 0x1F


def test_mixer_output_matches_existing_independent_model() -> None:
    apu = ApuModel()
    program_five_channels(apu)
    outputs, _ = apu_cycle(apu)
    assert apu.mixed_audio == quantized_mix(
        outputs.pulse1_output,
        outputs.pulse2_output,
        outputs.triangle_output,
        outputs.noise_output,
        outputs.dmc_output,
    )


def test_reset_with_pending_irq_clears_both_sources() -> None:
    sources = ApuIrqSources(frame=True, dmc=True)
    sources.reset()
    assert sources.status(0x1F) == 0x1F and not sources.line


def test_generated_phase5i_roms_are_legal_nrom128_images(
    tmp_path: Path,
) -> None:
    subprocess.run(
        [
            sys.executable,
            "scripts/generate_apu_cpu_phase5i_roms.py",
            "--output-dir",
            str(tmp_path),
        ],
        check=True,
    )
    game_a_image = (tmp_path / "phase5i_game_a.nes").read_bytes()
    game_b_image = (tmp_path / "phase5i_game_b.nes").read_bytes()
    assert len(game_a_image) == len(game_b_image) == PRG_SIZE + 16
    assert game_a_image[:16] == b"NES\x1a\x01\x00" + bytes(10)
    game_a = game_a_image[16:]
    reference = (tmp_path / "phase5i_rom_reference.txt").read_text()
    assert "irq_handler=9000" in reference and "nmi_handler=9200" in reference
    assert game_a[0x3FFC:0x4000] == bytes(
        (RESET & 0xFF, RESET >> 8, IRQ_HANDLER & 0xFF, IRQ_HANDLER >> 8)
    )
