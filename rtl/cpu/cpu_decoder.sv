`timescale 1ns/1ps

module cpu_decoder (
    input  logic [7:0]                  opcode,
    output cpu_pkg::cpu_decode_result_t decoded
);
    import cpu_pkg::*;

    always_comb begin
        decoded = '0;

        // Only official Phase 2D/2E opcodes are recognized. Every other byte
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

            // ADC
            8'h69: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'h65: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'h75: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'h6D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'h7D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'h79: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'h61: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'h71: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ADC; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // SBC
            8'hE9: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'hE5: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'hF5: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'hED: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'hFD: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'hF9: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'hE1: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'hF1: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_SBC; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // AND
            8'h29: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'h25: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'h35: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'h2D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'h3D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'h39: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'h21: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'h31: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_AND; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // ORA
            8'h09: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'h05: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'h15: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'h0D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'h1D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'h19: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'h01: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'h11: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ORA; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // EOR
            8'h49: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'h45: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'h55: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'h4D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'h5D: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'h59: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'h41: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'h51: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_EOR; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end

            // CMP, CPX, CPY
            8'hC9: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'hC5: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'hD5: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X;       end
            8'hCD: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'hDD: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;        end
            8'hD9: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_Y;        end
            8'hC1: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X; end
            8'hD1: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CMP; decoded.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y; end
            8'hE0: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CPX; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'hE4: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CPX; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'hEC: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CPX; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end
            8'hC0: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CPY; decoded.addressing_mode = CPU_ADDR_IMMEDIATE;          end
            8'hC4: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CPY; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;         end
            8'hCC: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_CPY; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;          end

            // Register increment/decrement
            8'hE8: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_INX; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'hC8: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_INY; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'hCA: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_DEX; decoded.addressing_mode = CPU_ADDR_IMPLIED; end
            8'h88: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_DEY; decoded.addressing_mode = CPU_ADDR_IMPLIED; end

            // Memory increment/decrement
            8'hE6: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_INC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'hF6: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_INC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'hEE: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_INC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'hFE: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_INC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end
            8'hC6: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_DEC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'hD6: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_DEC; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'hCE: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_DEC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'hDE: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_DEC; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end

            // Shifts and rotates
            8'h0A: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ASL; decoded.addressing_mode = CPU_ADDR_ACCUMULATOR; end
            8'h06: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ASL; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'h16: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ASL; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'h0E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ASL; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'h1E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ASL; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end
            8'h4A: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LSR; decoded.addressing_mode = CPU_ADDR_ACCUMULATOR; end
            8'h46: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LSR; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'h56: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LSR; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'h4E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LSR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'h5E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_LSR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end
            8'h2A: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROL; decoded.addressing_mode = CPU_ADDR_ACCUMULATOR; end
            8'h26: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROL; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'h36: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROL; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'h2E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROL; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'h3E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROL; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end
            8'h6A: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROR; decoded.addressing_mode = CPU_ADDR_ACCUMULATOR; end
            8'h66: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROR; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE;   end
            8'h76: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROR; decoded.addressing_mode = CPU_ADDR_ZERO_PAGE_X; end
            8'h6E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE;    end
            8'h7E: begin decoded.valid = 1'b1; decoded.instruction = CPU_INSTR_ROR; decoded.addressing_mode = CPU_ADDR_ABSOLUTE_X;  end

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

                CPU_INSTR_ADC: begin
                    decoded.uses_alu     = 1'b1;
                    decoded.alu_operation = CPU_ALU_ADD;
                end

                CPU_INSTR_SBC: begin
                    decoded.uses_alu     = 1'b1;
                    decoded.alu_operation = CPU_ALU_SUB;
                end

                CPU_INSTR_AND: begin
                    decoded.uses_alu     = 1'b1;
                    decoded.alu_operation = CPU_ALU_AND;
                end

                CPU_INSTR_ORA: begin
                    decoded.uses_alu     = 1'b1;
                    decoded.alu_operation = CPU_ALU_OR;
                end

                CPU_INSTR_EOR: begin
                    decoded.uses_alu     = 1'b1;
                    decoded.alu_operation = CPU_ALU_XOR;
                end

                CPU_INSTR_CMP,
                CPU_INSTR_CPX,
                CPU_INSTR_CPY: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.is_compare    = 1'b1;
                    decoded.alu_operation = CPU_ALU_CMP;
                end

                CPU_INSTR_INX,
                CPU_INSTR_INY,
                CPU_INSTR_INC: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.alu_operation = CPU_ALU_INC;
                end

                CPU_INSTR_DEX,
                CPU_INSTR_DEY,
                CPU_INSTR_DEC: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.alu_operation = CPU_ALU_DEC;
                end

                CPU_INSTR_ASL: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.alu_operation = CPU_ALU_ASL;
                end

                CPU_INSTR_LSR: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.alu_operation = CPU_ALU_LSR;
                end

                CPU_INSTR_ROL: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.alu_operation = CPU_ALU_ROL;
                end

                CPU_INSTR_ROR: begin
                    decoded.uses_alu      = 1'b1;
                    decoded.alu_operation = CPU_ALU_ROR;
                end

                default: begin
                    // The explicit opcode case prevents this path.
                end
            endcase

            case (decoded.addressing_mode)
                CPU_ADDR_IMPLIED,
                CPU_ADDR_ACCUMULATOR: decoded.operand_bytes = 2'd0;

                CPU_ADDR_ABSOLUTE,
                CPU_ADDR_ABSOLUTE_X,
                CPU_ADDR_ABSOLUTE_Y: decoded.operand_bytes = 2'd2;

                default: decoded.operand_bytes = 2'd1;
            endcase

            if (decoded.instruction == CPU_INSTR_INC ||
                decoded.instruction == CPU_INSTR_DEC ||
                ((decoded.instruction == CPU_INSTR_ASL ||
                  decoded.instruction == CPU_INSTR_LSR ||
                  decoded.instruction == CPU_INSTR_ROL ||
                  decoded.instruction == CPU_INSTR_ROR) &&
                 decoded.addressing_mode != CPU_ADDR_ACCUMULATOR)) begin
                decoded.is_rmw = 1'b1;
            end
        end
    end
endmodule
