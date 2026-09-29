`timescale 1ns/1ps

// FPGA-side logical runtime-loader protocol. The caller and downstream
// storage adapter use this same clock. A future physical HPS bridge owns CDC
// into this domain; this module neither receives asynchronous pulses nor
// accesses the NES CPU bus.
module nes_runtime_loader #(
    // Historical Phase 4F-A/B benches use the pre-manifest protocol to
    // preserve their focused proofs. All real integrations use the safe
    // default and must supply a complete Phase 4F-C manifest.
    parameter bit IMAGE_VALIDATION_ENABLE = 1'b1
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

    // BEGIN samples this manifest. The future HPS/iNES parser supplies
    // exact byte counts; no container parsing occurs in FPGA logic.
    input  logic                                      manifest_valid,
    input  logic [7:0]                                manifest_mapper,
    input  logic [15:0]                               manifest_prg_bytes,
    input  logic [15:0]                               manifest_chr_bytes,
    input  logic                                      manifest_chr_is_ram,
    input  logic [1:0]                                manifest_mirroring,

    output logic                                      storage_write_valid,
    output nes_runtime_loader_pkg::loader_target_t    storage_write_target,
    output logic [nes_runtime_loader_pkg::LOADER_ADDRESS_BITS-1:0]
                                                        storage_write_address,
    output logic [7:0]                                storage_write_data,
    input  logic                                      storage_write_ready,

    output nes_runtime_loader_pkg::loader_state_t     state,
    output logic                                      busy,
    output logic                                      completed,
    output logic                                      error,
    output nes_runtime_loader_pkg::loader_error_t     error_code,
    output logic                                      nes_hold_reset,

    output logic                                      image_valid,
    output logic [7:0]                                image_mapper,
    output logic [15:0]                               image_prg_bytes,
    output logic [15:0]                               image_chr_bytes,
    output logic                                      image_chr_is_ram,
    output logic [1:0]                                image_mirroring
);
    import nes_runtime_loader_pkg::*;

    loader_state_t state_register;
    loader_error_t error_register;
    logic write_seen;
    logic target_valid;
    logic address_valid;
    logic declared_target_valid;
    logic declared_address_valid;
    logic expected_address_valid;
    logic legal_active_write;
    logic begin_payload_valid;
    logic manifest_mirroring_valid;
    logic manifest_prg_valid;
    logic manifest_chr_valid;
    loader_error_t begin_manifest_error;

    logic session_manifest_valid;
    logic [7:0] image_mapper_register;
    logic [15:0] image_prg_bytes_register;
    logic [15:0] image_chr_bytes_register;
    logic image_chr_is_ram_register;
    logic [1:0] image_mirroring_register;
    logic [15:0] next_prg_address;
    logic [15:0] next_chr_address;

    always_comb begin
        target_valid = command_target == LOADER_TARGET_PRG ||
                       command_target == LOADER_TARGET_CHR;
        address_valid = 1'b0;
        case (command_target)
            LOADER_TARGET_PRG:
                address_valid = command_address <=
                                LOADER_PRG_LAST_ADDRESS;
            LOADER_TARGET_CHR:
                address_valid = command_address <=
                                LOADER_CHR_LAST_ADDRESS;
            default: address_valid = 1'b0;
        endcase
    end

    always_comb begin
        begin_payload_valid = command_target == LOADER_TARGET_NONE &&
                              command_address == 16'h0000 &&
                              command_data == 8'h00;
        manifest_mirroring_valid =
            manifest_mirroring == LOADER_MIRROR_VERTICAL ||
            manifest_mirroring == LOADER_MIRROR_HORIZONTAL;
        manifest_prg_valid =
            manifest_prg_bytes == LOADER_PRG_NROM128_BYTES ||
            manifest_prg_bytes == LOADER_PRG_NROM256_BYTES;
        manifest_chr_valid =
            (manifest_chr_is_ram && manifest_chr_bytes == 16'h0000) ||
            (!manifest_chr_is_ram &&
             manifest_chr_bytes == LOADER_CHR_ROM_BYTES);

        begin_manifest_error = LOADER_ERROR_NONE;
        if (!manifest_valid || !begin_payload_valid ||
            !manifest_mirroring_valid)
            begin_manifest_error = LOADER_ERROR_INVALID_MANIFEST;
        else if (manifest_mapper != 8'd0)
            begin_manifest_error = LOADER_ERROR_UNSUPPORTED_MAPPER;
        else if (!manifest_prg_valid)
            begin_manifest_error = LOADER_ERROR_UNSUPPORTED_PRG;
        else if (!manifest_chr_valid)
            begin_manifest_error = LOADER_ERROR_UNSUPPORTED_CHR;
    end

    always_comb begin
        declared_target_valid = target_valid;
        declared_address_valid = 1'b0;
        expected_address_valid = 1'b0;
        case (command_target)
            LOADER_TARGET_PRG: begin
                declared_address_valid =
                    command_address < image_prg_bytes_register;
                expected_address_valid =
                    command_address == next_prg_address;
            end
            LOADER_TARGET_CHR: begin
                declared_target_valid =
                    target_valid && !image_chr_is_ram_register;
                declared_address_valid =
                    command_address < image_chr_bytes_register;
                expected_address_valid =
                    command_address == next_chr_address;
            end
            default: begin
                declared_target_valid = 1'b0;
                declared_address_valid = 1'b0;
                expected_address_valid = 1'b0;
            end
        endcase
    end

    always_comb begin
        legal_active_write = !reset && command_valid &&
                             command == LOADER_COMMAND_WRITE &&
                             state_register == LOADER_STATE_LOADING &&
                             target_valid && address_valid;
        if (IMAGE_VALIDATION_ENABLE)
            legal_active_write = legal_active_write &&
                                 session_manifest_valid &&
                                 declared_target_valid &&
                                 declared_address_valid &&
                                 expected_address_valid;
    end

    // Invalid commands are accepted immediately so they receive a
    // deterministic disposition. A legal write applies downstream
    // backpressure directly to the upstream command channel.
    always_comb begin
        command_ready = 1'b0;
        if (!reset) begin
            if (legal_active_write)
                command_ready = storage_write_ready;
            else
                command_ready = 1'b1;
        end
    end

    assign command_accepted = command_valid && command_ready && !reset;

    assign storage_write_valid = legal_active_write;
    assign storage_write_target = command_target;
    assign storage_write_address = command_address;
    assign storage_write_data = command_data;

    // Reset-time output gating matches the repository's bus conventions.
    // Holding reset is fail-safe because no runtime image has been committed.
    assign state = reset ? LOADER_STATE_IDLE : state_register;
    assign busy = !reset && state_register == LOADER_STATE_LOADING;
    assign completed = !reset && state_register == LOADER_STATE_READY;
    assign error = !reset && state_register == LOADER_STATE_ERROR;
    assign error_code = reset ? LOADER_ERROR_NONE : error_register;
    assign nes_hold_reset = reset || state_register != LOADER_STATE_READY;
    assign image_valid = IMAGE_VALIDATION_ENABLE && completed;
    assign image_mapper = reset ? 8'h00 : image_mapper_register;
    assign image_prg_bytes = reset ? 16'h0000 : image_prg_bytes_register;
    assign image_chr_bytes = reset ? 16'h0000 : image_chr_bytes_register;
    assign image_chr_is_ram = !reset && image_chr_is_ram_register;
    assign image_mirroring = reset ? LOADER_MIRROR_VERTICAL :
                                     image_mirroring_register;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_register <= LOADER_STATE_IDLE;
            error_register <= LOADER_ERROR_NONE;
            write_seen <= 1'b0;
            session_manifest_valid <= 1'b0;
            image_mapper_register <= 8'h00;
            image_prg_bytes_register <= 16'h0000;
            image_chr_bytes_register <= 16'h0000;
            image_chr_is_ram_register <= 1'b0;
            image_mirroring_register <= LOADER_MIRROR_VERTICAL;
            next_prg_address <= 16'h0000;
            next_chr_address <= 16'h0000;
        end else if (command_accepted) begin
            // Preserve the first failure until reset or a fresh BEGIN.
            if (state_register == LOADER_STATE_ERROR &&
                command != LOADER_COMMAND_BEGIN) begin
                state_register <= LOADER_STATE_ERROR;
            end else begin
                case (command)
                    LOADER_COMMAND_BEGIN: begin
                        if (state_register == LOADER_STATE_LOADING) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_BEGIN_BUSY;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     begin_manifest_error !=
                                     LOADER_ERROR_NONE) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= begin_manifest_error;
                            write_seen <= 1'b0;
                            session_manifest_valid <= 1'b0;
                            image_mapper_register <= 8'h00;
                            image_prg_bytes_register <= 16'h0000;
                            image_chr_bytes_register <= 16'h0000;
                            image_chr_is_ram_register <= 1'b0;
                            image_mirroring_register <=
                                LOADER_MIRROR_VERTICAL;
                            next_prg_address <= 16'h0000;
                            next_chr_address <= 16'h0000;
                        end else begin
                            state_register <= LOADER_STATE_LOADING;
                            error_register <= LOADER_ERROR_NONE;
                            write_seen <= 1'b0;
                            next_prg_address <= 16'h0000;
                            next_chr_address <= 16'h0000;
                            if (IMAGE_VALIDATION_ENABLE) begin
                                session_manifest_valid <= 1'b1;
                                image_mapper_register <= manifest_mapper;
                                image_prg_bytes_register <=
                                    manifest_prg_bytes;
                                image_chr_bytes_register <=
                                    manifest_chr_bytes;
                                image_chr_is_ram_register <=
                                    manifest_chr_is_ram;
                                image_mirroring_register <=
                                    manifest_mirroring;
                            end else begin
                                session_manifest_valid <= 1'b0;
                            end
                        end
                    end

                    LOADER_COMMAND_WRITE: begin
                        if (state_register != LOADER_STATE_LOADING) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_WRONG_STATE;
                        end else if (!target_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_BAD_TARGET;
                        end else if (!address_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_BAD_ADDRESS;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     !session_manifest_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_INVALID_MANIFEST;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     !declared_target_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_BAD_TARGET;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     !declared_address_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_BAD_ADDRESS;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     !expected_address_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <=
                                LOADER_ERROR_UNEXPECTED_ADDRESS;
                        end else begin
                            // command_accepted also proves downstream ready.
                            write_seen <= 1'b1;
                            if (IMAGE_VALIDATION_ENABLE) begin
                                if (command_target == LOADER_TARGET_PRG)
                                    next_prg_address <=
                                        next_prg_address + 16'd1;
                                else
                                    next_chr_address <=
                                        next_chr_address + 16'd1;
                            end
                        end
                    end

                    LOADER_COMMAND_COMMIT: begin
                        if (state_register != LOADER_STATE_LOADING) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_WRONG_STATE;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     !session_manifest_valid) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_INVALID_MANIFEST;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     next_prg_address !=
                                     image_prg_bytes_register) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_PRG_INCOMPLETE;
                        end else if (IMAGE_VALIDATION_ENABLE &&
                                     next_chr_address !=
                                     image_chr_bytes_register) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_CHR_INCOMPLETE;
                        end else if (!IMAGE_VALIDATION_ENABLE &&
                                     !write_seen) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_EMPTY_LOAD;
                        end else begin
                            state_register <= LOADER_STATE_READY;
                            error_register <= LOADER_ERROR_NONE;
                        end
                    end

                    default: begin
                        state_register <= LOADER_STATE_ERROR;
                        error_register <= LOADER_ERROR_BAD_COMMAND;
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    logic backpressure_active;
    loader_target_t held_target;
    logic [LOADER_ADDRESS_BITS-1:0] held_address;
    logic [7:0] held_data;

    always_comb begin
        assert ($onehot({state == LOADER_STATE_IDLE,
                         state == LOADER_STATE_LOADING,
                         state == LOADER_STATE_READY,
                         state == LOADER_STATE_ERROR}));
        assert (!(busy && (completed || error)));
        assert (!(completed && error));
        if (storage_write_valid) begin
            assert (state_register == LOADER_STATE_LOADING);
            assert (command_valid && command == LOADER_COMMAND_WRITE);
            assert (target_valid && address_valid);
            assert (command_accepted == storage_write_ready);
            if (IMAGE_VALIDATION_ENABLE) begin
                assert (session_manifest_valid);
                assert (declared_target_valid && declared_address_valid);
                assert (expected_address_valid);
            end
        end
        if (completed) begin
            assert (!nes_hold_reset);
            if (IMAGE_VALIDATION_ENABLE) begin
                assert (session_manifest_valid);
                assert (next_prg_address == image_prg_bytes_register);
                assert (next_chr_address == image_chr_bytes_register);
            end else begin
                assert (write_seen);
            end
        end
        assert (image_valid == (IMAGE_VALIDATION_ENABLE && completed));
        if (busy || error || state == LOADER_STATE_IDLE)
            assert (nes_hold_reset);
        if (reset) begin
            assert (!command_ready && !command_accepted);
            assert (!storage_write_valid);
            assert (!busy && !completed && !error);
            assert (!image_valid);
            assert (nes_hold_reset);
        end
    end

    // Standard ready/valid rule: once a legal write is backpressured, its
    // valid level and complete payload remain stable until acceptance.
    always_ff @(posedge clk) begin
        if (reset) begin
            backpressure_active <= 1'b0;
            held_target <= LOADER_TARGET_NONE;
            held_address <= '0;
            held_data <= 8'h00;
        end else begin
            if (backpressure_active) begin
                assert (command_valid && command == LOADER_COMMAND_WRITE);
                assert (command_target == held_target);
                assert (command_address == held_address);
                assert (command_data == held_data);
            end

            if (storage_write_valid && !storage_write_ready) begin
                if (!backpressure_active) begin
                    held_target <= command_target;
                    held_address <= command_address;
                    held_data <= command_data;
                end
                backpressure_active <= 1'b1;
            end else begin
                backpressure_active <= 1'b0;
            end
        end
    end
`endif
endmodule
