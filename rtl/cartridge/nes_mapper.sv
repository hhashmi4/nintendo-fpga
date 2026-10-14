`timescale 1ns/1ps

// Cartridge policy and translation; memory remains in the storage endpoints.
// Only NROM is implemented. No future mapper ID aliases Mapper 0.
// Configuration is held by the cartridge lifecycle owner throughout execution.
module nes_mapper (
    input  logic        clk,
    input  logic        reset,
    input  logic        configuration_valid,
    input  logic [7:0]  mapper_number,
    input  logic [23:0] prg_rom_bytes,
    input  logic [23:0] chr_rom_bytes,
    input  logic        chr_is_ram,
    input  logic        prg_ram_enable,
    input  logic [1:0]  initial_mirroring,

    input  logic [15:0] cpu_address,
    input  logic        cpu_read,
    input  logic        cpu_write,
    input  logic [7:0]  cpu_write_data,
    // Accepted CPU bus slots, including slots outside cartridge space / DMA.
    input  logic        cpu_cycle_tick,
    input  logic [12:0] chr_address,
    input  logic        chr_read,
    input  logic        chr_write,
    // Full logical PPU activity, distinct from the decoded CHR memory port.
    input  logic        ppu_cycle_tick,
    input  logic [13:0] ppu_bus_address,
    input  logic        ppu_bus_read,
    input  logic        ppu_bus_write,

    output logic        mapper_supported,
    output logic        config_valid,
    output logic        cpu_prg_select,
    output logic        cpu_ram_select,
    output logic        cpu_read_valid,
    output logic        chr_read_valid,
    output logic [23:0] prg_address,
    output logic [23:0] prg_ram_address,
    output logic [23:0] chr_memory_address,
    output logic        prg_ram_write_enable,
    output logic        chr_write_enable,
    output logic [1:0]  mirroring_mode,
    output logic        irq
);
    logic [14:0] nrom_prg_address;
    logic enabled;

    nes_mapper0_address nrom_address (
        .nrom_256(prg_rom_bytes == 24'd32768),
        .cpu_address(cpu_address[14:0]),
        .prg_address(nrom_prg_address)
    );

    // Support describes the implementation; validity describes this image.
    // These status outputs do not disappear during functional reset.
    assign mapper_supported = mapper_number == 8'd0;
    assign config_valid = configuration_valid && mapper_supported &&
        (prg_rom_bytes == 24'd16384 || prg_rom_bytes == 24'd32768) &&
        ((chr_is_ram && chr_rom_bytes == 24'd0) ||
         (!chr_is_ram && chr_rom_bytes == 24'd8192));
    assign enabled = config_valid && !reset;

    // Selects are independent of access strobes: synchronous RAM precharge
    // must not wait for the one-fabric-cycle accepted read pulse.
    assign cpu_prg_select = enabled && cpu_address >= 16'h8000;
    assign cpu_ram_select = enabled && prg_ram_enable &&
                            cpu_address >= 16'h6000 && cpu_address < 16'h8000;
    assign cpu_read_valid = cpu_read && !cpu_write &&
                            (cpu_prg_select || cpu_ram_select);
    assign chr_read_valid = enabled && chr_read && !chr_write;
    assign prg_address = config_valid ? {9'd0, nrom_prg_address} : 24'd0;
    assign prg_ram_address = config_valid ? {11'd0, cpu_address[12:0]} : 24'd0;
    assign chr_memory_address = config_valid ? {11'd0, chr_address} : 24'd0;
    assign prg_ram_write_enable = cpu_ram_select && cpu_write && !cpu_read;
    assign chr_write_enable = enabled && chr_is_ram && chr_write && !chr_read;
    assign mirroring_mode = config_valid ? initial_mirroring : 2'd0;
    // NROM has no registers or IRQ state. CPU writes to ROM cannot write
    // payload memory: only the separate loader owns that write port.
    assign irq = 1'b0;

    // Reserved for stateful mapper implementations, not synthesized state or
    // support claims. The existing clock-enable architecture supplies these
    // events; a mapper must never use one as a generated clock.
    logic unused_stateful_inputs;
    assign unused_stateful_inputs = ^{clk, cpu_write_data, cpu_cycle_tick,
        ppu_cycle_tick, ppu_bus_address, ppu_bus_read, ppu_bus_write};
endmodule
