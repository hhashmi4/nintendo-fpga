`timescale 1ns/1ps

// CPU-facing NES system bus. This module owns address decode, read-data
// arbitration, mirrored sub-address generation, and accepted-access strobes.
// Peripheral state remains in the owning module; in particular, PPU register
// mirroring selects one of the existing eight registers rather than copying it.
module nes_cpu_bus (
    input  logic        reset,
    input  logic        cpu_enable,
    input  logic        cpu_bus_valid,
    input  logic [15:0] cpu_address,
    input  logic [7:0]  cpu_write_data,
    input  logic        cpu_write_enable,
    output logic [7:0]  cpu_read_data,

    output nes_system_pkg::nes_cpu_target_t selected_target,
    output logic [10:0] ram_address,
    output logic [2:0]  ppu_register,

    input  logic [7:0]  ram_read_data,
    output logic        ram_read,
    output logic        ram_write,

    input  logic [7:0]  ppu_read_data,
    output logic [15:0] ppu_address,
    output logic        ppu_read,
    output logic        ppu_write,

    input  logic [7:0]  apu_read_data,
    output logic [15:0] apu_address,
    output logic        apu_read,
    output logic        apu_write,
    output logic [7:0]  apu_write_data,

    output logic        dma_select,
    output logic        dma_write,
    output logic [7:0]  dma_write_data,

    input  logic [7:0]  controller_read_data,
    output logic        controller_port,
    output logic        controller_read,
    output logic        controller_write,
    output logic [7:0]  controller_write_data,

    input  logic [7:0]  cartridge_read_data,
    output logic [15:0] cartridge_address,
    output logic        cartridge_read,
    output logic        cartridge_write,
    output logic [7:0]  cartridge_write_data,

    output logic        ram_access,
    output logic        ppu_access,
    output logic        apu_access,
    output logic        controller_access,
    output logic        cartridge_access
);
    import nes_system_pkg::*;

    nes_cpu_target_t decoded_target;
    logic [10:0] decoded_ram_address;
    logic [2:0] decoded_ppu_register;
    logic accepted_access;
    logic accepted_read;
    logic accepted_write;

    nes_cpu_address_decoder decoder (
        .address      (cpu_address),
        .write_enable(cpu_write_enable),
        .target       (decoded_target),
        .ram_address  (decoded_ram_address),
        .ppu_register (decoded_ppu_register)
    );

    assign accepted_access = !reset && cpu_enable && cpu_bus_valid;
    assign accepted_read = accepted_access && !cpu_write_enable;
    assign accepted_write = accepted_access && cpu_write_enable;

    assign selected_target = reset ? NES_CPU_TARGET_NONE : decoded_target;
    assign ram_address = decoded_ram_address;
    assign ppu_register = decoded_ppu_register;

    assign ram_access = accepted_access &&
                        decoded_target == NES_CPU_TARGET_RAM;
    assign ppu_access = accepted_access &&
                        decoded_target == NES_CPU_TARGET_PPU;
    assign apu_access = accepted_access &&
                        decoded_target == NES_CPU_TARGET_APU;
    assign dma_select = accepted_access &&
                        decoded_target == NES_CPU_TARGET_DMA;
    assign controller_access = accepted_access &&
                               decoded_target == NES_CPU_TARGET_CONTROLLER;
    assign cartridge_access = accepted_access &&
                              decoded_target == NES_CPU_TARGET_CARTRIDGE;

    assign ram_read = accepted_read && decoded_target == NES_CPU_TARGET_RAM;
    assign ram_write = accepted_write && decoded_target == NES_CPU_TARGET_RAM;

    // Canonicalize every CPU-visible PPU alias to $2000-$2007. The PPU owns
    // the only copy of each register and sees the original access exactly once.
    assign ppu_address = {13'h400, decoded_ppu_register};
    assign ppu_read = accepted_read && decoded_target == NES_CPU_TARGET_PPU;
    assign ppu_write = accepted_write && decoded_target == NES_CPU_TARGET_PPU;

    assign apu_address = cpu_address;
    assign apu_read = accepted_read && decoded_target == NES_CPU_TARGET_APU;
    assign apu_write = accepted_write && decoded_target == NES_CPU_TARGET_APU;
    assign apu_write_data = cpu_write_data;

    assign dma_write = accepted_write && decoded_target == NES_CPU_TARGET_DMA;
    assign dma_write_data = cpu_write_data;

    assign controller_port = cpu_address[0];
    assign controller_read = accepted_read &&
                             decoded_target == NES_CPU_TARGET_CONTROLLER;
    assign controller_write = accepted_write &&
                              decoded_target == NES_CPU_TARGET_CONTROLLER;
    assign controller_write_data = cpu_write_data;

    assign cartridge_address = cpu_address;
    assign cartridge_read = accepted_read &&
                            decoded_target == NES_CPU_TARGET_CARTRIDGE;
    assign cartridge_write = accepted_write &&
                             decoded_target == NES_CPU_TARGET_CARTRIDGE;
    assign cartridge_write_data = cpu_write_data;

    always_comb begin
        cpu_read_data = 8'h00;
        if (!reset) begin
            case (decoded_target)
                NES_CPU_TARGET_RAM: cpu_read_data = ram_read_data;
                NES_CPU_TARGET_PPU: cpu_read_data = ppu_read_data;
                NES_CPU_TARGET_APU: cpu_read_data = apu_read_data;
                NES_CPU_TARGET_CONTROLLER:
                    cpu_read_data = controller_read_data;
                NES_CPU_TARGET_CARTRIDGE:
                    cpu_read_data = cartridge_read_data;
                default: cpu_read_data = 8'h00;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert ($onehot0({ram_access, ppu_access, apu_access, dma_select,
                          controller_access, cartridge_access}));
        assert (!(ram_read && ram_write));
        assert (!(ppu_read && ppu_write));
        assert (!(apu_read && apu_write));
        assert (!(controller_read && controller_write));
        assert (!(cartridge_read && cartridge_write));
        if (reset) begin
            assert (selected_target == NES_CPU_TARGET_NONE);
            assert (!(ram_access || ppu_access || apu_access || dma_select ||
                      controller_access || cartridge_access));
            assert (cpu_read_data == 8'h00);
        end
    end
`endif
endmodule
