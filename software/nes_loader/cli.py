"""Command-line interface for Phase 4F-E inspection and mock loading."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import TextIO

from .ines import INESError, ImageInspection, inspect_ines, load_runtime_image
from .loader import (
    LoadPlan,
    RuntimeLoadError,
    RuntimeLoaderTimeouts,
    execute_load_plan,
)
from .mmio import DevMemMmio
from .mmio_registers import MMIO_PHYSICAL_BASE, MMIO_SPAN_BYTES
from .transport import (
    MmioRuntimeLoaderTransport,
    MockRuntimeLoaderTransport,
    TransportError,
)


def _yes_no(value: bool) -> str:
    return "Yes" if value else "No"


def _inspection_lines(path: Path, inspection: ImageInspection) -> list[str]:
    header = inspection.header
    if header.four_screen:
        mirroring = "Four-screen"
    else:
        mirroring = "Vertical" if header.vertical_mirroring else "Horizontal"
    chr_type = "RAM" if header.chr_banks == 0 else "ROM"
    lines = [
        f"File:          {path}",
        f"Format:        {inspection.format_name}",
        f"Mapper:        {header.mapper}",
        f"PRG ROM:       {header.prg_bytes // 1024} KiB",
        f"CHR ROM:       {header.chr_bytes // 1024} KiB",
        f"CHR type:      {chr_type}",
        f"Mirroring:     {mirroring}",
        f"Trainer:       {_yes_no(header.trainer)}",
        f"Battery:       {_yes_no(header.battery)}",
        f"Supported:     {_yes_no(inspection.supported)}",
    ]
    if inspection.reason is not None:
        lines.append(f"Reason:        {inspection.reason}")
    return lines


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nes-loader",
        description="Inspect or load a Mapper-0 iNES image at runtime",
    )
    subparsers = parser.add_subparsers(dest="action", required=True)
    inspect_parser = subparsers.add_parser("inspect", help="inspect iNES metadata")
    inspect_parser.add_argument("file", type=Path)

    load_parser = subparsers.add_parser("load", help="validate and load an image")
    load_parser.add_argument("file", type=Path)
    load_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="execute against the deterministic mock transport",
    )
    load_parser.add_argument("--command-timeout", type=float, default=1.0)
    load_parser.add_argument("--validation-timeout", type=float, default=1.0)
    load_parser.add_argument("--activation-timeout", type=float, default=1.0)
    load_parser.add_argument(
        "--dev-mem",
        default="/dev/mem",
        help="physical-memory device used by the HPS MMIO backend",
    )
    return parser


def run(
    argv: list[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.action == "inspect":
            inspection = inspect_ines(args.file.read_bytes())
            print("\n".join(_inspection_lines(args.file, inspection)), file=stdout)
            return 0 if inspection.supported else 2

        image = load_runtime_image(args.file)
        plan = LoadPlan.from_image(image)
        if args.dry_run:
            transport = MockRuntimeLoaderTransport(
                validation_delay_polls=2,
                activation_delay_polls=4,
            )
            result = execute_load_plan(
                plan,
                transport,
                timeouts=RuntimeLoaderTimeouts(
                    command_s=args.command_timeout,
                    image_validation_s=args.validation_timeout,
                    activation_s=args.activation_timeout,
                ),
            )
        else:
            with DevMemMmio(
                MMIO_PHYSICAL_BASE,
                MMIO_SPAN_BYTES,
                device=args.dev_mem,
            ) as raw_mmio:
                transport = MmioRuntimeLoaderTransport(raw_mmio)
                result = execute_load_plan(
                    plan,
                    transport,
                    timeouts=RuntimeLoaderTimeouts(
                        command_s=args.command_timeout,
                        image_validation_s=args.validation_timeout,
                        activation_s=args.activation_timeout,
                    ),
                )
        print("Parsed image: OK", file=stdout)
        print(f"Mapper {result.manifest.mapper}: supported", file=stdout)
        print("Manifest: valid", file=stdout)
        print(f"PRG transfer: {result.prg_bytes_written} bytes", file=stdout)
        print(f"CHR transfer: {result.chr_bytes_written} bytes", file=stdout)
        print("Image validation: OK", file=stdout)
        print("Activation: OK", file=stdout)
        print(
            "Dry run completed successfully"
            if args.dry_run
            else "Runtime load completed successfully",
            file=stdout,
        )
        return 0
    except (OSError, INESError, RuntimeLoadError, TransportError, ValueError) as error:
        print(f"nes-loader: {args.file}: {error}", file=stderr)
        return 2
