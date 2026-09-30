`timescale 1ns/1ps

// Runtime loader, writable Mapper-0 storage, and Phase 4F-D atomic activation.
// This remains independent of the eventual HPS bridge/CDC implementation.
module nes_runtime_cartridge #(
    parameter bit IMAGE_VALIDATION_ENABLE = 1'b1,
    parameter bit ACTIVATION_ENABLE = 1'b1,
    parameter integer ACTIVATION_RESET_CYCLES = 4
) (
    input  logic                                      clk,
    input  logic                                      reset,

    input  logic                                      command_valid,
    input  nes_runtime_loader_pkg::loader_command_t   command,
    input  nes_runtime_loader_pkg::loader_target_t    command_target,
    input  logic [nes_runtime_loader_pkg::LOADER_ADDRESS_BITS-1:0]
                                                        command_address,
    input  logic [7:0]                                command_data,
    output logic                                      command_ready,
    output logic                                      command_accepted,

    input  logic                                      manifest_valid,
    input  logic [7:0]                                manifest_mapper,
    input  logic [15:0]                               manifest_prg_bytes,
    input  logic [15:0]                               manifest_chr_bytes,
    input  logic                                      manifest_chr_is_ram,
    input  logic [1:0]                                manifest_mirroring,

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

    output nes_runtime_loader_pkg::loader_state_t     loader_state,
    output logic                                      loader_busy,
    output logic                                      loader_completed,
    output logic                                      loader_error,
    output nes_runtime_loader_pkg::loader_error_t     loader_error_code,
    output logic                                      nes_hold_reset,
    output logic                                      image_valid,
    output logic [7:0]                                image_mapper,
    output logic [15:0]                               image_prg_bytes,
    output logic [15:0]                               image_chr_bytes,
    output logic                                      image_chr_is_ram,
    output logic [1:0]                                image_mirroring,

    output logic                                      activation_accepted,
    output logic                                      activation_in_progress,
    output logic                                      activation_error,
    output logic                                      runtime_active,
    output logic [7:0]                                active_mapper,
    output logic [15:0]                               active_prg_bytes,
    output logic [15:0]                               active_chr_bytes,
    output logic                                      active_chr_is_ram,
    output logic [1:0]                                active_mirroring,

    output logic [14:0]                               debug_prg_address,
    output logic [7:0]                                debug_prg_data,
    output logic [12:0]                               debug_chr_address,
    output logic [7:0]                                debug_chr_data,
    output logic                                      debug_prg_read,
    output logic                                      debug_prg_write,
    output logic                                      debug_chr_read,
    output logic                                      debug_chr_write
);
    import nes_runtime_loader_pkg::*;

    logic storage_write_valid;
    loader_target_t storage_write_target;
    logic [LOADER_ADDRESS_BITS-1:0] storage_write_address;
    logic [7:0] storage_write_data;
    logic storage_write_ready;
    logic loader_hold_reset;
    logic loader_activation_accepted;
    logic activation_required;
    localparam integer ACTIVATION_COUNTER_BITS =
        ACTIVATION_RESET_CYCLES < 2 ? 1 :
        $clog2(ACTIVATION_RESET_CYCLES + 1);
    logic [ACTIVATION_COUNTER_BITS-1:0] activation_reset_count;
    logic mapper_nrom_256;
    logic mapper_chr_is_ram;

    assign mapper_nrom_256 = ACTIVATION_ENABLE ?
                             active_prg_bytes == LOADER_PRG_NROM256_BYTES :
                             nrom_256;
    assign mapper_chr_is_ram = ACTIVATION_ENABLE ? active_chr_is_ram :
                                                    chr_is_ram;
    assign activation_error = ACTIVATION_ENABLE && loader_error &&
                              loader_error_code ==
                              LOADER_ERROR_ACTIVATE_INVALID;
    assign nes_hold_reset = ACTIVATION_ENABLE ?
                            (reset || activation_required ||
                             activation_in_progress) : loader_hold_reset;

    always_ff @(posedge clk) begin
        if (reset) begin
            activation_accepted <= 1'b0;
            activation_in_progress <= 1'b0;
            activation_required <= 1'b0;
            activation_reset_count <= '0;
            runtime_active <= 1'b0;
            active_mapper <= 8'h00;
            active_prg_bytes <= 16'h0000;
            active_chr_bytes <= 16'h0000;
            active_chr_is_ram <= 1'b0;
            active_mirroring <= LOADER_MIRROR_VERTICAL;
        end else begin
            activation_accepted <= 1'b0;

            if (ACTIVATION_ENABLE && command_accepted &&
                command == LOADER_COMMAND_BEGIN)
                activation_required <= 1'b1;

            if (ACTIVATION_ENABLE && loader_activation_accepted) begin
                // All active selection/configuration registers change on this
                // one edge while the reset window begins. Runtime payload RAM
                // was already proven complete by the loader.
                runtime_active <= 1'b1;
                active_mapper <= image_mapper;
                active_prg_bytes <= image_prg_bytes;
                active_chr_bytes <= image_chr_bytes;
                active_chr_is_ram <= image_chr_is_ram;
                active_mirroring <= image_mirroring;
                activation_required <= 1'b0;
                activation_accepted <= 1'b1;
                activation_in_progress <= 1'b1;
                activation_reset_count <=
                    ACTIVATION_COUNTER_BITS'(ACTIVATION_RESET_CYCLES);
            end else if (ACTIVATION_ENABLE && activation_in_progress) begin
                if (activation_reset_count <=
                    ACTIVATION_COUNTER_BITS'(1)) begin
                    activation_in_progress <= 1'b0;
                    activation_reset_count <= '0;
                end else begin
                    activation_reset_count <= activation_reset_count -
                                              ACTIVATION_COUNTER_BITS'(1);
                end
            end
        end
    end

    nes_runtime_loader #(
        .IMAGE_VALIDATION_ENABLE(IMAGE_VALIDATION_ENABLE)
    ) loader (
        .clk                  (clk),
        .reset                (reset),
        .command_valid        (command_valid),
        .command              (command),
        .command_target       (command_target),
        .command_address      (command_address),
        .command_data         (command_data),
        .command_ready        (command_ready),
        .command_accepted     (command_accepted),
        .manifest_valid       (manifest_valid),
        .manifest_mapper      (manifest_mapper),
        .manifest_prg_bytes   (manifest_prg_bytes),
        .manifest_chr_bytes   (manifest_chr_bytes),
        .manifest_chr_is_ram  (manifest_chr_is_ram),
        .manifest_mirroring   (manifest_mirroring),
        .storage_write_valid  (storage_write_valid),
        .storage_write_target (storage_write_target),
        .storage_write_address(storage_write_address),
        .storage_write_data   (storage_write_data),
        .storage_write_ready  (storage_write_ready),
        .state                (loader_state),
        .busy                 (loader_busy),
        .completed            (loader_completed),
        .error                (loader_error),
        .error_code           (loader_error_code),
        .nes_hold_reset       (loader_hold_reset),
        .image_valid          (image_valid),
        .image_mapper         (image_mapper),
        .image_prg_bytes      (image_prg_bytes),
        .image_chr_bytes      (image_chr_bytes),
        .image_chr_is_ram     (image_chr_is_ram),
        .image_mirroring      (image_mirroring),
        .activation_accepted  (loader_activation_accepted)
    );

    nes_runtime_mapper0 mapper (
        .clk                  (clk),
        .reset                (reset),
        .nrom_256             (mapper_nrom_256),
        .chr_is_ram           (mapper_chr_is_ram),
        .cpu_address          (cpu_address),
        .cpu_read             (cpu_read),
        .cpu_write            (cpu_write),
        .cpu_write_data       (cpu_write_data),
        .cpu_read_data        (cpu_read_data),
        .chr_address          (chr_address),
        .chr_read             (chr_read),
        .chr_write            (chr_write),
        .chr_write_data       (chr_write_data),
        .chr_read_data        (chr_read_data),
        .storage_write_valid  (storage_write_valid),
        .storage_write_target (storage_write_target),
        .storage_write_address(storage_write_address),
        .storage_write_data   (storage_write_data),
        .storage_write_ready  (storage_write_ready),
        .debug_prg_address    (debug_prg_address),
        .debug_prg_data       (debug_prg_data),
        .debug_chr_address    (debug_chr_address),
        .debug_chr_data       (debug_chr_data),
        .debug_prg_read       (debug_prg_read),
        .debug_prg_write      (debug_prg_write),
        .debug_chr_read       (debug_chr_read),
        .debug_chr_write      (debug_chr_write)
    );

`ifndef SYNTHESIS
    initial begin
        assert (ACTIVATION_RESET_CYCLES > 0)
            else $fatal(1, "activation reset must last at least one cycle");
    end

    always_comb begin
        if (ACTIVATION_ENABLE) begin
            if (!reset && !activation_required &&
                !activation_in_progress)
                assert (!nes_hold_reset);
            if (activation_accepted) begin
                assert (runtime_active);
                assert (active_mapper == 8'd0);
                assert (active_prg_bytes == LOADER_PRG_NROM128_BYTES ||
                        active_prg_bytes == LOADER_PRG_NROM256_BYTES);
            end
            if (activation_in_progress || activation_required)
                assert (nes_hold_reset);
        end
    end
`endif
endmodule
