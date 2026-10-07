`timescale 1ns/1ps

module nes_phase4c_controller_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] controller1_buttons = 8'ha5;
    logic [7:0] controller2_buttons = 8'h5a;

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
    logic [15:0] apu_cpu_address;
    logic apu_cpu_write;
    logic [15:0] cpu_debug_pc;

    logic controller_strobe;
    logic [7:0] controller1_shift;
    logic [7:0] controller2_shift;
    logic [3:0] controller1_index;
    logic [3:0] controller2_index;
    logic controller_read_4016;
    logic controller_read_4017;
    logic controller_latch_event;

    integer fabric_cycles = 0;
    integer read_4016_count = 0;
    integer read_4017_count = 0;
    integer latch_count = 0;
    integer write_4016_count = 0;

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
        .apu_cpu_write(apu_cpu_write),
        .apu_cpu_read_data(8'h00),
        .dmc_mem_request(1'b0), .dmc_mem_address(16'h0000),
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
        .cpu_debug_pc(cpu_debug_pc)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(clk),
        .reset(reset),
        .controller1_buttons(controller1_buttons),
        .controller2_buttons(controller2_buttons),
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
        .debug_latch_event(controller_latch_event)
    );

    nes_cartridge #(
        .MAPPER_NUMBER (0),
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd0),
        .PRG_INIT_FILE ("build/cartridge/phase4c_controller_nrom128.prg.hex"),
        .CHR_INIT_FILE ("build/cartridge/phase4c_controller_nrom128.chr.hex")
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
        if (!reset) begin
            fabric_cycles <= fabric_cycles + 1;
            if (controller_cpu_write) begin
                write_4016_count <= write_4016_count + 1;
                assert (!controller_port)
                    else $fatal(1, "$4017 write reached controller block");
            end
            if (controller_read_4016)
                read_4016_count <= read_4016_count + 1;
            if (controller_read_4017)
                read_4017_count <= read_4017_count + 1;
            if (controller_latch_event)
                latch_count <= latch_count + 1;
            if (apu_cpu_write && apu_cpu_address == 16'h4017)
                assert (!controller_cpu_write);
        end
    end

    initial begin
        $dumpfile("build/sim/nes_phase4c_controller.fst");
        $dumpvars(0, nes_phase4c_controller_tb);

        repeat (6) @(posedge clk);
        #1;
        assert (!controller_strobe);
        assert (controller1_shift == 8'h00 && controller2_shift == 8'h00);
        assert (controller1_index == 4'd0 && controller2_index == 4'd0);
        assert (controller_cpu_read_data == 8'h00);
        reset = 1'b0;

        while ((nes.internal_cpu_ram.memory[11'h012] < 8'd1 ||
                nes.internal_cpu_ram.memory[11'h010] != 8'ha5 ||
                nes.internal_cpu_ram.memory[11'h011] != 8'h5a) &&
               fabric_cycles < 200000)
            @(posedge clk);
        assert (fabric_cycles < 200000)
            else $fatal(1, "first controller poll timeout PC=%04x RAM=%02x/%02x",
                        cpu_debug_pc,
                        nes.internal_cpu_ram.memory[11'h010],
                        nes.internal_cpu_ram.memory[11'h011]);

        // Change live inputs only after a complete poll. The following poll
        // must latch and serialize the new values rather than stale state.
        controller1_buttons = 8'h3c;
        controller2_buttons = 8'hc3;
        while ((nes.internal_cpu_ram.memory[11'h012] < 8'd3 ||
                nes.internal_cpu_ram.memory[11'h010] != 8'h3c ||
                nes.internal_cpu_ram.memory[11'h011] != 8'hc3) &&
               fabric_cycles < 400000)
            @(posedge clk);

        assert (fabric_cycles < 400000)
            else $fatal(1, "second controller poll timeout PC=%04x RAM=%02x/%02x",
                        cpu_debug_pc,
                        nes.internal_cpu_ram.memory[11'h010],
                        nes.internal_cpu_ram.memory[11'h011]);
        assert (nes.internal_cpu_ram.memory[11'h010] == 8'h3c);
        assert (nes.internal_cpu_ram.memory[11'h011] == 8'hc3);
        assert (nes.internal_cpu_ram.memory[11'h012] >= 8'd3);
        assert (read_4016_count >= 24 && read_4017_count >= 24);
        assert (latch_count >= 3 && write_4016_count >= 6);
        assert (!controller_strobe);

        $display("PASS: Phase 4C integrated cartridge/controller CPU path");
        $display("fabric=%0d polls=%0d reads4016=%0d reads4017=%0d latches=%0d RAM=%02x/%02x pc=%04x",
                 fabric_cycles,
                 nes.internal_cpu_ram.memory[11'h012],
                 read_4016_count, read_4017_count, latch_count,
                 nes.internal_cpu_ram.memory[11'h010],
                 nes.internal_cpu_ram.memory[11'h011], cpu_debug_pc);
        $finish;
    end
endmodule
