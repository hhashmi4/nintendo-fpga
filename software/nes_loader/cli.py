"""Command-line interface for Phase 4F-E inspection and mock loading."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
from typing import TextIO

from .ines import INESError, ImageInspection, inspect_ines, load_runtime_image
from .library import GameLibrary, GameLibraryError, LibraryEntry
from .loader import (
    LoadPlan,
    LoadResult,
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


def _add_library_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--library",
        type=Path,
        default=os.environ.get("NES_LIBRARY_ROOT"),
        help="game-library root (default: NES_LIBRARY_ROOT)",
    )


def _add_runtime_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="execute against the deterministic mock transport",
    )
    parser.add_argument("--command-timeout", type=float, default=1.0)
    parser.add_argument("--validation-timeout", type=float, default=1.0)
    parser.add_argument("--activation-timeout", type=float, default=1.0)
    parser.add_argument(
        "--dev-mem",
        default="/dev/mem",
        help="physical-memory device used by the HPS MMIO backend",
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nes-loader",
        description="Inspect, discover, or load Mapper-0 iNES images at runtime",
    )
    subparsers = parser.add_subparsers(dest="action", required=True)
    inspect_parser = subparsers.add_parser("inspect", help="inspect iNES metadata")
    inspect_parser.add_argument("file", type=Path)

    load_parser = subparsers.add_parser("load", help="validate and load an image")
    load_parser.add_argument("file", type=Path)
    _add_runtime_arguments(load_parser)

    list_parser = subparsers.add_parser(
        "list", help="list supported, unsupported, and invalid library games"
    )
    _add_library_argument(list_parser)

    info_parser = subparsers.add_parser("info", help="inspect one library game")
    info_parser.add_argument("game", help="stable library-relative game ID")
    _add_library_argument(info_parser)

    library_load_parser = subparsers.add_parser(
        "load-library", help="select, validate, and load one library game"
    )
    library_load_parser.add_argument("game", help="stable library-relative game ID")
    _add_library_argument(library_load_parser)
    _add_runtime_arguments(library_load_parser)
    return parser


def _configured_library(path: Path | str | None) -> GameLibrary:
    if path is None:
        raise GameLibraryError(
            "library root is not configured; use --library PATH or set "
            "NES_LIBRARY_ROOT"
        )
    return GameLibrary(path)


def _entry_lines(entry: LibraryEntry, index: int | None = None) -> list[str]:
    prefix = f"{index}. " if index is not None else ""
    lines = [f"{prefix}{entry.display_name}", f"   ID: {entry.game_id}"]
    if entry.header is not None:
        details = [
            f"Mapper {entry.mapper}",
            f"{entry.prg_size // 1024} KiB PRG",
        ]
        if entry.chr_type is not None and entry.chr_type.value == "RAM":
            details.append("CHR-RAM")
        else:
            details.append(f"{entry.chr_size // 1024} KiB CHR-ROM")
        if entry.nrom_mode is not None:
            details.append(entry.nrom_mode)
        if entry.mirroring_name is not None:
            details.append(f"{entry.mirroring_name} mirroring")
        lines.append(f"   {' · '.join(details)}")
    if not entry.valid:
        lines.append(f"   Invalid: {entry.reason}")
    elif entry.supported:
        lines.append("   Supported")
    else:
        lines.append(f"   Unsupported: {entry.reason}")
    return lines


def _print_library(entries: tuple[LibraryEntry, ...], stdout: TextIO) -> None:
    print("Games", file=stdout)
    if not entries:
        print("", file=stdout)
        print("No .nes games found in the configured library.", file=stdout)
        return
    for index, entry in enumerate(entries, start=1):
        print("", file=stdout)
        print("\n".join(_entry_lines(entry, index)), file=stdout)


def _timeouts(args: argparse.Namespace) -> RuntimeLoaderTimeouts:
    return RuntimeLoaderTimeouts(
        command_s=args.command_timeout,
        image_validation_s=args.validation_timeout,
        activation_s=args.activation_timeout,
    )


def _load_image(image, args: argparse.Namespace) -> LoadResult:
    plan = LoadPlan.from_image(image)
    if args.dry_run:
        transport = MockRuntimeLoaderTransport(
            validation_delay_polls=2,
            activation_delay_polls=4,
        )
        return execute_load_plan(plan, transport, timeouts=_timeouts(args))
    with DevMemMmio(
        MMIO_PHYSICAL_BASE,
        MMIO_SPAN_BYTES,
        device=args.dev_mem,
    ) as raw_mmio:
        transport = MmioRuntimeLoaderTransport(raw_mmio)
        return execute_load_plan(plan, transport, timeouts=_timeouts(args))


def _print_load_result(
    result: LoadResult, *, dry_run: bool, stdout: TextIO
) -> None:
    print("Parsed image: OK", file=stdout)
    print(f"Mapper {result.manifest.mapper}: supported", file=stdout)
    print("Manifest: valid", file=stdout)
    print(f"PRG transfer: {result.prg_bytes_written} bytes", file=stdout)
    print(f"CHR transfer: {result.chr_bytes_written} bytes", file=stdout)
    print("Image validation: OK", file=stdout)
    print("Activation: OK", file=stdout)
    print(
        "Dry run completed successfully"
        if dry_run
        else "Runtime load completed successfully",
        file=stdout,
    )


def run(
    argv: list[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    args = _parser().parse_args(argv)
    subject = getattr(args, "file", getattr(args, "game", "library"))
    try:
        if args.action == "inspect":
            inspection = inspect_ines(args.file.read_bytes())
            print("\n".join(_inspection_lines(args.file, inspection)), file=stdout)
            return 0 if inspection.supported else 2

        if args.action == "list":
            _print_library(_configured_library(args.library).scan(), stdout)
            return 0

        if args.action == "info":
            entry = _configured_library(args.library).select(args.game)
            print("\n".join(_entry_lines(entry)), file=stdout)
            return 0 if entry.supported else 2

        if args.action == "load-library":
            entry, image = _configured_library(args.library).load(args.game)
            print(f"Selected: {entry.display_name} ({entry.game_id})", file=stdout)
        else:
            image = load_runtime_image(args.file)

        result = _load_image(image, args)
        _print_load_result(result, dry_run=args.dry_run, stdout=stdout)
        return 0
    except (
        OSError,
        INESError,
        GameLibraryError,
        RuntimeLoadError,
        TransportError,
        ValueError,
    ) as error:
        print(f"nes-loader: {subject}: {error}", file=stderr)
        return 2
