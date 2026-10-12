`timescale 1ns/1ps

// Independent HDMI branch of the Phase 5K PCM broadcast.  Only Gray pointers
// and Gray-coded diagnostic counters cross between fabric and PLL 50 MHz.
module hdmi_audio_transport #(
    parameter integer FIFO_DEPTH = 32,
    parameter integer PREFILL_LEVEL = 4
) (
    input  logic               source_clk,
    input  logic               source_reset,
    input  logic signed [15:0] pcm_sample,
    input  logic               pcm_valid,
    input  logic               accept_samples,
    input  logic               fifo_flush,
    output logic               sample_ready,
    input  logic               audio_clk,
    input  logic               audio_reset,
    input  logic               stream_enable,
    input  logic               mute,
    output logic               i2s_bclk,
    output logic               i2s_lrclk,
    output logic               i2s_data,
    output logic               primed,
    output logic [15:0]        fifo_occupancy,
    output logic [31:0]        sample_count,
    output logic [31:0]        fifo_underruns,
    output logic [31:0]        fifo_overruns
);
    localparam integer LEVEL_WIDTH = $clog2(FIFO_DEPTH) + 1;

    logic fifo_full, fifo_empty;
    logic fifo_write_enable, fifo_read_enable;
    logic fifo_overflow_event;
    logic [LEVEL_WIDTH-1:0] fifo_write_level;
    logic signed [15:0] fifo_read_data;
    logic serializer_sample_event;
    logic serializer_underrun_event;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] flush_sync, stream_sync, mute_sync;
    logic fifo_read_reset;
    logic [31:0] transmitted_binary, underrun_binary;
    logic [31:0] transmitted_gray, underrun_gray;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [31:0] transmitted_gray_sync1, transmitted_gray_sync2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [31:0] underrun_gray_sync1, underrun_gray_sync2;

    function automatic logic [31:0] binary_to_gray(input logic [31:0] value);
        binary_to_gray = (value >> 1) ^ value;
    endfunction

    function automatic logic [31:0] gray_to_binary(input logic [31:0] value);
        logic [31:0] result;
        integer index;
        begin
            result[31] = value[31];
            for (index = 30; index >= 0; index = index - 1)
                result[index] = result[index + 1] ^ value[index];
            gray_to_binary = result;
        end
    endfunction

    function automatic logic [31:0] saturating_increment(
        input logic [31:0] value
    );
        saturating_increment = (&value) ? value : value + 1'b1;
    endfunction

    assign sample_ready = accept_samples && !fifo_full && !fifo_flush;
    assign fifo_write_enable = pcm_valid && accept_samples && !fifo_flush;
    assign fifo_occupancy = 16'(fifo_write_level);
    assign primed = fifo_write_level >= LEVEL_WIDTH'(PREFILL_LEVEL);

    /* verilator lint_off PINCONNECTEMPTY */
    audio_async_fifo #(.WIDTH(16), .DEPTH(FIFO_DEPTH)) sample_fifo (
        .write_clk(source_clk),
        .write_reset(source_reset || fifo_flush),
        .write_enable(fifo_write_enable),
        .write_data(pcm_sample),
        .full(fifo_full),
        .overflow_event(fifo_overflow_event),
        .write_level(fifo_write_level),
        .read_clk(audio_clk),
        .read_reset(fifo_read_reset),
        .read_enable(fifo_read_enable),
        .read_data(fifo_read_data),
        .empty(fifo_empty),
        .underflow_event(),
        .read_level()
    );

    always_ff @(posedge audio_clk) begin
        if (audio_reset) begin
            flush_sync <= 2'b11;
            stream_sync <= '0;
            mute_sync <= 2'b11;
        end else begin
            flush_sync <= {flush_sync[0], fifo_flush};
            stream_sync <= {stream_sync[0], stream_enable};
            mute_sync <= {mute_sync[0], mute};
        end
    end
    assign fifo_read_reset = audio_reset || flush_sync[1];

    hdmi_i2s_tx serializer (
        .audio_clk(audio_clk),
        .reset(audio_reset),
        .stream_enable(stream_sync[1] && !fifo_read_reset),
        .mute(mute_sync[1]),
        .fifo_empty(fifo_empty),
        .fifo_read_data(fifo_read_data),
        .fifo_read_enable(fifo_read_enable),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_data(i2s_data),
        .frame_event(),
        .sample_consumed_event(serializer_sample_event),
        .underrun_event(serializer_underrun_event)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_ff @(posedge audio_clk) begin
        if (audio_reset) begin
            transmitted_binary <= '0;
            underrun_binary <= '0;
            transmitted_gray <= '0;
            underrun_gray <= '0;
        end else begin
            // Register Gray codes at the source; combinational binary-to-Gray
            // outputs can glitch when several binary counter bits change.
            if (serializer_sample_event) begin
                transmitted_binary <= saturating_increment(transmitted_binary);
                transmitted_gray <= binary_to_gray(
                    saturating_increment(transmitted_binary));
            end
            if (serializer_underrun_event) begin
                underrun_binary <= saturating_increment(underrun_binary);
                underrun_gray <= binary_to_gray(
                    saturating_increment(underrun_binary));
            end
        end
    end

    always_ff @(posedge source_clk) begin
        if (source_reset) begin
            transmitted_gray_sync1 <= '0;
            transmitted_gray_sync2 <= '0;
            underrun_gray_sync1 <= '0;
            underrun_gray_sync2 <= '0;
            fifo_overruns <= '0;
        end else begin
            transmitted_gray_sync1 <= transmitted_gray;
            transmitted_gray_sync2 <= transmitted_gray_sync1;
            underrun_gray_sync1 <= underrun_gray;
            underrun_gray_sync2 <= underrun_gray_sync1;
            if (fifo_overflow_event)
                fifo_overruns <= saturating_increment(fifo_overruns);
        end
    end

    assign sample_count = gray_to_binary(transmitted_gray_sync2);
    assign fifo_underruns = gray_to_binary(underrun_gray_sync2);

`ifndef SYNTHESIS
    always_ff @(posedge source_clk) begin
        if (!source_reset && pcm_valid && accept_samples && !sample_ready)
            assert (fifo_full || fifo_flush);
    end
`endif
endmodule
