`timescale 1ns/1ps

module hdmi_audio_transport_tb;
    logic source_clk = 1'b0;
    logic audio_clk = 1'b0;
    logic source_reset = 1'b1;
    logic audio_reset = 1'b1;
    logic signed [15:0] pcm_sample = '0;
    logic pcm_valid = 1'b0;
    logic accept_samples = 1'b0;
    logic fifo_flush = 1'b1;
    logic sample_ready;
    logic stream_enable = 1'b0;
    logic mute = 1'b0;
    logic i2s_bclk, i2s_lrclk, i2s_data, primed;
    logic [15:0] fifo_occupancy;
    logic [31:0] sample_count, fifo_underruns, fifo_overruns;
    integer checked_frames = 0;
    integer mismatches = 0;

    always #10 source_clk = !source_clk;
    always #10.003 audio_clk = !audio_clk;

    hdmi_audio_transport dut (
        .source_clk(source_clk),
        .source_reset(source_reset),
        .pcm_sample(pcm_sample),
        .pcm_valid(pcm_valid),
        .accept_samples(accept_samples),
        .fifo_flush(fifo_flush),
        .sample_ready(sample_ready),
        .audio_clk(audio_clk),
        .audio_reset(audio_reset),
        .stream_enable(stream_enable),
        .mute(mute),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_data(i2s_data),
        .primed(primed),
        .fifo_occupancy(fifo_occupancy),
        .sample_count(sample_count),
        .fifo_underruns(fifo_underruns),
        .fifo_overruns(fifo_overruns)
    );

    task automatic push_sample(input logic signed [15:0] value);
        begin
            @(negedge source_clk);
            pcm_sample = value;
            pcm_valid = 1'b1;
            @(negedge source_clk);
            pcm_valid = 1'b0;
        end
    endtask

    task automatic check_frame(
        input logic [15:0] expected,
        input logic expected_silence
    );
        integer position;
        logic expected_lr;
        logic expected_data;
        begin
            @(posedge dut.serializer.frame_event);
            for (position = 0; position < 64; position = position + 1) begin
                @(posedge i2s_bclk);
                expected_lr = position >= 32;
                expected_data = 1'b0;
                if (!expected_silence && position >= 1 && position <= 16)
                    expected_data = expected[16-position];
                if (!expected_silence && position >= 33 && position <= 48)
                    expected_data = expected[48-position];
                if (i2s_lrclk !== expected_lr || i2s_data !== expected_data) begin
                    $error("frame=%0d bit=%0d expected lr/data=%0b/%0b got=%0b/%0b",
                           checked_frames, position, expected_lr, expected_data,
                           i2s_lrclk, i2s_data);
                    mismatches = mismatches + 1;
                end
            end
            checked_frames = checked_frames + 1;
        end
    endtask

    initial begin
        repeat (8) @(posedge source_clk);
        source_reset = 1'b0;
        repeat (4) @(posedge audio_clk);
        audio_reset = 1'b0;
        fifo_flush = 1'b0;
        accept_samples = 1'b1;

        push_sample(16'sh0000);
        push_sample(16'sh1234);
        push_sample(-16'sh1234);
        push_sample(16'sh7fff);
        push_sample(-16'sh8000);
        if (!primed)
            $fatal(1, "FIFO did not reach the four-sample prime threshold");

        stream_enable = 1'b1;
        repeat (4) @(posedge audio_clk);
        check_frame(16'h0000, 1'b0);
        check_frame(16'h1234, 1'b0);
        check_frame(16'hedcc, 1'b0);
        check_frame(16'h7fff, 1'b0);
        check_frame(16'h8000, 1'b0);

        // Empty while enabled produces an explicit underrun and zero silence.
        check_frame(16'h0000, 1'b1);
        repeat (8) @(posedge source_clk);
        if (fifo_underruns == 0)
            $fatal(1, "empty streaming FIFO did not report underrun");

        // Muted transport continues consuming fresh samples, but emits zeros.
        stream_enable = 1'b0;
        fifo_flush = 1'b1;
        repeat (6) @(posedge audio_clk);
        fifo_flush = 1'b0;
        push_sample(16'sh7fff);
        push_sample(-16'sh8000);
        push_sample(16'sh5555);
        push_sample(-16'sh2222);
        mute = 1'b1;
        stream_enable = 1'b1;
        repeat (4) @(posedge audio_clk);
        check_frame(16'h0000, 1'b1);

        // Fill without consuming to exercise full detection and bounded drops.
        stream_enable = 1'b0;
        mute = 1'b0;
        fifo_flush = 1'b1;
        repeat (6) @(posedge audio_clk);
        fifo_flush = 1'b0;
        for (integer index = 0; index < 40; index = index + 1)
            push_sample(16'(index));
        repeat (4) @(posedge source_clk);
        if (fifo_occupancy != 32 || fifo_overruns != 8)
            $fatal(1, "FIFO full/overrun mismatch occupancy=%0d overruns=%0d",
                   fifo_occupancy, fifo_overruns);

        fifo_flush = 1'b1;
        repeat (4) @(posedge source_clk);
        if (fifo_occupancy != 0)
            $fatal(1, "flush did not discard stale samples");
        if (mismatches != 0)
            $fatal(1, "I2S mismatches=%0d", mismatches);
        $display("Phase 6D HDMI audio transport passed: frames=%0d samples=%0d underruns=%0d overruns=%0d",
                 checked_frames, sample_count, fifo_underruns, fifo_overruns);
        $finish;
    end
endmodule
