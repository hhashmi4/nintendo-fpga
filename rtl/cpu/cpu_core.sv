`timescale 1ns/1ps

module cpu_core (
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
    output cpu_pkg::cpu_execution_state_t debug_execution_state
);
    import cpu_pkg::*;

    // The synchronized platform reset has priority over cpu_enable. Outside
    // reset, every sequential CPU field changes only on a CPU enable pulse.
    always_ff @(posedge clk) begin
        if (reset) begin
            debug_a               <= CPU_RESET_A;
            debug_x               <= CPU_RESET_X;
            debug_y               <= CPU_RESET_Y;
            debug_sp              <= CPU_RESET_SP;
            debug_pc              <= CPU_RESET_PC;
            debug_status          <= cpu_status_normalize(CPU_RESET_STATUS);
            debug_instruction     <= CPU_RESET_IR;
            debug_execution_state <= CPU_STATE_RESET;
        end else if (cpu_enable) begin
            case (debug_execution_state)
                CPU_STATE_RESET: begin
                    // Reset-vector reads are deliberately deferred. The first
                    // enabled step merely enters the placeholder fetch state.
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_FETCH: begin
                    // Provide a real read-cycle boundary without interpreting
                    // the byte, advancing PC, or executing an instruction.
                    debug_instruction <= bus_read_data;
                end

                default: begin
                    // Later phases own these states. Recover deterministically
                    // if one is reached before its behavior is implemented.
                    debug_instruction     <= CPU_RESET_IR;
                    debug_execution_state <= CPU_STATE_RESET;
                end
            endcase
        end
    end

    // A read cycle remains active between CPU enable pulses so a future memory
    // interconnect can provide data before the next enabled rising edge.
    always_comb begin
        bus_address      = debug_pc;
        bus_write_data   = 8'h00;
        bus_write_enable = 1'b0;
        bus_valid        = 1'b0;

        if (reset) begin
            bus_address = CPU_RESET_PC;
        end else if (debug_execution_state == CPU_STATE_FETCH) begin
            bus_valid = 1'b1;
        end
    end
endmodule
