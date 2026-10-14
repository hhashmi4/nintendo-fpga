"""Phase 7A support and pre-MMIO rejection contracts, independent of RTL."""

from dataclasses import replace
from io import StringIO
import json
from pathlib import Path

import pytest

from software.nes_loader.cli import run
from software.nes_loader.ines import (
    INESFormatError, UnsupportedINESImage, parse_ines, validate_runtime_image,
)
from software.nes_loader.loader import LoadPlan, RuntimeLoadError, execute_load_plan
from software.nes_loader.protocol import (
    SUPPORTED_MAPPERS, LoaderErrorCode, Manifest, Mirroring, manifest_error,
)
from software.nes_loader.transport import MmioRuntimeLoaderTransport
from verification.runtime_loader_fixtures import make_ines
from verification.runtime_loader_mmio import SimulatedRuntimeLoaderMmio


def image(prg=1, chr_banks=1, vertical=False):
    return validate_runtime_image(parse_ines(make_ines(
        prg_banks=prg, chr_banks=chr_banks, flags6=int(vertical),
    )))


def test_only_nrom_is_supported_for_all_classic_mapper_ids():
    assert SUPPORTED_MAPPERS == {0}
    for mapper in range(256):
        manifest = Manifest(mapper, 16384, 8192, False, Mirroring.HORIZONTAL)
        expected = LoaderErrorCode.NONE if mapper == 0 else LoaderErrorCode.UNSUPPORTED_MAPPER
        assert manifest_error(manifest) == expected
        payload = make_ines(flags6=(mapper % 16) * 16, flags7=(mapper // 16) * 16)
        parsed = parse_ines(payload)
        assert parsed.header.mapper == mapper
        if mapper:
            with pytest.raises(UnsupportedINESImage, match=f"Mapper {mapper} "):
                validate_runtime_image(parsed)
        else:
            assert validate_runtime_image(parsed).mapper == 0


@pytest.mark.parametrize("prg", [1, 2])
@pytest.mark.parametrize("chr_banks", [0, 1])
@pytest.mark.parametrize("vertical", [False, True])
def test_manifest_and_wire_format_preserve_nrom_units(prg, chr_banks, vertical):
    cartridge = image(prg, chr_banks, vertical)
    manifest = cartridge.manifest()
    assert manifest.prg_bytes == prg * 16384
    assert manifest.chr_bytes == chr_banks * 8192
    assert manifest.chr_is_ram == (chr_banks == 0)
    assert int(manifest.mirroring) == (0 if vertical else 1)
    # Independent literal MMIO layout: valid bit 0, RAM bit 1, mirror bits 3:2.
    expected_word = 1 + (2 if chr_banks == 0 else 0) + (0 if vertical else 4)
    assert MmioRuntimeLoaderTransport._manifest_word(manifest) == expected_word


@pytest.mark.parametrize("mapper", [1, 2, 3, 4, 16, 255])
def test_invalid_plan_cannot_touch_an_active_mmio_cartridge(mapper):
    plan = LoadPlan.from_image(image(chr_banks=0))
    mmio = SimulatedRuntimeLoaderMmio()
    transport = MmioRuntimeLoaderTransport(mmio)
    execute_load_plan(plan, transport)
    before = (mmio.submissions, bytes(mmio.endpoint.prg),
              bytes(mmio.endpoint.chr), transport.read_status())
    bad = replace(plan, manifest=replace(plan.manifest, mapper=mapper))
    with pytest.raises(RuntimeLoadError, match="preflight.*UNSUPPORTED_MAPPER"):
        execute_load_plan(bad, transport)
    after = (mmio.submissions, bytes(mmio.endpoint.prg),
             bytes(mmio.endpoint.chr), transport.read_status())
    assert after == before


@pytest.mark.parametrize("change", [
    {"prg_bytes": 0}, {"prg_bytes": 16383}, {"prg_bytes": 65536},
    {"chr_bytes": 0}, {"chr_bytes": 8193}, {"chr_is_ram": True},
    {"mirroring": 2}, {"mirroring": 3},
])
def test_invalid_manifest_is_rejected_without_transport_calls(change):
    plan = LoadPlan.from_image(image())
    # None deliberately has no transport methods. Preflight must reject first.
    with pytest.raises(RuntimeLoadError, match="preflight"):
        execute_load_plan(replace(plan, manifest=replace(plan.manifest, **change)), None)


@pytest.mark.parametrize("part", ["prg_bytes", "chr_bytes"])
@pytest.mark.parametrize("delta", [-1, 1])
def test_payload_size_mismatch_is_rejected_before_begin(part, delta):
    plan = LoadPlan.from_image(image())
    data = getattr(plan, part)
    data = data[:-1] if delta < 0 else data + b"\x00"
    with pytest.raises(RuntimeLoadError, match="payload lengths"):
        execute_load_plan(replace(plan, **{part: data}), None)


@pytest.mark.parametrize("change", [
    {"mapper": 0.0}, {"prg_bytes": 16384.0}, {"chr_bytes": 8192.0},
    {"chr_is_ram": 2}, {"mirroring": 1.0}, {"mapper": False},
])
def test_unserializable_manifest_cannot_start_a_transaction(change):
    plan = LoadPlan.from_image(image())
    with pytest.raises(RuntimeLoadError, match="manifest field types"):
        execute_load_plan(replace(plan, manifest=replace(plan.manifest, **change)), None)


@pytest.mark.parametrize("payload", ["x" * 16384, [0] * 16384],
                         ids=["text", "integer-list"])
def test_nonbyte_payload_cannot_fail_after_begin(payload):
    plan = LoadPlan.from_image(image())
    with pytest.raises(RuntimeLoadError, match="immutable bytes"):
        execute_load_plan(replace(plan, prg_bytes=payload), None)


@pytest.mark.parametrize("cut", [0, 3, 15, 16, 16399, 16400, 24591])
def test_truncated_ines_is_rejected(cut):
    with pytest.raises(INESFormatError):
        parse_ines(make_ines()[:cut])


@pytest.mark.parametrize("mapper", [1, 2, 3, 4, 255])
def test_cli_rejects_future_mappers_before_opening_transport(tmp_path, mapper):
    path = tmp_path / "unsupported.nes"
    path.write_bytes(make_ines(flags6=(mapper % 16) * 16, flags7=(mapper // 16) * 16))
    stderr = StringIO()
    # This device must never be opened; the error must describe the mapper.
    assert run(["load", str(path), "--dev-mem", str(tmp_path / "absent")],
               stdout=StringIO(), stderr=stderr) == 2
    assert f"Mapper {mapper}" in stderr.getvalue()


def test_repeated_replacement_through_production_mmio_transport():
    mmio = SimulatedRuntimeLoaderMmio(command_delay_reads=1)
    transport = MmioRuntimeLoaderTransport(mmio)
    count = 0
    for prg, chr_banks in [(1, 1), (2, 0), (1, 0), (2, 1), (1, 1)]:
        plan = LoadPlan.from_image(image(prg, chr_banks))
        result = execute_load_plan(plan, transport)
        count += result.commands_accepted
        assert result.status.runtime_active and not result.status.nes_hold_reset
        assert mmio.endpoint.read_status().active_manifest == plan.manifest
        assert bytes(mmio.endpoint.prg) == plan.prg_bytes
        assert bytes(mmio.endpoint.chr) == plan.chr_bytes
    assert mmio.submissions == mmio.completed_count == count


def test_both_mmio_contracts_retain_their_independent_versions_and_addresses():
    root = Path(__file__).resolve().parents[2]
    loader = json.loads((root / "config/runtime_loader_mmio.json").read_text())
    diagnostic = json.loads((root / "config/diagnostic_mmio.json").read_text())
    assert (loader["version_major"], loader["version_minor"]) == (1, 0)
    assert (diagnostic["version_major"], diagnostic["version_minor"]) == (1, 3)
    assert loader["slave_offset"] == "0x00000000"
    assert diagnostic["slave_offset"] == "0x00001000"
    assert loader["registers"]["MANIFEST"] == "0x24"
    assert loader["registers"]["MANIFEST_PRG_BYTES"] == "0x28"
    assert loader["registers"]["MANIFEST_CHR_BYTES"] == "0x2c"
