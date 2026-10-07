`timescale 1ns/1ps

// Exclusive CPU/DMA ownership for the internal RAM read port and the shared
// CPU-facing PPU/cartridge ports. APU/controller/unmapped DMA source reads are
// deliberate deterministic zeroes and never emit peripheral access strobes.
module nes_internal_bus_arbiter (
    input  logic        reset,

    input  logic [10:0] cpu_ram_read_address,
    input  logic        cpu_ppu_enable,
    input  logic        cpu_ppu_valid,
    input  logic        cpu_ppu_write,
    input  logic [15:0] cpu_ppu_address,
    input  logic [7:0]  cpu_ppu_write_data,
    input  logic [15:0] cpu_cart_address,
    input  logic        cpu_cart_read,
    input  logic        cpu_cart_write,
    input  logic [7:0]  cpu_cart_write_data,

    input  logic        dma_active,
    input  logic        dma_cycle_slot,
    input  logic        dma_source_read_request,
    input  logic        dma_source_read_event,
    input  logic        dma_oam_write_event,
    input  logic [15:0] dma_source_address,
    input  logic [7:0]  dma_oam_write_data,

    input  logic        dmc_active,
    input  logic        dmc_source_read_request,
    input  logic        dmc_source_read_event,
    input  logic [15:0] dmc_source_address,

    input  logic [7:0]  ram_read_data,
    input  logic [7:0]  ppu_read_data,
    input  logic [7:0]  cart_read_data,

    output nes_system_pkg::nes_bus_master_t bus_owner,
    output nes_system_pkg::nes_cpu_target_t dma_source_target,
    output nes_system_pkg::nes_cpu_target_t dmc_source_target,
    output logic [10:0] shared_ram_read_address,
    output logic [7:0]  dma_source_read_data,
    output logic [7:0]  dmc_source_read_data,

    output logic        ppu_enable,
    output logic        ppu_valid,
    output logic        ppu_write,
    output logic [15:0] ppu_address,
    output logic [7:0]  ppu_write_data,

    output logic [15:0] cart_address,
    output logic        cart_read,
    output logic        cart_write,
    output logic [7:0]  cart_write_data
);
    import nes_system_pkg::*;

    logic [10:0] dma_ram_address;
    logic [2:0] dma_ppu_register;
    logic [10:0] dmc_ram_address;
    logic [2:0] dmc_ppu_register;

    nes_cpu_address_decoder dma_decoder (
        .address      (dma_source_address),
        .write_enable(1'b0),
        .target       (dma_source_target),
        .ram_address  (dma_ram_address),
        .ppu_register (dma_ppu_register)
    );

    nes_cpu_address_decoder dmc_decoder (
        .address      (dmc_source_address),
        .write_enable(1'b0),
        .target       (dmc_source_target),
        .ram_address  (dmc_ram_address),
        .ppu_register (dmc_ppu_register)
    );

    always_comb begin
        if (reset)
            bus_owner = NES_BUS_MASTER_NONE;
        else if (dmc_active)
            bus_owner = NES_BUS_MASTER_DMC;
        else if (dma_active)
            bus_owner = NES_BUS_MASTER_DMA;
        else
            bus_owner = NES_BUS_MASTER_CPU;

        // The registered RAM port is precharged for the entire DMA read phase.
        shared_ram_read_address = cpu_ram_read_address;
        if (dmc_source_read_request)
            shared_ram_read_address = dmc_ram_address;
        else if (dma_source_read_request)
            shared_ram_read_address = dma_ram_address;

        dma_source_read_data = 8'h00;
        case (dma_source_target)
            NES_CPU_TARGET_RAM: dma_source_read_data = ram_read_data;
            NES_CPU_TARGET_PPU: dma_source_read_data = ppu_read_data;
            NES_CPU_TARGET_CARTRIDGE:
                dma_source_read_data = cart_read_data;
            default: dma_source_read_data = 8'h00;
        endcase

        dmc_source_read_data = 8'h00;
        case (dmc_source_target)
            NES_CPU_TARGET_RAM: dmc_source_read_data = ram_read_data;
            NES_CPU_TARGET_PPU: dmc_source_read_data = ppu_read_data;
            NES_CPU_TARGET_CARTRIDGE:
                dmc_source_read_data = cart_read_data;
            default: dmc_source_read_data = 8'h00;
        endcase

        ppu_enable = cpu_ppu_enable;
        ppu_valid = cpu_ppu_valid;
        ppu_write = cpu_ppu_write;
        ppu_address = cpu_ppu_address;
        ppu_write_data = cpu_ppu_write_data;

        cart_address = cpu_cart_address;
        cart_read = cpu_cart_read;
        cart_write = cpu_cart_write;
        cart_write_data = cpu_cart_write_data;

        if (dmc_active) begin
            // DMC is the highest-priority read master. Its address is held
            // for the complete DMA so synchronous RAM/PRG data is ready on
            // the one read-event slot.
            ppu_enable = dmc_source_read_event;
            ppu_valid = 1'b0;
            ppu_write = 1'b0;
            ppu_address = {13'h400, dmc_ppu_register};
            ppu_write_data = 8'h00;

            cart_address = dmc_source_read_request ? dmc_source_address :
                                                       cpu_cart_address;
            cart_read = dmc_source_read_event &&
                        dmc_source_target == NES_CPU_TARGET_CARTRIDGE;
            cart_write = 1'b0;
            cart_write_data = 8'h00;

            if (dmc_source_read_event &&
                dmc_source_target == NES_CPU_TARGET_PPU)
                ppu_valid = 1'b1;
        end else if (dma_active) begin
            // CPU request strobes are suppressed by ownership even if a
            // future caller violates the upstream CPU-stall contract.
            ppu_enable = dma_cycle_slot;
            ppu_valid = 1'b0;
            ppu_write = 1'b0;
            ppu_address = {13'h400, dma_ppu_register};
            ppu_write_data = 8'h00;

            cart_address = dma_source_read_request ? dma_source_address :
                                                        cpu_cart_address;
            cart_read = 1'b0;
            cart_write = 1'b0;
            cart_write_data = 8'h00;

            if (dma_source_read_event &&
                dma_source_target == NES_CPU_TARGET_PPU) begin
                ppu_valid = 1'b1;
            end else if (dma_oam_write_event) begin
                ppu_valid = 1'b1;
                ppu_write = 1'b1;
                ppu_address = 16'h2004;
                ppu_write_data = dma_oam_write_data;
            end

            if (dma_source_read_event &&
                dma_source_target == NES_CPU_TARGET_CARTRIDGE)
                cart_read = 1'b1;
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (!(cart_read && cart_write));
        if (reset)
            assert (bus_owner == NES_BUS_MASTER_NONE);
        if (dmc_active) begin
            assert (bus_owner == NES_BUS_MASTER_DMC);
            assert (!cart_write && !ppu_write);
            if (dmc_source_target == NES_CPU_TARGET_APU ||
                dmc_source_target == NES_CPU_TARGET_CONTROLLER ||
                dmc_source_target == NES_CPU_TARGET_DMA ||
                dmc_source_target == NES_CPU_TARGET_NONE)
                assert (!ppu_valid && !cart_read);
        end else if (dma_active) begin
            assert (bus_owner == NES_BUS_MASTER_DMA);
            assert (!cart_write);
            assert (!(ppu_valid && ppu_write && cart_read));
            if (dma_source_target == NES_CPU_TARGET_APU ||
                dma_source_target == NES_CPU_TARGET_CONTROLLER ||
                dma_source_target == NES_CPU_TARGET_DMA ||
                dma_source_target == NES_CPU_TARGET_NONE)
                assert (!(ppu_valid && !ppu_write) && !cart_read);
        end
    end
`endif
endmodule
