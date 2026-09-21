`timescale 1ns/1ps

module nes_phase4b_boot_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
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
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic cpu_bus_valid;
    logic [15:0] cpu_debug_pc;
    logic [7:0] ppu_ctrl;
    logic [7:0] ppu_mask;
    logic cartridge_present;
    logic [7:0] mapper_number;
    logic nrom_256;
    logic chr_is_ram;
    logic [14:0] debug_prg_address;
    logic [7:0] debug_prg_data;
    logic [12:0] debug_chr_address;
    logic [7:0] debug_chr_data;

    integer fabric_cycles = 0;
    integer cpu_accesses = 0;
    integer cartridge_reads = 0;
    integer chr_reads = 0;
    integer nonzero_chr_reads = 0;
    integer reset_vector_low_reads = 0;
    integer reset_vector_high_reads = 0;
    logic saw_reset_pc = 1'b0;

    /* verilator lint_off PINMISSING */
    nes_core dut (
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
        .apu_cpu_read_data(8'h00),
        .controller_cpu_read_data(8'h00),
        .chr_addr(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .cpu_enable(cpu_enable),
        .cpu_address(cpu_address),
        .cpu_bus_valid(cpu_bus_valid),
        .cpu_debug_pc(cpu_debug_pc),
        .ppu_ctrl(ppu_ctrl),
        .ppu_mask(ppu_mask)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_cartridge #(
        .MAPPER_NUMBER (0),
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd1),
        .PRG_INIT_FILE ("build/cartridge/phase4b_boot_nrom128.prg.hex"),
        .CHR_INIT_FILE ("build/cartridge/phase4b_boot_nrom128.chr.hex")
    ) cartridge (
        .clk(clk), .reset(reset),
        .cpu_address(cart_cpu_address), .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write), .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .cartridge_present(cartridge_present),
        .mapper_number(mapper_number), .nrom_256(nrom_256),
        .chr_is_ram(chr_is_ram), .mirroring_mode(cartridge_mirroring),
        .debug_prg_address(debug_prg_address),
        .debug_prg_data(debug_prg_data),
        .debug_chr_address(debug_chr_address),
        .debug_chr_data(debug_chr_data),
        .debug_prg_read(), .debug_prg_write(),
        .debug_prg_ram_read(), .debug_prg_ram_write(),
        .debug_chr_read(), .debug_chr_write()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk <= ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            fabric_cycles <= fabric_cycles + 1;
            if (cpu_enable && cpu_bus_valid) begin
                cpu_accesses <= cpu_accesses + 1;
                assert (cpu_address == cart_cpu_address);
            end
            if (cpu_debug_pc == 16'h8000)
                saw_reset_pc <= 1'b1;
            if (cart_cpu_read) begin
                cartridge_reads <= cartridge_reads + 1;
                if (cart_cpu_address >= 16'h8000)
                    assert (debug_prg_address ==
                            {1'b0, cart_cpu_address[13:0]});
                if (cart_cpu_address == 16'hfffc) begin
                    reset_vector_low_reads <= reset_vector_low_reads + 1;
                    assert (cart_cpu_read_data == 8'h00)
                        else $fatal(1, "reset vector low was %02x",
                                    cart_cpu_read_data);
                end
                if (cart_cpu_address == 16'hfffd) begin
                    reset_vector_high_reads <= reset_vector_high_reads + 1;
                    assert (cart_cpu_read_data == 8'h80)
                        else $fatal(1, "reset vector high was %02x",
                                    cart_cpu_read_data);
                end
            end
            if (chr_read) begin
                chr_reads <= chr_reads + 1;
                assert (debug_chr_address == chr_address);
                assert (debug_chr_data == chr_read_data);
                if (chr_read_data != 8'h00)
                    nonzero_chr_reads <= nonzero_chr_reads + 1;
            end
        end
    end

    initial begin
        $dumpfile("build/sim/nes_phase4b_boot.fst");
        $dumpvars(0, nes_phase4b_boot_tb);

        repeat (6) @(posedge clk);
        assert (cart_cpu_read_data == 8'h00 && chr_read_data == 8'h00);
        reset = 1'b0;

        while ((dut.internal_cpu_ram.memory[11'h002] != 8'h4b ||
                dut.internal_cpu_ram.memory[11'h003] != 8'h5a ||
                ppu_ctrl != 8'h80 || ppu_mask != 8'h1e ||
                nonzero_chr_reads == 0) && fabric_cycles < 200000)
            @(posedge clk);
        repeat (20) @(posedge clk);

        assert (fabric_cycles < 200000)
            else $fatal(1, "cartridge boot timeout PC=%04x", cpu_debug_pc);
        assert (cartridge_present && mapper_number == 8'h00);
        assert (!nrom_256 && !chr_is_ram && cartridge_mirroring == 2'd1);
        assert (reset_vector_low_reads > 0 && reset_vector_high_reads > 0)
            else $fatal(1, "CPU did not fetch reset vector through cartridge");
        assert (saw_reset_pc)
            else $fatal(1, "CPU never constructed cartridge reset PC $8000");
        assert (dut.internal_cpu_ram.memory[11'h002] == 8'h4b);
        assert (dut.internal_cpu_ram.memory[11'h003] == 8'h5a);
        assert (ppu_ctrl == 8'h80 && ppu_mask == 8'h1e);
        assert (dut.ppu.background_core.memory.palette_ram[5'h00] == 8'h0f);
        assert (dut.ppu.background_core.memory.palette_ram[5'h01] == 8'h21);
        assert (chr_reads > 0 && nonzero_chr_reads > 0)
            else $fatal(1, "PPU did not consume nonzero cartridge CHR data");
        assert (debug_prg_data == cart_cpu_read_data);
        assert (cpu_accesses > 0);

        $display("PASS: Phase 4B integrated cartridge reset boot and CHR path");
        $display("fabric=%0d cpu=%0d cart_reads=%0d reset_vector=%0d/%0d chr_reads=%0d nonzero=%0d pc=%04x",
                 fabric_cycles, cpu_accesses, cartridge_reads, reset_vector_low_reads,
                 reset_vector_high_reads, chr_reads, nonzero_chr_reads,
                 cpu_debug_pc);
        $finish;
    end
endmodule
