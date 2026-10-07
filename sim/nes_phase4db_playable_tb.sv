`timescale 1ns/1ps

module nes_phase4db_playable_tb;
    import nes_system_pkg::*;
    import nes_debug_snapshot_pkg::*;

    logic clk = 1'b0;
    logic debug_clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] async_buttons = 8'h00;
    logic [7:0] synced_buttons;
    logic [1:0] cartridge_mirroring;
    logic cartridge_present;
    logic [7:0] cartridge_mapper_number;
    logic cartridge_nrom_256;
    logic cartridge_chr_is_ram;
    logic [14:0] cartridge_debug_prg_address;
    logic [7:0] cartridge_debug_prg_data;
    logic [12:0] cartridge_debug_chr_address;
    logic [7:0] cartridge_debug_chr_data;
    logic cartridge_debug_prg_read;
    logic cartridge_debug_prg_write;
    logic cartridge_debug_chr_read;
    logic cartridge_debug_chr_write;

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
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic [7:0] cpu_write_data;
    logic [7:0] cpu_read_data;
    logic cpu_write_enable;
    logic cpu_read_enable;
    logic cpu_bus_valid;
    logic [7:0] cpu_debug_a;
    logic [7:0] cpu_debug_x;
    logic [7:0] cpu_debug_y;
    logic [7:0] cpu_debug_sp;
    logic [15:0] cpu_debug_pc;
    logic [7:0] cpu_debug_status;
    logic [7:0] cpu_debug_instruction;
    logic [5:0] cpu_debug_execution_state;
    logic debugger_authorized;
    nes_debugger_snapshot_t debugger_status;

    logic dma_active;
    logic [2:0] dma_phase;
    logic [7:0] dma_page;
    logic [7:0] dma_index;
    logic [9:0] dma_stall_cycles;
    logic [8:0] dma_read_count;
    logic [8:0] dma_write_count;
    logic [7:0] dma_data;
    logic dma_read_event;
    logic dma_write_event;
    logic dma_complete_event;
    logic dma_start_event;
    logic dma_cpu_stall;
    logic [15:0] dma_source_address;
    logic [7:0] dma_source_data;
    logic dma_started_odd;
    logic dma_dummy_cycle;
    logic dma_alignment_cycle;
    nes_cpu_target_t dma_source_target;
    nes_bus_master_t internal_bus_owner;

    logic [8:0] ppu_dot;
    logic [8:0] ppu_scanline;
    logic ppu_frame_odd;
    logic ppu_frame_start;
    logic ppu_status_vblank;
    logic ppu_status_sprite_zero_hit;
    logic ppu_status_sprite_overflow;
    logic [7:0] ppu_ctrl;
    logic [7:0] ppu_mask;
    logic ppu_nmi_event;
    logic ppu_nmi_level;
    logic ppu_nmi_suppressed;
    logic pixel_valid;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic [5:0] pixel_color;
    logic [2:0] pixel_emphasis;
    logic [13:0] pixel_palette_address;
    logic [1:0] pixel_source;

    logic controller_strobe;
    logic [7:0] controller_live1;
    logic [7:0] controller_live2;
    logic [7:0] controller_latched;
    logic [7:0] controller_latched2;
    logic [3:0] controller_index;
    logic [3:0] controller_index2;
    logic controller_serial1;
    logic controller_serial2;
    logic controller_read_4016;
    logic controller_read_4017;
    logic controller_latch_event;

    nes_debug_snapshot_t debug_observations;
    nes_debug_snapshot_t debug_destination_snapshot;
    logic debug_frame_start = 1'b0;
    logic debug_capture_accepted;
    logic debug_source_busy;
    logic debug_destination_update;
    logic debug_destination_valid;
    integer debug_capture_count = 0;
    integer debug_update_count = 0;
    logic [15:0] previous_snapshot_pc = 16'h0000;
    logic [7:0] previous_snapshot_a = 8'h00;
    logic saw_snapshot_cpu_change = 1'b0;
    logic saw_snapshot_controller_input = 1'b0;
    logic saw_snapshot_cartridge_read = 1'b0;
    logic saw_snapshot_dma_completion = 1'b0;

    integer fabric_cycles = 0;
    integer ppu_cycles = 0;
    integer cpu_slots = 0;
    integer cpu_run_cycles = 0;
    integer frame_count = 0;
    integer nmi_events = 0;
    integer nmi_handlers = 0;
    integer dma_starts = 0;
    integer dma_completions = 0;
    integer dma_reads = 0;
    integer dma_writes = 0;
    integer controller_polls = 0;
    integer controller_reads = 0;
    integer ppu_register_writes = 0;
    integer prg_reads = 0;
    integer resumed_after_dma = 0;
    integer reset_vector_low_reads = 0;
    integer reset_vector_high_reads = 0;
    integer early_prg_trace_reads = 0;
    integer trace_file;
    logic previous_in_nmi = 1'b0;
    logic await_dma_resume = 1'b0;
    logic saw_first_dma_byte = 1'b0;
    logic saw_last_dma_byte = 1'b0;
    logic saw_rendering = 1'b0;
    logic saw_vblank = 1'b0;
    logic logged_initial_pc = 1'b0;
    logic logged_ram_initialization = 1'b0;
    logic logged_ppu_initialization = 1'b0;
    logic logged_controller_poll = 1'b0;
    logic logged_nametable_write = 1'b0;
    logic logged_palette_write = 1'b0;

    always #5 clk <= !clk;
    always #7 debug_clk <= !debug_clk;

    controller_input_sync #(.WIDTH(8)) input_synchronizer (
        .clk(clk),
        .reset(reset),
        .async_buttons(async_buttons),
        .synced_buttons(synced_buttons)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(clk),
        .reset(reset),
        .controller1_buttons(synced_buttons),
        .controller2_buttons(8'h00),
        .cpu_port(controller_port),
        .cpu_read(controller_cpu_read),
        .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data),
        .debug_strobe(controller_strobe),
        .debug_live_controller1(controller_live1),
        .debug_live_controller2(controller_live2),
        .debug_shift_controller1(controller_latched),
        .debug_shift_controller2(controller_latched2),
        .debug_index_controller1(controller_index),
        .debug_index_controller2(controller_index2),
        .debug_serial_controller1(controller_serial1),
        .debug_serial_controller2(controller_serial2),
        .debug_read_4016(controller_read_4016),
        .debug_read_4017(controller_read_4017),
        .debug_latch_event(controller_latch_event)
    );

    nes_cartridge #(
        .MAPPER_NUMBER (0),
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd1),
        .PRG_INIT_FILE ("build/cartridge/phase4db_playable_nrom128.prg.hex"),
        .CHR_INIT_FILE ("build/cartridge/phase4db_playable_nrom128.chr.hex")
    ) cartridge (
        .clk(clk), .reset(reset),
        .cpu_address(cart_cpu_address), .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write), .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .cartridge_present(cartridge_present),
        .mapper_number(cartridge_mapper_number),
        .nrom_256(cartridge_nrom_256),
        .chr_is_ram(cartridge_chr_is_ram),
        .mirroring_mode(cartridge_mirroring),
        .debug_prg_address(cartridge_debug_prg_address),
        .debug_prg_data(cartridge_debug_prg_data),
        .debug_chr_address(cartridge_debug_chr_address),
        .debug_chr_data(cartridge_debug_chr_data),
        .debug_prg_read(cartridge_debug_prg_read),
        .debug_prg_write(cartridge_debug_prg_write),
        .debug_prg_ram_read(), .debug_prg_ram_write(),
        .debug_chr_read(cartridge_debug_chr_read),
        .debug_chr_write(cartridge_debug_chr_write)
    );

    // Normal-mode hashes and all 300 frames exercise the real debugger RUN
    // authorization path, with no command tokens submitted.
    nes_debugger running_debugger (
        .clk(clk), .reset(reset), .command_valid(1'b0), .command(3'd0),
        .command_sequence(16'd0), .command_done(), .response_state(),
        .response_result(), .snapshot_ready(1'b1), .cpu_enable(cpu_enable),
        .cpu_execution_state(cpu_debug_execution_state), .cpu_pc(cpu_debug_pc),
        .dma_active(dma_active), .ppu_enable(ppu_enable), .frame_start(ppu_frame_start),
        .scheduler_authorized(debugger_authorized), .status_changed(),
        .status(debugger_status)
    );

    nes_core nes (
        .clk(clk),
        .reset(reset),
        .nes_enable(debugger_authorized),
        .irq(1'b0),
        .mirroring_mode(cartridge_mirroring),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
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
        .ppu_enable(ppu_enable),
        .cpu_cycle_slot(cpu_cycle_slot),
        .cpu_enable(cpu_enable),
        .scheduler_phase(),
        .cpu_address(cpu_address),
        .cpu_write_data(cpu_write_data),
        .cpu_read_data(cpu_read_data),
        .cpu_write_enable(cpu_write_enable),
        .cpu_read_enable(cpu_read_enable),
        .cpu_bus_valid(cpu_bus_valid),
        .cpu_debug_a(cpu_debug_a),
        .cpu_debug_x(cpu_debug_x),
        .cpu_debug_y(cpu_debug_y),
        .cpu_debug_sp(cpu_debug_sp),
        .cpu_debug_pc(cpu_debug_pc),
        .cpu_debug_status(cpu_debug_status),
        .cpu_debug_instruction(cpu_debug_instruction),
        .cpu_debug_execution_state(cpu_debug_execution_state),
        .cpu_bus_target(), .cpu_ram_address(), .cpu_ppu_register(),
        .cpu_ram_access(), .cpu_ppu_access(), .cpu_apu_access(),
        .cpu_dma_access(), .cpu_controller_access(),
        .cpu_cartridge_access(),
        .dma_active(dma_active), .dma_phase(dma_phase), .dma_page(dma_page),
        .dma_index(dma_index), .dma_data(dma_data),
        .dma_stall_cycles(dma_stall_cycles),
        .dma_read_count(dma_read_count),
        .dma_write_count(dma_write_count),
        .dma_read_event(dma_read_event),
        .dma_write_event(dma_write_event),
        .dma_complete_event(dma_complete_event),
        .dma_start_event(dma_start_event),
        .dma_cpu_stall(dma_cpu_stall),
        .dma_source_address(dma_source_address),
        .dma_source_data(dma_source_data),
        .dma_started_odd(dma_started_odd),
        .dma_dummy_cycle(dma_dummy_cycle),
        .dma_alignment_cycle(dma_alignment_cycle),
        .dma_source_target(dma_source_target),
        .internal_bus_owner(internal_bus_owner),
        .dmc_dma_active(), .dmc_dma_cpu_stall(), .dmc_dma_phase(),
        .dmc_dma_started_odd(), .dmc_dma_elapsed_cycles(),
        .dmc_dma_read_event(), .dmc_dma_start_event(),
        .dmc_dma_complete_event(), .dmc_source_target(),
        .ppu_dot(ppu_dot), .ppu_scanline(ppu_scanline),
        .ppu_frame_odd(ppu_frame_odd),
        .ppu_frame_start(ppu_frame_start), .ppu_frame_end(),
        .ppu_status_vblank(ppu_status_vblank),
        .ppu_status_sprite_zero_hit(ppu_status_sprite_zero_hit),
        .ppu_status_sprite_overflow(ppu_status_sprite_overflow),
        .ppu_ctrl(ppu_ctrl), .ppu_mask(ppu_mask),
        .ppu_nmi_level(ppu_nmi_level),
        .ppu_nmi_event(ppu_nmi_event),
        .ppu_nmi_suppressed(ppu_nmi_suppressed),
        .ppu_oam_addr(), .ppu_oam_write_commit(), .ppu_oam_collision(),
        .pixel_valid(pixel_valid), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_palette_address(pixel_palette_address),
        .pixel_nes_color(pixel_color),
        .pixel_color_emphasis(pixel_emphasis),
        .pixel_source(pixel_source)
    );
    /* verilator lint_on PINCONNECTEMPTY */

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
        debug_observations.cpu.address = cpu_address;
        debug_observations.cpu.read_data = cpu_read_data;
        debug_observations.cpu.write_data = cpu_write_data;
        debug_observations.cpu.read = cpu_read_enable;
        debug_observations.cpu.write = cpu_write_enable;
        debug_observations.cpu.bus_valid = cpu_bus_valid;
        debug_observations.cpu.stalled = dma_cpu_stall;
        debug_observations.cpu.bus_owner = internal_bus_owner;

        debug_observations.ppu.scanline = ppu_scanline;
        debug_observations.ppu.dot = ppu_dot;
        debug_observations.ppu.frame_odd = ppu_frame_odd;
        debug_observations.ppu.ctrl = ppu_ctrl;
        debug_observations.ppu.mask = ppu_mask;
        debug_observations.ppu.status = {
            ppu_status_vblank,
            ppu_status_sprite_zero_hit,
            ppu_status_sprite_overflow,
            5'b00000
        };
        debug_observations.ppu.pixel_x = pixel_x;
        debug_observations.ppu.pixel_y = pixel_y;
        debug_observations.ppu.palette_address = pixel_palette_address;
        debug_observations.ppu.pixel_color = pixel_color;
        debug_observations.ppu.pixel_emphasis = pixel_emphasis;
        debug_observations.ppu.pixel_source = pixel_source;
        debug_observations.ppu.pixel_valid = pixel_valid;
        debug_observations.ppu.nmi_enabled = ppu_ctrl[7];
        debug_observations.ppu.nmi_level = ppu_nmi_level;
        debug_observations.ppu.vblank = ppu_status_vblank;
        debug_observations.ppu.sprite_zero_hit =
            ppu_status_sprite_zero_hit;
        debug_observations.ppu.sprite_overflow =
            ppu_status_sprite_overflow;

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
        debug_observations.cartridge.mirroring = cartridge_mirroring;

        debug_observations.controller.live1 = controller_live1;
        debug_observations.controller.live2 = controller_live2;
        debug_observations.controller.shift1 = controller_latched;
        debug_observations.controller.shift2 = controller_latched2;
        debug_observations.controller.index1 = controller_index;
        debug_observations.controller.index2 = controller_index2;
        debug_observations.controller.strobe = controller_strobe;
        debug_observations.controller.serial1 = controller_serial1;
        debug_observations.controller.serial2 = controller_serial2;

        debug_observations.dma.active = dma_active;
        debug_observations.dma.source_page = dma_page;
        debug_observations.dma.source_address = dma_source_address;
        debug_observations.dma.source_data = dma_source_data;
        debug_observations.dma.byte_index = dma_index;
        debug_observations.dma.oam_data = dma_data;
        debug_observations.dma.phase = dma_phase;
        debug_observations.dma.started_odd = dma_started_odd;
        debug_observations.dma.elapsed_slots = dma_stall_cycles;
        debug_observations.dma.read_count = dma_read_count;
        debug_observations.dma.write_count = dma_write_count;
        debug_observations.dma.cpu_stall = dma_cpu_stall;
        debug_observations.dma.bus_owner = internal_bus_owner;
        debug_observations.dma.start_event = dma_start_event;
        debug_observations.dma.read_event = dma_read_event;
        debug_observations.dma.write_event = dma_write_event;
        debug_observations.dma.dummy_cycle = dma_dummy_cycle;
        debug_observations.dma.alignment_cycle = dma_alignment_cycle;
    end

    nes_debug_snapshot debug_snapshot (
        .source_clk(clk),
        .source_reset(reset),
        .source_frame_capture(ppu_frame_start),
        .manual_capture(1'b0),
        .observations(debug_observations),
        .nmi_event(ppu_nmi_event),
        .nmi_suppressed_event(ppu_nmi_suppressed),
        .dma_complete_event(dma_complete_event),
        .controller_poll_event(controller_latch_event),
        .controller_read_4016_event(controller_read_4016),
        .controller_read_4017_event(controller_read_4017),
        .cpu_slot_event(cpu_cycle_slot),
        .ppu_cycle_event(ppu_enable),
        .prg_read_event(cartridge_debug_prg_read),
        .chr_read_event(cartridge_debug_chr_read),
        .source_capture_accepted(debug_capture_accepted),
        .source_busy(debug_source_busy),
        .destination_clk(debug_clk),
        .destination_reset(reset),
        .destination_frame_start(debug_frame_start),
        .destination_update(debug_destination_update),
        .destination_valid(debug_destination_valid),
        .destination_snapshot(debug_destination_snapshot)
    );

    // Model a future video frame boundary after each asynchronous bundled-data
    // transfer has had ample time to settle and acknowledge.
    initial begin
        forever begin
            @(posedge ppu_frame_start);
            repeat (12) @(posedge debug_clk);
            debug_frame_start = 1'b1;
            @(posedge debug_clk);
            debug_frame_start = 1'b0;
        end
    end

    always @(negedge clk) begin
        if (!reset && debug_capture_accepted)
            debug_capture_count <= debug_capture_count + 1;
    end

    always @(negedge debug_clk) begin
        if (!reset && debug_destination_update) begin
            debug_update_count <= debug_update_count + 1;
            assert (debug_destination_valid);
            assert (debug_destination_snapshot.debugger == '0);
            assert (debug_destination_snapshot.system.snapshot_id ==
                    32'(debug_update_count + 1));
            assert (debug_destination_snapshot.system.source_frame_number ==
                    debug_destination_snapshot.system.snapshot_id);
            assert (debug_destination_snapshot.system.missed_capture_count ==
                    32'd0);
            assert (debug_destination_snapshot.ppu.scanline == 9'd0 &&
                    debug_destination_snapshot.ppu.dot == 9'd0);
            assert (debug_destination_snapshot.ppu.status[7] ==
                    debug_destination_snapshot.ppu.vblank);
            assert (debug_destination_snapshot.ppu.status[6] ==
                    debug_destination_snapshot.ppu.sprite_zero_hit);
            assert (debug_destination_snapshot.ppu.status[5] ==
                    debug_destination_snapshot.ppu.sprite_overflow);
            assert (debug_destination_snapshot.cartridge.present &&
                    debug_destination_snapshot.cartridge.mapper_number == 8'd0 &&
                    !debug_destination_snapshot.cartridge.nrom_256 &&
                    !debug_destination_snapshot.cartridge.chr_is_ram &&
                    debug_destination_snapshot.cartridge.mirroring == 2'd1);
            assert (debug_destination_snapshot.cpu.stalled ==
                    debug_destination_snapshot.dma.cpu_stall);
            assert (debug_destination_snapshot.cpu.bus_owner ==
                    debug_destination_snapshot.dma.bus_owner);

            if (debug_update_count != 0 &&
                (debug_destination_snapshot.cpu.pc != previous_snapshot_pc ||
                 debug_destination_snapshot.cpu.a != previous_snapshot_a))
                saw_snapshot_cpu_change <= 1'b1;
            if (debug_destination_snapshot.controller.live1 == 8'h50)
                saw_snapshot_controller_input <= 1'b1;
            if (debug_destination_snapshot.cartridge.prg_read)
                saw_snapshot_cartridge_read <= 1'b1;
            if (debug_destination_snapshot.dma.complete_event)
                saw_snapshot_dma_completion <= 1'b1;
            previous_snapshot_pc <= debug_destination_snapshot.cpu.pc;
            previous_snapshot_a <= debug_destination_snapshot.cpu.a;
        end
    end

    always @(posedge clk) begin
        logic in_nmi;
        if (!reset) begin
            assert (debugger_authorized && debugger_status == '0);
            fabric_cycles <= fabric_cycles + 1;
            if (ppu_enable)
                ppu_cycles <= ppu_cycles + 1;
            if (cpu_cycle_slot)
                cpu_slots <= cpu_slots + 1;
            if (cpu_enable)
                cpu_run_cycles <= cpu_run_cycles + 1;
            if (ppu_frame_start)
                frame_count <= frame_count + 1;
            if (ppu_nmi_event) begin
                nmi_events <= nmi_events + 1;
                $fwrite(trace_file, "NMI event frame=%0d scanline=%0d dot=%0d pc=%04x\n",
                        frame_count, ppu_scanline, ppu_dot, cpu_debug_pc);
            end
            if (ppu_status_vblank)
                saw_vblank <= 1'b1;
            if (ppu_mask == 8'h1e)
                saw_rendering <= 1'b1;

            in_nmi = cpu_debug_pc >= 16'h9000 && cpu_debug_pc < 16'h9020;
            if (in_nmi && !previous_in_nmi) begin
                nmi_handlers <= nmi_handlers + 1;
                $fwrite(trace_file, "NMI handler entry=%0d sp=%02x\n",
                        nmi_handlers + 1, cpu_debug_sp);
            end
            previous_in_nmi <= in_nmi;

            if (cart_cpu_read) begin
                prg_reads <= prg_reads + 1;
                if (early_prg_trace_reads < 16) begin
                    $fwrite(trace_file, "early PRG read address=%04x data=%02x pc=%04x\n",
                            cart_cpu_address, cart_cpu_read_data,
                            cpu_debug_pc);
                    early_prg_trace_reads <= early_prg_trace_reads + 1;
                end
                if (cart_cpu_address == 16'hfffc) begin
                    reset_vector_low_reads <= reset_vector_low_reads + 1;
                    $fwrite(trace_file, "reset-vector read FFFC data=%02x\n",
                            cart_cpu_read_data);
                end
                if (cart_cpu_address == 16'hfffd) begin
                    reset_vector_high_reads <= reset_vector_high_reads + 1;
                    $fwrite(trace_file, "reset-vector read FFFD data=%02x\n",
                            cart_cpu_read_data);
                end
            end
            if (!logged_initial_pc && cpu_debug_pc == 16'h8000) begin
                logged_initial_pc <= 1'b1;
                $fwrite(trace_file, "initial CPU PC=8000\n");
            end
            if (!logged_ram_initialization &&
                nes.internal_cpu_ram.memory[11'h00f] == 8'ha5) begin
                logged_ram_initialization <= 1'b1;
                $fwrite(trace_file,
                        "CPU RAM initialized marker=000f:a5 player=%02x,%02x\n",
                        nes.internal_cpu_ram.memory[11'h003],
                        nes.internal_cpu_ram.memory[11'h004]);
            end
            if (!logged_ppu_initialization && ppu_ctrl == 8'h80 &&
                ppu_mask == 8'h1e) begin
                logged_ppu_initialization <= 1'b1;
                $fwrite(trace_file, "PPU initialized ctrl=80 mask=1e\n");
            end
            if (!logged_nametable_write &&
                nes.ppu.background_core.memory.ciram_write_enable) begin
                logged_nametable_write <= 1'b1;
                $fwrite(trace_file, "nametable write observed\n");
            end
            if (!logged_palette_write &&
                nes.ppu.background_core.memory.palette_write_enable) begin
                logged_palette_write <= 1'b1;
                $fwrite(trace_file, "palette write observed\n");
            end
            if (cpu_enable && cpu_bus_valid && cpu_write_enable &&
                cpu_address >= 16'h2000 && cpu_address <= 16'h3fff)
                ppu_register_writes <= ppu_register_writes + 1;
            if (controller_read_4016)
                controller_reads <= controller_reads + 1;
            if (controller_latch_event)
                controller_polls <= controller_polls + 1;
            if (!logged_controller_poll && controller_latch_event) begin
                logged_controller_poll <= 1'b1;
                $fwrite(trace_file, "controller poll observed pc=%04x\n",
                        cpu_debug_pc);
            end

            assert (internal_bus_owner ==
                    (dma_active ? NES_BUS_MASTER_DMA : NES_BUS_MASTER_CPU));
            assert (!(cpu_enable && dma_cpu_stall));
            if (dma_active)
                assert (dma_page == 8'h02 &&
                        dma_source_target == NES_CPU_TARGET_RAM);
            if (dma_start_event) begin
                dma_starts <= dma_starts + 1;
                assert (cpu_write_data == 8'h02);
                $fwrite(trace_file, "DMA start=%0d frame=%0d pc=%04x\n",
                        dma_starts + 1, frame_count, cpu_debug_pc);
            end
            if (dma_read_event) begin
                dma_reads <= dma_reads + 1;
                assert (dma_source_address == {8'h02, dma_index});
                if (dma_index == 8'h00) begin
                    saw_first_dma_byte <= 1'b1;
                    assert (dma_source_data ==
                            nes.internal_cpu_ram.memory[11'h200]);
                end
                if (dma_index == 8'hff) begin
                    saw_last_dma_byte <= 1'b1;
                    assert (dma_source_data ==
                            nes.internal_cpu_ram.memory[11'h2ff]);
                end
            end
            if (dma_write_event)
                dma_writes <= dma_writes + 1;
            if (dma_complete_event) begin
                dma_completions <= dma_completions + 1;
                await_dma_resume <= 1'b1;
                assert (dma_read_count == 9'd256);
                assert (dma_write_count == 9'd256);
                assert (dma_stall_cycles == 10'd513 ||
                        dma_stall_cycles == 10'd514);
                assert (nes.ppu.oam.primary_oam[8'h00] ==
                        nes.internal_cpu_ram.memory[11'h200]);
                assert (nes.ppu.oam.primary_oam[8'h03] ==
                        nes.internal_cpu_ram.memory[11'h203]);
            end else if (await_dma_resume && cpu_enable) begin
                resumed_after_dma <= resumed_after_dma + 1;
                await_dma_resume <= 1'b0;
            end

            if (nes.internal_cpu_ram.memory[11'h00f] == 8'ha5) begin
                assert (cpu_debug_pc >= 16'h8000)
                    else $fatal(1, "PC escaped PRG ROM: %04x", cpu_debug_pc);
                assert (cpu_debug_sp >= 8'he0)
                    else $fatal(1, "stack pointer corrupted: %02x", cpu_debug_sp);
            end
        end
    end

    task automatic drive_one_poll(input logic [7:0] buttons);
        logic [7:0] starting_poll;
        logic [7:0] pressed_poll;
        begin
            starting_poll = nes.internal_cpu_ram.memory[11'h012];
            async_buttons = buttons;
            repeat (4) @(posedge clk);
            while (nes.internal_cpu_ram.memory[11'h012] == starting_poll)
                @(posedge clk);
            pressed_poll = nes.internal_cpu_ram.memory[11'h012];
            assert (nes.internal_cpu_ram.memory[11'h010] == buttons)
                else $fatal(1, "game polled %02x instead of %02x",
                            nes.internal_cpu_ram.memory[11'h010], buttons);
            async_buttons = 8'h00;
            repeat (4) @(posedge clk);
            while (nes.internal_cpu_ram.memory[11'h012] == pressed_poll)
                @(posedge clk);
            assert (nes.internal_cpu_ram.memory[11'h010] == 8'h00);
        end
    endtask

    task automatic capture_frame(
        input string path,
        output integer sprite_min_x,
        output integer sprite_min_y,
        output integer sprite_count
    );
        integer frame_file;
        integer count;
        integer expected_x;
        integer expected_y;
        begin
            do @(negedge clk); while (!ppu_frame_start);
            frame_file = $fopen(path, "w");
            assert (frame_file != 0)
                else $fatal(1, "could not open frame artifact %s", path);
            count = 0;
            sprite_count = 0;
            sprite_min_x = 256;
            sprite_min_y = 240;
            while (count < 256 * 240) begin
                @(negedge clk);
                if (pixel_valid) begin
                    expected_x = count & 255;
                    expected_y = count >> 8;
                    assert (32'(pixel_x) == expected_x &&
                            32'(pixel_y) == expected_y)
                        else $fatal(1, "pixel sequence %0d got %0d,%0d",
                                    count, pixel_x, pixel_y);
                    $fwrite(frame_file, "%03x\n",
                            {pixel_emphasis, pixel_color});
                    if (pixel_source == 2'd2) begin
                        sprite_count = sprite_count + 1;
                        if (32'(pixel_x) < sprite_min_x)
                            sprite_min_x = 32'(pixel_x);
                        if (32'(pixel_y) < sprite_min_y)
                            sprite_min_y = 32'(pixel_y);
                    end
                    count = count + 1;
                end
            end
            $fclose(frame_file);
        end
    endtask

    initial begin
        integer title_x;
        integer title_y;
        integer title_sprites;
        integer start_x;
        integer start_y;
        integer start_sprites;
        integer action_x;
        integer action_y;
        integer action_sprites;
        integer before_x;
        integer before_y;
        integer before_render_x;
        integer before_render_y;
        integer target_frame;

        trace_file = $fopen("build/sim/phase4db_boot_trace.txt", "w");
        assert (trace_file != 0);
        $dumpfile("build/sim/nes_phase4db_playable.fst");
        $dumpvars(0, nes_phase4db_playable_tb);

        repeat (6) @(posedge clk);
        reset = 1'b0;

        while ((nes.internal_cpu_ram.memory[11'h00f] != 8'ha5 ||
                dma_completions < 3 || frame_count < 5) &&
               fabric_cycles < 1_000_000)
            @(posedge clk);
        assert (fabric_cycles < 1_000_000)
            else $fatal(1, "playable boot timeout pc=%04x", cpu_debug_pc);
        assert (cpu_debug_pc == 16'h80a5 || cpu_debug_pc >= 16'h8000);
        assert (cartridge_mirroring == 2'd1);
        assert (ppu_ctrl == 8'h80 && ppu_mask == 8'h1e);
        assert (nes.internal_cpu_ram.memory[11'h002] == 8'h00);
        assert (nes.internal_cpu_ram.memory[11'h00e] == 8'h00);
        assert (nes.ppu.background_core.memory.ciram[0] == 8'h01);
        assert (nes.ppu.background_core.memory.palette_ram[0] == 8'h0f);
        capture_frame("build/sim/phase4db_title.hex",
                      title_x, title_y, title_sprites);
        assert (title_sprites == 0 && title_x == 256 && title_y == 240)
            else $fatal(1, "title unexpectedly rendered player sprite");

        // Start transitions into gameplay through the complete controller path.
        drive_one_poll(8'h08);
        assert (nes.internal_cpu_ram.memory[11'h002] == 8'h01);
        assert (nes.internal_cpu_ram.memory[11'h200] == 8'h64);
        capture_frame("build/sim/phase4db_started.hex",
                      start_x, start_y, start_sprites);
        assert (start_sprites > 0 && start_x == 121 && start_y == 101)
            else $fatal(1, "started frame sprite count=%0d min=%0d,%0d",
                        start_sprites, start_x, start_y);

        // A, B, and Select produce persistent, independently visible state.
        drive_one_poll(8'h01);
        assert (nes.internal_cpu_ram.memory[11'h005] == 8'h01);
        assert (nes.internal_cpu_ram.memory[11'h202] == 8'h01);
        capture_frame("build/sim/phase4db_a.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0);

        drive_one_poll(8'h02);
        assert (nes.internal_cpu_ram.memory[11'h007] == 8'h03);
        assert (nes.internal_cpu_ram.memory[11'h201] == 8'h03);
        capture_frame("build/sim/phase4db_b.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0);

        drive_one_poll(8'h04);
        assert (nes.internal_cpu_ram.memory[11'h005] == 8'h02);
        assert (nes.internal_cpu_ram.memory[11'h202] == 8'h02);
        capture_frame("build/sim/phase4db_select.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0);
        before_render_x = action_x;
        before_render_y = action_y;

        // Every D-pad bit changes game state, OAM source bytes, and rendered
        // sprite coordinates. Opposite directions return to the prior point.
        before_x = 32'(nes.internal_cpu_ram.memory[11'h003]);
        drive_one_poll(8'h80);
        assert (32'(nes.internal_cpu_ram.memory[11'h003]) == before_x + 2);
        capture_frame("build/sim/phase4db_right.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0 && action_x == before_render_x + 2);

        drive_one_poll(8'h40);
        assert (32'(nes.internal_cpu_ram.memory[11'h003]) == before_x);
        capture_frame("build/sim/phase4db_left.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0 && action_x == before_render_x);

        before_y = 32'(nes.internal_cpu_ram.memory[11'h004]);
        drive_one_poll(8'h10);
        assert (32'(nes.internal_cpu_ram.memory[11'h004]) == before_y - 2);
        capture_frame("build/sim/phase4db_up.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0 && action_y == before_render_y - 2);

        drive_one_poll(8'h20);
        assert (32'(nes.internal_cpu_ram.memory[11'h004]) == before_y);
        capture_frame("build/sim/phase4db_down.hex",
                      action_x, action_y, action_sprites);
        assert (action_sprites > 0 && action_y == before_render_y);

        // Explicit boundary behavior: hold left/up long enough to reach the
        // minimum and prove additional polls cannot wrap either coordinate.
        async_buttons = 8'h50;
        while (nes.internal_cpu_ram.memory[11'h003] != 8'h08 ||
               nes.internal_cpu_ram.memory[11'h004] != 8'h10)
            @(posedge clk);
        target_frame = frame_count + 4;
        while (frame_count < target_frame)
            @(posedge clk);
        assert (nes.internal_cpu_ram.memory[11'h003] == 8'h08);
        assert (nes.internal_cpu_ram.memory[11'h004] == 8'h10);
        async_buttons = 8'h00;

        // Preserve an interaction waveform, then run hundreds of complete
        // frames without producing an unbounded trace file.
        $dumpoff;
        while (frame_count < 300)
            @(posedge clk);
        while (dma_active || await_dma_resume)
            @(posedge clk);
        while (!debug_destination_valid ||
               debug_destination_snapshot.system.source_frame_number <
               32'(frame_count))
            @(posedge debug_clk);
        @(negedge debug_clk);

        assert (reset_vector_low_reads >= 1 && reset_vector_high_reads >= 1);
        assert (prg_reads > 100_000);
        assert (ppu_register_writes >= 1_050);
        assert (saw_vblank && saw_rendering);
        assert (logged_initial_pc && logged_ram_initialization &&
                logged_ppu_initialization && logged_controller_poll &&
                logged_nametable_write && logged_palette_write);
        assert (nmi_events >= 290 && nmi_handlers >= 290);
        assert (nmi_events == nmi_handlers || nmi_events == nmi_handlers + 1);
        assert (dma_starts == dma_completions);
        assert (dma_reads == dma_completions * 256);
        assert (dma_writes == dma_completions * 256);
        assert (resumed_after_dma == dma_completions);
        assert (controller_polls >= 290);
        assert (controller_reads == controller_polls * 8);
        assert (!controller_strobe && controller_index == 4'd8 &&
                controller_latched == 8'hff);
        assert (saw_first_dma_byte && saw_last_dma_byte);
        assert (debug_capture_count == frame_count);
        assert (debug_update_count == frame_count);
        assert (!debug_source_busy);
        assert (debug_destination_snapshot.system.snapshot_id ==
                32'(frame_count));
        assert (debug_destination_snapshot.system.source_frame_number ==
                32'(frame_count));
        assert (debug_destination_snapshot.system.nmi_count <=
                32'(nmi_events) &&
                32'(nmi_events) -
                debug_destination_snapshot.system.nmi_count <= 32'd1);
        assert (debug_destination_snapshot.system.dma_count <=
                32'(dma_completions) &&
                32'(dma_completions) -
                debug_destination_snapshot.system.dma_count <= 32'd1);
        assert (debug_destination_snapshot.system.controller_poll_count <=
                32'(controller_polls) &&
                32'(controller_polls) -
                debug_destination_snapshot.system.controller_poll_count <=
                32'd1);
        assert (debug_destination_snapshot.system.cpu_slot_count <=
                32'(cpu_slots));
        assert (debug_destination_snapshot.system.ppu_cycle_count <=
                32'(ppu_cycles));
        assert (debug_destination_snapshot.system.prg_read_count > 32'd100_000);
        assert (debug_destination_snapshot.system.chr_read_count > 32'd100_000);
        assert (saw_snapshot_cpu_change);
        assert (saw_snapshot_controller_input);
        assert (saw_snapshot_cartridge_read);
        assert (saw_snapshot_dma_completion);
        assert (nes.internal_cpu_ram.memory[11'h00e] == 8'h00);
        assert (cpu_debug_pc >= 16'h8000 && cpu_debug_pc < 16'h9200);
        $fwrite(trace_file,
                "SUMMARY fabric=%0d ppu=%0d cpu_slots=%0d cpu_run=%0d frames=%0d nmi_events=%0d nmi_handlers=%0d dma=%0d polls=%0d reads4016=%0d pc=%04x sp=%02x\n",
                fabric_cycles, ppu_cycles, cpu_slots, cpu_run_cycles,
                frame_count, nmi_events, nmi_handlers, dma_completions,
                controller_polls, controller_reads, cpu_debug_pc,
                cpu_debug_sp);
        $fwrite(trace_file, "CPU A=%02x X=%02x Y=%02x P=%02x\n",
                cpu_debug_a, cpu_debug_x, cpu_debug_y, cpu_debug_status);
        $fclose(trace_file);

        $display("PASS: Phase 4D-B playable NROM boot/controller/NMI/DMA/PPU long run");
        $display("fabric=%0d ppu=%0d cpu_slots=%0d cpu_run=%0d frames=%0d",
                 fabric_cycles, ppu_cycles, cpu_slots, cpu_run_cycles,
                 frame_count);
        $display("nmi_events=%0d handlers=%0d dma=%0d reads=%0d writes=%0d resumes=%0d",
                 nmi_events, nmi_handlers, dma_completions, dma_reads,
                 dma_writes, resumed_after_dma);
        $display("controller_polls=%0d reads4016=%0d prg_reads=%0d ppu_writes=%0d pc=%04x sp=%02x",
                 controller_polls, controller_reads, prg_reads,
                 ppu_register_writes, cpu_debug_pc, cpu_debug_sp);
        $display("Phase 4E-A snapshots=%0d updates=%0d nmi=%0d dma=%0d polls=%0d prg=%0d chr=%0d",
                 debug_capture_count, debug_update_count,
                 debug_destination_snapshot.system.nmi_count,
                 debug_destination_snapshot.system.dma_count,
                 debug_destination_snapshot.system.controller_poll_count,
                 debug_destination_snapshot.system.prg_read_count,
                 debug_destination_snapshot.system.chr_read_count);
        $finish;
    end

    initial begin
        repeat (35_000_000) @(posedge clk);
        $fatal(1, "Phase 4D-B playable simulation timeout pc=%04x frame=%0d",
               cpu_debug_pc, frame_count);
    end
endmodule
