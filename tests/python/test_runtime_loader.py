import random

import pytest

from verification.runtime_loader import (
    CHR_LAST_ADDRESS,
    PRG_LAST_ADDRESS,
    Command,
    Error,
    RuntimeLoader,
    State,
    Target,
    legal_address,
)


@pytest.mark.parametrize(
    ("target", "address", "expected"),
    [
        (Target.PRG, 0, True),
        (Target.PRG, PRG_LAST_ADDRESS, True),
        (Target.PRG, PRG_LAST_ADDRESS + 1, False),
        (Target.CHR, 0, True),
        (Target.CHR, CHR_LAST_ADDRESS, True),
        (Target.CHR, CHR_LAST_ADDRESS + 1, False),
        (Target.NONE, 0, False),
        (Target.RESERVED, 0, False),
    ],
)
def test_legal_target_address_ranges(target, address, expected):
    assert legal_address(target, address) is expected


def accepted(loader, command, **payload):
    result = loader.clock(
        valid=True, command=command, storage_ready=True, **payload
    )
    assert result.command_accepted
    return result


def test_reset_begin_writes_commit_and_new_begin():
    loader = RuntimeLoader(state=State.READY, error_code=Error.BAD_COMMAND)
    output = loader.clock(reset=True)
    assert output.state == State.IDLE
    assert not output.busy and not output.completed and not output.error
    assert output.nes_hold_reset and not output.write_valid
    assert loader.state == State.IDLE and loader.error_code == Error.NONE

    accepted(loader, Command.BEGIN)
    assert loader.state == State.LOADING
    assert loader.evaluate().busy and loader.evaluate().nes_hold_reset

    for target, address, data in (
        (Target.PRG, 0x1234, 0xA5),
        (Target.CHR, 0x1FFE, 0x5A),
    ):
        output = accepted(
            loader,
            Command.WRITE,
            target=target,
            address=address,
            data=data,
        )
        assert output.write_valid
        assert (output.write_target, output.write_address, output.write_data) == (
            target,
            address,
            data,
        )

    accepted(loader, Command.COMMIT)
    assert loader.state == State.READY
    assert loader.evaluate().completed
    assert not loader.evaluate().nes_hold_reset

    accepted(loader, Command.BEGIN)
    assert loader.state == State.LOADING
    assert loader.error_code == Error.NONE and not loader.write_seen


@pytest.mark.parametrize(
    ("setup", "command", "payload", "error"),
    [
        ((), Command.WRITE, {"target": Target.PRG}, Error.WRONG_STATE),
        ((), Command.COMMIT, {}, Error.WRONG_STATE),
        ((Command.BEGIN,), Command.BEGIN, {}, Error.BEGIN_BUSY),
        (
            (Command.BEGIN,),
            Command.WRITE,
            {"target": Target.RESERVED},
            Error.BAD_TARGET,
        ),
        (
            (Command.BEGIN,),
            Command.WRITE,
            {"target": Target.PRG, "address": 0x8000},
            Error.BAD_ADDRESS,
        ),
        (
            (Command.BEGIN,),
            Command.WRITE,
            {"target": Target.CHR, "address": 0x2000},
            Error.BAD_ADDRESS,
        ),
        ((Command.BEGIN,), Command.COMMIT, {}, Error.EMPTY_LOAD),
        ((), Command.RESERVED, {}, Error.BAD_COMMAND),
    ],
)
def test_invalid_transactions_latch_error(setup, command, payload, error):
    loader = RuntimeLoader()
    for setup_command in setup:
        accepted(loader, setup_command)
    accepted(loader, command, **payload)
    assert loader.state == State.ERROR
    assert loader.error_code == error
    status = loader.evaluate()
    assert status.error and status.nes_hold_reset and not status.completed
    assert not status.write_valid

    # Later invalid commands cannot hide the first failure.
    accepted(loader, Command.COMMIT)
    assert loader.error_code == error
    accepted(loader, Command.BEGIN)
    assert loader.state == State.LOADING
    assert loader.error_code == Error.NONE


def test_backpressure_holds_write_until_storage_accepts():
    loader = RuntimeLoader()
    accepted(loader, Command.BEGIN)
    payload = dict(
        valid=True,
        command=Command.WRITE,
        target=Target.CHR,
        address=0x1234,
        data=0xC7,
    )
    for _ in range(17):
        output = loader.clock(storage_ready=False, **payload)
        assert output.write_valid and not output.command_ready
        assert not output.command_accepted
        assert loader.state == State.LOADING and not loader.write_seen
    output = loader.clock(storage_ready=True, **payload)
    assert output.command_ready and output.command_accepted
    assert output.write_valid and loader.write_seen


def test_reset_during_backpressure_discards_transaction():
    loader = RuntimeLoader()
    accepted(loader, Command.BEGIN)
    loader.clock(
        valid=True,
        command=Command.WRITE,
        target=Target.PRG,
        address=7,
        data=9,
        storage_ready=False,
    )
    output = loader.clock(
        reset=True,
        valid=True,
        command=Command.WRITE,
        target=Target.PRG,
        address=7,
        data=9,
        storage_ready=True,
    )
    assert not output.write_valid and not output.command_accepted
    assert loader.state == State.IDLE and not loader.write_seen
    assert loader.evaluate().nes_hold_reset


def test_deterministic_randomized_commands_and_backpressure():
    random_source = random.Random(0x4FA2026)
    loader = RuntimeLoader()
    accepted_writes = 0

    for cycle in range(20_000):
        reset = cycle == 0 or random_source.randrange(181) == 0
        valid = random_source.randrange(4) != 0
        command = random_source.randrange(4)
        target = random_source.randrange(4)
        address = random_source.randrange(0x10000)
        data = random_source.randrange(0x100)
        storage_ready = bool(random_source.randrange(2))
        output = loader.clock(
            reset=reset,
            valid=valid,
            command=command,
            target=target,
            address=address,
            data=data,
            storage_ready=storage_ready,
        )
        if output.write_valid:
            assert output.state == State.LOADING
            assert command == Command.WRITE
            assert legal_address(target, address)
            assert output.command_ready == storage_ready
            if output.command_accepted:
                accepted_writes += 1
        if output.completed:
            assert not output.nes_hold_reset and not output.error
        else:
            assert output.nes_hold_reset
        assert not (output.busy and (output.completed or output.error))

    assert accepted_writes > 0
