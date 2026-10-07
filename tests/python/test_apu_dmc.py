import random

from verification.apu import (
    APU_STATUS,
    DMC_RATE_TABLE,
    ApuFoundationModel,
    ApuInputs,
    DmcInputs,
    DmcModel,
    dmc_sample_address,
    dmc_sample_length,
)


def step(model: DmcModel, **kwargs: object):
    return model.clock(DmcInputs(cpu_cycle_enable=True, **kwargs))


def write(model: DmcModel, register: int, data: int) -> None:
    step(model, write=True, write_register=register, write_data=data)


def start(
    model: DmcModel,
    *,
    address: int = 0,
    length: int = 0,
    control: int = 0,
) -> None:
    write(model, 0, control)
    write(model, 2, address)
    write(model, 3, length)
    step(model, status_write=True, enable=True)


def acknowledge(model: DmcModel, data: int) -> None:
    assert model.mem_request
    step(model, mem_acknowledge=True, mem_read_data=data)


def test_ntsc_rate_table_has_all_sixteen_exact_periods() -> None:
    assert DMC_RATE_TABLE == (
        428, 380, 340, 320, 286, 254, 226, 214,
        190, 160, 142, 128, 106, 85, 72, 54,
    )
    model = DmcModel()
    for index, period in enumerate(DMC_RATE_TABLE):
        write(model, 0, index)
        assert model.rate_index == index
        assert model.timer_period == period


def test_sample_address_formula_minimum_middle_and_maximum() -> None:
    assert dmc_sample_address(0x00) == 0xC000
    assert dmc_sample_address(0x55) == 0xD540
    assert dmc_sample_address(0x80) == 0xE000
    assert dmc_sample_address(0xFF) == 0xFFC0


def test_sample_length_formula_minimum_middle_and_maximum() -> None:
    assert dmc_sample_length(0x00) == 1
    assert dmc_sample_length(0x55) == 1361
    assert dmc_sample_length(0x80) == 2049
    assert dmc_sample_length(0xFF) == 4081


def test_all_four_registers_decode_through_apu_bus() -> None:
    apu = ApuFoundationModel()
    values = (0xCF, 0xFD, 0x6A, 0x35)
    for offset, value in enumerate(values):
        outputs, _ = apu.clock(ApuInputs(
            cpu_cycle_enable=True,
            cpu_write=True,
            cpu_address=0x4010 + offset,
            cpu_write_data=value,
        ))
        assert outputs.channel_write
        assert outputs.channel_write_register == 0x10 + offset
    state = apu.dmc.state()
    assert state.irq_enable and state.loop and state.rate_index == 0x0F
    assert state.output_level == 0x7D
    assert state.sample_address_register == 0x6A
    assert state.sample_length_register == 0x35


def test_4011_direct_load_is_seven_bit_and_never_starts_reader() -> None:
    model = DmcModel()
    for value in (0, 1, 63, 126, 127, 128, 255):
        write(model, 1, value)
        assert model.output_level == (value & 0x7F)
        assert model.bytes_remaining == 0
        assert not model.mem_request


def test_4015_start_disable_restart_and_active_status() -> None:
    apu = ApuFoundationModel()
    for address, value in ((0x4012, 0x21), (0x4013, 0x02)):
        apu.clock(ApuInputs(
            cpu_cycle_enable=True, cpu_write=True,
            cpu_address=address, cpu_write_data=value,
        ))
    apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_write=True,
        cpu_address=APU_STATUS, cpu_write_data=0x10,
    ))
    assert apu.dmc.current_address == 0xC840
    assert apu.dmc.bytes_remaining == 33
    assert apu.dmc.mem_request
    outputs, _ = apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_read=True, cpu_address=APU_STATUS,
    ))
    assert outputs.cpu_read_data & 0x10

    apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_write=True,
        cpu_address=APU_STATUS, cpu_write_data=0,
    ))
    assert apu.dmc.bytes_remaining == 0
    assert not apu.dmc.mem_request
    outputs, _ = apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_read=True, cpu_address=APU_STATUS,
    ))
    assert not outputs.cpu_read_data & 0x10


def test_request_is_held_with_stable_address_until_exactly_one_ack() -> None:
    model = DmcModel()
    start(model, address=0x23, length=0)
    expected = dmc_sample_address(0x23)
    assert model.mem_request and model.mem_address == expected
    for _ in range(37):
        step(model)
        assert model.mem_request and model.mem_address == expected
        assert model.bytes_remaining == 1
    acknowledge(model, 0xA6)
    assert not model.mem_request
    assert model.current_address == expected + 1
    assert model.bytes_remaining == 0
    assert model.sample_buffer == 0xA6


def test_current_address_wraps_ffff_to_8000_and_decrements_once() -> None:
    model = DmcModel()
    model.current_address = 0xFFFF
    model.bytes_remaining = 2
    model.timer_counter = 10
    step(model)
    assert model.mem_request and model.mem_address == 0xFFFF
    acknowledge(model, 0x19)
    assert model.current_address == 0x8000
    assert model.bytes_remaining == 1
    for _ in range(4):
        step(model)
    assert model.bytes_remaining == 1


def test_buffer_consumption_output_load_and_silence() -> None:
    model = DmcModel()
    model.sample_buffer = 0b1010_0101
    model.sample_buffer_empty = False
    model.bits_remaining = 1
    model.timer_counter = 0
    model.silence = True
    step(model)
    assert model.shift_register == 0b1010_0101
    assert model.bits_remaining == 8
    assert not model.silence and model.sample_buffer_empty

    model.sample_buffer_empty = True
    model.bits_remaining = 1
    model.timer_counter = 0
    step(model)
    assert model.silence and model.shift_register == 0


def test_delta_bits_raise_lower_and_saturate_without_wrap() -> None:
    model = DmcModel()
    model.silence = False
    model.bits_remaining = 8
    for initial, bit, expected in (
        (64, 1, 66), (64, 0, 62),
        (126, 1, 126), (127, 1, 127),
        (1, 0, 1), (0, 0, 0),
    ):
        model.output_level = initial
        model.shift_register = bit
        model.timer_counter = 0
        step(model)
        assert model.output_level == expected


def test_known_sample_byte_produces_lsb_first_dac_sequence() -> None:
    model = DmcModel()
    model.output_level = 64
    model.silence = False
    model.shift_register = 0b1010_0101
    model.bits_remaining = 8
    expected = [66, 64, 66, 64, 62, 64, 62, 64]
    observed = []
    for _ in range(8):
        model.timer_counter = 0
        step(model)
        observed.append(model.output_level)
    assert observed == expected


def test_long_sample_refills_without_drops_or_duplicates() -> None:
    model = DmcModel()
    start(model, address=0x40, length=1)  # 17 bytes
    expected = [(index * 37 + 0x5B) & 0xFF for index in range(17)]
    fetched_addresses = []
    for value in expected:
        assert model.mem_request
        fetched_addresses.append(model.mem_address)
        model.timer_counter = 10
        acknowledge(model, value)
        if value != expected[-1]:
            model.bits_remaining = 1
            model.timer_counter = 0
            step(model)  # consume the buffered byte
            step(model)  # empty buffer schedules the next request
    assert fetched_addresses == list(range(0xD000, 0xD011))
    assert model.bytes_remaining == 0
    assert len(set(fetched_addresses)) == 17


def test_loop_reloads_reader_without_terminal_irq() -> None:
    model = DmcModel()
    start(model, address=0xFE, length=0, control=0xC0)
    first = model.mem_address
    for _ in range(5):
        acknowledge(model, 0x81)
        assert model.bytes_remaining == 1
        assert model.current_address == first
        assert not model.irq_flag
        model.bits_remaining = 1
        model.timer_counter = 0
        step(model)
        step(model)
        assert model.mem_request and model.mem_address == first


def test_terminal_irq_generation_and_both_clear_paths() -> None:
    model = DmcModel()
    start(model, control=0x80)
    acknowledge(model, 0x55)
    assert model.irq_flag and model.bytes_remaining == 0

    step(model, status_write=True, enable=False)
    assert not model.irq_flag
    model = DmcModel()
    start(model, control=0x80)
    acknowledge(model, 0xAA)
    assert model.irq_flag
    write(model, 0, 0x00)
    assert not model.irq_flag


def test_irq_is_suppressed_when_disabled_or_looping() -> None:
    for control in (0x00, 0xC0):
        model = DmcModel()
        start(model, control=control)
        acknowledge(model, 0x11)
        assert not model.irq_flag


def test_apu_irq_is_frame_or_internal_dmc_and_status_read_does_not_clear_dmc() -> None:
    apu = ApuFoundationModel()
    for address, value in ((0x4010, 0x80), (0x4013, 0x00)):
        apu.clock(ApuInputs(
            cpu_cycle_enable=True, cpu_write=True,
            cpu_address=address, cpu_write_data=value,
        ))
    apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_write=True,
        cpu_address=APU_STATUS, cpu_write_data=0x10,
    ))
    apu.clock(ApuInputs(
        cpu_cycle_enable=True,
        dmc_mem_acknowledge=True,
        dmc_mem_read_data=0x5A,
    ))
    outputs, _ = apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_read=True, cpu_address=APU_STATUS,
    ))
    assert outputs.irq and outputs.cpu_read_data & 0x80
    outputs, _ = apu.clock(ApuInputs(
        cpu_cycle_enable=True, cpu_read=True, cpu_address=APU_STATUS,
    ))
    assert outputs.irq and outputs.cpu_read_data & 0x80


def test_pause_freezes_timer_reader_shifter_and_pending_request() -> None:
    model = DmcModel()
    start(model, address=0x44, length=2)
    before = model.state()
    for _ in range(100):
        model.clock(DmcInputs(cpu_cycle_enable=False))
    assert model.state() == before


def test_reset_cancels_outstanding_request_and_clears_all_runtime_state() -> None:
    model = DmcModel()
    start(model, address=0x99, length=0, control=0x8F)
    write(model, 1, 0x7F)
    assert model.mem_request
    model.clock(DmcInputs(reset=True))
    assert model.state() == DmcModel().state()
    assert not model.evaluate().active
    assert model.evaluate().raw_output == 0


def test_deterministic_randomized_reader_output_invariants() -> None:
    rng = random.Random(0xD0C5_2026)
    model = DmcModel()
    acknowledgements = 0
    for _ in range(100_000):
        if model.mem_request and rng.randrange(5) == 0:
            inputs = DmcInputs(
                cpu_cycle_enable=True,
                mem_acknowledge=True,
                mem_read_data=rng.randrange(256),
            )
            acknowledgements += 1
        elif rng.randrange(500) == 0:
            register = rng.randrange(4)
            inputs = DmcInputs(
                cpu_cycle_enable=True,
                write=True,
                write_register=register,
                write_data=rng.randrange(256),
            )
        elif rng.randrange(800) == 0:
            inputs = DmcInputs(
                cpu_cycle_enable=True,
                status_write=True,
                enable=bool(rng.randrange(2)),
            )
        else:
            inputs = DmcInputs(cpu_cycle_enable=bool(rng.randrange(5)))
        model.clock(inputs)
        state = model.state()
        assert 0 <= state.output_level <= 127
        assert 0 <= state.bytes_remaining <= 4081
        assert 1 <= state.bits_remaining <= 8
        if state.mem_request:
            assert state.bytes_remaining > 0
            assert 0x8000 <= state.mem_address <= 0xFFFF
    assert acknowledgements > 20
