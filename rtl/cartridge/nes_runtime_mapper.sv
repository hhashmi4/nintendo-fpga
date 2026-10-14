`timescale 1ns/1ps

// Mapper framework around the retained Phase 4F-B writable payload store.
// Storage reset is physical; mapper reset also covers loading/activation.
module nes_runtime_mapper (
    input  logic                                      clk,
    input  logic                                      reset,
    input  logic                                      mapper_reset,
    input  logic                                      configuration_valid,
    input  logic [7:0]                                mapper_number,
    input  logic [15:0]                               prg_rom_bytes,
    input  logic [15:0]                               chr_rom_bytes,
    input  logic [1:0]                                initial_mirroring,
    input  logic        cpu_cycle_tick,
    input  logic        ppu_cycle_tick,
    input  logic [13:0] ppu_bus_address,
    input  logic        ppu_bus_read,
    input  logic        ppu_bus_write,
    output logic [1:0]                                mirroring_mode,
    output logic                                      irq,
    input  logic                                      chr_is_ram,

    input  logic [15:0]                               cpu_address,
    input  logic                                      cpu_read,
    input  logic                                      cpu_write,
    input  logic [7:0]                                cpu_write_data,
    output logic [7:0]                                cpu_read_data,

    input  logic [12:0]                               chr_address,
    input  logic                                      chr_read,
    input  logic                                      chr_write,
    input  logic [7:0]                                chr_write_data,
    output logic [7:0]                                chr_read_data,

    input  logic                                      storage_write_valid,
    input  nes_runtime_loader_pkg::loader_target_t    storage_write_target,
    input  logic [nes_runtime_loader_pkg::LOADER_ADDRESS_BITS-1:0]
                                                        storage_write_address,
    input  logic [7:0]                                storage_write_data,
    output logic                                      storage_write_ready,

    output logic [14:0]                               debug_prg_address,
    output logic [7:0]                                debug_prg_data,
    output logic [12:0]                               debug_chr_address,
    output logic [7:0]                                debug_chr_data,
    output logic                                      debug_prg_read,
    output logic                                      debug_prg_write,
    output logic                                      debug_chr_read,
    output logic                                      debug_chr_write
);
    logic mapper_supported;
    logic mapper_config_valid;
    logic cpu_prg_select;
    logic cpu_ram_select;
    logic [23:0] physical_prg_address;
    logic [23:0] physical_prg_ram_address;
    logic [23:0] physical_chr_address;
    logic prg_ram_write_enable;
    logic chr_write_enable;
    logic unused_cpu_read_valid;
    logic unused_chr_read_valid;
    logic [14:0] mapped_prg_address;
    logic [7:0] storage_prg_read_data;
    logic [7:0] storage_chr_read_data;

    nes_mapper mapping (
        .clk(clk), .reset(reset || mapper_reset),
        .configuration_valid(configuration_valid), .mapper_number(mapper_number),
        .prg_rom_bytes({8'd0, prg_rom_bytes}), .chr_rom_bytes({8'd0, chr_rom_bytes}),
        .chr_is_ram(chr_is_ram), .prg_ram_enable(1'b0),
        .initial_mirroring(initial_mirroring),
        .cpu_address(cpu_address), .cpu_read(cpu_read),
        .cpu_write(cpu_write), .cpu_write_data(cpu_write_data),
        .chr_address(chr_address), .chr_read(chr_read), .chr_write(chr_write),
        .cpu_cycle_tick(cpu_cycle_tick),
        .ppu_cycle_tick(ppu_cycle_tick),
        .ppu_bus_address(ppu_bus_address),
        .ppu_bus_read(ppu_bus_read),
        .ppu_bus_write(ppu_bus_write),
        .mapper_supported(mapper_supported), .config_valid(mapper_config_valid),
        .cpu_prg_select(cpu_prg_select), .cpu_ram_select(cpu_ram_select),
        .cpu_read_valid(unused_cpu_read_valid),
        .chr_read_valid(unused_chr_read_valid),
        .prg_address(physical_prg_address),
        .prg_ram_address(physical_prg_ram_address),
        .chr_memory_address(physical_chr_address),
        .prg_ram_write_enable(prg_ram_write_enable),
        .chr_write_enable(chr_write_enable),
        .mirroring_mode(mirroring_mode), .irq(irq)
    );
    assign mapped_prg_address = physical_prg_address[14:0];

    always_comb begin
        cpu_read_data = 8'h00;
        if (cpu_prg_select)
            cpu_read_data = storage_prg_read_data;
        chr_read_data = reset || mapper_reset || !mapper_config_valid ?
                        8'h00 : storage_chr_read_data;
    end

    assign debug_prg_address = mapped_prg_address;
    // NROM ignores CPU writes, but expose their payload on the debug data
    // view so a write transaction remains fully observable.
    assign debug_prg_data = cpu_write ? cpu_write_data : cpu_read_data;
    assign debug_chr_address = chr_address;
    assign debug_chr_data = chr_read_data;
    assign debug_prg_read = cpu_prg_select && cpu_read;
    assign debug_prg_write = cpu_prg_select && cpu_write;
    assign debug_chr_read = !reset && !mapper_reset && mapper_config_valid && chr_read;
    assign debug_chr_write = !reset && !mapper_reset && mapper_config_valid && chr_write;

    nes_runtime_cartridge_storage storage (
        .clk                  (clk),
        .reset                (reset),
        .storage_write_valid  (storage_write_valid),
        .storage_write_target (storage_write_target),
        .storage_write_address(storage_write_address),
        .storage_write_data   (storage_write_data),
        .storage_write_ready  (storage_write_ready),
        .prg_read_address     (mapped_prg_address),
        .prg_read_data        (storage_prg_read_data),
        .chr_address          (physical_chr_address[12:0]),
        .chr_write            (chr_write),
        .chr_write_enable     (chr_write_enable),
        .chr_write_data       (chr_write_data),
        .chr_read_data        (storage_chr_read_data)
    );

    logic unused_mapping;
    assign unused_mapping = ^{mapper_supported, cpu_ram_select,
        physical_prg_address[23:15], physical_prg_ram_address,
        physical_chr_address[23:13], prg_ram_write_enable};

`ifndef SYNTHESIS
    always_comb begin
        assert (!(cpu_read && cpu_write));
        assert (!(chr_read && chr_write));
        if (mapper_config_valid && prg_rom_bytes == 16'd16384)
            assert (!mapped_prg_address[14]);
    end
`endif
endmodule
