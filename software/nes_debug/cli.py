"""Repository-local ``nes-debug`` command."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
from typing import TextIO

from .backend import (
    DiagnosticBackendError,
    INJECTION_CODES,
    MmioDiagnosticBackend,
    OfflineDiagnosticBackend,
)
from .client import DiagnosticClient
from .report import (
    collect_report,
    render_json,
    render_text,
    repository_identity,
    write_report,
)


ROOT = Path(__file__).resolve().parents[2]
INJECTION_CHOICES = tuple(INJECTION_CODES) + ("unsupported-version",)


def _add_backend_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--backend",
        choices=("offline", "mmio"),
        default="offline",
        help="offline is the safe default; mmio explicitly opts into /dev/mem",
    )
    parser.add_argument("--dev-mem", default="/dev/mem")
    parser.add_argument("--timeout", type=float, default=0.25)
    parser.add_argument(
        "--inject",
        action="append",
        choices=INJECTION_CHOICES,
        default=[],
        help="deterministic offline fault injection (repeatable)",
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nes-debug", description="Nintendo FPGA Phase 5M diagnostics"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    doctor = subparsers.add_parser("doctor", help="check diagnostic readiness")
    doctor.add_argument("--full", action="store_true")
    _add_backend_arguments(doctor)
    status = subparsers.add_parser("status", help="show a coherent status snapshot")
    status.add_argument("--json", action="store_true")
    _add_backend_arguments(status)
    faults = subparsers.add_parser("faults", help="show sticky fault codes")
    faults.add_argument("--json", action="store_true")
    faults.add_argument("--clear", action="store_true")
    _add_backend_arguments(faults)
    trace = subparsers.add_parser("trace", help="read the bounded event trace")
    trace.add_argument("--json", action="store_true")
    _add_backend_arguments(trace)
    report = subparsers.add_parser("report", help="create a structured report")
    report.add_argument("--format", choices=("json", "text"), default="text")
    report.add_argument("--output-dir", type=Path)
    _add_backend_arguments(report)
    return parser


def _backend(args: argparse.Namespace):
    if args.backend == "offline":
        return OfflineDiagnosticBackend(tuple(args.inject))
    if args.inject:
        raise DiagnosticBackendError("fault injection is available only offline")
    return MmioDiagnosticBackend.open(args.dev_mem)


def _run_check(command: list[str], *, timeout_s: float = 60.0) -> bool:
    try:
        subprocess.run(
            command,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout_s,
            cwd=ROOT,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return True


def _doctor(
    args: argparse.Namespace,
    client: DiagnosticClient,
    *,
    stdout: TextIO,
) -> int:
    identity = repository_identity()
    checks = {
        "Python": _run_check(
            [sys.executable, "scripts/generate_diagnostic_mmio_defs.py", "--check"]
        ),
        "Verilator": _run_check(["verilator", "--version"]),
    }
    simulation = {name: "NOT RUN" for name in ("CPU", "PPU", "APU", "Audio", "Loader")}
    evidence = "lightweight interface checks"
    if args.full:
        regression_ok = _run_check(
            [str(ROOT / "scripts" / "test.sh")], timeout_s=3600.0
        )
        result = "PASS" if regression_ok else "FAIL"
        simulation = {name: result for name in simulation}
        evidence = "current scripts/test.sh complete regression invocation"
    client.validate_interface()
    offline = not client.backend.hardware_available
    print("NES FPGA DIAGNOSTICS", file=stdout)
    print("", file=stdout)
    print("Repository:", file=stdout)
    print(f"  Commit: {identity['commit']}", file=stdout)
    print(f"  Branch: {identity['branch']}", file=stdout)
    print("", file=stdout)
    print("Software:", file=stdout)
    for name, passed in checks.items():
        print(f"  {name}: {'PASS' if passed else 'FAIL'}", file=stdout)
    print("", file=stdout)
    print("Hardware:", file=stdout)
    hardware_status = "NOT TESTED" if offline else "OBSERVED"
    for name in ("DE1-SoC", "HPS bridge", "FPGA clocks", "Audio codec", "VGA"):
        print(f"  {name}: {hardware_status}", file=stdout)
    print("", file=stdout)
    print("Simulation:", file=stdout)
    for name, status in simulation.items():
        print(f"  {name}: {status}", file=stdout)
    print(f"  Evidence: {evidence}", file=stdout)
    print("", file=stdout)
    print("Summary:", file=stdout)
    if all(checks.values()) and all(value != "FAIL" for value in simulation.values()):
        print("  Software checks passed.", file=stdout)
    else:
        print("  One or more software checks failed.", file=stdout)
    if offline:
        print("  Physical hardware validation pending.", file=stdout)
    return 0 if all(checks.values()) and all(
        value != "FAIL" for value in simulation.values()
    ) else 1


def _status(client: DiagnosticClient, json_output: bool, stdout: TextIO) -> int:
    snapshot = client.snapshot()
    interpreted = client.interpreted_status(snapshot)
    if json_output:
        print(json.dumps({"registers": snapshot, "status": interpreted}, indent=2), file=stdout)
    else:
        print("NES FPGA STATUS", file=stdout)
        print(f"Backend: {client.backend.backend_type}", file=stdout)
        print(f"Snapshot: {snapshot['snapshot_sequence']}", file=stdout)
        print(f"CPU PC: 0x{interpreted['cpu']['pc']:04x}", file=stdout)
        print(f"PPU frames: {interpreted['ppu']['frames']}", file=stdout)
        print(f"VGA frames: {interpreted['video']['frames']}", file=stdout)
        print(f"Fault flags: 0x{snapshot['fault_flags']:08x}", file=stdout)
        if not client.backend.hardware_available:
            print("Physical hardware: NOT TESTED", file=stdout)
    return 0


def _faults(args: argparse.Namespace, client: DiagnosticClient, stdout: TextIO) -> int:
    if args.clear:
        client.clear_faults()
    snapshot = client.snapshot()
    faults = client.faults(snapshot)
    if args.json:
        print(json.dumps(faults, indent=2), file=stdout)
    elif not faults:
        print("No diagnostic faults observed.", file=stdout)
    else:
        for fault in faults:
            print(f"{fault['code']:02d} {fault['name']}", file=stdout)
    return 1 if faults else 0


def _trace(client: DiagnosticClient, json_output: bool, stdout: TextIO) -> int:
    snapshot = client.snapshot()
    events = client.trace(snapshot)
    if json_output:
        print(json.dumps(events, indent=2), file=stdout)
    elif not events:
        print("Diagnostic trace is empty.", file=stdout)
    else:
        for event in events:
            print(
                f"{event['order']:02d} t={event['timestamp']:08x} "
                f"{event['name']} payload=0x{event['payload']:06x}",
                file=stdout,
            )
    return 0


def run(
    argv: list[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    args = _parser().parse_args(argv)
    try:
        with _backend(args) as backend:
            client = DiagnosticClient(backend, timeout_s=args.timeout)
            if args.command == "doctor":
                return _doctor(args, client, stdout=stdout)
            if args.command == "status":
                return _status(client, args.json, stdout)
            if args.command == "faults":
                return _faults(args, client, stdout)
            if args.command == "trace":
                return _trace(client, args.json, stdout)
            report = collect_report(backend, client)
            if args.output_dir is not None:
                path = write_report(report, args.output_dir, args.format)
                print(path, file=stdout)
            else:
                renderer = render_json if args.format == "json" else render_text
                print(renderer(report), end="", file=stdout)
            return 0
    except (DiagnosticBackendError, ValueError) as exc:
        print(f"nes-debug: {exc}", file=stderr)
        return 2


def main() -> None:
    raise SystemExit(run())


if __name__ == "__main__":
    main()
