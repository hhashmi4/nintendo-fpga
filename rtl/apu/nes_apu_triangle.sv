`timescale 1ns/1ps

// NES triangle-channel datapath. Unlike the pulse channels, its timer clocks
// on every CPU slot and its DAC keeps the current sequencer value whenever
// either counter gates advancement. Periods 0 and 1 remain digitally active;
// any ultrasonic filtering belongs to a later output stage.
module nes_apu_triangle (
    input  logic       clk,
    input  logic       reset,
    input  logic       cpu_cycle_enable,
    input  logic       enable,

    input  logic       write,
    input  logic [1:0] write_register,
    input  logic [7:0] write_data,
    input  logic       quarter_frame_tick,
    input  logic       half_frame_tick,

    output logic       active,
    output logic [3:0] raw_output,

    // Architectural state is exposed for deterministic model comparison.
    output logic       control_flag,
    output logic [6:0] linear_reload_value,
    output logic [6:0] linear_counter,
    output logic       linear_reload_flag,
    output logic [4:0] sequence_position,
    output logic [10:0] timer_period,
    output logic [10:0] timer_counter,
    output logic [7:0] length_counter
);
    import nes_apu_pkg::*;

    assign active = length_counter != 8'd0;
    assign raw_output = APU_TRIANGLE_SEQUENCE[sequence_position];

    always_ff @(posedge clk) begin
        if (reset) begin
            control_flag       <= 1'b0;
            linear_reload_value <= 7'd0;
            linear_counter     <= 7'd0;
            linear_reload_flag <= 1'b0;
            sequence_position  <= 5'd0;
            timer_period       <= 11'd0;
            timer_counter      <= 11'd0;
            length_counter     <= 8'd0;
        end else if (cpu_cycle_enable) begin
            // The triangle timer runs at the CPU clock rate, twice the pulse
            // timer rate. The divider continues while sequencing is gated.
            if (timer_counter == 11'd0) begin
                timer_counter <= timer_period;
                if (length_counter != 8'd0 && linear_counter != 7'd0)
                    sequence_position <= sequence_position + 5'd1;
            end else begin
                timer_counter <= timer_counter - 11'd1;
            end

            // Quarter-frame linear-counter operation uses the pre-edge reload
            // flag. Control also serves as the length-counter halt bit.
            if (quarter_frame_tick) begin
                if (linear_reload_flag)
                    linear_counter <= linear_reload_value;
                else if (linear_counter != 7'd0)
                    linear_counter <= linear_counter - 7'd1;

                if (!control_flag)
                    linear_reload_flag <= 1'b0;
            end

            if (half_frame_tick && length_counter != 8'd0 && !control_flag)
                length_counter <= length_counter - 8'd1;

            // $4009 is intentionally absent: register 1 writes do nothing.
            if (write) begin
                case (write_register)
                    2'd0: begin // $4008
                        control_flag <= write_data[7];
                        linear_reload_value <= write_data[6:0];
                    end
                    2'd2: begin // $400A
                        timer_period[7:0] <= write_data;
                    end
                    2'd3: begin // $400B
                        timer_period[10:8] <= write_data[2:0];
                        linear_reload_flag <= 1'b1;
                        if (enable)
                            length_counter <=
                                APU_LENGTH_TABLE[write_data[7:3]];
                    end
                    default: begin end
                endcase
            end

            // Disabling through $4015 clears length immediately. Enabling
            // alone never invents a new length value.
            if (!enable)
                length_counter <= 8'd0;
        end
    end

endmodule
