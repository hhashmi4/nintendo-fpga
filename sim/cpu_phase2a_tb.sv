`timescale 1ns/1ps

// Phase 2A regression: reset values, deterministic bus state, and enable
// gating remain invariant as later execution states become active.
module cpu_phase2a_tb;
    import cpu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data = 8'h02;
    logic bus_write_enable;
    logic bus_valid;
    logic [7:0] debug_a;
    logic [7:0] debug_x;
    logic [7:0] debug_y;
    logic [7:0] debug_sp;
    logic [15:0] debug_pc;
    cpu_status_t debug_status;
    logic [7:0] debug_instruction;
    cpu_execution_state_t debug_execution_state;
    cpu_instruction_t debug_decoded_instruction;
    logic [3:0] debug_addressing_mode;
    logic [15:0] debug_effective_address;
    logic debug_page_cross;
    logic debug_page_cross_valid;

    cpu_core dut (
        .clk                       (clk),
        .reset                     (reset),
        .cpu_enable                (cpu_enable),
        .bus_address               (bus_address),
        .bus_write_data            (bus_write_data),
        .bus_read_data             (bus_read_data),
        .bus_write_enable          (bus_write_enable),
        .bus_valid                 (bus_valid),
        .debug_a                   (debug_a),
        .debug_x                   (debug_x),
        .debug_y                   (debug_y),
        .debug_sp                  (debug_sp),
        .debug_pc                  (debug_pc),
        .debug_status              (debug_status),
        .debug_instruction         (debug_instruction),
        .debug_execution_state     (debug_execution_state),
        .debug_decoded_instruction (debug_decoded_instruction),
        .debug_addressing_mode     (debug_addressing_mode),
        .debug_effective_address   (debug_effective_address),
        .debug_page_cross          (debug_page_cross),
        .debug_page_cross_valid    (debug_page_cross_valid)
    );

    always #10 clk <= !clk;

    task automatic sample_clock;
        @(posedge clk);
        #1;
        assert (!$isunknown({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                             debug_status, debug_instruction,
                             debug_execution_state,
                             debug_decoded_instruction,
                             debug_addressing_mode,
                             debug_effective_address, debug_page_cross,
                             debug_page_cross_valid, bus_address,
                             bus_write_data, bus_write_enable, bus_valid}))
            else $fatal(1, "unknown CPU or bus state after clock edge");
        assert (!bus_write_enable)
            else $fatal(1, "reset/unsupported regression asserted a write");
    endtask

    task automatic assert_reset_state;
        assert (debug_a == CPU_RESET_A && debug_x == CPU_RESET_X &&
                debug_y == CPU_RESET_Y && debug_sp == CPU_RESET_SP &&
                debug_pc == CPU_RESET_PC &&
                debug_status == CPU_RESET_STATUS &&
                debug_instruction == CPU_RESET_IR)
            else $fatal(1, "architectural reset value mismatch");
        assert (debug_execution_state == CPU_STATE_RESET &&
                debug_decoded_instruction == CPU_INSTR_INVALID &&
                debug_addressing_mode == CPU_ADDR_IMPLIED)
            else $fatal(1, "execution reset value mismatch");
        assert ({bus_valid, bus_write_enable} == 2'b00 &&
                bus_address == CPU_RESET_PC && bus_write_data == 8'h00)
            else $fatal(1, "bus reset outputs are not deterministic");
    endtask

    initial begin
        $dumpfile("build/sim/cpu_phase2a.fst");
        $dumpvars(0, cpu_phase2a_tb);

        assert ($bits(debug_pc) == 16 && $bits(debug_sp) == 8)
            else $fatal(1, "architectural register width mismatch");

        #1;
        assert (!bus_valid && !bus_write_enable &&
                bus_address == CPU_RESET_PC)
            else $fatal(1, "bus is not deterministic before reset edge");

        sample_clock();
        assert_reset_state();
        repeat (2) begin
            sample_clock();
            assert_reset_state();
        end

        // Synchronous reset release cannot progress without cpu_enable.
        reset = 1'b0;
        repeat (4) begin
            sample_clock();
            assert_reset_state();
        end

        cpu_enable = 1'b1;
        sample_clock();
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == CPU_RESET_PC && bus_valid &&
                bus_address == CPU_RESET_PC)
            else $fatal(1, "first enable did not enter FETCH deterministically");

        // FETCH and every architectural field hold while disabled.
        cpu_enable = 1'b0;
        repeat (4) begin
            sample_clock();
            assert (debug_execution_state == CPU_STATE_FETCH &&
                    debug_pc == CPU_RESET_PC &&
                    debug_instruction == CPU_RESET_IR &&
                    debug_a == CPU_RESET_A && debug_x == CPU_RESET_X &&
                    debug_y == CPU_RESET_Y && debug_sp == CPU_RESET_SP &&
                    debug_status == CPU_RESET_STATUS &&
                    bus_valid && bus_address == CPU_RESET_PC)
                else $fatal(1, "state changed while cpu_enable was low");
        end

        // An unsupported byte exercises real fetch/PC progression without
        // introducing any architectural side effect or memory write.
        cpu_enable = 1'b1;
        sample_clock();
        assert (debug_execution_state == CPU_STATE_DECODE &&
                debug_instruction == 8'h02 && debug_pc == 16'h0001)
            else $fatal(1, "opcode fetch did not advance PC exactly once");

        cpu_enable = 1'b0;
        repeat (3) begin
            sample_clock();
            assert (debug_execution_state == CPU_STATE_DECODE &&
                    debug_pc == 16'h0001 && debug_instruction == 8'h02)
                else $fatal(1, "decode advanced without cpu_enable");
        end

        cpu_enable = 1'b1;
        sample_clock();
        assert (debug_execution_state == CPU_STATE_TRAP &&
                debug_decoded_instruction == CPU_INSTR_INVALID &&
                !bus_valid && !bus_write_enable)
            else $fatal(1, "unsupported opcode did not enter inert trap");
        repeat (3) begin
            sample_clock();
            assert (debug_execution_state == CPU_STATE_TRAP &&
                    debug_pc == 16'h0001 && !bus_valid && !bus_write_enable)
                else $fatal(1, "trap state was not deterministic");
        end

        // Reassertion restores the exact Phase 2A architectural reset.
        reset = 1'b1;
        sample_clock();
        assert_reset_state();
        reset = 1'b0;
        cpu_enable = 1'b0;
        repeat (2) begin
            sample_clock();
            assert_reset_state();
        end

        $display("PASS: Phase 2A reset, enable gating, and deterministic bus regression");
        $finish;
    end
endmodule
