"""Independent cycle model for the Phase 5A NTSC NES APU foundation."""

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
        self.reset_state()

    def reset_state(self) -> None:
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
            read_data = inputs.channel_active & 0x1F
            read_data |= int(self.frame_irq_flag or irq_set) << 6
            read_data |= int(inputs.dmc_irq_flag) << 7

        return ApuOutputs(
            cpu_read_data=read_data,
            irq=not inputs.reset and (self.frame_irq_flag or irq_set),
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
