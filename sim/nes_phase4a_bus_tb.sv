`timescale 1ns/1ps

module nes_phase4a_bus_tb;
    import nes_system_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic cpu_bus_valid = 1'b0;
    logic [15:0] cpu_address = 16'h0000;
    logic [7:0] cpu_write_data = 8'h00;
    logic cpu_write_enable = 1'b0;
    logic [7:0] cpu_read_data;
    nes_cpu_target_t selected_target;
    logic [10:0] ram_address;
    logic [2:0] ppu_register;
    logic [7:0] bus_ram_read_data;
    logic [7:0] memory_read_data;
    logic ram_read;
    logic ram_write;
    logic ppu_read;
    logic ppu_write;
    logic [15:0] ppu_address;
    logic apu_read;
    logic apu_write;
    logic [15:0] apu_address;
    logic [7:0] apu_write_data;
    logic dma_select;
    logic dma_write;
    logic [7:0] dma_write_data;
    logic controller_port;
    logic controller_read;
    logic controller_write;
    logic [7:0] controller_write_data;
    logic [15:0] cartridge_address;
    logic cartridge_read;
    logic cartridge_write;
    logic [7:0] cartridge_write_data;
    logic ram_access;
    logic ppu_access;
    logic apu_access;
    logic controller_access;
    logic cartridge_access;
    logic exercise_ram = 1'b0;

    integer vectors;
    integer vector_file;
    integer scan_result;
    logic vector_write;
    logic [2:0] vector_target;
    logic [10:0] vector_ram_address;
    logic [2:0] vector_ppu_register;
    integer access_count;

    assign bus_ram_read_data = exercise_ram ? memory_read_data : 8'ha1;

    nes_cpu_bus dut (
        .reset(reset),
        .cpu_enable(cpu_enable),
        .cpu_bus_valid(cpu_bus_valid),
        .cpu_address(cpu_address),
        .cpu_write_data(cpu_write_data),
        .cpu_write_enable(cpu_write_enable),
        .cpu_read_data(cpu_read_data),
        .selected_target(selected_target),
        .ram_address(ram_address),
        .ppu_register(ppu_register),
        .ram_read_data(bus_ram_read_data),
        .ram_read(ram_read),
        .ram_write(ram_write),
        .ppu_read_data(8'he5),
        .ppu_address(ppu_address),
        .ppu_read(ppu_read),
        .ppu_write(ppu_write),
        .apu_read_data(8'hb2),
        .apu_address(apu_address),
        .apu_read(apu_read),
        .apu_write(apu_write),
        .apu_write_data(apu_write_data),
        .dma_select(dma_select),
        .dma_write(dma_write),
        .dma_write_data(dma_write_data),
        .controller_read_data(8'hc3),
        .controller_port(controller_port),
        .controller_read(controller_read),
        .controller_write(controller_write),
        .controller_write_data(controller_write_data),
        .cartridge_read_data(8'hd4),
        .cartridge_address(cartridge_address),
        .cartridge_read(cartridge_read),
        .cartridge_write(cartridge_write),
        .cartridge_write_data(cartridge_write_data),
        .ram_access(ram_access),
        .ppu_access(ppu_access),
        .apu_access(apu_access),
        .controller_access(controller_access),
        .cartridge_access(cartridge_access)
    );

    nes_cpu_ram ram (
        .clk(clk),
        .read_address(ram_address),
        .read_data(memory_read_data),
        .write_enable(exercise_ram && ram_write),
        .write_address(ram_address),
        .write_data(cpu_write_data)
    );

    always #5 clk <= ~clk;

    task automatic write_ram_alias(
        input logic [15:0] address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            cpu_address = address;
            cpu_write_data = value;
            cpu_write_enable = 1'b1;
            cpu_bus_valid = 1'b1;
            cpu_enable = 1'b1;
            @(posedge clk);
            #1;
            assert (ram_write && ram_access)
                else $fatal(1, "RAM write not routed at %04x", address);
            @(negedge clk);
            cpu_bus_valid = 1'b0;
            cpu_write_enable = 1'b0;
        end
    endtask

    task automatic expect_ram_alias(
        input logic [15:0] address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            cpu_address = address;
            cpu_write_enable = 1'b0;
            cpu_bus_valid = 1'b1;
            cpu_enable = 1'b1;
            @(posedge clk);
            #1;
            assert (ram_read && ram_access)
                else $fatal(1, "RAM read not routed at %04x", address);
            assert (cpu_read_data == value)
                else $fatal(1, "RAM %04x expected %02x got %02x",
                            address, value, cpu_read_data);
            @(negedge clk);
            cpu_bus_valid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_phase4a_bus.fst");
        $dumpvars(0, nes_phase4a_bus_tb);

        #1;
        cpu_enable = 1'b1;
        cpu_bus_valid = 1'b1;
        cpu_write_enable = 1'b1;
        cpu_address = 16'hffff;
        cpu_write_data = 8'h5a;
        #1;
        assert (selected_target == NES_CPU_TARGET_NONE);
        assert (cpu_read_data == 8'h00);
        assert (!(ram_read || ram_write || ppu_read || ppu_write || apu_read ||
                  apu_write || dma_select || dma_write || controller_read ||
                  controller_write || cartridge_read || cartridge_write));

        reset = 1'b0;
        vector_file = $fopen("build/sim/nes_phase4a_bus_reference.txt", "r");
        assert (vector_file != 0) else $fatal(1, "cannot open bus vectors");
        vectors = 0;
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(vector_file, "%x %d %d %x %x\n",
                                  cpu_address, vector_write, vector_target,
                                  vector_ram_address, vector_ppu_register);
            if (scan_result == 5) begin
                cpu_write_enable = vector_write;
                cpu_bus_valid = 1'b1;
                cpu_enable = 1'b1;
                #1;
                assert (selected_target == vector_target)
                    else $fatal(1, "target mismatch address=%04x write=%0d",
                                cpu_address, vector_write);
                assert (ram_address == vector_ram_address);
                assert (ppu_register == vector_ppu_register);
                assert (ppu_address == {13'h400, vector_ppu_register});
                assert (apu_write_data == cpu_write_data);
                assert (dma_write_data == cpu_write_data);
                assert (controller_write_data == cpu_write_data);
                assert (cartridge_address == cpu_address);
                assert (cartridge_write_data == cpu_write_data);
                access_count = $countones({ram_access, ppu_access, apu_access,
                                           dma_select, controller_access,
                                           cartridge_access});
                if (vector_target == NES_CPU_TARGET_NONE) begin
                    assert (access_count == 0);
                end else begin
                    assert (access_count == 1);
                end

                assert (ram_access == (vector_target == NES_CPU_TARGET_RAM));
                assert (ppu_access == (vector_target == NES_CPU_TARGET_PPU));
                assert (apu_access == (vector_target == NES_CPU_TARGET_APU));
                assert (dma_select == (vector_target == NES_CPU_TARGET_DMA));
                assert (controller_access ==
                        (vector_target == NES_CPU_TARGET_CONTROLLER));
                assert (cartridge_access ==
                        (vector_target == NES_CPU_TARGET_CARTRIDGE));

                if (!vector_write) begin
                    case (vector_target)
                        NES_CPU_TARGET_RAM: assert (cpu_read_data == 8'ha1);
                        NES_CPU_TARGET_PPU: assert (cpu_read_data == 8'he5);
                        NES_CPU_TARGET_APU: assert (cpu_read_data == 8'hb2);
                        NES_CPU_TARGET_CONTROLLER:
                            assert (cpu_read_data == 8'hc3);
                        NES_CPU_TARGET_CARTRIDGE:
                            assert (cpu_read_data == 8'hd4);
                        default: assert (cpu_read_data == 8'h00);
                    endcase
                end
                vectors = vectors + 1;
            end
        end
        $fclose(vector_file);
        assert (vectors == 131072)
            else $fatal(1, "expected 131072 vectors, got %0d", vectors);

        // Direction-specific behavior at the shared $4017 address.
        cpu_address = 16'h4017;
        cpu_write_enable = 1'b0;
        #1;
        assert (controller_read && controller_port && !apu_read);
        cpu_write_enable = 1'b1;
        #1;
        assert (apu_write && !controller_write && apu_address == 16'h4017);

        // Exactly one physical 2 KiB RAM is visible through all four mirrors.
        cpu_bus_valid = 1'b0;
        exercise_ram = 1'b1;
        write_ram_alias(16'h0000, 8'h36);
        expect_ram_alias(16'h0000, 8'h36);
        expect_ram_alias(16'h0800, 8'h36);
        expect_ram_alias(16'h1000, 8'h36);
        expect_ram_alias(16'h1800, 8'h36);
        write_ram_alias(16'h1fff, 8'ha9);
        expect_ram_alias(16'h07ff, 8'ha9);
        expect_ram_alias(16'h0fff, 8'ha9);
        expect_ram_alias(16'h17ff, 8'ha9);
        expect_ram_alias(16'h1fff, 8'ha9);

        reset = 1'b1;
        cpu_bus_valid = 1'b1;
        cpu_address = 16'h4020;
        #1;
        assert (selected_target == NES_CPU_TARGET_NONE);
        assert (!cartridge_access && !cartridge_read && !cartridge_write);
        assert (cpu_read_data == 8'h00);

        $display("PASS: Phase 4A CPU bus (131072 exhaustive decode vectors, RAM mirrors, reset and arbitration)");
        $finish;
    end
endmodule
