#!/usr/bin/env python3
"""Generate deterministic Phase 5F DMC RTL/reference-model vectors."""

from argparse import ArgumentParser
from pathlib import Path
import random
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.apu import DmcInputs, DmcModel  # noqa: E402


RANDOM_SEED = 0x005F_2026
RANDOM_CYCLES = 100_000


class Vectors:
    def __init__(self, stream: TextIO) -> None:
        self.stream = stream
        self.model = DmcModel()
        self.rows = 0
        self.stalls = 0
        self.acknowledgements = 0
        self.requests = 0
        self.timer_expirations = 0
        self.output_changes = 0
        self.last_output = 0

    def cycle(self, scenario: int, **kwargs: object) -> None:
        inputs = DmcInputs(**kwargs)
        pre_counter = self.model.timer_counter
        outputs, state = self.model.clock(inputs)
        values = (
            scenario,
            int(inputs.reset),
            int(inputs.cpu_cycle_enable),
            int(inputs.enable),
            int(inputs.status_write),
            int(inputs.write),
            inputs.write_register,
            inputs.write_data,
            int(inputs.mem_acknowledge),
            inputs.mem_read_data,
            int(outputs.active),
            int(outputs.irq_flag),
            outputs.raw_output,
            int(outputs.mem_request),
            outputs.mem_address,
            int(state.irq_enable),
            int(state.loop),
            state.rate_index,
            state.sample_address_register,
            state.sample_length_register,
            state.current_address,
            state.bytes_remaining,
            state.sample_buffer,
            int(state.sample_buffer_empty),
            state.shift_register,
            state.bits_remaining,
            int(state.silence),
            state.output_level,
            self.model.timer_period,
            state.timer_counter,
            int(state.mem_request),
            state.mem_address,
            int(self.model.irq_flag),
        )
        self.stream.write(" ".join(str(value) for value in values) + "\n")
        self.rows += 1
        self.stalls += int(not inputs.cpu_cycle_enable)
        self.acknowledgements += int(inputs.mem_acknowledge)
        self.requests += int(outputs.mem_request)
        self.timer_expirations += int(
            inputs.cpu_cycle_enable and not inputs.reset and pre_counter == 0
        )
        self.output_changes += int(state.output_level != self.last_output)
        self.last_output = state.output_level

    def accepted(self, scenario: int, **kwargs: object) -> None:
        self.cycle(scenario, cpu_cycle_enable=True, **kwargs)

    def write(self, scenario: int, register: int, data: int) -> None:
        self.accepted(
            scenario,
            write=True,
            write_register=register,
            write_data=data,
        )

    def status(self, scenario: int, enable: bool) -> None:
        self.accepted(scenario, status_write=True, enable=enable)

    def service_request(self, scenario: int) -> None:
        assert self.model.mem_request
        address = self.model.mem_address
        data = ((address >> 8) ^ address ^ 0xA5) & 0xFF
        self.accepted(
            scenario,
            mem_acknowledge=True,
            mem_read_data=data,
        )

    def run_reader_until_fetches(
        self, scenario: int, fetches: int, *, limit: int = 100_000
    ) -> list[int]:
        addresses: list[int] = []
        for _ in range(limit):
            if self.model.mem_request:
                addresses.append(self.model.mem_address)
                self.service_request(scenario)
                if len(addresses) == fetches:
                    return addresses
            else:
                self.accepted(scenario)
        raise AssertionError("DMC reader did not complete requested fetch count")


def generate(stream: TextIO) -> Vectors:
    vectors = Vectors(stream)
    rng = random.Random(RANDOM_SEED)

    # 1: reset, all register decodes, all rates, and direct 7-bit loads.
    vectors.cycle(1, reset=True)
    vectors.cycle(1, reset=True, cpu_cycle_enable=True)
    for rate in range(16):
        vectors.write(1, 0, 0xC0 | rate)
    for level in (0, 1, 0x3F, 0x7E, 0x7F, 0x80, 0xFF):
        vectors.write(1, 1, level)
    for value in (0, 1, 0x55, 0x80, 0xFF):
        vectors.write(1, 2, value)
        vectors.write(1, 3, value)

    # 2: request hold, stable address, exactly-once fetch, and disable.
    vectors.cycle(2, reset=True, cpu_cycle_enable=True)
    vectors.write(2, 2, 0x23)
    vectors.write(2, 3, 0)
    vectors.status(2, True)
    for _ in range(32):
        vectors.cycle(2, cpu_cycle_enable=False)
        vectors.accepted(2)
    vectors.service_request(2)
    for _ in range(100):
        vectors.accepted(2)
    vectors.status(2, False)

    # 3: original deterministic 17-byte sample and complete DAC stream.
    vectors.cycle(3, reset=True, cpu_cycle_enable=True)
    vectors.write(3, 0, 0x0F)
    vectors.write(3, 1, 64)
    vectors.write(3, 2, 0x40)
    vectors.write(3, 3, 1)
    vectors.status(3, True)
    addresses = vectors.run_reader_until_fetches(3, 17)
    assert addresses == list(range(0xD000, 0xD011))
    for _ in range(1_000):
        vectors.accepted(3)

    # 4: 65 bytes cross $FFFF and prove the special $8000 wrap.
    vectors.cycle(4, reset=True, cpu_cycle_enable=True)
    vectors.write(4, 0, 0x0F)
    vectors.write(4, 2, 0xFF)
    vectors.write(4, 3, 4)
    vectors.status(4, True)
    addresses = vectors.run_reader_until_fetches(4, 65)
    assert addresses[0] == 0xFFC0
    assert addresses[63:] == [0xFFFF, 0x8000]

    # 5: one-byte sample loops repeatedly without raising IRQ.
    vectors.cycle(5, reset=True, cpu_cycle_enable=True)
    vectors.write(5, 0, 0xCF)
    vectors.write(5, 2, 0x7A)
    vectors.write(5, 3, 0)
    vectors.status(5, True)
    addresses = vectors.run_reader_until_fetches(5, 5)
    assert addresses == [0xDE80] * 5
    assert not vectors.model.irq_flag

    # 6: terminal IRQ, status clear, and $4010 IRQ-disable clear.
    vectors.cycle(6, reset=True, cpu_cycle_enable=True)
    vectors.write(6, 0, 0x8F)
    vectors.write(6, 3, 0)
    vectors.status(6, True)
    vectors.service_request(6)
    assert vectors.model.irq_flag
    vectors.status(6, False)
    while not vectors.model.sample_buffer_empty:
        vectors.accepted(6)
    vectors.status(6, True)
    vectors.service_request(6)
    assert vectors.model.irq_flag
    vectors.write(6, 0, 0x0F)

    # 7: pause/step and reset while a request is outstanding.
    vectors.cycle(7, reset=True, cpu_cycle_enable=True)
    vectors.write(7, 2, 0x66)
    vectors.write(7, 3, 2)
    vectors.status(7, True)
    for _ in range(4_096):
        vectors.cycle(7, cpu_cycle_enable=False)
    vectors.accepted(7)
    vectors.cycle(7, reset=True, cpu_cycle_enable=True)

    # 8: fixed-seed randomized state/model comparison. A request is either
    # held, acknowledged once, or reset; no impossible duplicate ACKs occur.
    for _ in range(RANDOM_CYCLES):
        if rng.randrange(60_000) == 0:
            vectors.cycle(8, reset=True, cpu_cycle_enable=bool(rng.randrange(2)))
        elif vectors.model.mem_request:
            if rng.randrange(5) == 0:
                vectors.service_request(8)
            else:
                vectors.cycle(8, cpu_cycle_enable=bool(rng.randrange(5)))
        elif rng.randrange(150) == 0:
            vectors.write(8, rng.randrange(4), rng.randrange(256))
        elif rng.randrange(300) == 0:
            vectors.status(8, bool(rng.randrange(2)))
        else:
            vectors.cycle(8, cpu_cycle_enable=bool(rng.randrange(5)))

    return vectors


def main() -> int:
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as stream:
        vectors = generate(stream)
    print(
        "DMC reference: "
        f"rows={vectors.rows} stalls={vectors.stalls} "
        f"requests={vectors.requests} acks={vectors.acknowledgements} "
        f"timer_expirations={vectors.timer_expirations} "
        f"output_changes={vectors.output_changes} seed=0x{RANDOM_SEED:08x}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
