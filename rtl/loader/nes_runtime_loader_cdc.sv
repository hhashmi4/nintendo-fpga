`timescale 1ns/1ps

// One-entry bundled-data request/acknowledge CDC plus a coherent return-status
// mailbox. Command payload banks remain stable until the loader accepts the
// command; status banks remain stable until the MMIO domain acknowledges them.
module nes_runtime_loader_cdc (
    input  logic                                      source_clk,
    input  logic                                      source_reset,
    input  logic                                      source_valid,
    input  nes_runtime_loader_pkg::loader_command_t   source_command,
    input  nes_runtime_loader_pkg::loader_target_t    source_target,
    input  logic [15:0]                               source_address,
    input  logic [7:0]                                source_data,
    input  logic                                      source_manifest_valid,
    input  logic [7:0]                                source_manifest_mapper,
    input  logic [15:0]                               source_manifest_prg_bytes,
    input  logic [15:0]                               source_manifest_chr_bytes,
    input  logic                                      source_manifest_chr_is_ram,
    input  logic [1:0]                                source_manifest_mirroring,
    output logic                                      source_ready,
    output logic                                      source_busy,
    output logic                                      source_done,
    output nes_runtime_loader_pkg::loader_state_t     source_response_state,
    output logic                                      source_response_error,
    output nes_runtime_loader_pkg::loader_error_t     source_response_error_code,
    output nes_runtime_loader_pkg::loader_state_t     source_status_state,
    output logic                                      source_status_busy,
    output logic                                      source_status_ready,
    output logic                                      source_status_image_valid,
    output logic                                      source_status_runtime_active,
    output logic                                      source_status_nes_hold_reset,
    output logic                                      source_status_error,
    output nes_runtime_loader_pkg::loader_error_t     source_status_error_code,
    output logic                                      source_status_activation_in_progress,

    input  logic                                      destination_clk,
    input  logic                                      destination_reset,
    output logic                                      destination_valid,
    output nes_runtime_loader_pkg::loader_command_t   destination_command,
    output nes_runtime_loader_pkg::loader_target_t    destination_target,
    output logic [15:0]                               destination_address,
    output logic [7:0]                                destination_data,
    output logic                                      destination_manifest_valid,
    output logic [7:0]                                destination_manifest_mapper,
    output logic [15:0]                               destination_manifest_prg_bytes,
    output logic [15:0]                               destination_manifest_chr_bytes,
    output logic                                      destination_manifest_chr_is_ram,
    output logic [1:0]                                destination_manifest_mirroring,
    input  logic                                      destination_command_ready,
    input  logic                                      destination_command_accepted,
    input  nes_runtime_loader_pkg::loader_state_t     destination_status_state,
    input  logic                                      destination_status_busy,
    input  logic                                      destination_status_image_valid,
    input  logic                                      destination_status_runtime_active,
    input  logic                                      destination_status_nes_hold_reset,
    input  logic                                      destination_status_error,
    input  nes_runtime_loader_pkg::loader_error_t     destination_status_error_code,
    input  logic                                      destination_status_activation_in_progress
);
    import nes_runtime_loader_pkg::*;

    localparam integer STATUS_WIDTH = 13;
    localparam integer RESPONSE_WIDTH = 7;
    localparam logic [STATUS_WIDTH-1:0] RESET_STATUS = {
        1'b0,                 // activation in progress
        LOADER_ERROR_NONE,    // error code
        1'b0,                 // loader error
        1'b1,                 // NES held reset
        1'b0,                 // runtime active
        1'b0,                 // image valid
        1'b0,                 // loader command ready
        1'b0,                 // loader busy
        LOADER_STATE_IDLE     // loader state
    };

    logic source_armed;
    logic request_toggle;
    logic acknowledge_toggle;
    logic status_request_toggle;
    logic status_acknowledge_toggle;
    logic destination_response_pending;

    (* preserve *) loader_command_t command_bank;
    (* preserve *) loader_target_t target_bank;
    (* preserve *) logic [15:0] address_bank;
    (* preserve *) logic [7:0] data_bank;
    (* preserve *) logic manifest_valid_bank;
    (* preserve *) logic [7:0] manifest_mapper_bank;
    (* preserve *) logic [15:0] manifest_prg_bytes_bank;
    (* preserve *) logic [15:0] manifest_chr_bytes_bank;
    (* preserve *) logic manifest_chr_is_ram_bank;
    (* preserve *) logic [1:0] manifest_mirroring_bank;
    (* preserve *) logic [RESPONSE_WIDTH-1:0] response_bank;
    (* preserve *) logic [STATUS_WIDTH-1:0] status_bank;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] acknowledge_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] status_request_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] status_acknowledge_sync;

    logic [STATUS_WIDTH-1:0] destination_live_status;
    logic [STATUS_WIDTH-1:0] destination_last_published_status;
    logic [STATUS_WIDTH-1:0] source_status_bank;

    assign destination_live_status = {
        destination_status_activation_in_progress,
        destination_status_error_code,
        destination_status_error,
        destination_status_nes_hold_reset,
        destination_status_runtime_active,
        destination_status_image_valid,
        destination_command_ready,
        destination_status_busy,
        destination_status_state
    };

    assign source_status_state = loader_state_t'(source_status_bank[1:0]);
    assign source_status_busy = source_status_bank[2];
    assign source_status_ready = source_status_bank[3];
    assign source_status_image_valid = source_status_bank[4];
    assign source_status_runtime_active = source_status_bank[5];
    assign source_status_nes_hold_reset = source_status_bank[6];
    assign source_status_error = source_status_bank[7];
    assign source_status_error_code = loader_error_t'(source_status_bank[11:8]);
    assign source_status_activation_in_progress = source_status_bank[12];

    assign source_ready = source_armed && !source_busy && !source_reset;

    always_ff @(posedge source_clk) begin
        if (source_reset) begin
            source_armed <= 1'b0;
            request_toggle <= 1'b0;
            acknowledge_sync <= 3'b000;
            status_request_sync <= 3'b000;
            status_acknowledge_toggle <= 1'b0;
            command_bank <= LOADER_COMMAND_BEGIN;
            target_bank <= LOADER_TARGET_NONE;
            address_bank <= 16'h0000;
            data_bank <= 8'h00;
            manifest_valid_bank <= 1'b0;
            manifest_mapper_bank <= 8'h00;
            manifest_prg_bytes_bank <= 16'h0000;
            manifest_chr_bytes_bank <= 16'h0000;
            manifest_chr_is_ram_bank <= 1'b0;
            manifest_mirroring_bank <= LOADER_MIRROR_VERTICAL;
            source_busy <= 1'b0;
            source_done <= 1'b0;
            source_response_state <= LOADER_STATE_IDLE;
            source_response_error <= 1'b0;
            source_response_error_code <= LOADER_ERROR_NONE;
            source_status_bank <= RESET_STATUS;
        end else begin
            acknowledge_sync <= {acknowledge_sync[1:0], acknowledge_toggle};
            status_request_sync <= {
                status_request_sync[1:0], status_request_toggle};
            source_done <= 1'b0;

            if (!source_valid)
                source_armed <= 1'b1;
            if (source_valid && source_ready) begin
                source_armed <= 1'b0;
                command_bank <= source_command;
                target_bank <= source_target;
                address_bank <= source_address;
                data_bank <= source_data;
                manifest_valid_bank <= source_manifest_valid;
                manifest_mapper_bank <= source_manifest_mapper;
                manifest_prg_bytes_bank <= source_manifest_prg_bytes;
                manifest_chr_bytes_bank <= source_manifest_chr_bytes;
                manifest_chr_is_ram_bank <= source_manifest_chr_is_ram;
                manifest_mirroring_bank <= source_manifest_mirroring;
                request_toggle <= !request_toggle;
                source_busy <= 1'b1;
            end

            if (status_request_sync[2] != status_acknowledge_toggle) begin
                source_status_bank <= status_bank;
                status_acknowledge_toggle <= status_request_sync[2];
            end

            if (source_busy && acknowledge_sync[2] == request_toggle) begin
                source_response_state <= loader_state_t'(response_bank[1:0]);
                source_response_error <= response_bank[2];
                source_response_error_code <=
                    loader_error_t'(response_bank[6:3]);
                source_busy <= 1'b0;
                source_done <= 1'b1;
            end
        end
    end

    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            request_sync <= 3'b000;
            acknowledge_toggle <= 1'b0;
            status_acknowledge_sync <= 3'b000;
            status_request_toggle <= 1'b0;
            destination_response_pending <= 1'b0;
            destination_valid <= 1'b0;
            destination_command <= LOADER_COMMAND_BEGIN;
            destination_target <= LOADER_TARGET_NONE;
            destination_address <= 16'h0000;
            destination_data <= 8'h00;
            destination_manifest_valid <= 1'b0;
            destination_manifest_mapper <= 8'h00;
            destination_manifest_prg_bytes <= 16'h0000;
            destination_manifest_chr_bytes <= 16'h0000;
            destination_manifest_chr_is_ram <= 1'b0;
            destination_manifest_mirroring <= LOADER_MIRROR_VERTICAL;
            response_bank <= {
                LOADER_ERROR_NONE, 1'b0, LOADER_STATE_IDLE};
            status_bank <= RESET_STATUS;
            destination_last_published_status <= ~RESET_STATUS;
        end else begin
            request_sync <= {request_sync[1:0], request_toggle};
            status_acknowledge_sync <= {
                status_acknowledge_sync[1:0], status_acknowledge_toggle};

            if (!destination_valid && !destination_response_pending &&
                request_sync[2] != acknowledge_toggle) begin
                destination_command <= command_bank;
                destination_target <= target_bank;
                destination_address <= address_bank;
                destination_data <= data_bank;
                destination_manifest_valid <= manifest_valid_bank;
                destination_manifest_mapper <= manifest_mapper_bank;
                destination_manifest_prg_bytes <= manifest_prg_bytes_bank;
                destination_manifest_chr_bytes <= manifest_chr_bytes_bank;
                destination_manifest_chr_is_ram <= manifest_chr_is_ram_bank;
                destination_manifest_mirroring <= manifest_mirroring_bank;
                destination_valid <= 1'b1;
            end

            if (destination_valid && destination_command_accepted) begin
                destination_valid <= 1'b0;
                destination_response_pending <= 1'b1;
            end

            // Wait one loader edge after acceptance so state/error signals
            // reflect the command just consumed before acknowledging it.
            if (destination_response_pending) begin
                response_bank <= {
                    destination_status_error_code,
                    destination_status_error,
                    destination_status_state
                };
                acknowledge_toggle <= request_sync[2];
                destination_response_pending <= 1'b0;
            end

            if (status_acknowledge_sync[2] == status_request_toggle &&
                destination_live_status !=
                destination_last_published_status) begin
                status_bank <= destination_live_status;
                destination_last_published_status <= destination_live_status;
                status_request_toggle <= !status_request_toggle;
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (!(destination_command_accepted && !destination_valid));
        if (destination_valid) begin
            assert (destination_command == command_bank);
            assert (destination_target == target_bank);
            assert (destination_address == address_bank);
            assert (destination_data == data_bank);
        end
    end
`endif
endmodule
