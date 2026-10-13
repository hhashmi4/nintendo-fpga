`timescale 1ns/1ps

// Real production top, with only the external HPS Avalon initiator and pad-2
// logical input substituted for unavailable hardware. A separate simulation
// consumer connects the real PPU/PCM streams to the existing HDMI modules.
// The extra framebuffer is a test instrument, not a proposed board image.
module phase6g_system_tb;
    import nes_runtime_loader_mmio_pkg::*;
    import nes_diagnostic_mmio_pkg::*;
    import nes_debugger_pkg::*;
    logic clk = 0, hps_clk = 0, hdmi_clk = 0, audio_clk = 0;
    logic key0 = 0, bridge_reset = 0;
    logic [7:0] buttons1 = 0, buttons2 = 0;
    logic [5:0] av_address = 0;
    logic av_read = 0, av_write = 0;
    logic [31:0] av_data = 0;
    logic [8:0] diag_address = 0;
    logic diag_read = 0, diag_write = 0;
    logic [31:0] diag_data = 0;
    logic debug_request = 0;
    logic [2:0] debug_command = 0;
    logic [7:0] vga_r, vga_g, vga_b;
    logic vga_blank;
    logic wm_bclk, wm_lr, wm_data;
    /* verilator lint_off SYNCASYNCNET */
    tri1 codec_scl, codec_sda;
    /* verilator lint_on SYNCASYNCNET */
    logic codec_ack = 0, codec_transaction = 0;
    logic codec_scl_prev = 1, codec_sda_prev = 1;
    integer codec_edges = 0;
    assign codec_sda = codec_ack ? 1'b0 : 1'bz;
    always #10 clk = !clk;
    always #7 hps_clk = !hps_clk; // deliberately unrelated to CLOCK_50
    initial begin #3; forever #10 audio_clk = !audio_clk; end
    // Fitted 50 MHz * 49/33 clock, rational half-period in 1 ps units.
    initial begin
        integer phase = 0;
        forever begin
            phase += 330000;
            #(1ps * (phase / 49));
            phase %= 49;
            hdmi_clk = !hdmi_clk;
        end
    end

    /* verilator lint_off PINMISSING */
    de1_soc_nes_vga_top #(
        .PRG_INIT_FILE("build/cartridge/phase4db_playable_nrom128.prg.hex"),
        .CHR_INIT_FILE("build/cartridge/phase4db_playable_nrom128.chr.hex")
    ) dut (
        .CLOCK_50(clk), .KEY0(key0), .SW0(1'b0), .SW1(1'b0),
        .SW2(buttons1[0]), .SW3(buttons1[1]), .SW4(buttons1[2]),
        .SW5(buttons1[3]), .SW6(buttons1[4]), .SW7(buttons1[5]),
        .SW8(buttons1[6]), .SW9(buttons1[7]),
        .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b), .VGA_BLANK_N(vga_blank),
        .AUD_BCLK(wm_bclk), .AUD_DACLRCK(wm_lr), .AUD_DACDAT(wm_data),
        .FPGA_I2C_SCLK(codec_scl), .FPGA_I2C_SDAT(codec_sda)
    );
    /* verilator lint_on PINMISSING */
    always @* begin
        force dut.hps_mmio_clk = hps_clk;
        force dut.hps_mmio_reset_raw = bridge_reset;
        force dut.hps_mmio_address = av_address;
        force dut.hps_mmio_read = av_read;
        force dut.hps_mmio_write = av_write;
        force dut.hps_mmio_writedata = av_data;
        force dut.hps_mmio_byteenable = 4'hf;
        force dut.diagnostic_mmio_address = diag_address;
        force dut.diagnostic_mmio_read = diag_read;
        force dut.diagnostic_mmio_write = diag_write;
        force dut.diagnostic_mmio_writedata = diag_data;
        force dut.diagnostic_mmio_byteenable = 4'hf;
        force dut.controllers.controller2_buttons = buttons2;
        force dut.debugger_request_valid = debug_request;
        force dut.debugger_request_command = debug_command;
    end

    // WM8731 model acknowledges the actual three-byte transactions on pins.
    always @(codec_scl or codec_sda) begin
        if (codec_sda_prev && !codec_sda && codec_scl_prev && codec_scl && !codec_transaction) begin
            codec_transaction = 1; codec_edges = 0; codec_ack = 0;
        end else if (!codec_sda_prev && codec_sda && codec_scl_prev && codec_scl && codec_transaction) begin
            codec_transaction = 0; codec_ack = 0;
        end else if (codec_scl_prev && !codec_scl && codec_transaction)
            codec_ack = codec_edges == 8 || codec_edges == 17 || codec_edges == 26;
        else if (!codec_scl_prev && codec_scl && codec_transaction) codec_edges++;
        codec_scl_prev = codec_scl; codec_sda_prev = codec_sda;
    end

    wire pcm_reset = dut.audio_output.pcm_output_reset;
    wire pcm_valid = dut.audio_output.pcm_output_valid;
    wire signed [15:0] pcm_sample = dut.audio_output.pcm_output_sample;
    logic hdmi_reset, audio_reset;
    reset_sync hdmi_reset_sync(.clk(hdmi_clk), .async_reset_n(key0), .reset(hdmi_reset));
    reset_sync audio_reset_sync(.clk(audio_clk), .async_reset_n(!pcm_reset), .reset(audio_reset));
    logic [23:0] rgb, tx_rgb;
    logic hsync, vsync, de, frame_start, frame_end, frame_toggle;
    logic [10:0] x;
    logic [9:0] y;
    logic display_valid;
    logic tx_pclk, tx_de, tx_start;
    logic hpd = 1, video_enable, safe_disable;
    logic hd_scl_low, hd_sda_low, sink_sda_low;
    wire hd_scl = !hd_scl_low;
    wire hd_sda = !(hd_sda_low || sink_sda_low);
    logic hd_enabled, hd_muted, hd_accept, hd_stream, hd_flush, primed;
    logic [31:0] hd_sent, hd_under, hd_over;
    logic hd_bclk, hd_lr, hd_data;
    /* verilator lint_off PINMISSING */
    nes_digital_video_pipeline video (
        .source_clk(clk), .source_reset(dut.nes_functional_reset),
        .source_frame_start(dut.ppu_frame_start), .source_pixel_valid(dut.pixel_valid),
        .source_pixel_x(dut.pixel_x), .source_pixel_y(dut.pixel_y),
        .source_pixel_color(dut.pixel_color), .source_pixel_emphasis(dut.pixel_emphasis),
        .capture_freeze(1'b0), .pixel_clk(hdmi_clk), .pixel_reset(hdmi_reset),
        .test_pattern_async(1'b0), .developer_layout_async(1'b0),
        .panel_valid(1'b0), .panel_rgb(24'd0), .rgb(rgb), .hsync(hsync),
        .vsync(vsync), .active_video(de), .frame_start(frame_start), .frame_end(frame_end),
        .scan_x(x), .scan_y(y), .display_valid(display_valid)
    );
    hdmi_rgb_output adapter (
        .pixel_clk(hdmi_clk), .pixel_reset(hdmi_reset),
        .video_enable_async(video_enable && !safe_disable),
        .pipeline_rgb(rgb), .pipeline_hsync(hsync), .pipeline_vsync(vsync),
        .pipeline_de(de), .pipeline_frame_start(frame_start),
        .tx_pixel_clock(tx_pclk), .tx_rgb(tx_rgb), .tx_data_enable(tx_de),
        .tx_frame_start(tx_start), .frame_toggle(frame_toggle)
    );
    hdmi_tx_controller #(
        .HPD_STABLE_CYCLES(8), .STARTUP_DELAY_CYCLES(8),
        .CLOCK_WAIT_TIMEOUT(200), .HPD_WAIT_TIMEOUT(100000),
        .RECOVERY_DELAY_CYCLES(16), .I2C_CLOCKS_PER_HALF_PERIOD(4),
        .I2C_TIMEOUT_CYCLES(64), .EDID_READY_POLLS(4), .EDID_POLL_DELAY_CYCLES(2)
    ) controller (
        .clk(clk), .reset(dut.system_reset), .pixel_clock_locked_async(!hdmi_reset),
        .frame_toggle_async(frame_toggle), .hpd_async(hpd), .scl_in(hd_scl), .sda_in(hd_sda),
        .audio_clock_locked_async(dut.audio_output.audio_pll_locked && !pcm_reset),
        .audio_configuration_allowed(1'b1), .audio_transport_primed(primed),
        .audio_user_mute(1'b0), .audio_fault_clear(1'b0),
        .audio_fifo_underruns(hd_under), .audio_fifo_overruns(hd_over),
        .scl_drive_low(hd_scl_low), .sda_drive_low(hd_sda_low),
        .video_enable(video_enable), .safe_disable(safe_disable),
        .hdmi_audio_enabled(hd_enabled), .hdmi_audio_muted(hd_muted),
        .hdmi_audio_accept_samples(hd_accept), .hdmi_audio_stream_enable(hd_stream),
        .hdmi_audio_fifo_flush(hd_flush)
    );
    hdmi_audio_transport transport (
        .source_clk(clk), .source_reset(pcm_reset), .pcm_sample(pcm_sample),
        .pcm_valid(pcm_valid), .accept_samples(hd_accept), .fifo_flush(hd_flush),
        .audio_clk(audio_clk), .audio_reset(audio_reset), .stream_enable(hd_stream),
        .mute(hd_muted), .i2s_bclk(hd_bclk), .i2s_lrclk(hd_lr), .i2s_data(hd_data),
        .primed(primed), .sample_count(hd_sent), .fifo_underruns(hd_under), .fifo_overruns(hd_over)
    );
    // Exercise a deliberately isolated logical power observer while the NES
    // runs. No permit/reset output has a connection to production hardware.
    logic power_report = 0;
    logic [63:0] power_data = 0;
    logic [415:0] power_diagnostics;
    usbc_power_supervisor #(.STALE_CYCLES(64)) power_observer (
        .clk(clk), .reset(dut.system_reset), .status_valid(power_report),
        .status_data(power_data), .fault_clear(1'b0), .diagnostics(power_diagnostics)
    );
    /* verilator lint_on PINMISSING */
    phase6g_hdmi_sink sink(.scl(hd_scl), .sda(hd_sda),
        .read_transaction(controller.i2c_master.latched_read), .drive_low(sink_sda_low));

    integer cycles = 0, ppu_frames = 0, dma_count = 0, dmc_count = 0;
    integer p1_reads = 0, p2_reads = 0, commands = 0, epochs = 0;
    integer pcm_count = 0, nonzero_pcm = 0, vga_pixels = 0, hdmi_pixels = 0;
    logic old_reset = 1;
    logic [23:0] expected_vga [0:307199];
    logic [23:0] expected_hdmi [0:921599];
    always @(posedge clk) begin
        cycles++;
        if (dut.nes_functional_reset && !old_reset) epochs++;
        old_reset = dut.nes_functional_reset;
        if (dut.nes_functional_reset) begin
            assert (!dut.nes_core_cpu_enable && !dut.nes_core_ppu_enable);
        end else begin
            if (dut.ppu_frame_start) ppu_frames++;
            if (dut.dma_complete_event) dma_count++;
            if (dut.dmc_mem_acknowledge) dmc_count++;
            if (dut.controller_debug_read_4016) p1_reads++;
            if (dut.controller_debug_read_4017) p2_reads++;
            assert (!dut.write_range_error && !dut.write_sequence_error);
        end
        if (pcm_valid) begin pcm_count++; if (pcm_sample != 0) nonzero_pcm++; end
        assert (dut.diagnostics.USBC_POWER_AVAILABLE == 0);
        assert (dut.diagnostics.usbc_diagnostics == 0);
    end

    // The I2S receiver compares pin words against a queue of actual broadcast
    // PCM samples. FIFO/serializer internals never supply expected data.
    logic [15:0] wm_queue[$], hd_queue[$];
    logic [15:0] wm_expected = 0, hd_expected = 0;
    integer wm_bit = -1, hd_bit = -1, wm_words = 0, hd_words = 0;
    always @(posedge clk) begin
        if (pcm_reset) wm_queue.delete();
        else if (pcm_valid) wm_queue.push_back(pcm_sample);
        if (pcm_reset || hd_flush) hd_queue.delete();
        else if (pcm_valid && hd_accept) hd_queue.push_back(pcm_sample);
    end
    always @(posedge dut.audio_output.audio_reset) wm_bit = -1;
    always @(posedge audio_reset) hd_bit = -1;
    always @(posedge dut.audio_output.serializer_transmitted_event) begin
        if (wm_queue.size() == 0) $fatal(1, "WM8731 consumed unproduced PCM");
        wm_expected = wm_queue.pop_front(); wm_bit = 0;
    end
    always @(posedge transport.serializer_sample_event) begin
        if (!pcm_reset && !hd_flush) begin
            if (hd_queue.size() == 0) $fatal(1, "HDMI consumed unproduced PCM");
            hd_expected = hd_queue.pop_front(); hd_bit = 0;
        end else hd_bit = -1;
    end
    function automatic logic serial_bit(input logic [15:0] word_value, input integer position);
        if (position >= 1 && position <= 16) return word_value[16-position];
        if (position >= 33 && position <= 48) return word_value[48-position];
        return 0;
    endfunction
    always @(posedge wm_bclk) if (wm_bit >= 0) begin
        assert (wm_lr == (wm_bit >= 32) && wm_data == serial_bit(wm_expected, wm_bit))
            else $fatal(1, "WM8731 PCM format/order bit=%0d", wm_bit);
        wm_bit++;
        if (wm_bit == 64) begin wm_words++; wm_bit = -1; end
    end
    always @(posedge hd_bclk) if (hd_bit >= 0) begin
        // A disconnect may mute the committed stereo frame at its boundary.
        if (!hd_muted && !hd_flush && !pcm_reset)
            assert (hd_lr == (hd_bit >= 32) && hd_data == serial_bit(hd_expected, hd_bit))
                else $fatal(1, "HDMI PCM format/order bit=%0d", hd_bit);
        hd_bit++;
        if (hd_bit == 64) begin hd_words++; hd_bit = -1; end
    end

    task automatic mmio_read(input logic [5:0] address, output logic [31:0] data);
        @(negedge hps_clk); av_address = address; av_read = 1;
        @(negedge hps_clk); data = dut.hps_mmio_readdata;
        assert (dut.hps_mmio_readdatavalid && !dut.hps_mmio_waitrequest);
        av_read = 0; av_address = 0;
    endtask
    task automatic mmio_write(input logic [5:0] address, input logic [31:0] data);
        logic [31:0] before_count, count, status;
        if (address == MMIO_REG_COMMAND) begin
            do mmio_read(MMIO_REG_STATUS, status); while (!status[MMIO_STATUS_BRIDGE_READY_BIT]);
            mmio_read(MMIO_REG_COMPLETED_COUNT, before_count);
        end
        @(negedge hps_clk); av_address = address; av_data = data; av_write = 1;
        @(negedge hps_clk); assert (!dut.hps_mmio_waitrequest);
        av_write = 0; av_address = 0; av_data = 0;
        if (address == MMIO_REG_COMMAND) begin
            commands++;
            for (integer poll = 0; poll < 10000; poll++) begin
                mmio_read(MMIO_REG_STATUS, status); mmio_read(MMIO_REG_COMPLETED_COUNT, count);
                if (count != before_count && !status[MMIO_STATUS_COMMAND_PENDING_BIT]) return;
            end
            $fatal(1, "system MMIO command timed out");
        end
    endtask
    task automatic replay(input string name, input integer limit = 0);
        integer fd, parsed, start_count;
        string line, op;
        logic [31:0] a, b, c, value;
        start_count = commands;
        fd = $fopen({"build/phase6g/system/", name, ".mmio"}, "r");
        assert (fd != 0);
        while ($fgets(line, fd) != 0) begin
            parsed = $sscanf(line, "%s %h %h %h", op, a, b, c);
            if (op == "W" && parsed == 3) mmio_write(a[5:0], b);
            else if (op == "R" && parsed == 4) begin
                mmio_read(a[5:0], value);
                assert ((value & b) == c) else $fatal(1, "MMIO trace read %s", name);
            end else if (op == "S" && parsed == 3) begin
                do mmio_read(MMIO_REG_STATUS, value); while ((value & a) != b);
            end else if (op != "#") $fatal(1, "malformed software trace");
            if (limit > 0 && commands - start_count >= limit) break;
        end
        $fclose(fd);
        $display("Phase6G replay=%s commands=%0d cycle=%0d", name, commands-start_count, cycles);
    endtask
    task automatic diag_access(input logic wr, input logic [8:0] address,
                               input logic [31:0] data, output logic [31:0] value);
        @(negedge hps_clk);
        diag_address = address; diag_data = data; diag_read = !wr; diag_write = wr;
        @(negedge hps_clk); value = dut.diagnostic_mmio_readdata;
        assert (!dut.diagnostic_mmio_waitrequest);
        if (!wr) assert (dut.diagnostic_mmio_readdatavalid);
        diag_read = 0; diag_write = 0;
    endtask
    task automatic snapshot;
        logic [31:0] value;
        diag_access(1, DIAG_REG_CONTROL, 1, value);
        do diag_access(0, DIAG_REG_CONTROL_STATUS, 0, value); while (value[0]);
    endtask
    task automatic debug_send(input logic [2:0] command_value);
        do @(negedge dut.pixel_clk); while (!dut.debugger_request_ready);
        debug_command = command_value; debug_request = 1;
        do @(negedge dut.pixel_clk); while (!dut.debugger_ack);
        assert (dut.debugger_ack_result == DBG_OK);
        debug_request = 0;
        repeat (3) @(negedge dut.pixel_clk);
    endtask
    task automatic wait_game_a;
        wait (!dut.nes_functional_reset && dut.ppu_debug_ctrl == 8'h80 && dut.ppu_debug_mask == 8'h0a &&
              dut.nes.internal_cpu_ram.memory[11'h012] == 8'hd1);
        repeat (3) begin
            @(posedge dut.ppu_frame_start); @(negedge clk);
        end
    endtask
    task automatic compare_video;
        fork
            begin
                @(posedge dut.vga_frame_start); @(negedge dut.pixel_clk);
                for (integer i = 0; i < 420000; i++) begin
                    if (vga_blank) begin
                        assert ({vga_r,vga_g,vga_b} == expected_vga[32'(dut.video.output_y)*640+32'(dut.video.output_x)])
                            else $fatal(1, "VGA pixel %0d,%0d", dut.video.output_x, dut.video.output_y);
                        vga_pixels++;
                    end
                    @(negedge dut.pixel_clk);
                end
            end
            begin
                @(posedge tx_start); @(posedge tx_pclk);
                for (integer i = 0; i < 1237500; i++) begin
                    assert (tx_de == (x < 1280 && y < 720));
                    assert (hsync == (x >= 1390 && x < 1430));
                    assert (vsync == (y >= 725 && y < 730));
                    if (tx_de) begin
                        assert (tx_rgb == expected_hdmi[32'(y)*1280+32'(x)])
                            else $fatal(1, "HDMI pixel %0d,%0d", x, y);
                        hdmi_pixels++;
                    end else assert (tx_rgb == 0);
                    @(posedge tx_pclk);
                end
            end
        join
    endtask
    initial begin : scenario
        logic [31:0] value;
        integer before_samples, before_frames;
        $readmemh("build/phase6g/system/vga.hex", expected_vga);
        $readmemh("build/phase6g/system/hdmi.hex", expected_hdmi);
        repeat (20) @(negedge clk); key0 = 1;
        wait (!dut.hps_mmio_reset && !dut.nes_functional_reset);
        replay("game_a"); wait_game_a();
        wait (hd_enabled && !hd_muted && display_valid && dut.framebuffer_valid);
        compare_video();
        assert (vga_pixels == 307200 && hdmi_pixels == 921600);
        $display("Phase6G both video frames match Python; cycle=%0d", cycles);
        for (integer pattern = 0; pattern < 16; pattern++) begin
            buttons1 = 8'(pattern * 17); buttons2 = ~buttons1;
            // Allow a complete poll after an intervening 514-slot OAM DMA.
            repeat (50000) @(negedge clk);
            assert (dut.nes.internal_cpu_ram.memory[11'h032] == buttons1 &&
                    dut.nes.internal_cpu_ram.memory[11'h033] == buttons2)
                else $fatal(1, "both controller ports pattern=%0d got=%h,%h expected=%h,%h", pattern,
                    dut.nes.internal_cpu_ram.memory[11'h032], dut.nes.internal_cpu_ram.memory[11'h033], buttons1, buttons2);
        end
        debug_send(DBG_PAUSE);
        wait (dut.debugger_status.state == DBG_PAUSED);
        before_samples = wm_words;
        before_frames = ppu_frames;
        repeat (50000) begin
            @(negedge clk);
            assert (!dut.nes_core_cpu_enable && !dut.nes_core_ppu_enable && !dut.dma_debug_active);
        end
        assert (wm_words > before_samples && ppu_frames == before_frames);
        snapshot();
        diag_access(0, DIAG_REG_CPU_STATUS, 0, value); assert (value[3]);
        debug_send(DBG_STEP_I);
        wait (dut.debugger_status.state == DBG_PAUSED);
        snapshot();
        diag_access(0, DIAG_REG_CPU_DEBUG_EVENTS, 0, value); assert (value >= 2);
        debug_send(DBG_RUN);
        wait (dut.debugger_status.state == DBG_RUNNING);
        $display("Phase6G both controller ports, Developer Mode pause/step/run and diagnostics passed; cycle=%0d", cycles);
        // Synthetic power reports are deliberately disconnected from NES reset.
        power_report = 1; power_data = 64'hffffffffffffffff;
        repeat (100) @(negedge clk);
        power_report = 0;
        assert (power_diagnostics[8*32 +: 32] != 0 && power_diagnostics[9*32 +: 32] > 0);
        assert (power_observer.downstream_disable_request && !power_observer.system_ready);
        assert (!dut.nes_functional_reset);
        snapshot();
        diag_access(0, DIAG_REG_USBC_ATTACHED, 0, value); assert (value == 0);
        diag_access(0, DIAG_REG_USBC_PROVENANCE, 0, value); assert (value == 0);
        before_samples = wm_words;
        hpd = 0; repeat (6000) @(negedge clk);
        assert (!video_enable && !hd_enabled && hd_data == 0 && wm_words > before_samples);
        hpd = 1; wait (video_enable && hd_enabled && !hd_muted);
        @(posedge tx_start);
        $display("Phase6G HDMI hotplug recovered independently of codec; cycle=%0d", cycles);
        // Replacement must revoke old video/snapshot ownership but not VGA timing.
        replay("failed_replacement");
        repeat (100) @(negedge clk);
        assert (dut.nes_functional_reset && !dut.framebuffer_valid && !display_valid && pcm_reset);
        assert (!dut.video_reset && !dut.debug_destination_valid);
        snapshot();
        diag_access(0, DIAG_REG_LOADER_ERRORS, 0, value); assert (value >= 1);
        replay("game_b");
        wait (dut.nes.internal_cpu_ram.memory[11'h022] == 8'ha6);
        assert (dut.cartridge_nrom_256 && dut.cartridge_chr_is_ram);
        assert (dut.nes.internal_cpu_ram.memory[11'h020] == 8'h3c &&
                dut.nes.internal_cpu_ram.memory[11'h021] == 8'hc7);
        replay("reload_a"); wait_game_a();
        for (integer restart = 0; restart < 4; restart++) begin
            repeat (137 + restart*701) @(negedge clk);
            mmio_write(MMIO_REG_COMMAND, 32'd3); // re-ACTIVATE the complete image
            wait_game_a();
            assert (dut.audio_output.diag_fifo_underruns == 0 &&
                    dut.audio_output.diag_fifo_overruns == 0);
        end
        before_frames = ppu_frames;
        replay("failed_replacement", 20); // HPS reset cancels a partial transfer
        bridge_reset = 1; repeat (20) @(negedge clk); bridge_reset = 0;
        wait (!dut.hps_mmio_reset && !dut.nes_functional_reset);
        assert (!dut.runtime_cartridge_active);
        replay("game_a"); wait_game_a();
        // Physical reset request is simulated twice. Each boot returns to
        // the legacy image and requires a fresh HPS load to select game A.
        for (integer board_reset = 0; board_reset < 2; board_reset++) begin
            wait (hd_enabled && !hd_muted);
            @(negedge clk); key0 = 0;
            repeat (20 + board_reset*7) @(negedge clk);
            // KEY0 also stops the VGA PLL. Synchronous reader registers clear
            // on its first returning edges; the reset request must be held.
            assert (pcm_reset && dut.video_content_reset && !display_valid);
            key0 = 1;
            wait (!dut.hps_mmio_reset && !dut.nes_functional_reset);
            assert (!dut.framebuffer_valid && !dut.debug_destination_valid);
            replay("game_a"); wait_game_a();
        end
        assert (ppu_frames > before_frames && p1_reads > 100 && p2_reads > 100);
        assert (dma_count >= 6 && dmc_count > 100 && nonzero_pcm > 100);
        assert (wm_words > 1000 && hd_words > 1000 && hd_under == 0 && hd_over == 0);
        snapshot();
        diag_access(0, DIAG_REG_VERSION, 0, value); assert (value == DIAG_VERSION);
        // Board reset deliberately clears lifetime diagnostics.
        diag_access(0, DIAG_REG_LOADER_ERRORS, 0, value); assert (value == 0);
        $display("PASS: Phase6G production system cycles=%0d PPU_frames=%0d reset_epochs=%0d MMIO_commands=%0d DMA=%0d DMC=%0d P1_reads=%0d P2_reads=%0d PCM=%0d nonzero_PCM=%0d WM8731_words=%0d HDMI_words=%0d VGA_pixels=%0d HDMI_pixels=%0d mismatches=0",
                 cycles, ppu_frames, epochs, commands, dma_count, dmc_count, p1_reads, p2_reads,
                 pcm_count, nonzero_pcm, wm_words, hd_words, vga_pixels, hdmi_pixels);
        $finish;
    end
    initial begin
        #1_500_000_000;
        $fatal(1, "Phase6G system watchdog cycles=%0d commands=%0d PC=%h HDMI=%h audio=%h error=%h/%h", cycles, commands, dut.cpu_debug_pc,
            controller.startup_state, controller.hdmi_audio_state, controller.last_error_code, controller.hdmi_audio_last_error);
    end
endmodule
