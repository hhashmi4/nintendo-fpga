`timescale 1ns/1ps

module cpu_core #(
    // Production remains at the Phase 2A placeholder PC. Verification may
    // override this parameter to keep test programs out of zero page.
    parameter logic [15:0] INITIAL_PC = cpu_pkg::CPU_RESET_PC
) (
    input  logic clk,
    input  logic reset,
    input  logic cpu_enable,

    output logic [15:0] bus_address,
    output logic [7:0]  bus_write_data,
    input  logic [7:0]  bus_read_data,
    output logic        bus_write_enable,
    output logic        bus_valid,

    // Read-only architectural visibility for verification and bring-up.
    output logic [7:0]  debug_a,
    output logic [7:0]  debug_x,
    output logic [7:0]  debug_y,
    output logic [7:0]  debug_sp,
    output logic [15:0] debug_pc,
    output cpu_pkg::cpu_status_t debug_status,
    output logic [7:0]  debug_instruction,
    output cpu_pkg::cpu_execution_state_t debug_execution_state,
    output cpu_pkg::cpu_instruction_t debug_decoded_instruction,
    output logic [3:0]  debug_addressing_mode,
    output logic [15:0] debug_effective_address,
    output logic        debug_page_cross,
    output logic        debug_page_cross_valid
);
    import cpu_pkg::*;

    cpu_decode_result_t   decoded;
    cpu_address_request_t address_request;
    // The shared Phase 2C result also carries branch/accumulator metadata that
    // this deliberately limited instruction subset cannot consume.
    /* verilator lint_off UNUSEDSIGNAL */
    cpu_address_result_t address_response;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [1:0] operand_bytes;
    logic       instruction_is_load;
    logic       instruction_is_store;
    logic [7:0] operand_low;
    logic [7:0] operand_high;
    logic [7:0] pointer_low;
    logic [7:0] pointer_high;
    logic       pointer_data_valid;
    logic [7:0] data_latch;

    cpu_decoder decoder (
        .opcode  (debug_instruction),
        .decoded (decoded)
    );

    cpu_address_gen address_generator (
        .request  (address_request),
        .response (address_response)
    );

    always_comb begin
        address_request                    = '0;
        address_request.addressing_mode    = debug_addressing_mode;
        address_request.base_address       = {operand_high, operand_low};
        address_request.operand_byte       = operand_low;
        address_request.x_index            = debug_x;
        address_request.y_index            = debug_y;
        address_request.pointer_low_byte   = pointer_low;
        address_request.pointer_high_byte  = pointer_high;
        address_request.pointer_data_valid = pointer_data_valid;
    end

    // The synchronized platform reset has priority over cpu_enable. Outside
    // reset, every sequential CPU field changes only on a CPU enable pulse.
    always_ff @(posedge clk) begin
        if (reset) begin
            debug_a                   <= CPU_RESET_A;
            debug_x                   <= CPU_RESET_X;
            debug_y                   <= CPU_RESET_Y;
            debug_sp                  <= CPU_RESET_SP;
            debug_pc                  <= INITIAL_PC;
            debug_status              <= cpu_status_normalize(CPU_RESET_STATUS);
            debug_instruction         <= CPU_RESET_IR;
            debug_execution_state     <= CPU_STATE_RESET;
            debug_decoded_instruction <= CPU_INSTR_INVALID;
            debug_addressing_mode     <= CPU_ADDR_IMPLIED;
            debug_effective_address   <= 16'h0000;
            debug_page_cross          <= 1'b0;
            debug_page_cross_valid    <= 1'b0;
            operand_bytes             <= 2'd0;
            instruction_is_load       <= 1'b0;
            instruction_is_store      <= 1'b0;
            operand_low               <= 8'h00;
            operand_high              <= 8'h00;
            pointer_low               <= 8'h00;
            pointer_high              <= 8'h00;
            pointer_data_valid        <= 1'b0;
            data_latch                <= 8'h00;
        end else if (cpu_enable) begin
            case (debug_execution_state)
                CPU_STATE_RESET: begin
                    // Reset-vector reads remain deferred. The first enabled
                    // step enters an opcode-fetch bus cycle.
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_FETCH: begin
                    debug_instruction      <= bus_read_data;
                    debug_pc               <= debug_pc + 16'd1;
                    debug_execution_state  <= CPU_STATE_DECODE;
                    debug_page_cross       <= 1'b0;
                    debug_page_cross_valid <= 1'b0;
                    operand_low            <= 8'h00;
                    operand_high           <= 8'h00;
                    pointer_low            <= 8'h00;
                    pointer_high           <= 8'h00;
                    pointer_data_valid     <= 1'b0;
                    data_latch             <= 8'h00;
                end

                CPU_STATE_DECODE: begin
                    debug_decoded_instruction <= decoded.instruction;
                    debug_addressing_mode     <= decoded.addressing_mode;
                    operand_bytes             <= decoded.operand_bytes;
                    instruction_is_load       <= decoded.is_load;
                    instruction_is_store      <= decoded.is_store;

                    if (!decoded.valid) begin
                        debug_execution_state <= CPU_STATE_TRAP;
                    end else if (decoded.is_transfer) begin
                        debug_execution_state <= CPU_STATE_TRANSFER;
                    end else begin
                        debug_execution_state <= CPU_STATE_OPERAND_LOW;
                    end
                end

                CPU_STATE_OPERAND_LOW: begin
                    operand_low <= bus_read_data;
                    debug_pc    <= debug_pc + 16'd1;
                    if (operand_bytes == 2'd2) begin
                        debug_execution_state <= CPU_STATE_OPERAND_HIGH;
                    end else begin
                        debug_execution_state <= CPU_STATE_ADDRESS;
                    end
                end

                CPU_STATE_OPERAND_HIGH: begin
                    operand_high          <= bus_read_data;
                    debug_pc              <= debug_pc + 16'd1;
                    debug_execution_state <= CPU_STATE_ADDRESS;
                end

                CPU_STATE_ADDRESS: begin
                    if (debug_addressing_mode == CPU_ADDR_IMMEDIATE) begin
                        if (address_response.immediate_valid) begin
                            data_latch <= address_response.immediate_value;
                            debug_execution_state <= CPU_STATE_WRITEBACK;
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else if (
                        debug_addressing_mode == CPU_ADDR_INDEXED_INDIRECT_X ||
                        debug_addressing_mode == CPU_ADDR_INDIRECT_INDEXED_Y
                    ) begin
                        if (!pointer_data_valid) begin
                            debug_execution_state <= CPU_STATE_POINTER_LOW;
                        end else if (address_response.effective_address_valid) begin
                            debug_effective_address <=
                                address_response.effective_address;
                            debug_page_cross <= address_response.page_cross;
                            debug_page_cross_valid <=
                                address_response.page_cross_valid;
                            if (instruction_is_load) begin
                                debug_execution_state <= CPU_STATE_MEMORY_READ;
                            end else if (instruction_is_store) begin
                                debug_execution_state <= CPU_STATE_MEMORY_WRITE;
                            end else begin
                                debug_execution_state <= CPU_STATE_TRAP;
                            end
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else if (address_response.effective_address_valid) begin
                        debug_effective_address <=
                            address_response.effective_address;
                        debug_page_cross <= address_response.page_cross;
                        debug_page_cross_valid <=
                            address_response.page_cross_valid;
                        if (instruction_is_load) begin
                            debug_execution_state <= CPU_STATE_MEMORY_READ;
                        end else if (instruction_is_store) begin
                            debug_execution_state <= CPU_STATE_MEMORY_WRITE;
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else begin
                        debug_execution_state <= CPU_STATE_TRAP;
                    end
                end

                CPU_STATE_POINTER_LOW: begin
                    pointer_low            <= bus_read_data;
                    debug_execution_state <= CPU_STATE_POINTER_HIGH;
                end

                CPU_STATE_POINTER_HIGH: begin
                    pointer_high           <= bus_read_data;
                    pointer_data_valid     <= 1'b1;
                    debug_execution_state <= CPU_STATE_ADDRESS;
                end

                CPU_STATE_MEMORY_READ: begin
                    data_latch             <= bus_read_data;
                    debug_execution_state <= CPU_STATE_WRITEBACK;
                end

                CPU_STATE_MEMORY_WRITE: begin
                    // The external bus consumes the sole write on this edge.
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_WRITEBACK: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_LDA: debug_a <= data_latch;
                        CPU_INSTR_LDX: debug_x <= data_latch;
                        CPU_INSTR_LDY: debug_y <= data_latch;
                        default: begin
                            // Decode prevents non-load writeback states.
                        end
                    endcase
                    debug_status.negative <= data_latch[7];
                    debug_status.zero     <= (data_latch == 8'h00);
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_TRANSFER: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_TAX: begin
                            debug_x               <= debug_a;
                            debug_status.negative <= debug_a[7];
                            debug_status.zero     <= (debug_a == 8'h00);
                        end

                        CPU_INSTR_TAY: begin
                            debug_y               <= debug_a;
                            debug_status.negative <= debug_a[7];
                            debug_status.zero     <= (debug_a == 8'h00);
                        end

                        CPU_INSTR_TXA: begin
                            debug_a               <= debug_x;
                            debug_status.negative <= debug_x[7];
                            debug_status.zero     <= (debug_x == 8'h00);
                        end

                        CPU_INSTR_TYA: begin
                            debug_a               <= debug_y;
                            debug_status.negative <= debug_y[7];
                            debug_status.zero     <= (debug_y == 8'h00);
                        end

                        CPU_INSTR_TSX: begin
                            debug_x               <= debug_sp;
                            debug_status.negative <= debug_sp[7];
                            debug_status.zero     <= (debug_sp == 8'h00);
                        end

                        CPU_INSTR_TXS: begin
                            debug_sp <= debug_x;
                        end

                        default: begin
                            // Decode prevents invalid transfer states.
                        end
                    endcase
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_TRAP: begin
                    // Unsupported opcode: safely halt until reset.
                    debug_execution_state <= CPU_STATE_TRAP;
                end

                default: begin
                    // Corrupt state cannot cause a write; fail closed.
                    debug_execution_state <= CPU_STATE_TRAP;
                end
            endcase
        end
    end

    // A bus cycle remains active between CPU enable pulses. The consumer must
    // commit a write once, on the enabled edge that completes MEMORY_WRITE.
    always_comb begin
        bus_address      = debug_pc;
        bus_write_data   = 8'h00;
        bus_write_enable = 1'b0;
        bus_valid        = 1'b0;

        if (reset) begin
            bus_address = INITIAL_PC;
        end else begin
            case (debug_execution_state)
                CPU_STATE_FETCH,
                CPU_STATE_OPERAND_LOW,
                CPU_STATE_OPERAND_HIGH: begin
                    bus_address = debug_pc;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_POINTER_LOW: begin
                    bus_address = address_response.pointer_low_address;
                    bus_valid   = address_response.pointer_addresses_valid;
                end

                CPU_STATE_POINTER_HIGH: begin
                    bus_address = address_response.pointer_high_address;
                    bus_valid   = address_response.pointer_addresses_valid;
                end

                CPU_STATE_MEMORY_READ: begin
                    bus_address = debug_effective_address;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_MEMORY_WRITE: begin
                    bus_address      = debug_effective_address;
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                    case (debug_decoded_instruction)
                        CPU_INSTR_STA: bus_write_data = debug_a;
                        CPU_INSTR_STX: bus_write_data = debug_x;
                        CPU_INSTR_STY: bus_write_data = debug_y;
                        default: begin
                            bus_write_data   = 8'h00;
                            bus_write_enable = 1'b0;
                            bus_valid        = 1'b0;
                        end
                    endcase
                end

                default: begin
                    // Internal-only states and TRAP have no bus cycle.
                end
            endcase
        end
    end
endmodule
