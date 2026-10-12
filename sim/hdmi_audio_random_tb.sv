`timescale 1ns/1ps

module hdmi_audio_random_tb;
    localparam integer SAMPLE_TOTAL = 256;
    localparam logic [31:0] RANDOM_SEED = 32'h6d48_0001;

    logic audio_clk = 1'b0;
    logic reset = 1'b1;
    logic stream_enable = 1'b0;
    logic mute = 1'b0;
    logic fifo_empty;
    logic signed [15:0] fifo_read_data;
    logic fifo_read_enable;
    logic i2s_bclk, i2s_lrclk, i2s_data;
    logic frame_event, consumed_event, underrun_event;
    logic [15:0] samples [0:SAMPLE_TOTAL-1];
    logic [63:0] expected_frames [0:SAMPLE_TOTAL-1];
    integer consumed = 0;
    integer checked = 0;
    integer mismatches = 0;
    integer audio_cycles = 0;
    integer previous_edge_cycle = 0;

    always #10 audio_clk = !audio_clk;
    always @(posedge reset) previous_edge_cycle = 0;
    always @(i2s_bclk) if (!reset) begin
        if (previous_edge_cycle != 0 && audio_cycles - previous_edge_cycle != 8 &&
            audio_cycles - previous_edge_cycle != 9)
            $fatal(1, "BCLK half-period is not 8/9 audio clocks");
        previous_edge_cycle = audio_cycles;
    end
    always @(i2s_data or i2s_lrclk) if (!reset)
        assert (!i2s_bclk) else $fatal(1, "I2S data/LRCLK changed at capture edge");
    assign fifo_empty = consumed >= SAMPLE_TOTAL;
    assign fifo_read_data = fifo_empty ? '0 : samples[consumed];

    hdmi_i2s_tx dut (
        .audio_clk(audio_clk), .reset(reset),
        .stream_enable(stream_enable), .mute(mute),
        .fifo_empty(fifo_empty), .fifo_read_data(fifo_read_data),
        .fifo_read_enable(fifo_read_enable), .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk), .i2s_data(i2s_data),
        .frame_event(frame_event), .sample_consumed_event(consumed_event),
        .underrun_event(underrun_event)
    );

    always_ff @(posedge audio_clk) begin
        audio_cycles <= audio_cycles + 1;
        if (!reset && consumed_event)
            consumed <= consumed + 1;
    end

    task automatic check_frame(
        input logic [63:0] expected
    );
        integer position;
        logic expected_data;
        begin
            @(posedge frame_event);
            for (position = 0; position < 64; position = position + 1) begin
                @(posedge i2s_bclk);
                expected_data = expected[63-position];
                if (i2s_lrclk !== (position >= 32) ||
                    i2s_data !== expected_data)
                    mismatches = mismatches + 1;
            end
            checked = checked + 1;
        end
    endtask

    initial begin
        $readmemh("build/sim/phase6d_random_pcm.hex", samples);
        $readmemh("build/sim/phase6d_random_i2s.hex", expected_frames);
        repeat (5) @(posedge audio_clk);
        reset = 1'b0;
        stream_enable = 1'b1;

        for (integer index = 0; index < SAMPLE_TOTAL; index = index + 1) begin
            // Seeded vector bits choose deterministic mute intervals.  The
            // sample is still consumed so unmute cannot replay stale audio.
            mute = (samples[index][4:0] == 5'h0d);
            check_frame(expected_frames[index]);
            if ((index + 1) % 64 == 0 && index + 1 < SAMPLE_TOTAL) begin
                reset = 1'b1;
                repeat (3) @(posedge audio_clk);
                reset = 1'b0;
            end
        end
        repeat (4) @(posedge audio_clk);
        if (consumed != SAMPLE_TOTAL || checked != SAMPLE_TOTAL ||
            underrun_event || mismatches != 0)
            $fatal(1, "random test mismatch consumed=%0d checked=%0d mismatches=%0d",
                   consumed, checked, mismatches);
        $display("Phase 6D randomized RTL passed: seed=0x%08x cycles=%0d samples=%0d mismatches=%0d",
                 RANDOM_SEED, audio_cycles, checked, mismatches);
        $finish;
    end
endmodule
