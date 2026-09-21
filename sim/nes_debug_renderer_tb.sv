`timescale 1ns/1ps

module nes_debug_renderer_tb;
    import debug_font_pkg::*;
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
    logic [7:0] normal_red = '0;
    logic [7:0] normal_green = '0;
    logic [7:0] normal_blue = '0;
    logic snapshot_stale;
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;

    integer trace_file;
    integer x;
    integer y;
    integer nibble;
    integer font_file;
    integer font_rows;
    integer font_scan_result;
    logic [7:0] font_character;
    logic [3:0] font_row_number;
    logic [5:0] font_expected;
    logic [23:0] first_debug_color;

    always #5 pixel_clk = !pixel_clk;

    nes_debug_renderer #(
        .STALE_FRAME_LIMIT(2)
    ) dut (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .developer_mode_enable(developer_mode_enable),
        .snapshot_valid(snapshot_valid),
        .snapshot_update(snapshot_update),
        .snapshot(snapshot),
        .frame_start(frame_start),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .active_video(active_video),
        .normal_red(normal_red),
        .normal_green(normal_green),
        .normal_blue(normal_blue),
        .snapshot_stale(snapshot_stale),
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

    initial begin
        $dumpfile("build/sim/nes_debug_renderer.fst");
        $dumpvars(0, nes_debug_renderer_tb);

        repeat (3) @(negedge pixel_clk);
        reset = 1'b0;

        // Exhaustive uppercase hexadecimal mapping.
        for (nibble = 0; nibble < 16; nibble = nibble + 1) begin
            if (debug_hex_char(nibble[3:0]) !==
                ((nibble < 10) ? (8'h30 + nibble[7:0]) :
                                 (8'h41 + nibble[7:0] - 8'd10)))
                $fatal(1, "hex formatter mismatch at nibble %0d", nibble);
        end

        font_file = $fopen("build/sim/debug_font_reference.txt", "r");
        if (font_file == 0)
            $fatal(1, "could not open exhaustive font vectors");
        font_rows = 0;
        font_scan_result = $fscanf(
            font_file, "%h %h %h\n",
            font_character, font_row_number, font_expected
        );
        while (font_scan_result == 3) begin
            if (debug_font_row(font_character, font_row_number[2:0]) !==
                font_expected)
                $fatal(1, "glyph mismatch char=%02x row=%0d", font_character,
                       font_row_number);
            font_rows = font_rows + 1;
            font_scan_result = $fscanf(
                font_file, "%h %h %h\n",
                font_character, font_row_number, font_expected
            );
        end
        $fclose(font_file);
        if (font_rows != 352)
            $fatal(1, "expected 352 exhaustive glyph rows, got %0d", font_rows);

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
        snapshot.ppu.palette_address = 14'h3f12;
        snapshot.ppu.pixel_color = 6'h23;
        snapshot.ppu.nmi_enabled = 1'b1;
        snapshot.ppu.nmi_level = 1'b1;
        snapshot.ppu.vblank = 1'b1;
        snapshot.ppu.sprite_zero_hit = 1'b1;

        snapshot.cartridge.present = 1'b1;
        snapshot.cartridge.mapper_number = 8'h00;
        snapshot.cartridge.nrom_256 = 1'b0;
        snapshot.cartridge.prg_address = 15'h40a5;
        snapshot.cartridge.prg_data = 8'h4c;
        snapshot.cartridge.chr_address = 13'h12f0;
        snapshot.cartridge.chr_data = 8'h03;
        snapshot.cartridge.mirroring = 2'd1;

        snapshot.controller.live1 = 8'h99;
        snapshot.controller.live2 = 8'h42;
        snapshot.controller.shift1 = 8'ha5;
        snapshot.controller.shift2 = 8'h5a;
        snapshot.controller.index1 = 4'd3;
        snapshot.controller.index2 = 4'd7;

        snapshot.dma.active = 1'b0;
        snapshot.dma.source_page = 8'h02;
        snapshot.dma.source_address = 16'h02c1;
        snapshot.dma.byte_index = 8'hc1;
        snapshot.dma.elapsed_slots = 10'h201;
        snapshot.dma.read_count = 9'h100;
        snapshot.dma.write_count = 9'h100;
        snapshot.dma.bus_owner = 2'd1;

        snapshot.system.snapshot_id = 32'h0000012c;
        snapshot.system.source_frame_number = 32'h0000012c;
        snapshot.system.nmi_count = 32'h00000129;
        snapshot.system.dma_count = 32'h00000129;
        snapshot.system.controller_poll_count = 32'h00000129;
        snapshot.system.cpu_slot_count = 32'h0087de98;
        snapshot.system.ppu_cycle_count = 32'h0197a4a8;

        // Reset/invalid status and a strict RGB bypass check.
        scan_x = 10'd0;
        scan_y = 10'd0;
        normal_red = 8'h12;
        normal_green = 8'h34;
        normal_blue = 8'h56;
        #1;
        if ({red, green, blue} !== 24'h123456)
            $fatal(1, "normal-mode RGB bypass mismatch");
        if (snapshot_stale)
            $fatal(1, "snapshot stale asserted after reset");

        developer_mode_enable = 1'b1;
        scan_x = 10'd168; // status word, row 1 / column 20
        scan_y = 10'd24;
        #1;
        if (dut.display_character !== 8'h49)
            $fatal(1, "INVALID status was not selected");

        snapshot_valid = 1'b1;
        pulse_snapshot_update();
        #1;
        if (snapshot_stale)
            $fatal(1, "fresh snapshot marked stale");
        if (dut.display_character !== 8'h56)
            $fatal(1, "VALID status was not selected");

        pulse_frame_start();
        if (snapshot_stale)
            $fatal(1, "snapshot became stale one frame too early");
        pulse_frame_start();
        if (!snapshot_stale)
            $fatal(1, "snapshot did not become stale at threshold");
        #1;
        if (dut.display_character !== 8'h53)
            $fatal(1, "STALE status was not selected");
        pulse_snapshot_update();
        if (snapshot_stale)
            $fatal(1, "snapshot update did not clear stale state");

        // The rendered page is independent of both normal-game pixel inputs.
        scan_x = 10'd20;
        scan_y = 10'd20;
        normal_red = 8'h00;
        normal_green = 8'h00;
        normal_blue = 8'h00;
        #1 first_debug_color = {red, green, blue};
        normal_red = 8'hff;
        normal_green = 8'h5a;
        normal_blue = 8'ha5;
        #1;
        if ({red, green, blue} !== first_debug_color)
            $fatal(1, "debug output depends on normal NES pixels");

        trace_file = $fopen("build/sim/phase4eb_developer_pixels.txt", "w");
        if (trace_file == 0)
            $fatal(1, "could not create developer pixel trace");

        normal_red = 8'hde;
        normal_green = 8'had;
        normal_blue = 8'hbe;
        active_video = 1'b1;
        for (y = 0; y < 480; y = y + 1) begin
            for (x = 0; x < 640; x = x + 1) begin
                scan_x = x[9:0];
                scan_y = y[9:0];
                #1;
                $fwrite(trace_file, "%02x%02x%02x\n", red, green, blue);
            end
        end
        $fclose(trace_file);

        $display("PASS: Phase 4E-B renderer/mux/status/frame pixels=307200 glyph_rows=%0d stale_limit=2", font_rows);
        $finish;
    end
endmodule
