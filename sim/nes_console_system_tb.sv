`timescale 1ns/1ps

// Real production top, with only the external HPS Avalon initiator and pad-2
// logical input substituted for unavailable hardware. A separate simulation
// consumer connects the real PPU/PCM streams to the existing HDMI modules.
// The extra framebuffer is a test instrument, not a proposed board image.
module nes_console_system_tb;
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
    logic vga_blank, vga_hs, vga_vs;
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
        .VGA_HS(vga_hs), .VGA_VS(vga_vs), .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b), .VGA_BLANK_N(vga_blank),
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


    integer cycles=0, commands=0;
    integer transition_cycle=0;
    logic [3:0] observed_state=0;
    always @(negedge clk) begin
        if(!dut.system_reset && dut.console_status[3:0]!=observed_state) begin
            $display("METRIC state=%0d next=%0d cycles=%0d at=%0d",
                     observed_state,dut.console_status[3:0],cycles-transition_cycle,cycles);
            observed_state=dut.console_status[3:0];transition_cycle=cycles;
        end
    end
    always @(posedge clk) cycles++;
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
        $display("Phase8A replay=%s commands=%0d cycle=%0d", name, commands-start_count, cycles);
    endtask
    task automatic debug_send(input logic [2:0] command_value);
        do @(negedge dut.pixel_clk); while (!dut.debugger_request_ready);
        debug_command = command_value; debug_request = 1;
        do @(negedge dut.pixel_clk); while (!dut.debugger_ack);
        assert (dut.debugger_ack_result == DBG_OK);
        debug_request = 0;
        repeat (3) @(negedge dut.pixel_clk);
    endtask
    logic [4:0] console_address=0;
    logic console_read=0, console_write=0;
    logic [31:0] console_data=0;
    always @* begin
        force dut.console_mmio_address=console_address;
        force dut.console_mmio_read=console_read;
        force dut.console_mmio_write=console_write;
        force dut.console_mmio_writedata=console_data;
        force dut.console_mmio_byteenable=4'hf;
    end
    task automatic console_read_word(input logic [4:0] offset, output logic [31:0] value);
        @(negedge hps_clk); console_address=offset; console_read=1;
        @(negedge hps_clk);
        assert(dut.console_mmio_readdatavalid && !dut.console_mmio_waitrequest);
        value=dut.console_mmio_readdata; console_read=0;
    endtask
    task automatic console_exchange(input logic [31:0] request_word,
                                    input logic [1:0] expected_result,
                                    output logic [31:0] response_word);
        logic [31:0] before_count,count,value;
        console_read_word(5'h1c,before_count);
        @(negedge hps_clk); console_address=5'h10; console_data=request_word; console_write=1;
        @(negedge hps_clk); console_write=0;
        count=before_count;
        for(int n=0;n<1000 && count==before_count;n++) console_read_word(5'h1c,count);
        assert(count==before_count+1) else $fatal(1,"console request timeout");
        console_read_word(5'h18,value);
        assert(value=={30'd0,expected_result}) else $fatal(1,"console result=%h request=%h",value,request_word);
        console_read_word(5'h14,response_word);
    endtask
    task automatic request_mode(input logic [3:0] opcode);
        logic [31:0] value;
        console_exchange(0,0,value);
        console_exchange({value[31:16],12'd0,opcode},0,value);
    endtask
    task automatic wait_state(input logic [3:0] expected_state, input logic [1:0] expected_source);
        logic [31:0] value;
        for(int n=0;n<1000;n++) begin
            console_exchange(0,0,value);
            if(value[3:0]==expected_state && value[7:6]==expected_source) begin
                if(expected_state==1)
                    assert(dut.audio_output.diag_muted && wm_data==0);
                return;
            end
            repeat(5000) @(negedge clk);
        end
        $fatal(1,"state timeout expected=%0d source=%0d got=%h",expected_state,expected_source,value);
    endtask

    // Additional framebuffer is a simulation instrument, as in Phase 6G.
    // It consumes actual production PPU pixels; the console overlay has none.
    logic hd_reset, hd_content_reset;
    reset_sync hd_reset_sync(.clk(hdmi_clk), .async_reset_n(!dut.system_reset), .reset(hd_reset));
    reset_sync hd_content_sync(.clk(hdmi_clk), .async_reset_n(!dut.nes_functional_reset && !hd_reset), .reset(hd_content_reset));
    logic [23:0] hd_game, hd_owned, hd_rgb;
    logic hd_hsync,hd_vsync,hd_de,hd_start,hd_boundary,hd_valid;
    logic [10:0] hd_x, hd_render_x;
    logic [9:0] hd_y,hd_render_y;
    logic hd_render_active,tx_de,tx_start,tx_clk;
    logic [1:0] hd_source;
    /* verilator lint_off PINMISSING */
    nes_digital_video_pipeline hd_pipeline (
        .source_clk(clk), .source_reset(dut.nes_functional_reset),
        .source_frame_start(dut.ppu_frame_start), .source_pixel_valid(dut.pixel_valid),
        .source_pixel_x(dut.pixel_x), .source_pixel_y(dut.pixel_y),
        .source_pixel_color(dut.pixel_color), .source_pixel_emphasis(dut.pixel_emphasis),
        .capture_freeze(1'b0), .pixel_clk(hdmi_clk), .pixel_reset(hd_reset),
        .test_pattern_async(1'b0), .developer_layout_async(1'b0),
        .panel_valid(1'b0), .panel_rgb(24'd0), .rgb(hd_game), .hsync(hd_hsync),
        .vsync(hd_vsync), .active_video(hd_de), .frame_start(hd_start),
        .scan_x(hd_x), .scan_y(hd_y), .display_valid(hd_valid),
        .render_x(hd_render_x),.render_y(hd_render_y),.render_active(hd_render_active),
        .ownership_frame_end(hd_boundary)
    );
    nes_console_720p_overlay hd_overlay (
        .focus(dut.console_focus),
        .source_clk(clk), .source_reset(dut.system_reset),
        .requested_status(dut.console_video_request), .buttons(dut.controller1_buttons),
        .held_reset(dut.nes_functional_reset), .inhibit_game(dut.console_inhibit),
        .pixel_clk(hdmi_clk), .pixel_reset(hd_reset), .content_reset(hd_content_reset),
        .frame_end(hd_boundary), .framebuffer_valid(hd_valid),
        .render_x(hd_render_x),.render_y(hd_render_y),.render_active(hd_render_active),
        .game_rgb(hd_game),.rgb(hd_owned),.selected_source(hd_source)
    );
    hdmi_rgb_output hd_adapter (
        .pixel_clk(hdmi_clk), .pixel_reset(hd_reset), .video_enable_async(1'b1),
        .pipeline_rgb(hd_owned), .pipeline_hsync(hd_hsync), .pipeline_vsync(hd_vsync),
        .pipeline_de(hd_de),.pipeline_frame_start(hd_start),
        .tx_pixel_clock(tx_clk),.tx_rgb(hd_rgb),.tx_data_enable(tx_de),.tx_frame_start(tx_start)
    );
    /* verilator lint_on PINMISSING */
    integer vga_pixels=0,hdmi_pixels=0,reset_epochs=0;
    logic old_reset=1;
    always @(negedge clk) begin
        if(dut.nes_functional_reset && !old_reset) reset_epochs++;
        old_reset=dut.nes_functional_reset;
    end
    // Check external raster timing throughout mode changes and cartridge resets.
    logic [1:0] raster_settled=0;
    always @(negedge dut.pixel_clk or negedge key0) begin
        if(!key0) raster_settled=0;
        else if(dut.video_reset) raster_settled=0;
        else begin
            // The retained scanout has two metadata stages after a whole-
            // FPGA reset. Functional console resets never clear this guard.
            if(raster_settled[1]) begin
                assert(vga_hs == !(dut.scan_x>=656 && dut.scan_x<752));
                assert(vga_vs == !(dut.scan_y>=490 && dut.scan_y<492));
                assert(vga_blank == (dut.scan_x<640 && dut.scan_y<480));
                if(!vga_blank) assert({vga_r,vga_g,vga_b}==0);
            end
            raster_settled={raster_settled[0],1'b1};
        end
    end
    task automatic capture_ui;
        integer fd,meta,count;
        // Navigation already skipped the splash. Settle both status banks,
        // then capture while the original boot window is still open: a
        // released button must not allow the splash to reappear.
        repeat(3) @(posedge dut.vga_frame_start);
        @(negedge dut.pixel_clk);
        do @(negedge dut.pixel_clk); while(dut.scan_x!=0 || dut.scan_y!=0);
        assert(dut.console_renderer.animation.boot_frames<24 && !dut.console_renderer.splash)
            else $fatal(1,"menu capture must prove persistent skip inside boot window");
        fd=$fopen("build/phase8a/vga-ui.hex","w");
        meta=$fopen("build/phase8a/vga-ui-status.txt","w");
        $fdisplay(meta,"%h %h %h",dut.console_display_status,dut.console_display_buttons,dut.console_display_reset);
        $fclose(meta);
        count=0;
        repeat(420000) begin
            if(vga_blank) begin
                $fdisplay(fd,"%06h",{vga_r,vga_g,vga_b}); count++;
                assert(dut.nes_functional_reset && !dut.pixel_valid);
            end
            @(negedge dut.pixel_clk);
        end
        $fclose(fd); vga_pixels=count;
        assert(count==307200);
        @(posedge tx_start); @(posedge tx_clk);
        fd=$fopen("build/phase8a/hdmi-ui.hex","w");
        meta=$fopen("build/phase8a/hdmi-ui-status.txt","w");
        $fdisplay(meta,"%h %h %h",hd_overlay.displayed_status,hd_overlay.displayed_buttons,hd_overlay.displayed_reset);
        $fclose(meta);count=0;
        repeat(1237500) begin
            assert(tx_de==(hd_x<1280 && hd_y<720));
            assert(hd_hsync==(hd_x>=1390 && hd_x<1430));
            assert(hd_vsync==(hd_y>=725 && hd_y<730));
            if(tx_de) begin $fdisplay(fd,"%06h",hd_rgb);count++;end
            else assert(hd_rgb==0);
            @(posedge tx_clk);
        end
        $fclose(fd);hdmi_pixels=count;
        assert(count==921600);
    endtask
    task automatic capture_splash;
        integer fd,meta,count;
        // Wait two frames so both displayed status banks show stable MENU.
        repeat(3) @(posedge dut.vga_frame_start);
        @(negedge dut.pixel_clk);
        do @(negedge dut.pixel_clk); while(dut.scan_x!=0 || dut.scan_y!=0);
        fd=$fopen("build/phase8b/vga-splash.hex","w");
        meta=$fopen("build/phase8b/vga-splash-status.txt","w");
        $fdisplay(meta,"%h %h %h %h %h %h",dut.console_display_status,dut.console_display_buttons,dut.console_display_reset,dut.console_display_focus,dut.console_renderer.splash,dut.console_renderer.phase);
        $fclose(meta);
        count=0;
        repeat(420000) begin
            if(vga_blank) begin
                $fdisplay(fd,"%06h",{vga_r,vga_g,vga_b}); count++;
                assert(dut.nes_functional_reset && !dut.pixel_valid);
            end
            @(negedge dut.pixel_clk);
        end
        $fclose(fd); vga_pixels=count;
        assert(count==307200);
        @(posedge tx_start); @(posedge tx_clk);
        fd=$fopen("build/phase8b/hdmi-splash.hex","w");
        meta=$fopen("build/phase8b/hdmi-splash-status.txt","w");
        $fdisplay(meta,"%h %h %h %h %h %h",hd_overlay.displayed_status,hd_overlay.displayed_buttons,hd_overlay.displayed_reset,hd_overlay.displayed_focus,hd_overlay.renderer.splash,hd_overlay.renderer.phase);
        $fclose(meta);count=0;
        repeat(1237500) begin
            assert(tx_de==(hd_x<1280 && hd_y<720));
            assert(hd_hsync==(hd_x>=1390 && hd_x<1430));
            assert(hd_vsync==(hd_y>=725 && hd_y<730));
            if(tx_de) begin $fdisplay(fd,"%06h",hd_rgb);count++;end
            else assert(hd_rgb==0);
            @(posedge tx_clk);
        end
        $fclose(fd);hdmi_pixels=count;
        assert(count==921600);
    endtask
    initial begin : scenario
        logic [31:0] value;
        integer started;
        logic [15:0] stale_epoch,paused_pc;
        repeat(20) @(negedge clk);key0=1;
        wait(!dut.hps_mmio_reset);
        wait_state(1,0);
        assert(!dut.runtime_cartridge_active && dut.nes_functional_reset);
        assert(dut.console_renderer.splash) else $fatal(1,"MENU readiness delayed past splash");
        capture_splash();
        // A normal navigation press interrupts the optional boot animation.
        started=cycles;buttons1=8'h20;
        wait(dut.console_display_focus);
        $display("METRIC focus_cycles=%0d",cycles-started);
        assert(cycles-started<1700000) else $fatal(1,"focus exceeded two frame handoffs");
        // Measure the emitted focus marker too, including beam travel to the
        // Developer row, rather than calling a metadata commit a visible pixel.
        do @(negedge dut.pixel_clk); while(dut.scan_x!=44 || dut.scan_y!=252);
        assert({vga_r,vga_g,vga_b}==24'hf0e9dc)
            else $fatal(1,"focused Developer marker not visible");
        $display("METRIC focus_pixel_cycles=%0d",cycles-started);
        assert(cycles-started<2110000) else $fatal(1,"visible focus latency exceeded bound");
        assert(!dut.console_renderer.splash) else $fatal(1,"navigation failed to skip splash");
        buttons1=0;repeat(20) @(negedge clk);buttons1=8'h10;
        wait(!dut.console_display_focus);buttons1=0;
        capture_ui();
        assert(dut.audio_output.diag_muted);
        // Physical START launches the owned build-time ROM without HPS policy.
        buttons1=8'h08;wait_state(4,1);
        assert(dut.controller_debug_live1==0); // held navigation suppressed
        buttons1=0;repeat(20) @(negedge clk);
        buttons1=8'h81;repeat(20) @(negedge clk);
        assert(dut.controller_debug_live1==8'h81);
        console_exchange(0,0,value);stale_epoch=value[31:16];
        request_mode(1);wait_state(1,0);
        assert(dut.nes_functional_reset && dut.controller_debug_live1==0);
        console_exchange({stale_epoch,16'd2},1,value);
        buttons1=0;
        // Existing software-generated load trace, actual loader/CDC/storage.
        request_mode(4);replay("game_a");wait_state(1,0);
        assert(dut.runtime_cartridge_active && dut.nes_functional_reset);
        request_mode(2);wait_state(4,1);
        wait(dut.nes.internal_cpu_ram.memory[11'h012]==8'hd1);
        wait(!dut.audio_output.diag_muted);
        buttons1=8'h0c; // START + SELECT are authentic game buttons in GAME.
        repeat(50000) @(negedge clk);
        assert(dut.nes.internal_cpu_ram.memory[11'h032]==8'h0c)
            else $fatal(1,"production ROM did not read routed controller input");
        // Keep both buttons held through subsequent menu/developer switches;
        // neither may turn into a local START/SELECT navigation edge.
        request_mode(3);wait_state(7,2);
        debug_send(DBG_PAUSE);wait(dut.debugger_status.state==DBG_PAUSED);
        paused_pc=dut.cpu_debug_pc;
        repeat(2) @(posedge dut.vga_frame_start);
        @(negedge clk);
        assert(dut.cpu_debug_pc==paused_pc && !dut.nes_core_ppu_enable);
        assert(dut.console_video_source==2 && dut.audio_output.diag_muted);
        request_mode(1);wait_state(1,0); // independent of paused execution
        // Unsupported raw mapper request safely stops; no rollback is claimed.
        mmio_write(MMIO_REG_MANIFEST,32'h00000201);
        mmio_write(MMIO_REG_MANIFEST_PRG_BYTES,32'h4000);
        mmio_write(MMIO_REG_MANIFEST_CHR_BYTES,32'h2000);
        mmio_write(MMIO_REG_COMMAND,0);
        wait_state(6,0);
        assert(dut.runtime_loader_error_code==8 && dut.nes_functional_reset);
        buttons1=0;repeat(20) @(negedge clk);started=cycles;buttons1=8'h02;
        wait_state(1,0);
        $display("METRIC error_to_menu_cycles=%0d",cycles-started);
        assert(cycles-started<1700000 && dut.nes_functional_reset);
        buttons1=0;repeat(20) @(negedge clk);
        request_mode(3);wait_state(7,2);
        assert(!dut.debug_destination_valid && !dut.video_reset);
        request_mode(1);wait_state(1,0);
        console_exchange(0,0,value);
        console_exchange({value[31:16],16'd2},3,value);
        request_mode(4);replay("game_b");wait_state(1,0);
        request_mode(2);wait_state(4,1);
        wait(dut.nes.internal_cpu_ram.memory[11'h022]==8'ha6);
        assert(dut.cartridge_nrom_256 && dut.cartridge_chr_is_ram);
        request_mode(1);wait_state(1,0);
        request_mode(4);replay("reload_a");wait_state(1,0);
        for(int n=0;n<3;n++) begin
            request_mode(2);wait_state(4,1);
            request_mode(1);wait_state(1,0);
            request_mode(3);wait_state(7,2);
            request_mode(1);wait_state(1,0);
        end
        request_mode(4);replay("failed_replacement",20);
        @(negedge clk);bridge_reset=1;
        repeat(20) @(negedge clk);bridge_reset=0;
        wait(!dut.hps_mmio_reset);wait_state(1,0);
        assert(!dut.runtime_cartridge_active && dut.nes_functional_reset);
        // Interrupted launch cannot survive the common bridge epoch reset.
        request_mode(2);bridge_reset=1;
        repeat(20) @(negedge clk);bridge_reset=0;
        wait(!dut.hps_mmio_reset);wait_state(1,0);
        assert(dut.nes_functional_reset && !dut.console_game_visible);
        for(int n=0;n<3;n++) begin
            if(n>0) assert(dut.console_renderer.splash);
            if(n==2) begin
                assert(dut.console_renderer.splash);
                request_mode(4);wait_state(2,0);
                wait(dut.console_display_status[3:0]==2);
                assert(!dut.console_renderer.splash);
            end
            key0=0;repeat(100) @(negedge clk);key0=1;
            wait(!dut.hps_mmio_reset);wait_state(1,0);
            assert(dut.nes_functional_reset && !dut.runtime_cartridge_active);
        end
        assert(dut.audio_output.diag_fifo_underruns==0 && dut.audio_output.diag_fifo_overruns==0);
        $display("PASS: Phase 8A default production top cycles=%0d reset_epochs=%0d loader_commands=%0d VGA_pixels=%0d HDMI_pixels=%0d; boot/input/load/replacement/paused-CPU/developer/reset recovery",cycles,reset_epochs,commands,vga_pixels,hdmi_pixels);
        $finish;
    end
    initial begin
        #2_000_000_000;
        $fatal(1,"Phase 8A system watchdog state=%h PC=%h",dut.console_status,dut.cpu_debug_pc);
    end
endmodule
