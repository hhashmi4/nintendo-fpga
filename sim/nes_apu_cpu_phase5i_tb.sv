`timescale 1ns/1ps

module nes_apu_cpu_phase5i_tb;
    import cpu_pkg::*;
    import nes_apu_pkg::*;
    import nes_runtime_loader_pkg::*;
    import nes_system_pkg::*;

    localparam logic [15:0] IRQ_HANDLER = 16'h9000;
    localparam logic [15:0] NMI_HANDLER = 16'h9200;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic debugger_authorized = 1'b1;
    logic functional_reset;

    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic command_valid = 1'b0;
    logic [15:0] command_address = '0;
    logic [7:0] command_data = '0;
    logic command_ready;
    logic command_accepted;
    logic [15:0] manifest_prg_bytes = LOADER_PRG_NROM128_BYTES;
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
    logic [19:0] mixed_audio;
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
    logic [7:0] cpu_write_data;
    logic cpu_write_enable;
    logic cpu_bus_valid;
    logic [7:0] cpu_debug_sp;
    logic [15:0] cpu_debug_pc;
    logic [7:0] cpu_debug_status;
    logic [5:0] cpu_debug_execution_state;
    logic dma_active;
    logic dma_read_event;
    logic dma_write_event;
    logic dma_complete_event;
    logic dmc_dma_active;
    logic dmc_dma_cpu_stall;
    logic dmc_dma_read_event;
    logic dmc_dma_start_event;
    nes_bus_master_t internal_bus_owner;
    logic ppu_frame_start;
    logic ppu_nmi_event;
    logic ppu_nmi_level;

    logic [7:0] game_a_prg [0:16383];
    logic [7:0] game_b_prg [0:16383];
    logic image_b_active = 1'b0;

    integer fabric_cycles = 0;
    integer cpu_slots = 0;
    integer cpu_instructions = 0;
    integer irq_entries = 0;
    integer nmi_entries = 0;
    integer brk_entries = 0;
    integer rti_completions = 0;
    integer dmc_fetches = 0;
    integer dmc_oam_collisions = 0;
    integer dmc_handler_fetches = 0;
    integer oam_completions = 0;
    integer controller_reads = 0;
    integer apu_writes = 0;
    integer status_reads = 0;
    integer audio_samples = 0;
    integer audio_nonzero_samples = 0;
    integer all_active_samples = 0;
    integer all_nonzero_samples = 0;
    integer pause_cycles = 0;
    integer step_slots = 0;
    integer frame_step_slots = 0;
    integer source_clear_checks = 0;
    integer stack_checks = 0;
    integer mismatches = 0;

    logic previous_apu_write = 1'b0;
    logic [7:0] pushed_pc_high;
    logic [7:0] pushed_pc_low;
    logic [7:0] pushed_stack_address;
    logic replacement_reset_seen = 1'b0;

    assign functional_reset = reset || nes_hold_reset;

    /* verilator lint_off PINMISSING */
    nes_core nes (
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
        .cpu_write_data(cpu_write_data),
        .cpu_write_enable(cpu_write_enable),
        .cpu_bus_valid(cpu_bus_valid),
        .cpu_debug_sp(cpu_debug_sp),
        .cpu_debug_pc(cpu_debug_pc),
        .cpu_debug_status(cpu_debug_status),
        .cpu_debug_execution_state(cpu_debug_execution_state),
        .dma_active(dma_active),
        .dma_read_event(dma_read_event),
        .dma_write_event(dma_write_event),
        .dma_complete_event(dma_complete_event),
        .internal_bus_owner(internal_bus_owner),
        .dmc_dma_active(dmc_dma_active),
        .dmc_dma_cpu_stall(dmc_dma_cpu_stall),
        .dmc_dma_read_event(dmc_dma_read_event),
        .dmc_dma_start_event(dmc_dma_start_event),
        .ppu_frame_start(ppu_frame_start),
        .ppu_nmi_level(ppu_nmi_level),
        .ppu_nmi_event(ppu_nmi_event)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off PINMISSING */
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
    /* verilator lint_on PINMISSING */
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
    /* verilator lint_off PINMISSING */
    nes_runtime_cartridge #(
        .IMAGE_VALIDATION_ENABLE(1'b1),
        .ACTIVATION_ENABLE(1'b1),
        .ACTIVATION_RESET_CYCLES(4)
    ) cartridge (
        .clk(clk),
        .reset(reset),
        .command_valid(command_valid),
        .command(command),
        .command_target(command_target),
        .command_address(command_address),
        .command_data(command_data),
        .command_ready(command_ready),
        .command_accepted(command_accepted),
        .manifest_valid(1'b1),
        .manifest_mapper(8'd0),
        .manifest_prg_bytes(manifest_prg_bytes),
        .manifest_chr_bytes(16'h0000),
        .manifest_chr_is_ram(1'b1),
        .manifest_mirroring(LOADER_MIRROR_HORIZONTAL),
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
        .loader_completed(loader_completed),
        .loader_error(loader_error),
        .nes_hold_reset(nes_hold_reset),
        .activation_accepted(activation_accepted),
        .activation_in_progress(activation_in_progress),
        .runtime_active(runtime_active)
    );
    /* verilator lint_on PINMISSING */
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk <= !clk;

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
            command_address = '0;
            command_data = '0;
        end
    endtask

    task automatic begin_image;
        begin
            send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE, 0, 0);
            assert (nes_hold_reset);
        end
    endtask

    task automatic finish_image(input logic select_b);
        integer address;
        begin
            for (address = 0; address < 16384; address++)
                send_command(
                    LOADER_COMMAND_WRITE,
                    LOADER_TARGET_PRG,
                    16'(address),
                    select_b ? game_b_prg[address] : game_a_prg[address]
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

    task automatic wait_ram(
        input logic [10:0] address,
        input logic [7:0] value,
        input integer limit
    );
        integer timeout;
        begin
            timeout = 0;
            while (nes.internal_cpu_ram.memory[address] != value &&
                   timeout < limit) begin
                @(posedge clk);
                timeout++;
            end
            assert (timeout < limit)
                else $fatal(1, "RAM wait timed out addr=%03x wanted=%02x got=%02x pc=%04x stage=%02x",
                            address, value,
                            nes.internal_cpu_ram.memory[address], cpu_debug_pc,
                            nes.internal_cpu_ram.memory[11'h030]);
        end
    endtask

    task automatic open_gate(input logic [10:0] address);
        begin
            @(negedge clk);
            nes.internal_cpu_ram.memory[address] = 8'h01;
        end
    endtask

    task automatic pause_and_single_step;
        logic [15:0] held_pc;
        logic [7:0] held_sp;
        logic [5:0] held_state;
        logic [15:0] held_frame_cycle;
        logic [15:0] held_dmc_address;
        logic [11:0] held_dmc_remaining;
        integer slots_before;
        begin
            @(negedge clk);
            debugger_authorized = 1'b0;
            held_pc = cpu_debug_pc;
            held_sp = cpu_debug_sp;
            held_state = cpu_debug_execution_state;
            held_frame_cycle = frame_sequence_cycle;
            held_dmc_address = dmc_mem_address;
            held_dmc_remaining = apu.dmc.bytes_remaining;
            repeat (128) begin
                @(posedge clk);
                #1;
                pause_cycles++;
                assert (!cpu_cycle_slot && cpu_debug_pc == held_pc &&
                        cpu_debug_sp == held_sp &&
                        cpu_debug_execution_state == held_state);
                assert (frame_sequence_cycle == held_frame_cycle &&
                        dmc_mem_address == held_dmc_address &&
                        apu.dmc.bytes_remaining == held_dmc_remaining);
            end

            slots_before = cpu_slots;
            @(negedge clk);
            debugger_authorized = 1'b1;
            do @(posedge clk); while (!cpu_cycle_slot);
            #1;
            @(negedge clk);
            debugger_authorized = 1'b0;
            assert (cpu_slots == slots_before + 1);
            step_slots++;
            repeat (16) begin
                @(posedge clk);
                #1;
                assert (!cpu_cycle_slot);
            end
            @(negedge clk);
            debugger_authorized = 1'b1;
        end
    endtask

    task automatic run_one_frame_step;
        integer slots_before;
        begin
            slots_before = cpu_slots;
            while (!ppu_frame_start)
                @(posedge clk);
            #1;
            @(negedge clk);
            debugger_authorized = 1'b0;
            frame_step_slots += cpu_slots - slots_before;
            assert (frame_step_slots > 1000);
            repeat (16) begin
                @(posedge clk);
                #1;
                assert (!cpu_cycle_slot);
            end
            @(negedge clk);
            debugger_authorized = 1'b1;
        end
    endtask

    always @(posedge clk) begin : integration_monitor
        if (reset) begin
            previous_apu_write <= 1'b0;
        end else begin
            fabric_cycles++;
            if (cpu_cycle_slot)
                cpu_slots++;
            if (cpu_enable && cpu_bus_valid &&
                cpu_debug_execution_state == CPU_STATE_FETCH)
                cpu_instructions++;

            assert (!apu_cpu_write ||
                    (cpu_enable && cpu_bus_valid && cpu_write_enable));
            assert (!apu_cpu_read ||
                    (cpu_enable && cpu_bus_valid && !cpu_write_enable));
            assert (!(apu_cpu_write && previous_apu_write))
                else $fatal(1, "APU write stretched across fabric cycles");
            previous_apu_write <= apu_cpu_write;

            if (apu_cpu_write) begin
                apu_writes++;
                assert (!dma_active && !dmc_dma_cpu_stall);
                assert ((apu_cpu_address >= 16'h4000 &&
                         apu_cpu_address <= 16'h4013) ||
                        apu_cpu_address == 16'h4015 ||
                        apu_cpu_address == 16'h4017);
            end
            if (apu_cpu_read && apu_cpu_address == 16'h4015)
                status_reads++;
            if (controller_cpu_read) begin
                controller_reads++;
                assert (!dmc_dma_cpu_stall);
            end
            if (dmc_dma_cpu_stall)
                assert (!apu_cpu_read && !apu_cpu_write &&
                        !controller_cpu_read && !cart_cpu_write);
            if (dmc_dma_active)
                assert (internal_bus_owner == NES_BUS_MASTER_DMC);
            assert (!(dmc_dma_read_event &&
                     (dma_read_event || dma_write_event)));

            if (dmc_mem_acknowledge) begin
                dmc_fetches++;
                assert (dmc_mem_read_data ==
                        (image_b_active ? game_b_prg[dmc_mem_address[13:0]] :
                                          game_a_prg[dmc_mem_address[13:0]]));
                if (dma_active)
                    dmc_oam_collisions++;
                if (cpu_debug_pc >= IRQ_HANDLER &&
                    cpu_debug_pc < NMI_HANDLER)
                    dmc_handler_fetches++;
            end
            if (dmc_dma_start_event && dma_active)
                dmc_oam_collisions++;
            if (dma_complete_event)
                oam_completions++;

            if (cpu_enable &&
                cpu_debug_execution_state == CPU_STATE_INTERRUPT_PUSH_HIGH) begin
                pushed_pc_high = cpu_write_data;
                pushed_stack_address = cpu_address[7:0];
                assert (cpu_address[15:8] == 8'h01 && cpu_write_enable);
            end
            if (cpu_enable &&
                cpu_debug_execution_state == CPU_STATE_INTERRUPT_PUSH_LOW) begin
                pushed_pc_low = cpu_write_data;
                assert (cpu_address ==
                        {8'h01, pushed_stack_address - 8'd1});
            end
            if (cpu_enable &&
                cpu_debug_execution_state == CPU_STATE_INTERRUPT_PUSH_STATUS) begin
                assert (cpu_address ==
                        {8'h01, pushed_stack_address - 8'd2});
                assert (cpu_write_data[5]);
                assert (cpu_write_data[4] ==
                        (nes.cpu.interrupt_source == CPU_INTERRUPT_BRK));
                assert ({pushed_pc_high, pushed_pc_low} ==
                        nes.cpu.return_address);
                stack_checks++;
            end
            if (cpu_enable &&
                cpu_debug_execution_state == CPU_STATE_INTERRUPT_VECTOR_LOW) begin
                case (nes.cpu.interrupt_source)
                    CPU_INTERRUPT_IRQ: begin
                        assert (cpu_address == 16'hFFFE);
                        irq_entries++;
                    end
                    CPU_INTERRUPT_NMI: begin
                        assert (cpu_address == 16'hFFFA);
                        nmi_entries++;
                    end
                    CPU_INTERRUPT_BRK: begin
                        assert (cpu_address == 16'hFFFE);
                        brk_entries++;
                    end
                    default: $fatal(1, "unexpected interrupt source");
                endcase
            end
            if (cpu_enable &&
                cpu_debug_execution_state == CPU_STATE_RTI_PULL_HIGH)
                rti_completions++;

            if (!functional_reset) begin
                audio_samples++;
                if (mixed_audio != 0)
                    audio_nonzero_samples++;
                if (apu.pulse1.active && apu.pulse2.active &&
                    apu.triangle.active && apu.noise.active && apu.dmc.active)
                    all_active_samples++;
                if (pulse1_output != 0 && pulse2_output != 0 &&
                    triangle_output != 0 && noise_output != 0 &&
                    dmc_output != 0)
                    all_nonzero_samples++;
            end

            if (nes_hold_reset) begin
                assert (!apu_irq && !frame_irq_flag && !dmc_mem_request &&
                        !dma_active && !dmc_dma_active);
                if (irq_entries != 0)
                    replacement_reset_seen <= 1'b1;
            end
        end
    end

    // Check the two acknowledgement orders after the sequential APU edge.
    always @(posedge clk) begin : source_clear_monitor
        if (!functional_reset && apu_cpu_read &&
            apu_cpu_address == 16'h4015 &&
            nes.internal_cpu_ram.memory[11'h030] == 8'h03) begin
            #1;
            assert (!frame_irq_flag && apu.dmc.irq_flag_register && apu_irq);
            source_clear_checks++;
        end
        if (!functional_reset && apu_cpu_write &&
            apu_cpu_address == 16'h4015 &&
            nes.internal_cpu_ram.memory[11'h030] == 8'h04) begin
            #1;
            assert (frame_irq_flag && !apu.dmc.irq_flag_register && apu_irq);
            source_clear_checks++;
        end
    end

    initial begin : phase5i_system
        integer timeout;
        integer irq_before_nmi;

        $readmemh("build/sim/phase5i_game_a.prg.hex", game_a_prg);
        $readmemh("build/sim/phase5i_game_b.prg.hex", game_b_prg);
        $dumpfile("build/sim/nes_apu_cpu_phase5i.fst");
        $dumpvars(0, nes_apu_cpu_phase5i_tb);

        repeat (6) @(posedge clk);
        reset = 1'b0;
        begin_image();
        finish_image(1'b0);

        wait_ram(11'h000, 8'h5A, 200_000);
        wait_ram(11'h011, 8'hD1, 500_000);
        wait_ram(11'h012, 8'hD2, 100_000);
        assert (nes.internal_cpu_ram.memory[11'h010][7]);
        assert (!nes.internal_cpu_ram.memory[11'h03E][4]);

        // Frame IRQ is pending and masked.  Pause with a held DMC request,
        // single-step one CPU slot, frame-step, pause inside the handler, and
        // resume without replaying any APU or DMA transaction.
        timeout = 0;
        while ((nes.internal_cpu_ram.memory[11'h030] != 8'h02 ||
                !frame_irq_flag || !dmc_mem_request || dmc_dma_active) &&
               timeout < 600_000) begin
            @(negedge clk);
            timeout++;
        end
        assert (timeout < 600_000);
        assert (apu_irq && cpu_debug_status[2]);
        pause_and_single_step();
        run_one_frame_step();
        open_gate(11'h070);
        timeout = 0;
        while (!(cpu_debug_pc >= IRQ_HANDLER &&
                 cpu_debug_pc < NMI_HANDLER) && timeout < 100_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 100_000);
        pause_and_single_step();
        wait_ram(11'h015, 8'hF1, 200_000);
        wait_ram(11'h016, 8'hF2, 200_000);
        assert (nes.internal_cpu_ram.memory[11'h014][6]);
        assert (!nes.internal_cpu_ram.memory[11'h014][7]);

        timeout = 0;
        while (!(nes.internal_cpu_ram.memory[11'h030] == 8'h03 &&
                 frame_irq_flag && apu.dmc.irq_flag_register) &&
               timeout < 600_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 600_000 && apu_irq && cpu_debug_status[2]);
        open_gate(11'h071);
        wait_ram(11'h018, 8'hB1, 200_000);
        wait_ram(11'h019, 8'hB2, 200_000);
        assert ((nes.internal_cpu_ram.memory[11'h017] & 8'hC0) == 8'hC0);

        timeout = 0;
        while (!(nes.internal_cpu_ram.memory[11'h030] == 8'h04 &&
                 frame_irq_flag && apu.dmc.irq_flag_register) &&
               timeout < 600_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 600_000 && apu_irq && cpu_debug_status[2]);
        open_gate(11'h072);
        wait_ram(11'h01B, 8'hC1, 200_000);
        wait_ram(11'h01C, 8'hC2, 200_000);
        assert ((nes.internal_cpu_ram.memory[11'h01A] & 8'hC0) == 8'h40);

        // Present an actual PPU NMI while APU IRQ is already level-high.
        timeout = 0;
        while (!(nes.internal_cpu_ram.memory[11'h030] == 8'h05 &&
                 frame_irq_flag) && timeout < 600_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 600_000 && apu_irq && cpu_debug_status[2]);
        irq_before_nmi = irq_entries;
        open_gate(11'h073);
        wait_ram(11'h01D, 8'hA1, 400_000);
        assert (nmi_entries >= 1 && irq_entries == irq_before_nmi);
        assert (apu_irq);
        wait_ram(11'h020, 8'hA4, 200_000);
        assert (nes.internal_cpu_ram.memory[11'h01E] == 8'hA2);
        assert (nes.internal_cpu_ram.memory[11'h01F] == 8'hA3);

        wait_ram(11'h021, 8'hB1, 200_000);
        wait_ram(11'h023, 8'hB2, 200_000);
        assert (nes.internal_cpu_ram.memory[11'h022][5:4] == 2'b11);

        timeout = 0;
        while (!(nes.internal_cpu_ram.memory[11'h030] == 8'h07 &&
                 frame_irq_flag) && timeout < 600_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 600_000 && cpu_debug_status[2]);
        open_gate(11'h074);
        wait_ram(11'h025, 8'hE1, 200_000);
        wait_ram(11'h026, 8'hE2, 200_000);
        assert (nes.internal_cpu_ram.memory[11'h024] == 8'h02);

        // Replace the running game only when DMC IRQ and OAM DMA are live.
        timeout = 0;
        while ((!apu.dmc.irq_flag_register || !dma_active) &&
               timeout < 300_000) begin
            @(posedge clk);
            timeout++;
        end
        assert (timeout < 300_000 && apu_irq);
        begin_image();
        repeat (2) @(posedge clk);
        #1;
        assert (functional_reset && !apu_irq && !frame_irq_flag &&
                !dmc_mem_request && !dmc_dma_active && !dma_active);
        assert (apu_channel_enable == 0 && apu.dmc.bytes_remaining == 0);
        image_b_active = 1'b1;
        finish_image(1'b1);
        wait_ram(11'h02F, 8'h99, 200_000);
        assert (!apu_irq && !dmc_mem_request && !dma_active &&
                !dmc_dma_active && apu_channel_enable == 0);

        assert (irq_entries == 7)
            else $fatal(1, "unexpected hardware IRQ count %0d", irq_entries);
        assert (nmi_entries == 1 && brk_entries == 1)
            else $fatal(1, "unexpected NMI/BRK counts nmi=%0d brk=%0d",
                        nmi_entries, brk_entries);
        assert (rti_completions == irq_entries + nmi_entries + brk_entries)
            else $fatal(1, "RTI count mismatch rti=%0d entries=%0d",
                        rti_completions,
                        irq_entries + nmi_entries + brk_entries);
        assert (stack_checks == irq_entries + nmi_entries + brk_entries)
            else $fatal(1, "stack count mismatch stack=%0d entries=%0d",
                        stack_checks,
                        irq_entries + nmi_entries + brk_entries);
        assert (source_clear_checks == 2)
            else $fatal(1, "source clear checks=%0d", source_clear_checks);
        assert (dmc_fetches >= 8 && dmc_oam_collisions >= 1)
            else $fatal(1, "DMC coverage fetches=%0d collisions=%0d",
                        dmc_fetches, dmc_oam_collisions);
        assert (oam_completions >= 1 && controller_reads >= 2)
            else $fatal(1, "OAM/controller coverage oam=%0d controller=%0d",
                        oam_completions, controller_reads);
        assert (apu_writes >= 50 && status_reads >= 6)
            else $fatal(1, "APU bus coverage writes=%0d reads=%0d",
                        apu_writes, status_reads);
        assert (all_active_samples > 100 && all_nonzero_samples > 0)
            else $fatal(1, "channel coverage active=%0d nonzero=%0d",
                        all_active_samples, all_nonzero_samples);
        assert (audio_samples > 100_000 && audio_nonzero_samples > 100)
            else $fatal(1, "audio coverage samples=%0d nonzero=%0d",
                        audio_samples, audio_nonzero_samples);
        assert (pause_cycles == 256 && step_slots == 2 &&
                frame_step_slots > 1000 && replacement_reset_seen);
        assert (mismatches == 0);

        $display("PASS: Phase 5I CPU/APU system cycles=%0d cpu_slots=%0d instructions=%0d IRQ=%0d NMI=%0d BRK=%0d RTI=%0d DMC_fetches=%0d DMC_OAM=%0d DMC_handler=%0d OAM=%0d controller=%0d APU_writes=%0d status_reads=%0d audio_samples=%0d all_active=%0d all_nonzero=%0d pause=%0d step=%0d frame_step_slots=%0d mismatches=%0d",
                 fabric_cycles, cpu_slots, cpu_instructions, irq_entries,
                 nmi_entries, brk_entries, rti_completions, dmc_fetches,
                 dmc_oam_collisions, dmc_handler_fetches, oam_completions,
                 controller_reads, apu_writes, status_reads, audio_samples,
                 all_active_samples, all_nonzero_samples, pause_cycles,
                 step_slots, frame_step_slots, mismatches);
        $finish;
    end
endmodule
