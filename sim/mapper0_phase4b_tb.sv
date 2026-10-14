`timescale 1ns/1ps

module mapper0_phase4b_tb;
    logic unused_phase7a_irq_0;
    logic unused_phase7a_irq_1;
    logic unused_phase7a_irq_2;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [15:0] cpu_address = 16'h0000;
    logic cpu_read = 1'b0;
    logic cpu_write = 1'b0;
    logic [7:0] cpu_write_data = 8'h00;
    logic [12:0] chr_address = 13'h0000;
    logic chr_read = 1'b0;
    logic chr_write = 1'b0;
    logic [7:0] chr_write_data = 8'h00;

    logic [7:0] nrom128_cpu_data;
    logic [7:0] nrom256_cpu_data;
    logic [7:0] chrram_cpu_data;
    logic [7:0] nrom128_chr_data;
    logic [7:0] nrom256_chr_data;
    logic [7:0] chrram_chr_data;
    logic nrom128_present;
    logic [7:0] nrom128_mapper;
    logic nrom128_is_256;
    logic nrom128_chr_is_ram;
    logic [1:0] nrom128_mirroring;
    logic [14:0] nrom128_debug_prg_address;
    logic [7:0] nrom128_debug_prg_data;
    logic [12:0] nrom128_debug_chr_address;
    logic [7:0] nrom128_debug_chr_data;
    logic nrom128_debug_prg_read;
    logic nrom128_debug_chr_read;

    logic [7:0] reference_prg128 [0:16383];
    logic [7:0] reference_prg256 [0:32767];
    logic [7:0] reference_chr [0:8191];
    integer address_index;
    integer prg_checks = 0;
    integer chr_checks = 0;

    /* verilator lint_off PINCONNECTEMPTY */
    nes_cartridge #(
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd1),
        .PRG_INIT_FILE ("build/cartridge/phase4b_map_nrom128.prg.hex"),
        .CHR_INIT_FILE ("build/cartridge/phase4b_map_nrom128.chr.hex")
    ) nrom128 (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .irq(unused_phase7a_irq_0),
        .clk(clk), .reset(reset),
        .cpu_address(cpu_address), .cpu_read(cpu_read),
        .cpu_write(cpu_write), .cpu_write_data(cpu_write_data),
        .cpu_read_data(nrom128_cpu_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(nrom128_chr_data),
        .cartridge_present(nrom128_present),
        .mapper_number(nrom128_mapper), .nrom_256(nrom128_is_256),
        .chr_is_ram(nrom128_chr_is_ram),
        .mirroring_mode(nrom128_mirroring),
        .debug_prg_address(nrom128_debug_prg_address),
        .debug_prg_data(nrom128_debug_prg_data),
        .debug_chr_address(nrom128_debug_chr_address),
        .debug_chr_data(nrom128_debug_chr_data),
        .debug_prg_read(nrom128_debug_prg_read),
        .debug_prg_write(), .debug_prg_ram_read(),
        .debug_prg_ram_write(),
        .debug_chr_read(nrom128_debug_chr_read), .debug_chr_write()
    );

    nes_cartridge #(
        .PRG_ROM_BYTES (32768),
        .CHR_IS_RAM    (1'b0),
        .PRG_RAM_ENABLE(1'b0),
        .MIRRORING_MODE(2'd0),
        .PRG_INIT_FILE ("build/cartridge/phase4b_map_nrom256.prg.hex"),
        .CHR_INIT_FILE ("build/cartridge/phase4b_map_nrom256.chr.hex")
    ) nrom256 (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .irq(unused_phase7a_irq_1),
        .clk(clk), .reset(reset),
        .cpu_address(cpu_address), .cpu_read(cpu_read),
        .cpu_write(cpu_write), .cpu_write_data(cpu_write_data),
        .cpu_read_data(nrom256_cpu_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(nrom256_chr_data),
        .cartridge_present(), .mapper_number(), .nrom_256(),
        .chr_is_ram(), .mirroring_mode(), .debug_prg_address(),
        .debug_prg_data(), .debug_chr_address(), .debug_chr_data(),
        .debug_prg_read(), .debug_prg_write(),
        .debug_prg_ram_read(), .debug_prg_ram_write(),
        .debug_chr_read(), .debug_chr_write()
    );

    nes_cartridge #(
        .PRG_ROM_BYTES (16384),
        .CHR_IS_RAM    (1'b1),
        .PRG_RAM_ENABLE(1'b1),
        .MIRRORING_MODE(2'd1),
        .PRG_INIT_FILE ("build/cartridge/phase4b_chrram_nrom128.prg.hex")
    ) ram_cartridge (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .irq(unused_phase7a_irq_2),
        .clk(clk), .reset(reset),
        .cpu_address(cpu_address), .cpu_read(cpu_read),
        .cpu_write(cpu_write), .cpu_write_data(cpu_write_data),
        .cpu_read_data(chrram_cpu_data),
        .chr_address(chr_address), .chr_read(chr_read),
        .chr_write(chr_write), .chr_write_data(chr_write_data),
        .chr_read_data(chrram_chr_data),
        .cartridge_present(), .mapper_number(), .nrom_256(),
        .chr_is_ram(), .mirroring_mode(), .debug_prg_address(),
        .debug_prg_data(), .debug_chr_address(), .debug_chr_data(),
        .debug_prg_read(), .debug_prg_write(),
        .debug_prg_ram_read(), .debug_prg_ram_write(),
        .debug_chr_read(), .debug_chr_write()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk <= ~clk;

    task automatic prefetch_cpu(input logic [15:0] address);
        begin
            @(negedge clk);
            cpu_address = address;
            cpu_read = 1'b0;
            cpu_write = 1'b0;
            @(posedge clk);
            #1;
            cpu_read = 1'b1;
            #1;
        end
    endtask

    task automatic write_prg_ram(
        input logic [15:0] address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            cpu_address = address;
            cpu_write_data = value;
            cpu_read = 1'b0;
            cpu_write = 1'b1;
            @(posedge clk);
            #1;
            cpu_write = 1'b0;
        end
    endtask

    task automatic write_chr_ram(
        input logic [12:0] address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            chr_address = address;
            chr_write_data = value;
            chr_read = 1'b0;
            chr_write = 1'b1;
            @(posedge clk);
            #1;
            chr_write = 1'b0;
        end
    endtask

    task automatic expect_chr_ram(
        input logic [12:0] address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            chr_address = address;
            chr_read = 1'b1;
            @(posedge clk);
            #1;
            assert (chrram_chr_data == value)
                else $fatal(1, "CHR RAM %04x expected %02x got %02x",
                            address, value, chrram_chr_data);
        end
    endtask

    initial begin
        $dumpfile("build/sim/mapper0_phase4b.fst");
        $dumpvars(0, mapper0_phase4b_tb);
        $readmemh("build/cartridge/phase4b_map_nrom128.prg.hex",
                  reference_prg128);
        $readmemh("build/cartridge/phase4b_map_nrom256.prg.hex",
                  reference_prg256);
        $readmemh("build/cartridge/phase4b_map_nrom128.chr.hex",
                  reference_chr);

        repeat (3) @(posedge clk);
        assert (nrom128_cpu_data == 8'h00 && nrom128_chr_data == 8'h00);
        reset = 1'b0;
        assert (nrom128_present && nrom128_mapper == 8'h00);
        assert (!nrom128_is_256 && !nrom128_chr_is_ram);
        assert (nrom128_mirroring == 2'd1);

        // Exhaustively prove NROM-128 mirroring and NROM-256 linear mapping.
        for (address_index = 0; address_index < 32768;
             address_index = address_index + 1) begin
            prefetch_cpu(16'h8000 + address_index[15:0]);
            assert (nrom128_cpu_data ==
                    reference_prg128[address_index & 32'h00003fff])
                else $fatal(1, "NROM-128 mismatch at %04x",
                            16'h8000 + address_index[15:0]);
            assert (nrom256_cpu_data == reference_prg256[address_index])
                else $fatal(1, "NROM-256 mismatch at %04x",
                            16'h8000 + address_index[15:0]);
            assert (nrom128_debug_prg_address ==
                    {1'b0, address_index[13:0]});
            assert (nrom128_debug_prg_data == nrom128_cpu_data);
            assert (nrom128_debug_prg_read);
            prg_checks = prg_checks + 2;
        end

        // Required CPU boundaries and all interrupt-vector bytes.
        for (address_index = 32'h00003ffa;
             address_index < 32'h00004000;
             address_index = address_index + 1) begin
            prefetch_cpu(16'hc000 + address_index[15:0]);
            assert (nrom128_cpu_data == reference_prg128[address_index]);
        end
        prefetch_cpu(16'h6000);
        assert (nrom128_cpu_data == 8'h00);
        prefetch_cpu(16'h7fff);
        assert (nrom128_cpu_data == 8'h00);
        prefetch_cpu(16'h8000);
        assert (nrom128_cpu_data == reference_prg128[0]);
        prefetch_cpu(16'hbfff);
        assert (nrom128_cpu_data == reference_prg128[14'h3fff]);
        prefetch_cpu(16'hc000);
        assert (nrom128_cpu_data == reference_prg128[0]);
        prefetch_cpu(16'hffff);
        assert (nrom128_cpu_data == reference_prg128[14'h3fff]);

        write_prg_ram(16'h6000, 8'h36);
        write_prg_ram(16'h7fff, 8'ha9);
        prefetch_cpu(16'h6000);
        assert (chrram_cpu_data == 8'h36);
        prefetch_cpu(16'h7fff);
        assert (chrram_cpu_data == 8'ha9);

        // Exhaustive 8 KiB CHR ROM addressing and read-only behavior.
        cpu_read = 1'b0;
        chr_read = 1'b1;
        for (address_index = 0; address_index < 8192;
             address_index = address_index + 1) begin
            @(negedge clk);
            chr_address = address_index[12:0];
            @(posedge clk);
            #1;
            assert (nrom128_chr_data == reference_chr[address_index])
                else $fatal(1, "CHR ROM mismatch at %04x", address_index);
            assert (nrom256_chr_data == reference_chr[address_index]);
            assert (nrom128_debug_chr_address == address_index[12:0]);
            assert (nrom128_debug_chr_data == nrom128_chr_data);
            assert (nrom128_debug_chr_read);
            chr_checks = chr_checks + 2;
        end

        // CHR RAM supports writes across both pattern tables.
        chr_read = 1'b0;
        write_chr_ram(13'h0000, 8'h10);
        write_chr_ram(13'h0fff, 8'h32);
        write_chr_ram(13'h1000, 8'h54);
        write_chr_ram(13'h1fff, 8'h76);
        expect_chr_ram(13'h0000, 8'h10);
        expect_chr_ram(13'h0fff, 8'h32);
        expect_chr_ram(13'h1000, 8'h54);
        expect_chr_ram(13'h1fff, 8'h76);

        reset = 1'b1;
        #1;
        assert (nrom128_cpu_data == 8'h00 && nrom128_chr_data == 8'h00);
        assert (!nrom128_debug_prg_read && !nrom128_debug_chr_read);

        $display("PASS: Phase 4B Mapper 0/NROM");
        $display("prg_checks=%0d chr_checks=%0d NROM-128/NROM-256/CHR-RAM/PRG-RAM",
                 prg_checks, chr_checks);
        $finish;
    end
endmodule
