"""Independent cycle model for the NTSC NES APU foundation and pulse channels."""

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


def pulse_sequence_cpu_cycles(timer_period: int) -> int:
    """Return CPU cycles in one complete eight-step pulse waveform."""

    if not 0 <= timer_period <= 0x7FF:
        raise ValueError("timer_period must be 11 bits")
    return 16 * (timer_period + 1)


def pulse_frequency_hz(timer_period: int, cpu_hz: float = 1_789_773.0) -> float:
    """Human-readable NTSC frequency; no floating point is used by RTL."""

    return cpu_hz / pulse_sequence_cpu_cycles(timer_period)


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


@dataclass(frozen=True)
class ApuOutputs:
    cpu_read_data: int
    irq: bool
    pulse1_output: int
    pulse2_output: int
    quarter_frame_tick: bool
    half_frame_tick: bool
    channel_write: bool
    channel_write_register: int
    channel_write_data: int
    dmc_irq_clear: bool


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
        self.reset_state()

    def reset_state(self) -> None:
        self.pulse1.reset_state()
        self.pulse2.reset_state()
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

        read_data = 0
        if status_read:
            pulse1_active = int(self.pulse1.evaluate(bool(self.channel_enable & 1)).active)
            pulse2_active = int(self.pulse2.evaluate(bool(self.channel_enable & 2)).active)
            read_data = (
                (inputs.channel_active & 0x1C)
                | (pulse2_active << 1)
                | pulse1_active
            )
            read_data |= int(self.frame_irq_flag or irq_set) << 6
            read_data |= int(inputs.dmc_irq_flag) << 7

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

        return ApuOutputs(
            cpu_read_data=read_data,
            irq=not inputs.reset and (self.frame_irq_flag or irq_set),
            pulse1_output=self.pulse1.evaluate(effective_pulse1_enable).raw_output,
            pulse2_output=self.pulse2.evaluate(effective_pulse2_enable).raw_output,
            quarter_frame_tick=quarter,
            half_frame_tick=half,
            channel_write=channel_write,
            channel_write_register=inputs.cpu_address & 0x1F,
            channel_write_data=inputs.cpu_write_data,
            dmc_irq_clear=status_write,
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
