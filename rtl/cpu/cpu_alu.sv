`timescale 1ns/1ps

module cpu_alu (
    // Keep the physical port four-state-complete so synthesis preserves the
    // deterministic default behavior for unused operation encodings. Callers
    // should drive values from cpu_alu_operation_t.
    input  logic [3:0] operation,
    input  logic [7:0] operand_a,
    input  logic [7:0] operand_b,
    input  logic       carry_in,

    output logic [7:0] result,
    output logic       result_valid,
    output logic       negative,
    output logic       overflow,
    output logic       zero,
    output logic       carry,
    output logic       n_valid,
    output logic       v_valid,
    output logic       z_valid,
    output logic       c_valid
);
    import cpu_pkg::*;

    logic [8:0] arithmetic_result;

    always_comb begin
        result            = 8'h00;
        result_valid      = 1'b0;
        negative          = 1'b0;
        overflow          = 1'b0;
        zero              = 1'b0;
        carry             = 1'b0;
        n_valid           = 1'b0;
        v_valid           = 1'b0;
        z_valid           = 1'b0;
        c_valid           = 1'b0;
        arithmetic_result = 9'h000;

        case (operation)
            CPU_ALU_ADD: begin
                arithmetic_result =
                    {1'b0, operand_a} + {1'b0, operand_b} +
                    {{8{1'b0}}, carry_in};
                result       = arithmetic_result[7:0];
                result_valid = 1'b1;
                overflow     = ~(operand_a[7] ^ operand_b[7]) &
                               (operand_a[7] ^ result[7]);
                carry        = arithmetic_result[8];
                n_valid      = 1'b1;
                v_valid      = 1'b1;
                z_valid      = 1'b1;
                c_valid      = 1'b1;
            end

            CPU_ALU_SUB: begin
                // 6502 SBC is A + ~B + C. Carry set means no borrow.
                arithmetic_result =
                    {1'b0, operand_a} + {1'b0, ~operand_b} +
                    {{8{1'b0}}, carry_in};
                result       = arithmetic_result[7:0];
                result_valid = 1'b1;
                overflow     = (operand_a[7] ^ operand_b[7]) &
                               (operand_a[7] ^ result[7]);
                carry        = arithmetic_result[8];
                n_valid      = 1'b1;
                v_valid      = 1'b1;
                z_valid      = 1'b1;
                c_valid      = 1'b1;
            end

            CPU_ALU_AND: begin
                result       = operand_a & operand_b;
                result_valid = 1'b1;
                n_valid      = 1'b1;
                z_valid      = 1'b1;
            end

            CPU_ALU_OR: begin
                result       = operand_a | operand_b;
                result_valid = 1'b1;
                n_valid      = 1'b1;
                z_valid      = 1'b1;
            end

            CPU_ALU_XOR: begin
                result       = operand_a ^ operand_b;
                result_valid = 1'b1;
                n_valid      = 1'b1;
                z_valid      = 1'b1;
            end

            CPU_ALU_ASL: begin
                result       = {operand_a[6:0], 1'b0};
                result_valid = 1'b1;
                carry        = operand_a[7];
                n_valid      = 1'b1;
                z_valid      = 1'b1;
                c_valid      = 1'b1;
            end

            CPU_ALU_LSR: begin
                result       = {1'b0, operand_a[7:1]};
                result_valid = 1'b1;
                carry        = operand_a[0];
                n_valid      = 1'b1;
                z_valid      = 1'b1;
                c_valid      = 1'b1;
            end

            CPU_ALU_ROL: begin
                result       = {operand_a[6:0], carry_in};
                result_valid = 1'b1;
                carry        = operand_a[7];
                n_valid      = 1'b1;
                z_valid      = 1'b1;
                c_valid      = 1'b1;
            end

            CPU_ALU_ROR: begin
                result       = {carry_in, operand_a[7:1]};
                result_valid = 1'b1;
                carry        = operand_a[0];
                n_valid      = 1'b1;
                z_valid      = 1'b1;
                c_valid      = 1'b1;
            end

            CPU_ALU_INC: begin
                result       = operand_a + 8'h01;
                result_valid = 1'b1;
                n_valid      = 1'b1;
                z_valid      = 1'b1;
            end

            CPU_ALU_DEC: begin
                result       = operand_a - 8'h01;
                result_valid = 1'b1;
                n_valid      = 1'b1;
                z_valid      = 1'b1;
            end

            CPU_ALU_CMP: begin
                arithmetic_result =
                    {1'b0, operand_a} + {1'b0, ~operand_b} + 9'h001;
                result  = arithmetic_result[7:0];
                carry   = arithmetic_result[8];
                n_valid = 1'b1;
                z_valid = 1'b1;
                c_valid = 1'b1;
            end

            default: begin
                // Unassigned operation encodings remain deterministic and
                // explicitly advertise that no output may be consumed.
            end
        endcase

        if (n_valid) begin
            negative = result[7];
        end
        if (z_valid) begin
            zero = (result == 8'h00);
        end
    end
endmodule
