// NES APU Noise channel.
//
// Implements the $400C/$400E/$400F envelope, length counter, NTSC timer,
// and 15-bit feedback shift register. The caller supplies the established
// every-other-CPU-cycle APU timer tick and shared frame-sequencer events.
module nes_apu_noise (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_cycle_enable,
    input  logic        timer_tick,
    input  logic        quarter_frame_tick,
    input  logic        half_frame_tick,
    input  logic        enable,
    input  logic        write,
    input  logic [1:0]  write_register,
    input  logic [7:0]  write_data,

    output logic        active,
    output logic [3:0]  raw_output,
    output logic        length_halt,
    output logic        constant_volume,
    output logic [3:0]  envelope_period,
    output logic        envelope_start,
    output logic [3:0]  envelope_divider,
    output logic [3:0]  envelope_decay,
    output logic        mode,
    output logic [3:0]  period_index,
    output logic [11:0] timer_period,
    output logic [10:0] timer_counter,
    output logic [7:0]  length_counter,
    output logic [14:0] lfsr
);
    import nes_apu_pkg::*;

    logic [3:0] selected_volume;
    logic feedback;

    always_comb begin
        timer_period = APU_NOISE_PERIOD_TABLE[period_index];
        selected_volume = constant_volume ? envelope_period : envelope_decay;
        active = (length_counter != 8'd0);
        raw_output = (enable && active && !lfsr[0]) ? selected_volume : 4'd0;
        feedback = lfsr[0] ^ (mode ? lfsr[6] : lfsr[1]);
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            length_halt      <= 1'b0;
            constant_volume  <= 1'b0;
            envelope_period  <= 4'd0;
            envelope_start   <= 1'b0;
            envelope_divider <= 4'd0;
            envelope_decay   <= 4'd0;
            mode             <= 1'b0;
            period_index     <= 4'd0;
            timer_counter    <= 11'd0;
            length_counter   <= 8'd0;
            lfsr             <= 15'h0001;
        end else if (cpu_cycle_enable) begin
            if (timer_tick) begin
                if (timer_counter == 11'd0) begin
                    timer_counter <=
                        APU_NOISE_PERIOD_TABLE[period_index][11:1] - 11'd1;
                    lfsr <= {feedback, lfsr[14:1]};
                end else begin
                    timer_counter <= timer_counter - 11'd1;
                end
            end

            if (quarter_frame_tick) begin
                if (envelope_start) begin
                    envelope_start   <= 1'b0;
                    envelope_decay   <= 4'd15;
                    envelope_divider <= envelope_period;
                end else if (envelope_divider != 4'd0) begin
                    envelope_divider <= envelope_divider - 4'd1;
                end else begin
                    envelope_divider <= envelope_period;
                    if (envelope_decay != 4'd0) begin
                        envelope_decay <= envelope_decay - 4'd1;
                    end else if (length_halt) begin
                        envelope_decay <= 4'd15;
                    end
                end
            end

            if (half_frame_tick && !length_halt &&
                (length_counter != 8'd0)) begin
                length_counter <= length_counter - 8'd1;
            end

            if (write) begin
                case (write_register)
                    2'd0: begin
                        length_halt     <= write_data[5];
                        constant_volume <= write_data[4];
                        envelope_period <= write_data[3:0];
                    end
                    2'd1: begin
                        // $400D is unused by the NES Noise channel.
                    end
                    2'd2: begin
                        mode         <= write_data[7];
                        period_index <= write_data[3:0];
                    end
                    2'd3: begin
                        envelope_start <= 1'b1;
                        if (enable)
                            length_counter <= APU_LENGTH_TABLE[write_data[7:3]];
                    end
                    default: begin
                    end
                endcase
            end

            if (!enable)
                length_counter <= 8'd0;

`ifndef SYNTHESIS
            // A one seed cannot reach the all-zero lock state with either tap.
            assert (lfsr != 15'd0);
`endif
        end
    end
endmodule
