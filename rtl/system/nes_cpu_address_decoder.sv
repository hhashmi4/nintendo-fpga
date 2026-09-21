`timescale 1ns/1ps

// Pure CPU-address decode. The target is direction-sensitive only at $4017:
// reads belong to controller port 2, while writes program the future APU
// frame counter. Physical sub-addresses expose RAM and PPU mirroring without
// duplicating either storage or registers.
module nes_cpu_address_decoder (
    input  logic [15:0] address,
    input  logic        write_enable,
    output nes_system_pkg::nes_cpu_target_t target,
    output logic [10:0] ram_address,
    output logic [2:0]  ppu_register
);
    import nes_system_pkg::*;

    always_comb begin
        target = NES_CPU_TARGET_NONE;
        if (address <= 16'h1fff) begin
            target = NES_CPU_TARGET_RAM;
        end else if (address <= 16'h3fff) begin
            target = NES_CPU_TARGET_PPU;
        end else if (address <= 16'h4013 || address == 16'h4015) begin
            target = NES_CPU_TARGET_APU;
        end else if (address == 16'h4014) begin
            target = NES_CPU_TARGET_DMA;
        end else if (address == 16'h4016) begin
            target = NES_CPU_TARGET_CONTROLLER;
        end else if (address == 16'h4017) begin
            target = write_enable ? NES_CPU_TARGET_APU :
                                    NES_CPU_TARGET_CONTROLLER;
        end else if (address >= 16'h4020) begin
            target = NES_CPU_TARGET_CARTRIDGE;
        end
    end

    assign ram_address = address[10:0];
    assign ppu_register = address[2:0];
endmodule
