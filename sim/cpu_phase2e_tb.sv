`timescale 1ns/1ps

module cpu_phase2e_tb;
    import cpu_pkg::*;

    localparam logic [15:0] PROGRAM_START = 16'h4000;
    localparam logic [7:0] TEST_RESET_STATUS = 8'h6D;
    localparam int unsigned OPCODE_COUNT = 86;
    localparam int unsigned VALUE_COUNT = 6;
    localparam int unsigned DIRECTED_VECTOR_COUNT =
        OPCODE_COUNT * VALUE_COUNT;

    localparam logic [7:0] OPCODES [0:OPCODE_COUNT-1] = '{
        // ADC, SBC, AND, ORA, EOR, CMP
        8'h69, 8'h65, 8'h75, 8'h6D, 8'h7D, 8'h79, 8'h61, 8'h71,
        8'hE9, 8'hE5, 8'hF5, 8'hED, 8'hFD, 8'hF9, 8'hE1, 8'hF1,
        8'h29, 8'h25, 8'h35, 8'h2D, 8'h3D, 8'h39, 8'h21, 8'h31,
        8'h09, 8'h05, 8'h15, 8'h0D, 8'h1D, 8'h19, 8'h01, 8'h11,
        8'h49, 8'h45, 8'h55, 8'h4D, 8'h5D, 8'h59, 8'h41, 8'h51,
        8'hC9, 8'hC5, 8'hD5, 8'hCD, 8'hDD, 8'hD9, 8'hC1, 8'hD1,
        // CPX, CPY; register INC/DEC; memory INC/DEC
        8'hE0, 8'hE4, 8'hEC, 8'hC0, 8'hC4, 8'hCC,
        8'hE8, 8'hC8, 8'hCA, 8'h88,
        8'hE6, 8'hF6, 8'hEE, 8'hFE, 8'hC6, 8'hD6, 8'hCE, 8'hDE,
        // ASL, LSR, ROL, ROR
        8'h0A, 8'h06, 8'h16, 8'h0E, 8'h1E,
        8'h4A, 8'h46, 8'h56, 8'h4E, 8'h5E,
        8'h2A, 8'h26, 8'h36, 8'h2E, 8'h3E,
        8'h6A, 8'h66, 8'h76, 8'h6E, 8'h7E
    };

    localparam cpu_instruction_t INSTRUCTIONS [0:OPCODE_COUNT-1] = '{
        CPU_INSTR_ADC, CPU_INSTR_ADC, CPU_INSTR_ADC, CPU_INSTR_ADC,
        CPU_INSTR_ADC, CPU_INSTR_ADC, CPU_INSTR_ADC, CPU_INSTR_ADC,
        CPU_INSTR_SBC, CPU_INSTR_SBC, CPU_INSTR_SBC, CPU_INSTR_SBC,
        CPU_INSTR_SBC, CPU_INSTR_SBC, CPU_INSTR_SBC, CPU_INSTR_SBC,
        CPU_INSTR_AND, CPU_INSTR_AND, CPU_INSTR_AND, CPU_INSTR_AND,
        CPU_INSTR_AND, CPU_INSTR_AND, CPU_INSTR_AND, CPU_INSTR_AND,
        CPU_INSTR_ORA, CPU_INSTR_ORA, CPU_INSTR_ORA, CPU_INSTR_ORA,
        CPU_INSTR_ORA, CPU_INSTR_ORA, CPU_INSTR_ORA, CPU_INSTR_ORA,
        CPU_INSTR_EOR, CPU_INSTR_EOR, CPU_INSTR_EOR, CPU_INSTR_EOR,
        CPU_INSTR_EOR, CPU_INSTR_EOR, CPU_INSTR_EOR, CPU_INSTR_EOR,
        CPU_INSTR_CMP, CPU_INSTR_CMP, CPU_INSTR_CMP, CPU_INSTR_CMP,
        CPU_INSTR_CMP, CPU_INSTR_CMP, CPU_INSTR_CMP, CPU_INSTR_CMP,
        CPU_INSTR_CPX, CPU_INSTR_CPX, CPU_INSTR_CPX,
        CPU_INSTR_CPY, CPU_INSTR_CPY, CPU_INSTR_CPY,
        CPU_INSTR_INX, CPU_INSTR_INY, CPU_INSTR_DEX, CPU_INSTR_DEY,
        CPU_INSTR_INC, CPU_INSTR_INC, CPU_INSTR_INC, CPU_INSTR_INC,
        CPU_INSTR_DEC, CPU_INSTR_DEC, CPU_INSTR_DEC, CPU_INSTR_DEC,
        CPU_INSTR_ASL, CPU_INSTR_ASL, CPU_INSTR_ASL, CPU_INSTR_ASL,
        CPU_INSTR_ASL,
        CPU_INSTR_LSR, CPU_INSTR_LSR, CPU_INSTR_LSR, CPU_INSTR_LSR,
        CPU_INSTR_LSR,
        CPU_INSTR_ROL, CPU_INSTR_ROL, CPU_INSTR_ROL, CPU_INSTR_ROL,
        CPU_INSTR_ROL,
        CPU_INSTR_ROR, CPU_INSTR_ROR, CPU_INSTR_ROR, CPU_INSTR_ROR,
        CPU_INSTR_ROR
    };

    localparam logic [3:0] MODES [0:OPCODE_COUNT-1] = '{
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X, CPU_ADDR_ABSOLUTE_Y,
        CPU_ADDR_INDEXED_INDIRECT_X, CPU_ADDR_INDIRECT_INDEXED_Y,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_IMMEDIATE, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_IMPLIED, CPU_ADDR_IMPLIED, CPU_ADDR_IMPLIED,
        CPU_ADDR_IMPLIED,
        CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_ABSOLUTE_X,
        CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X, CPU_ADDR_ABSOLUTE,
        CPU_ADDR_ABSOLUTE_X,
        CPU_ADDR_ACCUMULATOR, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X,
        CPU_ADDR_ACCUMULATOR, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X,
        CPU_ADDR_ACCUMULATOR, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X,
        CPU_ADDR_ACCUMULATOR, CPU_ADDR_ZERO_PAGE, CPU_ADDR_ZERO_PAGE_X,
        CPU_ADDR_ABSOLUTE, CPU_ADDR_ABSOLUTE_X
    };

    localparam cpu_alu_operation_t OPERATIONS [0:OPCODE_COUNT-1] = '{
        CPU_ALU_ADD, CPU_ALU_ADD, CPU_ALU_ADD, CPU_ALU_ADD,
        CPU_ALU_ADD, CPU_ALU_ADD, CPU_ALU_ADD, CPU_ALU_ADD,
        CPU_ALU_SUB, CPU_ALU_SUB, CPU_ALU_SUB, CPU_ALU_SUB,
        CPU_ALU_SUB, CPU_ALU_SUB, CPU_ALU_SUB, CPU_ALU_SUB,
        CPU_ALU_AND, CPU_ALU_AND, CPU_ALU_AND, CPU_ALU_AND,
        CPU_ALU_AND, CPU_ALU_AND, CPU_ALU_AND, CPU_ALU_AND,
        CPU_ALU_OR, CPU_ALU_OR, CPU_ALU_OR, CPU_ALU_OR,
        CPU_ALU_OR, CPU_ALU_OR, CPU_ALU_OR, CPU_ALU_OR,
        CPU_ALU_XOR, CPU_ALU_XOR, CPU_ALU_XOR, CPU_ALU_XOR,
        CPU_ALU_XOR, CPU_ALU_XOR, CPU_ALU_XOR, CPU_ALU_XOR,
        CPU_ALU_CMP, CPU_ALU_CMP, CPU_ALU_CMP, CPU_ALU_CMP,
        CPU_ALU_CMP, CPU_ALU_CMP, CPU_ALU_CMP, CPU_ALU_CMP,
        CPU_ALU_CMP, CPU_ALU_CMP, CPU_ALU_CMP,
        CPU_ALU_CMP, CPU_ALU_CMP, CPU_ALU_CMP,
        CPU_ALU_INC, CPU_ALU_INC, CPU_ALU_DEC, CPU_ALU_DEC,
        CPU_ALU_INC, CPU_ALU_INC, CPU_ALU_INC, CPU_ALU_INC,
        CPU_ALU_DEC, CPU_ALU_DEC, CPU_ALU_DEC, CPU_ALU_DEC,
        CPU_ALU_ASL, CPU_ALU_ASL, CPU_ALU_ASL, CPU_ALU_ASL,
        CPU_ALU_ASL,
        CPU_ALU_LSR, CPU_ALU_LSR, CPU_ALU_LSR, CPU_ALU_LSR,
        CPU_ALU_LSR,
        CPU_ALU_ROL, CPU_ALU_ROL, CPU_ALU_ROL, CPU_ALU_ROL,
        CPU_ALU_ROL,
        CPU_ALU_ROR, CPU_ALU_ROR, CPU_ALU_ROR, CPU_ALU_ROR,
        CPU_ALU_ROR
    };

    localparam logic [7:0] BOUNDARY_VALUES [0:VALUE_COUNT-1] = '{
        8'h00, 8'h01, 8'h7F, 8'h80, 8'hFE, 8'hFF
    };
    localparam logic [15:0] BOUNDARY_ADDRESSES [0:9] = '{
        16'h0000, 16'h0001, 16'h00FE, 16'h00FF, 16'h0100,
        16'h7FFF, 16'h8000, 16'hFF00, 16'hFFFE, 16'hFFFF
    };

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
    int unsigned alu_observation_count = 0;
    // The shared instruction enum now extends through Phase 2F; this Phase 2E
    // regression still accumulates only IDs through ROR.
    int unsigned instruction_vector_count [0:45];

    cpu_alu_operation_t expected_alu_operation;
    logic [7:0] expected_alu_operand_a;
    logic [7:0] expected_alu_operand_b;
    logic expected_alu_carry_in;
    logic [7:0] expected_alu_result;
    logic expected_result_valid;
    logic expected_negative;
    logic expected_overflow;
    logic expected_zero;
    logic expected_carry;
    logic expected_n_valid;
    logic expected_v_valid;
    logic expected_z_valid;
    logic expected_c_valid;

    cpu_core #(
        .INITIAL_STATUS (TEST_RESET_STATUS)
    ) dut (
        .clk                       (clk),
        .reset                     (reset),
        .cpu_enable                (cpu_enable),
        .nmi                       (nmi),
        .irq                       (irq),
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

    function automatic logic instruction_is_compare(
        input cpu_instruction_t instruction
    );
        return instruction == CPU_INSTR_CMP ||
               instruction == CPU_INSTR_CPX ||
               instruction == CPU_INSTR_CPY;
    endfunction

    function automatic logic instruction_is_memory_rmw(
        input cpu_instruction_t instruction,
        input logic [3:0] mode
    );
        return instruction == CPU_INSTR_INC ||
               instruction == CPU_INSTR_DEC ||
               ((instruction == CPU_INSTR_ASL ||
                 instruction == CPU_INSTR_LSR ||
                 instruction == CPU_INSTR_ROL ||
                 instruction == CPU_INSTR_ROR) &&
                mode != CPU_ADDR_ACCUMULATOR);
    endfunction

    function automatic int unsigned mode_operand_bytes(
        input logic [3:0] mode
    );
        if (mode == CPU_ADDR_IMPLIED || mode == CPU_ADDR_ACCUMULATOR) begin
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
        input logic is_rmw,
        input logic page_cross
    );
        if (mode == CPU_ADDR_IMPLIED || mode == CPU_ADDR_ACCUMULATOR) begin
            return 2;
        end
        if (mode == CPU_ADDR_IMMEDIATE) begin
            return 2;
        end
        if (mode == CPU_ADDR_INDEXED_INDIRECT_X) begin
            return 6;
        end
        if (mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
            return page_cross ? 6 : 5;
        end
        if (mode == CPU_ADDR_ABSOLUTE_X || mode == CPU_ADDR_ABSOLUTE_Y) begin
            if (is_rmw) return 7;
            return page_cross ? 5 : 4;
        end
        if (mode == CPU_ADDR_ABSOLUTE) return is_rmw ? 6 : 4;
        if (mode == CPU_ADDR_ZERO_PAGE_X) return is_rmw ? 6 : 4;
        return is_rmw ? 5 : 3;
    endfunction

    function automatic logic [7:0] status_with_alu_flags(
        input logic [7:0] previous_status
    );
        logic [7:0] updated;
        updated = previous_status;
        if (expected_n_valid) updated[7] = expected_negative;
        if (expected_v_valid) updated[6] = expected_overflow;
        if (expected_z_valid) updated[1] = expected_zero;
        if (expected_c_valid) updated[0] = expected_carry;
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

    task automatic step_cpu(input logic record_target);
        @(negedge clk);
        if (record_target && cpu_enable && bus_valid) begin
            assert (trace_count < 8)
                else $fatal(1, "Phase 2E bus trace overflow");
            trace_address[trace_count] = bus_address;
            trace_write_data[trace_count] = bus_write_data;
            trace_read_data[trace_count] = bus_read_data;
            trace_write_enable[trace_count] = bus_write_enable;
            trace_count++;
        end

        if (record_target && cpu_enable &&
            (debug_execution_state == CPU_STATE_ALU_EXECUTE ||
             (debug_execution_state == CPU_STATE_OPERAND_LOW &&
              debug_addressing_mode == CPU_ADDR_IMMEDIATE) ||
             debug_execution_state == CPU_STATE_MEMORY_READ ||
             (debug_execution_state == CPU_STATE_INDEXED_READ &&
              !dut.address_response.page_cross))) begin
            assert (dut.alu_operation == expected_alu_operation &&
                    dut.alu_operand_a == expected_alu_operand_a &&
                    dut.alu_operand_b == expected_alu_operand_b &&
                    dut.alu_carry_in == expected_alu_carry_in)
                else $fatal(1, "ALU selection/operand mismatch opcode=%02h",
                            debug_instruction);
            assert (dut.alu_result == expected_alu_result &&
                    dut.alu_result_valid == expected_result_valid &&
                    dut.alu_negative == expected_negative &&
                    dut.alu_overflow == expected_overflow &&
                    dut.alu_zero == expected_zero &&
                    dut.alu_carry == expected_carry)
                else $fatal(1, "ALU result/flag mismatch opcode=%02h",
                            debug_instruction);
            assert (dut.alu_n_valid == expected_n_valid &&
                    dut.alu_v_valid == expected_v_valid &&
                    dut.alu_z_valid == expected_z_valid &&
                    dut.alu_c_valid == expected_c_valid)
                else $fatal(1, "ALU validity mismatch opcode=%02h",
                            debug_instruction);
            alu_observation_count++;
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
                             last_write_address, last_write_data,
                             dut.alu_operation, dut.alu_operand_a,
                             dut.alu_operand_b, dut.alu_carry_in,
                             dut.alu_result, dut.alu_result_valid,
                             dut.alu_negative, dut.alu_overflow,
                             dut.alu_zero, dut.alu_carry,
                             dut.alu_n_valid, dut.alu_v_valid,
                             dut.alu_z_valid, dut.alu_c_valid}))
            else $fatal(1, "X/Z detected in Phase 2E CPU, ALU, or bus state");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write_enable asserted without bus_valid");
    endtask

    task automatic reset_core;
        logic [7:0] saved_vector_low;
        logic [7:0] saved_vector_high;
        saved_vector_low = memory_model.memory[CPU_VECTOR_RESET_LOW];
        saved_vector_high = memory_model.memory[CPU_VECTOR_RESET_LOW + 16'd1];
        memory_model.memory[CPU_VECTOR_RESET_LOW] = PROGRAM_START[7:0];
        memory_model.memory[CPU_VECTOR_RESET_LOW + 16'd1] =
            PROGRAM_START[15:8];
        reset = 1'b1;
        cpu_enable = 1'b0;
        step_cpu(1'b0);
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_RESET &&
                debug_pc == CPU_RESET_PC &&
                debug_a == CPU_RESET_A && debug_x == CPU_RESET_X &&
                debug_y == CPU_RESET_Y && debug_sp == CPU_RESET_SP &&
                debug_status == TEST_RESET_STATUS)
            else $fatal(1, "Phase 2E reset mismatch");
        assert (!bus_valid && !bus_write_enable && memory_write_count == 0)
            else $fatal(1, "reset left active bus/write state");

        reset = 1'b0;
        cpu_enable = 1'b1;
        repeat (7) step_cpu(1'b0);
        memory_model.memory[CPU_VECTOR_RESET_LOW] = saved_vector_low;
        memory_model.memory[CPU_VECTOR_RESET_LOW + 16'd1] = saved_vector_high;
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == PROGRAM_START)
            else $fatal(1, "CPU did not enter FETCH after reset");
    endtask

    task automatic execute_current_instruction(
        input logic record_target,
        output int unsigned enabled_steps
    );
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not start in FETCH");
        enabled_steps = 0;
        do begin
            step_cpu(record_target);
            enabled_steps++;
            assert (enabled_steps < 20)
                else $fatal(1, "instruction failed to complete");
        end while (debug_execution_state != CPU_STATE_FETCH);
    endtask

    task automatic select_directed_inputs(
        input cpu_instruction_t instruction,
        input int unsigned variant,
        output logic [7:0] lhs,
        output logic [7:0] operand,
        output logic carry_in
    );
        lhs = BOUNDARY_VALUES[(variant + 1) % VALUE_COUNT];
        operand = BOUNDARY_VALUES[variant];
        carry_in = variant[0];

        if (instruction == CPU_INSTR_ADC) begin
            case (variant)
                0: begin lhs = 8'h00; operand = 8'h00; carry_in = 1'b0; end
                1: begin lhs = 8'h00; operand = 8'h00; carry_in = 1'b1; end
                2: begin lhs = 8'h7F; operand = 8'h01; carry_in = 1'b0; end
                3: begin lhs = 8'h80; operand = 8'h80; carry_in = 1'b0; end
                4: begin lhs = 8'hFF; operand = 8'h01; carry_in = 1'b0; end
                default: begin lhs = 8'hFF; operand = 8'hFF; carry_in = 1'b1; end
            endcase
        end else if (instruction == CPU_INSTR_SBC) begin
            case (variant)
                0: begin lhs = 8'h00; operand = 8'h00; carry_in = 1'b1; end
                1: begin lhs = 8'h00; operand = 8'h00; carry_in = 1'b0; end
                2: begin lhs = 8'h00; operand = 8'h01; carry_in = 1'b1; end
                3: begin lhs = 8'h80; operand = 8'h01; carry_in = 1'b1; end
                4: begin lhs = 8'h7F; operand = 8'hFF; carry_in = 1'b1; end
                default: begin lhs = 8'hFF; operand = 8'hFF; carry_in = 1'b1; end
            endcase
        end else if (instruction_is_compare(instruction)) begin
            case (variant)
                0: begin lhs = 8'h00; operand = 8'h01; carry_in = 1'b0; end
                1: begin lhs = 8'h01; operand = 8'h01; carry_in = 1'b1; end
                2: begin lhs = 8'h02; operand = 8'h01; carry_in = 1'b0; end
                3: begin lhs = 8'h7F; operand = 8'h80; carry_in = 1'b1; end
                4: begin lhs = 8'h80; operand = 8'h7F; carry_in = 1'b0; end
                default: begin lhs = 8'hFF; operand = 8'hFF; carry_in = 1'b1; end
            endcase
        end
    endtask

    task automatic calculate_expected_alu(
        input cpu_instruction_t instruction,
        input cpu_alu_operation_t operation,
        input logic [7:0] lhs,
        input logic [7:0] operand,
        input logic carry_in
    );
        logic [8:0] wide;

        expected_alu_operation = operation;
        expected_alu_operand_a = lhs;
        expected_alu_operand_b = 8'h00;
        expected_alu_carry_in = 1'b0;
        expected_alu_result = 8'h00;
        expected_result_valid = !instruction_is_compare(instruction);
        expected_negative = 1'b0;
        expected_overflow = 1'b0;
        expected_zero = 1'b0;
        expected_carry = 1'b0;
        expected_n_valid = 1'b1;
        expected_v_valid = 1'b0;
        expected_z_valid = 1'b1;
        expected_c_valid = 1'b0;
        wide = 9'h000;

        case (operation)
            CPU_ALU_ADD: begin
                expected_alu_operand_b = operand;
                expected_alu_carry_in = carry_in;
                wide = {1'b0, lhs} + {1'b0, operand} +
                       {{8{1'b0}}, carry_in};
                expected_alu_result = wide[7:0];
                expected_overflow = ~(lhs[7] ^ operand[7]) &
                                    (lhs[7] ^ wide[7]);
                expected_carry = wide[8];
                expected_v_valid = 1'b1;
                expected_c_valid = 1'b1;
            end

            CPU_ALU_SUB: begin
                expected_alu_operand_b = operand;
                expected_alu_carry_in = carry_in;
                wide = {1'b0, lhs} + {1'b0, ~operand} +
                       {{8{1'b0}}, carry_in};
                expected_alu_result = wide[7:0];
                expected_overflow = (lhs[7] ^ operand[7]) &
                                    (lhs[7] ^ wide[7]);
                expected_carry = wide[8];
                expected_v_valid = 1'b1;
                expected_c_valid = 1'b1;
            end

            CPU_ALU_AND: begin
                expected_alu_operand_b = operand;
                expected_alu_result = lhs & operand;
            end
            CPU_ALU_OR: begin
                expected_alu_operand_b = operand;
                expected_alu_result = lhs | operand;
            end
            CPU_ALU_XOR: begin
                expected_alu_operand_b = operand;
                expected_alu_result = lhs ^ operand;
            end
            CPU_ALU_CMP: begin
                expected_alu_operand_b = operand;
                expected_alu_result = lhs - operand;
                expected_carry = lhs >= operand;
                expected_c_valid = 1'b1;
            end
            CPU_ALU_INC: expected_alu_result = lhs + 8'h01;
            CPU_ALU_DEC: expected_alu_result = lhs - 8'h01;
            CPU_ALU_ASL: begin
                expected_alu_result = {lhs[6:0], 1'b0};
                expected_carry = lhs[7];
                expected_c_valid = 1'b1;
            end
            CPU_ALU_LSR: begin
                expected_alu_result = {1'b0, lhs[7:1]};
                expected_carry = lhs[0];
                expected_c_valid = 1'b1;
            end
            CPU_ALU_ROL: begin
                expected_alu_carry_in = carry_in;
                expected_alu_result = {lhs[6:0], carry_in};
                expected_carry = lhs[7];
                expected_c_valid = 1'b1;
            end
            CPU_ALU_ROR: begin
                expected_alu_carry_in = carry_in;
                expected_alu_result = {carry_in, lhs[7:1]};
                expected_carry = lhs[0];
                expected_c_valid = 1'b1;
            end
            default: $fatal(1, "unexpected Phase 2E ALU operation");
        endcase

        expected_negative = expected_alu_result[7];
        expected_zero = expected_alu_result == 8'h00;
    endtask

    task automatic run_directed_vector(
        input int unsigned opcode_index,
        input int unsigned variant
    );
        logic [7:0] opcode;
        cpu_instruction_t instruction;
        logic [3:0] mode;
        cpu_alu_operation_t operation;
        logic [7:0] lhs;
        logic [7:0] operand;
        logic carry_in;
        logic [7:0] index_value;
        logic [7:0] zp_operand;
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
        logic [7:0] expected_status;
        logic [7:0] operation_lhs;
        logic is_rmw;
        logic expected_page_cross;
        logic expected_page_cross_valid;
        int unsigned enabled_steps;
        int unsigned setup_steps;
        int unsigned event_index;
        int unsigned prior_alu_observations;
        logic [15:0] tentative_address;
        logic final_read_seen;

        opcode = OPCODES[opcode_index];
        instruction = INSTRUCTIONS[opcode_index];
        mode = MODES[opcode_index];
        operation = OPERATIONS[opcode_index];
        select_directed_inputs(instruction, variant, lhs, operand, carry_in);
        index_value = BOUNDARY_VALUES[variant];
        zp_operand = BOUNDARY_VALUES[(variant + 2) % VALUE_COUNT];
        base_address = BOUNDARY_ADDRESSES[(opcode_index + variant) % 10];
        target_address = 16'h0000;
        pointer_base = 16'h0000;
        pointer_low_address = 16'h0000;
        pointer_high_address = 16'h0000;
        expected_page_cross = 1'b0;
        expected_page_cross_valid = 1'b0;
        is_rmw = instruction_is_memory_rmw(instruction, mode);
        tentative_address = 16'h0000;
        final_read_seen = 1'b0;

        reset = 1'b1;
        cpu_enable = 1'b0;
        cursor = PROGRAM_START;

        // Establish carry independently, then load source/index registers.
        // Loads preserve C/V/D/I, so TEST_RESET_STATUS also proves that the
        // stored D flag never changes binary 2A03 arithmetic.
        append_immediate(cursor, 8'hA2, 8'h00); // LDX #$00
        append_immediate(cursor, 8'hE0, carry_in ? 8'h00 : 8'h01);

        if (mode == CPU_ADDR_ZERO_PAGE_X ||
            mode == CPU_ADDR_ABSOLUTE_X ||
            mode == CPU_ADDR_INDEXED_INDIRECT_X) begin
            append_immediate(cursor, 8'hA2, index_value);
        end else if (mode == CPU_ADDR_ABSOLUTE_Y ||
                     mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
            append_immediate(cursor, 8'hA0, index_value);
        end

        case (instruction)
            CPU_INSTR_ADC,
            CPU_INSTR_SBC,
            CPU_INSTR_AND,
            CPU_INSTR_ORA,
            CPU_INSTR_EOR,
            CPU_INSTR_CMP: append_immediate(cursor, 8'hA9, lhs);

            CPU_INSTR_CPX,
            CPU_INSTR_INX,
            CPU_INSTR_DEX: append_immediate(cursor, 8'hA2, lhs);

            CPU_INSTR_CPY,
            CPU_INSTR_INY,
            CPU_INSTR_DEY: append_immediate(cursor, 8'hA0, lhs);

            CPU_INSTR_ASL,
            CPU_INSTR_LSR,
            CPU_INSTR_ROL,
            CPU_INSTR_ROR: begin
                if (mode == CPU_ADDR_ACCUMULATOR) begin
                    append_immediate(cursor, 8'hA9, operand);
                end
            end

            default: begin
                // Memory INC/DEC and memory shifts need no register source.
            end
        endcase

        target_pc = cursor;
        append_byte(cursor, opcode);
        case (mode)
            CPU_ADDR_IMPLIED,
            CPU_ADDR_ACCUMULATOR: begin
                // No operand byte or data address.
            end

            CPU_ADDR_IMMEDIATE: append_byte(cursor, operand);

            CPU_ADDR_ZERO_PAGE: begin
                target_address = {8'h00, zp_operand};
                append_byte(cursor, zp_operand);
            end

            CPU_ADDR_ZERO_PAGE_X: begin
                target_address = {8'h00, 8'(zp_operand + index_value)};
                append_byte(cursor, zp_operand);
            end

            CPU_ADDR_ABSOLUTE: begin
                target_address = base_address;
                append_byte(cursor, base_address[7:0]);
                append_byte(cursor, base_address[15:8]);
            end

            CPU_ADDR_ABSOLUTE_X: begin
                target_address = 16'(base_address + index_value);
                expected_page_cross =
                    ({1'b0, base_address[7:0]} +
                     {1'b0, index_value}) > 9'h0FF;
                expected_page_cross_valid = 1'b1;
                append_byte(cursor, base_address[7:0]);
                append_byte(cursor, base_address[15:8]);
            end

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
                target_address = BOUNDARY_ADDRESSES[variant + 4];
                pointer_low_address =
                    {8'h00, 8'(zp_operand + index_value)};
                pointer_high_address =
                    {8'h00, 8'({1'b0, zp_operand} +
                                {1'b0, index_value} + 9'd1)};
                memory_model.memory[pointer_low_address] =
                    target_address[7:0];
                memory_model.memory[pointer_high_address] =
                    target_address[15:8];
                append_byte(cursor, zp_operand);
            end

            CPU_ADDR_INDIRECT_INDEXED_Y: begin
                target_address = BOUNDARY_ADDRESSES[variant + 4];
                pointer_base = 16'(target_address - index_value);
                pointer_low_address = {8'h00, zp_operand};
                pointer_high_address = {8'h00, 8'(zp_operand + 1)};
                memory_model.memory[pointer_low_address] =
                    pointer_base[7:0];
                memory_model.memory[pointer_high_address] =
                    pointer_base[15:8];
                expected_page_cross =
                    ({1'b0, pointer_base[7:0]} +
                     {1'b0, index_value}) > 9'h0FF;
                expected_page_cross_valid = 1'b1;
                append_byte(cursor, zp_operand);
            end

            default: $fatal(1, "unexpected Phase 2E addressing mode");
        endcase

        if (mode != CPU_ADDR_IMPLIED &&
            mode != CPU_ADDR_ACCUMULATOR &&
            mode != CPU_ADDR_IMMEDIATE) begin
            memory_model.memory[target_address] = operand;
        end

        expected_pc = target_pc + 16'(1 + mode_operand_bytes(mode));
        reset_core();

        while (debug_pc != target_pc) begin
            execute_current_instruction(1'b0, setup_steps);
            assert (setup_steps > 0 && debug_pc <= target_pc)
                else $fatal(1, "setup failed to reach target instruction");
        end

        before_a = debug_a;
        before_x = debug_x;
        before_y = debug_y;
        before_sp = debug_sp;
        before_status = debug_status;
        assert (before_status[0] == carry_in &&
                before_status[6] && before_status[3] && before_status[2])
            else $fatal(1, "setup did not preserve V/D/I or select carry");

        if (instruction == CPU_INSTR_ADC ||
            instruction == CPU_INSTR_SBC ||
            instruction == CPU_INSTR_AND ||
            instruction == CPU_INSTR_ORA ||
            instruction == CPU_INSTR_EOR ||
            instruction == CPU_INSTR_CMP) begin
            operation_lhs = before_a;
        end else if (instruction == CPU_INSTR_CPX ||
                     instruction == CPU_INSTR_INX ||
                     instruction == CPU_INSTR_DEX) begin
            operation_lhs = before_x;
        end else if (instruction == CPU_INSTR_CPY ||
                     instruction == CPU_INSTR_INY ||
                     instruction == CPU_INSTR_DEY) begin
            operation_lhs = before_y;
        end else if (mode == CPU_ADDR_ACCUMULATOR) begin
            operation_lhs = before_a;
        end else begin
            operation_lhs = operand;
        end

        calculate_expected_alu(
            instruction, operation, operation_lhs, operand, before_status[0]
        );
        expected_status = status_with_alu_flags(before_status);
        trace_count = 0;
        prior_alu_observations = alu_observation_count;
        execute_current_instruction(1'b1, enabled_steps);

        assert (enabled_steps == expected_enabled_steps(
                    mode, is_rmw, expected_page_cross))
            else $fatal(1, "enabled-step mismatch opcode=%02h got=%0d",
                        opcode, enabled_steps);
        assert (alu_observation_count == prior_alu_observations + 1)
            else $fatal(1, "ALU execute count mismatch opcode=%02h", opcode);
        assert (debug_instruction == opcode &&
                debug_decoded_instruction == instruction &&
                debug_addressing_mode == mode &&
                debug_pc == expected_pc)
            else $fatal(1, "decode/PC mismatch opcode=%02h", opcode);
        assert (debug_status == expected_status && debug_sp == before_sp)
            else $fatal(1, "status/SP mismatch opcode=%02h", opcode);

        if (instruction == CPU_INSTR_ADC ||
            instruction == CPU_INSTR_SBC ||
            instruction == CPU_INSTR_AND ||
            instruction == CPU_INSTR_ORA ||
            instruction == CPU_INSTR_EOR) begin
            assert (debug_a == expected_alu_result &&
                    debug_x == before_x && debug_y == before_y &&
                    memory_write_count == 0)
                else $fatal(1, "accumulator ALU result mismatch opcode=%02h",
                            opcode);
        end else if (instruction_is_compare(instruction)) begin
            assert (debug_a == before_a && debug_x == before_x &&
                    debug_y == before_y && memory_write_count == 0)
                else $fatal(1, "compare modified source state opcode=%02h",
                            opcode);
        end else if (instruction == CPU_INSTR_INX ||
                     instruction == CPU_INSTR_DEX) begin
            assert (debug_x == expected_alu_result &&
                    debug_a == before_a && debug_y == before_y &&
                    memory_write_count == 0)
                else $fatal(1, "X inc/dec result mismatch opcode=%02h", opcode);
        end else if (instruction == CPU_INSTR_INY ||
                     instruction == CPU_INSTR_DEY) begin
            assert (debug_y == expected_alu_result &&
                    debug_a == before_a && debug_x == before_x &&
                    memory_write_count == 0)
                else $fatal(1, "Y inc/dec result mismatch opcode=%02h", opcode);
        end else if (mode == CPU_ADDR_ACCUMULATOR) begin
            assert (debug_a == expected_alu_result &&
                    debug_x == before_x && debug_y == before_y &&
                    memory_write_count == 0)
                else $fatal(1, "accumulator shift result mismatch opcode=%02h",
                            opcode);
        end else begin
            assert (debug_a == before_a && debug_x == before_x &&
                    debug_y == before_y && memory_write_count == 2 &&
                    last_write_address == target_address &&
                    last_write_data == expected_alu_result &&
                    memory_model.memory[target_address] == expected_alu_result)
                else $fatal(1, "memory RMW result mismatch opcode=%02h", opcode);
        end

        if (mode != CPU_ADDR_IMPLIED &&
            mode != CPU_ADDR_ACCUMULATOR &&
            mode != CPU_ADDR_IMMEDIATE) begin
            assert (debug_effective_address == target_address &&
                    debug_page_cross == expected_page_cross &&
                    debug_page_cross_valid == expected_page_cross_valid)
                else $fatal(1, "address metadata mismatch opcode=%02h", opcode);
        end

        event_index = 0;
        assert (!trace_write_enable[event_index] &&
                trace_address[event_index] == target_pc &&
                trace_read_data[event_index] == opcode)
            else $fatal(1, "opcode bus trace mismatch opcode=%02h", opcode);
        event_index++;
        if (mode_operand_bytes(mode) >= 1) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == target_pc + 16'd1)
                else $fatal(1, "operand-low trace mismatch opcode=%02h", opcode);
            event_index++;
        end
        if (mode_operand_bytes(mode) == 2) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == target_pc + 16'd2)
                else $fatal(1, "operand-high trace mismatch opcode=%02h", opcode);
            event_index++;
        end
        if (mode == CPU_ADDR_IMPLIED || mode == CPU_ADDR_ACCUMULATOR) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == target_pc + 16'd1)
                else $fatal(1, "implied/accumulator dummy mismatch opcode=%02h", opcode);
            event_index++;
        end
        if (mode == CPU_ADDR_ZERO_PAGE_X ||
            mode == CPU_ADDR_INDEXED_INDIRECT_X) begin
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == {8'h00, zp_operand})
                else $fatal(1, "zero-page index dummy mismatch opcode=%02h", opcode);
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
        if (mode == CPU_ADDR_ABSOLUTE_X ||
            mode == CPU_ADDR_ABSOLUTE_Y ||
            mode == CPU_ADDR_INDIRECT_INDEXED_Y) begin
            tentative_address = {
                (mode == CPU_ADDR_INDIRECT_INDEXED_Y)
                    ? pointer_base[15:8] : base_address[15:8],
                target_address[7:0]
            };
            assert (!trace_write_enable[event_index] &&
                    trace_address[event_index] == tentative_address)
                else $fatal(1, "indexed tentative read mismatch opcode=%02h", opcode);
            if (!is_rmw && !expected_page_cross) begin
                assert (trace_read_data[event_index] == operand)
                    else $fatal(1, "indexed final read data mismatch opcode=%02h", opcode);
                final_read_seen = 1'b1;
            end
            event_index++;
        end
        if (mode != CPU_ADDR_IMPLIED &&
            mode != CPU_ADDR_ACCUMULATOR &&
            mode != CPU_ADDR_IMMEDIATE) begin
            if (!final_read_seen) begin
                assert (!trace_write_enable[event_index] &&
                        trace_address[event_index] == target_address &&
                        trace_read_data[event_index] == operand)
                    else $fatal(1, "memory-read trace mismatch opcode=%02h", opcode);
                event_index++;
            end
        end
        if (is_rmw) begin
            assert (trace_write_enable[event_index] &&
                    trace_address[event_index] == target_address &&
                    trace_write_data[event_index] == operand)
                else $fatal(1, "RMW original-value write mismatch opcode=%02h", opcode);
            event_index++;
            assert (trace_write_enable[event_index] &&
                    trace_address[event_index] == target_address &&
                    trace_write_data[event_index] == expected_alu_result)
                else $fatal(1, "RMW final write mismatch opcode=%02h", opcode);
            event_index++;
        end
        assert (trace_count == event_index)
            else $fatal(1, "unexpected bus cycle count opcode=%02h", opcode);

        instruction_vector_count[instruction]++;
    endtask

    task automatic test_stall_in_state(
        input cpu_execution_state_t target_state
    );
        logic [7:0] held_a;
        logic [7:0] held_x;
        logic [7:0] held_y;
        logic [7:0] held_sp;
        logic [15:0] held_pc;
        logic [7:0] held_status;
        logic [15:0] held_bus_address;
        logic [7:0] held_bus_write_data;
        logic held_bus_write_enable;
        logic held_bus_valid;
        logic [31:0] held_write_count;
        int unsigned steps;

        reset = 1'b1;
        cpu_enable = 1'b0;
        case (target_state)
            CPU_STATE_FETCH,
            CPU_STATE_OPERAND_LOW: begin
                memory_model.memory[PROGRAM_START] = 8'h69; // ADC #$01
                memory_model.memory[PROGRAM_START + 1] = 8'h01;
            end

            CPU_STATE_ALU_EXECUTE: begin
                memory_model.memory[PROGRAM_START] = 8'h0A; // ASL A
            end

            CPU_STATE_MEMORY_READ: begin
                memory_model.memory[PROGRAM_START] = 8'h65; // ADC $80
                memory_model.memory[PROGRAM_START + 1] = 8'h80;
                memory_model.memory[16'h0080] = 8'h01;
            end

            CPU_STATE_RMW_DUMMY_WRITE,
            CPU_STATE_RMW_WRITE: begin
                memory_model.memory[PROGRAM_START] = 8'hE6; // INC $80
                memory_model.memory[PROGRAM_START + 1] = 8'h80;
                memory_model.memory[16'h0080] = 8'hFF;
            end

            default: $fatal(1, "unsupported stall target");
        endcase

        reset_core();
        steps = 0;
        while (debug_execution_state != target_state) begin
            step_cpu(1'b0);
            steps++;
            assert (steps < 12)
                else $fatal(1, "failed to reach stall state %0d", target_state);
        end

        held_a = debug_a;
        held_x = debug_x;
        held_y = debug_y;
        held_sp = debug_sp;
        held_pc = debug_pc;
        held_status = debug_status;
        held_bus_address = bus_address;
        held_bus_write_data = bus_write_data;
        held_bus_write_enable = bus_write_enable;
        held_bus_valid = bus_valid;
        held_write_count = memory_write_count;
        cpu_enable = 1'b0;

        repeat (4) begin
            step_cpu(1'b0);
            assert (debug_execution_state == target_state &&
                    debug_a == held_a && debug_x == held_x &&
                    debug_y == held_y && debug_sp == held_sp &&
                    debug_pc == held_pc && debug_status == held_status)
                else $fatal(1, "architectural state changed during stall %0d",
                            target_state);
            assert (bus_address == held_bus_address &&
                    bus_write_data == held_bus_write_data &&
                    bus_write_enable == held_bus_write_enable &&
                    bus_valid == held_bus_valid &&
                    memory_write_count == held_write_count)
                else $fatal(1, "bus/write changed during stall %0d",
                            target_state);
        end

        if (target_state == CPU_STATE_RMW_WRITE) begin
            assert (held_bus_valid && held_bus_write_enable &&
                    held_bus_address == 16'h0080 &&
                    held_bus_write_data == 8'h00 && held_write_count == 1)
                else $fatal(1, "RMW write was not presented during stall");
            cpu_enable = 1'b1;
            step_cpu(1'b0);
            assert (memory_write_count == 2 &&
                    memory_model.memory[16'h0080] == 8'h00 &&
                    debug_execution_state == CPU_STATE_FETCH)
                else $fatal(1, "stalled RMW did not commit exactly once");
        end
    endtask

    task automatic test_unsupported_opcode;
        reset = 1'b1;
        cpu_enable = 1'b0;
        memory_model.memory[PROGRAM_START] = 8'hEB; // unofficial SBC
        reset_core();
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_TRAP &&
                debug_decoded_instruction == CPU_INSTR_INVALID &&
                debug_pc == PROGRAM_START + 16'd1 &&
                !bus_valid && !bus_write_enable && memory_write_count == 0)
            else $fatal(1, "unsupported opcode did not trap safely");
    endtask

    initial begin
        int unsigned total_vectors;

        $dumpfile("build/sim/cpu_phase2e.fst");
        $dumpvars(0, cpu_phase2e_tb);
        #1;

        for (int unsigned instruction = 0; instruction < 31; instruction++) begin
            instruction_vector_count[instruction] = 0;
        end

        for (int unsigned opcode_index = 0;
             opcode_index < OPCODE_COUNT; opcode_index++) begin
            for (int unsigned variant = 0;
                 variant < VALUE_COUNT; variant++) begin
                run_directed_vector(opcode_index, variant);
            end
        end

        assert (instruction_vector_count[CPU_INSTR_ADC] == 48);
        assert (instruction_vector_count[CPU_INSTR_SBC] == 48);
        assert (instruction_vector_count[CPU_INSTR_AND] == 48);
        assert (instruction_vector_count[CPU_INSTR_ORA] == 48);
        assert (instruction_vector_count[CPU_INSTR_EOR] == 48);
        assert (instruction_vector_count[CPU_INSTR_CMP] == 48);
        assert (instruction_vector_count[CPU_INSTR_CPX] == 18);
        assert (instruction_vector_count[CPU_INSTR_CPY] == 18);
        assert (instruction_vector_count[CPU_INSTR_INX] == 6);
        assert (instruction_vector_count[CPU_INSTR_INY] == 6);
        assert (instruction_vector_count[CPU_INSTR_DEX] == 6);
        assert (instruction_vector_count[CPU_INSTR_DEY] == 6);
        assert (instruction_vector_count[CPU_INSTR_INC] == 24);
        assert (instruction_vector_count[CPU_INSTR_DEC] == 24);
        assert (instruction_vector_count[CPU_INSTR_ASL] == 30);
        assert (instruction_vector_count[CPU_INSTR_LSR] == 30);
        assert (instruction_vector_count[CPU_INSTR_ROL] == 30);
        assert (instruction_vector_count[CPU_INSTR_ROR] == 30);

        total_vectors = 0;
        for (int unsigned instruction = int'(CPU_INSTR_ADC);
             instruction <= int'(CPU_INSTR_ROR); instruction++) begin
            total_vectors += instruction_vector_count[instruction];
        end
        assert (total_vectors == DIRECTED_VECTOR_COUNT &&
                alu_observation_count == DIRECTED_VECTOR_COUNT)
            else $fatal(1, "unexpected Phase 2E vector/ALU count");

        test_stall_in_state(CPU_STATE_FETCH);
        test_stall_in_state(CPU_STATE_OPERAND_LOW);
        test_stall_in_state(CPU_STATE_MEMORY_READ);
        test_stall_in_state(CPU_STATE_ALU_EXECUTE);
        test_stall_in_state(CPU_STATE_RMW_DUMMY_WRITE);
        test_stall_in_state(CPU_STATE_RMW_WRITE);
        test_unsupported_opcode();

        $display("PASS: Phase 2E arithmetic/logic verification (%0d directed opcode vectors)",
                 total_vectors);
        $finish;
    end
endmodule
