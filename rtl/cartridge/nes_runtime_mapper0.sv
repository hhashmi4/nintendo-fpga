`timescale 1ns/1ps

// Runtime-configurable Mapper 0 address translation around the Phase 4F-B
// writable payload store. The Phase 4F-D cartridge wrapper supplies the
// atomically latched active configuration.
module nes_runtime_mapper0 (
    input  logic                                      clk,
    input  logic                                      reset,
    input  logic                                      nrom_256,
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
    logic [14:0] mapped_prg_address;
    logic [7:0] storage_prg_read_data;
    logic [7:0] storage_chr_read_data;

    always_comb begin
        if (nrom_256)
            mapped_prg_address = cpu_address[14:0];
        else
            mapped_prg_address = {1'b0, cpu_address[13:0]};
    end

    always_comb begin
        cpu_read_data = 8'h00;
        if (!reset && cpu_address >= 16'h8000)
            cpu_read_data = storage_prg_read_data;
        chr_read_data = reset ? 8'h00 : storage_chr_read_data;
    end

    assign debug_prg_address = mapped_prg_address;
    // NROM ignores CPU writes, but expose their payload on the debug data
    // view so a write transaction remains fully observable.
    assign debug_prg_data = cpu_write ? cpu_write_data : cpu_read_data;
    assign debug_chr_address = chr_address;
    assign debug_chr_data = chr_read_data;
    assign debug_prg_read = !reset && cpu_read && cpu_address >= 16'h8000;
    assign debug_prg_write = !reset && cpu_write && cpu_address >= 16'h8000;
    assign debug_chr_read = !reset && chr_read;
    assign debug_chr_write = !reset && chr_write;

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
        .chr_address          (chr_address),
        .chr_write            (chr_write),
        .chr_write_enable     (chr_is_ram),
        .chr_write_data       (chr_write_data),
        .chr_read_data        (storage_chr_read_data)
    );

`ifndef SYNTHESIS
    always_comb begin
        assert (!(cpu_read && cpu_write));
        assert (!(chr_read && chr_write));
        if (!nrom_256)
            assert (!mapped_prg_address[14]);
    end
`endif
endmodule
