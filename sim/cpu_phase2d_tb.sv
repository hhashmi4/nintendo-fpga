`timescale 1ns/1ps

module cpu_phase2d_tb;
    import cpu_pkg::*;

    localparam logic [15:0] PROGRAM_START = 16'h0200;
    localparam int unsigned OPCODE_COUNT = 37;
    localparam int unsigned BOUNDARY_VALUE_COUNT = 6;
    localparam int unsigned DIRECTED_VECTOR_COUNT =
        OPCODE_COUNT * BOUNDARY_VALUE_COUNT;

    localparam logic [7:0] OPCODES [0:OPCODE_COUNT-1] = '{
        // LDA
        8'hA9, 8'hA5, 8'hB5, 8'hAD, 8'hBD, 8'hB9, 8'hA1, 8'hB1,
        // LDX
        8'hA2, 8'hA6, 8'hB6, 8'hAE, 8'hBE,
        // LDY
        8'hA0, 8'hA4, 8'hB4, 8'hAC, 8'hBC,
        // STA, STX, STY
        8'h85, 8'h95, 8'h8D, 8'h9D, 8'h99, 8'h81, 8'h91,
        8'h86, 8'h96, 8'h8E,
        8'h84, 8'h94, 8'h8C,
        // Transfers
        8'hAA, 8'hA8, 8'h8A, 8'h98, 8'hBA, 8'h9A
    };

    localparam cpu_instruction_t INSTRUCTIONS [0:OPCODE_COUNT-1] = '{
        CPU_INSTR_LDA, CPU_INSTR_LDA, CPU_INSTR_LDA, CPU_INSTR_LDA,
        CPU_INSTR_LDA, CPU_INSTR_LDA, CPU_INSTR_LDA, CPU_INSTR_LDA,
        CPU_INSTR_LDX, CPU_INSTR_LDX, CPU_INSTR_LDX, CPU_INSTR_LDX,
        CPU_INSTR_LDX,
        CPU_INSTR_LDY, CPU_INSTR_LDY, CPU_INSTR_LDY, CPU_INSTR_LDY,
        CPU_INSTR_LDY,
        CPU_INSTR_STA, CPU_INSTR_STA, CPU_INSTR_STA, CPU_INSTR_STA,
        CPU_INSTR_STA, CPU_INSTR_STA, CPU_INSTR_STA,
        CPU_INSTR_STX, CPU_INSTR_STX, CPU_INSTR_STX,
        CPU_INSTR_STY, CPU_INSTR_STY, CPU_INSTR_STY,
        CPU_INSTR_TAX, CPU_INSTR_TAY, CPU_INSTR_TXA, CPU_INSTR_TYA,
        CPU_INSTR_TSX, CPU_INSTR_TXS
    };

    localparam logic [3:0] MODES [0:OPCODE_COUNT-1] = '{
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_Y,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X,
        CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_Y, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_IMPLIED, CPU_ADDR_IMPLIED, CPU_ADDR_IMPLIED,
        CPU_ADDR_IMPLIED, CPU_ADDR_IMPLIED, CPU_ADDR_IMPLIED
    };

    localparam logic [7:0] BOUNDARY_VALUES [0:5] = '{
        8'h00, 8'h01, 8'h7F, 8'h80, 8'hFE, 8'hFF
    };

    localparam logic [15:0] BOUNDARY_ADDRESSES [0:9] = '{
        16'h0000, 16'h0001, 16'h00FE, 16'h00FF, 16'h0100,
        16'h7FFF, 16'h8000, 16'hFF00, 16'hFFFE, 16'hFFFF
    };

    localparam logic [15:0] POINTER_TARGETS [0:5] = '{
        16'h0100, 16'h7FFF, 16'h8000,
        16'hFF00, 16'hFFFE, 16'hFFFF
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

    logic [15:0] trace_address [0:7];
    logic [7:0] trace_write_data [0:7];
    logic [7:0] trace_read_data [0:7];
    logic trace_write_enable [0:7];
    int unsigned trace_count = 0;
    // Sized for the shared Phase 2E instruction enum so enum-valued indices
    // remain width-clean while this regression still exercises IDs 1..12.
    int unsigned instruction_vector_count [0:30];

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

    function automatic logic [7:0] status_with_nz(
        input logic [7:0] previous_status,
        input logic [7:0] value
    );
        logic [7:0] updated;
        updated = previous_status;
        updated[7] = value[7];
        updated[1] = (value == 8'h00);
        return updated;
    endfunction

    function automatic logic instruction_is_load(
        input cpu_instruction_t instruction
    );
        return instruction == CPU_INSTR_LDA ||
               instruction == CPU_INSTR_LDX ||
               instruction == CPU_INSTR_LDY;
    endfunction

    function automatic logic instruction_is_store(
        input cpu_instruction_t instruction
    );
        return instruction == CPU_INSTR_STA ||
               instruction == CPU_INSTR_STX ||
               instruction == CPU_INSTR_STY;
    endfunction

    function automatic int unsigned mode_operand_bytes(
        input logic [3:0] mode
    );
        if (mode == CPU_ADDR_IMPLIED) begin
            return 0;
        end
        if (mode == CPU_ADDR_ABSOLUTE ||
            mode == CPU_ADDR_ABSOLUTE_X ||
            mode == CPU_ADDR_ABSOLUTE_Y) begin
            return 2;
        end
        return 1;
    endfunction

    function automatic int unsigned expected_enabled_steps(
        input logic [3:0] mode,
        input logic is_load
    );
        if (mode == CPU_ADDR_IMPLIED) begin
            return 3;
        end
        if (mode == CPU_ADDR_IMMEDIATE) begin
            return 5;
        end
        if (mode == CPU_ADDR_INDEXED_INDIRECT_X ||
            mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
            return is_load ? 9 : 8;
        end
        if (mode == CPU_ADDR_ABSOLUTE ||
            mode == CPU_ADDR_ABSOLUTE_X ||
            mode == CPU_ADDR_ABSOLUTE_Y) begin
            return is_load ? 7 : 6;
        end
        return is_load ? 6 : 5;
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
        @(negedge clk);
        if (record_bus && cpu_enable && bus_valid) begin
            assert (trace_count < 8)
                else $fatal(1, "bus trace overflow");
            trace_address[trace_count] = bus_address;
            trace_write_data[trace_count] = bus_write_data;
            trace_read_data[trace_count] = bus_read_data;
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
            else $fatal(1, "X/Z detected in Phase 2D CPU or bus state");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write_enable asserted without bus_valid");
    endtask

    task automatic reset_core;
        reset = 1'b1;
        cpu_enable = 1'b0;
        step_cpu(1'b0);
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_RESET)
            else $fatal(1, "reset did not enter RESET state");
        assert (debug_pc == PROGRAM_START &&
                debug_a == CPU_RESET_A && debug_x == CPU_RESET_X &&
                debug_y == CPU_RESET_Y && debug_sp == CPU_RESET_SP &&
                debug_status == CPU_RESET_STATUS)
            else $fatal(1, "architectural reset mismatch");
        assert (!bus_valid && !bus_write_enable && memory_write_count == 0)
            else $fatal(1, "reset left an active bus or write log");

        reset = 1'b0;
        cpu_enable = 1'b1;
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == PROGRAM_START)
            else $fatal(1, "CPU did not enter FETCH after reset");
    endtask

    task automatic execute_current_instruction(
        input logic record_bus,
        output int unsigned enabled_steps
    );
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not start in FETCH");
        enabled_steps = 0;
        do begin
            step_cpu(record_bus);
            enabled_steps++;
            assert (enabled_steps < 20)
                else $fatal(1, "instruction failed to complete");
        end while (debug_execution_state != CPU_STATE_FETCH);
    endtask

    task automatic run_directed_vector(
        input int unsigned opcode_index,
        input int unsigned variant
    );
        logic [7:0] opcode;
        cpu_instruction_t instruction;
        logic [3:0] mode;
        logic [7:0] value;
        logic [7:0] index_value;
        logic [7:0] operand;
        logic [15:0] base_address;
        logic [15:0] target_address;
        logic [15:0] pointer_base;
        logic [15:0] pointer_low_address;
        logic [15:0] pointer_high_address;
        logic [15:0] cursor;
        logic [15:0] target_pc;
        logic [15:0] expected_pc;
        logic [7:0] before_a;
        logic [7:0] before_x;
        logic [7:0] before_y;
        logic [7:0] before_sp;
        logic [7:0] before_status;
        logic expected_page_cross;
        logic expected_page_cross_valid;
        int unsigned enabled_steps;
        int unsigned setup_steps;
        int unsigned event_index;

        opcode = OPCODES[opcode_index];
        instruction = INSTRUCTIONS[opcode_index];
        mode = MODES[opcode_index];
        value = BOUNDARY_VALUES[variant];
        index_value = BOUNDARY_VALUES[variant];
        operand = BOUNDARY_VALUES[(variant + 2) % BOUNDARY_VALUE_COUNT];
        base_address =
            BOUNDARY_ADDRESSES[(opcode_index + variant) % 10];
        target_address = 16'h0000;
        pointer_base = 16'h0000;
        pointer_low_address = 16'h0000;
        pointer_high_address = 16'h0000;
        expected_page_cross = 1'b0;
        expected_page_cross_valid = 1'b0;

        // Assert reset before rewriting the generic memory image.
        reset = 1'b1;
        cpu_enable = 1'b0;
        cursor = PROGRAM_START;

        // Establish source/index registers through already-supported loads.
        case (instruction)
            CPU_INSTR_LDA: begin
                if (mode == CPU_ADDR_ZERO_PAGE_X ||
                    mode == CPU_ADDR_ABSOLUTE_X ||
                    mode == CPU_ADDR_INDEXED_INDIRECT_X) begin
                    append_immediate(cursor, 8'hA2, index_value);
                end else if (mode == CPU_ADDR_ABSOLUTE_Y ||
                             mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
                    append_immediate(cursor, 8'hA0, index_value);
                end
            end

            CPU_INSTR_LDX: begin
                if (mode == CPU_ADDR_ZERO_PAGE_Y ||
                    mode == CPU_ADDR_ABSOLUTE_Y) begin
                    append_immediate(cursor, 8'hA0, index_value);
                end
            end

            CPU_INSTR_LDY: begin
                if (mode == CPU_ADDR_ZERO_PAGE_X ||
                    mode == CPU_ADDR_ABSOLUTE_X) begin
                    append_immediate(cursor, 8'hA2, index_value);
                end
            end

            CPU_INSTR_STA: begin
                append_immediate(cursor, 8'hA9, value);
                if (mode == CPU_ADDR_ZERO_PAGE_X ||
                    mode == CPU_ADDR_ABSOLUTE_X ||
                    mode == CPU_ADDR_INDEXED_INDIRECT_X) begin
                    append_immediate(cursor, 8'hA2, index_value);
                end else if (mode == CPU_ADDR_ABSOLUTE_Y ||
                             mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
                    append_immediate(cursor, 8'hA0, index_value);
                end
            end

            CPU_INSTR_STX: begin
                append_immediate(cursor, 8'hA2, value);
                if (mode == CPU_ADDR_ZERO_PAGE_Y) begin
                    append_immediate(cursor, 8'hA0, index_value);
                end
            end

            CPU_INSTR_STY: begin
                append_immediate(cursor, 8'hA0, value);
                if (mode == CPU_ADDR_ZERO_PAGE_X) begin
                    append_immediate(cursor, 8'hA2, index_value);
                end
            end

            CPU_INSTR_TAX,
            CPU_INSTR_TAY: append_immediate(cursor, 8'hA9, value);

            CPU_INSTR_TXA,
            CPU_INSTR_TXS: append_immediate(cursor, 8'hA2, value);

            CPU_INSTR_TYA: append_immediate(cursor, 8'hA0, value);

            CPU_INSTR_TSX: begin
                append_immediate(cursor, 8'hA2, value);
                append_byte(cursor, 8'h9A);
            end

            default: begin
                // Every table entry is one of the explicit instructions.
            end
        endcase

        target_pc = cursor;
        append_byte(cursor, opcode);

        case (mode)
            CPU_ADDR_IMPLIED: begin
                // No operand or memory target.
            end

            CPU_ADDR_IMMEDIATE: begin
                append_byte(cursor, value);
            end

            CPU_ADDR_ZERO_PAGE: begin
                target_address = {8'h00, operand};
                append_byte(cursor, operand);
            end

            CPU_ADDR_ZERO_PAGE_X: begin
                target_address = {8'h00, 8'(operand + index_value)};
                append_byte(cursor, operand);
            end

            CPU_ADDR_ZERO_PAGE_Y: begin
                target_address = {8'h00, 8'(operand + index_value)};
                append_byte(cursor, operand);
            end

            CPU_ADDR_ABSOLUTE: begin
                target_address = base_address;
                append_byte(cursor, base_address[7:0]);
                append_byte(cursor, base_address[15:8]);
            end

            CPU_ADDR_ABSOLUTE_X,
            CPU_ADDR_ABSOLUTE_Y: begin
                target_address = 16'(base_address + index_value);
                expected_page_cross =
                    ({1'b0, base_address[7:0]} +
                     {1'b0, index_value}) > 9'h0FF;
                expected_page_cross_valid = 1'b1;
                append_byte(cursor, base_address[7:0]);
                append_byte(cursor, base_address[15:8]);
            end

            CPU_ADDR_INDEXED_INDIRECT_X: begin
                target_address = POINTER_TARGETS[variant];
                pointer_low_address =
                    {8'h00, 8'(operand + index_value)};
                pointer_high_address =
                    {8'h00, 8'({1'b0, operand} +
                               {1'b0, index_value} + 9'd1)};
                memory_model.memory[pointer_low_address] =
                    target_address[7:0];
                memory_model.memory[pointer_high_address] =
                    target_address[15:8];
                append_byte(cursor, operand);
            end

            CPU_ADDR_INDIRECT_INDEXED_Y: begin
                target_address = POINTER_TARGETS[variant];
                pointer_base = 16'(target_address - index_value);
                pointer_low_address = {8'h00, operand};
                pointer_high_address = {8'h00, 8'(operand + 1)};
                memory_model.memory[pointer_low_address] =
                    pointer_base[7:0];
                memory_model.memory[pointer_high_address] =
                    pointer_base[15:8];
                expected_page_cross =
                    ({1'b0, pointer_base[7:0]} +
                     {1'b0, index_value}) > 9'h0FF;
                expected_page_cross_valid = 1'b1;
                append_byte(cursor, operand);
            end

            default: begin
                $fatal(1, "unexpected mode in Phase 2D vector");
            end
        endcase

        if (instruction_is_load(instruction)) begin
            if (mode != CPU_ADDR_IMMEDIATE) begin
                memory_model.memory[target_address] = value;
            end
        end else if (instruction_is_store(instruction)) begin
            memory_model.memory[target_address] = value ^ 8'hFF;
        end

        expected_pc = target_pc + 16'(1 + mode_operand_bytes(mode));
        reset_core();

        // Execute setup instructions without including them in target trace.
        while (debug_pc != target_pc) begin
            execute_current_instruction(1'b0, setup_steps);
            assert (setup_steps > 0)
                else $fatal(1, "setup instruction did not advance");
            assert (debug_pc <= target_pc)
                else $fatal(1, "setup program advanced past target");
        end

        before_a = debug_a;
        before_x = debug_x;
        before_y = debug_y;
        before_sp = debug_sp;
        before_status = debug_status;
        trace_count = 0;
        execute_current_instruction(1'b1, enabled_steps);

        assert (enabled_steps ==
                expected_enabled_steps(mode, instruction_is_load(instruction)))
            else $fatal(1, "cycle scaffold mismatch opcode=%02h steps=%0d",
                        opcode, enabled_steps);
        assert (debug_instruction == opcode &&
                debug_decoded_instruction == instruction &&
                debug_addressing_mode == mode)
            else $fatal(1, "decode mismatch for opcode=%02h", opcode);
        assert (debug_pc == expected_pc)
            else $fatal(1, "PC mismatch opcode=%02h expected=%04h got=%04h",
                        opcode, expected_pc, debug_pc);

        if (instruction == CPU_INSTR_LDA) begin
            assert (debug_a == value && debug_x == before_x &&
                    debug_y == before_y && debug_sp == before_sp)
                else $fatal(1, "LDA register mismatch opcode=%02h", opcode);
            assert (debug_status == status_with_nz(before_status, value))
                else $fatal(1, "LDA flag mismatch opcode=%02h", opcode);
        end else if (instruction == CPU_INSTR_LDX) begin
            assert (debug_x == value && debug_a == before_a &&
                    debug_y == before_y && debug_sp == before_sp)
                else $fatal(1, "LDX register mismatch opcode=%02h", opcode);
            assert (debug_status == status_with_nz(before_status, value))
                else $fatal(1, "LDX flag mismatch opcode=%02h", opcode);
        end else if (instruction == CPU_INSTR_LDY) begin
            assert (debug_y == value && debug_a == before_a &&
                    debug_x == before_x && debug_sp == before_sp)
                else $fatal(1, "LDY register mismatch opcode=%02h", opcode);
            assert (debug_status == status_with_nz(before_status, value))
                else $fatal(1, "LDY flag mismatch opcode=%02h", opcode);
        end else if (instruction_is_store(instruction)) begin
            assert (debug_a == before_a && debug_x == before_x &&
                    debug_y == before_y && debug_sp == before_sp &&
                    debug_status == before_status)
                else $fatal(1, "store corrupted CPU state opcode=%02h", opcode);
            assert (memory_write_count == 1 &&
                    last_write_address == target_address &&
                    last_write_data == value &&
                    memory_model.memory[target_address] == value)
                else $fatal(1, "store bus result mismatch opcode=%02h", opcode);
        end else begin
            case (instruction)
                CPU_INSTR_TAX: assert (
                    debug_x == value && debug_a == value &&
                    debug_y == before_y && debug_sp == before_sp
                );
                CPU_INSTR_TAY: assert (
                    debug_y == value && debug_a == value &&
                    debug_x == before_x && debug_sp == before_sp
                );
                CPU_INSTR_TXA: assert (
                    debug_a == value && debug_x == value &&
                    debug_y == before_y && debug_sp == before_sp
                );
                CPU_INSTR_TYA: assert (
                    debug_a == value && debug_y == value &&
                    debug_x == before_x && debug_sp == before_sp
                );
                CPU_INSTR_TSX: assert (
                    debug_x == value && debug_sp == value &&
                    debug_a == before_a && debug_y == before_y
                );
                CPU_INSTR_TXS: assert (
                    debug_sp == value && debug_x == value &&
                    debug_a == before_a && debug_y == before_y
                );
                default: $fatal(1, "unexpected transfer instruction");
            endcase
            assert (debug_status ==
                    ((instruction == CPU_INSTR_TXS)
                     ? before_status : status_with_nz(before_status, value)))
                else $fatal(1, "transfer flag mismatch opcode=%02h", opcode);
            assert (memory_write_count == 0)
                else $fatal(1, "transfer caused a memory write");
        end

        if (instruction_is_load(instruction)) begin
            assert (memory_write_count == 0)
                else $fatal(1, "load caused a memory write opcode=%02h", opcode);
        end

        if (mode != CPU_ADDR_IMPLIED && mode != CPU_ADDR_IMMEDIATE) begin
            assert (debug_effective_address == target_address)
                else $fatal(1, "effective-address mismatch opcode=%02h", opcode);
            assert (debug_page_cross == expected_page_cross &&
                    debug_page_cross_valid == expected_page_cross_valid)
                else $fatal(1, "page metadata mismatch opcode=%02h", opcode);
        end

        // Check exact target-instruction bus ordering and write placement.
        event_index = 0;
        assert (!trace_write_enable[event_index] &&
                trace_address[event_index] == target_pc &&
                trace_read_data[event_index] == opcode)
            else $fatal(1, "opcode fetch trace mismatch opcode=%02h", opcode);
        event_index++;

        if (mode_operand_bytes(mode) >= 1) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == target_pc + 16'd1)
                else $fatal(1, "low operand trace mismatch opcode=%02h", opcode);
            event_index++;
        end
        if (mode_operand_bytes(mode) == 2) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == target_pc + 16'd2)
                else $fatal(1, "high operand trace mismatch opcode=%02h", opcode);
            event_index++;
        end
        if (mode == CPU_ADDR_INDEXED_INDIRECT_X ||
            mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == pointer_low_address)
                else $fatal(1, "pointer-low trace mismatch opcode=%02h", opcode);
            event_index++;
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == pointer_high_address)
                else $fatal(1, "pointer-high trace mismatch opcode=%02h", opcode);
            event_index++;
        end
        if (mode != CPU_ADDR_IMPLIED && mode != CPU_ADDR_IMMEDIATE) begin
            assert (trace_address[event_index] == target_address &&
                    trace_write_enable[event_index] ==
                    instruction_is_store(instruction))
                else $fatal(1, "final bus trace mismatch opcode=%02h", opcode);
            if (instruction_is_store(instruction)) begin
                assert (trace_write_data[event_index] == value)
                    else $fatal(1, "store data trace mismatch opcode=%02h", opcode);
            end else begin
                assert (trace_read_data[event_index] == value)
                    else $fatal(1, "load data trace mismatch opcode=%02h", opcode);
            end
            event_index++;
        end
        assert (trace_count == event_index)
            else $fatal(1, "unexpected bus cycle count opcode=%02h", opcode);

        instruction_vector_count[instruction]++;
    endtask

    task automatic test_enable_gating_during_store;
        logic [7:0] held_a;
        logic [7:0] held_x;
        logic [7:0] held_y;
        logic [7:0] held_sp;
        logic [15:0] held_pc;
        logic [7:0] held_status;
        int unsigned steps;

        reset = 1'b1;
        cpu_enable = 1'b0;
        memory_model.memory[PROGRAM_START] = 8'hA9;
        memory_model.memory[PROGRAM_START + 1] = 8'hA5;
        memory_model.memory[PROGRAM_START + 2] = 8'h8D;
        memory_model.memory[PROGRAM_START + 3] = 8'hFF;
        memory_model.memory[PROGRAM_START + 4] = 8'h7F;
        memory_model.memory[16'h7FFF] = 8'h00;
        reset_core();
        execute_current_instruction(1'b0, steps);
        assert (steps > 0)
            else $fatal(1, "gating setup instruction did not advance");

        // Advance STA until its write cycle is presented but not consumed.
        do begin
            step_cpu(1'b0);
        end while (debug_execution_state != CPU_STATE_MEMORY_WRITE);
        assert (bus_valid && bus_write_enable &&
                bus_address == 16'h7FFF && bus_write_data == 8'hA5 &&
                memory_write_count == 0)
            else $fatal(1, "store cycle was not presented correctly");

        held_a = debug_a;
        held_x = debug_x;
        held_y = debug_y;
        held_sp = debug_sp;
        held_pc = debug_pc;
        held_status = debug_status;
        cpu_enable = 1'b0;
        repeat (4) begin
            step_cpu(1'b0);
            assert (debug_execution_state == CPU_STATE_MEMORY_WRITE &&
                    debug_a == held_a && debug_x == held_x &&
                    debug_y == held_y && debug_sp == held_sp &&
                    debug_pc == held_pc && debug_status == held_status)
                else $fatal(1, "CPU state advanced while cpu_enable was low");
            assert (bus_valid && bus_write_enable &&
                    bus_address == 16'h7FFF && bus_write_data == 8'hA5 &&
                    memory_write_count == 0)
                else $fatal(1, "stalled store bus was not stable");
        end

        cpu_enable = 1'b1;
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                memory_write_count == 1 &&
                memory_model.memory[16'h7FFF] == 8'hA5)
            else $fatal(1, "enabled store did not commit exactly once");
    endtask

    task automatic test_unsupported_opcode;
        reset = 1'b1;
        cpu_enable = 1'b0;
        memory_model.memory[PROGRAM_START] = 8'h02;
        memory_model.memory[PROGRAM_START + 1] = 8'hA9;
        reset_core();
        step_cpu(1'b0); // FETCH -> DECODE
        step_cpu(1'b0); // DECODE -> TRAP
        assert (debug_execution_state == CPU_STATE_TRAP &&
                debug_pc == PROGRAM_START + 16'd1 &&
                debug_instruction == 8'h02 &&
                debug_decoded_instruction == CPU_INSTR_INVALID)
            else $fatal(1, "unsupported opcode did not enter deterministic trap");
        assert (!bus_valid && !bus_write_enable && memory_write_count == 0 &&
                debug_a == CPU_RESET_A && debug_x == CPU_RESET_X &&
                debug_y == CPU_RESET_Y && debug_sp == CPU_RESET_SP &&
                debug_status == CPU_RESET_STATUS)
            else $fatal(1, "unsupported opcode caused an architectural effect");
        repeat (3) begin
            step_cpu(1'b0);
            assert (debug_execution_state == CPU_STATE_TRAP &&
                    !bus_valid && !bus_write_enable &&
                    memory_write_count == 0)
                else $fatal(1, "trap state was not inert");
        end
    endtask

    initial begin
        int unsigned total_vectors;

        $dumpfile("build/sim/cpu_phase2d.fst");
        $dumpvars(0, cpu_phase2d_tb);

        // Let the memory model's time-zero deterministic clear complete
        // before the first vector installs its program image.
        #1;

        for (int unsigned instruction = 0; instruction < 31; instruction++) begin
            instruction_vector_count[instruction] = 0;
        end

        for (int unsigned opcode_index = 0;
             opcode_index < OPCODE_COUNT; opcode_index++) begin
            for (int unsigned variant = 0;
                 variant < BOUNDARY_VALUE_COUNT; variant++) begin
                run_directed_vector(opcode_index, variant);
            end
        end

        assert (instruction_vector_count[CPU_INSTR_LDA] == 48);
        assert (instruction_vector_count[CPU_INSTR_LDX] == 30);
        assert (instruction_vector_count[CPU_INSTR_LDY] == 30);
        assert (instruction_vector_count[CPU_INSTR_STA] == 42);
        assert (instruction_vector_count[CPU_INSTR_STX] == 18);
        assert (instruction_vector_count[CPU_INSTR_STY] == 18);
        assert (instruction_vector_count[CPU_INSTR_TAX] == 6);
        assert (instruction_vector_count[CPU_INSTR_TAY] == 6);
        assert (instruction_vector_count[CPU_INSTR_TXA] == 6);
        assert (instruction_vector_count[CPU_INSTR_TYA] == 6);
        assert (instruction_vector_count[CPU_INSTR_TSX] == 6);
        assert (instruction_vector_count[CPU_INSTR_TXS] == 6);

        total_vectors = 0;
        for (int unsigned instruction = 1; instruction < 13; instruction++) begin
            total_vectors += instruction_vector_count[instruction];
        end
        assert (total_vectors == DIRECTED_VECTOR_COUNT)
            else $fatal(1, "unexpected Phase 2D vector count: %0d",
                        total_vectors);

        test_enable_gating_during_store();
        test_unsupported_opcode();

        $display("PASS: Phase 2D load/store/transfer verification (%0d directed opcode vectors)",
                 total_vectors);
        $finish;
    end
endmodule
