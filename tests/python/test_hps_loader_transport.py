from __future__ import annotations

import pytest

from software.nes_loader.ines import validate_runtime_image, parse_ines
from software.nes_loader.loader import (
    LoadPlan,
    RuntimeLoadError,
    RuntimeLoaderTimeouts,
    execute_load_plan,
)
from software.nes_loader.protocol import (
    CHR_ROM_BYTES,
    PRG_NROM128_BYTES,
    Command,
    LoaderCommand,
    LoaderErrorCode,
    LoaderState,
    Target,
)
from software.nes_loader.transport import (
    MockRuntimeLoaderTransport,
    TransportProtocolError,
)
from verification.runtime_loader_fixtures import make_ines


def plan(*, chr_ram: bool = False) -> LoadPlan:
    image = validate_runtime_image(
        parse_ines(make_ines(chr_banks=0 if chr_ram else 1))
    )
    return LoadPlan.from_image(image)


def test_mock_executes_and_records_exact_chr_rom_sequence():
    load_plan = plan()
    transport = MockRuntimeLoaderTransport(
        validation_delay_polls=2,
        activation_delay_polls=4,
    )
    result = execute_load_plan(load_plan, transport)
    assert result.prg_bytes_written == PRG_NROM128_BYTES
    assert result.chr_bytes_written == CHR_ROM_BYTES
    assert result.commands_accepted == load_plan.transfer_command_count + 1
    assert len(transport.commands) == result.commands_accepted
    assert transport.commands[0].command is Command.BEGIN
    assert transport.commands[1].target is Target.PRG
    assert transport.commands[1].address == 0
    assert transport.commands[PRG_NROM128_BYTES].address == PRG_NROM128_BYTES - 1
    first_chr = transport.commands[PRG_NROM128_BYTES + 1]
    assert first_chr.target is Target.CHR and first_chr.address == 0
    assert transport.commands[-2].command is Command.COMMIT
    assert transport.commands[-1].command is Command.ACTIVATE
    assert bytes(transport.prg) == load_plan.prg_bytes
    assert bytes(transport.chr) == load_plan.chr_bytes
    assert result.status.runtime_active
    assert not result.status.activation_in_progress
    assert not result.status.nes_hold_reset
    assert transport.image_valid_waits == 1 and transport.active_waits == 1


def test_chr_ram_plan_emits_no_chr_writes():
    load_plan = plan(chr_ram=True)
    transport = MockRuntimeLoaderTransport(activation_delay_polls=0)
    execute_load_plan(load_plan, transport)
    writes = [item for item in transport.commands if item.command is Command.WRITE]
    assert len(writes) == PRG_NROM128_BYTES
    assert all(item.target is Target.PRG for item in writes)
    assert transport.chr == b""


def test_deterministic_command_backpressure_is_tolerated():
    delayed_address = 31

    def delay(_index, item):
        delayed = item.command is Command.WRITE and item.address == delayed_address
        return 2 if delayed else 0

    transport = MockRuntimeLoaderTransport(
        command_delay_polls=delay,
        activation_delay_polls=1,
    )
    result = execute_load_plan(
        plan(chr_ram=True),
        transport,
        timeouts=RuntimeLoaderTimeouts(command_s=0.002),
    )
    assert result.status.runtime_active


def test_command_acceptance_timeout_stops_before_failed_write():
    def delay(_index, item):
        return 3 if item.command is Command.WRITE and item.address == 5 else 0

    transport = MockRuntimeLoaderTransport(command_delay_polls=delay)
    with pytest.raises(RuntimeLoadError, match="PRG write at address 5.*timed out"):
        execute_load_plan(
            plan(chr_ram=True),
            transport,
            timeouts=RuntimeLoaderTimeouts(command_s=0.002),
        )
    assert [item.command for item in transport.commands].count(Command.WRITE) == 5
    assert all(
        item.command not in (Command.COMMIT, Command.ACTIVATE)
        for item in transport.commands
    )


def test_transport_failure_mid_prg_never_commits_or_activates():
    transport = MockRuntimeLoaderTransport(fail_at_command=17)
    with pytest.raises(RuntimeLoadError, match="simulated transport failure"):
        execute_load_plan(plan(), transport)
    assert len(transport.commands) == 17
    assert all(
        item.command not in (Command.COMMIT, Command.ACTIVATE)
        for item in transport.commands
    )


def test_validation_timeout_never_activates():
    transport = MockRuntimeLoaderTransport(validation_delay_polls=5)
    with pytest.raises(RuntimeLoadError, match="image validation.*timed out"):
        execute_load_plan(
            plan(chr_ram=True),
            transport,
            timeouts=RuntimeLoaderTimeouts(image_validation_s=0.002),
        )
    assert transport.commands[-1].command is Command.COMMIT
    assert all(item.command is not Command.ACTIVATE for item in transport.commands)


def test_fpga_validation_error_never_activates():
    transport = MockRuntimeLoaderTransport(
        validation_delay_polls=1,
        validation_error=LoaderErrorCode.CHR_INCOMPLETE,
    )
    with pytest.raises(RuntimeLoadError, match="CHR_INCOMPLETE"):
        execute_load_plan(plan(chr_ram=True), transport)
    assert transport.read_status().state is LoaderState.ERROR
    assert all(item.command is not Command.ACTIVATE for item in transport.commands)


def test_activation_timeout_is_stage_specific():
    transport = MockRuntimeLoaderTransport(activation_delay_polls=5)
    with pytest.raises(RuntimeLoadError, match="activation.*timed out"):
        execute_load_plan(
            plan(chr_ram=True),
            transport,
            timeouts=RuntimeLoaderTimeouts(activation_s=0.002),
        )
    assert transport.commands[-1].command is Command.ACTIVATE
    status = transport.read_status()
    assert status.runtime_active and status.activation_in_progress


def test_mock_rejects_out_of_order_and_recovers_with_fresh_begin():
    load_plan = plan(chr_ram=True)
    transport = MockRuntimeLoaderTransport()
    transport.send(LoaderCommand.begin(load_plan.manifest), timeout_s=1.0)
    with pytest.raises(TransportProtocolError, match="UNEXPECTED_ADDRESS"):
        transport.send(
            LoaderCommand.write(Target.PRG, 1, 0xAA),
            timeout_s=1.0,
        )
    assert transport.prg == b""
    transport.send(LoaderCommand.begin(load_plan.manifest), timeout_s=1.0)
    assert transport.read_status().state is LoaderState.LOADING


def test_mock_rejects_chr_write_for_chr_ram():
    load_plan = plan(chr_ram=True)
    transport = MockRuntimeLoaderTransport()
    transport.send(LoaderCommand.begin(load_plan.manifest), timeout_s=1.0)
    with pytest.raises(TransportProtocolError, match="BAD_TARGET"):
        transport.send(
            LoaderCommand.write(Target.CHR, 0, 0x55),
            timeout_s=1.0,
        )


def test_mock_requires_complete_transfer_before_commit():
    load_plan = plan(chr_ram=True)
    transport = MockRuntimeLoaderTransport()
    transport.send(LoaderCommand.begin(load_plan.manifest), timeout_s=1.0)
    with pytest.raises(TransportProtocolError, match="PRG_INCOMPLETE"):
        transport.send(LoaderCommand.commit(), timeout_s=1.0)


def test_mock_requires_image_valid_before_activation():
    transport = MockRuntimeLoaderTransport()
    with pytest.raises(TransportProtocolError, match="ACTIVATE_INVALID"):
        transport.send(LoaderCommand.activate(), timeout_s=1.0)
