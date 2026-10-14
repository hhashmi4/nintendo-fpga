`timescale 1ns/1ps

module nes_dmc_system_phase5f_tb;
    logic unused_phase7a_mapper_irq_0;
    logic [1:0] unused_phase7a_mapper_mirroring_1;
    logic [13:0] unused_phase7a_mapper_ppu_address_2;
    logic unused_phase7a_mapper_ppu_read_3;
    logic unused_phase7a_mapper_ppu_write_4;
    import nes_apu_pkg::*;
    import nes_runtime_loader_pkg::*;
    import nes_system_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic debugger_authorized = 1'b1;
    logic functional_reset;

    logic command_valid = 1'b0;
    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic [15:0] command_address = 16'h0000;
    logic [7:0] command_data = 8'h00;
    logic command_ready;
    logic command_accepted;
    logic manifest_valid = 1'b1;
    logic [7:0] manifest_mapper = 8'd0;
    logic [15:0] manifest_prg_bytes = LOADER_PRG_NROM128_BYTES;
    logic [15:0] manifest_chr_bytes = 16'h0000;
    logic manifest_chr_is_ram = 1'b1;
    logic [1:0] manifest_mirroring = LOADER_MIRROR_HORIZONTAL;
    logic nes_hold_reset;
    logic runtime_active;
    logic activation_accepted;
    logic activation_in_progress;
    logic loader_completed;
    logic loader_error;

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

    logic [15:0] apu_cpu_address;
    logic apu_cpu_read;
    logic apu_cpu_write;
    logic [7:0] apu_cpu_write_data;
    logic [7:0] apu_cpu_read_data;
    logic apu_irq;
    nes_apu_channel_mask_t apu_channel_enable;
    logic [3:0] pulse1_output;
    logic [3:0] pulse2_output;
    logic [3:0] triangle_output;
    logic [3:0] noise_output;
    logic [6:0] dmc_output;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [19:0] mixed_audio;
    /* verilator lint_on UNUSEDSIGNAL */
    logic frame_irq_flag;
    logic [15:0] frame_sequence_cycle;
    logic dmc_mem_request;
    logic [15:0] dmc_mem_address;
    logic dmc_mem_acknowledge;
    logic [7:0] dmc_mem_read_data;

    logic controller_port;
    logic controller_cpu_read;
    logic controller_cpu_write;
    logic [7:0] controller_cpu_write_data;
    logic [7:0] controller_cpu_read_data;

    logic ppu_enable;
    logic cpu_cycle_slot;
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic [15:0] cpu_debug_pc;
    logic dma_active;
    logic dma_read_event;
    logic dma_write_event;
    logic dma_complete_event;
    logic dmc_dma_active;
    logic dmc_dma_cpu_stall;
    logic [2:0] dmc_dma_phase;
    logic dmc_dma_read_event;
    logic dmc_dma_start_event;
    logic dmc_dma_complete_event;
    nes_bus_master_t internal_bus_owner;

    integer dmc_fetches = 0;
    integer dmc_oam_collisions = 0;
    integer oam_completions = 0;
    integer oam_reads = 0;
    integer oam_writes = 0;
    integer controller_reads = 0;
    integer pause_cycles = 0;
    integer replacement_count = 0;
    integer all_active_cycles = 0;
    integer all_nonzero_cycles = 0;
    integer nrom128_fetches = 0;
    integer nrom256_fetches = 0;
    logic image_b_active = 1'b0;

    assign functional_reset = reset || nes_hold_reset;

    /* verilator lint_off PINMISSING */
    nes_core nes (
        .mapper_ppu_address(unused_phase7a_mapper_ppu_address_2),
        .mapper_ppu_read(unused_phase7a_mapper_ppu_read_3),
        .mapper_ppu_write(unused_phase7a_mapper_ppu_write_4),
        .clk(clk),
        .reset(functional_reset),
        .nes_enable(debugger_authorized),
        .irq(apu_irq),
        .mirroring_mode(LOADER_MIRROR_HORIZONTAL),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_address(apu_cpu_address),
        .apu_cpu_read(apu_cpu_read),
        .apu_cpu_write(apu_cpu_write),
        .apu_cpu_write_data(apu_cpu_write_data),
        .apu_cpu_read_data(apu_cpu_read_data),
        .dmc_mem_request(dmc_mem_request),
        .dmc_mem_address(dmc_mem_address),
        .dmc_mem_acknowledge(dmc_mem_acknowledge),
        .dmc_mem_read_data(dmc_mem_read_data),
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
        .ppu_enable(ppu_enable),
        .cpu_cycle_slot(cpu_cycle_slot),
        .cpu_enable(cpu_enable),
        .cpu_address(cpu_address),
        .cpu_debug_pc(cpu_debug_pc),
        .dma_active(dma_active),
        .dma_read_event(dma_read_event),
        .dma_write_event(dma_write_event),
        .dma_complete_event(dma_complete_event),
        .internal_bus_owner(internal_bus_owner),
        .dmc_dma_active(dmc_dma_active),
        .dmc_dma_cpu_stall(dmc_dma_cpu_stall),
        .dmc_dma_phase(dmc_dma_phase),
        .dmc_dma_read_event(dmc_dma_read_event),
        .dmc_dma_start_event(dmc_dma_start_event),
        .dmc_dma_complete_event(dmc_dma_complete_event)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_apu apu (
        .clk(clk),
        .reset(functional_reset),
        .cpu_cycle_enable(cpu_cycle_slot),
        .cpu_read(apu_cpu_read),
        .cpu_write(apu_cpu_write),
        .cpu_address(apu_cpu_address),
        .cpu_write_data(apu_cpu_write_data),
        .cpu_read_data(apu_cpu_read_data),
        .dmc_mem_request(dmc_mem_request),
        .dmc_mem_address(dmc_mem_address),
        .dmc_mem_acknowledge(dmc_mem_acknowledge),
        .dmc_mem_read_data(dmc_mem_read_data),
        .channel_active('0),
        .dmc_irq_flag(1'b0),
        .channel_enable(apu_channel_enable),
        .channel_write(),
        .channel_write_register(),
        .channel_write_data(),
        .dmc_irq_clear(),
        .quarter_frame_tick(),
        .half_frame_tick(),
        .irq(apu_irq),
        .pulse1_output(pulse1_output),
        .pulse2_output(pulse2_output),
        .triangle_output(triangle_output),
        .noise_output(noise_output),
        .dmc_output(dmc_output),
        .mixed_audio(mixed_audio),
        .frame_mode(),
        .frame_irq_inhibit(),
        .frame_irq_flag(frame_irq_flag),
        .frame_sequence_cycle(frame_sequence_cycle),
        .cpu_cycle_odd(),
        .frame_reset_pending(),
        .frame_reset_delay(),
        .frame_tick_block()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(clk),
        .reset(functional_reset),
        .controller1_buttons(8'b1010_0101),
        .controller2_buttons(8'b0101_1010),
        .cpu_port(controller_port),
        .cpu_read(controller_cpu_read),
        .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data),
        .debug_strobe(),
        .debug_live_controller1(),
        .debug_live_controller2(),
        .debug_shift_controller1(),
        .debug_shift_controller2(),
        .debug_index_controller1(),
        .debug_index_controller2(),
        .debug_serial_controller1(),
        .debug_serial_controller2(),
        .debug_read_4016(),
        .debug_read_4017(),
        .debug_latch_event()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_runtime_cartridge #(
        .IMAGE_VALIDATION_ENABLE(1'b1),
        .ACTIVATION_ENABLE(1'b1),
        .ACTIVATION_RESET_CYCLES(4)
    ) cartridge (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .mapper_irq(unused_phase7a_mapper_irq_0),
        .mapper_mirroring(unused_phase7a_mapper_mirroring_1),
        .clk(clk),
        .reset(reset),
        .command_valid(command_valid),
        .command(command),
        .command_target(command_target),
        .command_address(command_address),
        .command_data(command_data),
        .command_ready(command_ready),
        .command_accepted(command_accepted),
        .manifest_valid(manifest_valid),
        .manifest_mapper(manifest_mapper),
        .manifest_prg_bytes(manifest_prg_bytes),
        .manifest_chr_bytes(manifest_chr_bytes),
        .manifest_chr_is_ram(manifest_chr_is_ram),
        .manifest_mirroring(manifest_mirroring),
        .nrom_256(1'b0),
        .chr_is_ram(1'b1),
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
        .loader_state(),
        .loader_busy(),
        .loader_completed(loader_completed),
        .loader_error(loader_error),
        .loader_error_code(),
        .nes_hold_reset(nes_hold_reset),
        .image_valid(),
        .image_mapper(),
        .image_prg_bytes(),
        .image_chr_bytes(),
        .image_chr_is_ram(),
        .image_mirroring(),
        .activation_accepted(activation_accepted),
        .activation_in_progress(activation_in_progress),
        .activation_error(),
        .runtime_active(runtime_active),
        .active_mapper(),
        .active_prg_bytes(),
        .active_chr_bytes(),
        .active_chr_is_ram(),
        .active_mirroring(),
        .debug_prg_address(),
        .debug_prg_data(),
        .debug_chr_address(),
        .debug_chr_data(),
        .debug_prg_read(),
        .debug_prg_write(),
        .debug_chr_read(),
        .debug_chr_write()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk <= !clk;

    function automatic logic [7:0] setup_value(input logic [4:0] index);
        begin
            case (index)
                0: setup_value = 8'h0f; // enable P1/P2/T/N before length loads
                1: setup_value = 8'hff; // Pulse 1 duty/halt/constant volume
                2: setup_value = 8'h08;
                3: setup_value = 8'h08;
                4: setup_value = 8'hba; // Pulse 2 distinct duty/volume
                5: setup_value = 8'h80;
                6: setup_value = 8'h08;
                7: setup_value = 8'hff; // Triangle control/linear reload
                8: setup_value = 8'h06;
                9: setup_value = 8'h08;
                10: setup_value = 8'h3d; // Noise halt/constant volume
                11: setup_value = 8'h82;
                12: setup_value = 8'h08;
                13: setup_value = 8'h4f; // DMC loop, fastest NTSC rate
                14: setup_value = 8'h40;
                15: setup_value = 8'h00;
                16: setup_value = 8'h01;
                17: setup_value = 8'h1f; // all five enabled
                default: setup_value = 8'h00;
            endcase
        end
    endfunction

    function automatic logic [7:0] setup_register(input logic [4:0] index);
        begin
            case (index)
                0: setup_register = 8'h15;
                1: setup_register = 8'h00;
                2: setup_register = 8'h02;
                3: setup_register = 8'h03;
                4: setup_register = 8'h04;
                5: setup_register = 8'h06;
                6: setup_register = 8'h07;
                7: setup_register = 8'h08;
                8: setup_register = 8'h0a;
                9: setup_register = 8'h0b;
                10: setup_register = 8'h0c;
                11: setup_register = 8'h0e;
                12: setup_register = 8'h0f;
                13: setup_register = 8'h10;
                14: setup_register = 8'h11;
                15: setup_register = 8'h12;
                16: setup_register = 8'h13;
                17: setup_register = 8'h15;
                default: setup_register = 8'h00;
            endcase
        end
    endfunction

    function automatic logic [7:0] setup_program_byte(
        input logic [15:0] address
    );
        logic [4:0] instruction;
        logic [2:0] byte_index;
        begin
            instruction = 5'(address / 5);
            byte_index = 3'(address % 5);
            case (byte_index)
                0: setup_program_byte = 8'ha9; // LDA immediate
                1: setup_program_byte = setup_value(instruction);
                2: setup_program_byte = 8'h8d; // STA absolute
                3: setup_program_byte = setup_register(instruction);
                default: setup_program_byte = 8'h40;
            endcase
        end
    endfunction

    function automatic logic [7:0] image_a_prg(input logic [15:0] address);
        begin
            image_a_prg = address[7:0] ^ address[15:8] ^ 8'h5a;
            if (address < 16'd90) begin
                image_a_prg = setup_program_byte(address);
            end else begin
                case (address)
                    16'd90: image_a_prg = 8'ha9; // LDA #$02
                    16'd91: image_a_prg = 8'h02;
                    16'd92: image_a_prg = 8'h8d; // STA $4014
                    16'd93: image_a_prg = 8'h14;
                    16'd94: image_a_prg = 8'h40;
                    16'd95: image_a_prg = 8'had; // LDA $4016
                    16'd96: image_a_prg = 8'h16;
                    16'd97: image_a_prg = 8'h40;
                    16'd98: image_a_prg = 8'h4c; // JMP $805a
                    16'd99: image_a_prg = 8'h5a;
                    16'd100: image_a_prg = 8'h80;
                    16'h3ffa: image_a_prg = 8'h00;
                    16'h3ffb: image_a_prg = 8'h80;
                    16'h3ffc: image_a_prg = 8'h00;
                    16'h3ffd: image_a_prg = 8'h80;
                    16'h3ffe: image_a_prg = 8'h00;
                    16'h3fff: image_a_prg = 8'h80;
                    default: begin end
                endcase
            end
        end
    endfunction

    function automatic logic [7:0] image_b_prg(input logic [15:0] address);
        begin
            image_b_prg = address[7:0] ^ address[15:8] ^ 8'ha6;
            if (address < 16'd90) begin
                image_b_prg = setup_program_byte(address);
            end else begin
                case (address)
                    16'd90: image_b_prg = 8'ha9; // LDA #$99
                    16'd91: image_b_prg = 8'h99;
                    16'd92: image_b_prg = 8'h85; // STA $03
                    16'd93: image_b_prg = 8'h03;
                    16'd94: image_b_prg = 8'ha9; // LDA #$02
                    16'd95: image_b_prg = 8'h02;
                    16'd96: image_b_prg = 8'h8d; // STA $4014
                    16'd97: image_b_prg = 8'h14;
                    16'd98: image_b_prg = 8'h40;
                    16'd99: image_b_prg = 8'had; // LDA $4016
                    16'd100: image_b_prg = 8'h16;
                    16'd101: image_b_prg = 8'h40;
                    16'd102: image_b_prg = 8'h4c; // JMP $805e
                    16'd103: image_b_prg = 8'h5e;
                    16'd104: image_b_prg = 8'h80;
                    16'h7ffa: image_b_prg = 8'h00;
                    16'h7ffb: image_b_prg = 8'h80;
                    16'h7ffc: image_b_prg = 8'h00;
                    16'h7ffd: image_b_prg = 8'h80;
                    16'h7ffe: image_b_prg = 8'h00;
                    16'h7fff: image_b_prg = 8'h80;
                    default: begin end
                endcase
            end
        end
    endfunction

    task automatic send_command(
        input loader_command_t requested_command,
        input loader_target_t requested_target,
        input logic [15:0] requested_address,
        input logic [7:0] requested_data
    );
        begin
            @(negedge clk);
            command = requested_command;
            command_target = requested_target;
            command_address = requested_address;
            command_data = requested_data;
            command_valid = 1'b1;
            while (!command_ready)
                @(negedge clk);
            @(posedge clk);
            #1;
            assert (command_accepted);
            @(negedge clk);
            command_valid = 1'b0;
            command_target = LOADER_TARGET_NONE;
            command_address = 16'h0000;
            command_data = 8'h00;
        end
    endtask

    task automatic load_image(input logic select_b);
        integer address;
        integer prg_bytes;
        begin
            manifest_prg_bytes = select_b ? 16'h8000 : 16'h4000;
            prg_bytes = select_b ? 32768 : 16384;
            send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE, 0, 0);
            assert (nes_hold_reset);
            for (address = 0; address < prg_bytes; address++)
                send_command(
                    LOADER_COMMAND_WRITE,
                    LOADER_TARGET_PRG,
                    16'(address),
                    select_b ? image_b_prg(16'(address)) :
                               image_a_prg(16'(address))
                );
            send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE, 0, 0);
            #1;
            assert (loader_completed && !loader_error);
            send_command(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE, 0, 0);
            #1;
            assert (activation_accepted && runtime_active);
            while (activation_in_progress)
                @(posedge clk);
            #1;
            assert (!nes_hold_reset && !functional_reset);
        end
    endtask

    always @(posedge clk) begin
        if (!functional_reset) begin
            assert (!(dmc_dma_read_event &&
                     (dma_read_event || dma_write_event)));
            if (dmc_dma_active)
                assert (internal_bus_owner == NES_BUS_MASTER_DMC);
            if (dmc_mem_acknowledge) begin
                dmc_fetches <= dmc_fetches + 1;
                if (image_b_active) begin
                    nrom256_fetches <= nrom256_fetches + 1;
                    assert (dmc_mem_read_data ==
                            image_b_prg(dmc_mem_address - 16'h8000))
                        else $fatal(1, "NROM-256 DMC byte addr=%04x got=%02x expected=%02x",
                                    dmc_mem_address, dmc_mem_read_data,
                                    image_b_prg(dmc_mem_address - 16'h8000));
                end else begin
                    nrom128_fetches <= nrom128_fetches + 1;
                    assert (dmc_mem_read_data ==
                            image_a_prg({2'b00, dmc_mem_address[13:0]}))
                        else $fatal(1, "NROM-128 DMC byte addr=%04x got=%02x expected=%02x",
                                    dmc_mem_address, dmc_mem_read_data,
                                    image_a_prg({2'b00, dmc_mem_address[13:0]}));
                end
            end
            if (dmc_dma_start_event && dma_active)
                dmc_oam_collisions <= dmc_oam_collisions + 1;
            if (dma_read_event)
                oam_reads <= oam_reads + 1;
            if (dma_write_event)
                oam_writes <= oam_writes + 1;
            if (dma_complete_event)
                oam_completions <= oam_completions + 1;
            if (controller_cpu_read)
                controller_reads <= controller_reads + 1;
            if (dmc_dma_cpu_stall)
                assert (!controller_cpu_read && !apu_cpu_read &&
                        !apu_cpu_write && !cart_cpu_write);
            if (apu.pulse1.active && apu.pulse2.active &&
                apu.triangle.active && apu.noise.active && apu.dmc.active)
                all_active_cycles <= all_active_cycles + 1;
            if (pulse1_output != 0 && pulse2_output != 0 &&
                triangle_output != 0 && noise_output != 0 && dmc_output != 0)
                all_nonzero_cycles <= all_nonzero_cycles + 1;
        end
    end

    initial begin : phase5f_system
        integer timeout;
        integer fetches_before_replacement;
        logic [15:0] held_dmc_address;
        logic [11:0] held_bytes_remaining;
        logic [8:0] held_timer;

        $dumpfile("build/sim/nes_dmc_system_phase5f.fst");
        $dumpvars(0, nes_dmc_system_phase5f_tb);

        repeat (6) @(posedge clk);
        reset = 1'b0;
        load_image(1'b0);

        // Pause with an unaccepted request: no scheduler, reader, timer, or
        // address progress occurs merely because the 50 MHz clock continues.
        timeout = 0;
        while ((!dmc_mem_request || dmc_dma_active) && timeout < 100_000) begin
            @(negedge clk);
            timeout++;
        end
        assert (timeout < 100_000);
        debugger_authorized = 1'b0;
        held_dmc_address = dmc_mem_address;
        held_bytes_remaining = apu.dmc.bytes_remaining;
        held_timer = apu.dmc.timer_counter;
        repeat (128) begin
            @(posedge clk);
            pause_cycles++;
            assert (dmc_mem_request && dmc_mem_address == held_dmc_address);
            assert (!dmc_mem_acknowledge && !cpu_cycle_slot);
            assert (apu.dmc.bytes_remaining == held_bytes_remaining &&
                    apu.dmc.timer_counter == held_timer);
        end

        // One debugger-style CPU-time step starts at most one DMA phase and
        // cannot duplicate the request or consume a byte.
        debugger_authorized = 1'b1;
        while (!dmc_dma_active)
            @(posedge clk);
        #1;
        @(negedge clk);
        debugger_authorized = 1'b0;
        repeat (32) @(posedge clk);
        assert (dmc_mem_request && !dmc_mem_acknowledge);
        assert (apu.dmc.bytes_remaining == held_bytes_remaining);
        debugger_authorized = 1'b1;

        // Let CPU, controller reads, OAM DMA, and repeated DMC refills overlap.
        timeout = 0;
        while ((dmc_fetches < 8 || dmc_oam_collisions < 2 ||
                oam_completions < 2 || controller_reads < 2) &&
               timeout < 2_000_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 2_000_000)
            else $fatal(1, "DMC/OAM/runtime interaction timed out fetch=%0d collision=%0d oam=%0d controller=%0d pc=%04x",
                        dmc_fetches, dmc_oam_collisions, oam_completions,
                        controller_reads, cpu_debug_pc);
        assert (oam_reads == oam_writes || oam_reads == oam_writes + 1);
        assert (all_active_cycles > 1_000);
        assert (all_nonzero_cycles > 10);
        assert (nrom128_fetches >= 8);

        // Begin runtime replacement while both bus masters are live. The
        // controlled functional reset cancels the channel request and both
        // DMA engines before image B becomes executable.
        timeout = 0;
        while ((!dma_active || !dmc_mem_request) && timeout < 500_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 500_000);
        fetches_before_replacement = dmc_fetches;
        manifest_prg_bytes = 16'h8000;
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE, 0, 0);
        repeat (2) @(posedge clk);
        #1;
        assert (functional_reset && !dmc_mem_request && !dmc_dma_active &&
                !dma_active && apu.dmc.bytes_remaining == 0);
        assert (apu_channel_enable == 0 && !apu_irq && !frame_irq_flag &&
                frame_sequence_cycle == 0);
        assert (apu.pulse1.length_counter == 0 &&
                apu.pulse2.length_counter == 0 &&
                apu.triangle.length_counter == 0 &&
                apu.noise.length_counter == 0 && apu.noise.lfsr == 15'd1);
        assert (!apu.dmc.mem_request_register && !apu.dmc.irq_flag_register &&
                apu.dmc.sample_buffer_empty && apu.dmc.silence);

        // Finish the already-begun image-B load and activate it.
        for (int address = 0; address < 16'h8000; address++)
            send_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                         16'(address), image_b_prg(16'(address)));
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE, 0, 0);
        send_command(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE, 0, 0);
        while (activation_in_progress)
            @(posedge clk);
        replacement_count++;
        image_b_active = 1'b1;
        timeout = 0;
        while ((nrom256_fetches < 4 ||
                nes.internal_cpu_ram.memory[11'h003] != 8'h99) &&
               timeout < 500_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 500_000);
        assert (nes.internal_cpu_ram.memory[11'h003] == 8'h99);
        assert (nrom256_fetches >= 4 && dmc_fetches > fetches_before_replacement);
        assert (apu.pulse1.active && apu.pulse2.active &&
                apu.triangle.active && apu.noise.active && apu.dmc.active);

        assert (pause_cycles == 128 && replacement_count == 1);
        assert (dmc_fetches >= 8 && dmc_oam_collisions >= 2);
        assert (oam_completions >= 2 && controller_reads >= 2);
        $display("PASS: Phase 5F/5G system all-channel runtime DMC fetches=%0d nrom128=%0d nrom256=%0d collisions=%0d OAM complete=%0d reads=%0d writes=%0d controller=%0d pause=%0d replacement=%0d all-active=%0d all-nonzero=%0d",
                 dmc_fetches, nrom128_fetches, nrom256_fetches,
                 dmc_oam_collisions, oam_completions, oam_reads, oam_writes,
                 controller_reads, pause_cycles, replacement_count,
                 all_active_cycles, all_nonzero_cycles);
        $finish;
    end

    logic unused_status;
    assign unused_status = apu_irq || ^apu_channel_enable ||
                           dmc_dma_complete_event || ^dmc_dma_phase ||
                           ^cpu_address || ppu_enable || cpu_enable ||
                           image_b_active;
endmodule
