`timescale 1ns/1ps

module cpu_decoder (
    input  logic [7:0]                  opcode,
    output cpu_pkg::cpu_decode_result_t decoded
);
    import cpu_pkg::*;

    always_comb begin
        decoded = '0;

        // Only official Phase 2D opcodes are recognized. Every other byte
        // retains the invalid, inert default.
        case (opcode)
            // LDA
            8'hA9: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'hA5: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'hB5: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'hAD: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'hBD: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'hB9: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'hA1: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'hB1: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDA; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // LDX
            8'hA2: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDX; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;    end
            8'hA6: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDX; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'hB6: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDX; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_Y; end
            8'hAE: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDX; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'hBE: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDX; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;  end

            // LDY
            8'hA0: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDY; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;    end
            8'hA4: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDY; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'hB4: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDY; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'hAC: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDY; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'hBC: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LDY; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end

            // STA
            8'h85: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;          end
            8'h95: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;        end
            8'h8D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;           end
            8'h9D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;         end
            8'h99: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;         end
            8'h81: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'h91: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STA; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // STX
            8'h86: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STX; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'h96: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STX; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_Y; end
            8'h8E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STX; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end

            // STY
            8'h84: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STY; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'h94: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STY; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'h8C: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_STY; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end

            // Implied transfers
            8'hAA: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_TAX; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'hA8: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_TAY; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'h8A: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_TXA; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'h98: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_TYA; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'hBA: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_TSX; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'h9A: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_TXS; decoded.addressing_mode = CPU_ADDR_IMPLIED; end

            default: begin
                // Unsupported instructions are intentionally invalid.
            end
        endcase

        if (decoded.valid) begin
            case (decoded.instruction)
                CPU_INSTR_LDA,
                CPU_INSTR_LDX,
                CPU_INSTR_LDY: decoded.is_load = 1'b1;

                CPU_INSTR_STA,
                CPU_INSTR_STX,
                CPU_INSTR_STY: decoded.is_store = 1'b1;

                CPU_INSTR_TAX,
                CPU_INSTR_TAY,
                CPU_INSTR_TXA,
                CPU_INSTR_TYA,
                CPU_INSTR_TSX,
                CPU_INSTR_TXS: decoded.is_transfer = 1'b1;

                default: begin
                    // The explicit opcode case prevents this path.
                end
            endcase

            case (decoded.addressing_mode)
                CPU_ADDR_IMPLIED: decoded.operand_bytes = 2'd0;

                CPU_ADDR_ABSOLUTE,
                CPU_ADDR_ABSOLUTE_X,
                CPU_ADDR_ABSOLUTE_Y: decoded.operand_bytes = 2'd2;

                default: decoded.operand_bytes = 2'd1;
            endcase
        end
    end
endmodule
