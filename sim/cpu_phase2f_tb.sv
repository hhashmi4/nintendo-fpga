`timescale 1ns/1ps

module cpu_phase2f_tb;
    import cpu_pkg::*;

    localparam logic [15:0] PROGRAM_START = 16'h8000;
    localparam int unsigned BRANCH_VECTOR_COUNT = 8 * 2 * 6;
    localparam int unsigned DIRECTED_VECTOR_COUNT =
        BRANCH_VECTOR_COUNT + 9 + 3 + 15 + 15 + 24 + 24 + 27 + 27 + 1;

    localparam logic [7:0] BRANCH_OPCODES [0:7] = '{
        8'h90, 8'hB0, 8'hF0, 8'h30, 8'hD0, 8'h10, 8'h50, 8'h70
    };
    localparam cpu_instruction_t BRANCH_INSTRUCTIONS [0:7] = '{
        CPU_INSTR_BCC, CPU_INSTR_BCS, CPU_INSTR_BEQ, CPU_INSTR_BMI,
        CPU_INSTR_BNE, CPU_INSTR_BPL, CPU_INSTR_BVC, CPU_INSTR_BVS
    };
    localparam logic [15:0] BRANCH_ADDRESSES [0:5] = '{
        16'h8200, 16'h80FD, 16'h8100,
        16'hFFFD, 16'hFFFF, 16'h2000
    };
    localparam logic [7:0] BRANCH_OFFSETS [0:5] = '{
        8'h05, 8'h01, 8'hFB, 8'h01, 8'hFE, 8'h7F
    };
    localparam logic [15:0] BOUNDARY_TARGETS [0:8] = '{
        16'h0000, 16'h0001, 16'h00FE, 16'h00FF, 16'h0100,
        16'h7FFF, 16'h8000, 16'hFFFE, 16'hFFFF
    };
    localparam logic [7:0] STACK_VALUES [0:4] = '{
        8'h00, 8'h01, 8'h7F, 8'h80, 8'hFF
    };
    localparam logic [7:0] STACK_POINTERS [0:2] = '{
        8'hFD, 8'h00, 8'hFF
    };
    localparam logic [7:0] STATUS_VALUES [0:7] = '{
        8'h00, 8'h01, 8'h02, 8'h04,
        8'h08, 8'h40, 8'h80, 8'hFF
    };

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data;
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
    logic [31:0] memory_write_count;
    logic [15:0] last_write_address;
    logic [7:0] last_write_data;

    logic [15:0] trace_address [0:15];
    logic [7:0] trace_write_data [0:15];
    logic trace_write_enable [0:15];
    int unsigned trace_count = 0;
    int unsigned directed_vector_count = 0;
    int unsigned stall_check_count = 0;

    cpu_core #(
        .INITIAL_PC (PROGRAM_START)
    ) dut (
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

    cpu_test_memory memory_model (
        .clk                (clk),
        .reset              (reset),
        .cpu_enable         (cpu_enable),
        .address            (bus_address),
        .write_data         (bus_write_data),
        .write_enable       (bus_write_enable),
        .valid              (bus_valid),
        .read_data          (bus_read_data),
        .write_count        (memory_write_count),
        .last_write_address (last_write_address),
        .last_write_data    (last_write_data)
    );

    always #5 clk <= !clk;

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic branch_condition(
        input cpu_instruction_t instruction,
        input logic [7:0] status
    );
        case (instruction)
            CPU_INSTR_BCC: return !status[0];
            CPU_INSTR_BCS: return status[0];
            CPU_INSTR_BEQ: return status[1];
            CPU_INSTR_BMI: return status[7];
            CPU_INSTR_BNE: return !status[1];
            CPU_INSTR_BPL: return !status[7];
            CPU_INSTR_BVC: return !status[6];
            CPU_INSTR_BVS: return status[6];
            default: return 1'b0;
        endcase
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [7:0] branch_status(
        input cpu_instruction_t instruction,
        input logic taken
    );
        logic [7:0] value;
        value = CPU_RESET_STATUS;
        case (instruction)
            CPU_INSTR_BCC: value[0] = !taken;
            CPU_INSTR_BCS: value[0] = taken;
            CPU_INSTR_BEQ: value[1] = taken;
            CPU_INSTR_BMI: value[7] = taken;
            CPU_INSTR_BNE: value[1] = !taken;
            CPU_INSTR_BPL: value[7] = !taken;
            CPU_INSTR_BVC: value[6] = !taken;
            CPU_INSTR_BVS: value[6] = taken;
            default: value = CPU_RESET_STATUS;
        endcase
        return cpu_status_normalize(value);
    endfunction

    function automatic logic [7:0] status_with_nz(
        input logic [7:0] status,
        input logic [7:0] value
    );
        logic [7:0] updated;
        updated = status;
        updated[7] = value[7];
        updated[1] = (value == 8'h00);
        return updated;
    endfunction

    task automatic append_byte(
        inout logic [15:0] cursor,
        input logic [7:0] value
    );
        memory_model.memory[cursor] = value;
        cursor = cursor + 16'd1;
    endtask

    task automatic append_immediate(
        inout logic [15:0] cursor,
        input logic [7:0] opcode,
        input logic [7:0] value
    );
        append_byte(cursor, opcode);
        append_byte(cursor, value);
    endtask

    task automatic step_cpu(input logic record_bus);
        logic [15:0] previous_pc;
        cpu_execution_state_t previous_state;
        logic previous_enable;
        logic previous_reset;
        @(negedge clk);
        previous_pc = debug_pc;
        previous_state = debug_execution_state;
        previous_enable = cpu_enable;
        previous_reset = reset;
        if (bus_write_enable) begin
            assert (debug_execution_state inside {
                CPU_STATE_MEMORY_WRITE,
                CPU_STATE_RMW_WRITE,
                CPU_STATE_STACK_PUSH,
                CPU_STATE_JSR_PUSH_HIGH,
                CPU_STATE_JSR_PUSH_LOW
            }) else $fatal(1, "write asserted outside an intentional state");
        end
        if (record_bus && cpu_enable && bus_valid) begin
            assert (trace_count < 16)
                else $fatal(1, "Phase 2F bus trace overflow");
            trace_address[trace_count] = bus_address;
            trace_write_data[trace_count] = bus_write_data;
            trace_write_enable[trace_count] = bus_write_enable;
            trace_count++;
        end
        @(posedge clk);
        #1;
        assert (!$isunknown({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                             debug_status, debug_instruction,
                             debug_execution_state,
                             debug_decoded_instruction,
                             debug_addressing_mode,
                             debug_effective_address, debug_page_cross,
                             debug_page_cross_valid, bus_address,
                             bus_write_data, bus_write_enable, bus_valid,
                             bus_read_data, memory_write_count,
                             last_write_address, last_write_data}))
            else $fatal(1, "X/Z detected in Phase 2F CPU or bus state");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write_enable asserted without bus_valid");
        if (!previous_reset && !previous_enable) begin
            assert (debug_pc == previous_pc)
                else $fatal(1, "PC changed while cpu_enable was low");
        end else if (!previous_reset && previous_enable &&
                     debug_pc != previous_pc) begin
            assert (previous_state inside {
                CPU_STATE_FETCH,
                CPU_STATE_OPERAND_LOW,
                CPU_STATE_OPERAND_HIGH,
                CPU_STATE_ADDRESS,
                CPU_STATE_BRANCH_DECIDE,
                CPU_STATE_JSR_PUSH_LOW,
                CPU_STATE_RTS_COMPLETE
            }) else $fatal(1, "PC changed outside an intentional state");
        end
    endtask

    task automatic reset_core;
        reset = 1'b1;
        cpu_enable = 1'b0;
        trace_count = 0;
        step_cpu(1'b0);
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_RESET &&
                debug_pc == PROGRAM_START && debug_sp == CPU_RESET_SP &&
                debug_status == CPU_RESET_STATUS)
            else $fatal(1, "Phase 2F reset regression");
        assert (!bus_valid && !bus_write_enable && memory_write_count == 0)
            else $fatal(1, "reset left bus or write log active");
        reset = 1'b0;
        cpu_enable = 1'b1;
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "CPU failed to enter FETCH");
    endtask

    task automatic execute_current_instruction(
        input logic record_bus,
        output int unsigned enabled_steps
    );
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not begin in FETCH");
        enabled_steps = 0;
        do begin
            step_cpu(record_bus);
            enabled_steps++;
            assert (enabled_steps < 20)
                else $fatal(1, "Phase 2F instruction failed to complete");
        end while (debug_execution_state != CPU_STATE_FETCH);
    endtask

    task automatic execute_setup(input int unsigned instruction_count);
        int unsigned ignored_steps;
        for (int unsigned index = 0; index < instruction_count; index++) begin
            execute_current_instruction(1'b0, ignored_steps);
            assert (ignored_steps > 0)
                else $fatal(1, "setup instruction made no progress");
        end
        trace_count = 0;
    endtask

    task automatic check_trace_read(
        input int unsigned index,
        input logic [15:0] address
    );
        assert (trace_address[index] == address &&
                !trace_write_enable[index])
            else $fatal(1, "read trace mismatch at event %0d", index);
    endtask

    task automatic check_trace_write(
        input int unsigned index,
        input logic [15:0] address,
        input logic [7:0] data
    );
        assert (trace_address[index] == address &&
                trace_write_enable[index] &&
                trace_write_data[index] == data)
            else $fatal(1, "write trace mismatch at event %0d", index);
    endtask

    task automatic test_branch(
        input logic [2:0] branch_index,
        input logic taken,
        input logic [2:0] address_index
    );
        logic [15:0] cursor;
        logic [15:0] branch_address;
        logic [15:0] branch_base;
        logic [15:0] branch_target;
        logic [7:0] expected_status;
        int unsigned enabled_steps;

        branch_address = BRANCH_ADDRESSES[address_index];
        expected_status = branch_status(BRANCH_INSTRUCTIONS[branch_index], taken);
        memory_model.memory[16'h01FE] = expected_status;
        cursor = PROGRAM_START;
        append_byte(cursor, 8'h28); // PLP supplies the exact condition flags.
        append_byte(cursor, 8'h4C);
        append_byte(cursor, branch_address[7:0]);
        append_byte(cursor, branch_address[15:8]);
        assert (cursor == PROGRAM_START + 16'd4)
            else $fatal(1, "branch setup length mismatch");
        memory_model.memory[branch_address] = BRANCH_OPCODES[branch_index];
        memory_model.memory[branch_address + 16'd1] =
            BRANCH_OFFSETS[address_index];

        reset_core();
        execute_setup(2);
        assert (debug_pc == branch_address && debug_status == expected_status)
            else $fatal(1, "branch setup failed");
        assert (branch_condition(BRANCH_INSTRUCTIONS[branch_index],
                                 debug_status) == taken)
            else $fatal(1, "branch condition setup mismatch");

        execute_current_instruction(1'b1, enabled_steps);
        branch_base = branch_address + 16'd2;
        branch_target = branch_base +
                        {{8{BRANCH_OFFSETS[address_index][7]}},
                         BRANCH_OFFSETS[address_index]};
        assert (debug_pc == (taken ? branch_target : branch_base) &&
                debug_status == expected_status)
            else $fatal(1, "branch result/status mismatch");
        assert (debug_effective_address == branch_target &&
                debug_page_cross_valid &&
                debug_page_cross ==
                    (branch_base[15:8] != branch_target[15:8]))
            else $fatal(1, "branch target metadata mismatch");
        assert (enabled_steps == 5 && trace_count == 2 &&
                memory_write_count == 0)
            else $fatal(1, "branch sequencing mismatch");
        check_trace_read(0, branch_address);
        check_trace_read(1, branch_address + 16'd1);
        directed_vector_count++;
    endtask

    task automatic test_jmp_absolute(input logic [15:0] target);
        int unsigned enabled_steps;
        memory_model.memory[PROGRAM_START] = 8'h4C;
        memory_model.memory[PROGRAM_START + 16'd1] = target[7:0];
        memory_model.memory[PROGRAM_START + 16'd2] = target[15:8];
        reset_core();
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_pc == target && debug_sp == CPU_RESET_SP &&
                debug_status == CPU_RESET_STATUS &&
                enabled_steps == 5 && trace_count == 3 &&
                memory_write_count == 0)
            else $fatal(1, "JMP absolute mismatch");
        check_trace_read(0, PROGRAM_START);
        check_trace_read(1, PROGRAM_START + 16'd1);
        check_trace_read(2, PROGRAM_START + 16'd2);
        directed_vector_count++;
    endtask

    task automatic test_jmp_indirect(
        input logic [15:0] pointer,
        input logic [15:0] expected_high_address,
        input logic [15:0] target
    );
        int unsigned enabled_steps;
        memory_model.memory[PROGRAM_START] = 8'h6C;
        memory_model.memory[PROGRAM_START + 16'd1] = pointer[7:0];
        memory_model.memory[PROGRAM_START + 16'd2] = pointer[15:8];
        memory_model.memory[pointer] = target[7:0];
        memory_model.memory[expected_high_address] = target[15:8];
        reset_core();
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_pc == target && enabled_steps == 8 &&
                trace_count == 5 && memory_write_count == 0)
            else $fatal(1, "JMP indirect mismatch");
        check_trace_read(0, PROGRAM_START);
        check_trace_read(1, PROGRAM_START + 16'd1);
        check_trace_read(2, PROGRAM_START + 16'd2);
        check_trace_read(3, pointer);
        check_trace_read(4, expected_high_address);
        directed_vector_count++;
    endtask

    task automatic test_pha(
        input logic [7:0] sp,
        input logic [7:0] value
    );
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        logic [7:0] before_status;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA9, value);
        append_immediate(cursor, 8'hA2, sp);
        append_byte(cursor, 8'h9A);
        instruction_pc = cursor;
        append_byte(cursor, 8'h48);
        reset_core();
        execute_setup(3);
        before_status = debug_status;
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_sp == (sp - 8'd1) &&
                debug_status == before_status &&
                debug_pc == instruction_pc + 16'd1 &&
                enabled_steps == 3 && trace_count == 2 &&
                memory_write_count == 1)
            else $fatal(1, "PHA architectural mismatch");
        check_trace_read(0, instruction_pc);
        check_trace_write(1, {8'h01, sp}, value);
        directed_vector_count++;
    endtask

    task automatic test_pla(
        input logic [7:0] sp,
        input logic [7:0] value
    );
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        logic [7:0] before_status;
        logic [7:0] expected_status;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA2, sp);
        append_byte(cursor, 8'h9A);
        instruction_pc = cursor;
        append_byte(cursor, 8'h68);
        memory_model.memory[{8'h01, sp + 8'd1}] = value;
        reset_core();
        execute_setup(2);
        before_status = debug_status;
        expected_status = status_with_nz(before_status, value);
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_a == value && debug_sp == (sp + 8'd1) &&
                debug_status == expected_status &&
                debug_pc == instruction_pc + 16'd1 &&
                enabled_steps == 4 && trace_count == 2 &&
                memory_write_count == 0)
            else $fatal(1, "PLA architectural mismatch");
        check_trace_read(0, instruction_pc);
        check_trace_read(1, {8'h01, sp + 8'd1});
        directed_vector_count++;
    endtask

    task automatic test_php(
        input logic [7:0] sp,
        input logic [7:0] stack_status
    );
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        logic [7:0] normalized;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA2, sp - 8'd1);
        append_byte(cursor, 8'h9A);
        append_byte(cursor, 8'h28);
        instruction_pc = cursor;
        append_byte(cursor, 8'h08);
        memory_model.memory[{8'h01, sp}] = stack_status;
        reset_core();
        execute_setup(3);
        normalized = cpu_status_normalize(stack_status);
        assert (debug_sp == sp && debug_status == normalized)
            else $fatal(1, "PHP setup/PLP normalization mismatch");
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_sp == (sp - 8'd1) && debug_status == normalized &&
                enabled_steps == 3 && trace_count == 2 &&
                memory_write_count == 1)
            else $fatal(1, "PHP architectural mismatch");
        check_trace_read(0, instruction_pc);
        check_trace_write(1, {8'h01, sp},
                          cpu_status_for_php(stack_status));
        assert (last_write_data[5:4] == 2'b11)
            else $fatal(1, "PHP did not synthesize U/B high");
        directed_vector_count++;
    endtask

    task automatic test_plp(
        input logic [7:0] sp,
        input logic [7:0] stack_status
    );
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA2, sp);
        append_byte(cursor, 8'h9A);
        instruction_pc = cursor;
        append_byte(cursor, 8'h28);
        memory_model.memory[{8'h01, sp + 8'd1}] = stack_status;
        reset_core();
        execute_setup(2);
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_sp == (sp + 8'd1) &&
                debug_status == cpu_status_normalize(stack_status) &&
                debug_status.unused && !debug_status.break_command &&
                enabled_steps == 4 && trace_count == 2 &&
                memory_write_count == 0)
            else $fatal(1, "PLP architectural/status mismatch");
        check_trace_read(0, instruction_pc);
        check_trace_read(1, {8'h01, sp + 8'd1});
        directed_vector_count++;
    endtask

    task automatic test_jsr(
        input logic [7:0] sp,
        input logic [15:0] target
    );
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        logic [15:0] return_address;
        logic [7:0] before_status;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA2, sp);
        append_byte(cursor, 8'h9A);
        instruction_pc = cursor;
        append_byte(cursor, 8'h20);
        append_byte(cursor, target[7:0]);
        append_byte(cursor, target[15:8]);
        return_address = instruction_pc + 16'd2;
        reset_core();
        execute_setup(2);
        before_status = debug_status;
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_pc == target && debug_sp == (sp - 8'd2) &&
                debug_status == before_status && enabled_steps == 7 &&
                trace_count == 5 && memory_write_count == 2)
            else $fatal(1, "JSR architectural mismatch");
        check_trace_read(0, instruction_pc);
        check_trace_read(1, instruction_pc + 16'd1);
        check_trace_read(2, instruction_pc + 16'd2);
        check_trace_write(3, {8'h01, sp}, return_address[15:8]);
        check_trace_write(4, {8'h01, sp - 8'd1}, return_address[7:0]);
        directed_vector_count++;
    endtask

    task automatic test_rts(
        input logic [7:0] sp,
        input logic [15:0] stored_return
    );
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        logic [7:0] before_status;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA2, sp);
        append_byte(cursor, 8'h9A);
        instruction_pc = cursor;
        append_byte(cursor, 8'h60);
        memory_model.memory[{8'h01, sp + 8'd1}] = stored_return[7:0];
        memory_model.memory[{8'h01, sp + 8'd2}] = stored_return[15:8];
        reset_core();
        execute_setup(2);
        before_status = debug_status;
        execute_current_instruction(1'b1, enabled_steps);
        assert (debug_pc == (stored_return + 16'd1) &&
                debug_sp == (sp + 8'd2) && debug_status == before_status &&
                enabled_steps == 6 && trace_count == 3 &&
                memory_write_count == 0)
            else $fatal(1, "RTS architectural mismatch");
        check_trace_read(0, instruction_pc);
        check_trace_read(1, {8'h01, sp + 8'd1});
        check_trace_read(2, {8'h01, sp + 8'd2});
        directed_vector_count++;
    endtask

    task automatic test_jsr_rts_round_trip;
        logic [15:0] cursor;
        logic [15:0] instruction_pc;
        int unsigned enabled_steps;
        cursor = PROGRAM_START;
        append_immediate(cursor, 8'hA2, 8'hFD);
        append_byte(cursor, 8'h9A);
        instruction_pc = cursor;
        append_byte(cursor, 8'h20);
        append_byte(cursor, 8'h00);
        append_byte(cursor, 8'h90);
        memory_model.memory[16'h9000] = 8'h60;
        reset_core();
        execute_setup(2);
        execute_current_instruction(1'b0, enabled_steps);
        assert (debug_pc == 16'h9000 && debug_sp == 8'hFB &&
                enabled_steps == 7)
            else $fatal(1, "round-trip JSR failed");
        execute_current_instruction(1'b0, enabled_steps);
        assert (debug_pc == instruction_pc + 16'd3 && debug_sp == 8'hFD &&
                memory_write_count == 2 && enabled_steps == 6)
            else $fatal(1, "round-trip RTS failed");
        directed_vector_count++;
    endtask

    task automatic prepare_stall(input cpu_execution_state_t target_state);
        logic [15:0] cursor;
        cursor = PROGRAM_START;
        case (target_state)
            CPU_STATE_OPERAND_LOW,
            CPU_STATE_BRANCH_DECIDE: begin
                append_byte(cursor, 8'hB0);
                append_byte(cursor, 8'h05);
            end

            CPU_STATE_STACK_PUSH: append_byte(cursor, 8'h48);

            CPU_STATE_STACK_READ: begin
                append_byte(cursor, 8'h68);
                memory_model.memory[16'h01FE] = 8'hA5;
            end

            CPU_STATE_JSR_PUSH_HIGH,
            CPU_STATE_JSR_PUSH_LOW: begin
                append_byte(cursor, 8'h20);
                append_byte(cursor, 8'h00);
                append_byte(cursor, 8'h90);
            end

            CPU_STATE_RTS_PULL_LOW,
            CPU_STATE_RTS_PULL_HIGH: begin
                append_byte(cursor, 8'h60);
                memory_model.memory[16'h01FE] = 8'h34;
                memory_model.memory[16'h01FF] = 8'h12;
            end

            CPU_STATE_POINTER_LOW,
            CPU_STATE_POINTER_HIGH: begin
                append_byte(cursor, 8'h6C);
                append_byte(cursor, 8'hFF);
                append_byte(cursor, 8'h12);
                memory_model.memory[16'h12FF] = 8'h00;
                memory_model.memory[16'h1200] = 8'h90;
            end

            default: $fatal(1, "unsupported Phase 2F stall state");
        endcase
        assert (cursor != PROGRAM_START)
            else $fatal(1, "stall setup emitted no instruction");
        reset_core();
    endtask

    task automatic test_stall(input cpu_execution_state_t target_state);
        logic [7:0] held_a;
        logic [7:0] held_x;
        logic [7:0] held_y;
        logic [7:0] held_sp;
        logic [15:0] held_pc;
        logic [7:0] held_status;
        logic [15:0] held_bus_address;
        logic [7:0] held_bus_data;
        logic held_bus_write;
        logic held_bus_valid;
        logic [31:0] held_write_count;
        int unsigned guard;

        prepare_stall(target_state);
        guard = 0;
        while (debug_execution_state != target_state) begin
            step_cpu(1'b0);
            guard++;
            assert (guard < 16) else $fatal(1, "stall state not reached");
        end

        held_a = debug_a;
        held_x = debug_x;
        held_y = debug_y;
        held_sp = debug_sp;
        held_pc = debug_pc;
        held_status = debug_status;
        held_bus_address = bus_address;
        held_bus_data = bus_write_data;
        held_bus_write = bus_write_enable;
        held_bus_valid = bus_valid;
        held_write_count = memory_write_count;
        cpu_enable = 1'b0;
        repeat (3) begin
            step_cpu(1'b0);
            assert (debug_execution_state == target_state &&
                    debug_a == held_a && debug_x == held_x &&
                    debug_y == held_y && debug_sp == held_sp &&
                    debug_pc == held_pc && debug_status == held_status &&
                    bus_address == held_bus_address &&
                    bus_write_data == held_bus_data &&
                    bus_write_enable == held_bus_write &&
                    bus_valid == held_bus_valid &&
                    memory_write_count == held_write_count)
                else $fatal(1, "cpu_enable stall changed Phase 2F state");
        end
        cpu_enable = 1'b1;
        step_cpu(1'b0);
        assert (debug_execution_state != target_state)
            else $fatal(1, "Phase 2F state did not resume after stall");
        stall_check_count++;
    endtask

    task automatic test_unsupported_trap;
        logic [15:0] trapped_pc;
        memory_model.memory[PROGRAM_START] = 8'h00; // BRK remains excluded.
        reset_core();
        step_cpu(1'b0);
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_TRAP &&
                !bus_valid && !bus_write_enable && memory_write_count == 0)
            else $fatal(1, "unsupported opcode did not trap inertly");
        trapped_pc = debug_pc;
        repeat (3) begin
            step_cpu(1'b0);
            assert (debug_execution_state == CPU_STATE_TRAP &&
                    debug_pc == trapped_pc && !bus_valid &&
                    !bus_write_enable && memory_write_count == 0)
                else $fatal(1, "unsupported trap was not stable");
        end
    endtask

    initial begin
        $dumpfile("build/sim/cpu_phase2f.fst");
        $dumpvars(0, cpu_phase2f_tb);

        for (int unsigned branch_index = 0;
             branch_index < 8; branch_index++) begin
            for (int unsigned taken = 0; taken < 2; taken++) begin
                for (int unsigned address_index = 0;
                     address_index < 6; address_index++) begin
                    test_branch(branch_index[2:0], taken[0],
                                address_index[2:0]);
                end
            end
        end

        for (int unsigned index = 0; index < 9; index++) begin
            test_jmp_absolute(BOUNDARY_TARGETS[index]);
        end
        test_jmp_indirect(16'h1234, 16'h1235, 16'h8000);
        test_jmp_indirect(16'h12FF, 16'h1200, 16'hBEEF);
        test_jmp_indirect(16'hFFFF, 16'hFF00, 16'h0001);

        for (int unsigned sp_index = 0; sp_index < 3; sp_index++) begin
            for (int unsigned value_index = 0;
                 value_index < 5; value_index++) begin
                test_pha(STACK_POINTERS[sp_index], STACK_VALUES[value_index]);
                test_pla(STACK_POINTERS[sp_index], STACK_VALUES[value_index]);
            end
            for (int unsigned status_index = 0;
                 status_index < 8; status_index++) begin
                test_php(STACK_POINTERS[sp_index], STATUS_VALUES[status_index]);
                test_plp(STACK_POINTERS[sp_index], STATUS_VALUES[status_index]);
            end
            for (int unsigned target_index = 0;
                 target_index < 9; target_index++) begin
                test_jsr(STACK_POINTERS[sp_index],
                         BOUNDARY_TARGETS[target_index]);
                test_rts(STACK_POINTERS[sp_index],
                         BOUNDARY_TARGETS[target_index]);
            end
        end
        test_jsr_rts_round_trip();

        test_stall(CPU_STATE_OPERAND_LOW);
        test_stall(CPU_STATE_BRANCH_DECIDE);
        test_stall(CPU_STATE_STACK_PUSH);
        test_stall(CPU_STATE_STACK_READ);
        test_stall(CPU_STATE_JSR_PUSH_HIGH);
        test_stall(CPU_STATE_JSR_PUSH_LOW);
        test_stall(CPU_STATE_RTS_PULL_LOW);
        test_stall(CPU_STATE_RTS_PULL_HIGH);
        test_stall(CPU_STATE_POINTER_LOW);
        test_stall(CPU_STATE_POINTER_HIGH);
        test_unsupported_trap();

        assert (directed_vector_count == DIRECTED_VECTOR_COUNT)
            else $fatal(1, "Phase 2F vector count mismatch: %0d",
                        directed_vector_count);
        assert (stall_check_count == 10)
            else $fatal(1, "Phase 2F stall check count mismatch");
        $display("PASS: Phase 2F control/stack verification (%0d directed vectors, %0d stall checks)",
                 directed_vector_count, stall_check_count);
        $finish;
    end
endmodule
