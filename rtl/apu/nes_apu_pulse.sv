`timescale 1ns/1ps

// Reusable NES pulse-channel datapath. CHANNEL_ONE keeps Pulse 1's
// one's-complement sweep-negate quirk explicit; Pulse 2 selects the distinct
// two's-complement behavior without duplicating the channel implementation.
module nes_apu_pulse #(
    parameter bit CHANNEL_ONE = 1'b1
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_cycle_enable,
    input  logic        timer_tick,
    input  logic        enable,

    input  logic        write,
    input  logic [1:0]  write_register,
    input  logic [7:0]  write_data,
    input  logic        quarter_frame_tick,
    input  logic        half_frame_tick,

    output logic        active,
    output logic [3:0]  raw_output,

    // Architectural state is exposed for deterministic model comparison.
    output logic [1:0]  duty,
    output logic [2:0]  duty_position,
    output logic [10:0] timer_period,
    output logic [10:0] timer_counter,
    output logic [7:0]  length_counter,
    output logic        length_halt,
    output logic        constant_volume,
    output logic [3:0]  envelope_period,
    output logic        envelope_start,
    output logic [3:0]  envelope_divider,
    output logic [3:0]  envelope_decay,
    output logic        sweep_enabled,
    output logic [2:0]  sweep_period,
    output logic        sweep_negate,
    output logic [2:0]  sweep_shift,
    output logic        sweep_reload,
    output logic [2:0]  sweep_divider,
    output logic [11:0] sweep_target,
    output logic        sweep_mute
);
    import nes_apu_pkg::*;

    logic [10:0] sweep_change;
    logic duty_output;
    logic [3:0] selected_volume;
    logic pulse_write_0;
    logic pulse_write_1;
    logic pulse_write_2;
    logic pulse_write_3;

    assign pulse_write_0 = write && write_register == 2'd0;
    assign pulse_write_1 = write && write_register == 2'd1;
    assign pulse_write_2 = write && write_register == 2'd2;
    assign pulse_write_3 = write && write_register == 2'd3;

    assign sweep_change = timer_period >> sweep_shift;
    always_comb begin
        if (sweep_negate) begin
            sweep_target = {1'b0, timer_period} -
                           {1'b0, sweep_change} -
                           {{11{1'b0}}, CHANNEL_ONE};
        end else begin
            sweep_target = {1'b0, timer_period} +
                           {1'b0, sweep_change};
        end
    end

    // A negative sweep cannot overflow upward for an otherwise audible
    // period. Positive target overflow and raw periods below 8 mute even if
    // sweep updates themselves are disabled.
    assign sweep_mute = timer_period < 11'd8 ||
                        (!sweep_negate && sweep_target > 12'h7FF);
    assign duty_output = APU_PULSE_DUTY_TABLE[duty][duty_position];
    assign selected_volume = constant_volume ? envelope_period :
                             envelope_decay;
    assign active = length_counter != 8'd0;
    assign raw_output = enable && active && duty_output && !sweep_mute ?
                        selected_volume : 4'd0;

    always_ff @(posedge clk) begin
        if (reset) begin
            duty              <= 2'd0;
            duty_position     <= 3'd0;
            timer_period      <= 11'd0;
            timer_counter     <= 11'd0;
            length_counter    <= 8'd0;
            length_halt       <= 1'b0;
            constant_volume   <= 1'b0;
            envelope_period   <= 4'd0;
            envelope_start    <= 1'b0;
            envelope_divider  <= 4'd0;
            envelope_decay    <= 4'd0;
            sweep_enabled     <= 1'b0;
            sweep_period      <= 3'd0;
            sweep_negate      <= 1'b0;
            sweep_shift       <= 3'd0;
            sweep_reload      <= 1'b0;
            sweep_divider     <= 3'd0;
        end else if (cpu_cycle_enable) begin
            // The pulse timer is clocked on every other CPU slot. Register
            // writes update the reload value but do not reset its divider.
            if (timer_tick) begin
                if (timer_counter == 11'd0) begin
                    timer_counter <= timer_period;
                    duty_position <= duty_position - 3'd1;
                end else begin
                    timer_counter <= timer_counter - 11'd1;
                end
            end

            if (quarter_frame_tick) begin
                if (envelope_start) begin
                    envelope_start   <= 1'b0;
                    envelope_decay   <= 4'd15;
                    envelope_divider <= envelope_period;
                end else if (envelope_divider == 4'd0) begin
                    envelope_divider <= envelope_period;
                    if (envelope_decay != 4'd0)
                        envelope_decay <= envelope_decay - 4'd1;
                    else if (length_halt)
                        envelope_decay <= 4'd15;
                end else begin
                    envelope_divider <= envelope_divider - 4'd1;
                end
            end

            if (half_frame_tick) begin
                if (length_counter != 8'd0 && !length_halt)
                    length_counter <= length_counter - 8'd1;

                if (sweep_divider == 3'd0) begin
                    if (sweep_enabled && sweep_shift != 3'd0 &&
                        timer_period >= 11'd8 &&
                        sweep_target <= 12'h7FF) begin
                        timer_period <= sweep_target[10:0];
                    end
                    sweep_divider <= sweep_period;
                end else begin
                    sweep_divider <= sweep_divider - 3'd1;
                end

                if (sweep_reload) begin
                    sweep_divider <= sweep_period;
                    sweep_reload <= 1'b0;
                end
            end

            if (pulse_write_0) begin
                duty            <= write_data[7:6];
                length_halt     <= write_data[5];
                constant_volume <= write_data[4];
                envelope_period <= write_data[3:0];
            end

            if (pulse_write_1) begin
                sweep_enabled <= write_data[7];
                sweep_period  <= write_data[6:4];
                sweep_negate  <= write_data[3];
                sweep_shift   <= write_data[2:0];
                sweep_reload  <= 1'b1;
            end

            if (pulse_write_2)
                timer_period[7:0] <= write_data;

            if (pulse_write_3) begin
                timer_period[10:8] <= write_data[2:0];
                duty_position <= 3'd0;
                envelope_start <= 1'b1;
                if (enable)
                    length_counter <= APU_LENGTH_TABLE[write_data[7:3]];
            end

            // $4015 disable has final priority over length clocks and loads.
            if (!enable)
                length_counter <= 8'd0;
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (!half_frame_tick || quarter_frame_tick);
    end
`endif
endmodule
