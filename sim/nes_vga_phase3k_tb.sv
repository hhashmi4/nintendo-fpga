`timescale 1ns/1ps

module nes_vga_phase3k_tb;
    logic system_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic reset = 1'b1;
    logic nes_master_ce;
    logic nes_ppu_ce;
    logic timing_cpu_ce;
    logic timing_apu_ce;
    logic [15:0] cart_cpu_address;
    logic cart_cpu_read;
    logic cart_cpu_write;
    logic [7:0] cart_cpu_write_data;
    logic [7:0] cart_cpu_read_data;
    logic [12:0] chr_address;
    logic chr_read;
    logic chr_write;
    logic [7:0] chr_write_data;
    logic [7:0] chr_read_data;
    logic ppu_enable;
    logic cpu_cycle_slot;
    logic [15:0] cpu_debug_pc;
    logic dma_complete_event;
    logic ppu_frame_start;
    logic ppu_nmi_event;
    logic pixel_valid;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic [5:0] pixel_color;
    logic [2:0] pixel_emphasis;
    logic [1:0] pixel_source;

    logic capture_complete;
    logic capture_pending;
    logic [1:0] capture_write_bank;
    logic [15:0] captured_frames;
    logic write_range_error;
    logic write_sequence_error;
    logic [15:0] framebuffer_address;
    logic [8:0] framebuffer_pixel;
    logic display_valid;
    logic vga_frame_end;
    logic framebuffer_swap;
    logic [1:0] framebuffer_read_bank;
    logic [15:0] displayed_frames;
    logic [9:0] scan_x;
    logic [9:0] scan_y;
    logic active_video;
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;

    logic [8:0] shadow0 [0:61439];
    logic [8:0] shadow1 [0:61439];
    logic [8:0] shadow2 [0:61439];
    integer bank_sprite_x [0:2];
    integer current_sprite_x = -1;
    integer system_cycles = 0;
    integer ppu_ticks = 0;
    integer cpu_slots = 0;
    integer nmi_events = 0;
    integer dma_completions = 0;
    integer sprite_pixels = 0;
    integer compared_pixels = 0;
    integer trace_file;
    logic saw_reset_program = 1'b0;
    logic saw_nmi_program = 1'b0;

    always #10 system_clk <= !system_clk;
    always #20 pixel_clk <= !pixel_clk;

    nes_timing_gen rate_generator (
        .clk(system_clk),
        .reset(reset),
        .nes_master_ce(nes_master_ce),
        .ppu_ce(nes_ppu_ce),
        .cpu_ce(timing_cpu_ce),
        .apu_ce(timing_apu_ce)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off PINMISSING */
    nes_core nes (
        .clk(system_clk),
        .reset(reset),
        .nes_enable(nes_ppu_ce),
        .irq(1'b0),
        .mirroring_mode(2'b00),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_read_data(8'h00),
        .controller_cpu_read_data(8'h00),
        .chr_addr(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .ppu_enable(ppu_enable),
        .cpu_cycle_slot(cpu_cycle_slot),
        .cpu_enable(),
        .scheduler_phase(),
        .cpu_address(),
        .cpu_write_data(),
        .cpu_read_data(),
        .cpu_write_enable(),
        .cpu_bus_valid(),
        .cpu_debug_a(),
        .cpu_debug_x(),
        .cpu_debug_y(),
        .cpu_debug_sp(),
        .cpu_debug_pc(cpu_debug_pc),
        .dma_active(),
        .dma_phase(),
        .dma_page(),
        .dma_index(),
        .dma_data(),
        .dma_stall_cycles(),
        .dma_read_count(),
        .dma_write_count(),
        .dma_read_event(),
        .dma_write_event(),
        .dma_complete_event(dma_complete_event),
        .ppu_dot(),
        .ppu_scanline(),
        .ppu_frame_odd(),
        .ppu_frame_start(ppu_frame_start),
        .ppu_frame_end(),
        .ppu_status_vblank(),
        .ppu_status_sprite_zero_hit(),
        .ppu_status_sprite_overflow(),
        .ppu_ctrl(),
        .ppu_mask(),
        .ppu_nmi_level(),
        .ppu_nmi_event(ppu_nmi_event),
        .ppu_nmi_suppressed(),
        .ppu_oam_addr(),
        .ppu_oam_write_commit(),
        .ppu_oam_collision(),
        .pixel_valid(pixel_valid),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_palette_address(),
        .pixel_nes_color(pixel_color),
        .pixel_color_emphasis(pixel_emphasis),
        .pixel_source(pixel_source)
    );
    /* verilator lint_on PINMISSING */
    /* verilator lint_on PINCONNECTEMPTY */

    nes_vga_diag_memory cartridge (
        .cpu_address(cart_cpu_address),
        .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write),
        .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data)
    );

    nes_framebuffer framebuffer (
        .write_clk(system_clk),
        .write_reset(reset),
        .write_frame_start(ppu_frame_start),
        .write_valid(pixel_valid),
        .write_x(pixel_x),
        .write_y(pixel_y),
        .write_color(pixel_color),
        .write_emphasis(pixel_emphasis),
        .capture_freeze(1'b0),
        .capture_active(),
        .capture_complete(capture_complete),
        .capture_pending(capture_pending),
        .write_bank(capture_write_bank),
        .captured_frames(captured_frames),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .read_clk(pixel_clk),
        .read_reset(reset),
        .read_frame_end(vga_frame_end),
        .read_address(framebuffer_address),
        .read_pixel(framebuffer_pixel),
        .display_valid(display_valid),
        .swap_complete(framebuffer_swap),
        .read_bank(framebuffer_read_bank),
        .displayed_frames(displayed_frames)
    );

    nes_vga_video video (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .test_pattern(1'b0),
        .developer_layout(1'b0),
        .framebuffer_valid(display_valid),
        .framebuffer_pixel(framebuffer_pixel),
        .framebuffer_address(framebuffer_address),
        .frame_start(),
        .frame_end(vga_frame_end),
        .line_start(),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .render_x(),
        .render_y(),
        .render_active(),
        .source_nes_x(),
        .source_nes_y(),
        .active_video(active_video),
        .hsync_n(),
        .vsync_n(),
        .blank_n(),
        .red(red),
        .green(green),
        .blue(blue)
    );

    always @(posedge system_clk) begin
        integer shadow_address;
        if (!reset) begin
            system_cycles <= system_cycles + 1;
            if (ppu_enable)
                ppu_ticks <= ppu_ticks + 1;
            if (cpu_cycle_slot)
                cpu_slots <= cpu_slots + 1;
            if (ppu_nmi_event)
                nmi_events <= nmi_events + 1;
            if (dma_complete_event)
                dma_completions <= dma_completions + 1;
            if (cpu_debug_pc >= 16'h8000 && cpu_debug_pc <= 16'h8092)
                saw_reset_program <= 1'b1;
            if (cpu_debug_pc >= 16'h9000 && cpu_debug_pc <= 16'h9015)
                saw_nmi_program <= 1'b1;

            if (ppu_frame_start)
                current_sprite_x <= -1;
            if (pixel_valid && pixel_source == 2'd2) begin
                sprite_pixels <= sprite_pixels + 1;
                if (pixel_y == 8'd65 && pixel_color == 6'h2a &&
                    current_sprite_x < 0)
                    current_sprite_x <= {24'd0, pixel_x};
            end

            if (framebuffer.accept_write) begin
                shadow_address = 32'({pixel_y, pixel_x});
                case (framebuffer.selected_write_bank)
                    2'd1: shadow1[shadow_address] <= {
                        pixel_emphasis, pixel_color
                    };
                    2'd2: shadow2[shadow_address] <= {
                        pixel_emphasis, pixel_color
                    };
                    default: shadow0[shadow_address] <= {
                        pixel_emphasis, pixel_color
                    };
                endcase
            end

            if (capture_complete)
                bank_sprite_x[framebuffer.completed_bank] <= current_sprite_x;
        end
    end

    task automatic trace_complete_vga_frame;
        integer x;
        integer y;
        integer address;
        logic [8:0] expected_pixel;
        logic [1:0] selected_bank;
        begin
            do @(negedge pixel_clk);
            while (!(active_video && scan_x == 0 && scan_y == 0 &&
                     bank_sprite_x[framebuffer_read_bank] >= 0));
            selected_bank = framebuffer_read_bank;
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    assert (active_video && scan_x == 10'(x) &&
                            scan_y == 10'(y));
                    assert (framebuffer_read_bank == selected_bank)
                        else $fatal(1, "display bank changed in active frame");
                    if (x >= 64 && x < 576) begin
                        address = (y >> 1) * 256 + ((x - 64) >> 1);
                        case (selected_bank)
                            2'd1: expected_pixel = shadow1[address];
                            2'd2: expected_pixel = shadow2[address];
                            default: expected_pixel = shadow0[address];
                        endcase
                        $fwrite(trace_file, "%0d %0d 1 %03x %02x%02x%02x\n",
                                x, y, expected_pixel, red, green, blue);
                    end else begin
                        $fwrite(trace_file, "%0d %0d 0 000 %02x%02x%02x\n",
                                x, y, red, green, blue);
                    end
                    compared_pixels = compared_pixels + 1;
                    if (x != 639)
                        @(negedge pixel_clk);
                    else if (y != 479) begin
                        do @(negedge pixel_clk);
                        while (!(active_video && scan_x == 0 &&
                                 scan_y == 10'(y + 1)));
                    end
                end
            end
        end
    endtask

    initial begin
        integer first_nes_x;
        integer second_nes_x;
        integer movement_trials;
        logic [1:0] first_bank;

        trace_file = $fopen("build/sim/nes_vga_phase3k_pixels.txt", "w");
        assert (trace_file != 0) else $fatal(1, "could not open NES VGA trace");
        bank_sprite_x[0] = -1;
        bank_sprite_x[1] = -1;
        bank_sprite_x[2] = -1;

        repeat (10) @(posedge system_clk);
        reset = 1'b0;

        trace_complete_vga_frame();
        first_bank = framebuffer_read_bank;
        first_nes_x = bank_sprite_x[first_bank];
        assert (compared_pixels == 307200);

        movement_trials = 0;
        second_nes_x = -1;
        while (second_nes_x != ((first_nes_x + 8) & 255) &&
               movement_trials < 6) begin
            do @(negedge pixel_clk);
            while (!(active_video && scan_x == 0 && scan_y == 0 &&
                     framebuffer_read_bank != first_bank &&
                     bank_sprite_x[framebuffer_read_bank] >= 0));
            second_nes_x = bank_sprite_x[framebuffer_read_bank];
            if (second_nes_x != ((first_nes_x + 8) & 255)) begin
                first_nes_x = second_nes_x;
                first_bank = framebuffer_read_bank;
                movement_trials = movement_trials + 1;
            end
        end
        assert (second_nes_x == ((first_nes_x + 8) & 255))
            else $fatal(1, "no displayed NES +8 movement pair after %0d trials",
                        movement_trials);
        assert ((64 + 2 * second_nes_x) - (64 + 2 * first_nes_x) == 16)
            else $fatal(1, "VGA sprite displacement was not +16");

        assert (!write_range_error && !write_sequence_error);
        assert (captured_frames >= 3 && displayed_frames >= 2);
        assert (nmi_events >= 2 && dma_completions >= 3);
        assert (sprite_pixels > 0);
        assert (saw_reset_program && saw_nmi_program);
        assert (ppu_ticks == cpu_slots * 3 ||
                ppu_ticks == cpu_slots * 3 + 1 ||
                ppu_ticks == cpu_slots * 3 + 2);

        $fclose(trace_file);
        $display("Phase 3K integrated NES-to-VGA path passed");
        $display("system_cycles=%0d ppu_ticks=%0d cpu_slots=%0d nmi=%0d dma=%0d",
                 system_cycles, ppu_ticks, cpu_slots,
                 nmi_events, dma_completions);
        $display("captured=%0d displayed=%0d compared_pixels=%0d sprite_nes=%0d->%0d sprite_vga=%0d->%0d",
                 captured_frames, displayed_frames, compared_pixels,
                 first_nes_x, second_nes_x,
                 64 + 2 * first_nes_x, 64 + 2 * second_nes_x);
        $finish;
    end

    initial begin
        repeat (10_000_000) @(posedge system_clk);
        $fatal(1, "integrated NES/VGA timeout");
    end
endmodule
