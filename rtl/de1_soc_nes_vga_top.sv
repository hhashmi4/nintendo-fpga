`timescale 1ns/1ps

// Phase 4E-D physical top. The NES stays in the 50 MHz fabric domain and is
// advanced by an NTSC-rate clock enable; the VGA reader uses a PLL-derived
// 25.2 MHz clock and crosses only through nes_framebuffer's handoff protocol.
module de1_soc_nes_vga_top #(
    parameter logic DEVELOPER_MODE_DEFAULT = 1'b0,
    parameter logic [2:0] DEVELOPER_PAGE_DEFAULT = 3'd0,
    parameter string PRG_INIT_FILE =
        "../build/cartridge/phase4db_playable_nrom128.prg.hex",
    parameter string CHR_INIT_FILE =
        "../build/cartridge/phase4db_playable_nrom128.chr.hex"
) (
    input  logic       CLOCK_50,
    input  logic       KEY0,
    input  logic       SW0,
    input  logic       SW1,
    input  logic       SW2,
    input  logic       SW3,
    input  logic       SW4,
    input  logic       SW5,
    input  logic       SW6,
    input  logic       SW7,
    input  logic       SW8,
    input  logic       SW9,
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
    logic nes_core_ppu_enable;
    logic nes_core_cpu_cycle_slot;
    logic dma_complete_event;
    logic dma_start_event;
    logic dma_read_event;
    logic dma_write_event;
    logic ppu_nmi_event;
    logic ppu_nmi_suppressed;
    logic [7:0] cpu_debug_a;
    logic [7:0] cpu_debug_x;
    logic [7:0] cpu_debug_y;
    logic [7:0] cpu_debug_sp;
    logic [15:0] cpu_debug_pc;
    logic [7:0] cpu_debug_status;
    logic [7:0] cpu_debug_instruction;
    logic [15:0] cpu_debug_bus_address;
    logic [7:0] cpu_debug_bus_write_data;
    logic [7:0] cpu_debug_bus_read_data;
    logic cpu_debug_bus_write;
    logic cpu_debug_bus_read;
    logic cpu_debug_bus_valid;
    logic [8:0] ppu_debug_dot;
    logic [8:0] ppu_debug_scanline;
    logic ppu_debug_frame_odd;
    logic ppu_debug_vblank;
    logic ppu_debug_sprite_zero_hit;
    logic ppu_debug_sprite_overflow;
    logic [7:0] ppu_debug_ctrl;
    logic [7:0] ppu_debug_mask;
    logic ppu_debug_nmi_level;
    logic [13:0] ppu_debug_palette_address;
    logic [7:0] dma_debug_page;
    logic [7:0] dma_debug_index;
    logic [7:0] dma_debug_data;
    logic [2:0] dma_debug_phase;
    logic [9:0] dma_debug_elapsed_cycles;
    logic [8:0] dma_debug_read_count;
    logic [8:0] dma_debug_write_count;
    logic [7:0] dma_debug_source_data;
    logic [15:0] dma_debug_source_address;
    logic dma_debug_active;
    logic dma_debug_cpu_stall;
    logic dma_debug_started_odd;
    logic dma_debug_dummy_cycle;
    logic dma_debug_alignment_cycle;
    nes_system_pkg::nes_bus_master_t dma_debug_bus_owner;
    logic [1:0] ppu_debug_pixel_source;

    logic [7:0] controller1_async_buttons;
    logic [7:0] controller1_buttons;
    logic controller_port;
    logic controller_cpu_read;
    logic controller_cpu_write;
    logic [7:0] controller_cpu_write_data;
    logic [7:0] controller_cpu_read_data;
    logic controller_debug_strobe;
    logic [7:0] controller_debug_live1;
    logic [7:0] controller_debug_live2;
    logic [7:0] controller_debug_shift1;
    logic [7:0] controller_debug_shift2;
    logic [3:0] controller_debug_index1;
    logic [3:0] controller_debug_index2;
    logic controller_debug_serial1;
    logic controller_debug_serial2;
    logic controller_debug_read_4016;
    logic controller_debug_read_4017;
    logic controller_debug_latch;

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
    logic [9:0] panel_render_x;
    logic [9:0] panel_render_y;
    logic panel_render_active;
    logic [7:0] source_nes_x;
    logic [7:0] source_nes_y;
    logic active_video;
    logic vga_frame_start;
    logic vga_line_start;
    logic [7:0] normal_vga_red;
    logic [7:0] normal_vga_green;
    logic [7:0] normal_vga_blue;
    logic [7:0] panel_vga_red;
    logic [7:0] panel_vga_green;
    logic [7:0] panel_vga_blue;
    logic debug_snapshot_stale;
    (* preserve, noprune *) logic [23:0] debug_panel_retention;

    logic capture_heartbeat;
    logic vga_heartbeat;
    logic dma_heartbeat;
    logic nmi_heartbeat;

    // All ten slide switches already have Phase 4D-B functions. The parameter
    // gives simulation a clean renderer control while the board image keeps
    // Developer Mode hard-disabled until a non-conflicting control exists.
    (* preserve *) logic developer_mode_enable;
    // Virtual/testbench hooks. They intentionally have no physical board
    // mapping because SW0..SW9 and KEY0 are all retained Phase 4D-B controls.
    (* preserve, noprune *) logic developer_page_next_request;
    (* preserve, noprune *) logic developer_page_select_valid;
    (* preserve, noprune *) logic [2:0] developer_page_request;
    (* preserve, noprune *) logic [2:0] developer_page_active;
    (* preserve, noprune *) logic developer_page_request_pending;
    nes_debug_snapshot_pkg::nes_debug_snapshot_t debug_observations;
    nes_debug_snapshot_pkg::nes_debug_snapshot_t debug_destination_snapshot;
    logic debug_source_capture_accepted;
    logic debug_source_busy;
    logic debug_destination_update;
    logic debug_destination_valid;
    // Source-side virtual controls live in the continuing video domain.
    (* preserve, noprune *) logic debugger_request_valid;
    (* preserve, noprune *) logic [2:0] debugger_request_command;
    logic debugger_request_ready, debugger_request_busy, debugger_ack;
    logic [15:0] debugger_ack_sequence;
    logic [2:0] debugger_ack_state;
    logic [1:0] debugger_ack_result;
    // Retain a small video-domain JTAG status readback word even before a
    // physical JTAG producer is bound. This keeps acknowledgement outputs
    // from being optimized away merely because they have no board pins.
    (* preserve, noprune *) logic [23:0] debugger_command_readback;
    logic debugger_command_valid, debugger_command_done;
    logic [2:0] debugger_command, debugger_response_state;
    logic [15:0] debugger_command_sequence;
    logic [1:0] debugger_response_result;
    logic debugger_authorized, debugger_status_changed;
    logic [5:0] cpu_debug_execution_state;
    logic nes_core_cpu_enable;
    nes_debug_snapshot_pkg::nes_debugger_snapshot_t debugger_status;
    logic debug_capture_pending;
    logic [18:0] debug_pause_heartbeat;

    nes_debug_command_cdc debugger_mailbox (
        .source_clk(pixel_clk), .source_reset(video_reset),
        .source_valid(debugger_request_valid),
        .source_command(debugger_request_command),
        .source_ready(debugger_request_ready), .source_busy(debugger_request_busy),
        .source_ack(debugger_ack), .source_ack_sequence(debugger_ack_sequence),
        .source_ack_state(debugger_ack_state), .source_ack_result(debugger_ack_result),
        .destination_clk(CLOCK_50), .destination_reset(system_reset),
        .destination_valid(debugger_command_valid),
        .destination_command(debugger_command),
        .destination_sequence(debugger_command_sequence),
        .destination_done(debugger_command_done),
        .destination_state(debugger_response_state),
        .destination_result(debugger_response_result)
    );
    nes_debugger debugger (
        .clk(CLOCK_50), .reset(system_reset),
        .command_valid(debugger_command_valid), .command(debugger_command),
        .command_sequence(debugger_command_sequence),
        .command_done(debugger_command_done), .response_state(debugger_response_state),
        .response_result(debugger_response_result),
        .snapshot_ready(!debug_capture_pending && !debug_source_busy &&
                        !debugger_status_changed),
        .cpu_enable(nes_core_cpu_enable), .cpu_execution_state(cpu_debug_execution_state),
        .cpu_pc(cpu_debug_pc), .dma_active(dma_debug_active),
        .ppu_enable(nes_core_ppu_enable), .frame_start(ppu_frame_start),
        .scheduler_authorized(debugger_authorized),
        .status_changed(debugger_status_changed), .status(debugger_status)
    );
    // Retry status/pause captures through a busy mailbox. A paused heartbeat
    // keeps CDC health observable without advancing any NES event counter.
    always_ff @(posedge CLOCK_50) begin
        if (system_reset) begin
            debug_capture_pending <= 1'b0;
            debug_pause_heartbeat <= '0;
        end else begin
            if (debug_source_capture_accepted)
                debug_capture_pending <= 1'b0;
            if (debugger_status.state == nes_debugger_pkg::DBG_PAUSED)
                debug_pause_heartbeat <= debug_pause_heartbeat + 19'd1;
            else
                debug_pause_heartbeat <= '0;
            if (debugger_status_changed || &debug_pause_heartbeat)
                debug_capture_pending <= 1'b1;
        end
    end


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

    // No Phase 4D-B board control is repurposed. This retained self-holding
    // video-domain register makes the complete Developer Mode datapath real
    // synthesized logic while selecting the parameter default after reset.
    // The production image uses the default zero; simulation can set one.
    always_ff @(posedge pixel_clk) begin
        if (video_reset) begin
            debugger_command_readback <= 24'd0;
            developer_mode_enable <= DEVELOPER_MODE_DEFAULT;
            developer_page_next_request <= 1'b0;
            developer_page_select_valid <= 1'b0;
            developer_page_request <= DEVELOPER_PAGE_DEFAULT;
            debugger_request_valid <= 1'b0;
            debugger_request_command <= 3'd0;
        end else begin
            debugger_command_readback <= {debugger_request_ready,
                debugger_request_busy, debugger_ack, debugger_ack_sequence,
                debugger_ack_state, debugger_ack_result};
            developer_mode_enable <= developer_mode_enable;
            developer_page_next_request <= developer_page_next_request;
            developer_page_select_valid <= developer_page_select_valid;
            developer_page_request <= developer_page_request;
            debugger_request_valid <= debugger_request_valid;
            debugger_request_command <= debugger_request_command;
        end
    end

    nes_debug_page_select #(
        .RESET_PAGE(DEVELOPER_PAGE_DEFAULT)
    ) debug_page_select (
        .pixel_clk(pixel_clk),
        .reset(video_reset),
        .frame_start(vga_frame_start),
        .page_next_request(developer_page_next_request),
        .page_select_valid(developer_page_select_valid),
        .requested_page(developer_page_request),
        .active_page(developer_page_active),
        .request_pending(developer_page_request_pending)
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

    // Temporary development mapping. The abstract button vector remains
    // independent of board wiring: bit 0=A through bit 7=Right.
    assign controller1_async_buttons =
        {SW9, SW8, SW7, SW6, SW5, SW4, SW3, SW2};

    controller_input_sync #(.WIDTH(8)) controller1_input_synchronizer (
        .clk(CLOCK_50),
        .reset(system_reset),
        .async_buttons(controller1_async_buttons),
        .synced_buttons(controller1_buttons)
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
        .nes_enable(nes_ppu_ce && debugger_authorized),
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
        .controller_port(controller_port),
        .controller_cpu_read(controller_cpu_read),
        .controller_cpu_write(controller_cpu_write),
        .controller_cpu_write_data(controller_cpu_write_data),
        .controller_cpu_read_data(controller_cpu_read_data),
        .chr_addr(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .ppu_enable(nes_core_ppu_enable),
        .cpu_cycle_slot(nes_core_cpu_cycle_slot),
        .cpu_enable(nes_core_cpu_enable),
        .scheduler_phase(),
        .cpu_address(cpu_debug_bus_address),
        .cpu_write_data(cpu_debug_bus_write_data),
        .cpu_read_data(cpu_debug_bus_read_data),
        .cpu_write_enable(cpu_debug_bus_write),
        .cpu_read_enable(cpu_debug_bus_read),
        .cpu_bus_valid(cpu_debug_bus_valid),
        .cpu_debug_a(cpu_debug_a),
        .cpu_debug_x(cpu_debug_x),
        .cpu_debug_y(cpu_debug_y),
        .cpu_debug_sp(cpu_debug_sp),
        .cpu_debug_pc(cpu_debug_pc),
        .cpu_debug_status(cpu_debug_status),
        .cpu_debug_instruction(cpu_debug_instruction),
        .cpu_debug_execution_state(cpu_debug_execution_state),
        .cpu_bus_target(),
        .cpu_ram_address(),
        .cpu_ppu_register(),
        .cpu_ram_access(),
        .cpu_ppu_access(),
        .cpu_apu_access(),
        .cpu_dma_access(),
        .cpu_controller_access(),
        .cpu_cartridge_access(),
        .dma_active(dma_debug_active),
        .dma_phase(dma_debug_phase),
        .dma_page(dma_debug_page),
        .dma_index(dma_debug_index),
        .dma_data(dma_debug_data),
        .dma_stall_cycles(dma_debug_elapsed_cycles),
        .dma_read_count(dma_debug_read_count),
        .dma_write_count(dma_debug_write_count),
        .dma_read_event(dma_read_event),
        .dma_write_event(dma_write_event),
        .dma_complete_event(dma_complete_event),
        .dma_start_event(dma_start_event),
        .dma_cpu_stall(dma_debug_cpu_stall),
        .dma_source_address(dma_debug_source_address),
        .dma_source_data(dma_debug_source_data),
        .dma_started_odd(dma_debug_started_odd),
        .dma_dummy_cycle(dma_debug_dummy_cycle),
        .dma_alignment_cycle(dma_debug_alignment_cycle),
        .internal_bus_owner(dma_debug_bus_owner),
        .ppu_dot(ppu_debug_dot),
        .ppu_scanline(ppu_debug_scanline),
        .ppu_frame_odd(ppu_debug_frame_odd),
        .ppu_frame_start(ppu_frame_start),
        .ppu_frame_end(),
        .ppu_status_vblank(ppu_debug_vblank),
        .ppu_status_sprite_zero_hit(ppu_debug_sprite_zero_hit),
        .ppu_status_sprite_overflow(ppu_debug_sprite_overflow),
        .ppu_ctrl(ppu_debug_ctrl),
        .ppu_mask(ppu_debug_mask),
        .ppu_nmi_level(ppu_debug_nmi_level),
        .ppu_nmi_event(ppu_nmi_event),
        .ppu_nmi_suppressed(ppu_nmi_suppressed),
        .ppu_oam_addr(),
        .ppu_oam_write_commit(),
        .ppu_oam_collision(),
        .pixel_valid(pixel_valid),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_palette_address(ppu_debug_palette_address),
        .pixel_nes_color(pixel_color),
        .pixel_color_emphasis(pixel_emphasis),
        .pixel_source(ppu_debug_pixel_source)
    );
    /* verilator lint_on PINMISSING */
    /* verilator lint_on PINCONNECTEMPTY */

    nes_controller controllers (
        .clk(CLOCK_50),
        .reset(system_reset),
        .controller1_buttons(controller1_buttons),
        .controller2_buttons(8'h00),
        .cpu_port(controller_port),
        .cpu_read(controller_cpu_read),
        .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data),
        .debug_strobe(controller_debug_strobe),
        .debug_live_controller1(controller_debug_live1),
        .debug_live_controller2(controller_debug_live2),
        .debug_shift_controller1(controller_debug_shift1),
        .debug_shift_controller2(controller_debug_shift2),
        .debug_index_controller1(controller_debug_index1),
        .debug_index_controller2(controller_debug_index2),
        .debug_serial_controller1(controller_debug_serial1),
        .debug_serial_controller2(controller_debug_serial2),
        .debug_read_4016(controller_debug_read_4016),
        .debug_read_4017(controller_debug_read_4017),
        .debug_latch_event(controller_debug_latch)
    );

    nes_cartridge #(
        .MAPPER_NUMBER (0),
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd1),
        .PRG_INIT_FILE (PRG_INIT_FILE),
        .CHR_INIT_FILE (CHR_INIT_FILE)
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
        .developer_layout(developer_mode_enable),
        .framebuffer_valid(framebuffer_valid),
        .framebuffer_pixel(framebuffer_pixel),
        .framebuffer_address(framebuffer_address),
        .frame_start(vga_frame_start),
        .frame_end(vga_frame_end),
        .line_start(vga_line_start),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .render_x(panel_render_x),
        .render_y(panel_render_y),
        .render_active(panel_render_active),
        .source_nes_x(source_nes_x),
        .source_nes_y(source_nes_y),
        .active_video(active_video),
        .hsync_n(VGA_HS),
        .vsync_n(VGA_VS),
        .blank_n(VGA_BLANK_N),
        .red(normal_vga_red),
        .green(normal_vga_green),
        .blue(normal_vga_blue)
    );

    always_comb begin
        debug_observations = '0;
        debug_observations.debugger = debugger_status;

        debug_observations.cpu.pc = cpu_debug_pc;
        debug_observations.cpu.a = cpu_debug_a;
        debug_observations.cpu.x = cpu_debug_x;
        debug_observations.cpu.y = cpu_debug_y;
        debug_observations.cpu.sp = cpu_debug_sp;
        debug_observations.cpu.status = cpu_debug_status;
        debug_observations.cpu.opcode = cpu_debug_instruction;
        debug_observations.cpu.address = cpu_debug_bus_address;
        debug_observations.cpu.read_data = cpu_debug_bus_read_data;
        debug_observations.cpu.write_data = cpu_debug_bus_write_data;
        debug_observations.cpu.read = cpu_debug_bus_read;
        debug_observations.cpu.write = cpu_debug_bus_write;
        debug_observations.cpu.bus_valid = cpu_debug_bus_valid;
        debug_observations.cpu.stalled = dma_debug_cpu_stall;
        debug_observations.cpu.bus_owner = dma_debug_bus_owner;

        debug_observations.ppu.scanline = ppu_debug_scanline;
        debug_observations.ppu.dot = ppu_debug_dot;
        debug_observations.ppu.frame_odd = ppu_debug_frame_odd;
        debug_observations.ppu.ctrl = ppu_debug_ctrl;
        debug_observations.ppu.mask = ppu_debug_mask;
        debug_observations.ppu.status = {
            ppu_debug_vblank,
            ppu_debug_sprite_zero_hit,
            ppu_debug_sprite_overflow,
            5'b00000
        };
        debug_observations.ppu.pixel_x = pixel_x;
        debug_observations.ppu.pixel_y = pixel_y;
        debug_observations.ppu.palette_address =
            ppu_debug_palette_address;
        debug_observations.ppu.pixel_color = pixel_color;
        debug_observations.ppu.pixel_emphasis = pixel_emphasis;
        debug_observations.ppu.pixel_source = ppu_debug_pixel_source;
        debug_observations.ppu.pixel_valid = pixel_valid;
        debug_observations.ppu.nmi_enabled = ppu_debug_ctrl[7];
        debug_observations.ppu.nmi_level = ppu_debug_nmi_level;
        debug_observations.ppu.vblank = ppu_debug_vblank;
        debug_observations.ppu.sprite_zero_hit =
            ppu_debug_sprite_zero_hit;
        debug_observations.ppu.sprite_overflow =
            ppu_debug_sprite_overflow;

        debug_observations.cartridge.present = cartridge_present;
        debug_observations.cartridge.mapper_number =
            cartridge_mapper_number;
        debug_observations.cartridge.nrom_256 = cartridge_nrom_256;
        debug_observations.cartridge.prg_address =
            cartridge_debug_prg_address;
        debug_observations.cartridge.prg_data = cartridge_debug_prg_data;
        debug_observations.cartridge.prg_read = cartridge_debug_prg_read;
        debug_observations.cartridge.prg_write = cartridge_debug_prg_write;
        debug_observations.cartridge.chr_address =
            cartridge_debug_chr_address;
        debug_observations.cartridge.chr_data = cartridge_debug_chr_data;
        debug_observations.cartridge.chr_read = cartridge_debug_chr_read;
        debug_observations.cartridge.chr_write = cartridge_debug_chr_write;
        debug_observations.cartridge.chr_is_ram = cartridge_chr_is_ram;
        debug_observations.cartridge.mirroring =
            cartridge_mirroring_mode;

        debug_observations.controller.live1 = controller_debug_live1;
        debug_observations.controller.live2 = controller_debug_live2;
        debug_observations.controller.shift1 = controller_debug_shift1;
        debug_observations.controller.shift2 = controller_debug_shift2;
        debug_observations.controller.index1 = controller_debug_index1;
        debug_observations.controller.index2 = controller_debug_index2;
        debug_observations.controller.strobe = controller_debug_strobe;
        debug_observations.controller.serial1 = controller_debug_serial1;
        debug_observations.controller.serial2 = controller_debug_serial2;

        debug_observations.dma.active = dma_debug_active;
        debug_observations.dma.source_page = dma_debug_page;
        debug_observations.dma.source_address = dma_debug_source_address;
        debug_observations.dma.source_data = dma_debug_source_data;
        debug_observations.dma.byte_index = dma_debug_index;
        debug_observations.dma.oam_data = dma_debug_data;
        debug_observations.dma.phase = dma_debug_phase;
        debug_observations.dma.started_odd = dma_debug_started_odd;
        debug_observations.dma.elapsed_slots = dma_debug_elapsed_cycles;
        debug_observations.dma.read_count = dma_debug_read_count;
        debug_observations.dma.write_count = dma_debug_write_count;
        debug_observations.dma.cpu_stall = dma_debug_cpu_stall;
        debug_observations.dma.bus_owner = dma_debug_bus_owner;
        debug_observations.dma.start_event = dma_start_event;
        debug_observations.dma.read_event = dma_read_event;
        debug_observations.dma.write_event = dma_write_event;
        debug_observations.dma.dummy_cycle = dma_debug_dummy_cycle;
        debug_observations.dma.alignment_cycle =
            dma_debug_alignment_cycle;
    end

    nes_debug_snapshot debug_snapshot (
        .source_clk(CLOCK_50),
        .source_reset(system_reset),
        .source_frame_capture(ppu_frame_start),
        .manual_capture(debug_capture_pending && !debug_source_busy),
        .observations(debug_observations),
        .nmi_event(ppu_nmi_event),
        .nmi_suppressed_event(ppu_nmi_suppressed),
        .dma_complete_event(dma_complete_event),
        .controller_poll_event(controller_debug_latch),
        .controller_read_4016_event(controller_debug_read_4016),
        .controller_read_4017_event(controller_debug_read_4017),
        .cpu_slot_event(nes_core_cpu_cycle_slot),
        .ppu_cycle_event(nes_core_ppu_enable),
        .prg_read_event(cartridge_debug_prg_read),
        .chr_read_event(cartridge_debug_chr_read),
        .source_capture_accepted(debug_source_capture_accepted),
        .source_busy(debug_source_busy),
        .destination_clk(pixel_clk),
        .destination_reset(video_reset),
        .destination_frame_start(vga_frame_start),
        .destination_update(debug_destination_update),
        .destination_valid(debug_destination_valid),
        .destination_snapshot(debug_destination_snapshot)
    );

    // The compact renderer observes only the Phase 4E-A video-domain stable
    // bank. It has no NES-pixel input and no path back into execution.
    nes_debug_panel_renderer debug_panel_renderer (
        .pixel_clk(pixel_clk),
        .reset(video_reset),
        .snapshot_valid(debug_destination_valid),
        .snapshot_update(debug_destination_update),
        .snapshot(debug_destination_snapshot),
        .page_select(developer_page_active),
        .frame_start(vga_frame_start),
        .scan_x(panel_render_x),
        .scan_y(panel_render_y),
        .active_video(panel_render_active),
        .snapshot_stale(debug_snapshot_stale),
        .red(panel_vga_red),
        .green(panel_vga_green),
        .blue(panel_vga_blue)
    );

    nes_developer_compositor developer_compositor (
        .developer_mode_enable(developer_mode_enable),
        .scan_x(scan_x),
        .active_video(active_video),
        .game_red(normal_vga_red),
        .game_green(normal_vga_green),
        .game_blue(normal_vga_blue),
        .panel_red(panel_vga_red),
        .panel_green(panel_vga_green),
        .panel_blue(panel_vga_blue),
        .red(VGA_R),
        .green(VGA_G),
        .blue(VGA_B)
    );

    // Retain the panel output explicitly in the hard-disabled production
    // image so Phase 4E-D synthesis measures the implemented renderer.
    always_ff @(posedge pixel_clk) begin
        if (video_reset)
            debug_panel_retention <= '0;
        else
            debug_panel_retention <= {
                panel_vga_red, panel_vga_green, panel_vga_blue
            };
    end

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

    // HEX1:HEX0 shows the synchronized Controller 1 state for board bring-up.
    hex7seg hex0_driver (.value(controller_debug_live1[3:0]), .segments_n(HEX0));
    hex7seg hex1_driver (.value(controller_debug_live1[7:4]), .segments_n(HEX1));
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
                           cartridge_debug_chr_write ||
                           ^captured_frames || controller_debug_strobe ||
                           ^controller_debug_live2 ||
                           ^controller_debug_shift1 ||
                           ^controller_debug_shift2 ||
                           ^controller_debug_index1 ||
                           ^controller_debug_index2 ||
                           controller_debug_serial1 ||
                           controller_debug_serial2 ||
                           controller_debug_read_4016 ||
                           controller_debug_read_4017 ||
                           controller_debug_latch || ^cpu_debug_a ||
                           ^cpu_debug_x || ^cpu_debug_y || ^cpu_debug_sp ||
                           ^cpu_debug_status || ^cpu_debug_bus_address ||
                           ^cpu_debug_bus_write_data ||
                           ^cpu_debug_bus_read_data || cpu_debug_bus_write ||
                           cpu_debug_bus_read || cpu_debug_bus_valid ||
                           ^ppu_debug_dot || ^ppu_debug_scanline ||
                           ppu_debug_frame_odd || ppu_debug_vblank ||
                           ppu_debug_sprite_zero_hit ||
                           ppu_debug_sprite_overflow || ^ppu_debug_ctrl ||
                           ^ppu_debug_mask || ppu_debug_nmi_level ||
                           ^ppu_debug_pixel_source || dma_debug_active ||
                           ^dma_debug_page || ^dma_debug_index ||
                           ^dma_debug_elapsed_cycles ||
                           ^dma_debug_source_address ||
                           ^dma_debug_source_data || ^dma_debug_bus_owner ||
                           developer_mode_enable ||
                           debug_snapshot_stale || ^debug_panel_retention ||
                           debug_source_capture_accepted || debug_source_busy ||
                           debug_destination_update || debug_destination_valid ||
                           ^debug_destination_snapshot;
endmodule
