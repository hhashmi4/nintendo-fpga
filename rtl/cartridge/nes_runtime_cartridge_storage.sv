`timescale 1ns/1ps

// Runtime-writable Mapper-0 payload storage. Loader addresses are byte
// offsets within the maximum supported NROM payloads; CPU address mapping is
// deliberately kept in the mapper framework.
module nes_runtime_cartridge_storage (
    input  logic                                      clk,
    input  logic                                      reset,

    input  logic                                      storage_write_valid,
    input  nes_runtime_loader_pkg::loader_target_t    storage_write_target,
    input  logic [nes_runtime_loader_pkg::LOADER_ADDRESS_BITS-1:0]
                                                        storage_write_address,
    input  logic [7:0]                                storage_write_data,
    output logic                                      storage_write_ready,

    input  logic [14:0]                               prg_read_address,
    output logic [7:0]                                prg_read_data,

    input  logic [12:0]                               chr_address,
    input  logic                                      chr_write,
    input  logic                                      chr_write_enable,
    input  logic [7:0]                                chr_write_data,
    output logic [7:0]                                chr_read_data
);
    import nes_runtime_loader_pkg::*;

    localparam integer PRG_STORAGE_BYTES = 32768;
    localparam integer CHR_STORAGE_BYTES = 8192;

    (* ramstyle = "M10K" *) logic [7:0] prg_memory
        [0:PRG_STORAGE_BYTES-1];
    (* ramstyle = "M10K" *) logic [7:0] chr_memory
        [0:CHR_STORAGE_BYTES-1];

    logic [7:0] prg_read_data_register;
    logic [7:0] chr_read_data_register;
    logic prg_bypass_valid;
    logic [7:0] prg_bypass_data;
    logic chr_bypass_valid;
    logic [7:0] chr_bypass_data;
    logic target_valid;
    logic address_valid;
    logic accepted_prg_write;
    logic accepted_chr_write;
    logic chr_write_port_enable;
    logic [12:0] chr_write_port_address;
    logic [7:0] chr_write_port_data;

`ifndef ALTERA_SYNTHESIS
    integer initialize_index;
    initial begin
        for (initialize_index = 0;
             initialize_index < PRG_STORAGE_BYTES;
             initialize_index = initialize_index + 1)
            prg_memory[initialize_index] = 8'h00;
        for (initialize_index = 0;
             initialize_index < CHR_STORAGE_BYTES;
             initialize_index = initialize_index + 1)
            chr_memory[initialize_index] = 8'h00;
    end
`endif

    always_comb begin
        target_valid = 1'b0;
        address_valid = 1'b0;
        case (storage_write_target)
            LOADER_TARGET_PRG: begin
                target_valid = 1'b1;
                address_valid = storage_write_address <=
                                LOADER_PRG_LAST_ADDRESS;
            end
            LOADER_TARGET_CHR: begin
                target_valid = 1'b1;
                address_valid = storage_write_address <=
                                LOADER_CHR_LAST_ADDRESS;
            end
            default: begin
                target_valid = 1'b0;
                address_valid = 1'b0;
            end
        endcase
    end

    // The local M10K write ports can accept one loader byte every cycle.
    // Reset is the only intentional not-ready condition. The range checks
    // make a direct, invalid storage request harmless even though Phase 4F-A
    // already prevents such requests architecturally.
    assign storage_write_ready = !reset && target_valid && address_valid;
    assign accepted_prg_write = storage_write_valid &&
                                storage_write_ready &&
                                storage_write_target == LOADER_TARGET_PRG;
    assign accepted_chr_write = storage_write_valid &&
                                storage_write_ready &&
                                storage_write_target == LOADER_TARGET_CHR;

    always_comb begin
        chr_write_port_enable = 1'b0;
        chr_write_port_address = 13'h0000;
        chr_write_port_data = 8'h00;
        if (accepted_chr_write) begin
            chr_write_port_enable = 1'b1;
            chr_write_port_address = storage_write_address[12:0];
            chr_write_port_data = storage_write_data;
        end else if (!reset && chr_write_enable && chr_write) begin
            chr_write_port_enable = 1'b1;
            chr_write_port_address = chr_address;
            chr_write_port_data = chr_write_data;
        end
    end

    assign prg_read_data = reset ? 8'h00 :
                           prg_bypass_valid ? prg_bypass_data :
                           prg_read_data_register;
    assign chr_read_data = reset ? 8'h00 :
                           chr_bypass_valid ? chr_bypass_data :
                           chr_read_data_register;

    // Memory contents are intentionally not reset. Reset suppresses writes,
    // masks read outputs to zero, and retains already accepted bytes. This
    // keeps the arrays inferable as block RAM. Same-address reads are
    // explicitly write-first. A loader CHR write takes priority over a PPU
    // CHR-RAM write because the inferred memory has one write port; the
    // Phase 4F-D activation controller holds the NES while loading.
    // Keep each memory's read and write ports in the canonical synchronous
    // simple-dual-port form. The bypass registers define write-first behavior
    // without depending on the device's native mixed-port collision mode.
    always_ff @(posedge clk) begin
        if (!reset && accepted_prg_write)
            prg_memory[storage_write_address[14:0]] <= storage_write_data;
        if (!reset && chr_write_port_enable)
            chr_memory[chr_write_port_address] <= chr_write_port_data;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            prg_bypass_valid <= 1'b0;
            prg_bypass_data <= 8'h00;
            chr_bypass_valid <= 1'b0;
            chr_bypass_data <= 8'h00;
        end else begin
            prg_read_data_register <= prg_memory[prg_read_address];
            chr_read_data_register <= chr_memory[chr_address];

            prg_bypass_valid <= accepted_prg_write &&
                                storage_write_address[14:0] ==
                                prg_read_address;
            if (accepted_prg_write)
                prg_bypass_data <= storage_write_data;

            chr_bypass_valid <= chr_write_port_enable &&
                                chr_write_port_address == chr_address;
            if (chr_write_port_enable)
                chr_bypass_data <= chr_write_port_data;
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        if (reset) begin
            assert (!storage_write_ready);
            assert (!accepted_prg_write && !accepted_chr_write);
            assert (prg_read_data == 8'h00 && chr_read_data == 8'h00);
        end
        assert (!(accepted_prg_write && accepted_chr_write));
        if (accepted_prg_write)
            assert (storage_write_address <= LOADER_PRG_LAST_ADDRESS);
        if (accepted_chr_write)
            assert (storage_write_address <= LOADER_CHR_LAST_ADDRESS);
    end
`endif
endmodule
