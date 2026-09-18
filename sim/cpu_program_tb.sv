`timescale 1ns/1ps

// Verification-only flat 64 KiB CPU program runner. This is deliberately not
// an NES memory map and has no place in synthesis or the board top level.
module cpu_program_tb;
    import cpu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data, bus_read_data;
    logic bus_write_enable, bus_valid;
    logic [7:0] debug_a, debug_x, debug_y, debug_sp;
    logic [15:0] debug_pc;
    cpu_status_t debug_status;
    logic [7:0] debug_instruction;
    cpu_execution_state_t debug_execution_state;
    cpu_instruction_t debug_decoded_instruction;
    logic [3:0] debug_addressing_mode;
    logic [15:0] debug_effective_address;
    logic debug_page_cross, debug_page_cross_valid;
    logic [31:0] memory_write_count;
    logic [15:0] last_write_address;
    logic [7:0] last_write_data;

    string program_file;
    int unsigned start_pc;
    int unsigned pass_pc;
    int unsigned max_cycles;
    int unsigned logical_cycles;
    int unsigned pass_hits;
    int unsigned same_pc_hits;
    logic [15:0] previous_fetch_pc;

    cpu_core dut (
        .clk(clk), .reset(reset), .cpu_enable(cpu_enable), .nmi(1'b0), .irq(1'b0),
        .bus_address(bus_address), .bus_write_data(bus_write_data),
        .bus_read_data(bus_read_data), .bus_write_enable(bus_write_enable),
        .bus_valid(bus_valid), .debug_a(debug_a), .debug_x(debug_x),
        .debug_y(debug_y), .debug_sp(debug_sp), .debug_pc(debug_pc),
        .debug_status(debug_status), .debug_instruction(debug_instruction),
        .debug_execution_state(debug_execution_state),
        .debug_decoded_instruction(debug_decoded_instruction),
        .debug_addressing_mode(debug_addressing_mode),
        .debug_effective_address(debug_effective_address),
        .debug_page_cross(debug_page_cross),
        .debug_page_cross_valid(debug_page_cross_valid)
    );

    cpu_test_memory memory_model (
        .clk(clk), .reset(reset), .cpu_enable(cpu_enable),
        .address(bus_address), .write_data(bus_write_data),
        .write_enable(bus_write_enable), .valid(bus_valid),
        .read_data(bus_read_data), .write_count(memory_write_count),
        .last_write_address(last_write_address),
        .last_write_data(last_write_data)
    );

    always #5 clk <= !clk;

    task automatic step_cpu;
        @(posedge clk);
        #1;
        assert (!$isunknown({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                             debug_status, debug_instruction,
                             debug_execution_state, debug_decoded_instruction,
                             debug_addressing_mode, debug_effective_address,
                             debug_page_cross, debug_page_cross_valid,
                             bus_address, bus_write_data, bus_write_enable,
                             bus_valid, bus_read_data, memory_write_count,
                             last_write_address, last_write_data}))
            else $fatal(1, "X/Z during flat CPU program");
        assert (!bus_write_enable || bus_valid);
    endtask

    initial begin
        assert ($value$plusargs("PROGRAM=%s", program_file))
            else $fatal(1, "PROGRAM=<readmemh file> is required");
        assert ($value$plusargs("START_PC=%h", start_pc))
            else $fatal(1, "START_PC=<hex> is required");
        assert ($value$plusargs("PASS_PC=%h", pass_pc))
            else $fatal(1, "PASS_PC=<hex> is required");
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 100_000_000;
        assert (start_pc <= 16'hFFFF && pass_pc <= 16'hFFFF && max_cycles > 0);

        $readmemh(program_file, memory_model.memory);
        memory_model.memory[CPU_VECTOR_RESET_LOW] = start_pc[7:0];
        memory_model.memory[CPU_VECTOR_RESET_LOW + 16'd1] = start_pc[15:8];

        repeat (2) step_cpu();
        reset = 1'b0;
        cpu_enable = 1'b1;
        repeat (7) step_cpu();
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == start_pc[15:0])
            else $fatal(1, "program reset/start mismatch");

        logical_cycles = 0;
        pass_hits = 0;
        same_pc_hits = 0;
        previous_fetch_pc = 16'hFFFF;
        while (logical_cycles < max_cycles) begin
            step_cpu();
            logical_cycles++;
            if (debug_execution_state == CPU_STATE_TRAP)
                $fatal(1, "unsupported opcode %02h trapped at PC=%04h after %0d cycles",
                       debug_instruction, debug_pc, logical_cycles);
            if (debug_execution_state == CPU_STATE_FETCH) begin
                if (debug_pc == pass_pc[15:0]) begin
                    pass_hits++;
                    if (pass_hits == 2) begin
                        $display("PASS: flat CPU program reached stable success PC=%04h in %0d enabled cycles (%0d writes)",
                                 debug_pc, logical_cycles, memory_write_count);
                        $finish;
                    end
                end else begin
                    pass_hits = 0;
                end
                if (debug_pc == previous_fetch_pc)
                    same_pc_hits++;
                else
                    same_pc_hits = 0;
                if (same_pc_hits == 4 && debug_pc != pass_pc[15:0])
                    $fatal(1, "program entered failure loop at PC=%04h after %0d cycles",
                           debug_pc, logical_cycles);
                previous_fetch_pc = debug_pc;
            end
        end
        $fatal(1, "program timeout after %0d enabled cycles PC=%04h",
               logical_cycles, debug_pc);
    end
endmodule
