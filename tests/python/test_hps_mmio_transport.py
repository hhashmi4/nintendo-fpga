from __future__ import annotations

import json
import mmap
from pathlib import Path
import re
import struct

import pytest

from software.nes_loader.ines import parse_ines, validate_runtime_image
from software.nes_loader.loader import LoadPlan, execute_load_plan
from software.nes_loader.mmio import DevMemMmio, FakeMmio
from software.nes_loader.mmio_registers import (
    ERROR_RESPONSE_FAILED,
    ERROR_STATE_MASK,
    ERROR_STATE_SHIFT,
    MMIO_CAPABILITIES,
    MMIO_MAGIC,
    MMIO_PHYSICAL_BASE,
    MMIO_SPAN_BYTES,
    MMIO_VERSION,
    REG_COMMAND,
    REG_ERROR,
    REG_STATUS,
    STATUS_COMMAND_PENDING,
    STATUS_SUBMIT_REJECTED,
)
from software.nes_loader.protocol import LoaderCommand, LoaderState, Target
from software.nes_loader.transport import (
    MmioRuntimeLoaderTransport,
    TransportIdentityError,
    TransportProtocolError,
)
from verification.runtime_loader_fixtures import make_ines
from verification.runtime_loader_mmio import SimulatedRuntimeLoaderMmio


def chr_ram_plan() -> LoadPlan:
    image = validate_runtime_image(parse_ines(make_ines(chr_banks=0)))
    return LoadPlan.from_image(image)


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"magic": 0}, "magic mismatch"),
        ({"version": 0x00020000}, "major version 2"),
        ({"capabilities": MMIO_CAPABILITIES & ~1}, "capabilities"),
    ],
)
def test_mmio_transport_rejects_incompatible_endpoint(kwargs, message):
    with pytest.raises(TransportIdentityError, match=message):
        MmioRuntimeLoaderTransport(SimulatedRuntimeLoaderMmio(**kwargs))


def test_production_transport_executes_full_plan_against_mmio_model():
    mmio = SimulatedRuntimeLoaderMmio(
        command_delay_reads=2,
        validation_delay_polls=2,
        activation_delay_polls=3,
    )
    result = execute_load_plan(chr_ram_plan(), MmioRuntimeLoaderTransport(mmio))
    assert result.status.runtime_active
    assert bytes(mmio.endpoint.prg) == chr_ram_plan().prg_bytes
    assert mmio.endpoint.chr == b""
    assert mmio.submissions == result.commands_accepted
    assert mmio.completed_count == result.commands_accepted


def test_typed_fpga_error_survives_mmio_boundary_and_begin_recovers():
    plan = chr_ram_plan()
    mmio = SimulatedRuntimeLoaderMmio()
    transport = MmioRuntimeLoaderTransport(mmio)
    transport.send(LoaderCommand.begin(plan.manifest), timeout_s=0.1)
    with pytest.raises(TransportProtocolError, match="unexpected address"):
        transport.send(LoaderCommand.write(Target.PRG, 1, 0x55), timeout_s=0.1)
    transport.send(LoaderCommand.begin(plan.manifest), timeout_s=0.1)


def test_error_response_flag_and_resulting_state_fields_do_not_overlap():
    plan = chr_ram_plan()
    mmio = SimulatedRuntimeLoaderMmio()
    transport = MmioRuntimeLoaderTransport(mmio)
    transport.send(LoaderCommand.begin(plan.manifest), timeout_s=0.1)
    error_word = mmio.read32(REG_ERROR)
    assert not error_word & ERROR_RESPONSE_FAILED
    assert (error_word & ERROR_STATE_MASK) >> ERROR_STATE_SHIFT == LoaderState.LOADING


def test_repeated_reads_do_not_duplicate_and_busy_write_cannot_overwrite():
    plan = chr_ram_plan()
    mmio = SimulatedRuntimeLoaderMmio(command_delay_reads=4)
    transport = MmioRuntimeLoaderTransport(mmio)
    transport.mmio.write32(0x18, 0)
    transport.mmio.write32(0x1C, 0)
    transport.mmio.write32(0x20, 0)
    manifest = transport._manifest_word(plan.manifest)
    transport.mmio.write32(0x24, manifest)
    transport.mmio.write32(0x28, plan.manifest.prg_bytes)
    transport.mmio.write32(0x2C, plan.manifest.chr_bytes)
    transport.mmio.write32(REG_COMMAND, 0)
    for _ in range(2):
        assert transport.mmio.read32(REG_STATUS) & STATUS_COMMAND_PENDING
        transport.mmio.read32(REG_COMMAND)
    transport.mmio.write32(REG_COMMAND, 1)
    assert transport.mmio.read32(REG_STATUS) & STATUS_SUBMIT_REJECTED
    assert mmio.submissions == 1


def test_transport_reports_and_clears_sticky_submission_rejection():
    mmio = SimulatedRuntimeLoaderMmio()
    transport = MmioRuntimeLoaderTransport(mmio)
    mmio.write32(REG_COMMAND, 4)
    with pytest.raises(TransportProtocolError, match="rejected MMIO submission"):
        transport.read_status()
    assert not mmio.read32(REG_STATUS) & STATUS_SUBMIT_REJECTED


def _sv_constant(source: str, name: str) -> int:
    match = re.search(rf"{name}\s*=\s*\d+'h([0-9a-fA-F]+)", source)
    assert match is not None
    return int(match.group(1), 16)


def test_generated_software_rtl_qsys_address_contract_is_one_source():
    contract = json.loads(
        Path("config/runtime_loader_mmio.json").read_text(encoding="utf-8")
    )
    sv = Path("rtl/loader/nes_runtime_loader_mmio_pkg.sv").read_text(
        encoding="utf-8"
    )
    tcl = Path("quartus/nes_runtime_loader_mmio_map.tcl").read_text(
        encoding="utf-8"
    )
    assert MMIO_MAGIC == int(contract["magic"], 0)
    assert MMIO_VERSION == (
        contract["version_major"] << 16 | contract["version_minor"]
    )
    assert MMIO_SPAN_BYTES == contract["span_bytes"]
    assert MMIO_PHYSICAL_BASE == (
        int(contract["hps_lightweight_window_base"], 0)
        + int(contract["slave_offset"], 0)
    )
    assert _sv_constant(sv, "MMIO_MAGIC") == MMIO_MAGIC
    assert f"0x{int(contract['slave_offset'], 0):08x}" in tcl


def test_fake_mmio_alignment_bounds_and_cleanup():
    mmio = FakeMmio(MMIO_SPAN_BYTES)
    mmio.write32(0, 0x12345678)
    assert mmio.read32(0) == 0x12345678
    with pytest.raises(ValueError, match="offset"):
        mmio.read32(2)
    with pytest.raises(ValueError, match="offset"):
        mmio.write32(MMIO_SPAN_BYTES, 0)
    mmio.close()
    with pytest.raises(ValueError, match="closed"):
        mmio.read32(0)


def test_devmem_mmio_page_alignment_minimal_span_and_cleanup(tmp_path: Path):
    device = tmp_path / "physical-memory"
    device.write_bytes(bytes(2 * mmap.PAGESIZE))
    physical_base = mmap.PAGESIZE - 16
    with DevMemMmio(
        physical_base,
        MMIO_SPAN_BYTES,
        device=str(device),
    ) as mmio:
        mmio.write32(0, 0x89ABCDEF)
        mmio.write32(MMIO_SPAN_BYTES - 4, 0x12345678)
        assert mmio.read32(0) == 0x89ABCDEF
        assert mmio.read32(MMIO_SPAN_BYTES - 4) == 0x12345678
    contents = device.read_bytes()
    assert struct.unpack_from("<I", contents, physical_base)[0] == 0x89ABCDEF
    assert (
        struct.unpack_from("<I", contents, physical_base + MMIO_SPAN_BYTES - 4)[0]
        == 0x12345678
    )
