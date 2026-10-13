`timescale 1ns/1ps

// CPU/APU capture -> actual Phase 5K FIR/conditioner -> two independent FIFOs
// -> WM8731 and HDMI serial pins. Python golden samples are computed from the
// original mixer events, before either RTL serializer is run.
module hdmi_audio_pcm_integration_tb;
    logic clk = 0, reset = 1;
    logic codec_retry = 0, source_reset = 0, checking = 1;
    always #10 clk = !clk;
    logic tick = 0;
    logic [19:0] mixed = 0;
    logic [19:0] mixed_values [0:19999];
    logic [15:0] expected [0:535];
    logic signed [15:0] pcm;
    logic pcm_valid, pcm_reset, pll_locked, codec_done;
    logic audio_clk, hdmi_clk, hdmi_reset;
    logic codec_scl_low, codec_sda_low, codec_ack = 0;
    /* verilator lint_off SYNCASYNCNET */
    wire scl = !codec_scl_low;
    wire sda = !(codec_sda_low || codec_ack);
    /* verilator lint_on SYNCASYNCNET */
    logic scl_previous = 1, sda_previous = 1, transaction = 0;
    integer bus_edges = 0;
    logic wm_bclk, wm_lr, wm_data;
    logic hd_bclk, hd_lr, hd_data, primed, started = 0;
    logic [31:0] sent, under, over, wm_under, wm_over;
    integer pcm_count = 0, hd_count = 0, wm_count = 0;
    integer fabric_cycles = 0;
    logic [31:0] previous_sent_gray = 0, previous_under_gray = 0;
    always @(negedge audio_clk) begin
        if ($test$plusargs("phase6g_reset")) begin
            if (!source.audio_reset) begin
                assert ($onehot0(previous_sent_gray ^ source.audio_transmitted_gray));
                assert ($onehot0(previous_under_gray ^ source.audio_underrun_gray));
            end
            previous_sent_gray = source.audio_transmitted_gray;
            previous_under_gray = source.audio_underrun_gray;
        end
    end

    always @(scl or sda) begin
        if (sda_previous && !sda && scl_previous && scl && !transaction) begin
            transaction = 1; bus_edges = 0; codec_ack = 0;
        end else if (!sda_previous && sda && scl_previous && scl && transaction) begin
            transaction = 0; codec_ack = 0;
        end else if (scl_previous && !scl && transaction)
            codec_ack = bus_edges == 8 || bus_edges == 17 || bus_edges == 26;
        else if (!scl_previous && scl && transaction) bus_edges++;
        scl_previous = scl;
        sda_previous = sda;
    end

    /* verilator lint_off PINCONNECTEMPTY */
    nes_audio_output #(.ENABLE_HDMI_CLOCK(1'b1)) source (
        .clk(clk), .reset(reset), .source_reset(source_reset), .input_tick(tick),
        .mixed_audio(mixed), .test_tone_enable(1'b0), .codec_retry_request(codec_retry),
        .i2c_scl_in(scl), .i2c_sda_in(sda), .i2c_scl_drive_low(codec_scl_low),
        .i2c_sda_drive_low(codec_sda_low), .aud_xck(audio_clk),
        .aud_bclk(wm_bclk), .aud_daclrck(wm_lr), .aud_dacdat(wm_data),
        .audio_pll_locked(pll_locked), .codec_init_done(codec_done),
        .pcm_output_sample(pcm), .pcm_output_valid(pcm_valid),
        .pcm_output_reset(pcm_reset), .hdmi_audio_clk(hdmi_clk),
        .codec_init_busy(), .codec_init_error(), .diag_i2c_ack_count(),
        .diag_i2c_nack_count(), .diag_init_retry_count(), .diag_i2c_timeout_count(),
        .diag_samples_generated(), .diag_samples_transmitted(),
        .diag_fifo_underruns(wm_under), .diag_fifo_overruns(wm_over),
        .diag_saturation_count(), .diag_fifo_occupancy(), .diag_sample_rate(),
        .diag_muted(), .diag_last_fault()
    );
    reset_sync sync_reset (.clk(hdmi_clk), .async_reset_n(!pcm_reset), .reset(hdmi_reset));
    hdmi_audio_transport transport (
        .source_clk(clk), .source_reset(pcm_reset), .pcm_sample(pcm), .pcm_valid(pcm_valid),
        .accept_samples(1'b1), .fifo_flush(1'b0), .sample_ready(),
        .audio_clk(hdmi_clk), .audio_reset(hdmi_reset), .stream_enable(started),
        .mute(1'b0), .i2s_bclk(hd_bclk), .i2s_lrclk(hd_lr), .i2s_data(hd_data),
        .primed(primed), .fifo_occupancy(), .sample_count(sent),
        .fifo_underruns(under), .fifo_overruns(over)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always @(posedge clk) begin
        fabric_cycles++;
        if (pcm_reset) started <= 0;
        else if (primed) started <= 1;
        if (!pcm_reset && pcm_valid) begin
            assert (!checking || (pcm_count < 536 && pcm == expected[pcm_count]))
                else $fatal(1, "Phase5K PCM model mismatch index=%0d got=%h expected=%h",
                            pcm_count, pcm, expected[pcm_count]);
            pcm_count++;
        end
    end

    // Each receiver aligns to the first frame that actually consumes data,
    // then observes only pins, independently of the serializer bit counter.
    initial begin : hd_receiver
        logic [15:0] left_word, right_word;
        wait (transport.serializer.sample_consumed_event);
        forever begin
            left_word = 0; right_word = 0;
            for (int bit_index = 0; bit_index < 64; bit_index++) begin
                @(posedge hd_bclk);
                assert(!checking || hd_lr == (bit_index >= 32));
                if (bit_index >= 1 && bit_index <= 16) left_word = {left_word[14:0], hd_data};
                else if (bit_index >= 33 && bit_index <= 48) right_word = {right_word[14:0], hd_data};
                else assert(!checking || hd_data == 0);
            end
            assert (!checking || (left_word == expected[hd_count] && right_word == left_word))
                else $fatal(1, "HDMI model mismatch sample=%0d got=%h", hd_count, left_word);
            hd_count++;
        end
    end
    initial begin : wm_receiver
        logic [15:0] left_word, right_word;
        wait (source.serializer_transmitted_event);
        forever begin
            left_word = 0; right_word = 0;
            for (int bit_index = 0; bit_index < 64; bit_index++) begin
                @(posedge wm_bclk);
                assert(!checking || wm_lr == (bit_index >= 32));
                if (bit_index >= 1 && bit_index <= 16) left_word = {left_word[14:0], wm_data};
                else if (bit_index >= 33 && bit_index <= 48) right_word = {right_word[14:0], wm_data};
                else assert(!checking || wm_data == 0);
            end
            assert (!checking || (left_word == expected[wm_count] && right_word == left_word))
                else $fatal(1, "WM8731 preservation mismatch sample=%0d", wm_count);
            wm_count++;
        end
    end
    initial begin : stimulus
        integer phase = 0, input_index = 0;
        $readmemh("build/sim/phase6d_melody_mixed.hex", mixed_values);
        $readmemh("build/sim/phase6d_phase5k_pcm.hex", expected);
        repeat(8) @(negedge clk);
        reset = 0;
        wait (codec_done && !pcm_reset);
        while (hd_count < 512 || wm_count < 512) begin
            @(negedge clk);
            tick = 0;
            phase += 315;
            if (phase >= 8800 && input_index < 20000) begin
                phase -= 8800;
                mixed = mixed_values[input_index];
                input_index++;
                tick = 1;
            end
        end
        assert(under == 0 && over == 0 && wm_under == 0 && wm_over == 0);
        $display("Phase 6D actual PCM integration: CPU-capture ticks=%0d PCM=%0d HDMI=%0d WM8731=%0d mismatches=0", input_index, pcm_count, hd_count, wm_count);
        // After the complete golden replay, restart the actual codec during
        // playback. Both branches must reset, then regenerate fresh silence
        // from a held mixer value, not replay buffered melody samples.
        checking = 0;
        tick = 0;
        @(negedge clk); codec_retry = 1;
        @(negedge clk); codec_retry = 0;
        repeat (20) @(negedge clk);
        assert(pcm_reset && hdmi_reset && !codec_done && hd_data == 0 && wm_data == 0);
        wait(codec_done && !pcm_reset);
        for (integer clock_index = 0; clock_index < 60000; clock_index++) begin
            @(negedge clk);
            tick = 0; phase += 315;
            if (phase >= 8800) begin phase -= 8800; tick = 1; end
            assert(hd_data == 0 && wm_data == 0);
            if (pcm_valid) assert(pcm == 0);
        end
        assert(sent > 40 && under == 0 && over == 0 && wm_under == 0 && wm_over == 0);
        source_reset = 1; tick = 0;
        repeat (20) @(negedge clk);
        assert(pcm_reset && hdmi_reset && codec_done && hd_data == 0 && wm_data == 0 && sent == 0);
        source_reset = 0;
        $display("Phase 6D codec restart and source reset passed: fresh silence, both consumers reset, no stale samples");
        if ($test$plusargs("phase6g_reset")) begin
            // Pulse widths include less than one 12 MHz period. The fabric
            // must wait for the consumer to clear its pointer before prefill.
            for (integer epoch = 0; epoch < 32; epoch++) begin
                @(negedge clk); source_reset = 1; tick = 0;
                repeat (1 + epoch % 4) @(negedge clk);
                source_reset = 0;
                assert (pcm_reset);
                wait (!pcm_reset);
                assert (!source.audio_reset && !source.prefill_complete);
                for (integer cycle = 0; cycle < 20000 + epoch*13; cycle++) begin
                    @(negedge clk); tick = 0; phase += 315;
                    if (phase >= 8800) begin phase -= 8800; tick = 1; end
                    assert (hd_data == 0 && wm_data == 0);
                end
                assert (sent > 8 && under == 0 && over == 0 && wm_under == 0 && wm_over == 0);
            end
            tick = 0;
            repeat (40000) @(negedge clk);
            assert (under > 0 && wm_under > 0 && hd_data == 0 && wm_data == 0);
            source_reset = 1;
            @(negedge clk); source_reset = 0;
            wait (!pcm_reset);
            repeat (20) @(negedge clk);
            assert (under == 0 && wm_under == 0 && !source.prefill_complete);
            // Losing lock reinitializes the actual codec sequencer. Only the
            // lock indication is injected; no replacement serializer is used.
            force source.audio_pll_locked = 1'b0;
            repeat (20) @(negedge clk);
            assert (pcm_reset && hdmi_reset && !codec_done && hd_data == 0 && wm_data == 0);
            release source.audio_pll_locked;
            wait (codec_done && !pcm_reset);
            for (integer cycle = 0; cycle < 20000; cycle++) begin
                @(negedge clk); tick = 0; phase += 315;
                if (phase >= 8800) begin phase -= 8800; tick = 1; end
            end
            assert (sent > 8 && under == 0 && wm_under == 0 && wm_over == 0 && over == 0);
            $display("PASS: Phase6G audio cycles=%0d, 32 short reset epochs, starvation, PLL loss, codec recovery and registered Gray transitions; mismatches=0", fabric_cycles);
        end
        $finish;
    end
    initial begin
        #100_000_000;
        $fatal(1, "PCM integration watchdog");
    end
endmodule
