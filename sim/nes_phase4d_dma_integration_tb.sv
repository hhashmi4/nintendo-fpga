`timescale 1ns/1ps

module nes_phase4d_dma_integration_tb;
    import nes_system_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [1:0] cartridge_mirroring;
    logic [15:0] cart_cpu_address;
    logic cart_cpu_read;
    logic cart_cpu_write;
    logic [7:0] cart_cpu_write_data;
    logic [7:0] cart_cpu_read_data;
    logic [15:0] apu_cpu_address;
    logic apu_cpu_read;
    logic apu_cpu_write;
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
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic cpu_write_enable;
    logic cpu_bus_valid;
    logic [7:0] cpu_debug_a;
    logic [7:0] cpu_debug_x;
    logic [7:0] cpu_debug_y;
    logic [7:0] cpu_debug_sp;
    logic [15:0] cpu_debug_pc;
    logic [7:0] cpu_debug_status;
    logic dma_active;
    logic [2:0] dma_phase;
    logic [7:0] dma_page;
    logic [7:0] dma_index;
    logic [7:0] dma_data;
    logic [9:0] dma_stall_cycles;
    logic [8:0] dma_read_count;
    logic [8:0] dma_write_count;
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

    logic controller_strobe;
    logic [7:0] controller1_shift;
    logic [7:0] controller2_shift;
    logic [3:0] controller1_index;
    logic [3:0] controller2_index;
    logic controller_read_4016;
    logic controller_read_4017;

    logic previous_dma_active = 1'b0;
    logic [7:0] held_a;
    logic [7:0] held_x;
    logic [7:0] held_y;
    logic [7:0] held_sp;
    logic [15:0] held_pc;
    logic [7:0] held_status;
    logic [15:0] held_address;
    logic held_write_enable;
    logic held_bus_valid;
    integer fabric_cycles = 0;
    integer starts = 0;
    integer completions = 0;
    integer total_reads = 0;
    integer total_writes = 0;
    integer cartridge_dma_reads = 0;
    integer stall_lengths [0:2];

    always #5 clk <= !clk;

    /* verilator lint_off PINMISSING */
    nes_core nes (
        .clk(clk),
        .reset(reset),
        .nes_enable(1'b1),
        .irq(1'b0),
        .mirroring_mode(cartridge_mirroring),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_address(apu_cpu_address),
        .apu_cpu_read(apu_cpu_read),
        .apu_cpu_write(apu_cpu_write),
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
        .cpu_enable(cpu_enable),
        .cpu_address(cpu_address),
        .cpu_write_enable(cpu_write_enable),
        .cpu_bus_valid(cpu_bus_valid),
        .cpu_debug_a(cpu_debug_a),
        .cpu_debug_x(cpu_debug_x),
        .cpu_debug_y(cpu_debug_y),
        .cpu_debug_sp(cpu_debug_sp),
        .cpu_debug_pc(cpu_debug_pc),
        .cpu_debug_status(cpu_debug_status),
        .dma_active(dma_active),
        .dma_phase(dma_phase),
        .dma_page(dma_page),
        .dma_index(dma_index),
        .dma_data(dma_data),
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
        .internal_bus_owner(internal_bus_owner)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(clk),
        .reset(reset),
        .controller1_buttons(8'ha5),
        .controller2_buttons(8'h5a),
        .cpu_port(controller_port),
        .cpu_read(controller_cpu_read),
        .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data),
        .debug_strobe(controller_strobe),
        .debug_live_controller1(),
        .debug_live_controller2(),
        .debug_shift_controller1(controller1_shift),
        .debug_shift_controller2(controller2_shift),
        .debug_index_controller1(controller1_index),
        .debug_index_controller2(controller2_index),
        .debug_serial_controller1(),
        .debug_serial_controller2(),
        .debug_read_4016(controller_read_4016),
        .debug_read_4017(controller_read_4017),
        .debug_latch_event()
    );

    nes_cartridge #(
        .MAPPER_NUMBER (0),
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd0),
        .PRG_INIT_FILE ("build/cartridge/phase4d_dma_nrom128.prg.hex"),
        .CHR_INIT_FILE ("build/cartridge/phase4d_dma_nrom128.chr.hex")
    ) cartridge (
        .clk(clk), .reset(reset),
        .cpu_address(cart_cpu_address), .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write), .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .cartridge_present(), .mapper_number(), .nrom_256(),
        .chr_is_ram(), .mirroring_mode(cartridge_mirroring),
        .debug_prg_address(), .debug_prg_data(),
        .debug_chr_address(), .debug_chr_data(),
        .debug_prg_read(), .debug_prg_write(),
        .debug_prg_ram_read(), .debug_prg_ram_write(),
        .debug_chr_read(), .debug_chr_write()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always @(posedge clk) begin
        if (reset) begin
            previous_dma_active <= 1'b0;
        end else begin
            fabric_cycles <= fabric_cycles + 1;
            assert (internal_bus_owner ==
                    (dma_active ? NES_BUS_MASTER_DMA : NES_BUS_MASTER_CPU));
            assert (dma_cpu_stall == dma_active);
            assert (dma_dummy_cycle ==
                    (dma_active && dma_phase == NES_DMA_DUMMY));
            assert (dma_alignment_cycle ==
                    (dma_active && dma_phase == NES_DMA_ALIGN));
            assert (apu_cpu_address == cpu_address);

            if (dma_start_event) begin
                starts <= starts + 1;
                if (starts == 1)
                    assert (nes.internal_cpu_ram.memory[11'h013] == 8'h11);
                if (starts == 2)
                    assert (nes.internal_cpu_ram.memory[11'h013] == 8'h22);
            end

            if (dma_active && !previous_dma_active) begin
                held_a <= cpu_debug_a;
                held_x <= cpu_debug_x;
                held_y <= cpu_debug_y;
                held_sp <= cpu_debug_sp;
                held_pc <= cpu_debug_pc;
                held_status <= cpu_debug_status;
                held_address <= cpu_address;
                held_write_enable <= cpu_write_enable;
                held_bus_valid <= cpu_bus_valid;
            end else if (dma_active) begin
                assert (!cpu_enable);
                assert (cpu_debug_a == held_a && cpu_debug_x == held_x &&
                        cpu_debug_y == held_y && cpu_debug_sp == held_sp &&
                        cpu_debug_pc == held_pc &&
                        cpu_debug_status == held_status);
                assert (cpu_address == held_address);
                assert (cpu_write_enable == held_write_enable &&
                        cpu_bus_valid == held_bus_valid);
                assert (!(controller_cpu_read || controller_cpu_write ||
                          controller_read_4016 || controller_read_4017));
                assert (!(apu_cpu_read || apu_cpu_write));
            end

            if (dma_read_event) begin
                total_reads <= total_reads + 1;
                assert (dma_index == dma_read_count[7:0]);
                assert (dma_source_address == {dma_page, dma_index});
                if (dma_page == 8'h02)
                    assert (dma_source_data ==
                            (dma_read_count[7:0] ^ 8'h5a));
                if (dma_page == 8'h80)
                    assert (dma_source_target == NES_CPU_TARGET_CARTRIDGE);
                if (dma_page == 8'h40 && dma_source_address < 16'h4020) begin
                    assert (dma_source_data == 8'h00);
                    assert (dma_source_target != NES_CPU_TARGET_CARTRIDGE);
                end
            end
            if (dma_write_event)
                total_writes <= total_writes + 1;
            if (dma_write_event && dma_page == 8'h02)
                assert (dma_data == (dma_index ^ 8'h5a));

            if (dma_active && cart_cpu_read) begin
                cartridge_dma_reads <= cartridge_dma_reads + 1;
                assert (dma_read_event &&
                        dma_source_target == NES_CPU_TARGET_CARTRIDGE);
                assert (cart_cpu_address == dma_source_address);
            end

            if (dma_complete_event) begin
                stall_lengths[completions] <= {22'd0, dma_stall_cycles};
                assert (dma_read_count == 9'd256 &&
                        dma_write_count == 9'd256);
                assert (dma_stall_cycles ==
                        (dma_started_odd ? 10'd514 : 10'd513));
                if (dma_page == 8'h02) begin
                    for (int index = 0; index < 256; index++)
                        assert (nes.ppu.oam.primary_oam[index] ==
                                (index[7:0] ^ 8'h5a));
                end else if (dma_page == 8'h80) begin
                    for (int index = 0; index < 256; index++)
                        assert (nes.ppu.oam.primary_oam[index] ==
                                cartridge.mapper0_selected.mapper
                                    .prg_rom[index]);
                end else if (dma_page == 8'h40) begin
                    for (int index = 0; index < 256; index++)
                        assert (nes.ppu.oam.primary_oam[index] == 8'h00);
                end else begin
                    $fatal(1, "unexpected DMA page %02x", dma_page);
                end
                completions <= completions + 1;
            end

            previous_dma_active <= dma_active;
        end
    end

    initial begin
        $dumpfile("build/sim/nes_phase4d_dma_integration.fst");
        $dumpvars(0, nes_phase4d_dma_integration_tb);

        repeat (6) @(posedge clk);
        #1;
        assert (internal_bus_owner == NES_BUS_MASTER_NONE);
        assert (!dma_active && !dma_cpu_stall && !dma_start_event &&
                !dma_read_event && !dma_write_event && !dma_complete_event);
        reset = 1'b0;

        while ((completions < 3 ||
                nes.internal_cpu_ram.memory[11'h013] != 8'h33) &&
               fabric_cycles < 200000)
            @(posedge clk);
        repeat (20) @(posedge clk);

        assert (fabric_cycles < 200000)
            else $fatal(1, "integrated DMA timeout pc=%04x page=%02x phase=%0d",
                        cpu_debug_pc, dma_page, dma_phase);
        assert (starts == 3 && completions == 3);
        assert (total_reads == 3 * 256 && total_writes == 3 * 256);
        assert ((stall_lengths[0] == 513 && stall_lengths[1] == 514) ||
                (stall_lengths[0] == 514 && stall_lengths[1] == 513));
        assert (cartridge_dma_reads == 256 + 224);
        assert (!controller_strobe);
        assert (controller1_shift == 8'h00 && controller2_shift == 8'h00);
        assert (controller1_index == 4'd0 && controller2_index == 4'd0);
        assert (nes.internal_cpu_ram.memory[11'h013] == 8'h33);
        assert (!dma_active && internal_bus_owner == NES_BUS_MASTER_CPU);

        $display("PASS: Phase 4D-A integrated CPU -> $4014 -> DMA bus master -> OAM -> CPU resume");
        $display("fabric=%0d starts=%0d completions=%0d reads=%0d writes=%0d stalls=%0d/%0d/%0d cart_dma_reads=%0d marker=%02x pc=%04x",
                 fabric_cycles, starts, completions, total_reads, total_writes,
                 stall_lengths[0], stall_lengths[1], stall_lengths[2],
                 cartridge_dma_reads,
                 nes.internal_cpu_ram.memory[11'h013], cpu_debug_pc);
        $finish;
    end
endmodule
