`timescale 1ns/1ps

module cpu_board_diag_tb;
    import cpu_board_diag_pkg::*;
    import cpu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic debug_mode = 1'b1;
    logic [1:0] run_phase = '0;
    logic run_cpu_enable;
    logic cpu_enable;
    logic pass;
    logic fail;
    logic [7:0] failure_code;
    logic cpu_alive;
    logic write_activity;
    logic irq_observed;
    logic nmi_observed;
    logic stall_active;
    logic stall_tested;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data;
    logic bus_write_enable;
    logic bus_valid;
    logic [15:0] debug_pc;
    logic [7:0] debug_instruction;
    logic [15:0] observed_pc;
    logic [7:0] observed_instruction;

    int unsigned clock_cycles;
    int unsigned enabled_cycles;
    int unsigned suppressed_run_pulses;
    int unsigned stack_reads;
    int unsigned stack_writes;
    int unsigned rmw_writes;
    logic reset_vector_low_seen;
    logic reset_vector_high_seen;
    logic page_cross_write_seen;
    logic page_cross_read_seen;
    logic result_signature_seen;

    assign run_cpu_enable = run_phase == 2'd0;

    cpu_board_diag #(
        .DEBUG_DIVIDER(4),
        .STALL_CYCLES(24),
        .NMI_PULSE_CYCLES(3),
        .WRITE_STRETCH_CYCLES(8)
    ) dut (
        .clk(clk),
        .reset(reset),
        .run_cpu_enable(run_cpu_enable),
        .debug_mode(debug_mode),
        .cpu_enable(cpu_enable),
        .pass(pass),
        .fail(fail),
        .failure_code(failure_code),
        .cpu_alive(cpu_alive),
        .write_activity(write_activity),
        .irq_observed(irq_observed),
        .nmi_observed(nmi_observed),
        .stall_active(stall_active),
        .stall_tested(stall_tested),
        .bus_address(bus_address),
        .bus_write_data(bus_write_data),
        .bus_read_data(bus_read_data),
        .bus_write_enable(bus_write_enable),
        .bus_valid(bus_valid),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .observed_pc(observed_pc),
        .observed_instruction(observed_instruction)
    );

    always #5 clk <= !clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            run_phase <= '0;
        end else begin
            run_phase <= run_phase + 1'b1;
        end
    end

    always @(posedge clk) begin
        clock_cycles++;
        #1;
        assert (!$isunknown({cpu_enable, pass, fail, failure_code,
                             irq_observed, nmi_observed, stall_active,
                             stall_tested, bus_address, bus_write_data,
                             bus_read_data, bus_write_enable, bus_valid,
                             debug_pc, debug_instruction, observed_pc,
                             observed_instruction}))
            else $fatal(1, "X/Z in Phase 2K diagnostic");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write without valid bus cycle");
        if (stall_active) begin
            assert (!cpu_enable)
                else $fatal(1, "cpu_enable asserted during forced stall");
            if (run_cpu_enable && !debug_mode) suppressed_run_pulses++;
        end
        if (cpu_enable) begin
            enabled_cycles++;
            if (bus_valid && !bus_write_enable) begin
                if (bus_address == CPU_VECTOR_RESET_LOW)
                    reset_vector_low_seen = 1'b1;
                if (bus_address == CPU_VECTOR_RESET_LOW + 16'd1)
                    reset_vector_high_seen = 1'b1;
                if (bus_address[15:8] == 8'h01) stack_reads++;
                if (bus_address == 16'h0500) page_cross_read_seen = 1'b1;
            end
            if (bus_valid && bus_write_enable) begin
                if (bus_address[15:8] == 8'h01) stack_writes++;
                if (bus_address == 16'h0023) rmw_writes++;
                if (bus_address == 16'h0500 && bus_write_data == 8'h77)
                    page_cross_write_seen = 1'b1;
                if (bus_address == CPU_DIAG_RESULT_ADDRESS &&
                    bus_write_data == CPU_DIAG_PASS_SIGNATURE)
                    result_signature_seen = 1'b1;
            end
        end
    end

    initial begin
        int unsigned first_pulse_cycle;
        int unsigned second_pulse_cycle;
        int unsigned pass_enabled_cycle;

        $dumpfile("build/sim/cpu_board_diag.fst");
        $dumpvars(0, cpu_board_diag_tb);

        clock_cycles = 0;
        enabled_cycles = 0;
        suppressed_run_pulses = 0;
        stack_reads = 0;
        stack_writes = 0;
        rmw_writes = 0;
        reset_vector_low_seen = 1'b0;
        reset_vector_high_seen = 1'b0;
        page_cross_write_seen = 1'b0;
        page_cross_read_seen = 1'b0;
        result_signature_seen = 1'b0;

        // Prove that debug mode creates clock-enable pulses, not a clock.
        repeat (4) @(posedge clk);
        reset = 1'b0;
        do @(posedge clk); while (!cpu_enable);
        first_pulse_cycle = clock_cycles;
        do @(posedge clk); while (!cpu_enable);
        second_pulse_cycle = clock_cycles;
        assert (second_pulse_cycle - first_pulse_cycle == 4)
            else $fatal(1, "debug enable spacing mismatch: %0d",
                        second_pulse_cycle - first_pulse_cycle);

        // Restart cleanly in automatic run mode and execute the exact ROM
        // synthesized into the board image.
        reset = 1'b1;
        debug_mode = 1'b0;
        repeat (4) @(posedge clk);
        reset = 1'b0;

        while (!pass && !fail && clock_cycles < 200_000) begin
            @(posedge clk);
        end
        #1;
        assert (!fail)
            else $fatal(1, "Phase 2K diagnostic failed with code %02h PC=%04h",
                        failure_code, debug_pc);
        assert (pass)
            else $fatal(1, "Phase 2K diagnostic timed out PC=%04h IR=%02h",
                        debug_pc, debug_instruction);
        pass_enabled_cycle = enabled_cycles;

        assert (observed_pc == CPU_DIAG_PASS_LOOP &&
                observed_instruction == 8'h4C)
            else $fatal(1, "pass loop observation mismatch PC=%04h IR=%02h",
                        observed_pc, observed_instruction);
        assert (reset_vector_low_seen && reset_vector_high_seen)
            else $fatal(1, "reset vector bus cycles were not observed");
        assert (irq_observed && nmi_observed)
            else $fatal(1, "interrupt vector evidence missing IRQ=%0b NMI=%0b",
                        irq_observed, nmi_observed);
        assert (stall_tested && suppressed_run_pulses >= 4)
            else $fatal(1, "stall evidence missing tested=%0b pulses=%0d",
                        stall_tested, suppressed_run_pulses);
        assert (stack_reads >= 6 && stack_writes >= 6)
            else $fatal(1, "insufficient stack traffic reads=%0d writes=%0d",
                        stack_reads, stack_writes);
        assert (rmw_writes == 5)
            else $fatal(1, "RMW original/modified writes mismatch: %0d",
                        rmw_writes);
        assert (page_cross_write_seen && page_cross_read_seen)
            else $fatal(1, "page-cross accesses missing write=%0b read=%0b",
                        page_cross_write_seen, page_cross_read_seen);
        assert (result_signature_seen)
            else $fatal(1, "PASS signature bus write not observed");

        repeat (32) @(posedge clk);
        #1;
        assert (pass && !fail && observed_pc == CPU_DIAG_PASS_LOOP &&
                observed_instruction == 8'h4C)
            else $fatal(1, "latched PASS state was not stable");

        $display("PASS: Phase 2K board diagnostic reached PC=%04h IR=%02h in %0d enabled CPU cycles (%0d clocks, %0d suppressed run pulses)",
                 observed_pc, observed_instruction, pass_enabled_cycle,
                 clock_cycles, suppressed_run_pulses);
        $finish;
    end
endmodule
