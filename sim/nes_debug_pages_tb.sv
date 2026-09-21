`timescale 1ns/1ps

module nes_debug_pages_tb;
    import nes_debug_snapshot_pkg::*;

    logic pixel_clk = 1'b0;
    logic reset = 1'b1;
    logic frame_start = 1'b0;
    logic page_next_request = 1'b0;
    logic page_select_valid = 1'b0;
    logic [2:0] requested_page = 3'd0;
    logic [2:0] active_page;
    logic request_pending;
    logic snapshot_valid = 1'b1;
    logic snapshot_update = 1'b0;
    nes_debug_snapshot_t snapshot = '0;
    logic [9:0] scan_x = '0;
    logic [9:0] scan_y = '0;
    logic active_video = 1'b1;
    logic snapshot_stale;
    logic [7:0] panel_red;
    logic [7:0] panel_green;
    logic [7:0] panel_blue;
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;
    logic [7:0] game_red;
    logic [7:0] game_green;
    logic [7:0] game_blue;
    integer page;
    integer x;
    integer y;
    integer trace_file;
    string trace_name;

    always #5 pixel_clk = !pixel_clk;

    nes_debug_page_select selector (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .frame_start(frame_start),
        .page_next_request(page_next_request),
        .page_select_valid(page_select_valid),
        .requested_page(requested_page),
        .active_page(active_page),
        .request_pending(request_pending)
    );

    nes_debug_panel_renderer #(
        .STALE_FRAME_LIMIT(255)
    ) panel (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .snapshot_valid(snapshot_valid),
        .snapshot_update(snapshot_update),
        .snapshot(snapshot),
        .page_select(active_page),
        .frame_start(frame_start),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .active_video(active_video),
        .snapshot_stale(snapshot_stale),
        .red(panel_red),
        .green(panel_green),
        .blue(panel_blue)
    );

    nes_developer_compositor compositor (
        .developer_mode_enable(1'b1),
        .scan_x(scan_x),
        .active_video(active_video),
        .game_red(game_red),
        .game_green(game_green),
        .game_blue(game_blue),
        .panel_red(panel_red),
        .panel_green(panel_green),
        .panel_blue(panel_blue),
        .red(red),
        .green(green),
        .blue(blue)
    );

    task automatic pulse_frame_start;
        begin
            @(negedge pixel_clk);
            frame_start = 1'b1;
            @(negedge pixel_clk);
            frame_start = 1'b0;
            #1;
        end
    endtask

    task automatic queue_direct_page(input logic [2:0] value);
        begin
            @(negedge pixel_clk);
            requested_page = value;
            page_select_valid = 1'b1;
            @(negedge pixel_clk);
            page_select_valid = 1'b0;
            #1;
        end
    endtask

    task automatic queue_next_page;
        begin
            @(negedge pixel_clk);
            page_next_request = 1'b1;
            @(negedge pixel_clk);
            page_next_request = 1'b0;
            #1;
        end
    endtask

    task automatic latch_pixel;
        begin
            @(posedge pixel_clk);
            #1;
        end
    endtask

    task automatic load_fixture;
        begin
            snapshot = '0;
            snapshot.cpu.pc = 16'h80a5;
            snapshot.cpu.a = 8'h03;
            snapshot.cpu.x = 8'h10;
            snapshot.cpu.y = 8'h20;
            snapshot.cpu.sp = 8'hff;
            snapshot.cpu.status = 8'h24;
            snapshot.cpu.opcode = 8'ha9;
            snapshot.cpu.address = 16'h2002;
            snapshot.cpu.read_data = 8'hea;
            snapshot.cpu.write_data = 8'h55;
            snapshot.cpu.read = 1'b1;
            snapshot.cpu.bus_valid = 1'b1;
            snapshot.cpu.bus_owner = 2'd1;
            snapshot.ppu.scanline = 9'd142;
            snapshot.ppu.dot = 9'd221;
            snapshot.ppu.frame_odd = 1'b1;
            snapshot.ppu.ctrl = 8'h80;
            snapshot.ppu.mask = 8'h1e;
            snapshot.ppu.status = 8'ha0;
            snapshot.ppu.pixel_x = 8'h80;
            snapshot.ppu.pixel_y = 8'h70;
            snapshot.ppu.palette_address = 14'h3f12;
            snapshot.ppu.pixel_color = 6'h23;
            snapshot.ppu.pixel_valid = 1'b1;
            snapshot.ppu.nmi_enabled = 1'b1;
            snapshot.ppu.nmi_level = 1'b1;
            snapshot.ppu.vblank = 1'b1;
            snapshot.ppu.sprite_zero_hit = 1'b1;
            snapshot.cartridge.present = 1'b1;
            snapshot.cartridge.mapper_number = 8'h00;
            snapshot.cartridge.prg_address = 15'h40a5;
            snapshot.cartridge.prg_data = 8'h4c;
            snapshot.cartridge.prg_read = 1'b1;
            snapshot.cartridge.chr_address = 13'h12f0;
            snapshot.cartridge.chr_data = 8'h03;
            snapshot.cartridge.chr_read = 1'b1;
            snapshot.cartridge.mirroring = 2'd1;
            snapshot.controller.live1 = 8'h99;
            snapshot.controller.live2 = 8'h42;
            snapshot.controller.shift1 = 8'ha5;
            snapshot.controller.shift2 = 8'h5a;
            snapshot.controller.index1 = 4'h3;
            snapshot.controller.index2 = 4'h7;
            snapshot.controller.serial1 = 1'b1;
            snapshot.controller.read_4016 = 1'b1;
            snapshot.dma.source_page = 8'h02;
            snapshot.dma.source_address = 16'h02c1;
            snapshot.dma.source_data = 8'h5a;
            snapshot.dma.byte_index = 8'hc1;
            snapshot.dma.oam_data = 8'ha5;
            snapshot.dma.phase = 3'd3;
            snapshot.dma.started_odd = 1'b1;
            snapshot.dma.elapsed_slots = 10'h201;
            snapshot.dma.read_count = 9'h100;
            snapshot.dma.write_count = 9'h100;
            snapshot.dma.bus_owner = 2'd1;
            snapshot.dma.read_event = 1'b1;
            snapshot.dma.alignment_cycle = 1'b1;
            snapshot.system.snapshot_id = 32'h0000012c;
            snapshot.system.source_frame_number = 32'h0000012c;
            snapshot.system.nmi_count = 32'h00000129;
            snapshot.system.dma_count = 32'h00000129;
            snapshot.system.controller_poll_count = 32'h00000129;
            snapshot.system.cpu_slot_count = 32'h0087de98;
            snapshot.system.ppu_cycle_count = 32'h0197a4a8;
            snapshot.system.prg_read_count = 32'h00034567;
            snapshot.system.chr_read_count = 32'h00045678;
        end
    endtask

    initial begin
        load_fixture();
        $dumpfile("build/sim/nes_debug_pages.fst");
        $dumpvars(0, nes_debug_pages_tb);

        repeat (3) @(negedge pixel_clk);
        reset = 1'b0;
        @(posedge pixel_clk);
        #1;
        assert (active_page == 3'd0);
        assert (!snapshot_stale);

        // A request in the middle of a frame is pending and cannot alter the
        // renderer-visible page until the next frame boundary.
        scan_x = 10'd520;
        scan_y = 10'd0;
        queue_next_page();
        assert (request_pending && (active_page == 3'd0));
        latch_pixel();
        assert (panel.display_character == 8'h4f); // OVERVIEW
        pulse_frame_start();
        assert (!request_pending && (active_page == 3'd1));
        latch_pixel();
        assert (panel.display_character == 8'h43); // CPU/BUS

        // Required 0->1->2->3->4->0 wrapping, plus deterministic reset.
        queue_next_page(); pulse_frame_start(); assert (active_page == 3'd2);
        queue_next_page(); pulse_frame_start(); assert (active_page == 3'd3);
        queue_next_page(); pulse_frame_start(); assert (active_page == 3'd4);
        queue_next_page();
        assert (active_page == 3'd4);
        pulse_frame_start();
        assert (active_page == 3'd0);

        // Invalid direct page values sanitize to Page 0.
        queue_direct_page(3'd7);
        pulse_frame_start();
        assert (active_page == 3'd0);

        // Page changes never alter game-region RGB.
        scan_x = 10'd100;
        scan_y = 10'd100;
        game_red = 8'h12;
        game_green = 8'h34;
        game_blue = 8'h56;
        queue_direct_page(3'd4);
        pulse_frame_start();
        latch_pixel();
        assert ({red, green, blue} == 24'h123456);

        // Capture one complete 640x480 combined frame for every page. Dumping
        // is disabled here to keep the required FST compact.
        $dumpoff;
        for (page = 0; page < 5; page = page + 1) begin
            queue_direct_page(page[2:0]);
            pulse_frame_start();
            assert (active_page == page[2:0]);
            trace_name = $sformatf(
                "build/sim/phase4ed_page%0d_combined_pixels.txt", page);
            trace_file = $fopen(trace_name, "w");
            assert (trace_file != 0);
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    scan_x = x[9:0];
                    scan_y = y[9:0];
                    game_red = x[7:0];
                    game_green = y[7:0];
                    game_blue = x[7:0] ^ y[7:0];
                    latch_pixel();
                    $fwrite(trace_file, "%02x%02x%02x\n", red, green, blue);
                end
            end
            $fclose(trace_file);
        end

        reset = 1'b1;
        @(posedge pixel_clk);
        #1;
        assert (active_page == 3'd0);
        $display("PASS: Phase 4E-D pages=5 frames=5 pixels=1536000 wrap=0 frame_latched=1");
        $finish;
    end
endmodule
