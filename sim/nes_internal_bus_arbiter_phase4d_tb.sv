`timescale 1ns/1ps

module nes_internal_bus_arbiter_phase4d_tb;
    import nes_system_pkg::*;

    logic reset = 1'b1;
    logic [10:0] cpu_ram_read_address = 11'h345;
    logic cpu_ppu_enable = 1'b1;
    logic cpu_ppu_valid = 1'b1;
    logic cpu_ppu_write = 1'b0;
    logic [15:0] cpu_ppu_address = 16'h2002;
    logic [7:0] cpu_ppu_write_data = 8'h12;
    logic [15:0] cpu_cart_address = 16'h8123;
    logic cpu_cart_read = 1'b1;
    logic cpu_cart_write = 1'b0;
    logic [7:0] cpu_cart_write_data = 8'h34;
    logic dma_active = 1'b0;
    logic dma_cycle_slot = 1'b0;
    logic dma_source_read_request = 1'b0;
    logic dma_source_read_event = 1'b0;
    logic dma_oam_write_event = 1'b0;
    logic [15:0] dma_source_address = 16'h0000;
    logic [7:0] dma_oam_write_data = 8'h00;
    logic dmc_active = 1'b0;
    logic dmc_source_read_request = 1'b0;
    logic dmc_source_read_event = 1'b0;
    logic [15:0] dmc_source_address = 16'h0000;
    logic [7:0] ram_read_data = 8'h5a;
    logic [7:0] ppu_read_data = 8'ha5;
    logic [7:0] cart_read_data = 8'hc3;
    nes_bus_master_t bus_owner;
    nes_cpu_target_t dma_source_target;
    nes_cpu_target_t dmc_source_target;
    logic [10:0] shared_ram_read_address;
    logic [7:0] dma_source_read_data;
    logic [7:0] dmc_source_read_data;
    logic ppu_enable;
    logic ppu_valid;
    logic ppu_write;
    logic [15:0] ppu_address;
    logic [7:0] ppu_write_data;
    logic [15:0] cart_address;
    logic cart_read;
    logic cart_write;
    logic [7:0] cart_write_data;
    integer checks = 0;

    nes_internal_bus_arbiter dut (.*);

    task automatic check_dma_address(input logic [15:0] address);
        begin
            dma_source_address = address;
            #1;
            if (address <= 16'h1fff) begin
                assert (dma_source_target == NES_CPU_TARGET_RAM);
                assert (shared_ram_read_address == address[10:0]);
                assert (dma_source_read_data == ram_read_data);
            end else if (address <= 16'h3fff) begin
                assert (dma_source_target == NES_CPU_TARGET_PPU);
                assert (ppu_valid && !ppu_write);
                assert (ppu_address == {13'h400, address[2:0]});
                assert (dma_source_read_data == ppu_read_data);
            end else if (address >= 16'h4020) begin
                assert (dma_source_target == NES_CPU_TARGET_CARTRIDGE);
                assert (cart_address == address && cart_read && !cart_write);
                assert (dma_source_read_data == cart_read_data);
            end else begin
                assert (dma_source_read_data == 8'h00);
                assert (!(ppu_valid || cart_read || cart_write));
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_internal_bus_arbiter_phase4d.fst");
        $dumpvars(0, nes_internal_bus_arbiter_phase4d_tb);

        #1;
        assert (bus_owner == NES_BUS_MASTER_NONE);
        reset = 1'b0;
        #1;
        assert (bus_owner == NES_BUS_MASTER_CPU);
        assert (shared_ram_read_address == cpu_ram_read_address);
        assert (ppu_enable == cpu_ppu_enable && ppu_valid && !ppu_write);
        assert (ppu_address == cpu_ppu_address);
        assert (cart_address == cpu_cart_address && cart_read && !cart_write);
        assert (cart_write_data == cpu_cart_write_data);

        // Deliberately leave CPU requests asserted: DMA ownership must suppress
        // them rather than relying only on cooperative upstream behavior.
        dma_active = 1'b1;
        dma_cycle_slot = 1'b1;
        dma_source_read_request = 1'b1;
        dma_source_read_event = 1'b1;
        #1;
        assert (bus_owner == NES_BUS_MASTER_DMA);

        // Every byte of representative base and mirrored CPU RAM pages.
        for (int page_index = 0; page_index < 5; page_index++) begin
            logic [7:0] page;
            case (page_index)
                0: page = 8'h00;
                1: page = 8'h02;
                2: page = 8'h08;
                3: page = 8'h0a;
                default: page = 8'h18;
            endcase
            for (int index = 0; index < 256; index++)
                check_dma_address({page, index[7:0]});
        end

        // PPU aliases all reach exactly one canonical register read.
        check_dma_address(16'h2000);
        check_dma_address(16'h2007);
        check_dma_address(16'h2008);
        check_dma_address(16'h3fff);

        // APU, DMA, controllers, and the reserved gap are deterministic zero
        // and never inherit the intentionally asserted CPU-side requests.
        check_dma_address(16'h4000);
        check_dma_address(16'h4013);
        check_dma_address(16'h4014);
        check_dma_address(16'h4015);
        check_dma_address(16'h4016);
        check_dma_address(16'h4017);
        for (int address = 16408; address <= 16415; address++)
            check_dma_address(address[15:0]);

        // Every byte of a cartridge source page is routed to the existing
        // cartridge interface, with the address held during the read phase.
        for (int index = 0; index < 256; index++)
            check_dma_address({8'h80, index[7:0]});
        check_dma_address(16'h4020);
        check_dma_address(16'hffff);

        // Destination writes exclusively own the PPU port at canonical $2004.
        dma_source_read_request = 1'b0;
        dma_source_read_event = 1'b0;
        dma_oam_write_event = 1'b1;
        dma_oam_write_data = 8'h6d;
        #1;
        assert (ppu_valid && ppu_write && ppu_address == 16'h2004);
        assert (ppu_write_data == 8'h6d);
        assert (!(cart_read || cart_write));

        // Phase 5F DMC reads share the same decoder and take deterministic
        // priority without inheriting either CPU or OAM strobes.
        dmc_active = 1'b1;
        dmc_source_read_request = 1'b1;
        dmc_source_read_event = 1'b1;
        dmc_source_address = 16'h1855;
        #1;
        assert (bus_owner == NES_BUS_MASTER_DMC);
        assert (dmc_source_target == NES_CPU_TARGET_RAM);
        assert (shared_ram_read_address == 11'h055);
        assert (dmc_source_read_data == ram_read_data);
        assert (!(ppu_valid || cart_read || cart_write));

        dmc_source_address = 16'h3fff;
        #1;
        assert (dmc_source_target == NES_CPU_TARGET_PPU);
        assert (ppu_valid && !ppu_write && ppu_address == 16'h2007);
        assert (dmc_source_read_data == ppu_read_data);

        dmc_source_address = 16'hc123;
        #1;
        assert (dmc_source_target == NES_CPU_TARGET_CARTRIDGE);
        assert (cart_read && !cart_write && cart_address == 16'hc123);
        assert (dmc_source_read_data == cart_read_data);

        dmc_source_address = 16'h4016;
        #1;
        assert (dmc_source_target == NES_CPU_TARGET_CONTROLLER);
        assert (!(ppu_valid || cart_read || cart_write));
        assert (dmc_source_read_data == 8'h00);

        dmc_active = 1'b0;
        dmc_source_read_request = 1'b0;
        dmc_source_read_event = 1'b0;

        dma_active = 1'b0;
        dma_oam_write_event = 1'b0;
        #1;
        assert (bus_owner == NES_BUS_MASTER_CPU);
        assert (cart_read == cpu_cart_read && ppu_valid == cpu_ppu_valid);

        $display("PASS: Phase 4D-A internal bus arbitration checks=%0d RAM/PPU/I-O/cartridge",
                 checks);
        $finish;
    end
endmodule
