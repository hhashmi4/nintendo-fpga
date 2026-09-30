from __future__ import annotations

from io import StringIO
from pathlib import Path
import re

import pytest

import software.nes_loader.cli as loader_cli
from software.nes_loader.cli import run
from software.nes_loader.ines import (
    CHRType,
    INESFormatError,
    UnsupportedINESImage,
    inspect_ines,
    load_runtime_image,
    parse_ines,
    validate_runtime_image,
)
from software.nes_loader.loader import LoadPlan
from software.nes_loader.protocol import (
    CHR_LAST_ADDRESS,
    CHR_ROM_BYTES,
    MAPPER_0,
    PRG_LAST_ADDRESS,
    PRG_NROM128_BYTES,
    PRG_NROM256_BYTES,
    Command,
    LoaderCommand,
    LoaderErrorCode,
    LoaderState,
    Mirroring,
    Target,
)
from verification.runtime_loader_fixtures import (
    make_ines,
    valid_runtime_images,
    write_valid_runtime_images,
)


@pytest.mark.parametrize(
    ("name", "prg_size", "chr_type", "mirroring"),
    [
        (
            "nrom128_chrrom_horizontal.nes",
            PRG_NROM128_BYTES,
            CHRType.ROM,
            Mirroring.HORIZONTAL,
        ),
        (
            "nrom128_chrrom_vertical.nes",
            PRG_NROM128_BYTES,
            CHRType.ROM,
            Mirroring.VERTICAL,
        ),
        (
            "nrom256_chrrom_horizontal.nes",
            PRG_NROM256_BYTES,
            CHRType.ROM,
            Mirroring.HORIZONTAL,
        ),
        (
            "nrom128_chrram_vertical.nes",
            PRG_NROM128_BYTES,
            CHRType.RAM,
            Mirroring.VERTICAL,
        ),
    ],
)
def test_generated_supported_images(name, prg_size, chr_type, mirroring):
    parsed = parse_ines(valid_runtime_images()[name])
    image = validate_runtime_image(parsed)
    assert image.mapper == MAPPER_0
    assert image.prg_size == prg_size
    assert image.chr_type is chr_type
    assert image.chr_size == (0 if chr_type is CHRType.RAM else CHR_ROM_BYTES)
    assert image.mirroring is mirroring
    assert image.manifest().prg_bytes == prg_size


def test_fixture_generation_is_deterministic(tmp_path: Path):
    first = write_valid_runtime_images(tmp_path / "first")
    second = write_valid_runtime_images(tmp_path / "second")
    assert [path.name for path in first] == [path.name for path in second]
    assert [path.read_bytes() for path in first] == [
        path.read_bytes() for path in second
    ]


def test_trainer_boundary_is_parsed_then_runtime_rejected():
    parsed = parse_ines(make_ines(trainer=True))
    assert len(parsed.trainer_bytes) == 512
    assert parsed.prg_bytes[0] == (1 * 7 + 1)
    with pytest.raises(UnsupportedINESImage, match="trainers"):
        validate_runtime_image(parsed)


@pytest.mark.parametrize(
    ("data", "message"),
    [
        (b"", "16-byte"),
        (b"NES\x1a", "16-byte"),
        (b"BAD!" + bytes(12), "magic"),
        (make_ines()[:-1], "truncated"),
        (make_ines(trailing=b"\x00"), "trailing"),
    ],
)
def test_malformed_and_boundary_errors(data, message):
    with pytest.raises(INESFormatError, match=message):
        parse_ines(data)


@pytest.mark.parametrize(
    ("image", "message"),
    [
        (make_ines(flags6=0x10), "Mapper 1"),
        (make_ines(flags7=0x20), "Mapper 32"),
        (make_ines(prg_banks=0), "0 PRG banks"),
        (make_ines(prg_banks=3), "3 PRG banks"),
        (make_ines(chr_banks=2), "2 CHR banks"),
        (make_ines(flags6=0x08), "four-screen"),
        (make_ines(flags6=0x02), "battery-backed"),
        (make_ines(flags7=0x01), "VS System"),
    ],
)
def test_well_formed_but_unsupported_classic_images(image, message):
    with pytest.raises(UnsupportedINESImage, match=message):
        validate_runtime_image(parse_ines(image))


def test_nes2_is_detected_before_classic_payload_interpretation():
    data = make_ines(flags7=0x08)
    with pytest.raises(UnsupportedINESImage, match="NES 2.0"):
        parse_ines(data)
    inspection = inspect_ines(data)
    assert inspection.format_name == "NES 2.0"
    assert not inspection.supported
    assert inspection.parsed is None


def test_reserved_header_fields_are_rejected():
    image = bytearray(make_ines())
    image[12] = 1
    with pytest.raises(INESFormatError, match="bytes 12-15"):
        parse_ines(bytes(image))

    image = bytearray(make_ines())
    image[7] = 0x04
    with pytest.raises(INESFormatError, match="format bits"):
        parse_ines(bytes(image))


def test_nrom128_payload_is_not_duplicated():
    image = validate_runtime_image(parse_ines(make_ines(prg_banks=1)))
    assert len(image.prg_bytes) == PRG_NROM128_BYTES
    assert image.nrom_mode == "NROM-128"


def test_chr_ram_has_zero_transfer_payload():
    image = validate_runtime_image(parse_ines(make_ines(chr_banks=0)))
    assert image.chr_is_ram
    assert image.chr_bytes == b""
    assert image.manifest().chr_bytes == 0


def test_load_plan_is_lazy_and_has_exact_boundaries():
    image = validate_runtime_image(parse_ines(make_ines()))
    plan = LoadPlan.from_image(image)
    iterator = plan.iter_transfer_commands()
    begin = next(iterator)
    first_prg = next(iterator)
    assert begin.command is Command.BEGIN and begin.manifest == image.manifest()
    assert first_prg == LoaderCommand.write(Target.PRG, 0, image.prg_bytes[0])
    commands = list(plan.iter_transfer_commands())
    assert len(commands) == 2 + PRG_NROM128_BYTES + CHR_ROM_BYTES
    assert commands[PRG_NROM128_BYTES].address == PRG_NROM128_BYTES - 1
    assert commands[PRG_NROM128_BYTES + 1].target is Target.CHR
    assert commands[-2].address == CHR_ROM_BYTES - 1
    assert commands[-1].command is Command.COMMIT


def _rtl_value(source: str, name: str) -> int:
    match = re.search(
        rf"{name}\s*=\s*\d+'(?P<radix>[dh])(?P<value>[0-9a-fA-F]+)",
        source,
    )
    assert match is not None
    base = 16 if match.group("radix") == "h" else 10
    return int(match.group("value"), base)


def test_software_protocol_constants_match_rtl_package():
    source = Path("rtl/loader/nes_runtime_loader_pkg.sv").read_text(encoding="utf-8")
    assert _rtl_value(source, "LOADER_PRG_NROM128_BYTES") == PRG_NROM128_BYTES
    assert _rtl_value(source, "LOADER_PRG_NROM256_BYTES") == PRG_NROM256_BYTES
    assert _rtl_value(source, "LOADER_CHR_ROM_BYTES") == CHR_ROM_BYTES
    assert _rtl_value(source, "LOADER_PRG_LAST_ADDRESS") == PRG_LAST_ADDRESS
    assert _rtl_value(source, "LOADER_CHR_LAST_ADDRESS") == CHR_LAST_ADDRESS
    assert _rtl_value(source, "LOADER_MIRROR_VERTICAL") == int(Mirroring.VERTICAL)
    assert _rtl_value(source, "LOADER_MIRROR_HORIZONTAL") == int(Mirroring.HORIZONTAL)

    for member in Command:
        rtl_name = "RESERVED" if member is Command.ACTIVATE else member.name
        assert _rtl_value(source, f"LOADER_COMMAND_{rtl_name}") == int(member)
    for member in Target:
        assert _rtl_value(source, f"LOADER_TARGET_{member.name}") == int(member)
    for member in LoaderState:
        assert _rtl_value(source, f"LOADER_STATE_{member.name}") == int(member)
    for member in LoaderErrorCode:
        assert _rtl_value(source, f"LOADER_ERROR_{member.name}") == int(member)


def test_inspect_cli_reports_supported_and_unsupported(tmp_path: Path):
    supported = tmp_path / "supported.nes"
    supported.write_bytes(make_ines(flags6=0x01))
    stdout = StringIO()
    assert run(["inspect", str(supported)], stdout=stdout, stderr=StringIO()) == 0
    report = stdout.getvalue()
    assert "Format:        iNES 1.0" in report
    assert "Mapper:        0" in report
    assert "PRG ROM:       16 KiB" in report
    assert "CHR ROM:       8 KiB" in report
    assert "Mirroring:     Vertical" in report
    assert "Supported:     Yes" in report

    unsupported = tmp_path / "mapper2.nes"
    unsupported.write_bytes(make_ines(flags6=0x20))
    stdout = StringIO()
    assert run(["inspect", str(unsupported)], stdout=stdout, stderr=StringIO()) == 2
    report = stdout.getvalue()
    assert "Mapper:        2" in report
    assert "Supported:     No" in report
    assert "Reason:        Mapper 2 is not supported" in report


def test_load_cli_dry_run_and_real_mmio_error(tmp_path: Path):
    path = tmp_path / "owned.nes"
    path.write_bytes(make_ines(chr_banks=0))
    stdout = StringIO()
    assert run(["load", str(path), "--dry-run"], stdout=stdout, stderr=StringIO()) == 0
    report = stdout.getvalue()
    assert "PRG transfer: 16384 bytes" in report
    assert "CHR transfer: 0 bytes" in report
    assert "Image validation: OK" in report
    assert "Activation: OK" in report

    stderr = StringIO()
    missing_device = tmp_path / "missing-dev-mem"
    assert (
        run(
            ["load", str(path), "--dev-mem", str(missing_device)],
            stdout=StringIO(),
            stderr=stderr,
        )
        == 2
    )
    assert str(missing_device) in stderr.getvalue()


def test_load_cli_reports_incompatible_fpga_without_traceback(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    path = tmp_path / "owned.nes"
    path.write_bytes(make_ines(chr_banks=0))
    device = tmp_path / "fake-dev-mem"
    device.write_bytes(bytes(loader_cli.MMIO_SPAN_BYTES))
    monkeypatch.setattr(loader_cli, "MMIO_PHYSICAL_BASE", 0)

    stderr = StringIO()
    assert (
        run(
            ["load", str(path), "--dev-mem", str(device)],
            stdout=StringIO(),
            stderr=stderr,
        )
        == 2
    )
    assert "FPGA loader bridge magic mismatch" in stderr.getvalue()


def test_load_runtime_image_rejects_before_transport_boundary(tmp_path: Path):
    path = tmp_path / "bad.nes"
    path.write_bytes(make_ines(flags7=0x30))
    with pytest.raises(UnsupportedINESImage, match="Mapper 48"):
        load_runtime_image(path)
