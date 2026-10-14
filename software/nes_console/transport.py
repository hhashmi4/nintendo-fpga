"""Bounded, single-owner request/response transport for the console mailbox."""

import time

from software.nes_loader.mmio import RawMmio
from .protocol import (
    Command, MAGIC, VERSION, REG_MAGIC, REG_VERSION, REG_BRIDGE,
    REG_COMMAND, REG_RESPONSE, REG_RESULT, REG_COMPLETED,
    Result, State, Source, Status, allowed, request_word,
)


class ConsoleError(RuntimeError):
    pass


class ConsoleTransport:
    def __init__(self, mmio: RawMmio, *, timeout_s: float = 3.0,
                 clock=time.monotonic, sleep=time.sleep):
        if timeout_s <= 0:
            raise ValueError("timeout must be positive")
        self.mmio, self.timeout_s = mmio, timeout_s
        self.clock, self.sleep = clock, sleep
        if mmio.read32(REG_MAGIC) != MAGIC or mmio.read32(REG_VERSION) != VERSION:
            raise ConsoleError("console MMIO identity mismatch")

    def _wait(self, predicate, deadline):
        while not predicate():
            if self.clock() >= deadline:
                raise ConsoleError("console timeout; ownership is unconfirmed")
            self.sleep(0.001)

    def exchange(self, command: Command, epoch: int = 0) -> Status:
        deadline = self.clock() + self.timeout_s
        self._wait(lambda: self.mmio.read32(REG_BRIDGE) & 1, deadline)
        count = self.mmio.read32(REG_COMPLETED)
        self.mmio.write32(REG_COMMAND, request_word(command, epoch))
        expected_count = (count + 1) & 0xFFFFFFFF

        def completed():
            observed = self.mmio.read32(REG_COMPLETED)
            if observed not in (count, expected_count):
                raise ConsoleError("console reset or another issuer interrupted the request")
            return observed == expected_count

        self._wait(completed, deadline)
        result = Result(self.mmio.read32(REG_RESULT))
        status = Status.decode(self.mmio.read32(REG_RESPONSE))
        if result != Result.OK:
            raise ConsoleError(f"console rejected {command.name}: {result.name}")
        return status

    def status(self) -> Status:
        return self.exchange(Command.STATUS)

    def request(self, command: Command) -> Status:
        status = self.status()
        if not allowed(command, status.state):
            raise ConsoleError(f"{command.name} invalid in {status.state.name}")
        # Never automatically retry a stale ownership-changing command.
        return self.exchange(command, status.epoch)

    def wait_state(self, state: State, *, epoch: int | None = None) -> Status:
        deadline = self.clock() + self.timeout_s
        while True:
            status = self.status()
            if epoch is not None and status.epoch != epoch:
                raise ConsoleError("console ownership request was superseded")
            expected_source = {State.MENU: Source.SYSTEM, State.GAME: Source.GAME,
                               State.DEVELOPER: Source.DEVELOPER}.get(state)
            if status.state == state and (expected_source is None or
                                          status.video_source == expected_source):
                return status
            if status.state == State.ERROR:
                raise ConsoleError(f"console recovery error {status.error}")
            if self.clock() >= deadline:
                raise ConsoleError(f"console did not reach {state.name}")
            self.sleep(0.001)

    def menu(self) -> Status:
        before = self.request(Command.MENU)
        return self.wait_state(State.MENU, epoch=(before.epoch + 1) & 0xFFFF)

    def launch(self) -> Status:
        before = self.request(Command.LAUNCH)
        return self.wait_state(State.GAME, epoch=(before.epoch + 1) & 0xFFFF)
