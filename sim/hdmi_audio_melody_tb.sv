`timescale 1ns/1ps

// Staged CPU-melody replay: the input file is cut from the independently
// validated Phase 5J CPU/APU capture's 48 kHz WAV, never authored by this TB.
module hdmi_audio_melody_tb;
    localparam integer SAMPLE_TOTAL = 512;
    logic audio_clk = 1'b0;
    logic reset = 1'b1;
    logic fifo_empty;
    logic signed [15:0] fifo_read_data;
    logic fifo_read_enable;
    logic i2s_bclk, i2s_lrclk, i2s_data;
    logic frame_event;
    logic [15:0] samples [0:SAMPLE_TOTAL-1];
    integer consumed = 0;
    integer mismatches = 0;

    always #10 audio_clk = !audio_clk;
    assign fifo_empty = consumed >= SAMPLE_TOTAL;
    assign fifo_read_data = fifo_empty ? '0 : samples[consumed];

    /* verilator lint_off PINCONNECTEMPTY */
    hdmi_i2s_tx dut (
        .audio_clk(audio_clk), .reset(reset), .stream_enable(1'b1),
        .mute(1'b0), .fifo_empty(fifo_empty),
        .fifo_read_data(fifo_read_data), .fifo_read_enable(fifo_read_enable),
        .i2s_bclk(i2s_bclk), .i2s_lrclk(i2s_lrclk), .i2s_data(i2s_data),
        .frame_event(frame_event), .sample_consumed_event(), .underrun_event()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_ff @(posedge audio_clk)
        if (!reset && fifo_read_enable)
            consumed <= consumed + 1;

    task automatic check_frame(input logic [15:0] expected);
        integer position;
        logic expected_data;
        begin
            @(posedge frame_event);
            for (position = 0; position < 64; position = position + 1) begin
                @(posedge i2s_bclk);
                expected_data = 1'b0;
                if (position >= 1 && position <= 16)
                    expected_data = expected[16-position];
                if (position >= 33 && position <= 48)
                    expected_data = expected[48-position];
                if (i2s_lrclk !== (position >= 32) ||
                    i2s_data !== expected_data)
                    mismatches = mismatches + 1;
            end
        end
    endtask

    initial begin
        $readmemh("build/sim/phase6d_melody_pcm.hex", samples);
        repeat (5) @(posedge audio_clk);
        reset = 1'b0;
        for (integer index = 0; index < SAMPLE_TOTAL; index = index + 1)
            check_frame(samples[index]);
        if (consumed != SAMPLE_TOTAL || mismatches != 0)
            $fatal(1, "melody replay mismatch consumed=%0d mismatches=%0d",
                   consumed, mismatches);
        $display("Phase 6D staged CPU melody replay passed: source=Phase5J_CPU_APU_WAV samples=%0d mismatches=%0d",
                 SAMPLE_TOTAL, mismatches);
        $finish;
    end
endmodule
