`timescale 1ns/1ps

// FPGA-side logical runtime-loader protocol. The caller and downstream
// storage adapter use this same clock. A future physical HPS bridge owns CDC
// into this domain; this module neither receives asynchronous pulses nor
// accesses the NES CPU bus.
module nes_runtime_loader (
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
    output logic                                      nes_hold_reset
);
    import nes_runtime_loader_pkg::*;

    loader_state_t state_register;
    loader_error_t error_register;
    logic write_seen;
    logic target_valid;
    logic address_valid;
    logic legal_active_write;

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

    assign legal_active_write = !reset && command_valid &&
                                command == LOADER_COMMAND_WRITE &&
                                state_register == LOADER_STATE_LOADING &&
                                target_valid && address_valid;

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

    always_ff @(posedge clk) begin
        if (reset) begin
            state_register <= LOADER_STATE_IDLE;
            error_register <= LOADER_ERROR_NONE;
            write_seen <= 1'b0;
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
                        end else begin
                            state_register <= LOADER_STATE_LOADING;
                            error_register <= LOADER_ERROR_NONE;
                            write_seen <= 1'b0;
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
                        end else begin
                            // command_accepted also proves downstream ready.
                            write_seen <= 1'b1;
                        end
                    end

                    LOADER_COMMAND_COMMIT: begin
                        if (state_register != LOADER_STATE_LOADING) begin
                            state_register <= LOADER_STATE_ERROR;
                            error_register <= LOADER_ERROR_WRONG_STATE;
                        end else if (!write_seen) begin
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
        end
        if (completed) begin
            assert (!nes_hold_reset);
            assert (write_seen);
        end
        if (busy || error || state == LOADER_STATE_IDLE)
            assert (nes_hold_reset);
        if (reset) begin
            assert (!command_ready && !command_accepted);
            assert (!storage_write_valid);
            assert (!busy && !completed && !error);
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
