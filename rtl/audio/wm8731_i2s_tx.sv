`timescale 1ns/1ps

// WM8731 slave-mode I2S transmitter.  A 64/125 phase accumulator produces
// BCLK half-edges from the 12 MHz MCLK: 3.072 MHz BCLK (64fs) and exactly
// 48 kHz LRCK (250 MCLKs/frame).  LRCK changes only on falling BCLK edges.
// Slot zero in each half-frame is the mandatory I2S one-bit delay, followed
// by 16 MSB-first sample bits and fifteen zero padding bits.
module wm8731_i2s_tx (
    input  logic               audio_clk,
    input  logic               reset,
    input  logic               stream_enable,
    input  logic               fifo_empty,
    input  logic signed [15:0] fifo_read_data,
    output logic               fifo_read_enable,
    output logic               aud_bclk,
    output logic               aud_daclrck,
    output logic               aud_dacdat,
    output logic               muted,
    output logic               frame_event,
    output logic               sample_transmitted_event,
    output logic               underrun_event
);
    logic [6:0] bclk_phase;
    logic [5:0] bit_position;
    logic signed [15:0] current_sample;
    logic streaming;

    assign muted = !streaming;

    always_ff @(posedge audio_clk) begin : serialize
        logic [5:0] next_position;

        if (reset) begin
            bclk_phase <= '0;
            bit_position <= '0;
            current_sample <= '0;
            streaming <= 1'b0;
            fifo_read_enable <= 1'b0;
            aud_bclk <= 1'b0;
            aud_daclrck <= 1'b0;
            aud_dacdat <= 1'b0;
            frame_event <= 1'b0;
            sample_transmitted_event <= 1'b0;
            underrun_event <= 1'b0;
        end else begin
            fifo_read_enable <= 1'b0;
            frame_event <= 1'b0;
            sample_transmitted_event <= 1'b0;
            underrun_event <= 1'b0;

            if (({1'b0, bclk_phase} + 8'd64) >= 8'd125) begin
                bclk_phase <= 7'(({1'b0, bclk_phase} + 8'd64) - 8'd125);
                aud_bclk <= !aud_bclk;

                if (aud_bclk) begin
                    if (bit_position == 6'd63)
                        next_position = '0;
                    else
                        next_position = bit_position + 1'b1;
                    bit_position <= next_position;

                    if (next_position == 6'd0) begin
                        frame_event <= 1'b1;
                        aud_daclrck <= 1'b0;
                        aud_dacdat <= 1'b0;
                        if (!stream_enable) begin
                            streaming <= 1'b0;
                            current_sample <= '0;
                        end else if (fifo_empty) begin
                            streaming <= 1'b1;
                            current_sample <= '0;
                            underrun_event <= 1'b1;
                        end else begin
                            streaming <= 1'b1;
                            current_sample <= fifo_read_data;
                            fifo_read_enable <= 1'b1;
                            sample_transmitted_event <= 1'b1;
                        end
                    end else if (next_position == 6'd32) begin
                        aud_daclrck <= 1'b1;
                        aud_dacdat <= 1'b0;
                    end else if ((next_position >= 6'd1) &&
                                 (next_position <= 6'd16)) begin
                        aud_dacdat <= current_sample[16 - next_position];
                    end else if ((next_position >= 6'd33) &&
                                 (next_position <= 6'd48)) begin
                        aud_dacdat <= current_sample[48 - next_position];
                    end else begin
                        aud_dacdat <= 1'b0;
                    end
                end
            end else begin
                bclk_phase <= bclk_phase + 7'd64;
            end
        end
    end
endmodule
