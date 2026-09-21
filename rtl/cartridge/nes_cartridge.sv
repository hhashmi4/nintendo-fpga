`timescale 1ns/1ps

// Generic synthesized-cartridge boundary. Future mapper implementations plug
// in here without changing nes_core, the CPU system bus, or the PPU CHR port.
module nes_cartridge #(
    parameter integer MAPPER_NUMBER = 0,
    parameter integer PRG_ROM_BYTES = 16384,
    parameter bit     CHR_IS_RAM = 1'b0,
    parameter bit     PRG_RAM_ENABLE = 1'b0,
    parameter logic [1:0] MIRRORING_MODE = 2'd0,
    parameter string  PRG_INIT_FILE = "",
    parameter string  CHR_INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [15:0] cpu_address,
    input  logic        cpu_read,
    input  logic        cpu_write,
    input  logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,

    input  logic [12:0] chr_address,
    input  logic        chr_read,
    input  logic        chr_write,
    input  logic [7:0]  chr_write_data,
    output logic [7:0]  chr_read_data,

    output logic        cartridge_present,
    output logic [7:0]  mapper_number,
    output logic        nrom_256,
    output logic        chr_is_ram,
    output logic [1:0]  mirroring_mode,
    output logic [14:0] debug_prg_address,
    output logic [7:0]  debug_prg_data,
    output logic [12:0] debug_chr_address,
    output logic [7:0]  debug_chr_data,
    output logic        debug_prg_read,
    output logic        debug_prg_write,
    output logic        debug_prg_ram_read,
    output logic        debug_prg_ram_write,
    output logic        debug_chr_read,
    output logic        debug_chr_write
);
    assign cartridge_present = 1'b1;
    assign mapper_number = 8'(MAPPER_NUMBER);
    assign nrom_256 = PRG_ROM_BYTES == 32768;
    assign chr_is_ram = CHR_IS_RAM;
    assign mirroring_mode = MIRRORING_MODE;

    generate
        if (MAPPER_NUMBER == 0) begin : mapper0_selected
            nes_mapper0 #(
                .PRG_ROM_BYTES (PRG_ROM_BYTES),
                .CHR_IS_RAM    (CHR_IS_RAM),
                .PRG_RAM_ENABLE(PRG_RAM_ENABLE),
                .PRG_INIT_FILE (PRG_INIT_FILE),
                .CHR_INIT_FILE (CHR_INIT_FILE)
            ) mapper (
                .*
            );
        end else begin : unsupported_mapper
            always_comb begin
                cpu_read_data = 8'h00;
                chr_read_data = 8'h00;
                debug_prg_address = 15'h0000;
                debug_prg_data = 8'h00;
                debug_chr_address = 13'h0000;
                debug_chr_data = 8'h00;
                debug_prg_read = 1'b0;
                debug_prg_write = 1'b0;
                debug_prg_ram_read = 1'b0;
                debug_prg_ram_write = 1'b0;
                debug_chr_read = 1'b0;
                debug_chr_write = 1'b0;
            end
`ifndef SYNTHESIS
            initial $fatal(1, "unsupported synthesized cartridge mapper");
`endif
        end
    endgenerate
endmodule
