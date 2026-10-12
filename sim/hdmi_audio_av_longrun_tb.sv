`timescale 1ns/1fs

module hdmi_audio_av_longrun_tb;
    localparam integer SOURCE_HZ = 50_000_000;
    localparam integer AUDIO_HZ = 48_000;
    localparam integer VIDEO_HZ = 60;
    localparam integer TARGET_FRAMES = 12;

    logic source_clk = 1'b0;
    logic reset = 1'b1;
    logic audio_clk, audio_locked, audio_reset;
    logic signed [15:0] pcm_sample = '0;
    logic pcm_valid = 1'b0;
    logic sample_ready, i2s_bclk, i2s_lrclk, i2s_data, primed;
    logic [15:0] occupancy;
    logic [31:0] sample_count, underruns, overruns;
    logic stream_enable = 1'b0;
    logic run_generation = 1'b1;
    integer sample_phase = 0;
    integer video_phase = 0;
    integer generated_samples = 0;
    integer video_frames = 0;
    integer source_cycles = 0;
    integer high_water = 0;
    logic pixel_clk = 0, vga_clk = 0;
    // Nominal 74.25 MHz and the fitter's 50 MHz * 49 / 33 approximation
    // are tested separately. Neither drives or restarts the audio clock.
    always #($test$plusargs("fitted_video_clock") ? 6.734693877551 : 6.734006734007)
        pixel_clk = !pixel_clk;
    always #19.841269841270 vga_clk = !vga_clk;
    logic [10:0] x;
    logic [9:0] y, vx, vy;
    logic active, hs, vs, frame_end, vactive, vhs, vvs, vframe_end;
    integer raster_frames = 0, vga_frames = 0, pixels = 0, active_pixels = 0;
    integer decoded_samples = 0;

    /* verilator lint_off PINCONNECTEMPTY */
    video_720p_timing video (
        .pixel_clk(pixel_clk), .reset(reset), .x(x), .y(y),
        .active_video(active), .hsync(hs), .vsync(vs), .frame_end(frame_end),
        .line_start(), .line_end(), .frame_start()
    );
    vga_timing vga (
        .pixel_clk(vga_clk), .reset(reset), .x(vx), .y(vy),
        .active_video(vactive), .hsync_n(vhs), .vsync_n(vvs),
        .frame_end(vframe_end), .line_start(), .frame_start()
    );
    /* verilator lint_on PINCONNECTEMPTY */
    always @(posedge pixel_clk) if (!reset) begin
        assert (integer'(x) == pixels % 1650 && integer'(y) == pixels / 1650);
        assert (hs == (x >= 1390 && x < 1430));
        assert (vs == (y >= 725 && y < 730));
        pixels++;
        if (active) active_pixels++;
        if (frame_end) begin
            assert (pixels == 1237500 && active_pixels == 921600);
            pixels = 0; active_pixels = 0; raster_frames++;
        end
    end
    always @(posedge vga_clk) if (!reset) begin
        assert(vhs == !(vx >= 656 && vx < 752));
        assert(vvs == !(vy >= 490 && vy < 492));
        assert(vactive == (vx < 640 && vy < 480));
        if (vframe_end) vga_frames++;
    end
    initial begin : receiver
        logic [15:0] left_word, right_word;
        wait(dut.serializer.sample_consumed_event);
        forever begin
            left_word = 0; right_word = 0;
            for (int bit_index = 0; bit_index < 64; bit_index++) begin
                @(posedge i2s_bclk);
                assert(i2s_lrclk == (bit_index >= 32));
                if (bit_index >= 1 && bit_index <= 16) left_word = {left_word[14:0], i2s_data};
                else if (bit_index >= 33 && bit_index <= 48) right_word = {right_word[14:0], i2s_data};
                else assert(i2s_data == 0);
            end
            assert(left_word == 16'(decoded_samples * 73 + 16'h1234) && right_word == left_word)
                else $fatal(1, "long-run I2S loss/duplication index=%0d", decoded_samples);
            decoded_samples++;
        end
    end

    always #10 source_clk = !source_clk;

    /* verilator lint_off PINCONNECTEMPTY */
    audio_pll #(.ENABLE_HDMI_CLOCK(1'b1)) clock_source (
        .ref_clk(source_clk),
        .reset(reset),
        .audio_clk(),
        .hdmi_audio_clk(audio_clk),
        .locked(audio_locked)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    reset_sync audio_reset_sync (
        .clk(audio_clk),
        .async_reset_n(!reset && audio_locked),
        .reset(audio_reset)
    );

    hdmi_audio_transport dut (
        .source_clk(source_clk), .source_reset(reset),
        .pcm_sample(pcm_sample), .pcm_valid(pcm_valid),
        .accept_samples(1'b1), .fifo_flush(1'b0),
        .sample_ready(sample_ready), .audio_clk(audio_clk),
        .audio_reset(audio_reset), .stream_enable(stream_enable),
        .mute(1'b0), .i2s_bclk(i2s_bclk), .i2s_lrclk(i2s_lrclk),
        .i2s_data(i2s_data), .primed(primed),
        .fifo_occupancy(occupancy), .sample_count(sample_count),
        .fifo_underruns(underruns), .fifo_overruns(overruns)
    );

    always_ff @(posedge source_clk) begin
        if (reset) begin
            sample_phase <= 0;
            video_phase <= 0;
            generated_samples <= 0;
            video_frames <= 0;
            source_cycles <= 0;
            pcm_valid <= 1'b0;
            pcm_sample <= '0;
            stream_enable <= 1'b0;
            high_water <= 0;
        end else begin
            source_cycles <= source_cycles + 1;
            pcm_valid <= 1'b0;
            if (primed)
                stream_enable <= 1'b1;
            if (32'(occupancy) > high_water)
                high_water <= 32'(occupancy);

            if (run_generation) begin
                if (sample_phase + AUDIO_HZ >= SOURCE_HZ) begin
                    sample_phase <= sample_phase + AUDIO_HZ - SOURCE_HZ;
                    pcm_sample <= 16'(generated_samples * 73 + 16'h1234);
                    pcm_valid <= 1'b1;
                    generated_samples <= generated_samples + 1;
                end else begin
                    sample_phase <= sample_phase + AUDIO_HZ;
                end

                if (video_phase + VIDEO_HZ >= SOURCE_HZ) begin
                    video_phase <= video_phase + VIDEO_HZ - SOURCE_HZ;
                    video_frames <= video_frames + 1;
                end else begin
                    video_phase <= video_phase + VIDEO_HZ;
                end
            end
        end
    end

    initial begin
        repeat (8) @(posedge source_clk);
        reset = 1'b0;
        wait (video_frames == TARGET_FRAMES);
        @(negedge source_clk);
        run_generation = 1'b0;
        repeat (20) @(posedge source_clk);

        if (generated_samples != TARGET_FRAMES * 800)
            $fatal(1, "A/V rate mismatch frames=%0d generated=%0d",
                   video_frames, generated_samples);
        assert(raster_frames == ($test$plusargs("fitted_video_clock") ?
            TARGET_FRAMES - 1 : TARGET_FRAMES) && vga_frames == TARGET_FRAMES);
        assert(decoded_samples >= generated_samples - 6);
        if (underruns != 0 || overruns != 0)
            $fatal(1, "long-run FIFO errors under=%0d over=%0d",
                   underruns, overruns);
        if (high_water < 4 || high_water > 8)
            $fatal(1, "unbounded/unexpected FIFO high water=%0d", high_water);
        if (sample_count + 32'(occupancy) + 2 < generated_samples ||
            sample_count + 32'(occupancy) > generated_samples + 2)
            $fatal(1, "sample accounting mismatch generated=%0d sent=%0d queued=%0d",
                   generated_samples, sample_count, occupancy);

        $display("Phase 6D long-run A/V passed: duration_cycles=%0d samples=%0d video_frames=%0d sent=%0d fifo_high_water=%0d underruns=%0d overruns=%0d",
                 source_cycles, generated_samples, video_frames, sample_count,
                 high_water, underruns, overruns);
        $display("Actual rasters: fitted_clock=%0b 720p_frames=%0d VGA_frames=%0d I2S_decoded=%0d mismatches=0", $test$plusargs("fitted_video_clock"), raster_frames, vga_frames, decoded_samples);
        $finish;
    end
endmodule
