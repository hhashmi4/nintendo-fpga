"""Secret-minimal JSON and text report generation."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
from typing import Any

from .backend import DiagnosticBackend
from .client import DiagnosticClient
from . import mmio_registers as regs


ROOT = Path(__file__).resolve().parents[2]


def _command(args: list[str]) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            args,
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
            cwd=ROOT,
        )
    except (OSError, subprocess.SubprocessError):
        return False, "unavailable"
    output = (result.stdout or result.stderr).strip().splitlines()
    return True, " ".join(output[:2]) if output else "available"


def repository_identity() -> dict[str, str]:
    _, commit = _command(["git", "rev-parse", "HEAD"])
    _, branch = _command(["git", "branch", "--show-current"])
    return {"commit": commit, "branch": branch}


def toolchain_versions() -> dict[str, str]:
    _, verilator = _command(["verilator", "--version"])
    quartus_ok, quartus = _command(["quartus_sh", "--version"])
    quartus_match = re.search(r"Version ([^ ]+)", quartus)
    quartus_executable = shutil.which("quartus_sh")
    qsys_candidate = (
        Path(quartus_executable).parent.parent / "sopc_builder/bin/qsys-generate"
        if quartus_executable is not None
        else None
    )
    if quartus_ok and quartus_match and qsys_candidate is not None and qsys_candidate.exists():
        platform_designer = (
            f"{quartus_match.group(1)} (bundled Platform Designer/Qsys)"
        )
    else:
        platform_designer = "unavailable"
    return {
        "python": platform.python_version(),
        "verilator": verilator,
        "quartus": quartus,
        "platform_designer": platform_designer,
    }


def collect_report(backend: DiagnosticBackend, client: DiagnosticClient) -> dict[str, Any]:
    snapshot = client.snapshot()
    faults = client.faults(snapshot)
    interface_version = snapshot["version"]
    hardware_available = backend.hardware_available
    warnings: list[str] = []
    if not hardware_available:
        warnings.append("Physical DE1-SoC hardware was not accessed; hardware checks are NOT TESTED.")
    if faults:
        warnings.append(f"{len(faults)} sticky diagnostic fault(s) are present.")
    unavailable = ["cpu_instruction_retirement", "physical_hdmi_transmitter"]
    if not hardware_available:
        unavailable.extend([
            "de1_soc_board",
            "hps_bridge",
            "fpga_clocks",
            "audio_codec",
            "vga_output",
        ])
    return {
        "schema_version": 1,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "repository": repository_identity(),
        "toolchain": toolchain_versions(),
        "diagnostic_interface": {
            "major": interface_version >> 16,
            "minor": interface_version & 0xFFFF,
            "build_id": f"0x{snapshot['build_id']:08x}",
        },
        "backend_type": backend.backend_type,
        "hardware_available": hardware_available,
        "hardware_status": {
            "de1_soc": "OBSERVED" if hardware_available else "NOT TESTED",
            "hps_bridge": "OBSERVED" if hardware_available else "NOT TESTED",
            "fpga_clocks": "OBSERVED" if hardware_available else "NOT TESTED",
            "audio_codec": "OBSERVED" if hardware_available else "NOT TESTED",
            "vga": "OBSERVED" if hardware_available else "NOT TESTED",
            # The stock DE1-SoC has no HDMI transmitter. This remains
            # unobserved even when the existing VGA board is available.
            "hdmi_transmitter": "NOT TESTED",
        },
        "observed_registers": {
            name: f"0x{value:08x}" for name, value in sorted(snapshot.items())
        },
        "interpreted_status": client.interpreted_status(snapshot),
        "faults": faults,
        "trace": client.trace(snapshot),
        "warnings": warnings,
        "unavailable_measurements": unavailable,
    }


def render_json(report: dict[str, Any]) -> str:
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def render_text(report: dict[str, Any]) -> str:
    repository = report["repository"]
    interface = report["diagnostic_interface"]
    lines = [
        "NES FPGA DIAGNOSTIC REPORT",
        "",
        f"Timestamp: {report['timestamp']}",
        f"Commit: {repository['commit']}",
        f"Branch: {repository['branch']}",
        f"Backend: {report['backend_type']}",
        f"Hardware available: {'YES' if report['hardware_available'] else 'NO'}",
        f"Interface: {interface['major']}.{interface['minor']} ({interface['build_id']})",
        "",
        "Toolchain:",
    ]
    for name, version in report["toolchain"].items():
        lines.append(f"  {name}: {version}")
    lines.extend([
        "",
        "Hardware:",
    ])
    for name, status in report["hardware_status"].items():
        lines.append(f"  {name}: {status}")
    lines.extend(["", "Observed registers:"])
    for name, value in report["observed_registers"].items():
        lines.append(f"  {name}: {value}")
    lines.extend(["", "Interpreted status:"])
    for group, values in report["interpreted_status"].items():
        rendered_values = ", ".join(
            f"{name}={str(value).lower() if isinstance(value, bool) else value}"
            for name, value in values.items()
        )
        lines.append(f"  {group}: {rendered_values}")
    lines.extend(["", "Faults:"])
    if report["faults"]:
        for fault in report["faults"]:
            lines.append(f"  {fault['code']}: {fault['name']}")
    else:
        lines.append("  None observed")
    lines.extend(["", "Trace:"])
    if report["trace"]:
        for event in report["trace"]:
            lines.append(
                f"  {event['order']:02d} t={event['timestamp']:08x} "
                f"{event['name']} payload=0x{event['payload']:06x}"
            )
    else:
        lines.append("  Empty")
    lines.extend(["", "Unavailable measurements:"])
    for measurement in report["unavailable_measurements"]:
        lines.append(f"  {measurement}")
    if report["warnings"]:
        lines.extend(["", "Warnings:"])
        lines.extend(f"  {warning}" for warning in report["warnings"])
    return "\n".join(lines) + "\n"


def write_report(
    report: dict[str, Any], output_dir: Path, output_format: str
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    suffix = "json" if output_format == "json" else "txt"
    path = output_dir / f"nes-diagnostics-{stamp}.{suffix}"
    content = render_json(report) if output_format == "json" else render_text(report)
    path.write_text(content, encoding="utf-8")
    return path
