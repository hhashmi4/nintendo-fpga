`timescale 1ns/1ps

module cpu_phase2i_tb;
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

    logic [15:0] trace_address [0:15];
    logic [7:0] trace_write_data [0:15];
    logic trace_write [0:15];
    logic trace_valid [0:15];
    int unsigned trace_count = 0;
    int unsigned decimal_vectors = 0;
    int unsigned status_vectors = 0;
    int unsigned interrupt_vectors = 0;
    int unsigned bus_audit_vectors = 0;

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
            assert (trace_count < 16) else $fatal(1, "Phase 2I trace overflow");
            trace_address[trace_count] = bus_address;
            trace_write_data[trace_count] = bus_write_data;
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
            else $fatal(1, "X/Z in Phase 2I CPU or bus state");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write asserted without a valid bus cycle");
    endtask

    task automatic check_read(input int unsigned index,
                              input logic [15:0] address);
        assert (trace_valid[index] && !trace_write[index] &&
                trace_address[index] == address)
            else $fatal(1, "read mismatch index=%0d expected=%04h got=%04h",
                        index, address, trace_address[index]);
    endtask

    task automatic check_write(input int unsigned index,
                               input logic [15:0] address,
                               input logic [7:0] data);
        assert (trace_valid[index] && trace_write[index] &&
                trace_address[index] == address &&
                trace_write_data[index] == data)
            else $fatal(1, "write mismatch index=%0d", index);
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
                debug_status == CPU_RESET_STATUS && trace_count == 7)
            else $fatal(1, "2A03 reset architectural state mismatch");
        check_read(0, CPU_RESET_PC);
        check_read(1, CPU_RESET_PC);
        check_read(2, 16'h0100);
        check_read(3, 16'h01FF);
        check_read(4, 16'h01FE);
        check_read(5, CPU_VECTOR_RESET_LOW);
        check_read(6, CPU_VECTOR_RESET_LOW + 16'd1);
        assert (memory_write_count == 0)
            else $fatal(1, "reset performed an unintended write");
        bus_audit_vectors++;
        trace_count = 0;
    endtask

    task automatic execute_instruction(output int unsigned cycles);
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not start at FETCH");
        trace_count = 0;
        cycles = 0;
        do begin
            step_cpu(1'b1);
            cycles++;
            assert (cycles <= 8) else $fatal(1, "instruction exceeded 8 cycles");
        end while (debug_execution_state != CPU_STATE_FETCH &&
                   debug_execution_state != CPU_STATE_TRAP);
    endtask

    task automatic run_decimal_mode(
        input logic [7:0] opcode,
        input logic [7:0] accumulator,
        input logic [7:0] operand,
        input logic carry_in,
        input logic decimal,
        output logic [7:0] result,
        output logic [7:0] status
    );
        int unsigned cycles;
        logic [7:0] pulled_status;
        pulled_status = 8'h20 | {4'b0000, decimal, 2'b00, carry_in};
        memory_model.memory[START] = 8'hA9; // LDA #accumulator
        memory_model.memory[START + 1] = accumulator;
        memory_model.memory[START + 2] = 8'h28; // PLP
        memory_model.memory[START + 3] = opcode;
        memory_model.memory[START + 4] = operand;
        memory_model.memory[16'h01FE] = pulled_status;
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_a == accumulator);
        execute_instruction(cycles);
        assert (cycles == 4 && debug_status.decimal == decimal &&
                debug_status.carry == carry_in);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_status.decimal == decimal)
            else $fatal(1, "ADC/SBC changed stored D");
        result = debug_a;
        status = debug_status;
        decimal_vectors++;
    endtask

    task automatic check_decimal_pair(
        input logic [7:0] opcode,
        input logic [7:0] accumulator,
        input logic [7:0] operand,
        input logic carry_in
    );
        logic [7:0] d0_result, d1_result, d0_status, d1_status;
        run_decimal_mode(opcode, accumulator, operand, carry_in, 1'b0,
                         d0_result, d0_status);
        run_decimal_mode(opcode, accumulator, operand, carry_in, 1'b1,
                         d1_result, d1_status);
        assert (d0_result == d1_result &&
                (d0_status & 8'hF7) == (d1_status & 8'hF7) &&
                !d0_status[3] && d1_status[3])
            else $fatal(1, "D altered binary arithmetic opcode=%02h A=%02h B=%02h C=%0d",
                        opcode, accumulator, operand, carry_in);
    endtask

    task automatic test_decimal_disabled;
        check_decimal_pair(8'h69, 8'h00, 8'h00, 1'b0);
        check_decimal_pair(8'h69, 8'h00, 8'h00, 1'b1);
        check_decimal_pair(8'h69, 8'h7F, 8'h01, 1'b0);
        check_decimal_pair(8'h69, 8'h80, 8'h80, 1'b0);
        check_decimal_pair(8'h69, 8'hFF, 8'h01, 1'b0);
        check_decimal_pair(8'h69, 8'hFF, 8'hFF, 1'b1);
        check_decimal_pair(8'h69, 8'h49, 8'h51, 1'b0); // differs from BCD
        check_decimal_pair(8'h69, 8'h99, 8'h01, 1'b0); // differs from BCD
        check_decimal_pair(8'hE9, 8'h00, 8'h00, 1'b0);
        check_decimal_pair(8'hE9, 8'h00, 8'h00, 1'b1);
        check_decimal_pair(8'hE9, 8'h00, 8'h01, 1'b1);
        check_decimal_pair(8'hE9, 8'h80, 8'h01, 1'b1);
        check_decimal_pair(8'hE9, 8'h7F, 8'hFF, 1'b1);
        check_decimal_pair(8'hE9, 8'hFF, 8'hFF, 1'b0);
        check_decimal_pair(8'hE9, 8'h50, 8'h01, 1'b1); // differs from BCD
        check_decimal_pair(8'hE9, 8'h00, 8'h99, 1'b1); // differs from BCD
    endtask

    task automatic test_status_policy;
        int unsigned cycles;
        logic [7:0] raw_status;
        for (int unsigned flags = 0; flags < 64; flags++) begin
            raw_status = {flags[5], flags[4], 1'b0, 1'b0,
                          flags[3], flags[2], flags[1], flags[0]};
            memory_model.memory[START] = 8'h28; // PLP
            memory_model.memory[START + 1] = 8'h08; // PHP
            memory_model.memory[16'h01FE] = raw_status;
            reset_core(START);
            execute_instruction(cycles);
            assert (debug_status == cpu_status_normalize(raw_status) &&
                    !debug_status.break_command && debug_status.unused);
            execute_instruction(cycles);
            assert (cycles == 3 && debug_sp == 8'hFD &&
                    memory_model.memory[16'h01FE] == cpu_status_for_php(raw_status));
            assert (memory_model.memory[16'h01FE][5:4] == 2'b11);
            status_vectors++;
        end
    endtask

    task automatic test_plp_irq_poll_delay;
        int unsigned cycles;

        // Old I=1, pulled I=0: execute one instruction before IRQ entry.
        memory_model.memory[START] = 8'h28; // PLP
        memory_model.memory[START + 1] = 8'hAA; // TAX
        memory_model.memory[16'h01FE] = 8'h20;
        memory_model.memory[CPU_VECTOR_IRQ_LOW] = HANDLER[7:0];
        memory_model.memory[CPU_VECTOR_IRQ_LOW + 16'd1] = HANDLER[15:8];
        reset_core(START);
        cpu_enable = 1'b0;
        irq = 1'b1;
        repeat (3) step_cpu(1'b0);
        cpu_enable = 1'b1;
        execute_instruction(cycles);
        assert (!debug_status.interrupt_disable);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_pc == START + 2)
            else $fatal(1, "PLP clear-I did not delay IRQ by one instruction");
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER);
        interrupt_vectors++;

        // Establish I=0, consume its boundary, then PLP I=1 while IRQ is
        // synchronized during the instruction. Old I=0 must still admit it.
        memory_model.memory[START] = 8'h28; // PLP I=0
        memory_model.memory[START + 1] = 8'hAA; // consume boundary
        memory_model.memory[START + 2] = 8'h28; // PLP I=1
        memory_model.memory[16'h01FE] = 8'h20;
        memory_model.memory[16'h01FF] = 8'h24;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (!debug_status.interrupt_disable && debug_pc == START + 2);
        trace_count = 0;
        step_cpu(1'b1); // fetch second PLP
        assert (debug_execution_state == CPU_STATE_STACK_DUMMY);
        cpu_enable = 1'b0;
        irq = 1'b1;
        repeat (3) step_cpu(1'b0);
        cpu_enable = 1'b1;
        repeat (3) step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_status.interrupt_disable);
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER)
            else $fatal(1, "PLP set-I incorrectly suppressed already-polled IRQ");
        interrupt_vectors++;
    endtask

    task automatic test_nmi_edge_and_priority;
        int unsigned cycles;
        memory_model.memory[CPU_VECTOR_NMI_LOW] = HANDLER[7:0];
        memory_model.memory[CPU_VECTOR_NMI_LOW + 16'd1] = HANDLER[15:8];
        memory_model.memory[CPU_VECTOR_IRQ_LOW] = 8'h00;
        memory_model.memory[CPU_VECTOR_IRQ_LOW + 16'd1] = 8'hA0;
        memory_model.memory[HANDLER] = 8'hAA;
        memory_model.memory[HANDLER + 1] = 8'hA8;
        reset_core(START);
        cpu_enable = 1'b0;
        nmi = 1'b1;
        irq = 1'b1;
        repeat (4) step_cpu(1'b0);
        cpu_enable = 1'b1;
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER)
            else $fatal(1, "NMI did not win simultaneous NMI/IRQ");
        assert (trace_write_data[4][5:4] == 2'b10)
            else $fatal(1, "hardware interrupt pushed wrong B/U bits");

        // A held logical NMI level must not create another edge.
        irq = 1'b0;
        execute_instruction(cycles);
        assert (cycles == 2 && debug_pc == HANDLER + 1);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_pc == HANDLER + 2);

        // Deassert and reassert to create a distinct synchronized edge.
        cpu_enable = 1'b0;
        nmi = 1'b0;
        repeat (4) step_cpu(1'b0);
        nmi = 1'b1;
        repeat (4) step_cpu(1'b0);
        cpu_enable = 1'b1;
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER);
        interrupt_vectors++;
    endtask

    task automatic test_jmp_indirect_quirk;
        int unsigned cycles;
        memory_model.memory[START] = 8'h6C;
        memory_model.memory[START + 1] = 8'hFF;
        memory_model.memory[START + 2] = 8'h12;
        memory_model.memory[16'h12FF] = 8'hCD;
        memory_model.memory[16'h1200] = 8'hAB;
        memory_model.memory[16'h1300] = 8'hEE;
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 5 && debug_pc == 16'hABCD);
        check_read(3, 16'h12FF);
        check_read(4, 16'h1200);
        bus_audit_vectors++;
    endtask

    task automatic check_rmw(
        input logic [7:0] opcode,
        input logic [7:0] original,
        input logic [7:0] modified
    );
        int unsigned cycles;
        memory_model.memory[START] = opcode;
        memory_model.memory[START + 1] = 8'h80;
        memory_model.memory[16'h0080] = original;
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 5 && memory_model.memory[16'h0080] == modified);
        check_read(2, 16'h0080);
        check_write(3, 16'h0080, original);
        check_write(4, 16'h0080, modified);
        bus_audit_vectors++;
    endtask

    task automatic test_rmw_bus_behavior;
        check_rmw(8'hE6, 8'h7F, 8'h80); // INC
        check_rmw(8'hC6, 8'h00, 8'hFF); // DEC
        check_rmw(8'h06, 8'h81, 8'h02); // ASL
        check_rmw(8'h46, 8'h81, 8'h40); // LSR
        check_rmw(8'h26, 8'h81, 8'h02); // ROL, reset C=0
        check_rmw(8'h66, 8'h81, 8'h40); // ROR, reset C=0
    endtask

    task automatic test_page_cross_classes;
        int unsigned cycles;
        // LDX #1; LDA $12FF,X incurs a correction cycle.
        memory_model.memory[START] = 8'hA2;
        memory_model.memory[START + 1] = 8'h01;
        memory_model.memory[START + 2] = 8'hBD;
        memory_model.memory[START + 3] = 8'hFF;
        memory_model.memory[START + 4] = 8'h12;
        memory_model.memory[16'h1300] = 8'h5A;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (cycles == 5 && debug_a == 8'h5A && debug_page_cross);
        check_read(3, 16'h1200);
        check_read(4, 16'h1300);

        // STA $12FF,X remains fixed at five cycles and writes only final EA.
        memory_model.memory[debug_pc] = 8'h9D;
        memory_model.memory[debug_pc + 16'd1] = 8'hFF;
        memory_model.memory[debug_pc + 16'd2] = 8'h12;
        execute_instruction(cycles);
        assert (cycles == 5);
        check_read(3, 16'h1200);
        check_write(4, 16'h1300, 8'h5A);

        // Taken branch: same-page three cycles and crossing four cycles.
        memory_model.memory[16'h80F0] = 8'h90;
        memory_model.memory[16'h80F1] = 8'h05;
        reset_core(16'h80F0);
        execute_instruction(cycles);
        assert (cycles == 3 && debug_pc == 16'h80F7);
        memory_model.memory[16'h80FD] = 8'h90;
        memory_model.memory[16'h80FE] = 8'h01;
        reset_core(16'h80FD);
        execute_instruction(cycles);
        assert (cycles == 4 && debug_pc == 16'h8100 && debug_page_cross);
        bus_audit_vectors += 4;
    endtask

    task automatic test_unsupported_policy;
        logic [31:0] writes_before;
        memory_model.memory[START] = 8'h02;
        reset_core(START);
        writes_before = memory_write_count;
        step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_TRAP &&
                memory_write_count == writes_before && !bus_write_enable)
            else $fatal(1, "unofficial opcode did not trap inertly");

        bus_audit_vectors++;
    endtask

    initial begin
        $dumpfile("build/sim/cpu_phase2i.fst");
        $dumpvars(0, cpu_phase2i_tb);
        #1;
        reset_core(START);
        test_decimal_disabled();
        test_status_policy();
        test_plp_irq_poll_delay();
        test_nmi_edge_and_priority();
        test_jmp_indirect_quirk();
        test_rmw_bus_behavior();
        test_page_cross_classes();
        test_unsupported_policy();
        assert (decimal_vectors == 32 && status_vectors == 64 &&
                interrupt_vectors == 3 && bus_audit_vectors == 123)
            else $fatal(1, "Phase 2I vector accounting mismatch %0d/%0d/%0d/%0d",
                        decimal_vectors, status_vectors, interrupt_vectors,
                        bus_audit_vectors);
        $display("PASS: Phase 2I Ricoh 2A03 audit (32 decimal, 64 status, 3 interrupt, 123 bus/reset vectors)");
        $finish;
    end
endmodule
