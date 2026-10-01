#!/usr/bin/env python3
"""Generate original Phase 4F-G ROMs and software-originated MMIO traces."""

from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.generate_phase4b_fixtures import (  # noqa: E402
    Program,
    make_ines,
    put,
    set_vectors,
)
from software.nes_loader.ines import load_runtime_image  # noqa: E402
from software.nes_loader.loader import (  # noqa: E402
    LoadPlan,
    RuntimeLoaderTimeouts,
    execute_load_plan,
)
from software.nes_loader.mmio import RawMmio  # noqa: E402
from software.nes_loader.mmio_registers import (  # noqa: E402
    ERROR_CODE_MASK,
    ERROR_RESPONSE_FAILED,
    MMIO_CAPABILITIES,
    MMIO_MAGIC,
    MMIO_SPAN_BYTES,
    MMIO_VERSION,
    REG_CAPABILITIES,
    REG_ERROR,
    REG_MAGIC,
    REG_STATUS,
    REG_VERSION,
    STATUS_ACTIVATION_IN_PROGRESS,
    STATUS_IMAGE_VALID,
    STATUS_NES_HELD_RESET,
    STATUS_RUNTIME_ACTIVE,
)
from software.nes_loader.protocol import (  # noqa: E402
    LoaderCommand,
    LoaderErrorCode,
    RuntimeStatus,
    Target,
)
from software.nes_loader.transport import (  # noqa: E402
    MmioRuntimeLoaderTransport,
    RuntimeLoaderTransport,
    TransportProtocolError,
)
from verification.runtime_loader_mmio import (  # noqa: E402
    SimulatedRuntimeLoaderMmio,
)


PRG_128_BYTES = 16 * 1024
PRG_256_BYTES = 32 * 1024
CHR_BYTES = 8 * 1024
TIMEOUTS = RuntimeLoaderTimeouts(10.0, 10.0, 10.0)


def game_a_prg() -> bytes:
    """NROM-128 program exercising CPU, PPU, NMI, DMA, and controller paths."""

    prg = bytearray([0xEA] * PRG_128_BYTES)
    reset = Program(0x8000)
    reset.emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A)  # SEI; CLD; LDX #$ff; TXS
    for address, value in ((0x02, 0x42), (0x03, 0x4F), (0x04, 0x47)):
        reset.emit(0xA9, value, 0x85, address)
    reset.emit(0xA9, 0x00)
    for address in (0x10, 0x11, 0x12):
        reset.emit(0x85, address)
    reset.emit(0x8D, 0x00, 0x20, 0x8D, 0x01, 0x20)  # rendering/NMI off

    # Deterministic background palette.
    reset.emit(0xA9, 0x3F, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x00, 0x8D, 0x06, 0x20, 0xA2, 0x00)
    reset.label("palette")
    reset.emit(0xBD, 0x00, 0x82, 0x8D, 0x07, 0x20, 0xE8, 0xE0, 0x20)
    reset.branch(0xD0, "palette")

    # Fill one complete nametable with tile 1, including deterministic
    # attribute bytes. The unique tile comes only from the runtime CHR payload.
    reset.emit(0xA9, 0x20, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    reset.emit(0xA0, 0x04, 0xA2, 0x00, 0xA9, 0x01)
    reset.label("nametable")
    reset.emit(0x8D, 0x07, 0x20, 0xE8)
    reset.branch(0xD0, "nametable")
    reset.emit(0x88)
    reset.branch(0xD0, "nametable")

    # Prepare and execute one real OAM DMA from internal CPU RAM page $02.
    reset.emit(0xA2, 0x00, 0xA9, 0xFE)
    reset.label("dma_page")
    reset.emit(0x9D, 0x00, 0x02, 0xE8)
    reset.branch(0xD0, "dma_page")
    reset.emit(0xA9, 0x02, 0x8D, 0x14, 0x40)
    reset.emit(0xA9, 0xD1, 0x85, 0x12)  # proves execution resumed after DMA

    reset.emit(0xA9, 0x00, 0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20)
    reset.emit(0xA9, 0x80, 0x8D, 0x00, 0x20)  # NMI on
    reset.emit(0xA9, 0x0A, 0x8D, 0x01, 0x20)  # background on
    reset.label("controller")
    reset.emit(0xA9, 0x01, 0x8D, 0x16, 0x40)
    reset.emit(0xA9, 0x00, 0x8D, 0x16, 0x40)
    reset.emit(0xAD, 0x16, 0x40, 0x29, 0x01, 0x85, 0x11)
    reset.absolute(0x4C, "controller")
    put(prg, 0x8000, reset.resolve())

    nmi = Program(0x9000)
    nmi.emit(0x48, 0xE6, 0x10, 0x68, 0x40)  # PHA; INC $10; PLA; RTI
    put(prg, 0x9000, nmi.resolve())
    put(prg, 0x9100, bytes((0x40,)))  # defensive IRQ/BRK handler
    put(
        prg,
        0x8200,
        bytes((0x0F, 0x01, 0x21, 0x31) * 4 + (0x0F, 0x06, 0x16, 0x26) * 4),
    )
    set_vectors(prg, nmi=0x9000, reset=0x8000, irq=0x9100)
    return bytes(prg)


def game_a_chr() -> bytes:
    """Original tile data whose alternating bit planes are easy to identify."""

    data = bytearray(CHR_BYTES)
    for row in range(8):
        data[0x10 + row] = 0x55 if row % 2 == 0 else 0xAA
        data[0x18 + row] = 0x00
    return bytes(data)


def game_b_prg() -> bytes:
    """NROM-256 CHR-RAM program with distinct lower and upper PRG halves."""

    prg = bytearray([0xEA] * PRG_256_BYTES)
    prg[0x0000] = 0x3C  # value read through CPU $8000 from lower PRG half
    reset = Program(0xC000)
    reset.emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A)
    for address, value in ((0x02, 0x47), (0x03, 0x42), (0x04, 0x32)):
        reset.emit(0xA9, value, 0x85, address)
    reset.emit(0xAD, 0x00, 0x80, 0x85, 0x20)  # lower half sentinel
    reset.emit(0xAD, 0x00, 0xC2, 0x85, 0x21)  # upper half sentinel

    # The CPU writes runtime CHR-RAM through the real PPU port, then performs
    # the required buffered read sequence and publishes the result in $22.
    reset.emit(0xA9, 0x00, 0x8D, 0x00, 0x20, 0x8D, 0x01, 0x20)
    reset.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0x10, 0x8D, 0x06, 0x20)
    reset.emit(0xA9, 0xA6, 0x8D, 0x07, 0x20)
    # Re-select $0010 before each buffered read so the address increment does
    # not advance away from the synchronous CHR storage location. The final
    # read publishes the written byte after both existing read pipelines.
    for _ in range(4):
        reset.emit(0xA9, 0x00, 0x8D, 0x06, 0x20)
        reset.emit(0xA9, 0x10, 0x8D, 0x06, 0x20)
        reset.emit(0xAD, 0x07, 0x20)
    reset.emit(0x85, 0x22)
    reset.label("loop")
    reset.absolute(0x4C, "loop")
    put(prg, 0xC000, reset.resolve())
    put(prg, 0xC100, bytes((0x40,)))
    put(prg, 0xC200, bytes((0xC7,)))
    set_vectors(prg, nmi=0xC100, reset=0xC000, irq=0xC100)
    return bytes(prg)


class RecordingMmio(RawMmio):
    """Record software-visible writes while a faithful model services reads."""

    def __init__(self, endpoint: SimulatedRuntimeLoaderMmio) -> None:
        super().__init__(MMIO_SPAN_BYTES)
        self.endpoint = endpoint
        self.lines: list[str] = []
        self.enabled = True

    def read32(self, offset: int) -> int:
        return self.endpoint.read32(offset)

    def write32(self, offset: int, value: int) -> None:
        if self.enabled:
            self.lines.append(f"W {offset:02x} {value:08x}")
        self.endpoint.write32(offset, value)

    def close(self) -> None:
        self.endpoint.close()


class TracingTransport(RuntimeLoaderTransport):
    """Delegate to the production transport and retain semantic status polls."""

    def __init__(
        self, delegate: MmioRuntimeLoaderTransport, recorder: RecordingMmio
    ) -> None:
        self.delegate = delegate
        self.recorder = recorder

    def send(self, command: LoaderCommand, *, timeout_s: float) -> None:
        self.delegate.send(command, timeout_s=timeout_s)

    def read_status(self) -> RuntimeStatus:
        return self.delegate.read_status()

    def wait_for_image_valid(self, *, timeout_s: float) -> RuntimeStatus:
        status = self.delegate.wait_for_image_valid(timeout_s=timeout_s)
        mask = STATUS_IMAGE_VALID | STATUS_RUNTIME_ACTIVE | STATUS_NES_HELD_RESET
        expected = STATUS_IMAGE_VALID | STATUS_NES_HELD_RESET
        if status.runtime_active:
            expected |= STATUS_RUNTIME_ACTIVE
        self.recorder.lines.append(
            f"S {mask:08x} {expected:08x}"
        )
        return status

    def wait_for_active(self, *, timeout_s: float) -> RuntimeStatus:
        status = self.delegate.wait_for_active(timeout_s=timeout_s)
        mask = (
            STATUS_IMAGE_VALID
            | STATUS_RUNTIME_ACTIVE
            | STATUS_NES_HELD_RESET
            | STATUS_ACTIVATION_IN_PROGRESS
        )
        self.recorder.lines.append(
            f"S {mask:08x} {(STATUS_IMAGE_VALID | STATUS_RUNTIME_ACTIVE):08x}"
        )
        return status


def trace_preamble() -> list[str]:
    return [
        "# Phase 4F-G software-visible MMIO trace v1",
        "# R offset mask expected; W offset value; S status-mask expected",
        f"R {REG_MAGIC:02x} ffffffff {MMIO_MAGIC:08x}",
        f"R {REG_VERSION:02x} ffffffff {MMIO_VERSION:08x}",
        f"R {REG_CAPABILITIES:02x} ffffffff {MMIO_CAPABILITIES:08x}",
    ]


def create_transport() -> tuple[
    RecordingMmio, TracingTransport, MmioRuntimeLoaderTransport
]:
    endpoint = SimulatedRuntimeLoaderMmio(
        command_delay_reads=2,
        validation_delay_polls=2,
        activation_delay_polls=3,
    )
    recorder = RecordingMmio(endpoint)
    raw_transport = MmioRuntimeLoaderTransport(
        recorder,
        poll_interval_s=0.000001,
        sleep=lambda _seconds: None,
    )
    return recorder, TracingTransport(raw_transport, recorder), raw_transport


def write_valid_trace(
    rom: Path,
    trace: Path,
    context: tuple[RecordingMmio, TracingTransport, MmioRuntimeLoaderTransport]
    | None = None,
) -> dict[str, int | str | bool]:
    image = load_runtime_image(rom)
    plan = LoadPlan.from_image(image)
    recorder, transport, _raw = context or create_transport()
    recorder.lines.clear()
    recorder.enabled = True
    result = execute_load_plan(plan, transport, timeouts=TIMEOUTS)
    trace.write_text("\n".join(trace_preamble() + recorder.lines) + "\n")
    return {
        "rom": rom.name,
        "trace": trace.name,
        "nrom_mode": image.nrom_mode,
        "prg_bytes": result.prg_bytes_written,
        "chr_bytes": result.chr_bytes_written,
        "chr_is_ram": image.chr_is_ram,
        "commands_accepted": result.commands_accepted,
    }


def write_failed_replacement_trace(
    game_a: Path,
    trace: Path,
    context: tuple[RecordingMmio, TracingTransport, MmioRuntimeLoaderTransport]
    | None = None,
) -> dict[str, int]:
    """Generate a real MMIO sequence for an incomplete second image."""

    image = load_runtime_image(game_a)
    recorder, transport, raw_transport = context or create_transport()
    if context is None:
        recorder.enabled = False
        execute_load_plan(LoadPlan.from_image(image), transport, timeouts=TIMEOUTS)
    recorder.lines.clear()
    recorder.enabled = True

    replacement = load_runtime_image(game_a).manifest()
    raw_transport.send(LoaderCommand.begin(replacement), timeout_s=10.0)
    partial_count = 257
    for address, value in enumerate(image.prg_bytes[:partial_count]):
        raw_transport.send(
            LoaderCommand.write(Target.PRG, address, value), timeout_s=10.0
        )
    try:
        raw_transport.send(LoaderCommand.commit(), timeout_s=10.0)
    except TransportProtocolError as error:
        if LoaderErrorCode.PRG_INCOMPLETE.name not in str(error):
            raise
    else:
        raise AssertionError("incomplete replacement COMMIT unexpectedly succeeded")

    error_word = recorder.read32(REG_ERROR)
    expected_error = int(LoaderErrorCode.PRG_INCOMPLETE) | ERROR_RESPONSE_FAILED
    if error_word & (ERROR_CODE_MASK | ERROR_RESPONSE_FAILED) != expected_error:
        raise AssertionError(f"unexpected failed replacement error 0x{error_word:08x}")
    recorder.lines.append(
        f"R {REG_ERROR:02x} {(ERROR_CODE_MASK | ERROR_RESPONSE_FAILED):08x} "
        f"{expected_error:08x}"
    )
    mask = STATUS_IMAGE_VALID | STATUS_RUNTIME_ACTIVE | STATUS_NES_HELD_RESET
    recorder.lines.append(
        f"S {mask:08x} {(STATUS_RUNTIME_ACTIVE | STATUS_NES_HELD_RESET):08x}"
    )
    trace.write_text("\n".join(trace_preamble() + recorder.lines) + "\n")
    return {"prg_bytes": partial_count, "chr_bytes": 0}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT_DIRECTORY")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)

    game_a = output / "phase4fg_game_a_nrom128_chrrom.nes"
    game_b = output / "phase4fg_game_b_nrom256_chrram.nes"
    game_a.write_bytes(make_ines(game_a_prg(), game_a_chr(), vertical=False))
    game_b.write_bytes(make_ines(game_b_prg(), b"", vertical=True))

    context = create_transport()
    metadata = {
        "game_a": write_valid_trace(game_a, output / "game_a.mmio", context),
        "failed_replacement": write_failed_replacement_trace(
            game_a, output / "failed_replacement.mmio", context
        ),
        "game_b": write_valid_trace(game_b, output / "game_b.mmio", context),
    }
    (output / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n"
    )
    print(
        "Phase 4F-G fixtures: "
        "Game A PRG=16384 CHR=8192; failed PRG=257; "
        "Game B PRG=32768 CHR=0"
    )


if __name__ == "__main__":
    main()
