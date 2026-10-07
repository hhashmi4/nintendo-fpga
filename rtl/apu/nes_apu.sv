`timescale 1ns/1ps

// NES APU foundation plus both pulse, triangle, and Noise channels. All state
// is in the fabric clock domain and advances only on cpu_cycle_enable, the
// complete NES CPU-time slot stream including OAM-DMA stalls. Accepted bus
// strobes remain CPU-only.
module nes_apu (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_cycle_enable,

    input  logic        cpu_read,
    input  logic        cpu_write,
    input  logic [15:0] cpu_address,
    input  logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,

    // Bit 4 remains an external placeholder for the future DMC. Noise,
    // Triangle, and both pulse channels own bits 3:0 internally.
    /* verilator lint_off UNUSEDSIGNAL */
    input  nes_apu_pkg::nes_apu_channel_mask_t channel_active,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        dmc_irq_flag,
    output nes_apu_pkg::nes_apu_channel_mask_t channel_enable,

    // Exactly-once write event shared by the channel modules.
    output logic        channel_write,
    output logic [4:0]  channel_write_register,
    output logic [7:0]  channel_write_data,
    output logic        dmc_irq_clear,

    output logic        quarter_frame_tick,
    output logic        half_frame_tick,
    output logic        irq,
    output logic [3:0]  pulse1_output,
    output logic [3:0]  pulse2_output,
    output logic [3:0]  triangle_output,
    output logic [3:0]  noise_output,

    // Architectural/debug state used by verification and future snapshots.
    output nes_apu_pkg::nes_apu_frame_mode_t frame_mode,
    output logic        frame_irq_inhibit,
    output logic        frame_irq_flag,
    output logic [15:0] frame_sequence_cycle,
    output logic        cpu_cycle_odd,
    output logic        frame_reset_pending,
    output logic [2:0]  frame_reset_delay,
    output logic        frame_tick_block
);
    import nes_apu_pkg::*;

    logic pending_frame_mode;
    logic [15:0] next_frame_cycle;
    logic accepted_read;
    logic accepted_write;
    logic status_read;
    logic status_write;
    logic frame_control_write;
    logic frame_reset_apply;
    logic natural_quarter_tick;
    logic natural_half_tick;
    logic scheduled_quarter_tick;
    logic scheduled_half_tick;
    logic delayed_five_step_tick;
    logic frame_irq_set_event;
    logic effective_irq_inhibit;
    logic pulse1_active;
    logic pulse1_enable;
    logic pulse2_active;
    logic pulse2_enable;
    logic triangle_active;
    logic triangle_enable;
    logic noise_active;
    logic noise_enable;
    logic pulse_timer_tick;
    nes_apu_channel_mask_t effective_channel_active;

    assign accepted_read = !reset && cpu_cycle_enable && cpu_read;
    assign accepted_write = !reset && cpu_cycle_enable && cpu_write;
    assign status_read = accepted_read &&
                         cpu_address == APU_STATUS_REGISTER;
    assign status_write = accepted_write &&
                          cpu_address == APU_STATUS_REGISTER;
    assign frame_control_write = accepted_write &&
                                 cpu_address == APU_FRAME_COUNTER_REGISTER;

    assign channel_write = accepted_write &&
                           cpu_address >= APU_REGISTER_FIRST &&
                           cpu_address <= APU_CHANNEL_REGISTER_LAST;
    assign channel_write_register = cpu_address[4:0];
    assign channel_write_data = cpu_write_data;
    // A future DMC consumes this pulse to clear its own IRQ latch.
    assign dmc_irq_clear = status_write;

    // A $4015 write affects all implemented channels on its accepted CPU edge
    // rather than one slot later. The stored mask remains visible state.
    assign pulse1_enable = status_write ? cpu_write_data[0] :
                           channel_enable[APU_STATUS_PULSE1_BIT];
    assign pulse2_enable = status_write ? cpu_write_data[1] :
                           channel_enable[APU_STATUS_PULSE2_BIT];
    assign triangle_enable = status_write ? cpu_write_data[2] :
                             channel_enable[APU_STATUS_TRIANGLE_BIT];
    assign noise_enable = status_write ? cpu_write_data[3] :
                          channel_enable[APU_STATUS_NOISE_BIT];
    assign pulse_timer_tick = cpu_cycle_enable && !cpu_cycle_odd;
    assign effective_channel_active = {
        channel_active[4], noise_active, triangle_active,
        pulse2_active, pulse1_active
    };

    assign next_frame_cycle = frame_sequence_cycle + 16'd1;
    // A newer write supersedes a pending value on the same CPU cycle.
    assign frame_reset_apply = !reset && cpu_cycle_enable &&
                               frame_reset_pending &&
                               frame_reset_delay == 3'd1 &&
                               !frame_control_write;

    always_comb begin
        scheduled_quarter_tick = 1'b0;
        scheduled_half_tick = 1'b0;
        if (!reset && cpu_cycle_enable) begin
            if (next_frame_cycle == APU_NTSC_QUARTER_1 ||
                next_frame_cycle == APU_NTSC_HALF_1 ||
                next_frame_cycle == APU_NTSC_QUARTER_3) begin
                scheduled_quarter_tick = 1'b1;
            end else if (frame_mode == NES_APU_FRAME_MODE_4_STEP &&
                         next_frame_cycle == APU_NTSC_4STEP_HALF) begin
                scheduled_quarter_tick = 1'b1;
            end else if (frame_mode == NES_APU_FRAME_MODE_5_STEP &&
                         next_frame_cycle == APU_NTSC_5STEP_HALF) begin
                scheduled_quarter_tick = 1'b1;
            end

            if (next_frame_cycle == APU_NTSC_HALF_1 ||
                (frame_mode == NES_APU_FRAME_MODE_4_STEP &&
                 next_frame_cycle == APU_NTSC_4STEP_HALF) ||
                (frame_mode == NES_APU_FRAME_MODE_5_STEP &&
                 next_frame_cycle == APU_NTSC_5STEP_HALF)) begin
                scheduled_half_tick = 1'b1;
            end
        end
    end

    // Hardware prevents two clocks of the controlled units on adjacent CPU
    // cycles. This matters when a delayed 5-step application lands one cycle
    // after a natural frame event.
    assign natural_quarter_tick = scheduled_quarter_tick &&
                                  !frame_reset_apply && !frame_tick_block;
    assign natural_half_tick = scheduled_half_tick &&
                               !frame_reset_apply && !frame_tick_block;
    assign delayed_five_step_tick = frame_reset_apply && pending_frame_mode &&
                                    !scheduled_quarter_tick &&
                                    !frame_tick_block;

    // In 5-step mode the delayed $4017 application clocks both units. These
    // are single-fabric-cycle event pulses because cpu_cycle_enable is itself
    // a one-cycle strobe.
    assign quarter_frame_tick = natural_quarter_tick || delayed_five_step_tick;
    assign half_frame_tick = natural_half_tick || delayed_five_step_tick;

    // IRQ inhibit changes on the write cycle, before the delayed sequence
    // reset and mode change.
    assign effective_irq_inhibit = frame_control_write ?
                                   cpu_write_data[6] : frame_irq_inhibit;
    assign frame_irq_set_event = !reset && cpu_cycle_enable &&
        !frame_reset_apply &&
        frame_mode == NES_APU_FRAME_MODE_4_STEP &&
        !effective_irq_inhibit &&
        (next_frame_cycle == APU_NTSC_4STEP_IRQ_1 ||
         next_frame_cycle == APU_NTSC_4STEP_HALF ||
         next_frame_cycle == APU_NTSC_4STEP_END);

    // Include the current terminal-cycle event combinationally so a $4015
    // read on the same CPU cycle observes bit 6. The sequential set then wins
    // over the read-clear side effect, matching the hardware behavior.
    always_comb begin
        cpu_read_data = 8'h00;
        if (status_read) begin
            cpu_read_data[4:0] = effective_channel_active;
            cpu_read_data[5] = 1'b0; // project-wide open-bus simplification
            cpu_read_data[APU_STATUS_FRAME_IRQ_BIT] =
                frame_irq_flag || frame_irq_set_event;
            cpu_read_data[APU_STATUS_DMC_IRQ_BIT] = dmc_irq_flag;
        end
    end

    // Phase 5A exposes only the implemented frame IRQ at this boundary. The
    // future DMC phase will OR its owned IRQ latch into this expression.
    assign irq = !reset && (frame_irq_flag || frame_irq_set_event);

    /* verilator lint_off PINCONNECTEMPTY */
    nes_apu_pulse #(
        .CHANNEL_ONE(1'b1)
    ) pulse1 (
        .clk(clk),
        .reset(reset),
        .cpu_cycle_enable(cpu_cycle_enable),
        .timer_tick(pulse_timer_tick),
        .enable(pulse1_enable),
        .write(channel_write && channel_write_register[4:2] == 3'd0),
        .write_register(channel_write_register[1:0]),
        .write_data(channel_write_data),
        .quarter_frame_tick(quarter_frame_tick),
        .half_frame_tick(half_frame_tick),
        .active(pulse1_active),
        .raw_output(pulse1_output),
        .duty(),
        .duty_position(),
        .timer_period(),
        .timer_counter(),
        .length_counter(),
        .length_halt(),
        .constant_volume(),
        .envelope_period(),
        .envelope_start(),
        .envelope_divider(),
        .envelope_decay(),
        .sweep_enabled(),
        .sweep_period(),
        .sweep_negate(),
        .sweep_shift(),
        .sweep_reload(),
        .sweep_divider(),
        .sweep_target(),
        .sweep_mute()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_apu_pulse #(
        .CHANNEL_ONE(1'b0)
    ) pulse2 (
        .clk(clk),
        .reset(reset),
        .cpu_cycle_enable(cpu_cycle_enable),
        .timer_tick(pulse_timer_tick),
        .enable(pulse2_enable),
        .write(channel_write && channel_write_register[4:2] == 3'd1),
        .write_register(channel_write_register[1:0]),
        .write_data(channel_write_data),
        .quarter_frame_tick(quarter_frame_tick),
        .half_frame_tick(half_frame_tick),
        .active(pulse2_active),
        .raw_output(pulse2_output),
        .duty(),
        .duty_position(),
        .timer_period(),
        .timer_counter(),
        .length_counter(),
        .length_halt(),
        .constant_volume(),
        .envelope_period(),
        .envelope_start(),
        .envelope_divider(),
        .envelope_decay(),
        .sweep_enabled(),
        .sweep_period(),
        .sweep_negate(),
        .sweep_shift(),
        .sweep_reload(),
        .sweep_divider(),
        .sweep_target(),
        .sweep_mute()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_apu_triangle triangle (
        .clk(clk),
        .reset(reset),
        .cpu_cycle_enable(cpu_cycle_enable),
        .enable(triangle_enable),
        .write(channel_write && channel_write_register[4:2] == 3'd2),
        .write_register(channel_write_register[1:0]),
        .write_data(channel_write_data),
        .quarter_frame_tick(quarter_frame_tick),
        .half_frame_tick(half_frame_tick),
        .active(triangle_active),
        .raw_output(triangle_output),
        .control_flag(),
        .linear_reload_value(),
        .linear_counter(),
        .linear_reload_flag(),
        .sequence_position(),
        .timer_period(),
        .timer_counter(),
        .length_counter()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_apu_noise noise (
        .clk(clk),
        .reset(reset),
        .cpu_cycle_enable(cpu_cycle_enable),
        .timer_tick(pulse_timer_tick),
        .quarter_frame_tick(quarter_frame_tick),
        .half_frame_tick(half_frame_tick),
        .enable(noise_enable),
        .write(channel_write && channel_write_register[4:2] == 3'd3),
        .write_register(channel_write_register[1:0]),
        .write_data(channel_write_data),
        .active(noise_active),
        .raw_output(noise_output),
        .length_halt(),
        .constant_volume(),
        .envelope_period(),
        .envelope_start(),
        .envelope_divider(),
        .envelope_decay(),
        .mode(),
        .period_index(),
        .timer_period(),
        .timer_counter(),
        .length_counter(),
        .lfsr()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_ff @(posedge clk) begin
        if (reset) begin
            channel_enable       <= '0;
            frame_mode           <= NES_APU_FRAME_MODE_4_STEP;
            frame_irq_inhibit    <= 1'b0;
            frame_irq_flag       <= 1'b0;
            frame_sequence_cycle <= 16'd0;
            cpu_cycle_odd        <= 1'b0;
            frame_reset_pending  <= 1'b0;
            frame_reset_delay    <= 3'd0;
            pending_frame_mode    <= NES_APU_FRAME_MODE_4_STEP;
            frame_tick_block      <= 1'b0;
        end else if (cpu_cycle_enable) begin
            cpu_cycle_odd <= !cpu_cycle_odd;
            // Any emitted quarter/half event blocks the immediately following
            // CPU slot, then expires. Half ticks always include quarter ticks.
            frame_tick_block <= quarter_frame_tick;

            if (frame_reset_apply) begin
                frame_mode <= pending_frame_mode ?
                    NES_APU_FRAME_MODE_5_STEP :
                    NES_APU_FRAME_MODE_4_STEP;
                frame_sequence_cycle <= 16'd0;
            end else if (frame_mode == NES_APU_FRAME_MODE_4_STEP &&
                         next_frame_cycle == APU_NTSC_4STEP_END) begin
                frame_sequence_cycle <= 16'd0;
            end else if (frame_mode == NES_APU_FRAME_MODE_5_STEP &&
                         next_frame_cycle == APU_NTSC_5STEP_END) begin
                frame_sequence_cycle <= 16'd0;
            end else begin
                frame_sequence_cycle <= next_frame_cycle;
            end

            if (frame_control_write) begin
                pending_frame_mode <= cpu_write_data[7];
                frame_reset_pending <= 1'b1;
                // Writes during an APU/even cycle apply after three later CPU
                // cycles; between APU cycles they apply after four.
                frame_reset_delay <= cpu_cycle_odd ? 3'd4 : 3'd3;
                frame_irq_inhibit <= cpu_write_data[6];
            end else if (frame_reset_pending) begin
                if (frame_reset_delay == 3'd1) begin
                    frame_reset_pending <= 1'b0;
                    frame_reset_delay <= 3'd0;
                end else begin
                    frame_reset_delay <= frame_reset_delay - 3'd1;
                end
            end

            if (status_write)
                channel_enable <= cpu_write_data[4:0];

            // Immediate inhibit/clear has priority. Otherwise an IRQ set on
            // this cycle wins over a simultaneous $4015 read-clear.
            if (frame_control_write && cpu_write_data[6])
                frame_irq_flag <= 1'b0;
            else if (frame_irq_set_event)
                frame_irq_flag <= 1'b1;
            else if (status_read)
                frame_irq_flag <= 1'b0;
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (!(channel_write && (status_write || frame_control_write)));
        assert (!(half_frame_tick && !quarter_frame_tick));
        assert (frame_reset_delay <= 3'd4);
        if (reset) begin
            assert (!channel_write && !dmc_irq_clear);
            assert (!quarter_frame_tick && !half_frame_tick && !irq);
            assert (cpu_read_data == 8'h00);
        end
    end
`endif
endmodule
