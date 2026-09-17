`timescale 1ns/1ps

module cpu_phase2h_tb;
    import cpu_pkg::*;

    localparam logic [15:0] START = 16'h8000;
    localparam logic [15:0] HANDLER = 16'h9000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic nmi = 1'b0;
    logic irq = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data;
    logic bus_write_enable;
    logic bus_valid;
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

    logic [15:0] trace_address [0:31];
    logic [15:0] trace_pc [0:31];
    cpu_execution_state_t trace_state [0:31];
    logic [7:0] trace_write_data [0:31];
    logic [7:0] trace_read_data [0:31];
    logic [7:0] trace_sp [0:31];
    logic [7:0] trace_opcode [0:31];
    logic trace_write [0:31];
    logic trace_valid [0:31];
    int unsigned trace_count = 0;
    int unsigned exact_cycle_vectors = 0;
    int unsigned bus_trace_vectors = 0;
    int unsigned stall_vectors = 0;

    cpu_core dut (
        .clk(clk), .reset(reset), .cpu_enable(cpu_enable), .nmi(nmi), .irq(irq),
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

    task automatic step_cpu(input logic record_bus);
        @(negedge clk);
        if (record_bus && cpu_enable) begin
            assert (trace_count < 32) else $fatal(1, "Phase 2H trace overflow");
            trace_address[trace_count] = bus_address;
            trace_pc[trace_count] = debug_pc;
            trace_state[trace_count] = debug_execution_state;
            trace_write_data[trace_count] = bus_write_data;
            trace_read_data[trace_count] = bus_read_data;
            trace_sp[trace_count] = debug_sp;
            trace_opcode[trace_count] = debug_instruction;
            trace_write[trace_count] = bus_write_enable;
            trace_valid[trace_count] = bus_valid;
            trace_count++;
        end
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
            else $fatal(1, "X/Z in Phase 2H CPU/bus trace");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write without valid");
    endtask

    task automatic check_read(input int unsigned index,
                              input logic [15:0] address);
        assert (trace_valid[index] && !trace_write[index] &&
                trace_address[index] == address)
            else $fatal(1, "read trace mismatch index=%0d expected=%04h got=%04h",
                        index, address, trace_address[index]);
    endtask

    task automatic check_write(input int unsigned index,
                               input logic [15:0] address,
                               input logic [7:0] data);
        assert (trace_valid[index] && trace_write[index] &&
                trace_address[index] == address &&
                trace_write_data[index] == data)
            else $fatal(1, "write trace mismatch index=%0d", index);
    endtask

    task automatic reset_core(input logic [15:0] target);
        memory_model.memory[CPU_VECTOR_RESET_LOW] = target[7:0];
        memory_model.memory[CPU_VECTOR_RESET_LOW + 16'd1] = target[15:8];
        reset = 1'b1;
        cpu_enable = 1'b0;
        nmi = 1'b0;
        irq = 1'b0;
        step_cpu(1'b0);
        step_cpu(1'b0);
        reset = 1'b0;
        cpu_enable = 1'b1;
        trace_count = 0;
        repeat (7) step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == target && debug_sp == CPU_POST_RESET_SP &&
                trace_count == 7)
            else $fatal(1, "seven-cycle reset mismatch");
        check_read(0, CPU_RESET_PC);
        check_read(1, CPU_RESET_PC);
        check_read(2, 16'h0100);
        check_read(3, 16'h01FF);
        check_read(4, 16'h01FE);
        check_read(5, CPU_VECTOR_RESET_LOW);
        check_read(6, CPU_VECTOR_RESET_LOW + 16'd1);
        exact_cycle_vectors++;
        bus_trace_vectors++;
        trace_count = 0;
    endtask

    task automatic execute_instruction(output int unsigned cycles);
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not begin at FETCH");
        trace_count = 0;
        cycles = 0;
        do begin
            step_cpu(1'b1);
            cycles++;
            assert (cycles <= 8) else $fatal(1, "instruction exceeded 8 cycles");
        end while (debug_execution_state != CPU_STATE_FETCH);
        assert (trace_count == cycles)
            else $fatal(1, "one bus event per enabled cycle violated");
        for (int unsigned index = 0; index < trace_count; index++) begin
            assert (trace_valid[index])
                else $fatal(1, "bus-idle enabled cycle index=%0d", index);
            assert (!$isunknown({trace_pc[index], trace_state[index],
                                 trace_read_data[index], trace_sp[index],
                                 trace_opcode[index]}))
                else $fatal(1, "trace metadata contains X/Z index=%0d", index);
        end
        exact_cycle_vectors++;
        bus_trace_vectors++;
    endtask

    task automatic test_indexed_reads_and_store;
        int unsigned cycles;

        // LDX #1; LDA $1200,X (no crossing).
        memory_model.memory[START] = 8'hA2;
        memory_model.memory[START + 1] = 8'h01;
        memory_model.memory[START + 2] = 8'hBD;
        memory_model.memory[START + 3] = 8'h00;
        memory_model.memory[START + 4] = 8'h12;
        memory_model.memory[16'h1201] = 8'h55;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (cycles == 4 && debug_a == 8'h55);
        check_read(3, 16'h1201);

        // LDA $12FF,X crosses and repeats the read after high-byte repair.
        memory_model.memory[debug_pc] = 8'hBD;
        memory_model.memory[debug_pc + 1] = 8'hFF;
        memory_model.memory[debug_pc + 2] = 8'h12;
        memory_model.memory[16'h1200] = 8'h11;
        memory_model.memory[16'h1300] = 8'h80;
        execute_instruction(cycles);
        assert (cycles == 5 && debug_a == 8'h80 &&
                debug_page_cross && debug_page_cross_valid);
        check_read(3, 16'h1200);
        check_read(4, 16'h1300);

        // STA has the tentative read even on crossing, but no variable penalty.
        memory_model.memory[debug_pc] = 8'h9D;
        memory_model.memory[debug_pc + 1] = 8'hFF;
        memory_model.memory[debug_pc + 2] = 8'h12;
        execute_instruction(cycles);
        assert (cycles == 5 && memory_model.memory[16'h1300] == 8'h80);
        check_read(3, 16'h1200);
        check_write(4, 16'h1300, 8'h80);
    endtask

    task automatic test_rmw_double_write_and_stalls;
        int unsigned guard;
        logic [31:0] held_writes;
        memory_model.memory[START] = 8'hE6; // INC $80
        memory_model.memory[START + 1] = 8'h80;
        memory_model.memory[16'h0080] = 8'h7F;
        reset_core(START);
        trace_count = 0;
        guard = 0;
        while (debug_execution_state != CPU_STATE_RMW_DUMMY_WRITE) begin
            step_cpu(1'b1);
            guard++;
            assert (guard < 6);
        end
        assert (guard == 3 && bus_write_enable && bus_write_data == 8'h7F);
        held_writes = memory_write_count;
        cpu_enable = 1'b0;
        repeat (4) step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_RMW_DUMMY_WRITE &&
                memory_write_count == held_writes &&
                memory_model.memory[16'h0080] == 8'h7F)
            else $fatal(1, "stalled RMW original write duplicated");
        stall_vectors++;
        cpu_enable = 1'b1;
        step_cpu(1'b1);
        assert (memory_write_count == held_writes + 1 &&
                debug_execution_state == CPU_STATE_RMW_WRITE &&
                bus_write_data == 8'h80);
        cpu_enable = 1'b0;
        repeat (4) step_cpu(1'b0);
        assert (memory_write_count == held_writes + 1)
            else $fatal(1, "stalled RMW final write duplicated");
        stall_vectors++;
        cpu_enable = 1'b1;
        step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                memory_write_count == held_writes + 2 &&
                memory_model.memory[16'h0080] == 8'h80 &&
                last_write_address == 16'h0080 && last_write_data == 8'h80);
        assert (trace_count == 5);
        check_read(0, START);
        check_read(1, START + 1);
        check_read(2, 16'h0080);
        check_write(3, 16'h0080, 8'h7F);
        check_write(4, 16'h0080, 8'h80);
        exact_cycle_vectors++;
        bus_trace_vectors++;
    endtask

    task automatic test_branches;
        int unsigned cycles;
        // Not taken BCS.
        memory_model.memory[START] = 8'hB0;
        memory_model.memory[START + 1] = 8'h7F;
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_pc == START + 2);

        // Taken BCC, same page.
        memory_model.memory[START] = 8'h90;
        memory_model.memory[START + 1] = 8'h05;
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 3 && debug_pc == START + 7);
        check_read(2, START + 2);

        // $80FD + opcode/displacement has base $80FF; +1 crosses to $8100.
        memory_model.memory[16'h80FD] = 8'h90;
        memory_model.memory[16'h80FE] = 8'h01;
        reset_core(16'h80FD);
        execute_instruction(cycles);
        assert (cycles == 4 && debug_pc == 16'h8100 && debug_page_cross);
        check_read(2, 16'h80FF);
        check_read(3, 16'h8000);
    endtask

    task automatic test_jsr_rts_stack;
        int unsigned cycles;
        memory_model.memory[START] = 8'h20;
        memory_model.memory[START + 1] = HANDLER[7:0];
        memory_model.memory[START + 2] = HANDLER[15:8];
        memory_model.memory[HANDLER] = 8'h60;
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 6 && debug_pc == HANDLER && debug_sp == 8'hFB);
        check_read(0, START);
        check_read(1, START + 1);
        check_read(2, 16'h01FD);
        check_write(3, 16'h01FD, 8'h80);
        check_write(4, 16'h01FC, 8'h02);
        check_read(5, START + 2);
        execute_instruction(cycles);
        assert (cycles == 6 && debug_pc == START + 3 && debug_sp == 8'hFD);
        check_read(1, HANDLER + 1);
        check_read(2, 16'h01FB);
        check_read(3, 16'h01FC);
        check_read(4, 16'h01FD);
        check_read(5, START + 2);
    endtask

    task automatic test_stack_push_pull;
        int unsigned cycles;
        memory_model.memory[START] = 8'hA9;
        memory_model.memory[START + 1] = 8'hA5;
        memory_model.memory[START + 2] = 8'h48;
        memory_model.memory[START + 3] = 8'h68;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (cycles == 3 && debug_sp == 8'hFC);
        check_read(1, START + 3);
        check_write(2, 16'h01FD, 8'hA5);
        execute_instruction(cycles);
        assert (cycles == 4 && debug_a == 8'hA5 && debug_sp == 8'hFD);
        check_read(1, START + 4);
        check_read(2, 16'h01FC);
        check_read(3, 16'h01FD);
    endtask

    task automatic test_brk_rti;
        int unsigned cycles;
        memory_model.memory[START] = 8'h00;
        memory_model.memory[START + 1] = 8'hEA;
        memory_model.memory[HANDLER] = 8'h40;
        memory_model.memory[CPU_VECTOR_IRQ_LOW] = HANDLER[7:0];
        memory_model.memory[CPU_VECTOR_IRQ_LOW + 1] = HANDLER[15:8];
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER && debug_sp == 8'hFA);
        check_read(0, START);
        check_read(1, START + 1);
        check_write(2, 16'h01FD, 8'h80);
        check_write(3, 16'h01FC, 8'h02);
        assert (trace_write_data[4][5:4] == 2'b11);
        check_read(5, CPU_VECTOR_IRQ_LOW);
        check_read(6, CPU_VECTOR_IRQ_LOW + 1);
        execute_instruction(cycles);
        assert (cycles == 6 && debug_pc == START + 2 && debug_sp == 8'hFD);
        check_read(1, HANDLER + 1);
        check_read(2, 16'h01FA);
        check_read(3, 16'h01FB);
        check_read(4, 16'h01FC);
        check_read(5, 16'h01FD);
    endtask

    task automatic test_hardware_interrupts;
        int unsigned cycles;
        // PLP clears I, then a held IRQ is sampled at the next boundary.
        memory_model.memory[START] = 8'h28;
        memory_model.memory[16'h01FE] = 8'h20;
        memory_model.memory[CPU_VECTOR_IRQ_LOW] = HANDLER[7:0];
        memory_model.memory[CPU_VECTOR_IRQ_LOW + 1] = HANDLER[15:8];
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 4 && !debug_status.interrupt_disable);
        cpu_enable = 1'b0;
        irq = 1'b1;
        repeat (3) step_cpu(1'b0);
        cpu_enable = 1'b1;
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER);
        check_read(0, START + 1);
        check_read(1, START + 1);
        check_read(5, CPU_VECTOR_IRQ_LOW);
        check_read(6, CPU_VECTOR_IRQ_LOW + 1);

        // A distinct NMI edge uses the same seven-cycle engine and FFFA/B.
        memory_model.memory[CPU_VECTOR_NMI_LOW] = HANDLER[7:0];
        memory_model.memory[CPU_VECTOR_NMI_LOW + 1] = HANDLER[15:8];
        reset_core(16'h8100);
        cpu_enable = 1'b0;
        nmi = 1'b1;
        repeat (4) step_cpu(1'b0);
        cpu_enable = 1'b1;
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER);
        check_read(5, CPU_VECTOR_NMI_LOW);
        check_read(6, CPU_VECTOR_NMI_LOW + 1);
    endtask

    initial begin
        $dumpfile("build/sim/cpu_phase2h.fst");
        $dumpvars(0, cpu_phase2h_tb);
        #1;
        test_indexed_reads_and_store();
        test_rmw_double_write_and_stalls();
        test_branches();
        test_jsr_rts_stack();
        test_stack_push_pull();
        test_brk_rti();
        test_hardware_interrupts();
        assert (exact_cycle_vectors == 28 && bus_trace_vectors == 28 &&
                stall_vectors == 2)
            else $fatal(1, "Phase 2H vector accounting mismatch %0d/%0d/%0d",
                        exact_cycle_vectors, bus_trace_vectors, stall_vectors);
        $display("PASS: Phase 2H cycle timing (28 exact-cycle traces, 2 write stalls)");
        $finish;
    end
endmodule
