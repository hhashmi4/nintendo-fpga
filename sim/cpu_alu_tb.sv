`timescale 1ns/1ps

module cpu_alu_tb;
    import cpu_pkg::*;

    cpu_alu_operation_t operation = CPU_ALU_ADD;
    logic [7:0] operand_a = 8'h00;
    logic [7:0] operand_b = 8'h00;
    logic carry_in = 1'b0;
    logic [7:0] result;
    logic result_valid;
    logic negative;
    logic overflow;
    logic zero;
    logic carry;
    logic n_valid;
    logic v_valid;
    logic z_valid;
    logic c_valid;
    int unsigned vector_count = 0;

    cpu_alu dut (
        .operation    (operation),
        .operand_a    (operand_a),
        .operand_b    (operand_b),
        .carry_in     (carry_in),
        .result       (result),
        .result_valid (result_valid),
        .negative     (negative),
        .overflow     (overflow),
        .zero         (zero),
        .carry        (carry),
        .n_valid      (n_valid),
        .v_valid      (v_valid),
        .z_valid      (z_valid),
        .c_valid      (c_valid)
    );

    task automatic apply_and_check(
        input cpu_alu_operation_t requested_operation,
        input logic [7:0] requested_a,
        input logic [7:0] requested_b,
        input logic requested_carry,
        input logic [7:0] expected_result,
        input logic expected_result_valid,
        input logic [3:0] expected_flags,
        input logic [3:0] expected_valids
    );
        operation = requested_operation;
        operand_a = requested_a;
        operand_b = requested_b;
        carry_in = requested_carry;
        #1;

        assert (!$isunknown({result, result_valid, negative, overflow, zero,
                             carry, n_valid, v_valid, z_valid, c_valid}))
            else $fatal(1, "unknown ALU output for op=%0d a=%02h b=%02h c=%0b",
                        requested_operation, requested_a, requested_b,
                        requested_carry);
        assert (result == expected_result)
            else $fatal(1, "result mismatch op=%0d a=%02h b=%02h c=%0b",
                        requested_operation, requested_a, requested_b,
                        requested_carry);
        assert (result_valid == expected_result_valid)
            else $fatal(1, "result validity mismatch for op=%0d",
                        requested_operation);
        assert ({negative, overflow, zero, carry} == expected_flags)
            else $fatal(1, "flag mismatch op=%0d a=%02h b=%02h c=%0b",
                        requested_operation, requested_a, requested_b,
                        requested_carry);
        assert ({n_valid, v_valid, z_valid, c_valid} == expected_valids)
            else $fatal(1, "flag validity mismatch for op=%0d",
                        requested_operation);
        vector_count++;
    endtask

    task automatic check_invalid_operation(input logic [3:0] encoding);
        operation = cpu_alu_operation_t'(encoding);
        operand_a = 8'hA5;
        operand_b = 8'h5A;
        carry_in = 1'b1;
        #1;

        assert (!$isunknown({result, result_valid, negative, overflow, zero,
                             carry, n_valid, v_valid, z_valid, c_valid}))
            else $fatal(1, "unknown output for invalid operation %0d", encoding);
        assert ({result, result_valid, negative, overflow, zero, carry,
                 n_valid, v_valid, z_valid, c_valid} == '0)
            else $fatal(1, "invalid operation %0d was not inert", encoding);
        vector_count++;
    endtask

    initial begin
        int unsigned total;
        int signed difference;
        int signed signed_result;
        logic [7:0] expected_result;
        logic expected_carry;
        logic expected_overflow;

        $dumpfile("build/sim/cpu_alu.fst");
        $dumpvars(0, cpu_alu_tb);

        for (int unsigned a = 0; a < 256; a++) begin
            for (int unsigned b = 0; b < 256; b++) begin
                for (int unsigned carry_value = 0;
                     carry_value < 2; carry_value++) begin
                    total = a + b + carry_value;
                    expected_result = 8'(total);
                    expected_carry = (total > 255);
                    signed_result = ((a < 128) ? int'(a) : int'(a) - 256) +
                                    ((b < 128) ? int'(b) : int'(b) - 256) +
                                    int'(carry_value);
                    expected_overflow =
                        (signed_result < -128) || (signed_result > 127);
                    apply_and_check(
                        CPU_ALU_ADD, 8'(a), 8'(b), 1'(carry_value),
                        expected_result, 1'b1,
                        {expected_result[7], expected_overflow,
                         (expected_result == 8'h00), expected_carry},
                        4'b1111
                    );
                end
            end
        end

        for (int unsigned a = 0; a < 256; a++) begin
            for (int unsigned b = 0; b < 256; b++) begin
                for (int unsigned carry_value = 0;
                     carry_value < 2; carry_value++) begin
                    difference = int'(a) - int'(b) -
                                 (1 - int'(carry_value));
                    expected_result = 8'(difference);
                    expected_carry = (difference >= 0);
                    signed_result = ((a < 128) ? int'(a) : int'(a) - 256) -
                                    ((b < 128) ? int'(b) : int'(b) - 256) -
                                    (1 - int'(carry_value));
                    expected_overflow =
                        (signed_result < -128) || (signed_result > 127);
                    apply_and_check(
                        CPU_ALU_SUB, 8'(a), 8'(b), 1'(carry_value),
                        expected_result, 1'b1,
                        {expected_result[7], expected_overflow,
                         (expected_result == 8'h00), expected_carry},
                        4'b1111
                    );
                end
            end
        end

        for (int unsigned a = 0; a < 256; a++) begin
            for (int unsigned b = 0; b < 256; b++) begin
                expected_result = 8'(a) & 8'(b);
                apply_and_check(
                    CPU_ALU_AND, 8'(a), 8'(b), 1'b0,
                    expected_result, 1'b1,
                    {expected_result[7], 1'b0,
                     (expected_result == 8'h00), 1'b0},
                    4'b1010
                );

                expected_result = 8'(a) | 8'(b);
                apply_and_check(
                    CPU_ALU_OR, 8'(a), 8'(b), 1'b0,
                    expected_result, 1'b1,
                    {expected_result[7], 1'b0,
                     (expected_result == 8'h00), 1'b0},
                    4'b1010
                );

                expected_result = 8'(a) ^ 8'(b);
                apply_and_check(
                    CPU_ALU_XOR, 8'(a), 8'(b), 1'b0,
                    expected_result, 1'b1,
                    {expected_result[7], 1'b0,
                     (expected_result == 8'h00), 1'b0},
                    4'b1010
                );
            end
        end

        for (int unsigned a = 0; a < 256; a++) begin
            expected_result = {a[6:0], 1'b0};
            apply_and_check(
                CPU_ALU_ASL, 8'(a), 8'h00, 1'b0,
                expected_result, 1'b1,
                {expected_result[7], 1'b0,
                 (expected_result == 8'h00), a[7]},
                4'b1011
            );

            expected_result = {1'b0, a[7:1]};
            apply_and_check(
                CPU_ALU_LSR, 8'(a), 8'h00, 1'b0,
                expected_result, 1'b1,
                {expected_result[7], 1'b0,
                 (expected_result == 8'h00), a[0]},
                4'b1011
            );

            expected_result = 8'(a + 1);
            apply_and_check(
                CPU_ALU_INC, 8'(a), 8'h00, 1'b0,
                expected_result, 1'b1,
                {expected_result[7], 1'b0,
                 (expected_result == 8'h00), 1'b0},
                4'b1010
            );

            expected_result = 8'(a - 1);
            apply_and_check(
                CPU_ALU_DEC, 8'(a), 8'h00, 1'b0,
                expected_result, 1'b1,
                {expected_result[7], 1'b0,
                 (expected_result == 8'h00), 1'b0},
                4'b1010
            );

            for (int unsigned carry_value = 0;
                 carry_value < 2; carry_value++) begin
                expected_result = {a[6:0], carry_value[0]};
                apply_and_check(
                    CPU_ALU_ROL, 8'(a), 8'h00, 1'(carry_value),
                    expected_result, 1'b1,
                    {expected_result[7], 1'b0,
                     (expected_result == 8'h00), a[7]},
                    4'b1011
                );

                expected_result = {carry_value[0], a[7:1]};
                apply_and_check(
                    CPU_ALU_ROR, 8'(a), 8'h00, 1'(carry_value),
                    expected_result, 1'b1,
                    {expected_result[7], 1'b0,
                     (expected_result == 8'h00), a[0]},
                    4'b1011
                );
            end
        end

        for (int unsigned a = 0; a < 256; a++) begin
            for (int unsigned b = 0; b < 256; b++) begin
                difference = int'(a) - int'(b);
                expected_result = 8'(difference);
                for (int unsigned carry_value = 0;
                     carry_value < 2; carry_value++) begin
                    apply_and_check(
                        CPU_ALU_CMP, 8'(a), 8'(b), 1'(carry_value),
                        expected_result, 1'b0,
                        {expected_result[7], 1'b0,
                         (a == b), (a >= b)},
                        4'b1011
                    );
                end
            end
        end

        for (int unsigned encoding = 12; encoding < 16; encoding++) begin
            check_invalid_operation(4'(encoding));
        end

        assert (vector_count == 591_876)
            else $fatal(1, "unexpected ALU vector count: %0d", vector_count);

        $display("PASS: Phase 2B ALU exhaustive verification (%0d vectors)",
                 vector_count);
        $finish;
    end
endmodule
