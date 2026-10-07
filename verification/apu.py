"""Independent NTSC NES APU model for all five sound channels."""

from dataclasses import dataclass


APU_CHANNEL_FIRST = 0x4000
APU_CHANNEL_LAST = 0x4013
APU_STATUS = 0x4015
APU_FRAME_COUNTER = 0x4017

QUARTER_1 = 7457
HALF_1 = 14913
QUARTER_3 = 22371
FOUR_STEP_IRQ_1 = 29828
FOUR_STEP_HALF = 29829
FOUR_STEP_END = 29830
FIVE_STEP_HALF = 37281
FIVE_STEP_END = 37282

LENGTH_TABLE = (
    10, 254, 20, 2, 40, 4, 80, 6,
    160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30,
)

# Position zero is selected by a $4003 write. The hardware sequencer counts
# downward, selecting position seven on its first timer expiration.
PULSE_DUTY_TABLE = (
    (0, 0, 0, 0, 0, 0, 0, 1),
    (0, 0, 0, 0, 0, 0, 1, 1),
    (0, 0, 0, 0, 1, 1, 1, 1),
    (1, 1, 1, 1, 1, 1, 0, 0),
)

TRIANGLE_SEQUENCE = (
    15, 14, 13, 12, 11, 10, 9, 8,
    7, 6, 5, 4, 3, 2, 1, 0,
    0, 1, 2, 3, 4, 5, 6, 7,
    8, 9, 10, 11, 12, 13, 14, 15,
)

NOISE_PERIOD_TABLE = (
    4, 8, 16, 32, 64, 96, 128, 160,
    202, 254, 380, 508, 762, 1016, 2034, 4068,
)

DMC_RATE_TABLE = (
    428, 380, 340, 320, 286, 254, 226, 214,
    190, 160, 142, 128, 106, 85, 72, 54,
)


def dmc_sample_address(register: int) -> int:
    """Expand $4012 into its $C000-$FFC0 CPU sample address."""

    if not 0 <= register <= 0xFF:
        raise ValueError("sample address register must be 8 bits")
    return 0xC000 | (register << 6)


def dmc_sample_length(register: int) -> int:
    """Expand $4013 into its 1-4081 byte sample length."""

    if not 0 <= register <= 0xFF:
        raise ValueError("sample length register must be 8 bits")
    return (register << 4) | 1


def pulse_sequence_cpu_cycles(timer_period: int) -> int:
    """Return CPU cycles in one complete eight-step pulse waveform."""

    if not 0 <= timer_period <= 0x7FF:
        raise ValueError("timer_period must be 11 bits")
    return 16 * (timer_period + 1)


def pulse_frequency_hz(timer_period: int, cpu_hz: float = 1_789_773.0) -> float:
    """Human-readable NTSC frequency; no floating point is used by RTL."""

    return cpu_hz / pulse_sequence_cpu_cycles(timer_period)


def triangle_sequence_cpu_cycles(timer_period: int) -> int:
    """Return CPU cycles in one complete 32-step triangle waveform."""

    if not 0 <= timer_period <= 0x7FF:
        raise ValueError("timer_period must be 11 bits")
    return 32 * (timer_period + 1)


def triangle_frequency_hz(
    timer_period: int, cpu_hz: float = 1_789_773.0
) -> float:
    """Human-readable NTSC frequency; no floating point is used by RTL."""

    return cpu_hz / triangle_sequence_cpu_cycles(timer_period)


def noise_shift_cpu_cycles(period_index: int) -> int:
    """Return CPU cycles between Noise LFSR shifts for an NTSC period index."""

    if not 0 <= period_index <= 0x0F:
        raise ValueError("period_index must be 4 bits")
    return NOISE_PERIOD_TABLE[period_index]


def noise_shift_rate_hz(
    period_index: int, cpu_hz: float = 1_789_773.0
) -> float:
    """Human-readable LFSR shift rate; RTL uses integer divider logic."""

    return cpu_hz / noise_shift_cpu_cycles(period_index)


@dataclass(frozen=True)
class PulseInputs:
    reset: bool = False
    cpu_cycle_enable: bool = False
    timer_tick: bool = False
    enable: bool = False
    write: bool = False
    write_register: int = 0
    write_data: int = 0
    quarter_frame_tick: bool = False
    half_frame_tick: bool = False


@dataclass(frozen=True)
class PulseOutputs:
    active: bool
    raw_output: int
    sweep_target: int
    sweep_mute: bool


@dataclass(frozen=True)
class PulseState:
    duty: int
    duty_position: int
    timer_period: int
    timer_counter: int
    length_counter: int
    length_halt: bool
    constant_volume: bool
    envelope_period: int
    envelope_start: bool
    envelope_divider: int
    envelope_decay: int
    sweep_enabled: bool
    sweep_period: int
    sweep_negate: bool
    sweep_shift: int
    sweep_reload: bool
    sweep_divider: int


class PulseModel:
    """Behavioral specification of a 2A03 pulse channel."""

    def __init__(self, *, channel_one: bool) -> None:
        self.channel_one = channel_one
        self.reset_state()

    def reset_state(self) -> None:
        self.duty = 0
        self.duty_position = 0
        self.timer_period = 0
        self.timer_counter = 0
        self.length_counter = 0
        self.length_halt = False
        self.constant_volume = False
        self.envelope_period = 0
        self.envelope_start = False
        self.envelope_divider = 0
        self.envelope_decay = 0
        self.sweep_enabled = False
        self.sweep_period = 0
        self.sweep_negate = False
        self.sweep_shift = 0
        self.sweep_reload = False
        self.sweep_divider = 0

    def state(self) -> PulseState:
        return PulseState(
            duty=self.duty,
            duty_position=self.duty_position,
            timer_period=self.timer_period,
            timer_counter=self.timer_counter,
            length_counter=self.length_counter,
            length_halt=self.length_halt,
            constant_volume=self.constant_volume,
            envelope_period=self.envelope_period,
            envelope_start=self.envelope_start,
            envelope_divider=self.envelope_divider,
            envelope_decay=self.envelope_decay,
            sweep_enabled=self.sweep_enabled,
            sweep_period=self.sweep_period,
            sweep_negate=self.sweep_negate,
            sweep_shift=self.sweep_shift,
            sweep_reload=self.sweep_reload,
            sweep_divider=self.sweep_divider,
        )

    @staticmethod
    def _validate(inputs: PulseInputs) -> None:
        if not 0 <= inputs.write_register <= 3:
            raise ValueError("write_register must be 2 bits")
        if not 0 <= inputs.write_data <= 0xFF:
            raise ValueError("write_data must be 8 bits")
        if inputs.half_frame_tick and not inputs.quarter_frame_tick:
            raise ValueError("half-frame ticks must include quarter-frame ticks")
        if inputs.timer_tick and not inputs.cpu_cycle_enable:
            raise ValueError("timer_tick requires cpu_cycle_enable")

    def sweep_target(self) -> int:
        change = self.timer_period >> self.sweep_shift
        if self.sweep_negate:
            correction = 1 if self.channel_one else 0
            return (self.timer_period - change - correction) & 0xFFF
        return self.timer_period + change

    def sweep_mute(self) -> bool:
        return self.timer_period < 8 or (
            not self.sweep_negate and self.sweep_target() > 0x7FF
        )

    def evaluate(self, enable: bool) -> PulseOutputs:
        active = self.length_counter != 0
        duty_bit = PULSE_DUTY_TABLE[self.duty][self.duty_position]
        volume = (
            self.envelope_period if self.constant_volume else self.envelope_decay
        )
        output = volume if enable and active and duty_bit and not self.sweep_mute() else 0
        return PulseOutputs(
            active=active,
            raw_output=output,
            sweep_target=self.sweep_target(),
            sweep_mute=self.sweep_mute(),
        )

    def clock(self, inputs: PulseInputs) -> tuple[PulseOutputs, PulseState]:
        """Evaluate pre-edge output, then apply one fabric-clock edge."""

        self._validate(inputs)
        outputs = self.evaluate(inputs.enable)
        if inputs.reset:
            self.reset_state()
            return outputs, self.state()
        if not inputs.cpu_cycle_enable:
            return outputs, self.state()

        old = self.state()
        old_target = outputs.sweep_target

        if inputs.timer_tick:
            if old.timer_counter == 0:
                self.timer_counter = old.timer_period
                self.duty_position = (old.duty_position - 1) & 0x07
            else:
                self.timer_counter = old.timer_counter - 1

        if inputs.quarter_frame_tick:
            if old.envelope_start:
                self.envelope_start = False
                self.envelope_decay = 15
                self.envelope_divider = old.envelope_period
            elif old.envelope_divider == 0:
                self.envelope_divider = old.envelope_period
                if old.envelope_decay != 0:
                    self.envelope_decay = old.envelope_decay - 1
                elif old.length_halt:
                    self.envelope_decay = 15
            else:
                self.envelope_divider = old.envelope_divider - 1

        if inputs.half_frame_tick:
            if old.length_counter != 0 and not old.length_halt:
                self.length_counter = old.length_counter - 1

            if old.sweep_divider == 0:
                if (
                    old.sweep_enabled
                    and old.sweep_shift != 0
                    and old.timer_period >= 8
                    and old_target <= 0x7FF
                ):
                    self.timer_period = old_target
                self.sweep_divider = old.sweep_period
            else:
                self.sweep_divider = old.sweep_divider - 1

            if old.sweep_reload:
                self.sweep_divider = old.sweep_period
                self.sweep_reload = False

        if inputs.write:
            if inputs.write_register == 0:
                self.duty = (inputs.write_data >> 6) & 0x03
                self.length_halt = bool(inputs.write_data & 0x20)
                self.constant_volume = bool(inputs.write_data & 0x10)
                self.envelope_period = inputs.write_data & 0x0F
            elif inputs.write_register == 1:
                self.sweep_enabled = bool(inputs.write_data & 0x80)
                self.sweep_period = (inputs.write_data >> 4) & 0x07
                self.sweep_negate = bool(inputs.write_data & 0x08)
                self.sweep_shift = inputs.write_data & 0x07
                self.sweep_reload = True
            elif inputs.write_register == 2:
                self.timer_period = (self.timer_period & 0x700) | inputs.write_data
            else:
                self.timer_period = (
                    (self.timer_period & 0x0FF) | ((inputs.write_data & 0x07) << 8)
                )
                self.duty_position = 0
                self.envelope_start = True
                if inputs.enable:
                    self.length_counter = LENGTH_TABLE[inputs.write_data >> 3]

        if not inputs.enable:
            self.length_counter = 0

        return outputs, self.state()


class Pulse1Model(PulseModel):
    """Pulse 1 model with the channel-one sweep-negate correction."""

    def __init__(self) -> None:
        super().__init__(channel_one=True)


class Pulse2Model(PulseModel):
    """Pulse 2 model with the channel-two sweep-negate calculation."""

    def __init__(self) -> None:
        super().__init__(channel_one=False)


@dataclass(frozen=True)
class TriangleInputs:
    reset: bool = False
    cpu_cycle_enable: bool = False
    enable: bool = False
    write: bool = False
    write_register: int = 0
    write_data: int = 0
    quarter_frame_tick: bool = False
    half_frame_tick: bool = False


@dataclass(frozen=True)
class TriangleOutputs:
    active: bool
    raw_output: int


@dataclass(frozen=True)
class TriangleState:
    control_flag: bool
    linear_reload_value: int
    linear_counter: int
    linear_reload_flag: bool
    sequence_position: int
    timer_period: int
    timer_counter: int
    length_counter: int


class TriangleModel:
    """Behavioral specification of the 2A03 triangle channel."""

    def __init__(self) -> None:
        self.reset_state()

    def reset_state(self) -> None:
        self.control_flag = False
        self.linear_reload_value = 0
        self.linear_counter = 0
        self.linear_reload_flag = False
        self.sequence_position = 0
        self.timer_period = 0
        self.timer_counter = 0
        self.length_counter = 0

    def state(self) -> TriangleState:
        return TriangleState(
            control_flag=self.control_flag,
            linear_reload_value=self.linear_reload_value,
            linear_counter=self.linear_counter,
            linear_reload_flag=self.linear_reload_flag,
            sequence_position=self.sequence_position,
            timer_period=self.timer_period,
            timer_counter=self.timer_counter,
            length_counter=self.length_counter,
        )

    @staticmethod
    def _validate(inputs: TriangleInputs) -> None:
        if not 0 <= inputs.write_register <= 3:
            raise ValueError("write_register must be 2 bits")
        if not 0 <= inputs.write_data <= 0xFF:
            raise ValueError("write_data must be 8 bits")
        if inputs.half_frame_tick and not inputs.quarter_frame_tick:
            raise ValueError("half-frame ticks must include quarter-frame ticks")

    def evaluate(self) -> TriangleOutputs:
        return TriangleOutputs(
            active=self.length_counter != 0,
            raw_output=TRIANGLE_SEQUENCE[self.sequence_position],
        )

    def clock(
        self, inputs: TriangleInputs
    ) -> tuple[TriangleOutputs, TriangleState]:
        """Evaluate pre-edge DAC output, then apply one fabric-clock edge."""

        self._validate(inputs)
        outputs = self.evaluate()
        if inputs.reset:
            self.reset_state()
            return outputs, self.state()
        if not inputs.cpu_cycle_enable:
            return outputs, self.state()

        old = self.state()

        # The triangle divider clocks on every CPU slot and is not stopped by
        # the length/linear gates; only sequence advancement is stopped.
        if old.timer_counter == 0:
            self.timer_counter = old.timer_period
            if old.length_counter != 0 and old.linear_counter != 0:
                self.sequence_position = (old.sequence_position + 1) & 0x1F
        else:
            self.timer_counter = old.timer_counter - 1

        if inputs.quarter_frame_tick:
            if old.linear_reload_flag:
                self.linear_counter = old.linear_reload_value
            elif old.linear_counter != 0:
                self.linear_counter = old.linear_counter - 1
            if not old.control_flag:
                self.linear_reload_flag = False

        if inputs.half_frame_tick and old.length_counter != 0:
            if not old.control_flag:
                self.length_counter = old.length_counter - 1

        if inputs.write:
            if inputs.write_register == 0:  # $4008
                self.control_flag = bool(inputs.write_data & 0x80)
                self.linear_reload_value = inputs.write_data & 0x7F
            elif inputs.write_register == 2:  # $400A
                self.timer_period = (old.timer_period & 0x700) | inputs.write_data
            elif inputs.write_register == 3:  # $400B
                self.timer_period = (
                    (old.timer_period & 0x0FF) | ((inputs.write_data & 0x07) << 8)
                )
                self.linear_reload_flag = True
                if inputs.enable:
                    self.length_counter = LENGTH_TABLE[inputs.write_data >> 3]

        if not inputs.enable:
            self.length_counter = 0

        return outputs, self.state()


@dataclass(frozen=True)
class NoiseInputs:
    reset: bool = False
    cpu_cycle_enable: bool = False
    timer_tick: bool = False
    enable: bool = False
    write: bool = False
    write_register: int = 0
    write_data: int = 0
    quarter_frame_tick: bool = False
    half_frame_tick: bool = False


@dataclass(frozen=True)
class NoiseOutputs:
    active: bool
    raw_output: int


@dataclass(frozen=True)
class NoiseState:
    length_halt: bool
    constant_volume: bool
    envelope_period: int
    envelope_start: bool
    envelope_divider: int
    envelope_decay: int
    mode: bool
    period_index: int
    timer_counter: int
    length_counter: int
    lfsr: int


class NoiseModel:
    """Behavioral specification of the 2A03 Noise channel."""

    def __init__(self) -> None:
        self.reset_state()

    def reset_state(self) -> None:
        self.length_halt = False
        self.constant_volume = False
        self.envelope_period = 0
        self.envelope_start = False
        self.envelope_divider = 0
        self.envelope_decay = 0
        self.mode = False
        self.period_index = 0
        self.timer_counter = 0
        self.length_counter = 0
        self.lfsr = 1

    def state(self) -> NoiseState:
        return NoiseState(
            length_halt=self.length_halt,
            constant_volume=self.constant_volume,
            envelope_period=self.envelope_period,
            envelope_start=self.envelope_start,
            envelope_divider=self.envelope_divider,
            envelope_decay=self.envelope_decay,
            mode=self.mode,
            period_index=self.period_index,
            timer_counter=self.timer_counter,
            length_counter=self.length_counter,
            lfsr=self.lfsr,
        )

    @staticmethod
    def _validate(inputs: NoiseInputs) -> None:
        if not 0 <= inputs.write_register <= 3:
            raise ValueError("write_register must be 2 bits")
        if not 0 <= inputs.write_data <= 0xFF:
            raise ValueError("write_data must be 8 bits")
        if inputs.half_frame_tick and not inputs.quarter_frame_tick:
            raise ValueError("half-frame ticks must include quarter-frame ticks")
        if inputs.timer_tick and not inputs.cpu_cycle_enable:
            raise ValueError("timer_tick requires cpu_cycle_enable")

    @property
    def timer_period(self) -> int:
        return NOISE_PERIOD_TABLE[self.period_index]

    def evaluate(self, enable: bool) -> NoiseOutputs:
        active = self.length_counter != 0
        volume = (
            self.envelope_period if self.constant_volume else self.envelope_decay
        )
        output = volume if enable and active and not (self.lfsr & 1) else 0
        return NoiseOutputs(active=active, raw_output=output)

    def clock(self, inputs: NoiseInputs) -> tuple[NoiseOutputs, NoiseState]:
        """Evaluate pre-edge output, then apply one fabric-clock edge."""

        self._validate(inputs)
        outputs = self.evaluate(inputs.enable)
        if inputs.reset:
            self.reset_state()
            return outputs, self.state()
        if not inputs.cpu_cycle_enable:
            return outputs, self.state()

        old = self.state()

        if inputs.timer_tick:
            if old.timer_counter == 0:
                tap = 6 if old.mode else 1
                feedback = (old.lfsr & 1) ^ ((old.lfsr >> tap) & 1)
                self.lfsr = (old.lfsr >> 1) | (feedback << 14)
                self.timer_counter = NOISE_PERIOD_TABLE[old.period_index] // 2 - 1
            else:
                self.timer_counter = old.timer_counter - 1

        if inputs.quarter_frame_tick:
            if old.envelope_start:
                self.envelope_start = False
                self.envelope_decay = 15
                self.envelope_divider = old.envelope_period
            elif old.envelope_divider != 0:
                self.envelope_divider = old.envelope_divider - 1
            else:
                self.envelope_divider = old.envelope_period
                if old.envelope_decay != 0:
                    self.envelope_decay = old.envelope_decay - 1
                elif old.length_halt:
                    self.envelope_decay = 15

        if (
            inputs.half_frame_tick
            and old.length_counter != 0
            and not old.length_halt
        ):
            self.length_counter = old.length_counter - 1

        if inputs.write:
            if inputs.write_register == 0:  # $400C
                self.length_halt = bool(inputs.write_data & 0x20)
                self.constant_volume = bool(inputs.write_data & 0x10)
                self.envelope_period = inputs.write_data & 0x0F
            elif inputs.write_register == 1:  # $400D, unused
                pass
            elif inputs.write_register == 2:  # $400E
                self.mode = bool(inputs.write_data & 0x80)
                self.period_index = inputs.write_data & 0x0F
            else:  # $400F
                self.envelope_start = True
                if inputs.enable:
                    self.length_counter = LENGTH_TABLE[inputs.write_data >> 3]

        if not inputs.enable:
            self.length_counter = 0

        if self.lfsr == 0:
            raise AssertionError("Noise LFSR entered the all-zero lock state")

        return outputs, self.state()


@dataclass(frozen=True)
class DmcInputs:
    reset: bool = False
    cpu_cycle_enable: bool = False
    enable: bool = False
    status_write: bool = False
    write: bool = False
    write_register: int = 0
    write_data: int = 0
    mem_acknowledge: bool = False
    mem_read_data: int = 0


@dataclass(frozen=True)
class DmcOutputs:
    active: bool
    irq_flag: bool
    raw_output: int
    mem_request: bool
    mem_address: int


@dataclass(frozen=True)
class DmcState:
    irq_enable: bool
    loop: bool
    rate_index: int
    sample_address_register: int
    sample_length_register: int
    current_address: int
    bytes_remaining: int
    sample_buffer: int
    sample_buffer_empty: bool
    shift_register: int
    bits_remaining: int
    silence: bool
    output_level: int
    timer_counter: int
    mem_request: bool
    mem_address: int


class DmcModel:
    """Behavioral DMC reader/output unit with a held request/ack interface."""

    def __init__(self) -> None:
        self.reset_state()

    def reset_state(self) -> None:
        self.irq_enable = False
        self.loop = False
        self.rate_index = 0
        self.sample_address_register = 0
        self.sample_length_register = 0
        self.current_address = 0
        self.bytes_remaining = 0
        self.sample_buffer = 0
        self.sample_buffer_empty = True
        self.shift_register = 0
        self.bits_remaining = 8
        self.silence = True
        self.output_level = 0
        self.timer_counter = 0
        self.mem_request = False
        self.mem_address = 0
        self.irq_flag = False

    @property
    def timer_period(self) -> int:
        return DMC_RATE_TABLE[self.rate_index]

    def state(self) -> DmcState:
        return DmcState(
            irq_enable=self.irq_enable,
            loop=self.loop,
            rate_index=self.rate_index,
            sample_address_register=self.sample_address_register,
            sample_length_register=self.sample_length_register,
            current_address=self.current_address,
            bytes_remaining=self.bytes_remaining,
            sample_buffer=self.sample_buffer,
            sample_buffer_empty=self.sample_buffer_empty,
            shift_register=self.shift_register,
            bits_remaining=self.bits_remaining,
            silence=self.silence,
            output_level=self.output_level,
            timer_counter=self.timer_counter,
            mem_request=self.mem_request,
            mem_address=self.mem_address,
        )

    def evaluate(self, inputs: DmcInputs | None = None) -> DmcOutputs:
        reset = inputs.reset if inputs is not None else False
        return DmcOutputs(
            active=not reset and self.bytes_remaining != 0,
            irq_flag=not reset and self.irq_flag,
            raw_output=0 if reset else self.output_level,
            mem_request=not reset and self.mem_request,
            mem_address=self.mem_address,
        )

    @staticmethod
    def _validate(inputs: DmcInputs) -> None:
        if not 0 <= inputs.write_register <= 3:
            raise ValueError("write_register must be 2 bits")
        if not 0 <= inputs.write_data <= 0xFF:
            raise ValueError("write_data must be 8 bits")
        if not 0 <= inputs.mem_read_data <= 0xFF:
            raise ValueError("mem_read_data must be 8 bits")

    def clock(self, inputs: DmcInputs) -> tuple[DmcOutputs, DmcState]:
        self._validate(inputs)
        outputs = self.evaluate(inputs)
        if inputs.reset:
            self.reset_state()
            return outputs, self.state()
        if not inputs.cpu_cycle_enable:
            return outputs, self.state()
        if inputs.mem_acknowledge and not self.mem_request:
            raise AssertionError("DMC acknowledge without a held request")

        old_counter = self.timer_counter
        old_bits = self.bits_remaining
        old_silence = self.silence
        old_shift = self.shift_register
        old_empty = self.sample_buffer_empty
        old_buffer = self.sample_buffer
        old_request = self.mem_request
        old_remaining = self.bytes_remaining
        old_address = self.current_address
        output_reload = old_counter == 0 and old_bits == 1
        acknowledge_bypass = (
            inputs.mem_acknowledge and output_reload and old_empty
        )

        if old_counter == 0:
            self.timer_counter = self.timer_period - 1
            if not old_silence:
                if old_shift & 1 and self.output_level <= 125:
                    self.output_level += 2
                elif not (old_shift & 1) and self.output_level >= 2:
                    self.output_level -= 2

            if old_bits == 1:
                self.bits_remaining = 8
                if not old_empty:
                    self.shift_register = old_buffer
                    self.sample_buffer_empty = True
                    self.silence = False
                else:
                    self.shift_register = 0
                    self.silence = True
            else:
                self.bits_remaining = old_bits - 1
                self.shift_register = old_shift >> 1
        else:
            self.timer_counter = old_counter - 1

        if inputs.mem_acknowledge:
            self.mem_request = False
            self.current_address = 0x8000 if old_address == 0xFFFF else (
                old_address + 1
            )
            if acknowledge_bypass:
                self.shift_register = inputs.mem_read_data
                self.bits_remaining = 8
                self.silence = False
                self.sample_buffer_empty = True
            else:
                self.sample_buffer = inputs.mem_read_data
                self.sample_buffer_empty = False

            if old_remaining == 1:
                if self.loop:
                    self.current_address = dmc_sample_address(
                        self.sample_address_register
                    )
                    self.bytes_remaining = dmc_sample_length(
                        self.sample_length_register
                    )
                else:
                    self.bytes_remaining = 0
                    if self.irq_enable:
                        self.irq_flag = True
            elif old_remaining:
                self.bytes_remaining = old_remaining - 1
        elif not old_request and old_empty and old_remaining:
            self.mem_request = True
            self.mem_address = old_address

        if inputs.status_write:
            self.irq_flag = False
            if not inputs.enable:
                self.bytes_remaining = 0
                self.mem_request = False
            elif old_remaining == 0:
                self.current_address = dmc_sample_address(
                    self.sample_address_register
                )
                self.bytes_remaining = dmc_sample_length(
                    self.sample_length_register
                )
                if old_empty and not old_request:
                    self.mem_request = True
                    self.mem_address = dmc_sample_address(
                        self.sample_address_register
                    )

        if inputs.write:
            if inputs.write_register == 0:
                self.irq_enable = bool(inputs.write_data & 0x80)
                self.loop = bool(inputs.write_data & 0x40)
                self.rate_index = inputs.write_data & 0x0F
                if not inputs.write_data & 0x80:
                    self.irq_flag = False
            elif inputs.write_register == 1:
                self.output_level = inputs.write_data & 0x7F
            elif inputs.write_register == 2:
                self.sample_address_register = inputs.write_data
            else:
                self.sample_length_register = inputs.write_data

        assert 0 <= self.output_level <= 127
        assert 1 <= self.bits_remaining <= 8
        assert 0 <= self.bytes_remaining <= 4081
        return outputs, self.state()


@dataclass(frozen=True)
class ApuInputs:
    """Signals presented for one fabric cycle.

    ``cpu_cycle_enable`` is the repository's complete NES CPU-time slot,
    rather than an instruction-retirement or CPU-core execution indication.
    """

    reset: bool = False
    cpu_cycle_enable: bool = False
    cpu_read: bool = False
    cpu_write: bool = False
    cpu_address: int = 0
    cpu_write_data: int = 0
    channel_active: int = 0
    dmc_irq_flag: bool = False
    dmc_mem_acknowledge: bool = False
    dmc_mem_read_data: int = 0


@dataclass(frozen=True)
class ApuOutputs:
    cpu_read_data: int
    irq: bool
    pulse1_output: int
    pulse2_output: int
    triangle_output: int
    noise_output: int
    quarter_frame_tick: bool
    half_frame_tick: bool
    channel_write: bool
    channel_write_register: int
    channel_write_data: int
    dmc_irq_clear: bool
    dmc_output: int
    dmc_mem_request: bool
    dmc_mem_address: int


@dataclass(frozen=True)
class ApuState:
    channel_enable: int
    mode_5_step: bool
    irq_inhibit: bool
    frame_irq_flag: bool
    frame_sequence_cycle: int
    cpu_cycle_odd: bool
    frame_reset_pending: bool
    frame_reset_delay: int
    frame_tick_block: bool


class ApuFoundationModel:
    """Executable specification of register and frame-counter behavior."""

    def __init__(self) -> None:
        self.pulse1 = Pulse1Model()
        self.pulse2 = Pulse2Model()
        self.triangle = TriangleModel()
        self.noise = NoiseModel()
        self.dmc = DmcModel()
        self.reset_state()

    def reset_state(self) -> None:
        self.pulse1.reset_state()
        self.pulse2.reset_state()
        self.triangle.reset_state()
        self.noise.reset_state()
        self.dmc.reset_state()
        self.channel_enable = 0
        self.mode_5_step = False
        self.irq_inhibit = False
        self.frame_irq_flag = False
        self.frame_sequence_cycle = 0
        self.cpu_cycle_odd = False
        self.frame_reset_pending = False
        self.frame_reset_delay = 0
        self.pending_mode_5_step = False
        self.frame_tick_block = False

    def state(self) -> ApuState:
        return ApuState(
            channel_enable=self.channel_enable,
            mode_5_step=self.mode_5_step,
            irq_inhibit=self.irq_inhibit,
            frame_irq_flag=self.frame_irq_flag,
            frame_sequence_cycle=self.frame_sequence_cycle,
            cpu_cycle_odd=self.cpu_cycle_odd,
            frame_reset_pending=self.frame_reset_pending,
            frame_reset_delay=self.frame_reset_delay,
            frame_tick_block=self.frame_tick_block,
        )

    @staticmethod
    def _validate(inputs: ApuInputs) -> None:
        if not 0 <= inputs.cpu_address <= 0xFFFF:
            raise ValueError("cpu_address must be 16 bits")
        if not 0 <= inputs.cpu_write_data <= 0xFF:
            raise ValueError("cpu_write_data must be 8 bits")
        if not 0 <= inputs.channel_active <= 0x1F:
            raise ValueError("channel_active must be 5 bits")
        if not 0 <= inputs.dmc_mem_read_data <= 0xFF:
            raise ValueError("dmc_mem_read_data must be 8 bits")

    def evaluate(self, inputs: ApuInputs) -> ApuOutputs:
        """Evaluate event outputs from the state immediately before the edge."""

        self._validate(inputs)
        accepted_read = (
            not inputs.reset and inputs.cpu_cycle_enable and inputs.cpu_read
        )
        accepted_write = (
            not inputs.reset and inputs.cpu_cycle_enable and inputs.cpu_write
        )
        status_read = accepted_read and inputs.cpu_address == APU_STATUS
        status_write = accepted_write and inputs.cpu_address == APU_STATUS
        frame_write = accepted_write and inputs.cpu_address == APU_FRAME_COUNTER
        channel_write = (
            accepted_write
            and APU_CHANNEL_FIRST <= inputs.cpu_address <= APU_CHANNEL_LAST
        )

        apply_reset = (
            not inputs.reset
            and inputs.cpu_cycle_enable
            and self.frame_reset_pending
            and self.frame_reset_delay == 1
            and not frame_write
        )
        next_cycle = (self.frame_sequence_cycle + 1) & 0xFFFF

        scheduled_quarter = False
        scheduled_half = False
        if not inputs.reset and inputs.cpu_cycle_enable:
            scheduled_quarter = next_cycle in (QUARTER_1, HALF_1, QUARTER_3)
            if self.mode_5_step:
                scheduled_quarter = scheduled_quarter or next_cycle == FIVE_STEP_HALF
                scheduled_half = next_cycle in (HALF_1, FIVE_STEP_HALF)
            else:
                scheduled_quarter = scheduled_quarter or next_cycle == FOUR_STEP_HALF
                scheduled_half = next_cycle in (HALF_1, FOUR_STEP_HALF)

        quarter = (
            scheduled_quarter
            and not apply_reset
            and not self.frame_tick_block
        )
        half = scheduled_half and not apply_reset and not self.frame_tick_block
        delayed_five_step_tick = (
            apply_reset
            and self.pending_mode_5_step
            and not scheduled_quarter
            and not self.frame_tick_block
        )
        quarter = quarter or delayed_five_step_tick
        half = half or delayed_five_step_tick

        effective_inhibit = (
            bool(inputs.cpu_write_data & 0x40) if frame_write else self.irq_inhibit
        )
        irq_set = (
            not inputs.reset
            and inputs.cpu_cycle_enable
            and not apply_reset
            and not self.mode_5_step
            and not effective_inhibit
            and next_cycle in (FOUR_STEP_IRQ_1, FOUR_STEP_HALF, FOUR_STEP_END)
        )

        dmc_outputs = self.dmc.evaluate(DmcInputs(reset=inputs.reset))
        read_data = 0
        if status_read:
            pulse1_active = int(self.pulse1.evaluate(bool(self.channel_enable & 1)).active)
            pulse2_active = int(self.pulse2.evaluate(bool(self.channel_enable & 2)).active)
            triangle_active = int(self.triangle.evaluate().active)
            noise_active = int(self.noise.evaluate(bool(self.channel_enable & 8)).active)
            read_data = (
                ((int(dmc_outputs.active) | ((inputs.channel_active >> 4) & 1)) << 4)
                | (noise_active << 3)
                | (triangle_active << 2)
                | (pulse2_active << 1)
                | pulse1_active
            )
            read_data |= int(self.frame_irq_flag or irq_set) << 6
            read_data |= int(inputs.dmc_irq_flag or dmc_outputs.irq_flag) << 7

        effective_pulse1_enable = (
            bool(inputs.cpu_write_data & 0x01)
            if status_write
            else bool(self.channel_enable & 0x01)
        )
        effective_pulse2_enable = (
            bool(inputs.cpu_write_data & 0x02)
            if status_write
            else bool(self.channel_enable & 0x02)
        )
        effective_noise_enable = (
            bool(inputs.cpu_write_data & 0x08)
            if status_write
            else bool(self.channel_enable & 0x08)
        )
        return ApuOutputs(
            cpu_read_data=read_data,
            irq=(
                not inputs.reset
                and (self.frame_irq_flag or irq_set or dmc_outputs.irq_flag)
            ),
            pulse1_output=self.pulse1.evaluate(effective_pulse1_enable).raw_output,
            pulse2_output=self.pulse2.evaluate(effective_pulse2_enable).raw_output,
            triangle_output=self.triangle.evaluate().raw_output,
            noise_output=self.noise.evaluate(effective_noise_enable).raw_output,
            quarter_frame_tick=quarter,
            half_frame_tick=half,
            channel_write=channel_write,
            channel_write_register=inputs.cpu_address & 0x1F,
            channel_write_data=inputs.cpu_write_data,
            dmc_irq_clear=status_write,
            dmc_output=dmc_outputs.raw_output,
            dmc_mem_request=dmc_outputs.mem_request,
            dmc_mem_address=dmc_outputs.mem_address,
        )

    def clock(self, inputs: ApuInputs) -> tuple[ApuOutputs, ApuState]:
        """Evaluate one cycle, apply its edge, and return outputs and new state."""

        outputs = self.evaluate(inputs)
        status_write = (
            not inputs.reset
            and inputs.cpu_cycle_enable
            and inputs.cpu_write
            and inputs.cpu_address == APU_STATUS
        )
        effective_pulse1_enable = (
            bool(inputs.cpu_write_data & 0x01)
            if status_write
            else bool(self.channel_enable & 0x01)
        )
        effective_pulse2_enable = (
            bool(inputs.cpu_write_data & 0x02)
            if status_write
            else bool(self.channel_enable & 0x02)
        )
        effective_triangle_enable = (
            bool(inputs.cpu_write_data & 0x04)
            if status_write
            else bool(self.channel_enable & 0x04)
        )
        effective_noise_enable = (
            bool(inputs.cpu_write_data & 0x08)
            if status_write
            else bool(self.channel_enable & 0x08)
        )
        effective_dmc_enable = (
            bool(inputs.cpu_write_data & 0x10)
            if status_write
            else bool(self.channel_enable & 0x10)
        )
        self.pulse1.clock(
            PulseInputs(
                reset=inputs.reset,
                cpu_cycle_enable=inputs.cpu_cycle_enable,
                timer_tick=(
                    inputs.cpu_cycle_enable and not self.cpu_cycle_odd
                ),
                enable=effective_pulse1_enable,
                write=(
                    outputs.channel_write
                    and outputs.channel_write_register <= 0x03
                ),
                write_register=outputs.channel_write_register & 0x03,
                write_data=outputs.channel_write_data,
                quarter_frame_tick=outputs.quarter_frame_tick,
                half_frame_tick=outputs.half_frame_tick,
            )
        )
        self.pulse2.clock(
            PulseInputs(
                reset=inputs.reset,
                cpu_cycle_enable=inputs.cpu_cycle_enable,
                timer_tick=(
                    inputs.cpu_cycle_enable and not self.cpu_cycle_odd
                ),
                enable=effective_pulse2_enable,
                write=(
                    outputs.channel_write
                    and 0x04 <= outputs.channel_write_register <= 0x07
                ),
                write_register=outputs.channel_write_register & 0x03,
                write_data=outputs.channel_write_data,
                quarter_frame_tick=outputs.quarter_frame_tick,
                half_frame_tick=outputs.half_frame_tick,
            )
        )
        self.triangle.clock(
            TriangleInputs(
                reset=inputs.reset,
                cpu_cycle_enable=inputs.cpu_cycle_enable,
                enable=effective_triangle_enable,
                write=(
                    outputs.channel_write
                    and 0x08 <= outputs.channel_write_register <= 0x0B
                ),
                write_register=outputs.channel_write_register & 0x03,
                write_data=outputs.channel_write_data,
                quarter_frame_tick=outputs.quarter_frame_tick,
                half_frame_tick=outputs.half_frame_tick,
            )
        )
        self.noise.clock(
            NoiseInputs(
                reset=inputs.reset,
                cpu_cycle_enable=inputs.cpu_cycle_enable,
                timer_tick=(
                    inputs.cpu_cycle_enable and not self.cpu_cycle_odd
                ),
                enable=effective_noise_enable,
                write=(
                    outputs.channel_write
                    and 0x0C <= outputs.channel_write_register <= 0x0F
                ),
                write_register=outputs.channel_write_register & 0x03,
                write_data=outputs.channel_write_data,
                quarter_frame_tick=outputs.quarter_frame_tick,
                half_frame_tick=outputs.half_frame_tick,
            )
        )
        self.dmc.clock(
            DmcInputs(
                reset=inputs.reset,
                cpu_cycle_enable=inputs.cpu_cycle_enable,
                enable=effective_dmc_enable,
                status_write=status_write,
                write=(
                    outputs.channel_write
                    and 0x10 <= outputs.channel_write_register <= 0x13
                ),
                write_register=outputs.channel_write_register & 0x03,
                write_data=outputs.channel_write_data,
                mem_acknowledge=inputs.dmc_mem_acknowledge,
                mem_read_data=inputs.dmc_mem_read_data,
            )
        )
        if inputs.reset:
            self.reset_state()
            return outputs, self.state()
        if not inputs.cpu_cycle_enable:
            return outputs, self.state()

        accepted_read = inputs.cpu_read
        accepted_write = inputs.cpu_write
        status_read = accepted_read and inputs.cpu_address == APU_STATUS
        status_write = accepted_write and inputs.cpu_address == APU_STATUS
        frame_write = accepted_write and inputs.cpu_address == APU_FRAME_COUNTER
        apply_reset = (
            self.frame_reset_pending
            and self.frame_reset_delay == 1
            and not frame_write
        )
        next_cycle = (self.frame_sequence_cycle + 1) & 0xFFFF
        effective_inhibit = (
            bool(inputs.cpu_write_data & 0x40) if frame_write else self.irq_inhibit
        )
        irq_set = (
            not apply_reset
            and not self.mode_5_step
            and not effective_inhibit
            and next_cycle in (FOUR_STEP_IRQ_1, FOUR_STEP_HALF, FOUR_STEP_END)
        )

        old_cycle_odd = self.cpu_cycle_odd
        self.cpu_cycle_odd = not self.cpu_cycle_odd
        self.frame_tick_block = outputs.quarter_frame_tick

        if apply_reset:
            self.mode_5_step = self.pending_mode_5_step
            self.frame_sequence_cycle = 0
        elif (
            not self.mode_5_step and next_cycle == FOUR_STEP_END
        ) or (
            self.mode_5_step and next_cycle == FIVE_STEP_END
        ):
            self.frame_sequence_cycle = 0
        else:
            self.frame_sequence_cycle = next_cycle

        if frame_write:
            self.pending_mode_5_step = bool(inputs.cpu_write_data & 0x80)
            self.frame_reset_pending = True
            self.frame_reset_delay = 4 if old_cycle_odd else 3
            self.irq_inhibit = bool(inputs.cpu_write_data & 0x40)
        elif self.frame_reset_pending:
            if self.frame_reset_delay == 1:
                self.frame_reset_pending = False
                self.frame_reset_delay = 0
            else:
                self.frame_reset_delay -= 1

        if status_write:
            self.channel_enable = inputs.cpu_write_data & 0x1F

        if frame_write and inputs.cpu_write_data & 0x40:
            self.frame_irq_flag = False
        elif irq_set:
            self.frame_irq_flag = True
        elif status_read:
            self.frame_irq_flag = False

        return outputs, self.state()
