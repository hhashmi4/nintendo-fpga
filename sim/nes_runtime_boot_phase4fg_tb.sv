`timescale 1ns/1ps

module nes_runtime_boot_phase4fg_tb;
    logic unused_phase7a_mapper_irq_0;
    logic [13:0] unused_phase7a_mapper_ppu_address_1;
    logic unused_phase7a_mapper_ppu_read_2;
    logic unused_phase7a_mapper_ppu_write_3;
    import nes_runtime_loader_pkg::*;
    import nes_runtime_loader_mmio_pkg::*;

    logic source_clk = 1'b0;
    logic destination_clk = 1'b0;
    logic source_reset = 1'b1;
    logic destination_reset = 1'b1;

    logic [5:0] avs_address = 6'd0;
    logic avs_read = 1'b0;
    logic avs_write = 1'b0;
    logic [31:0] avs_writedata = 32'd0;
    logic [3:0] avs_byteenable = 4'hf;
    logic avs_waitrequest;
    logic [31:0] avs_readdata;
    logic avs_readdatavalid;

    logic source_valid;
    loader_command_t source_command;
    loader_target_t source_target;
    logic [15:0] source_address;
    logic [7:0] source_data;
    logic source_manifest_valid;
    logic [7:0] source_manifest_mapper;
    logic [15:0] source_manifest_prg_bytes;
    logic [15:0] source_manifest_chr_bytes;
    logic source_manifest_chr_is_ram;
    logic [1:0] source_manifest_mirroring;
    logic source_ready, source_busy, source_done;
    loader_state_t source_response_state;
    logic source_response_error;
    loader_error_t source_response_error_code;
    loader_state_t source_status_state;
    logic source_status_busy, source_status_ready;
    logic source_status_image_valid, source_status_runtime_active;
    logic source_status_nes_hold_reset, source_status_error;
    loader_error_t source_status_error_code;
    logic source_status_activation_in_progress;

    logic destination_valid;
    loader_command_t destination_command;
    loader_target_t destination_target;
    logic [15:0] destination_address;
    logic [7:0] destination_data;
    logic destination_manifest_valid;
    logic [7:0] destination_manifest_mapper;
    logic [15:0] destination_manifest_prg_bytes;
    logic [15:0] destination_manifest_chr_bytes;
    logic destination_manifest_chr_is_ram;
    logic [1:0] destination_manifest_mirroring;
    logic cartridge_command_ready, cartridge_command_accepted;
    logic gated_destination_valid, gated_destination_ready;
    logic backpressure_allow = 1'b0;

    loader_state_t loader_state;
    logic loader_busy, loader_completed, loader_error;
    loader_error_t loader_error_code;
    logic staged_image_valid, activation_accepted;
    logic activation_in_progress, activation_error;
    logic runtime_active, nes_hold_reset;
    logic functional_reset;
    logic cartridge_present;
    logic [7:0] mapper_number;
    logic nrom_256, chr_is_ram;
    logic [1:0] mirroring_mode;

    logic [15:0] cart_cpu_address;
    logic cart_cpu_read, cart_cpu_write;
    logic [7:0] cart_cpu_write_data, cart_cpu_read_data;
    logic [12:0] chr_address;
    logic chr_read, chr_write;
    logic [7:0] chr_write_data, chr_read_data;
    logic [14:0] debug_prg_address;
    logic [7:0] debug_prg_data;
    logic [12:0] debug_chr_address;
    logic [7:0] debug_chr_data;
    logic debug_prg_read, debug_prg_write;
    logic debug_prg_ram_read, debug_prg_ram_write;
    logic debug_chr_read, debug_chr_write;

    logic [7:0] async_buttons = 8'h00;
    logic [7:0] synced_buttons;
    logic controller_port, controller_cpu_read, controller_cpu_write;
    logic [7:0] controller_cpu_write_data, controller_cpu_read_data;

    logic nes_master_ce, nes_ppu_ce, unused_cpu_ce, unused_apu_ce;
    logic ppu_enable, cpu_enable;
    logic [15:0] cpu_debug_pc;
    logic dma_active, dma_start_event, dma_complete_event;
    logic [8:0] dma_read_count, dma_write_count;
    logic [9:0] dma_stall_cycles;
    logic [8:0] ppu_dot, ppu_scanline;
    logic ppu_frame_start, ppu_status_vblank, ppu_nmi_event;
    logic [7:0] ppu_ctrl, ppu_mask;
    logic pixel_valid;
    logic [7:0] pixel_x, pixel_y;
    logic [5:0] pixel_nes_color;
    logic [2:0] pixel_color_emphasis;
    logic [1:0] pixel_source;

    integer load_phase = 0;
    integer activated_game = 0;
    integer session_prg_writes = 0;
    integer session_chr_writes = 0;
    integer accepted_commands = 0;
    integer begin_count = 0;
    integer commit_count = 0;
    integer activation_count = 0;
    integer backpressure_cycles = 0;
    integer vector_a_low = 0;
    integer vector_a_high = 0;
    integer vector_b_low = 0;
    integer vector_b_high = 0;
    integer runtime_prg_reads = 0;
    integer runtime_chr_reads = 0;
    integer runtime_chr_writes = 0;
    integer nmi_events = 0;
    integer dma_starts = 0;
    integer dma_completions = 0;
    logic saw_chr_55 = 1'b0;
    logic saw_chr_aa = 1'b0;

    assign functional_reset = destination_reset || nes_hold_reset;
    assign gated_destination_valid = destination_valid && backpressure_allow;
    assign gated_destination_ready = cartridge_command_ready &&
                                     backpressure_allow;

    always #7 source_clk = !source_clk;
    always #10 destination_clk = !destination_clk;

    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            backpressure_allow <= 1'b0;
        end else if (!destination_valid || cartridge_command_accepted) begin
            backpressure_allow <= 1'b0;
        end else if (!backpressure_allow) begin
            // Every newly delivered CDC command waits at least one complete
            // destination cycle before the real cartridge sees valid/ready.
            backpressure_allow <= 1'b1;
        end
    end

    nes_runtime_loader_mmio mmio (
        .clk(source_clk), .reset(source_reset),
        .avs_address(avs_address), .avs_read(avs_read), .avs_write(avs_write),
        .avs_writedata(avs_writedata), .avs_byteenable(avs_byteenable),
        .avs_waitrequest(avs_waitrequest), .avs_readdata(avs_readdata),
        .avs_readdatavalid(avs_readdatavalid),
        .command_submit(source_valid), .command(source_command),
        .command_target(source_target), .command_address(source_address),
        .command_data(source_data), .manifest_valid(source_manifest_valid),
        .manifest_mapper(source_manifest_mapper),
        .manifest_prg_bytes(source_manifest_prg_bytes),
        .manifest_chr_bytes(source_manifest_chr_bytes),
        .manifest_chr_is_ram(source_manifest_chr_is_ram),
        .manifest_mirroring(source_manifest_mirroring),
        .command_channel_ready(source_ready),
        .command_channel_busy(source_busy), .command_done(source_done),
        .command_response_state(source_response_state),
        .command_response_error(source_response_error),
        .command_response_error_code(source_response_error_code),
        .status_loader_state(source_status_state),
        .status_loader_busy(source_status_busy),
        .status_loader_ready(source_status_ready),
        .status_image_valid(source_status_image_valid),
        .status_runtime_active(source_status_runtime_active),
        .status_nes_hold_reset(source_status_nes_hold_reset),
        .status_loader_error(source_status_error),
        .status_activation_in_progress(
            source_status_activation_in_progress)
    );

    nes_runtime_loader_cdc cdc (
        .source_clk(source_clk), .source_reset(source_reset),
        .source_valid(source_valid), .source_command(source_command),
        .source_target(source_target), .source_address(source_address),
        .source_data(source_data),
        .source_manifest_valid(source_manifest_valid),
        .source_manifest_mapper(source_manifest_mapper),
        .source_manifest_prg_bytes(source_manifest_prg_bytes),
        .source_manifest_chr_bytes(source_manifest_chr_bytes),
        .source_manifest_chr_is_ram(source_manifest_chr_is_ram),
        .source_manifest_mirroring(source_manifest_mirroring),
        .source_ready(source_ready), .source_busy(source_busy),
        .source_done(source_done),
        .source_response_state(source_response_state),
        .source_response_error(source_response_error),
        .source_response_error_code(source_response_error_code),
        .source_status_state(source_status_state),
        .source_status_busy(source_status_busy),
        .source_status_ready(source_status_ready),
        .source_status_image_valid(source_status_image_valid),
        .source_status_runtime_active(source_status_runtime_active),
        .source_status_nes_hold_reset(source_status_nes_hold_reset),
        .source_status_error(source_status_error),
        .source_status_error_code(source_status_error_code),
        .source_status_activation_in_progress(
            source_status_activation_in_progress),
        .destination_clk(destination_clk),
        .destination_reset(destination_reset),
        .destination_valid(destination_valid),
        .destination_command(destination_command),
        .destination_target(destination_target),
        .destination_address(destination_address),
        .destination_data(destination_data),
        .destination_manifest_valid(destination_manifest_valid),
        .destination_manifest_mapper(destination_manifest_mapper),
        .destination_manifest_prg_bytes(destination_manifest_prg_bytes),
        .destination_manifest_chr_bytes(destination_manifest_chr_bytes),
        .destination_manifest_chr_is_ram(destination_manifest_chr_is_ram),
        .destination_manifest_mirroring(destination_manifest_mirroring),
        .destination_command_ready(gated_destination_ready),
        .destination_command_accepted(cartridge_command_accepted),
        .destination_status_state(loader_state),
        .destination_status_busy(loader_busy),
        .destination_status_image_valid(staged_image_valid),
        .destination_status_runtime_active(runtime_active),
        .destination_status_nes_hold_reset(nes_hold_reset),
        .destination_status_error(loader_error),
        .destination_status_error_code(loader_error_code),
        .destination_status_activation_in_progress(activation_in_progress)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    nes_cartridge_runtime_mux #(
        .LEGACY_MAPPER_NUMBER(0),
        .LEGACY_PRG_ROM_BYTES(16384),
        .LEGACY_CHR_IS_RAM(1'b0),
        .LEGACY_PRG_RAM_ENABLE(1'b0),
        .LEGACY_MIRRORING_MODE(LOADER_MIRROR_HORIZONTAL),
        .LEGACY_PRG_INIT_FILE(
            "build/cartridge/phase4b_boot_nrom128.prg.hex"),
        .LEGACY_CHR_INIT_FILE(
            "build/cartridge/phase4b_boot_nrom128.chr.hex"),
        .ACTIVATION_RESET_CYCLES(4)
    ) cartridge (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .mapper_irq(unused_phase7a_mapper_irq_0),
        .clk(destination_clk), .reset(destination_reset),
        .command_valid(gated_destination_valid),
        .command(destination_command), .command_target(destination_target),
        .command_address(destination_address), .command_data(destination_data),
        .command_ready(cartridge_command_ready),
        .command_accepted(cartridge_command_accepted),
        .manifest_valid(destination_manifest_valid),
        .manifest_mapper(destination_manifest_mapper),
        .manifest_prg_bytes(destination_manifest_prg_bytes),
        .manifest_chr_bytes(destination_manifest_chr_bytes),
        .manifest_chr_is_ram(destination_manifest_chr_is_ram),
        .manifest_mirroring(destination_manifest_mirroring),
        .cpu_address(cart_cpu_address), .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write), .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data), .chr_address(chr_address),
        .chr_read(chr_read), .chr_write(chr_write),
        .chr_write_data(chr_write_data), .chr_read_data(chr_read_data),
        .cartridge_present(cartridge_present), .mapper_number(mapper_number),
        .nrom_256(nrom_256), .chr_is_ram(chr_is_ram),
        .mirroring_mode(mirroring_mode), .loader_state(loader_state),
        .loader_busy(loader_busy), .loader_completed(loader_completed),
        .loader_error(loader_error), .loader_error_code(loader_error_code),
        .staged_image_valid(staged_image_valid),
        .activation_accepted(activation_accepted),
        .activation_in_progress(activation_in_progress),
        .activation_error(activation_error), .runtime_active(runtime_active),
        .nes_hold_reset(nes_hold_reset), .debug_prg_address(debug_prg_address),
        .debug_prg_data(debug_prg_data), .debug_chr_address(debug_chr_address),
        .debug_chr_data(debug_chr_data), .debug_prg_read(debug_prg_read),
        .debug_prg_write(debug_prg_write),
        .debug_prg_ram_read(debug_prg_ram_read),
        .debug_prg_ram_write(debug_prg_ram_write),
        .debug_chr_read(debug_chr_read), .debug_chr_write(debug_chr_write)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    controller_input_sync #(.WIDTH(8)) input_synchronizer (
        .clk(destination_clk), .reset(functional_reset),
        .async_buttons(async_buttons), .synced_buttons(synced_buttons)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(destination_clk), .reset(functional_reset),
        .controller1_buttons(synced_buttons),
        .controller2_buttons(8'h00), .cpu_port(controller_port),
        .cpu_read(controller_cpu_read), .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data), .debug_strobe(),
        .debug_live_controller1(), .debug_live_controller2(),
        .debug_shift_controller1(), .debug_shift_controller2(),
        .debug_index_controller1(), .debug_index_controller2(),
        .debug_serial_controller1(), .debug_serial_controller2(),
        .debug_read_4016(), .debug_read_4017(), .debug_latch_event()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    nes_timing_gen rate_generator (
        .clk(destination_clk), .reset(destination_reset),
        .nes_master_ce(nes_master_ce), .ppu_ce(nes_ppu_ce),
        .cpu_ce(unused_cpu_ce), .apu_ce(unused_apu_ce)
    );

    /* verilator lint_off PINMISSING */
    nes_core nes (
        .mapper_ppu_address(unused_phase7a_mapper_ppu_address_1),
        .mapper_ppu_read(unused_phase7a_mapper_ppu_read_2),
        .mapper_ppu_write(unused_phase7a_mapper_ppu_write_3),
        .clk(destination_clk), .reset(functional_reset),
        .nes_enable(nes_ppu_ce), .irq(1'b0),
        .mirroring_mode(mirroring_mode), .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read), .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data), .apu_cpu_read_data(8'h00),
        .dmc_mem_request(1'b0), .dmc_mem_address(16'h0000),
        .dmc_mem_acknowledge(), .dmc_mem_read_data(),
        .controller_port(controller_port),
        .controller_cpu_read(controller_cpu_read),
        .controller_cpu_write(controller_cpu_write),
        .controller_cpu_write_data(controller_cpu_write_data),
        .controller_cpu_read_data(controller_cpu_read_data),
        .chr_addr(chr_address), .chr_read(chr_read), .chr_write(chr_write),
        .chr_write_data(chr_write_data), .chr_read_data(chr_read_data),
        .ppu_enable(ppu_enable), .cpu_enable(cpu_enable),
        .cpu_debug_pc(cpu_debug_pc), .dma_active(dma_active),
        .dma_start_event(dma_start_event),
        .dma_complete_event(dma_complete_event),
        .dma_read_count(dma_read_count), .dma_write_count(dma_write_count),
        .dma_stall_cycles(dma_stall_cycles), .ppu_dot(ppu_dot),
        .ppu_scanline(ppu_scanline), .ppu_frame_start(ppu_frame_start),
        .ppu_status_vblank(ppu_status_vblank), .ppu_ctrl(ppu_ctrl),
        .ppu_mask(ppu_mask), .ppu_nmi_event(ppu_nmi_event),
        .pixel_valid(pixel_valid), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_nes_color(pixel_nes_color),
        .pixel_color_emphasis(pixel_color_emphasis),
        .pixel_source(pixel_source)
    );
    /* verilator lint_on PINMISSING */

    task automatic av_write(input logic [5:0] address,
                            input logic [31:0] data);
        logic [31:0] before_count;
        logic [31:0] count;
        logic [31:0] status;
        begin
            if (address == MMIO_REG_COMMAND) begin
                do av_read(MMIO_REG_STATUS, status);
                while (!status[MMIO_STATUS_BRIDGE_READY_BIT]);
                av_read(MMIO_REG_COMPLETED_COUNT, before_count);
            end
            @(negedge source_clk);
            avs_address = address;
            avs_writedata = data;
            avs_byteenable = 4'hf;
            avs_write = 1'b1;
            @(negedge source_clk);
            assert (!avs_waitrequest);
            avs_write = 1'b0;
            avs_address = 6'd0;
            avs_writedata = 32'd0;
            if (address == MMIO_REG_COMMAND) begin
                for (integer poll = 0; poll < 10000; poll++) begin
                    av_read(MMIO_REG_STATUS, status);
                    av_read(MMIO_REG_COMPLETED_COUNT, count);
                    if (count != before_count &&
                        !status[MMIO_STATUS_COMMAND_PENDING_BIT])
                        return;
                end
                $fatal(1, "MMIO command %0d did not complete", data[1:0]);
            end
        end
    endtask

    task automatic av_read(input logic [5:0] address,
                           output logic [31:0] data);
        begin
            @(negedge source_clk);
            avs_address = address;
            avs_read = 1'b1;
            @(negedge source_clk);
            data = avs_readdata;
            assert (!avs_waitrequest && avs_readdatavalid);
            avs_read = 1'b0;
            avs_address = 6'd0;
        end
    endtask

    task automatic replay_trace(input string path);
        integer descriptor;
        integer parsed;
        integer line_number;
        integer polls;
        string line;
        string operation;
        logic [31:0] first, second, third, value;
        begin
            descriptor = $fopen(path, "r");
            assert (descriptor != 0)
                else $fatal(1, "could not open MMIO trace %s", path);
            line_number = 0;
            while ($fgets(line, descriptor) != 0) begin
                line_number = line_number + 1;
                operation = "";
                first = 0;
                second = 0;
                third = 0;
                parsed = $sscanf(line, "%s %h %h %h",
                                 operation, first, second, third);
                if (parsed == 0 || operation == "#") begin
                    // Blank/comment line.
                end else if (operation == "W" && parsed == 3) begin
                    av_write(first[5:0], second);
                end else if (operation == "R" && parsed == 4) begin
                    av_read(first[5:0], value);
                    assert ((value & second) == third)
                        else $fatal(1,
                            "%s:%0d read[%02x]=%08x mask=%08x expected=%08x",
                            path, line_number, first[5:0], value, second, third);
                end else if (operation == "S" && parsed == 3) begin
                    polls = 0;
                    do begin
                        av_read(MMIO_REG_STATUS, value);
                        polls = polls + 1;
                        if (polls == 100000)
                            $fatal(1,
                                "%s:%0d status=%08x mask=%08x expected=%08x",
                                path, line_number, value, first, second);
                    end while ((value & first) != second);
                end else begin
                    $fatal(1, "%s:%0d malformed trace operation: %s",
                           path, line_number, line);
                end
            end
            $fclose(descriptor);
        end
    endtask

    task automatic wait_for_game_a;
        integer timeout;
        begin
            timeout = 0;
            while ((nes.internal_cpu_ram.memory[11'h002] != 8'h42 ||
                    nes.internal_cpu_ram.memory[11'h003] != 8'h4f ||
                    nes.internal_cpu_ram.memory[11'h004] != 8'h47 ||
                    nes.internal_cpu_ram.memory[11'h012] != 8'hd1 ||
                    ppu_ctrl != 8'h80 || ppu_mask != 8'h0a ||
                    vector_a_low == 0 || vector_a_high == 0 ||
                    dma_completions == 0) && timeout < 3_000_000) begin
                @(posedge destination_clk);
                timeout = timeout + 1;
            end
            assert (timeout < 3_000_000)
                else $fatal(1, "Game A boot timed out pc=%04x", cpu_debug_pc);
            assert (!nrom_256 && !chr_is_ram &&
                    mirroring_mode == LOADER_MIRROR_HORIZONTAL);
            assert (ppu_ctrl == 8'h80 && ppu_mask == 8'h0a);
            assert (dma_read_count == 9'd256 && dma_write_count == 9'd256);
            assert (dma_stall_cycles == 10'd513 || dma_stall_cycles == 10'd514);
        end
    endtask

    task automatic capture_frame(input string path);
        integer descriptor;
        integer count;
        integer expected_x;
        integer expected_y;
        begin
            do @(negedge destination_clk); while (!ppu_frame_start);
            descriptor = $fopen(path, "w");
            assert (descriptor != 0);
            count = 0;
            while (count < 256 * 240) begin
                @(negedge destination_clk);
                if (pixel_valid) begin
                    expected_x = count & 255;
                    expected_y = count >> 8;
                    assert (32'(pixel_x) == expected_x &&
                            32'(pixel_y) == expected_y)
                        else $fatal(1, "frame sequence %0d got %0d,%0d",
                                    count, pixel_x, pixel_y);
                    $fwrite(descriptor, "%03x\n",
                            {pixel_color_emphasis, pixel_nes_color});
                    count = count + 1;
                end
            end
            $fclose(descriptor);
            $display("runtime frame=Game-A pixels=%0d mismatches=checked-by-Python",
                     count);
        end
    endtask

    always_ff @(posedge destination_clk) begin
        if (!destination_reset) begin
            if (destination_valid && !backpressure_allow)
                backpressure_cycles <= backpressure_cycles + 1;
            if (cartridge_command_accepted) begin
                accepted_commands <= accepted_commands + 1;
                case (destination_command)
                    LOADER_COMMAND_BEGIN: begin
                        begin_count <= begin_count + 1;
                        session_prg_writes <= 0;
                        session_chr_writes <= 0;
                    end
                    LOADER_COMMAND_WRITE: begin
                        if (destination_target == LOADER_TARGET_PRG)
                            session_prg_writes <= session_prg_writes + 1;
                        else if (destination_target == LOADER_TARGET_CHR)
                            session_chr_writes <= session_chr_writes + 1;
                    end
                    LOADER_COMMAND_COMMIT: begin
                        commit_count <= commit_count + 1;
                        case (load_phase)
                            1: assert (session_prg_writes == 16384 &&
                                       session_chr_writes == 8192);
                            2: assert (session_prg_writes == 257 &&
                                       session_chr_writes == 0);
                            3: assert (session_prg_writes == 32768 &&
                                       session_chr_writes == 0);
                            default: $fatal(1, "COMMIT outside load phase");
                        endcase
                    end
                    LOADER_COMMAND_ACTIVATE: begin
                        activation_count <= activation_count + 1;
                        activated_game <= load_phase;
                    end
                    default: $fatal(1, "unknown accepted loader command");
                endcase
            end

            if (runtime_active && !functional_reset && cart_cpu_read) begin
                runtime_prg_reads <= runtime_prg_reads + 1;
                if (cart_cpu_address == 16'hfffc) begin
                    if (activated_game == 1) begin
                        vector_a_low <= vector_a_low + 1;
                        assert (cart_cpu_read_data == 8'h00);
                    end else if (activated_game == 3) begin
                        vector_b_low <= vector_b_low + 1;
                        assert (cart_cpu_read_data == 8'h00);
                    end
                end
                if (cart_cpu_address == 16'hfffd) begin
                    if (activated_game == 1) begin
                        vector_a_high <= vector_a_high + 1;
                        assert (cart_cpu_read_data == 8'h80);
                    end else if (activated_game == 3) begin
                        vector_b_high <= vector_b_high + 1;
                        assert (cart_cpu_read_data == 8'hc0);
                    end
                end
            end
            if (runtime_active && debug_chr_read) begin
                runtime_chr_reads <= runtime_chr_reads + 1;
                if (activated_game == 1 && debug_chr_data == 8'h55)
                    saw_chr_55 <= 1'b1;
                if (activated_game == 1 && debug_chr_data == 8'haa)
                    saw_chr_aa <= 1'b1;
            end
            if (runtime_active && debug_chr_write)
                runtime_chr_writes <= runtime_chr_writes + 1;
            if (ppu_nmi_event)
                nmi_events <= nmi_events + 1;
            if (dma_start_event)
                dma_starts <= dma_starts + 1;
            if (dma_complete_event)
                dma_completions <= dma_completions + 1;

            if (nes_hold_reset) begin
                assert (!cpu_enable && !ppu_enable);
                assert (!debug_prg_read && !debug_chr_read);
            end
            if (staged_image_valid) begin
                if (load_phase == 1)
                    assert (session_prg_writes == 16384 &&
                            session_chr_writes == 8192);
                if (load_phase == 3)
                    assert (session_prg_writes == 32768 &&
                            session_chr_writes == 0);
            end
        end
    end

    initial begin : phase4fg_test
        integer timeout;
        integer nmi_before;
        integer activation_before;
        integer commands_before;

        $dumpfile("build/sim/nes_runtime_boot_phase4fg.fst");
        $dumpvars(0, nes_runtime_boot_phase4fg_tb);
        #200;
        @(negedge source_clk);
        source_reset = 1'b0;
        @(negedge destination_clk);
        destination_reset = 1'b0;

        load_phase = 1;
        commands_before = accepted_commands;
        replay_trace("build/runtime_e2e/game_a.mmio");
        assert (accepted_commands - commands_before == 24579);
        assert (session_prg_writes == 16384 && session_chr_writes == 8192);
        assert (runtime_active && staged_image_valid && !nes_hold_reset);
        wait_for_game_a();
        assert (runtime_prg_reads > 0 && dma_starts == 1 && dma_completions == 1);

        async_buttons = 8'h01;
        timeout = 0;
        while (nes.internal_cpu_ram.memory[11'h011] != 8'h01 &&
               timeout < 300000) begin
            @(posedge destination_clk);
            timeout = timeout + 1;
        end
        assert (timeout < 300000)
            else $fatal(1, "runtime Game A did not consume controller A");
        async_buttons = 8'h00;
        timeout = 0;
        while (nes.internal_cpu_ram.memory[11'h011] != 8'h00 &&
               timeout < 300000) begin
            @(posedge destination_clk);
            timeout = timeout + 1;
        end
        assert (timeout < 300000);

        nmi_before = integer'(nes.internal_cpu_ram.memory[11'h010]);
        while (nes.internal_cpu_ram.memory[11'h010] == 8'(nmi_before))
            @(posedge destination_clk);
        assert (nmi_events > 0);
        capture_frame("build/sim/phase4fg_game_a.hex");
        assert (saw_chr_55 && saw_chr_aa && runtime_chr_reads > 1000)
            else $fatal(1, "runtime CHR-ROM pattern was not consumed by PPU");

        // Incomplete Game B replacement in the same configured FPGA. BEGIN
        // safely holds the NES; failed COMMIT cannot execute partial storage.
        load_phase = 2;
        activation_before = activation_count;
        commands_before = accepted_commands;
        replay_trace("build/runtime_e2e/failed_replacement.mmio");
        assert (accepted_commands - commands_before == 259);
        assert (activation_count == activation_before);
        assert (loader_error && loader_error_code == LOADER_ERROR_PRG_INCOMPLETE);
        assert (runtime_active && nes_hold_reset && functional_reset);
        assert (!staged_image_valid && !activation_in_progress);
        assert (!nrom_256 && !chr_is_ram);
        repeat (100) @(posedge destination_clk);
        assert (nes.internal_cpu_ram.memory[11'h002] == 8'h42 &&
                nes.internal_cpu_ram.memory[11'h003] == 8'h4f &&
                nes.internal_cpu_ram.memory[11'h004] == 8'h47);

        // A fresh valid BEGIN is the specified recovery. Game B replaces A
        // without resetting or reconfiguring the FPGA fabric.
        load_phase = 3;
        commands_before = accepted_commands;
        replay_trace("build/runtime_e2e/game_b.mmio");
        assert (accepted_commands - commands_before == 32771);
        assert (session_prg_writes == 32768 && session_chr_writes == 0);
        assert (runtime_active && nrom_256 && chr_is_ram && !nes_hold_reset);
        assert (mirroring_mode == LOADER_MIRROR_VERTICAL);
        timeout = 0;
        while ((nes.internal_cpu_ram.memory[11'h002] != 8'h47 ||
                nes.internal_cpu_ram.memory[11'h003] != 8'h42 ||
                nes.internal_cpu_ram.memory[11'h004] != 8'h32 ||
                nes.internal_cpu_ram.memory[11'h020] != 8'h3c ||
                nes.internal_cpu_ram.memory[11'h021] != 8'hc7 ||
                nes.internal_cpu_ram.memory[11'h022] != 8'ha6 ||
                vector_b_low == 0 || vector_b_high == 0) &&
               timeout < 1_000_000) begin
            @(posedge destination_clk);
            timeout = timeout + 1;
        end
        assert (timeout < 1_000_000)
            else $fatal(1,
                "Game B boot/CHR-RAM timed out pc=%04x sig=%02x%02x%02x halves=%02x/%02x chr=%02x storage=%02x buffer=%02x writes=%0d reads=%0d addr=%04x",
                cpu_debug_pc,
                nes.internal_cpu_ram.memory[11'h002],
                nes.internal_cpu_ram.memory[11'h003],
                nes.internal_cpu_ram.memory[11'h004],
                nes.internal_cpu_ram.memory[11'h020],
                nes.internal_cpu_ram.memory[11'h021],
                nes.internal_cpu_ram.memory[11'h022],
                cartridge.runtime_cartridge.mapper.storage.chr_memory[13'h010],
                nes.ppu.background_core.core.registers.ppu_data_read_buffer,
                runtime_chr_writes, runtime_chr_reads, chr_address);
        assert (runtime_chr_writes > 0 && runtime_chr_reads > 1000);
        assert (begin_count == 3 && commit_count == 3 && activation_count == 2);
        assert (accepted_commands == 57609);
        assert (backpressure_cycles == accepted_commands);

        $display("PASS: Phase 4F-G .nes->parser/load-plan->MMIO/CDC->runtime cartridge->NES boot");
        $display("Game A PRG=%0d CHR=%0d signature=424f47 vectors=%0d/%0d NMI=%0d DMA=%0d controller=A frame_pixels=61440",
                 16384, 8192, vector_a_low, vector_a_high,
                 nmi_events, dma_completions);
        $display("failed replacement PRG=257 CHR=0 error=PRG_INCOMPLETE held_reset=1");
        $display("Game B PRG=%0d CHR=%0d signature=474232 vectors=%0d/%0d lower=3c upper=c7 CHR-RAM=a6",
                 32768, 0, vector_b_low, vector_b_high);
        $display("commands=%0d BEGIN=%0d COMMIT=%0d ACTIVATE=%0d backpressure_cycles=%0d",
                 accepted_commands, begin_count, commit_count,
                 activation_count, backpressure_cycles);
        $finish;
    end

    initial begin
        #200_000_000;
        $fatal(1, "Phase 4F-G end-to-end timeout");
    end
endmodule
