`timescale 1ns/1ps

module nes_vga_phase4db_tb;
    logic system_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] async_buttons = 8'h08;
    logic [7:0] synced_buttons;
    logic nes_master_ce;
    logic nes_ppu_ce;
    logic timing_cpu_ce;
    logic timing_apu_ce;
    logic [1:0] cartridge_mirroring;
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
    logic controller_port;
    logic controller_cpu_read;
    logic controller_cpu_write;
    logic [7:0] controller_cpu_write_data;
    logic [7:0] controller_cpu_read_data;
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
    integer selected_sprite_ticks = 0;
    integer nonzero_sprite_fetches = 0;
    integer nonzero_sprite_low_fetches = 0;
    integer nonzero_sprite_high_fetches = 0;
    integer sprite_slot0_loads = 0;
    integer sprite_slot0_nonzero_loads = 0;
    integer sprite_slot0_x_zero = 0;
    integer opaque_sprite_ticks = 0;
    integer compared_pixels = 0;
    integer trace_file;

    always #10 system_clk <= !system_clk;
    always #20 pixel_clk <= !pixel_clk;

    nes_timing_gen rate_generator (
        .clk(system_clk), .reset(reset),
        .nes_master_ce(nes_master_ce), .ppu_ce(nes_ppu_ce),
        .cpu_ce(timing_cpu_ce), .apu_ce(timing_apu_ce)
    );

    controller_input_sync #(.WIDTH(8)) input_synchronizer (
        .clk(system_clk), .reset(reset),
        .async_buttons(async_buttons), .synced_buttons(synced_buttons)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(system_clk), .reset(reset),
        .controller1_buttons(synced_buttons),
        .controller2_buttons(8'h00),
        .cpu_port(controller_port), .cpu_read(controller_cpu_read),
        .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data),
        .debug_strobe(), .debug_live_controller1(),
        .debug_live_controller2(), .debug_shift_controller1(),
        .debug_shift_controller2(), .debug_index_controller1(),
        .debug_index_controller2(), .debug_serial_controller1(),
        .debug_serial_controller2(), .debug_read_4016(),
        .debug_read_4017(), .debug_latch_event()
    );

    nes_cartridge #(
        .MAPPER_NUMBER(0), .PRG_ROM_BYTES(16384),
        .CHR_IS_RAM(1'b0), .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd1),
        .PRG_INIT_FILE("build/cartridge/phase4db_playable_nrom128.prg.hex"),
        .CHR_INIT_FILE("build/cartridge/phase4db_playable_nrom128.chr.hex")
    ) cartridge (
        .clk(system_clk), .reset(reset),
        .cpu_address(cart_cpu_address), .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write), .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .cartridge_present(), .mapper_number(), .nrom_256(),
        .chr_is_ram(), .mirroring_mode(cartridge_mirroring),
        .debug_prg_address(), .debug_prg_data(),
        .debug_chr_address(), .debug_chr_data(), .debug_prg_read(),
        .debug_prg_write(), .debug_prg_ram_read(),
        .debug_prg_ram_write(), .debug_chr_read(), .debug_chr_write()
    );

    nes_core nes (
        .clk(system_clk), .reset(reset), .nes_enable(nes_ppu_ce),
        .irq(1'b0), .mirroring_mode(cartridge_mirroring),
        .cart_cpu_address(cart_cpu_address), .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_address(), .apu_cpu_read(), .apu_cpu_write(),
        .apu_cpu_write_data(), .apu_cpu_read_data(8'h00),
        .dmc_mem_request(1'b0), .dmc_mem_address(16'h0000),
        .dmc_mem_acknowledge(), .dmc_mem_read_data(),
        .controller_port(controller_port),
        .controller_cpu_read(controller_cpu_read),
        .controller_cpu_write(controller_cpu_write),
        .controller_cpu_write_data(controller_cpu_write_data),
        .controller_cpu_read_data(controller_cpu_read_data),
        .chr_addr(chr_address), .chr_read(chr_read), .chr_write(chr_write),
        .chr_write_data(chr_write_data), .chr_read_data(chr_read_data),
        .ppu_enable(ppu_enable), .cpu_cycle_slot(cpu_cycle_slot),
        .cpu_enable(), .scheduler_phase(), .cpu_address(),
        .cpu_write_data(), .cpu_read_data(), .cpu_write_enable(),
        .cpu_read_enable(), .cpu_bus_valid(), .cpu_debug_a(),
        .cpu_debug_x(), .cpu_debug_y(), .cpu_debug_sp(),
        .cpu_debug_pc(cpu_debug_pc), .cpu_debug_status(),
        .cpu_debug_instruction(),
        .cpu_debug_execution_state(),
        .cpu_bus_target(), .cpu_ram_address(), .cpu_ppu_register(),
        .cpu_ram_access(), .cpu_ppu_access(), .cpu_apu_access(),
        .cpu_dma_access(), .cpu_controller_access(),
        .cpu_cartridge_access(), .dma_active(), .dma_phase(), .dma_page(),
        .dma_index(), .dma_data(), .dma_stall_cycles(), .dma_read_count(),
        .dma_write_count(), .dma_read_event(), .dma_write_event(),
        .dma_complete_event(dma_complete_event), .dma_start_event(),
        .dma_cpu_stall(), .dma_source_address(), .dma_source_data(),
        .dma_started_odd(), .dma_dummy_cycle(), .dma_alignment_cycle(),
        .dma_source_target(), .internal_bus_owner(),
        .dmc_dma_active(), .dmc_dma_cpu_stall(), .dmc_dma_phase(),
        .dmc_dma_started_odd(), .dmc_dma_elapsed_cycles(),
        .dmc_dma_read_event(), .dmc_dma_start_event(),
        .dmc_dma_complete_event(), .dmc_source_target(), .ppu_dot(),
        .ppu_scanline(), .ppu_frame_odd(),
        .ppu_frame_start(ppu_frame_start), .ppu_frame_end(),
        .ppu_status_vblank(), .ppu_status_sprite_zero_hit(),
        .ppu_status_sprite_overflow(), .ppu_ctrl(), .ppu_mask(),
        .ppu_nmi_level(), .ppu_nmi_event(ppu_nmi_event),
        .ppu_nmi_suppressed(), .ppu_oam_addr(), .ppu_oam_write_commit(),
        .ppu_oam_collision(), .pixel_valid(pixel_valid),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_palette_address(), .pixel_nes_color(pixel_color),
        .pixel_color_emphasis(pixel_emphasis),
        .pixel_source(pixel_source)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    nes_framebuffer framebuffer (
        .write_clk(system_clk), .write_reset(reset),
        .write_frame_start(ppu_frame_start), .write_valid(pixel_valid),
        .write_x(pixel_x), .write_y(pixel_y), .write_color(pixel_color),
        .write_emphasis(pixel_emphasis), .capture_freeze(1'b0),
        .capture_active(), .capture_complete(capture_complete),
        .capture_pending(capture_pending), .write_bank(capture_write_bank),
        .captured_frames(captured_frames),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .read_clk(pixel_clk), .read_reset(reset),
        .read_frame_end(vga_frame_end), .read_address(framebuffer_address),
        .read_pixel(framebuffer_pixel), .display_valid(display_valid),
        .swap_complete(framebuffer_swap), .read_bank(framebuffer_read_bank),
        .displayed_frames(displayed_frames)
    );

    nes_vga_video video (
        .pixel_clk(pixel_clk), .reset(reset), .test_pattern(1'b0),
        .developer_layout(1'b0),
        .framebuffer_valid(display_valid),
        .framebuffer_pixel(framebuffer_pixel),
        .framebuffer_address(framebuffer_address), .frame_start(),
        .frame_end(vga_frame_end), .line_start(), .scan_x(scan_x),
        .scan_y(scan_y), .render_x(), .render_y(), .render_active(),
        .source_nes_x(), .source_nes_y(),
        .active_video(active_video), .hsync_n(), .vsync_n(), .blank_n(),
        .red(red), .green(green), .blue(blue)
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
            if (ppu_enable && nes.ppu.selected_sprite_count != 0)
                selected_sprite_ticks <= selected_sprite_ticks + 1;
            if (ppu_enable && nes.ppu.sprite_fetch_complete &&
                nes.ppu.sprite_memory_read_data != 0)
                nonzero_sprite_fetches <= nonzero_sprite_fetches + 1;
            if (ppu_enable && nes.ppu.sprite_fetch_complete &&
                nes.ppu.sprite_fetch_phase == 3'd5 &&
                nes.ppu.sprite_memory_read_data != 0)
                nonzero_sprite_low_fetches <=
                    nonzero_sprite_low_fetches + 1;
            if (ppu_enable && nes.ppu.sprite_fetch_complete &&
                nes.ppu.sprite_fetch_phase == 3'd7 &&
                nes.ppu.sprite_memory_read_data != 0)
                nonzero_sprite_high_fetches <=
                    nonzero_sprite_high_fetches + 1;
            if (ppu_enable && nes.ppu.sprite_slot_load &&
                nes.ppu.sprite_fetch_slot == 3'd0) begin
                sprite_slot0_loads <= sprite_slot0_loads + 1;
                if (nes.ppu.sprite_renderer.pattern_low[0] != 0 ||
                    nes.ppu.sprite_renderer.pattern_high[0] != 0)
                    sprite_slot0_nonzero_loads <=
                        sprite_slot0_nonzero_loads + 1;
            end
            if (ppu_enable && nes.ppu.sprite_renderer.slot_valid[0] &&
                nes.ppu.sprite_renderer.x_counter[0] == 0 &&
                (nes.ppu.sprite_renderer.pattern_low[0] != 0 ||
                 nes.ppu.sprite_renderer.pattern_high[0] != 0))
                sprite_slot0_x_zero <= sprite_slot0_x_zero + 1;
            if (ppu_enable && nes.ppu.sprite_opaque)
                opaque_sprite_ticks <= opaque_sprite_ticks + 1;
            if (ppu_frame_start)
                current_sprite_x <= -1;
            if (pixel_valid && pixel_source == 2'd2 &&
                current_sprite_x < 0) begin
                current_sprite_x <= 32'(pixel_x);
                sprite_pixels <= sprite_pixels + 1;
            end else if (pixel_valid && pixel_source == 2'd2)
                sprite_pixels <= sprite_pixels + 1;

            if (framebuffer.accept_write) begin
                shadow_address = 32'({pixel_y, pixel_x});
                case (framebuffer.selected_write_bank)
                    2'd1: shadow1[shadow_address] <=
                        {pixel_emphasis, pixel_color};
                    2'd2: shadow2[shadow_address] <=
                        {pixel_emphasis, pixel_color};
                    default: shadow0[shadow_address] <=
                        {pixel_emphasis, pixel_color};
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
                    assert (framebuffer_read_bank == selected_bank);
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
        integer starting_poll;
        logic [1:0] first_bank;

        trace_file = $fopen("build/sim/phase4db_vga_pixels.txt", "w");
        assert (trace_file != 0);
        bank_sprite_x[0] = -1;
        bank_sprite_x[1] = -1;
        bank_sprite_x[2] = -1;
        repeat (10) @(posedge system_clk);
        reset = 1'b0;

        while (nes.internal_cpu_ram.memory[11'h002] != 8'h01)
            @(posedge system_clk);
        async_buttons = 8'h00;
        while (nes.internal_cpu_ram.memory[11'h010] != 8'h00)
            @(posedge system_clk);

        trace_complete_vga_frame();
        first_bank = framebuffer_read_bank;
        first_nes_x = bank_sprite_x[first_bank];
        assert (compared_pixels == 640 * 480);

        starting_poll = 32'(nes.internal_cpu_ram.memory[11'h012]);
        async_buttons = 8'h80;
        while (32'(nes.internal_cpu_ram.memory[11'h012]) == starting_poll)
            @(posedge system_clk);
        while (nes.internal_cpu_ram.memory[11'h003] != 8'h7a)
            @(posedge system_clk);
        async_buttons = 8'h00;

        second_nes_x = -1;
        while (second_nes_x != first_nes_x + 2) begin
            do @(negedge pixel_clk);
            while (!(active_video && scan_x == 0 && scan_y == 0 &&
                     framebuffer_read_bank != first_bank &&
                     bank_sprite_x[framebuffer_read_bank] >= 0));
            second_nes_x = bank_sprite_x[framebuffer_read_bank];
            first_bank = framebuffer_read_bank;
        end

        assert ((64 + 2 * second_nes_x) - (64 + 2 * first_nes_x) == 4)
            else $fatal(1, "VGA movement did not scale from two to four pixels");
        assert (!write_range_error && !write_sequence_error);
        assert (captured_frames >= 3 && displayed_frames >= 2);
        assert (nmi_events >= 2 && dma_completions >= 2);
        assert (ppu_ticks == cpu_slots * 3 ||
                ppu_ticks == cpu_slots * 3 + 1 ||
                ppu_ticks == cpu_slots * 3 + 2);
        assert (cpu_debug_pc >= 16'h8000 && cpu_debug_pc < 16'h9200);

        $fclose(trace_file);
        $display("PASS: Phase 4D-B playable cartridge -> NES -> framebuffer -> VGA");
        $display("system=%0d ppu=%0d cpu_slots=%0d nmi=%0d dma=%0d captured=%0d displayed=%0d pixels=%0d sprite_nes=%0d->%0d",
                 system_cycles, ppu_ticks, cpu_slots, nmi_events,
                 dma_completions, captured_frames, displayed_frames,
                 compared_pixels, first_nes_x, second_nes_x);
        $finish;
    end

    initial begin
        repeat (15_000_000) @(posedge system_clk);
        $fatal(1, "Phase 4D-B playable VGA timeout pc=%04x state=%02x poll=%02x x=%02x captured=%0d displayed=%0d bank=%0d sprites=%0d/%0d/%0d pixels=%0d selected=%0d fetch=%0d low=%0d high=%0d loads=%0d nzloads=%0d xzero=%0d opaque=%0d oam=%02x/%02x/%02x/%02x",
               cpu_debug_pc, nes.internal_cpu_ram.memory[11'h002],
               nes.internal_cpu_ram.memory[11'h012],
               nes.internal_cpu_ram.memory[11'h003], captured_frames,
               displayed_frames, framebuffer_read_bank,
               bank_sprite_x[0], bank_sprite_x[1], bank_sprite_x[2],
               sprite_pixels, selected_sprite_ticks, nonzero_sprite_fetches,
               nonzero_sprite_low_fetches, nonzero_sprite_high_fetches,
               sprite_slot0_loads, sprite_slot0_nonzero_loads,
               sprite_slot0_x_zero, opaque_sprite_ticks,
               nes.ppu.oam.primary_oam[0],
               nes.ppu.oam.primary_oam[1], nes.ppu.oam.primary_oam[2],
               nes.ppu.oam.primary_oam[3]);
    end
endmodule
