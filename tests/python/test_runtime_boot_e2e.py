from __future__ import annotations

from pathlib import Path

import pytest

from scripts.generate_phase4b_fixtures import make_ines
from scripts.generate_phase4fg_runtime_boot import game_a_chr, game_a_prg, game_b_prg
from software.nes_loader.ines import INESError, load_runtime_image
from software.nes_loader.loader import LoadPlan, RuntimeLoadError, execute_load_plan
from software.nes_loader.mmio import RawMmio
from software.nes_loader.mmio_registers import MMIO_SPAN_BYTES, REG_COMMAND
from software.nes_loader.protocol import Command
from software.nes_loader.transport import MmioRuntimeLoaderTransport, TransportError
from verification.runtime_loader_mmio import SimulatedRuntimeLoaderMmio


class CountingMmio(RawMmio):
    def __init__(self, endpoint: SimulatedRuntimeLoaderMmio) -> None:
        super().__init__(MMIO_SPAN_BYTES)
        self.endpoint = endpoint
        self.writes: list[tuple[int, int]] = []

    def read32(self, offset: int) -> int:
        return self.endpoint.read32(offset)

    def write32(self, offset: int, value: int) -> None:
        self.writes.append((offset, value))
        self.endpoint.write32(offset, value)

    def close(self) -> None:
        self.endpoint.close()


class FailingMmio(CountingMmio):
    def __init__(self, endpoint: SimulatedRuntimeLoaderMmio, fail_at: int) -> None:
        super().__init__(endpoint)
        self.fail_at = fail_at

    def write32(self, offset: int, value: int) -> None:
        if len(self.writes) == self.fail_at:
            raise TransportError("injected MMIO write failure")
        super().write32(offset, value)


def write(path: Path, payload: bytes) -> Path:
    path.write_bytes(payload)
    return path


def test_original_runtime_roms_parse_into_required_load_plans(tmp_path: Path):
    game_a = load_runtime_image(
        write(tmp_path / "a.nes", make_ines(game_a_prg(), game_a_chr(), vertical=False))
    )
    game_b = load_runtime_image(
        write(tmp_path / "b.nes", make_ines(game_b_prg(), b"", vertical=True))
    )

    plan_a = LoadPlan.from_image(game_a)
    plan_b = LoadPlan.from_image(game_b)
    assert (game_a.nrom_mode, len(plan_a.prg_bytes), len(plan_a.chr_bytes)) == (
        "NROM-128",
        16384,
        8192,
    )
    assert not plan_a.manifest.chr_is_ram
    assert (game_b.nrom_mode, len(plan_b.prg_bytes), len(plan_b.chr_bytes)) == (
        "NROM-256",
        32768,
        0,
    )
    assert plan_b.manifest.chr_is_ram
    assert plan_a.prg_bytes[0x3FFC:0x4000] == bytes((0x00, 0x80, 0x00, 0x91))
    assert plan_b.prg_bytes[0x7FFC:0x8000] == bytes((0x00, 0xC0, 0x00, 0xC1))


def malformed_images() -> list[tuple[str, bytes]]:
    valid = bytearray(make_ines(game_a_prg(), game_a_chr(), vertical=False))
    wrong_magic = bytearray(valid)
    wrong_magic[:4] = b"BAD!"
    mapper = bytearray(valid)
    mapper[6] |= 0x10
    trainer = bytearray(valid)
    trainer[6] |= 0x04
    trainer[16:16] = bytes(512)
    nes2 = bytearray(valid)
    nes2[7] |= 0x08
    return [
        ("wrong_magic", bytes(wrong_magic)),
        ("mapper_1", bytes(mapper)),
        ("unsupported_prg", make_ines(bytes(3 * 16384), b"", vertical=False)),
        ("unsupported_chr", make_ines(game_a_prg(), bytes(2 * 8192), vertical=False)),
        ("trainer", bytes(trainer)),
        ("nes2", bytes(nes2)),
        ("truncated", bytes(valid[:-1])),
    ]


@pytest.mark.parametrize(("name", "payload"), malformed_images())
def test_malformed_rom_is_rejected_before_any_mmio_write(
    tmp_path: Path, name: str, payload: bytes
):
    raw = CountingMmio(SimulatedRuntimeLoaderMmio())
    with pytest.raises(INESError):
        image = load_runtime_image(write(tmp_path / f"{name}.nes", payload))
        execute_load_plan(LoadPlan.from_image(image), MmioRuntimeLoaderTransport(raw))
    assert raw.writes == []


def test_transport_failure_stops_before_activate(tmp_path: Path):
    image = load_runtime_image(
        write(tmp_path / "a.nes", make_ines(game_a_prg(), game_a_chr(), vertical=False))
    )
    raw = FailingMmio(SimulatedRuntimeLoaderMmio(), fail_at=40)
    with pytest.raises(RuntimeLoadError, match="injected MMIO write failure"):
        execute_load_plan(LoadPlan.from_image(image), MmioRuntimeLoaderTransport(raw))
    command_values = [value for offset, value in raw.writes if offset == REG_COMMAND]
    assert int(Command.ACTIVATE) not in command_values
