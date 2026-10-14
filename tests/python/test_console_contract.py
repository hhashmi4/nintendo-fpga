"""Software-only contract tests. RTL coverage is in the console benches."""

import json
from pathlib import Path

import pytest

from software.nes_console.protocol import (
    Command, State, Source, Status, Result, allowed, request_word,
    MAGIC, VERSION, REG_BRIDGE, REG_COMMAND, REG_RESPONSE,
    REG_RESULT, REG_COMPLETED,
)
from software.nes_console.transport import ConsoleTransport, ConsoleError
from software.nes_console.session import load_game
from software.nes_loader.mmio import FakeMmio
from software.nes_loader.ines import INESError
from software.nes_loader.loader import RuntimeLoadError
from software.nes_loader.transport import MockRuntimeLoaderTransport
from verification.runtime_loader_fixtures import make_ines


@pytest.mark.parametrize("state", list(State))
@pytest.mark.parametrize("command", list(Command))
def test_transition_preconditions(state, command):
    # Explicit independent table, including transitional states.
    states = {
        Command.STATUS: set(range(8)), Command.MENU: set(range(8)),
        Command.DEVELOPER: set(range(8)), Command.REPORT_ERROR: set(range(8)),
        Command.LAUNCH: {1, 7}, Command.PREPARE_LOAD: {1, 6, 7},
    }
    assert allowed(command, state) == (int(state) in states[command])


@pytest.mark.parametrize("epoch", [0, 1, 0xFFFF])
@pytest.mark.parametrize("command", list(Command))
def test_epoch_encoding(epoch, command):
    assert request_word(command, epoch) == epoch * 65536 + int(command)


@pytest.mark.parametrize("epoch", [-1, 65536])
def test_invalid_epoch(epoch):
    with pytest.raises(ValueError):
        request_word(Command.LAUNCH, epoch)


def test_decode_independent_wire_example():
    status = Status.decode(0x1234DBA7)
    assert status == Status(State.DEVELOPER, Source.DEVELOPER,
                            Source.DEVELOPER, True, True, 2, 13, 0x1234)


def scripted_mmio(responses):
    """A response script exercises transport; it does not emulate hardware."""
    pending = iter(responses)
    requests = []
    mmio = FakeMmio(32)
    mmio.words[0:2] = [MAGIC, VERSION]
    mmio.words[REG_BRIDGE // 4] = 1

    def write(offset, value):
        assert offset == REG_COMMAND
        requests.append(value)
        result, status = next(pending)
        mmio.words[REG_RESULT // 4] = result
        mmio.words[REG_RESPONSE // 4] = status
        mmio.words[REG_COMPLETED // 4] += 1

    mmio.write_hook = write
    return mmio, requests


def test_launch_uses_observed_epoch_and_waits_for_game_ack():
    mmio, requests = scripted_mmio([(0, 0x120101), (0, 0x120101),
                                  (0, 0x130103), (0, 0x130154)])
    console = ConsoleTransport(mmio)
    assert console.launch().state == State.GAME
    assert requests == [0, 0x120002, 0, 0]


@pytest.mark.parametrize("result", [Result.STALE, Result.INVALID, Result.UNAVAILABLE])
def test_rejection_is_not_retried(result):
    mmio, requests = scripted_mmio([(0, 0x10001), (result, 0x20001)])
    with pytest.raises(ConsoleError, match=result.name):
        ConsoleTransport(mmio).request(Command.LAUNCH)
    assert requests == [0, 0x10002]


def test_invalid_launch_does_not_write_ownership_command():
    mmio, requests = scripted_mmio([(0, 0x10002)])
    with pytest.raises(ConsoleError, match="invalid"):
        ConsoleTransport(mmio).launch()
    assert requests == [0]


def test_interrupted_hps_request_times_out():
    mmio = FakeMmio(32)
    mmio.words[0:2] = [MAGIC, VERSION]
    times = iter([0, 1, 2, 3])
    with pytest.raises(ConsoleError, match="ownership is unconfirmed"):
        ConsoleTransport(mmio, timeout_s=1, clock=lambda: next(times),
                         sleep=lambda _: None).status()


def test_reset_counter_is_not_mistaken_for_completion():
    mmio, _ = scripted_mmio([])
    mmio.words[REG_COMPLETED // 4] = 19
    mmio.write_hook = lambda *_: mmio.words.__setitem__(REG_COMPLETED // 4, 0)
    with pytest.raises(ConsoleError, match="reset or another issuer"):
        ConsoleTransport(mmio).status()


def test_superseded_launch_is_not_reported_successful():
    mmio, requests = scripted_mmio([(0, 0x10001), (0, 0x10001), (0, 0x30054)])
    with pytest.raises(ConsoleError, match="superseded"):
        ConsoleTransport(mmio).launch()
    assert requests == [0, 0x10002, 0]


def test_mmio_legacy_contracts_preserved():
    loader = json.loads(Path("config/runtime_loader_mmio.json").read_text())
    diagnostic = json.loads(Path("config/diagnostic_mmio.json").read_text())
    assert (loader["version_major"], loader["version_minor"], loader["span_bytes"]) == (1, 0, 64)
    assert (diagnostic["version_major"], diagnostic["version_minor"], diagnostic["span_bytes"]) == (1, 3, 512)


def test_console_contract_matches_software():
    from software.nes_console import protocol
    contract = json.loads(Path("config/console_mmio.json").read_text())
    assert int(contract["hps_lightweight_window_base"], 0) + int(contract["slave_offset"], 0) == protocol.PHYSICAL_BASE
    assert contract["span_bytes"] == protocol.SPAN_BYTES
    assert int(contract["magic"], 0) == protocol.MAGIC
    for name, offset in contract["registers"].items():
        assert getattr(protocol, "REG_" + name) == int(offset, 0)
    for key, enum in [("states", State), ("commands", Command),
                      ("results", Result), ("sources", Source)]:
        assert contract[key] == {item.name: item.value for item in enum}


class RecordingConsole:
    def __init__(self):
        self.calls = []

    def menu(self):
        self.calls.append("menu acknowledged")

    def request(self, command):
        self.calls.append(command)

    def wait_state(self, state):
        self.calls.append(state)

    def launch(self):
        self.calls.append("game acknowledged")


def test_existing_library_load_sequence(tmp_path):
    (tmp_path / "owned.nes").write_bytes(make_ines())
    console = RecordingConsole()
    result = load_game(console, MockRuntimeLoaderTransport(), "owned.nes", library=tmp_path)
    assert result.status.runtime_active
    assert console.calls == ["menu acknowledged", Command.PREPARE_LOAD,
                             State.MENU, "game acknowledged"]


@pytest.mark.parametrize("failure_index", [0, 1, 20])
def test_interrupted_load_reports_error_and_does_not_launch(tmp_path, failure_index):
    path = tmp_path / "owned.nes"
    path.write_bytes(make_ines())
    console = RecordingConsole()
    loader = MockRuntimeLoaderTransport(fail_at_command=failure_index)
    with pytest.raises(RuntimeLoadError, match="failed"):
        load_game(console, loader, path)
    assert console.calls == ["menu acknowledged", Command.PREPARE_LOAD, Command.REPORT_ERROR]
    assert len(loader.commands) == failure_index
    if failure_index > 1:
        assert len(loader.prg) > 0  # No fictitious rollback after partial writes.


@pytest.mark.parametrize("contents", [b"bad", make_ines(flags6=0x20)])
def test_invalid_or_unsupported_selection_never_begins_load(tmp_path, contents):
    path = tmp_path / "bad.nes"
    path.write_bytes(contents)
    console = RecordingConsole()
    with pytest.raises(INESError):
        load_game(console, None, path)
    assert console.calls == [Command.REPORT_ERROR]
