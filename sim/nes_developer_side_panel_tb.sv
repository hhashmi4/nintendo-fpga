`timescale 1ns/1ps

module nes_developer_side_panel_tb;
    import nes_debug_snapshot_pkg::*;

    logic pixel_clk = 1'b0;
    logic reset = 1'b1;
    logic developer_mode_enable = 1'b0;
    logic snapshot_valid = 1'b0;
    logic snapshot_update = 1'b0;
    nes_debug_snapshot_t snapshot = '0;
    logic frame_start = 1'b0;
    logic [9:0] scan_x = '0;
    logic [9:0] scan_y = '0;
    logic active_video = 1'b1;
    logic [7:0] game_red = 8'h12;
    logic [7:0] game_green = 8'h34;
    logic [7:0] game_blue = 8'h56;
    logic [7:0] panel_red;
    logic [7:0] panel_green;
    logic [7:0] panel_blue;
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;
    logic snapshot_stale;

    logic [9:0] boundary_x [0:7];
    logic [23:0] held_panel_color;
    integer trace_file;
    integer index;
    integer x;
    integer y;

    always #5 pixel_clk = !pixel_clk;

    nes_debug_panel_renderer #(
        .STALE_FRAME_LIMIT(2)
    ) panel (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .snapshot_valid(snapshot_valid),
        .snapshot_update(snapshot_update),
        .snapshot(snapshot),
        .page_select(3'd0),
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
        .developer_mode_enable(developer_mode_enable),
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
        end
    endtask

    task automatic pulse_snapshot_update;
        begin
            @(negedge pixel_clk);
            snapshot_update = 1'b1;
            @(negedge pixel_clk);
            snapshot_update = 1'b0;
        end
    endtask

    task automatic latch_panel_pixel;
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
            snapshot.cpu.bus_owner = 2'd1;
            snapshot.ppu.scanline = 9'd142;
            snapshot.ppu.dot = 9'd221;
            snapshot.ppu.frame_odd = 1'b1;
            snapshot.ppu.ctrl = 8'h80;
            snapshot.ppu.mask = 8'h1e;
            snapshot.ppu.status = 8'ha0;
            snapshot.ppu.nmi_level = 1'b1;
            snapshot.ppu.vblank = 1'b1;
            snapshot.ppu.sprite_zero_hit = 1'b1;
            snapshot.cartridge.present = 1'b1;
            snapshot.cartridge.mapper_number = 8'h00;
            snapshot.cartridge.nrom_256 = 1'b0;
            snapshot.cartridge.prg_address = 15'h40a5;
            snapshot.cartridge.chr_address = 13'h12f0;
            snapshot.cartridge.mirroring = 2'd1;
            snapshot.controller.live1 = 8'h99;
            snapshot.dma.source_page = 8'h02;
            snapshot.dma.byte_index = 8'hc1;
            snapshot.system.snapshot_id = 32'h0000012c;
            snapshot.system.source_frame_number = 32'h0000012c;
            snapshot.system.nmi_count = 32'h00000129;
            snapshot.system.dma_count = 32'h00000129;
        end
    endtask

    initial begin
        boundary_x[0] = 10'd0;
        boundary_x[1] = 10'd1;
        boundary_x[2] = 10'd510;
        boundary_x[3] = 10'd511;
        boundary_x[4] = 10'd512;
        boundary_x[5] = 10'd513;
        boundary_x[6] = 10'd638;
        boundary_x[7] = 10'd639;
        load_fixture();

        $dumpfile("build/sim/nes_developer_side_panel.fst");
        $dumpvars(0, nes_developer_side_panel_tb);

        repeat (3) @(negedge pixel_clk);
        reset = 1'b0;

        // Normal mode is a strict RGB bypass at every required boundary.
        for (y = 0; y <= 479; y = y + 479) begin
            scan_y = y[9:0];
            for (index = 0; index < 8; index = index + 1) begin
                scan_x = boundary_x[index];
                latch_panel_pixel();
                assert ({red, green, blue} == 24'h123456);
            end
        end

        // Developer selection is exact at x=511/512 for both vertical edges.
        developer_mode_enable = 1'b1;
        snapshot_valid = 1'b1;
        pulse_snapshot_update();
        for (y = 0; y <= 479; y = y + 479) begin
            scan_y = y[9:0];
            for (index = 0; index < 8; index = index + 1) begin
                scan_x = boundary_x[index];
                latch_panel_pixel();
                if (scan_x < 10'd512) begin
                    assert ({red, green, blue} == 24'h123456);
                end else begin
                    assert ({red, green, blue} ==
                            {panel_red, panel_green, panel_blue});
                end
            end
        end

        // NES/game RGB changes cannot affect a panel pixel.
        scan_x = 10'd520;
        scan_y = 10'd64;
        latch_panel_pixel();
        held_panel_color = {red, green, blue};
        game_red = 8'hff;
        game_green = 8'h00;
        game_blue = 8'haa;
        #1;
        assert ({red, green, blue} == held_panel_color);

        // Snapshot changes cannot affect a game pixel.
        scan_x = 10'd100;
        scan_y = 10'd64;
        snapshot = '1;
        #1;
        assert ({red, green, blue} == 24'hff00aa);
        load_fixture();

        // INVALID -> VALID -> STALE -> VALID health sequence.
        scan_x = 10'd520;
        scan_y = 10'd16;
        snapshot_valid = 1'b0;
        #1;
        assert (panel.display_character == 8'h49);
        snapshot_valid = 1'b1;
        pulse_snapshot_update();
        #1;
        assert (!snapshot_stale && panel.display_character == 8'h56);
        pulse_frame_start();
        assert (!snapshot_stale);
        pulse_frame_start();
        #1;
        assert (snapshot_stale && panel.display_character == 8'h53);
        pulse_snapshot_update();
        assert (!snapshot_stale);

        // Full deterministic synthetic combined frame for software comparison.
        trace_file = $fopen("build/sim/phase4ec_combined_pixels.txt", "w");
        assert (trace_file != 0);
        active_video = 1'b1;
        for (y = 0; y < 480; y = y + 1) begin
            for (x = 0; x < 640; x = x + 1) begin
                scan_x = x[9:0];
                scan_y = y[9:0];
                game_red = x[7:0];
                game_green = y[7:0];
                game_blue = x[7:0] ^ y[7:0];
                latch_panel_pixel();
                $fwrite(trace_file, "%02x%02x%02x\n", red, green, blue);
            end
        end
        $fclose(trace_file);

        reset = 1'b1;
        @(posedge pixel_clk);
        assert (!snapshot_stale);
        $display("PASS: Phase 4E-C panel/compositor boundaries=16 pixels=307200 stale_limit=2");
        $finish;
    end
endmodule
