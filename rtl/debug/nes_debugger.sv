`timescale 1ns/1ps

// Execution authorization only. CPU/PPU/DMA retain their existing clocks,
// state machines, bus cycles, and relative timing. The registered debugger
// state is the only new input to the scheduler enable.
module nes_debugger (
    input logic clk,
    input logic reset,
    input logic command_valid,
    input logic [2:0] command,
    input logic [15:0] command_sequence,
    output logic command_done,
    output logic [2:0] response_state,
    output logic [1:0] response_result,
    input logic snapshot_ready,
    input logic cpu_enable,
    input logic [5:0] cpu_execution_state,
    input logic [15:0] cpu_pc,
    input logic dma_active,
    input logic ppu_enable,
    input logic frame_start,
    output logic scheduler_authorized,
    output logic status_changed,
    output nes_debug_snapshot_pkg::nes_debugger_snapshot_t status
);
    import cpu_pkg::*;
    import nes_debugger_pkg::*;
    logic command_seen;
    logic previous_fetch;
    logic instruction_started;
    logic frame_crossed;
    logic safe_boundary;

    assign scheduler_authorized = status.state != DBG_PAUSED;
    // Never change authorization on an edge that accepts a CPU bus cycle.
    // After the final instruction/DMA cycle, the scheduler has at least two
    // fabric edges before its next CPU slot, including at nes_enable=1.
    assign safe_boundary = !dma_active && !cpu_enable &&
        (cpu_execution_state == CPU_STATE_FETCH ||
         cpu_execution_state == CPU_STATE_TRAP);

    always_ff @(posedge clk) begin
        if (reset) begin
            status <= '0; // state 0 = RUNNING, counters and sequence zero
            command_seen <= 1'b0;
            command_done <= 1'b0;
            response_state <= DBG_RUNNING;
            response_result <= DBG_OK;
            previous_fetch <= 1'b0;
            instruction_started <= 1'b0;
            frame_crossed <= 1'b0;
            status_changed <= 1'b0;
        end else begin
            command_done <= 1'b0;
            status_changed <= 1'b0;
            previous_fetch <= cpu_enable &&
                              cpu_execution_state == CPU_STATE_FETCH;
            if (!command_valid)
                command_seen <= 1'b0;

            // Interrupt entry leaves FETCH for INTERRUPT_DUMMY. It does not
            // count as the instruction owed by a STEP-I token. BRK, including
            // its vector/stack sequence, does count as one instruction.
            if (status.state == DBG_INSTRUCTION_STEP && previous_fetch &&
                cpu_execution_state != CPU_STATE_INTERRUPT_DUMMY)
                instruction_started <= 1'b1;

            if (status.state == DBG_FRAME_STEP) begin
                if (frame_start)
                    frame_crossed <= 1'b1;
                if (frame_crossed && ppu_enable)
                    status.frame_overrun <= status.frame_overrun + 16'd1;
            end

            if (safe_boundary &&
                (status.state == DBG_PAUSE_REQUESTED ||
                 (status.state == DBG_INSTRUCTION_STEP && instruction_started) ||
                 (status.state == DBG_FRAME_STEP &&
                  (frame_crossed || frame_start)))) begin
                status.state <= DBG_PAUSED;
                status.pc_after <= cpu_pc;
                status_changed <= 1'b1;
                if (status.state == DBG_INSTRUCTION_STEP) begin
                    status.instruction_steps <= status.instruction_steps + 16'd1;
                    status.boundary <= 3'd2;
                end else if (status.state == DBG_FRAME_STEP) begin
                    status.frame_steps <= status.frame_steps + 16'd1;
                    status.boundary <= 3'd3;
                end else begin
                    status.boundary <= 3'd1;
                end
            end

            // ACK means command disposition, not asynchronous execution
            // completion. Busy commands are explicitly rejected, never queued.
            // A command arriving just after pause waits for the coherent pause
            // capture to cross before it can resume or step the machine.
            if (command_valid && !command_seen &&
                (status.state != DBG_PAUSED || snapshot_ready)) begin
                command_seen <= 1'b1;
                command_done <= 1'b1;
                response_state <= status.state;
                response_result <= DBG_OK;
                status.sequence_id <= command_sequence;
                status.result <= DBG_OK;
                status_changed <= 1'b1;
                if (command > DBG_STEP_F) begin
                    response_result <= DBG_BAD_COMMAND;
                    status.result <= DBG_BAD_COMMAND;
                end else if (status.state != DBG_RUNNING &&
                             status.state != DBG_PAUSED) begin
                    response_result <= DBG_BUSY;
                    status.result <= DBG_BUSY;
                end else if (command >= DBG_STEP_I &&
                             status.state != DBG_PAUSED) begin
                    response_result <= DBG_WRONG_STATE;
                    status.result <= DBG_WRONG_STATE;
                end else begin
                    status.last_command <= command;
                    case (command)
                        DBG_RUN: begin
                            status.state <= DBG_RUNNING;
                            response_state <= DBG_RUNNING;
                        end
                        DBG_PAUSE: if (status.state == DBG_RUNNING) begin
                            status.state <= DBG_PAUSE_REQUESTED;
                            response_state <= DBG_PAUSE_REQUESTED;
                        end
                        DBG_STEP_I: begin
                            status.state <= DBG_INSTRUCTION_STEP;
                            response_state <= DBG_INSTRUCTION_STEP;
                            instruction_started <= 1'b0;
                            status.pc_before <= cpu_pc;
                            status.boundary <= 3'd0;
                        end
                        DBG_STEP_F: begin
                            status.state <= DBG_FRAME_STEP;
                            response_state <= DBG_FRAME_STEP;
                            frame_crossed <= 1'b0;
                            status.frame_overrun <= 16'd0;
                            status.pc_before <= cpu_pc;
                            status.boundary <= 3'd0;
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
