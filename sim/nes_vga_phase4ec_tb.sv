`timescale 1ns/1ps

module nes_vga_phase4ec_tb;
    import nes_debug_snapshot_pkg::*;

    logic clock_50 = 1'b0;
    logic key0 = 1'b0;
    logic sw0 = 1'b0;
    logic sw1 = 1'b0;
    logic sw2 = 1'b0;
    logic sw3 = 1'b0;
    logic sw4 = 1'b0;
    logic sw5 = 1'b1;
    logic sw6 = 1'b0;
    logic sw7 = 1'b0;
    logic sw8 = 1'b0;
    logic sw9 = 1'b0;
    logic [9:0] ledr;
    logic [6:0] hex0;
    logic [6:0] hex1;
    logic [6:0] hex2;
    logic [6:0] hex3;
    logic [6:0] hex4;
    logic [6:0] hex5;
    logic [7:0] vga_r;
    logic [7:0] vga_g;
    logic [7:0] vga_b;
    logic vga_hs;
    logic vga_vs;
    logic vga_clk;
    logic vga_blank_n;
    logic vga_sync_n;

    logic [8:0] shadow0 [0:61439];
    logic [8:0] shadow1 [0:61439];
    logic [8:0] shadow2 [0:61439];
    integer bank_sprite_x [0:2];
    integer current_sprite_x = -1;
    integer system_cycles = 0;
    integer ppu_ticks = 0;
    integer nmi_events = 0;
    integer dma_completions = 0;
    integer controller_polls = 0;
    integer snapshot_updates = 0;
    integer cpu_state_changes = 0;
    integer page_changes = 0;
    integer combined_pixels = 0;
    logic [63:0] last_cpu_state = '0;
    logic have_cpu_state = 1'b0;
    nes_debug_snapshot_t frame_snapshot;

    always #10 clock_50 = !clock_50;

    de1_soc_nes_vga_top #(
        .DEVELOPER_MODE_DEFAULT(1'b1),
        .PRG_INIT_FILE("build/cartridge/phase4db_playable_nrom128.prg.hex"),
        .CHR_INIT_FILE("build/cartridge/phase4db_playable_nrom128.chr.hex")
    ) dut (
        .CLOCK_50(clock_50),
        .KEY0(key0),
        .SW0(sw0), .SW1(sw1), .SW2(sw2), .SW3(sw3), .SW4(sw4),
        .SW5(sw5), .SW6(sw6), .SW7(sw7), .SW8(sw8), .SW9(sw9),
        .LEDR(ledr), .HEX0(hex0), .HEX1(hex1), .HEX2(hex2),
        .HEX3(hex3), .HEX4(hex4), .HEX5(hex5),
        .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b),
        .VGA_HS(vga_hs), .VGA_VS(vga_vs), .VGA_CLK(vga_clk),
        .VGA_BLANK_N(vga_blank_n), .VGA_SYNC_N(vga_sync_n)
    );

    task automatic set_buttons(input logic [7:0] buttons);
        begin
            {sw9, sw8, sw7, sw6, sw5, sw4, sw3, sw2} = buttons;
        end
    endtask

    task automatic request_virtual_next_page;
        logic [2:0] previous_page;
        logic [2:0] expected_page;
        begin
            previous_page = dut.developer_page_active;
            expected_page = (previous_page == 3'd4) ?
                            3'd0 : previous_page + 3'd1;
            do @(negedge dut.pixel_clk);
            while (dut.vga_frame_start);
            force dut.developer_page_next_request = 1'b1;
            @(posedge dut.pixel_clk);
            #1;
            force dut.developer_page_next_request = 1'b0;
            assert (dut.developer_page_active == previous_page);
            assert (dut.developer_page_request_pending);
            while (dut.developer_page_active == previous_page)
                @(posedge dut.pixel_clk);
            #1;
            assert (dut.developer_page_active == expected_page);
            assert (!dut.developer_page_request_pending);
            release dut.developer_page_next_request;
            page_changes = page_changes + 1;
        end
    endtask

    always @(posedge clock_50) begin
        integer shadow_address;
        if (!dut.system_reset) begin
            system_cycles <= system_cycles + 1;
            if (dut.nes_core_ppu_enable)
                ppu_ticks <= ppu_ticks + 1;
            if (dut.ppu_nmi_event)
                nmi_events <= nmi_events + 1;
            if (dut.dma_complete_event)
                dma_completions <= dma_completions + 1;
            if (dut.controller_debug_latch)
                controller_polls <= controller_polls + 1;

            if (dut.ppu_frame_start)
                current_sprite_x <= -1;
            if (dut.pixel_valid && dut.ppu_debug_pixel_source == 2'd2 &&
                current_sprite_x < 0)
                current_sprite_x <= 32'(dut.pixel_x);

            if (dut.framebuffer.accept_write) begin
                shadow_address = 32'({dut.pixel_y, dut.pixel_x});
                case (dut.framebuffer.selected_write_bank)
                    2'd1: shadow1[shadow_address] <=
                        {dut.pixel_emphasis, dut.pixel_color};
                    2'd2: shadow2[shadow_address] <=
                        {dut.pixel_emphasis, dut.pixel_color};
                    default: shadow0[shadow_address] <=
                        {dut.pixel_emphasis, dut.pixel_color};
                endcase
            end
            if (dut.capture_complete)
                bank_sprite_x[dut.framebuffer.completed_bank] <=
                    current_sprite_x;

        end
    end

    always @(posedge dut.pixel_clk) begin
        logic [63:0] current_cpu_state;
        if (!dut.video_reset && dut.debug_destination_update) begin
            snapshot_updates <= snapshot_updates + 1;
            current_cpu_state = {
                dut.debug_destination_snapshot.cpu.pc,
                dut.debug_destination_snapshot.cpu.a,
                dut.debug_destination_snapshot.cpu.x,
                dut.debug_destination_snapshot.cpu.y,
                dut.debug_destination_snapshot.cpu.sp,
                dut.debug_destination_snapshot.cpu.status,
                dut.debug_destination_snapshot.cpu.opcode
            };
            if (have_cpu_state && current_cpu_state != last_cpu_state)
                cpu_state_changes <= cpu_state_changes + 1;
            last_cpu_state <= current_cpu_state;
            have_cpu_state <= 1'b1;
        end
    end

    task automatic capture_real_combined_frame;
        integer trace_file;
        integer metadata_file;
        integer x;
        integer y;
        integer address;
        logic [8:0] expected_pixel;
        logic [1:0] selected_bank;
        begin
            do @(negedge dut.pixel_clk);
            while (!(dut.active_video && dut.scan_x == 0 &&
                     dut.scan_y == 0 && dut.debug_destination_valid &&
                     bank_sprite_x[dut.framebuffer_read_bank] >= 0));
            selected_bank = dut.framebuffer_read_bank;
            frame_snapshot = dut.debug_destination_snapshot;

            metadata_file = $fopen("build/sim/phase4ec_playable_snapshot.txt", "w");
            assert (metadata_file != 0);
            $fwrite(metadata_file, "pc %04x\n", frame_snapshot.cpu.pc);
            $fwrite(metadata_file, "a %02x\n", frame_snapshot.cpu.a);
            $fwrite(metadata_file, "x %02x\n", frame_snapshot.cpu.x);
            $fwrite(metadata_file, "y %02x\n", frame_snapshot.cpu.y);
            $fwrite(metadata_file, "sp %02x\n", frame_snapshot.cpu.sp);
            $fwrite(metadata_file, "status %02x\n", frame_snapshot.cpu.status);
            $fwrite(metadata_file, "opcode %02x\n", frame_snapshot.cpu.opcode);
            $fwrite(metadata_file, "bus_owner %x\n", frame_snapshot.cpu.bus_owner);
            $fwrite(metadata_file, "stalled %x\n", frame_snapshot.cpu.stalled);
            $fwrite(metadata_file, "scanline %03x\n", frame_snapshot.ppu.scanline);
            $fwrite(metadata_file, "dot %03x\n", frame_snapshot.ppu.dot);
            $fwrite(metadata_file, "frame_odd %x\n", frame_snapshot.ppu.frame_odd);
            $fwrite(metadata_file, "ctrl %02x\n", frame_snapshot.ppu.ctrl);
            $fwrite(metadata_file, "mask %02x\n", frame_snapshot.ppu.mask);
            $fwrite(metadata_file, "ppu_status %02x\n", frame_snapshot.ppu.status);
            $fwrite(metadata_file, "nmi_level %x\n", frame_snapshot.ppu.nmi_level);
            $fwrite(metadata_file, "vblank %x\n", frame_snapshot.ppu.vblank);
            $fwrite(metadata_file, "sprite_zero_hit %x\n", frame_snapshot.ppu.sprite_zero_hit);
            $fwrite(metadata_file, "mapper %02x\n", frame_snapshot.cartridge.mapper_number);
            $fwrite(metadata_file, "nrom_256 %x\n", frame_snapshot.cartridge.nrom_256);
            $fwrite(metadata_file, "prg_address %04x\n", frame_snapshot.cartridge.prg_address);
            $fwrite(metadata_file, "chr_address %04x\n", frame_snapshot.cartridge.chr_address);
            $fwrite(metadata_file, "mirroring %x\n", frame_snapshot.cartridge.mirroring);
            $fwrite(metadata_file, "pad1 %02x\n", frame_snapshot.controller.live1);
            $fwrite(metadata_file, "dma_active %x\n", frame_snapshot.dma.active);
            $fwrite(metadata_file, "dma_page %02x\n", frame_snapshot.dma.source_page);
            $fwrite(metadata_file, "dma_index %02x\n", frame_snapshot.dma.byte_index);
            $fwrite(metadata_file, "snapshot_id %08x\n", frame_snapshot.system.snapshot_id);
            $fwrite(metadata_file, "source_frame %08x\n", frame_snapshot.system.source_frame_number);
            $fwrite(metadata_file, "nmi_count %08x\n", frame_snapshot.system.nmi_count);
            $fwrite(metadata_file, "dma_count %08x\n", frame_snapshot.system.dma_count);
            $fclose(metadata_file);

            trace_file = $fopen("build/sim/phase4ec_playable_combined_pixels.txt", "w");
            assert (trace_file != 0);
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    assert (dut.active_video && dut.scan_x == 10'(x) &&
                            dut.scan_y == 10'(y));
                    assert (dut.framebuffer_read_bank == selected_bank);
                    assert (dut.debug_destination_snapshot == frame_snapshot)
                        else $fatal(1, "snapshot tore inside displayed frame");
                    if (x < 512) begin
                        address = (y >> 1) * 256 + (x >> 1);
                        case (selected_bank)
                            2'd1: expected_pixel = shadow1[address];
                            2'd2: expected_pixel = shadow2[address];
                            default: expected_pixel = shadow0[address];
                        endcase
                    end else
                        expected_pixel = 9'h000;
                    $fwrite(trace_file, "%0d %0d %03x %02x%02x%02x\n",
                            x, y, expected_pixel, vga_r, vga_g, vga_b);
                    combined_pixels = combined_pixels + 1;
                    if (x != 639)
                        @(negedge dut.pixel_clk);
                    else if (y != 479) begin
                        do @(negedge dut.pixel_clk);
                        while (!(dut.active_video && dut.scan_x == 0 &&
                                 dut.scan_y == 10'(y + 1)));
                    end
                end
            end
            $fclose(trace_file);
        end
    endtask

    initial begin
        integer first_sprite_x;
        integer first_game_x;
        integer second_sprite_x;
        integer first_snapshot_id;
        integer first_source_frame;
        integer first_nmi_count;
        integer first_dma_count;
        integer starting_poll;
        integer freeze_captures;
        integer freeze_snapshot;
        integer freeze_bank;
        integer long_run_start;
        integer page_index;

        bank_sprite_x[0] = -1;
        bank_sprite_x[1] = -1;
        bank_sprite_x[2] = -1;
        repeat (10) @(posedge clock_50);
        key0 = 1'b1;
        wait (!dut.system_reset && !dut.video_reset);
        assert (dut.developer_mode_enable);

        while (dut.nes.internal_cpu_ram.memory[11'h002] != 8'h01)
            @(posedge clock_50);
        set_buttons(8'h00);
        while (dut.nes.internal_cpu_ram.memory[11'h010] != 8'h00)
            @(posedge clock_50);

        capture_real_combined_frame();
        assert (combined_pixels == 640 * 480);
        first_sprite_x = bank_sprite_x[dut.framebuffer_read_bank];
        first_game_x = 32'(dut.nes.internal_cpu_ram.memory[11'h003]);
        first_snapshot_id = 32'(frame_snapshot.system.snapshot_id);
        first_source_frame = 32'(frame_snapshot.system.source_frame_number);
        first_nmi_count = 32'(frame_snapshot.system.nmi_count);
        first_dma_count = 32'(frame_snapshot.system.dma_count);

        // SW0 remains the game-source test pattern. The panel stays selected.
        sw0 = 1'b1;
        wait (dut.test_pattern);
        do @(negedge dut.pixel_clk);
        while (!(dut.active_video && dut.scan_x == 0 && dut.scan_y == 0));
        assert ({vga_r, vga_g, vga_b} == 24'hffffff);
        do @(negedge dut.pixel_clk);
        while (!(dut.active_video && dut.scan_x == 10'd512 && dut.scan_y == 0));
        assert ({vga_r, vga_g, vga_b} ==
                {dut.panel_vga_red, dut.panel_vga_green, dut.panel_vga_blue});
        sw0 = 1'b0;
        wait (!dut.test_pattern);

        // Real controller polling moves the playable-ROM sprite and appears
        // in a later coherent panel snapshot.
        starting_poll = controller_polls;
        set_buttons(8'h80);
        while (controller_polls == starting_poll)
            @(posedge clock_50);
        while (32'(dut.nes.internal_cpu_ram.memory[11'h003]) !=
               first_game_x + 2)
            @(posedge clock_50);
        while (!(dut.debug_destination_valid &&
                 dut.debug_destination_snapshot.controller.live1 == 8'h80 &&
                 dut.debug_destination_snapshot.system.snapshot_id >
                    frame_snapshot.system.snapshot_id))
            @(posedge dut.pixel_clk);
        set_buttons(8'h00);

        while (bank_sprite_x[dut.framebuffer_read_bank] == first_sprite_x)
            @(negedge dut.pixel_clk);
        second_sprite_x = bank_sprite_x[dut.framebuffer_read_bank];
        assert (second_sprite_x > first_sprite_x);

        // Cycle repeatedly through every page using the internal virtual
        // control hook. Each request is deliberately made mid-frame and must
        // remain pending until the next VGA frame start.
        for (page_index = 0; page_index < 10; page_index = page_index + 1)
            request_virtual_next_page();
        assert (page_changes == 10);
        assert (dut.developer_page_active == 3'd0);

        // SW1 freezes only framebuffer capture. Snapshots and panel state keep
        // advancing while the displayed game bank remains unchanged.
        sw1 = 1'b1;
        wait (dut.freeze_capture);
        wait (!dut.capture_active && !dut.capture_pending);
        freeze_captures = 32'(dut.captured_frames);
        freeze_snapshot = 32'(dut.debug_destination_snapshot.system.snapshot_id);
        freeze_bank = 32'(dut.framebuffer_read_bank);
        while (32'(dut.debug_destination_snapshot.system.snapshot_id) <
               freeze_snapshot + 3)
            @(posedge dut.pixel_clk);
        assert (32'(dut.captured_frames) == freeze_captures);
        assert (32'(dut.framebuffer_read_bank) == freeze_bank);
        sw1 = 1'b0;
        wait (!dut.freeze_capture);

        // Sustained Developer Mode composition remains live for 60 additional
        // coherent snapshots after the directed integration checks.
        long_run_start = 32'(dut.debug_destination_snapshot.system.snapshot_id);
        while (32'(dut.debug_destination_snapshot.system.snapshot_id) <
               long_run_start + 60)
            @(posedge dut.pixel_clk);

        assert (!dut.write_range_error && !dut.write_sequence_error);
        assert (dut.debug_destination_snapshot.system.source_frame_number >
                first_source_frame);
        assert (dut.debug_destination_snapshot.system.nmi_count >
                first_nmi_count);
        assert (dut.debug_destination_snapshot.system.dma_count >
                first_dma_count);
        assert (32'(dut.debug_destination_snapshot.system.snapshot_id) >
                first_snapshot_id);
        assert (nmi_events > first_nmi_count);
        assert (dma_completions > first_dma_count);
        assert (controller_polls > starting_poll);
        assert (snapshot_updates >= 60);
        assert (cpu_state_changes > 0);

        $display("PASS: Phase 4E-C/D playable ROM + coherent multi-page side panel integration");
        $display("system=%0d ppu=%0d frames=%0d snapshots=%0d nmi=%0d dma=%0d polls=%0d cpu_state_changes=%0d page_changes=%0d pixels=%0d sprite=%0d->%0d",
                 system_cycles, ppu_ticks,
                 dut.debug_destination_snapshot.system.source_frame_number,
                 snapshot_updates, nmi_events, dma_completions,
                 controller_polls, cpu_state_changes, page_changes, combined_pixels,
                 first_sprite_x, second_sprite_x);
        $finish;
    end

    initial begin
        repeat (80_000_000) @(posedge clock_50);
        $fatal(1, "Phase 4E-C playable side-panel timeout pc=%04x frame=%0d snapshot=%0d",
               dut.cpu_debug_pc,
               dut.debug_destination_snapshot.system.source_frame_number,
               dut.debug_destination_snapshot.system.snapshot_id);
    end
endmodule
