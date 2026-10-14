`timescale 1ns/1ps

module mapper_framework_tb;
    logic clk = 0;
    always #5 clk = !clk;
    logic reset = 1;
    logic configuration_valid = 0;
    logic [7:0] mapper_number = 0;
    logic [23:0] prg_rom_bytes = 0;
    logic [23:0] chr_rom_bytes = 0;
    logic chr_is_ram = 0;
    logic prg_ram_enable = 0;
    logic [1:0] initial_mirroring = 0;
    logic [15:0] cpu_address = 0;
    logic cpu_read = 0, cpu_write = 0;
    logic [7:0] cpu_write_data = 0;
    logic cpu_cycle_tick = 0;
    logic [12:0] chr_address = 0;
    logic chr_read = 0, chr_write = 0;
    logic ppu_cycle_tick = 0;
    logic [13:0] ppu_bus_address = 0;
    logic ppu_bus_read = 0, ppu_bus_write = 0;
    logic mapper_supported, config_valid;
    logic cpu_prg_select, cpu_ram_select, cpu_read_valid, chr_read_valid;
    logic [23:0] prg_address, prg_ram_address, chr_memory_address;
    logic prg_ram_write_enable, chr_write_enable;
    logic [1:0] mirroring_mode;
    logic irq;
    integer checks = 0;

    nes_mapper dut (.*);

    // Independent expectations use arithmetic intervals/modulo, not the DUT's
    // translator, support predicate or address-slice implementation.
    task automatic check(input bit support, input bit valid_image,
                         input integer size);
        bit run_image, rom_owner, ram_owner;
        #1;
        run_image = valid_image && !reset;
        rom_owner = run_image && int'(cpu_address) / 8192 >= 4;
        ram_owner = run_image && prg_ram_enable &&
                    int'(cpu_address) / 8192 == 3;
        assert (mapper_supported == support && config_valid == valid_image)
            else $fatal(1, "selection mapper=%0d size=%0d", mapper_number, prg_rom_bytes);
        assert (cpu_prg_select == rom_owner && cpu_ram_select == ram_owner)
            else $fatal(1, "ownership cpu=%04x", cpu_address);
        assert (cpu_read_valid == ((rom_owner || ram_owner) && cpu_read && !cpu_write));
        assert (chr_read_valid == (run_image && chr_read && !chr_write));
        assert (prg_ram_write_enable == (ram_owner && cpu_write && !cpu_read));
        assert (chr_write_enable == (run_image && chr_is_ram && chr_write && !chr_read));
        assert (prg_address == (valid_image ? 24'(int'(cpu_address) % size) : 24'd0))
            else $fatal(1, "PRG mapping cpu=%04x physical=%06x size=%0d", cpu_address, prg_address, size);
        assert (prg_ram_address == (valid_image ? 24'(int'(cpu_address) % 8192) : 24'd0));
        assert (chr_memory_address == (valid_image ? 24'(chr_address) : 24'd0));
        assert (mirroring_mode == (valid_image ? initial_mirroring : 2'd0));
        assert (!irq) else $fatal(1, "NROM/invalid cartridge asserted IRQ");
        checks++;
    endtask

    initial begin
        check(1, 0, 16384); // power-on, no cartridge configuration
        reset = 0;
        configuration_valid = 1;
        // Every CPU address, every CHR offset, all legacy mirroring modes,
        // both RAM policies and simultaneous CPU/PPU reads/writes. Addresses
        // keep changing between strobes, exercising memory precharge selects.
        for (int size = 16384; size <= 32768; size *= 2) begin
            prg_rom_bytes = 24'(size);
            for (int mode = 0; mode < 16; mode++) begin
                chr_is_ram = 1'(mode);
                chr_rom_bytes = chr_is_ram ? 0 : 8192;
                prg_ram_enable = 1'(mode >> 1);
                initial_mirroring = 2'(mode >> 2);
                for (int address = 0; address < 65536; address++) begin
                    cpu_address = 16'(address);
                    cpu_read = 1'(address);
                    cpu_write = 1'(address >> 1);
                    cpu_write_data = 8'(address / 7);
                    chr_address = 13'(address);
                    chr_read = 1'(address >> 2);
                    chr_write = 1'(address >> 3);
                    cpu_cycle_tick = address % 3 == 0;
                    ppu_cycle_tick = 1'(address >> 4);
                    ppu_bus_address = 14'(address);
                    ppu_bus_read = 1'(address >> 5);
                    ppu_bus_write = 1'(address >> 6);
                    check(1, 1, size);
                end
            end
        end
        // Exhaust all classic-iNES mapper IDs; future planned IDs never alias
        // NROM. Unsupported selection must discard a previously mapped bank.
        for (int id = 1; id < 256; id++) begin
            mapper_number = 8'(id);
            check(0, 0, 32768);
        end
        mapper_number = 0;
        configuration_valid = 0;
        check(1, 0, 32768);
        configuration_valid = 1;
        prg_rom_bytes = 0; check(1, 0, 32768);
        prg_rom_bytes = 16383; check(1, 0, 32768);
        prg_rom_bytes = 32769; check(1, 0, 32768);
        prg_rom_bytes = 65536; check(1, 0, 32768);
        prg_rom_bytes = 24'h804000; check(1, 0, 32768);
        prg_rom_bytes = 16384;
        chr_is_ram = 0;
        chr_rom_bytes = 0; check(1, 0, 16384);
        chr_rom_bytes = 8191; check(1, 0, 16384);
        chr_rom_bytes = 8193; check(1, 0, 16384);
        chr_rom_bytes = 24'h802000; check(1, 0, 16384);
        chr_rom_bytes = 8192;
        chr_is_ram = 1; check(1, 0, 16384);
        chr_rom_bytes = 0;
        // No stale high bank or IRQ after repeated replacement/reset cycles.
        for (int epoch = 0; epoch < 32; epoch++) begin
            prg_rom_bytes = 32768;
            cpu_address = 16'hffff;
            check(1, 1, 32768);
            reset = 1; check(1, 1, 32768);
            prg_rom_bytes = 16384; check(1, 1, 16384);
            reset = 0; check(1, 1, 16384);
        end
        $display("PASS: Phase7A mapper framework checks=%0d exhaustive CPU/CHR, 256 IDs, permissions, mirroring, concurrent activity and 32 reset/replacement epochs", checks);
        $finish;
    end
    initial begin
        #3000000;
        $fatal(1, "mapper framework timeout");
    end
endmodule
