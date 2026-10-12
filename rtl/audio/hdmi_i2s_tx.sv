`timescale 1ns/1ps

// ADV7513 standard-I2S source. A 50 MHz output of the Phase 5K PLL and a 768/6250
// half-edge accumulator produce a continuous 3.072 MHz BCLK.  Each 32-bit
// channel slot contains the mandatory one-bit I2S delay, sixteen MSB-first
// sample bits, and zero padding.  The mono source is duplicated into L/R.
module hdmi_i2s_tx #(
    parameter integer SAMPLE_WIDTH = 16,
    parameter integer SLOT_WIDTH = 32
) (
    input  logic                          audio_clk,
    input  logic                          reset,
    input  logic                          stream_enable,
    input  logic                          mute,
    input  logic                          fifo_empty,
    input  logic signed [SAMPLE_WIDTH-1:0] fifo_read_data,
    output logic                          fifo_read_enable,
    output logic                          i2s_bclk,
    output logic                          i2s_lrclk,
    output logic                          i2s_data,
    output logic                          frame_event,
    output logic                          sample_consumed_event,
    output logic                          underrun_event
);
    localparam integer FRAME_BITS = SLOT_WIDTH * 2;
    localparam integer POSITION_WIDTH = $clog2(FRAME_BITS);

    logic [12:0] bclk_phase;
    logic [POSITION_WIDTH-1:0] bit_position;
    logic signed [SAMPLE_WIDTH-1:0] current_sample;

    always_ff @(posedge audio_clk) begin : serialize
        logic [POSITION_WIDTH-1:0] next_position;

        if (reset) begin
            bclk_phase <= '0;
            bit_position <= '0;
            current_sample <= '0;
            fifo_read_enable <= 1'b0;
            i2s_bclk <= 1'b0;
            i2s_lrclk <= 1'b0;
            i2s_data <= 1'b0;
            frame_event <= 1'b0;
            sample_consumed_event <= 1'b0;
            underrun_event <= 1'b0;
        end else begin
            fifo_read_enable <= 1'b0;
            frame_event <= 1'b0;
            sample_consumed_event <= 1'b0;
            underrun_event <= 1'b0;

            if (({1'b0, bclk_phase} + 14'd768) >= 14'd6250) begin
                bclk_phase <= 13'(({1'b0, bclk_phase} + 14'd768) - 14'd6250);
                i2s_bclk <= !i2s_bclk;

                // Data and LRCLK change on falling BCLK.  The transmitter is
                // configured to capture on rising BCLK.
                if (i2s_bclk) begin
                    if (bit_position == POSITION_WIDTH'(FRAME_BITS - 1))
                        next_position = '0;
                    else
                        next_position = bit_position + 1'b1;
                    bit_position <= next_position;

                    if (next_position == 0) begin
                        frame_event <= 1'b1;
                        i2s_lrclk <= 1'b0;
                        i2s_data <= 1'b0;
                        if (!stream_enable) begin
                            current_sample <= '0;
                        end else if (fifo_empty) begin
                            current_sample <= '0;
                            underrun_event <= 1'b1;
                        end else begin
                            current_sample <= mute ? '0 : fifo_read_data;
                            fifo_read_enable <= 1'b1;
                            sample_consumed_event <= 1'b1;
                        end
                    end else if (next_position == POSITION_WIDTH'(SLOT_WIDTH)) begin
                        i2s_lrclk <= 1'b1;
                        i2s_data <= 1'b0;
                    end else if (next_position >= POSITION_WIDTH'(1) &&
                                 next_position <= POSITION_WIDTH'(SAMPLE_WIDTH)) begin
                        i2s_data <= current_sample[
                            SAMPLE_WIDTH - integer'(next_position)];
                    end else if (next_position >=
                                 POSITION_WIDTH'(SLOT_WIDTH + 1) &&
                                 next_position <=
                                 POSITION_WIDTH'(SLOT_WIDTH + SAMPLE_WIDTH)) begin
                        i2s_data <= current_sample[
                            SLOT_WIDTH + SAMPLE_WIDTH -
                            integer'(next_position)];
                    end else begin
                        i2s_data <= 1'b0;
                    end
                end
            end else begin
                bclk_phase <= bclk_phase + 13'd768;
            end
        end
    end

    initial begin
        if (SAMPLE_WIDTH < 2 || SLOT_WIDTH <= SAMPLE_WIDTH || SLOT_WIDTH > 32)
            $error("invalid HDMI I2S sample/slot width");
        if (FRAME_BITS != 64)
            $error("50 MHz clock divider requires 32-bit stereo slots");
    end
endmodule
