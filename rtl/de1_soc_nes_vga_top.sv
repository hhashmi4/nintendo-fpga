`timescale 1ns/1ps

// Phase 3K physical top. The NES stays in the 50 MHz fabric domain and is
// advanced by an NTSC-rate clock enable; the VGA reader uses a PLL-derived
// 25.2 MHz clock and crosses only through nes_framebuffer's handoff protocol.
module de1_soc_nes_vga_top (
    input  logic       CLOCK_50,
    input  logic       KEY0,
    input  logic       SW0,
    input  logic       SW1,
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5,
    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,
    output logic       VGA_CLK,
    output logic       VGA_BLANK_N,
    output logic       VGA_SYNC_N
);
    logic pixel_clk;
    logic pll_locked;
    logic reset_request_n;
    logic system_reset;
    logic video_reset;
    logic test_pattern;
    logic freeze_capture;
    logic test_pattern_sys;

    logic nes_master_ce;
    logic nes_ppu_ce;
    logic unused_cpu_ce;
    logic unused_apu_ce;
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
    logic cartridge_present;
    logic [7:0] cartridge_mapper_number;
    logic cartridge_nrom_256;
    logic cartridge_chr_is_ram;
    logic [1:0] cartridge_mirroring_mode;
    logic [14:0] cartridge_debug_prg_address;
    logic [7:0] cartridge_debug_prg_data;
    logic [12:0] cartridge_debug_chr_address;
    logic [7:0] cartridge_debug_chr_data;
    logic cartridge_debug_prg_read;
    logic cartridge_debug_prg_write;
    logic cartridge_debug_prg_ram_read;
    logic cartridge_debug_prg_ram_write;
    logic cartridge_debug_chr_read;
    logic cartridge_debug_chr_write;
    logic pixel_valid;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic [5:0] pixel_color;
    logic [2:0] pixel_emphasis;
    logic ppu_frame_start;
    logic dma_complete_event;
    logic ppu_nmi_event;
    logic [15:0] cpu_debug_pc;

    logic capture_active;
    logic capture_complete;
    logic capture_pending;
    logic [1:0] capture_write_bank;
    logic [15:0] captured_frames;
    logic write_range_error;
    logic write_sequence_error;
    logic [15:0] framebuffer_address;
    logic [8:0] framebuffer_pixel;
    logic framebuffer_valid;
    logic vga_frame_end;
    logic framebuffer_swap;
    logic [1:0] framebuffer_read_bank;
    logic [15:0] displayed_frames;
    logic [9:0] scan_x;
    logic [9:0] scan_y;
    logic [7:0] source_nes_x;
    logic [7:0] source_nes_y;
    logic active_video;
    logic vga_frame_start;
    logic vga_line_start;

    logic capture_heartbeat;
    logic vga_heartbeat;
    logic dma_heartbeat;
    logic nmi_heartbeat;

    video_pll pixel_clock_source (
        .ref_clk(CLOCK_50),
        .reset_n(KEY0),
        .pixel_clk(pixel_clk),
        .locked(pll_locked)
    );

    assign reset_request_n = KEY0 && pll_locked;

    reset_sync system_reset_generator (
        .clk(CLOCK_50),
        .async_reset_n(reset_request_n),
        .reset(system_reset)
    );

    reset_sync video_reset_generator (
        .clk(pixel_clk),
        .async_reset_n(reset_request_n),
        .reset(video_reset)
    );

    level_sync test_pattern_video_sync (
        .clk(pixel_clk),
        .reset(video_reset),
        .async_level(SW0),
        .synced_level(test_pattern)
    );

    level_sync test_pattern_system_sync (
        .clk(CLOCK_50),
        .reset(system_reset),
        .async_level(SW0),
        .synced_level(test_pattern_sys)
    );

    level_sync freeze_switch_sync (
        .clk(CLOCK_50),
        .reset(system_reset),
        .async_level(SW1),
        .synced_level(freeze_capture)
    );

    nes_timing_gen nes_rate_generator (
        .clk(CLOCK_50),
        .reset(system_reset),
        .nes_master_ce(nes_master_ce),
        .ppu_ce(nes_ppu_ce),
        .cpu_ce(unused_cpu_ce),
        .apu_ce(unused_apu_ce)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off PINMISSING */
    nes_core nes (
        .clk(CLOCK_50),
        .reset(system_reset),
        .nes_enable(nes_ppu_ce),
        .irq(1'b0),
        .mirroring_mode(cartridge_mirroring_mode),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_address(),
        .apu_cpu_read(),
        .apu_cpu_write(),
        .apu_cpu_write_data(),
        .apu_cpu_read_data(8'h00),
        .controller_port(),
        .controller_cpu_read(),
        .controller_cpu_write(),
        .controller_cpu_write_data(),
        .controller_cpu_read_data(8'h00),
        .chr_addr(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .ppu_enable(),
        .cpu_cycle_slot(),
        .cpu_enable(),
        .scheduler_phase(),
        .cpu_address(),
        .cpu_write_data(),
        .cpu_read_data(),
        .cpu_write_enable(),
        .cpu_read_enable(),
        .cpu_bus_valid(),
        .cpu_debug_a(),
        .cpu_debug_x(),
        .cpu_debug_y(),
        .cpu_debug_sp(),
        .cpu_debug_pc(cpu_debug_pc),
        .cpu_debug_status(),
        .cpu_bus_target(),
        .cpu_ram_address(),
        .cpu_ppu_register(),
        .cpu_ram_access(),
        .cpu_ppu_access(),
        .cpu_apu_access(),
        .cpu_dma_access(),
        .cpu_controller_access(),
        .cpu_cartridge_access(),
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
        .pixel_source()
    );
    /* verilator lint_on PINMISSING */
    /* verilator lint_on PINCONNECTEMPTY */

    nes_cartridge #(
        .MAPPER_NUMBER (0),
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd0),
        .PRG_INIT_FILE ("../build/cartridge/phase4b_display_nrom128.prg.hex"),
        .CHR_INIT_FILE ("../build/cartridge/phase4b_display_nrom128.chr.hex")
    ) cartridge (
        .clk(CLOCK_50),
        .reset(system_reset),
        .cpu_address(cart_cpu_address),
        .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write),
        .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .cartridge_present(cartridge_present),
        .mapper_number(cartridge_mapper_number),
        .nrom_256(cartridge_nrom_256),
        .chr_is_ram(cartridge_chr_is_ram),
        .mirroring_mode(cartridge_mirroring_mode),
        .debug_prg_address(cartridge_debug_prg_address),
        .debug_prg_data(cartridge_debug_prg_data),
        .debug_chr_address(cartridge_debug_chr_address),
        .debug_chr_data(cartridge_debug_chr_data),
        .debug_prg_read(cartridge_debug_prg_read),
        .debug_prg_write(cartridge_debug_prg_write),
        .debug_prg_ram_read(cartridge_debug_prg_ram_read),
        .debug_prg_ram_write(cartridge_debug_prg_ram_write),
        .debug_chr_read(cartridge_debug_chr_read),
        .debug_chr_write(cartridge_debug_chr_write)
    );

    nes_framebuffer framebuffer (
        .write_clk(CLOCK_50),
        .write_reset(system_reset),
        .write_frame_start(ppu_frame_start),
        .write_valid(pixel_valid),
        .write_x(pixel_x),
        .write_y(pixel_y),
        .write_color(pixel_color),
        .write_emphasis(pixel_emphasis),
        .capture_freeze(freeze_capture),
        .capture_active(capture_active),
        .capture_complete(capture_complete),
        .capture_pending(capture_pending),
        .write_bank(capture_write_bank),
        .captured_frames(captured_frames),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .read_clk(pixel_clk),
        .read_reset(video_reset),
        .read_frame_end(vga_frame_end),
        .read_address(framebuffer_address),
        .read_pixel(framebuffer_pixel),
        .display_valid(framebuffer_valid),
        .swap_complete(framebuffer_swap),
        .read_bank(framebuffer_read_bank),
        .displayed_frames(displayed_frames)
    );

    nes_vga_video video (
        .pixel_clk(pixel_clk),
        .reset(video_reset),
        .test_pattern(test_pattern),
        .framebuffer_valid(framebuffer_valid),
        .framebuffer_pixel(framebuffer_pixel),
        .framebuffer_address(framebuffer_address),
        .frame_start(vga_frame_start),
        .frame_end(vga_frame_end),
        .line_start(vga_line_start),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .source_nes_x(source_nes_x),
        .source_nes_y(source_nes_y),
        .active_video(active_video),
        .hsync_n(VGA_HS),
        .vsync_n(VGA_VS),
        .blank_n(VGA_BLANK_N),
        .red(VGA_R),
        .green(VGA_G),
        .blue(VGA_B)
    );

    always_ff @(posedge CLOCK_50) begin
        if (system_reset) begin
            capture_heartbeat <= 1'b0;
            dma_heartbeat <= 1'b0;
            nmi_heartbeat <= 1'b0;
        end else begin
            if (capture_complete)
                capture_heartbeat <= !capture_heartbeat;
            if (dma_complete_event)
                dma_heartbeat <= !dma_heartbeat;
            if (ppu_nmi_event)
                nmi_heartbeat <= !nmi_heartbeat;
        end
    end

    always_ff @(posedge pixel_clk) begin
        if (video_reset)
            vga_heartbeat <= 1'b0;
        else if (vga_frame_start)
            vga_heartbeat <= !vga_heartbeat;
    end

    hex7seg hex0_driver (.value(captured_frames[3:0]), .segments_n(HEX0));
    hex7seg hex1_driver (.value(captured_frames[7:4]), .segments_n(HEX1));
    hex7seg hex2_driver (.value(cpu_debug_pc[3:0]), .segments_n(HEX2));
    hex7seg hex3_driver (.value(cpu_debug_pc[7:4]), .segments_n(HEX3));
    hex7seg hex4_driver (.value(cpu_debug_pc[11:8]), .segments_n(HEX4));
    hex7seg hex5_driver (.value(cpu_debug_pc[15:12]), .segments_n(HEX5));

    assign LEDR[0] = pll_locked;
    assign LEDR[1] = !system_reset;
    assign LEDR[2] = test_pattern_sys;
    assign LEDR[3] = freeze_capture;
    assign LEDR[4] = capture_heartbeat;
    assign LEDR[5] = vga_heartbeat;
    assign LEDR[6] = dma_heartbeat;
    assign LEDR[7] = nmi_heartbeat;
    assign LEDR[8] = write_range_error || write_sequence_error;
    assign LEDR[9] = system_reset || video_reset;

    // ADV7123 samples RGB on VGA_CLK's rising edge. Inverting the internal
    // scan clock gives the DAC a half-cycle of setup after each RTL update.
    assign VGA_CLK = !pixel_clk;
    assign VGA_SYNC_N = 1'b0;

    logic unused_status;
    assign unused_status = nes_master_ce || capture_active || capture_pending ||
                           (|capture_write_bank) || framebuffer_swap ||
                           (|framebuffer_read_bank) || ^displayed_frames ||
                           ^scan_x || ^scan_y || ^source_nes_x ||
                           ^source_nes_y || active_video || vga_line_start ||
                           cartridge_present || ^cartridge_mapper_number ||
                           cartridge_nrom_256 || cartridge_chr_is_ram ||
                           ^cartridge_mirroring_mode ||
                           ^cartridge_debug_prg_address ||
                           ^cartridge_debug_prg_data ||
                           ^cartridge_debug_chr_address ||
                           ^cartridge_debug_chr_data ||
                           cartridge_debug_prg_read ||
                           cartridge_debug_prg_write ||
                           cartridge_debug_prg_ram_read ||
                           cartridge_debug_prg_ram_write ||
                           cartridge_debug_chr_read ||
                           cartridge_debug_chr_write;
endmodule
