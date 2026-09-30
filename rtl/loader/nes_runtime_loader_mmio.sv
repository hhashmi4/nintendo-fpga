`timescale 1ns/1ps

// Software-facing 32-bit Avalon-MM register bank. A COMMAND write is a strobe:
// the staged payload is copied into a one-entry command bank exactly once and
// remains stable until the CDC channel reports loader acceptance.
module nes_runtime_loader_mmio (
    input  logic                                      clk,
    input  logic                                      reset,

    input  logic [5:0]                                avs_address,
    input  logic                                      avs_read,
    input  logic                                      avs_write,
    input  logic [31:0]                               avs_writedata,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [3:0]                                avs_byteenable,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic                                      avs_waitrequest,
    output logic [31:0]                               avs_readdata,
    output logic                                      avs_readdatavalid,

    output logic                                      command_submit,
    output nes_runtime_loader_pkg::loader_command_t   command,
    output nes_runtime_loader_pkg::loader_target_t    command_target,
    output logic [15:0]                               command_address,
    output logic [7:0]                                command_data,
    output logic                                      manifest_valid,
    output logic [7:0]                                manifest_mapper,
    output logic [15:0]                               manifest_prg_bytes,
    output logic [15:0]                               manifest_chr_bytes,
    output logic                                      manifest_chr_is_ram,
    output logic [1:0]                                manifest_mirroring,
    input  logic                                      command_channel_ready,
    input  logic                                      command_channel_busy,
    input  logic                                      command_done,
    input  nes_runtime_loader_pkg::loader_state_t     command_response_state,
    input  logic                                      command_response_error,
    input  nes_runtime_loader_pkg::loader_error_t     command_response_error_code,

    input  nes_runtime_loader_pkg::loader_state_t     status_loader_state,
    input  logic                                      status_loader_busy,
    input  logic                                      status_loader_ready,
    input  logic                                      status_image_valid,
    input  logic                                      status_runtime_active,
    input  logic                                      status_nes_hold_reset,
    input  logic                                      status_loader_error,
    input  logic                                      status_activation_in_progress
);
    import nes_runtime_loader_pkg::*;
    import nes_runtime_loader_mmio_pkg::*;

    loader_target_t staged_target;
    logic [15:0] staged_address;
    logic [7:0] staged_data;
    logic staged_manifest_valid;
    logic [7:0] staged_manifest_mapper;
    logic [15:0] staged_manifest_prg_bytes;
    logic [15:0] staged_manifest_chr_bytes;
    logic staged_manifest_chr_is_ram;
    logic [1:0] staged_manifest_mirroring;

    logic command_pending;
    logic submit_rejected;
    logic [31:0] completed_count;
    loader_state_t last_response_state;
    logic last_response_error;
    loader_error_t last_response_error_code;
    logic [31:0] read_data_mux;
    logic bridge_ready;

    assign avs_waitrequest = 1'b0;
    assign bridge_ready = !reset && !command_pending &&
                          !command_channel_busy && command_channel_ready;

    always_comb begin
        read_data_mux = 32'h00000000;
        case (avs_address)
            MMIO_REG_MAGIC:
                read_data_mux = MMIO_MAGIC;
            MMIO_REG_VERSION:
                read_data_mux = MMIO_VERSION;
            MMIO_REG_CAPABILITIES:
                read_data_mux = MMIO_CAPABILITIES;
            MMIO_REG_STATUS: begin
                read_data_mux[MMIO_STATUS_BRIDGE_READY_BIT] = bridge_ready;
                read_data_mux[MMIO_STATUS_COMMAND_PENDING_BIT] =
                    command_pending;
                read_data_mux[MMIO_STATUS_LOADER_BUSY_BIT] =
                    status_loader_busy;
                read_data_mux[MMIO_STATUS_LOADER_READY_BIT] =
                    status_loader_ready;
                read_data_mux[MMIO_STATUS_IMAGE_VALID_BIT] =
                    status_image_valid;
                read_data_mux[MMIO_STATUS_RUNTIME_ACTIVE_BIT] =
                    status_runtime_active;
                read_data_mux[MMIO_STATUS_NES_HELD_RESET_BIT] =
                    status_nes_hold_reset;
                read_data_mux[MMIO_STATUS_LOADER_ERROR_BIT] =
                    status_loader_error;
                read_data_mux[MMIO_STATUS_ACTIVATION_IN_PROGRESS_BIT] =
                    status_activation_in_progress;
                read_data_mux[MMIO_STATUS_SUBMIT_REJECTED_BIT] =
                    submit_rejected;
                read_data_mux[MMIO_STATUS_STATE_SHIFT +: 2] =
                    status_loader_state;
            end
            MMIO_REG_ERROR: begin
                read_data_mux[MMIO_ERROR_CODE_SHIFT +: 4] =
                    last_response_error_code;
                read_data_mux[MMIO_ERROR_SUBMIT_REJECTED_BIT] =
                    submit_rejected;
                // This bit makes a zero error register unambiguously mean
                // that the last completed command did not fail.
                read_data_mux[MMIO_ERROR_RESPONSE_FAILED_BIT] =
                    last_response_error;
                read_data_mux[MMIO_ERROR_STATE_SHIFT +: 2] =
                    last_response_state;
            end
            MMIO_REG_TARGET:
                read_data_mux[1:0] = staged_target;
            MMIO_REG_ADDRESS:
                read_data_mux[15:0] = staged_address;
            MMIO_REG_WRITE_DATA:
                read_data_mux[7:0] = staged_data;
            MMIO_REG_MANIFEST: begin
                read_data_mux[MMIO_MANIFEST_VALID_SHIFT] =
                    staged_manifest_valid;
                read_data_mux[MMIO_MANIFEST_CHR_IS_RAM_SHIFT] =
                    staged_manifest_chr_is_ram;
                read_data_mux[MMIO_MANIFEST_MIRRORING_SHIFT +: 2] =
                    staged_manifest_mirroring;
                read_data_mux[MMIO_MANIFEST_MAPPER_SHIFT +: 8] =
                    staged_manifest_mapper;
            end
            MMIO_REG_MANIFEST_PRG_BYTES:
                read_data_mux[15:0] = staged_manifest_prg_bytes;
            MMIO_REG_MANIFEST_CHR_BYTES:
                read_data_mux[15:0] = staged_manifest_chr_bytes;
            MMIO_REG_COMPLETED_COUNT:
                read_data_mux = completed_count;
            default:
                read_data_mux = 32'h00000000;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            avs_readdata <= 32'h00000000;
            avs_readdatavalid <= 1'b0;
            command_submit <= 1'b0;
            command <= LOADER_COMMAND_BEGIN;
            command_target <= LOADER_TARGET_NONE;
            command_address <= 16'h0000;
            command_data <= 8'h00;
            manifest_valid <= 1'b0;
            manifest_mapper <= 8'h00;
            manifest_prg_bytes <= 16'h0000;
            manifest_chr_bytes <= 16'h0000;
            manifest_chr_is_ram <= 1'b0;
            manifest_mirroring <= LOADER_MIRROR_VERTICAL;
            staged_target <= LOADER_TARGET_NONE;
            staged_address <= 16'h0000;
            staged_data <= 8'h00;
            staged_manifest_valid <= 1'b0;
            staged_manifest_mapper <= 8'h00;
            staged_manifest_prg_bytes <= 16'h0000;
            staged_manifest_chr_bytes <= 16'h0000;
            staged_manifest_chr_is_ram <= 1'b0;
            staged_manifest_mirroring <= LOADER_MIRROR_VERTICAL;
            command_pending <= 1'b0;
            submit_rejected <= 1'b0;
            completed_count <= 32'h00000000;
            last_response_state <= LOADER_STATE_IDLE;
            last_response_error <= 1'b0;
            last_response_error_code <= LOADER_ERROR_NONE;
        end else begin
            avs_readdatavalid <= avs_read;
            if (avs_read)
                avs_readdata <= read_data_mux;
            command_submit <= 1'b0;

            if (command_done) begin
                command_pending <= 1'b0;
                completed_count <= completed_count + 32'd1;
                last_response_state <= command_response_state;
                last_response_error <= command_response_error;
                last_response_error_code <= command_response_error_code;
            end

            if (avs_write) begin
                case (avs_address)
                    MMIO_REG_TARGET: begin
                        if (avs_byteenable[0])
                            staged_target <= loader_target_t'(avs_writedata[1:0]);
                    end
                    MMIO_REG_ADDRESS: begin
                        if (avs_byteenable[0])
                            staged_address[7:0] <= avs_writedata[7:0];
                        if (avs_byteenable[1])
                            staged_address[15:8] <= avs_writedata[15:8];
                    end
                    MMIO_REG_WRITE_DATA: begin
                        if (avs_byteenable[0])
                            staged_data <= avs_writedata[7:0];
                    end
                    MMIO_REG_MANIFEST: begin
                        if (avs_byteenable[0]) begin
                            staged_manifest_valid <=
                                avs_writedata[MMIO_MANIFEST_VALID_SHIFT];
                            staged_manifest_chr_is_ram <=
                                avs_writedata[MMIO_MANIFEST_CHR_IS_RAM_SHIFT];
                            staged_manifest_mirroring <= avs_writedata[
                                MMIO_MANIFEST_MIRRORING_SHIFT +: 2];
                        end
                        if (avs_byteenable[1])
                            staged_manifest_mapper <= avs_writedata[
                                MMIO_MANIFEST_MAPPER_SHIFT +: 8];
                    end
                    MMIO_REG_MANIFEST_PRG_BYTES: begin
                        if (avs_byteenable[0])
                            staged_manifest_prg_bytes[7:0] <=
                                avs_writedata[7:0];
                        if (avs_byteenable[1])
                            staged_manifest_prg_bytes[15:8] <=
                                avs_writedata[15:8];
                    end
                    MMIO_REG_MANIFEST_CHR_BYTES: begin
                        if (avs_byteenable[0])
                            staged_manifest_chr_bytes[7:0] <=
                                avs_writedata[7:0];
                        if (avs_byteenable[1])
                            staged_manifest_chr_bytes[15:8] <=
                                avs_writedata[15:8];
                    end
                    MMIO_REG_CONTROL: begin
                        if (avs_byteenable[0] && avs_writedata[
                            MMIO_CONTROL_CLEAR_SUBMIT_REJECTED_BIT])
                            submit_rejected <= 1'b0;
                    end
                    MMIO_REG_COMMAND: begin
                        if (bridge_ready && avs_byteenable[0] &&
                            avs_writedata[31:2] == 30'd0) begin
                            command <= loader_command_t'(avs_writedata[1:0]);
                            command_target <= staged_target;
                            command_address <= staged_address;
                            command_data <= staged_data;
                            manifest_valid <= staged_manifest_valid;
                            manifest_mapper <= staged_manifest_mapper;
                            manifest_prg_bytes <= staged_manifest_prg_bytes;
                            manifest_chr_bytes <= staged_manifest_chr_bytes;
                            manifest_chr_is_ram <=
                                staged_manifest_chr_is_ram;
                            manifest_mirroring <=
                                staged_manifest_mirroring;
                            command_submit <= 1'b1;
                            command_pending <= 1'b1;
                        end else begin
                            submit_rejected <= 1'b1;
                        end
                    end
                    default: begin
                        // Writes to read-only and reserved words are ignored.
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (!(command_submit && !command_pending));
        assert (!(bridge_ready && command_pending));
        assert (!(avs_read && avs_write));
    end
`endif
endmodule
