from __future__ import annotations

from io import StringIO
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import pytest

from software.nes_debug import backend as backend_module
from software.nes_debug.backend import (
    DiagnosticPermissionError,
    INJECTION_CODES,
    MalformedMmioReadError,
    MissingHardwareError,
    MmioDiagnosticBackend,
    OfflineDiagnosticBackend,
)
from software.nes_debug.cli import run
from software.nes_debug.client import (
    DiagnosticClient,
    UnsupportedDiagnosticInterface,
)
from software.nes_debug.model import (
    DiagnosticReferenceModel,
    FaultLatch,
    SnapshotModel,
    TraceBuffer,
    UNAVAILABLE_WORD,
    increment_u32,
)
from software.nes_debug.report import (
    collect_report,
    render_json,
    render_text,
    write_report,
)
from software.nes_debug import mmio_registers as regs


ROOT = Path(__file__).resolve().parents[2]


def test_generated_magic_version_and_register_contract() -> None:
    contract = json.loads(
        (ROOT / "config/diagnostic_mmio.json").read_text(encoding="utf-8")
    )
    assert regs.MMIO_MAGIC == int(contract["magic"], 0)
    assert regs.MMIO_VERSION == (
        contract["version_major"] << 16 | contract["version_minor"]
    )
    assert regs.REGISTER_OFFSETS == {
        name: int(value, 0) for name, value in contract["registers"].items()
    }
    assert len(set(regs.REGISTER_OFFSETS.values())) == len(regs.REGISTER_OFFSETS)
    assert all(
        offset % 4 == 0 and offset + 4 <= regs.MMIO_SPAN_BYTES
        for offset in regs.REGISTER_OFFSETS.values()
    )


def test_loader_aperture_isolation_and_qsys_decode() -> None:
    loader = json.loads(
        (ROOT / "config/runtime_loader_mmio.json").read_text(encoding="utf-8")
    )
    diagnostic = json.loads(
        (ROOT / "config/diagnostic_mmio.json").read_text(encoding="utf-8")
    )
    loader_start = int(loader["slave_offset"], 0)
    loader_end = loader_start + loader["span_bytes"]
    diagnostic_start = int(diagnostic["slave_offset"], 0)
    diagnostic_end = diagnostic_start + diagnostic["span_bytes"]
    assert loader_end <= diagnostic_start or diagnostic_end <= loader_start
    root = ET.parse(ROOT / "quartus/nes_hps_loader_system.qsys").getroot()
    connections = {
        connection.attrib["end"]: int(
            connection.find("./parameter[@name='baseAddress']").attrib["value"],
            0,
        )
        for connection in root.findall(
            "./connection[@start='hps_0.h2f_lw_axi_master']"
        )
    }
    assert connections["loader_mmio_bridge.s0"] == loader_start
    assert connections["diagnostic_mmio_bridge.s0"] == diagnostic_start


def test_snapshot_is_atomic_and_unavailable_is_explicit() -> None:
    model = SnapshotModel()
    model.set("counter", 7)
    model.set("instructions", None)
    model.capture()
    model.set("counter", 8)
    assert model.encoded("counter") == 7
    assert model.encoded("instructions") == UNAVAILABLE_WORD
    model.capture()
    assert model.encoded("counter") == 8


def test_counter_increment_and_rollover() -> None:
    model = DiagnosticReferenceModel()
    assert model.tick("cycles") == 1
    model.counters["cycles"] = 0xFFFF_FFFF
    assert model.tick("cycles") == 0
    assert increment_u32(0xFFFF_FFFE, 2) == 0


def test_sticky_fault_latch_and_explicit_clear() -> None:
    latch = FaultLatch()
    latch.observe(regs.FAULT_CODEC_INIT_NACK)
    latch.observe(regs.FAULT_AUDIO_FIFO_UNDERRUN)
    assert latch.flags == (
        regs.FAULT_BITS[regs.FAULT_CODEC_INIT_NACK]
        | regs.FAULT_BITS[regs.FAULT_AUDIO_FIFO_UNDERRUN]
    )
    latch.clear(regs.FAULT_BITS[regs.FAULT_CODEC_INIT_NACK])
    assert latch.flags == regs.FAULT_BITS[regs.FAULT_AUDIO_FIFO_UNDERRUN]
    latch.clear(0xFFFF_FFFF)
    assert latch.flags == 0
    assert latch.last_code == 0


def test_trace_arm_trigger_freeze_overflow_and_ordering() -> None:
    trace = TraceBuffer(depth=4)
    trace.add(0, regs.EVENT_RESET)
    assert trace.count == 0
    trace.arm()
    for index in range(6):
        trace.add(index, regs.EVENT_NMI, index)
    assert trace.count == 4
    assert trace.overflow == 2
    assert [event.payload for event in trace.ordered()] == [2, 3, 4, 5]
    trace.trigger()
    trace.add(7, regs.EVENT_IRQ)
    assert trace.triggered and trace.frozen and not trace.armed
    assert trace.count == 4
    trace.clear()
    trace.arm()
    trace.freeze()
    assert trace.frozen and not trace.armed


@pytest.mark.parametrize("name,code", INJECTION_CODES.items())
def test_all_deterministic_fault_injections(name: str, code: int) -> None:
    backend = OfflineDiagnosticBackend((name,))
    client = DiagnosticClient(backend)
    snapshot = client.snapshot()
    faults = client.faults(snapshot)
    assert faults == [{"code": code, "name": regs.FAULT_NAMES[code], "bit": code - 1}]
    assert snapshot["last_fault"] == code
    client.clear_faults()
    assert client.snapshot()["fault_flags"] == 0


def test_unsupported_interface_version() -> None:
    backend = OfflineDiagnosticBackend(("unsupported-version",))
    with pytest.raises(UnsupportedDiagnosticInterface):
        DiagnosticClient(backend).validate_interface()


def test_malformed_mmio_read() -> None:
    backend = OfflineDiagnosticBackend()
    with pytest.raises(MalformedMmioReadError):
        backend.read32(3)
    with pytest.raises(MalformedMmioReadError):
        backend.read32(regs.MMIO_SPAN_BYTES)


def test_missing_hardware_is_reported_without_devmem_access(tmp_path: Path) -> None:
    with pytest.raises(MissingHardwareError):
        MmioDiagnosticBackend.open(str(tmp_path / "missing-dev-mem"))


def test_permission_denial_is_structured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(backend_module.Path, "exists", lambda _self: True)

    def deny(*_args, **_kwargs):
        raise PermissionError("denied")

    monkeypatch.setattr(backend_module, "DevMemMmio", deny)
    with pytest.raises(DiagnosticPermissionError):
        MmioDiagnosticBackend.open("/dev/mem")


def test_trace_readout_reorders_wrapped_physical_entries() -> None:
    backend = OfflineDiagnosticBackend()
    backend.trace = [
        (12, regs.EVENT_IRQ, 12),
        (13, regs.EVENT_NMI, 13),
        (10, regs.EVENT_RESET, 10),
        (11, regs.EVENT_LOADER_ERROR, 11),
    ]
    # depth is 16 in hardware; use four valid entries without wrap.
    backend.words[regs.REG_TRACE_STATUS] = 4 << 3
    events = DiagnosticClient(backend).trace()
    assert [event["payload"] for event in events] == [12, 13, 10, 11]


def test_json_and_text_reports_label_offline_hardware_not_tested(
    tmp_path: Path,
) -> None:
    backend = OfflineDiagnosticBackend()
    report = collect_report(backend, DiagnosticClient(backend))
    json_text = render_json(report)
    text = render_text(report)
    decoded = json.loads(json_text)
    assert decoded["hardware_available"] is False
    assert set(decoded["hardware_status"].values()) == {"NOT TESTED"}
    assert "Physical hardware validation" not in text
    assert "NOT TESTED" in text
    assert "Toolchain:" in text
    assert "Observed registers:" in text
    assert "Interpreted status:" in text
    assert "Trace:" in text
    assert "magic: 0x4e455344" in text
    json_path = write_report(report, tmp_path, "json")
    text_path = write_report(report, tmp_path, "text")
    assert json.loads(json_path.read_text(encoding="utf-8"))["schema_version"] == 1
    assert "NES FPGA DIAGNOSTIC REPORT" in text_path.read_text(encoding="utf-8")


def test_reports_do_not_include_secrets(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GITHUB_TOKEN", "super-secret-token")
    backend = OfflineDiagnosticBackend()
    rendered = render_json(collect_report(backend, DiagnosticClient(backend)))
    assert "super-secret-token" not in rendered
    assert "GITHUB_TOKEN" not in rendered


def test_cli_status_fault_trace_and_exit_codes() -> None:
    output = StringIO()
    error = StringIO()
    assert run(["status"], stdout=output, stderr=error) == 0
    assert "Physical hardware: NOT TESTED" in output.getvalue()
    output = StringIO()
    assert run(
        ["faults", "--inject", "dma-timeout"],
        stdout=output,
        stderr=error,
    ) == 1
    assert "DMA_TRANSACTION_TIMEOUT" in output.getvalue()
    output = StringIO()
    assert run(["trace"], stdout=output, stderr=error) == 0
    assert "empty" in output.getvalue()
    error = StringIO()
    assert run(
        ["status", "--inject", "unsupported-version"],
        stdout=StringIO(),
        stderr=error,
    ) == 2
    assert "unsupported diagnostic interface" in error.getvalue()


def test_cli_doctor_and_report_output_directory(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    commands: list[list[str]] = []

    def record_check(command: list[str], *, timeout_s: float = 60.0) -> bool:
        commands.append(command)
        if Path(command[0]).name == "test.sh":
            assert timeout_s == 3600.0
        return True

    monkeypatch.setattr("software.nes_debug.cli._run_check", record_check)
    output = StringIO()
    assert run(["doctor", "--full"], stdout=output, stderr=StringIO()) == 0
    doctor = output.getvalue()
    assert "DE1-SoC: NOT TESTED" in doctor
    assert "CPU: PASS" in doctor
    assert Path(commands[-1][0]).is_absolute()
    assert Path(commands[-1][0]).name == "test.sh"
    output = StringIO()
    assert run(
        ["report", "--format", "json", "--output-dir", str(tmp_path)],
        stdout=output,
        stderr=StringIO(),
    ) == 0
    path = Path(output.getvalue().strip())
    assert path.parent == tmp_path
    assert json.loads(path.read_text(encoding="utf-8"))["backend_type"] == "offline-simulation"


def test_cli_real_backend_missing_hardware(tmp_path: Path) -> None:
    error = StringIO()
    code = run(
        ["status", "--backend", "mmio", "--dev-mem", str(tmp_path / "none")],
        stdout=StringIO(),
        stderr=error,
    )
    assert code == 2
    assert "not present" in error.getvalue()
