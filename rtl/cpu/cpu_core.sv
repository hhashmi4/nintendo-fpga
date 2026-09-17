`timescale 1ns/1ps

module cpu_core #(
    // Verification may override the initial status to exercise preservation.
    // Production uses the deterministic Ricoh 2A03 reset value.
    parameter logic [7:0] INITIAL_STATUS = cpu_pkg::CPU_RESET_STATUS
) (
    input  logic clk,
    input  logic reset,
    input  logic cpu_enable,
    input  logic nmi,
    input  logic irq,

    output logic [15:0] bus_address,
    output logic [7:0]  bus_write_data,
    input  logic [7:0]  bus_read_data,
    output logic        bus_write_enable,
    output logic        bus_valid,

    // Read-only architectural visibility for verification and bring-up.
    output logic [7:0]  debug_a,
    output logic [7:0]  debug_x,
    output logic [7:0]  debug_y,
    output logic [7:0]  debug_sp,
    output logic [15:0] debug_pc,
    output cpu_pkg::cpu_status_t debug_status,
    output logic [7:0]  debug_instruction,
    output cpu_pkg::cpu_execution_state_t debug_execution_state,
    output cpu_pkg::cpu_instruction_t debug_decoded_instruction,
    output logic [3:0]  debug_addressing_mode,
    output logic [15:0] debug_effective_address,
    output logic        debug_page_cross,
    output logic        debug_page_cross_valid
);
    import cpu_pkg::*;

    cpu_decode_result_t   decoded;
    cpu_address_request_t address_request;
    // Mode-specific result fields that are not relevant to the execution
    // path in use remain intentionally unconsumed.
    /* verilator lint_off UNUSEDSIGNAL */
    cpu_address_result_t address_response;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [1:0] operand_bytes;
    logic       instruction_is_load;
    logic       instruction_is_store;
    logic       instruction_uses_alu;
    logic       instruction_is_compare;
    logic       instruction_is_rmw;
    logic [7:0] operand_low;
    logic [7:0] operand_high;
    logic [7:0] pointer_low;
    logic [7:0] pointer_high;
    logic       pointer_data_valid;
    logic [7:0] data_latch;
    logic [15:0] return_address;
    logic [7:0]  rts_low_byte;
    logic        branch_taken;
    cpu_interrupt_source_t interrupt_source;
    logic [15:0] interrupt_vector_low_address;

    // External interrupt inputs are synchronized to CLOCK_50. NMI is then
    // edge-latched so a held request cannot repeatedly retrigger; IRQ remains
    // a level request and is qualified by I at instruction boundaries.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic nmi_meta, nmi_sync;
    logic nmi_sync_delayed;
    logic nmi_pending;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic irq_meta, irq_sync;
    logic accept_nmi;
    logic accept_irq;
    logic interrupt_boundary_request;

    cpu_alu_operation_t alu_operation;
    logic [7:0] alu_operand_a;
    logic [7:0] alu_operand_b;
    logic       alu_carry_in;
    logic [7:0] alu_result;
    logic       alu_result_valid;
    logic       alu_negative;
    logic       alu_overflow;
    logic       alu_zero;
    logic       alu_carry;
    logic       alu_n_valid;
    logic       alu_v_valid;
    logic       alu_z_valid;
    logic       alu_c_valid;

    cpu_decoder decoder (
        .opcode  (debug_instruction),
        .decoded (decoded)
    );

    cpu_address_gen address_generator (
        .request  (address_request),
        .response (address_response)
    );

    cpu_alu alu (
        .operation    (alu_operation),
        .operand_a    (alu_operand_a),
        .operand_b    (alu_operand_b),
        .carry_in     (alu_carry_in),
        .result       (alu_result),
        .result_valid (alu_result_valid),
        .negative     (alu_negative),
        .overflow     (alu_overflow),
        .zero         (alu_zero),
        .carry        (alu_carry),
        .n_valid      (alu_n_valid),
        .v_valid      (alu_v_valid),
        .z_valid      (alu_z_valid),
        .c_valid      (alu_c_valid)
    );

    always_comb begin
        address_request                    = '0;
        address_request.addressing_mode    = debug_addressing_mode;
        if (debug_addressing_mode == CPU_ADDR_RELATIVE) begin
            // The caller explicitly supplies the PC after the displacement
            // byte has been consumed, matching the Phase 2C contract.
            address_request.base_address = debug_pc;
        end else begin
            address_request.base_address = {operand_high, operand_low};
        end
        address_request.operand_byte       = operand_low;
        address_request.x_index            = debug_x;
        address_request.y_index            = debug_y;
        address_request.pointer_low_byte   = pointer_low;
        address_request.pointer_high_byte  = pointer_high;
        address_request.pointer_data_valid = pointer_data_valid;
    end

    always_comb begin
        accept_nmi = debug_execution_state == CPU_STATE_FETCH && nmi_pending;
        accept_irq = debug_execution_state == CPU_STATE_FETCH &&
                     !nmi_pending && irq_sync &&
                     !debug_status.interrupt_disable;
        interrupt_boundary_request = accept_nmi || accept_irq;

        case (interrupt_source)
            CPU_INTERRUPT_NMI:
                interrupt_vector_low_address = CPU_VECTOR_NMI_LOW;
            CPU_INTERRUPT_IRQ,
            CPU_INTERRUPT_BRK:
                interrupt_vector_low_address = CPU_VECTOR_IRQ_LOW;
            CPU_INTERRUPT_RESET:
                interrupt_vector_low_address = CPU_VECTOR_RESET_LOW;
            default:
                interrupt_vector_low_address = 16'h0000;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            nmi_meta         <= 1'b0;
            nmi_sync         <= 1'b0;
            nmi_sync_delayed <= 1'b0;
            nmi_pending      <= 1'b0;
            irq_meta         <= 1'b0;
            irq_sync         <= 1'b0;
        end else begin
            nmi_meta         <= nmi;
            nmi_sync         <= nmi_meta;
            nmi_sync_delayed <= nmi_sync;
            irq_meta         <= irq;
            irq_sync         <= irq_meta;

            if (cpu_enable && accept_nmi) begin
                nmi_pending <= 1'b0;
            end
            if (nmi_sync && !nmi_sync_delayed) begin
                nmi_pending <= 1'b1;
            end
        end
    end

    always_comb begin
        branch_taken = 1'b0;
        case (debug_decoded_instruction)
            CPU_INSTR_BCC: branch_taken = !debug_status.carry;
            CPU_INSTR_BCS: branch_taken = debug_status.carry;
            CPU_INSTR_BEQ: branch_taken = debug_status.zero;
            CPU_INSTR_BMI: branch_taken = debug_status.negative;
            CPU_INSTR_BNE: branch_taken = !debug_status.zero;
            CPU_INSTR_BPL: branch_taken = !debug_status.negative;
            CPU_INSTR_BVC: branch_taken = !debug_status.overflow;
            CPU_INSTR_BVS: branch_taken = debug_status.overflow;
            default: begin
                // Non-branch instructions never redirect in BRANCH_DECIDE.
            end
        endcase
    end

    // Operand routing is instruction-class based. The ALU remains the only
    // implementation of arithmetic, logic, compare, increment/decrement,
    // shift, rotate, and their N/V/Z/C semantics.
    always_comb begin
        alu_operand_a = data_latch;
        alu_operand_b = 8'h00;
        alu_carry_in  = 1'b0;

        case (debug_decoded_instruction)
            CPU_INSTR_ADC,
            CPU_INSTR_SBC,
            CPU_INSTR_AND,
            CPU_INSTR_ORA,
            CPU_INSTR_EOR,
            CPU_INSTR_CMP: begin
                alu_operand_a = debug_a;
                alu_operand_b = data_latch;
            end

            CPU_INSTR_CPX: begin
                alu_operand_a = debug_x;
                alu_operand_b = data_latch;
            end

            CPU_INSTR_CPY: begin
                alu_operand_a = debug_y;
                alu_operand_b = data_latch;
            end

            CPU_INSTR_INX,
            CPU_INSTR_DEX: alu_operand_a = debug_x;

            CPU_INSTR_INY,
            CPU_INSTR_DEY: alu_operand_a = debug_y;

            CPU_INSTR_ASL,
            CPU_INSTR_LSR,
            CPU_INSTR_ROL,
            CPU_INSTR_ROR: begin
                if (debug_addressing_mode == CPU_ADDR_ACCUMULATOR) begin
                    alu_operand_a = debug_a;
                end
            end

            default: begin
                // Memory INC/DEC and memory shifts use data_latch.
            end
        endcase

        if (debug_decoded_instruction == CPU_INSTR_ADC ||
            debug_decoded_instruction == CPU_INSTR_SBC ||
            debug_decoded_instruction == CPU_INSTR_ROL ||
            debug_decoded_instruction == CPU_INSTR_ROR) begin
            alu_carry_in = debug_status.carry;
        end
    end

    // The synchronized platform reset has priority over cpu_enable. Outside
    // reset, architectural/sequencer state changes only on a CPU enable
    // pulse; the input synchronizers above intentionally run every fabric
    // clock so interrupt edges are retained between pulses.
    always_ff @(posedge clk) begin
        if (reset) begin
            debug_a                   <= CPU_RESET_A;
            debug_x                   <= CPU_RESET_X;
            debug_y                   <= CPU_RESET_Y;
            debug_sp                  <= CPU_RESET_SP;
            debug_pc                  <= CPU_RESET_PC;
            debug_status              <= cpu_status_normalize(INITIAL_STATUS);
            debug_instruction         <= CPU_RESET_IR;
            debug_execution_state     <= CPU_STATE_RESET;
            debug_decoded_instruction <= CPU_INSTR_INVALID;
            debug_addressing_mode     <= CPU_ADDR_IMPLIED;
            debug_effective_address   <= 16'h0000;
            debug_page_cross          <= 1'b0;
            debug_page_cross_valid    <= 1'b0;
            operand_bytes             <= 2'd0;
            instruction_is_load       <= 1'b0;
            instruction_is_store      <= 1'b0;
            instruction_uses_alu      <= 1'b0;
            instruction_is_compare    <= 1'b0;
            instruction_is_rmw        <= 1'b0;
            alu_operation             <= CPU_ALU_ADD;
            operand_low               <= 8'h00;
            operand_high              <= 8'h00;
            pointer_low               <= 8'h00;
            pointer_high              <= 8'h00;
            pointer_data_valid        <= 1'b0;
            data_latch                <= 8'h00;
            return_address            <= 16'h0000;
            rts_low_byte              <= 8'h00;
            interrupt_source          <= CPU_INTERRUPT_RESET;
        end else if (cpu_enable) begin
            case (debug_execution_state)
                CPU_STATE_RESET: begin
                    // Reset is bus-visible: no direct PC initialization is
                    // permitted. This boundary enters the low-vector read.
                    debug_execution_state <= CPU_STATE_RESET_VECTOR_LOW;
                end

                CPU_STATE_FETCH: begin
                    if (accept_nmi || accept_irq) begin
                        return_address <= debug_pc;
                        if (accept_nmi) begin
                            interrupt_source <= CPU_INTERRUPT_NMI;
                        end else begin
                            interrupt_source <= CPU_INTERRUPT_IRQ;
                        end
                        debug_decoded_instruction <= CPU_INSTR_INVALID;
                        debug_execution_state <=
                            CPU_STATE_INTERRUPT_PUSH_HIGH;
                    end else begin
                        debug_instruction      <= bus_read_data;
                        debug_pc               <= debug_pc + 16'd1;
                        debug_execution_state  <= CPU_STATE_DECODE;
                        debug_page_cross       <= 1'b0;
                        debug_page_cross_valid <= 1'b0;
                        operand_low            <= 8'h00;
                        operand_high           <= 8'h00;
                        pointer_low            <= 8'h00;
                        pointer_high           <= 8'h00;
                        pointer_data_valid     <= 1'b0;
                        data_latch             <= 8'h00;
                        return_address         <= 16'h0000;
                        rts_low_byte           <= 8'h00;
                        instruction_is_load    <= 1'b0;
                        instruction_is_store   <= 1'b0;
                        instruction_uses_alu   <= 1'b0;
                        instruction_is_compare <= 1'b0;
                        instruction_is_rmw     <= 1'b0;
                    end
                end

                CPU_STATE_DECODE: begin
                    debug_decoded_instruction <= decoded.instruction;
                    debug_addressing_mode     <= decoded.addressing_mode;
                    operand_bytes             <= decoded.operand_bytes;
                    instruction_is_load       <= decoded.is_load;
                    instruction_is_store      <= decoded.is_store;
                    instruction_uses_alu      <= decoded.uses_alu;
                    instruction_is_compare    <= decoded.is_compare;
                    instruction_is_rmw        <= decoded.is_rmw;
                    alu_operation             <= decoded.alu_operation;

                    if (!decoded.valid) begin
                        debug_execution_state <= CPU_STATE_TRAP;
                    end else if (decoded.is_interrupt) begin
                        case (decoded.instruction)
                            CPU_INSTR_BRK:
                                debug_execution_state <= CPU_STATE_BRK_PADDING;
                            CPU_INSTR_RTI:
                                debug_execution_state <= CPU_STATE_RTI_PULL;
                            default:
                                debug_execution_state <= CPU_STATE_TRAP;
                        endcase
                    end else if (decoded.is_transfer) begin
                        debug_execution_state <= CPU_STATE_TRANSFER;
                    end else if (decoded.is_stack) begin
                        case (decoded.instruction)
                            CPU_INSTR_PHA,
                            CPU_INSTR_PHP:
                                debug_execution_state <= CPU_STATE_STACK_PUSH;

                            CPU_INSTR_PLA,
                            CPU_INSTR_PLP:
                                debug_execution_state <= CPU_STATE_STACK_PULL;

                            default:
                                debug_execution_state <= CPU_STATE_TRAP;
                        endcase
                    end else if (decoded.is_jump || decoded.is_branch) begin
                        if (decoded.instruction == CPU_INSTR_RTS) begin
                            debug_execution_state <= CPU_STATE_RTS_PULL;
                        end else begin
                            debug_execution_state <= CPU_STATE_OPERAND_LOW;
                        end
                    end else if (decoded.uses_alu &&
                                 (decoded.addressing_mode == CPU_ADDR_IMPLIED ||
                                  decoded.addressing_mode ==
                                  CPU_ADDR_ACCUMULATOR)) begin
                        debug_execution_state <= CPU_STATE_ALU_EXECUTE;
                    end else begin
                        debug_execution_state <= CPU_STATE_OPERAND_LOW;
                    end
                end

                CPU_STATE_OPERAND_LOW: begin
                    operand_low <= bus_read_data;
                    debug_pc    <= debug_pc + 16'd1;
                    if (operand_bytes == 2'd2) begin
                        debug_execution_state <= CPU_STATE_OPERAND_HIGH;
                    end else begin
                        debug_execution_state <= CPU_STATE_ADDRESS;
                    end
                end

                CPU_STATE_OPERAND_HIGH: begin
                    operand_high          <= bus_read_data;
                    debug_pc              <= debug_pc + 16'd1;
                    debug_execution_state <= CPU_STATE_ADDRESS;
                end

                CPU_STATE_ADDRESS: begin
                    if (debug_addressing_mode == CPU_ADDR_IMMEDIATE) begin
                        if (address_response.immediate_valid) begin
                            data_latch <= address_response.immediate_value;
                            if (instruction_is_load) begin
                                debug_execution_state <= CPU_STATE_WRITEBACK;
                            end else if (instruction_uses_alu) begin
                                debug_execution_state <= CPU_STATE_ALU_EXECUTE;
                            end else begin
                                debug_execution_state <= CPU_STATE_TRAP;
                            end
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else if (debug_addressing_mode == CPU_ADDR_RELATIVE) begin
                        if (address_response.branch_target_valid &&
                            address_response.page_cross_valid) begin
                            debug_effective_address <=
                                address_response.branch_target;
                            debug_page_cross <= address_response.page_cross;
                            debug_page_cross_valid <= 1'b1;
                            debug_execution_state <= CPU_STATE_BRANCH_DECIDE;
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else if (
                        debug_addressing_mode == CPU_ADDR_INDIRECT ||
                        debug_addressing_mode == CPU_ADDR_INDEXED_INDIRECT_X ||
                        debug_addressing_mode == CPU_ADDR_INDIRECT_INDEXED_Y
                    ) begin
                        if (!pointer_data_valid) begin
                            debug_execution_state <= CPU_STATE_POINTER_LOW;
                        end else if (address_response.effective_address_valid) begin
                            debug_effective_address <=
                                address_response.effective_address;
                            debug_page_cross <= address_response.page_cross;
                            debug_page_cross_valid <=
                                address_response.page_cross_valid;
                            if (debug_decoded_instruction == CPU_INSTR_JMP) begin
                                debug_pc <= address_response.effective_address;
                                debug_execution_state <= CPU_STATE_FETCH;
                            end else if (instruction_is_load ||
                                         instruction_uses_alu) begin
                                debug_execution_state <= CPU_STATE_MEMORY_READ;
                            end else if (instruction_is_store) begin
                                debug_execution_state <= CPU_STATE_MEMORY_WRITE;
                            end else begin
                                debug_execution_state <= CPU_STATE_TRAP;
                            end
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else if (address_response.effective_address_valid) begin
                        debug_effective_address <=
                            address_response.effective_address;
                        debug_page_cross <= address_response.page_cross;
                        debug_page_cross_valid <=
                            address_response.page_cross_valid;
                        if (debug_decoded_instruction == CPU_INSTR_JMP) begin
                            debug_pc <= address_response.effective_address;
                            debug_execution_state <= CPU_STATE_FETCH;
                        end else if (debug_decoded_instruction == CPU_INSTR_JSR) begin
                            // After both target bytes have been consumed, PC
                            // points one beyond JSR. NMOS 6502 JSR stacks the
                            // address of the high operand byte (PC - 1).
                            return_address <= debug_pc - 16'd1;
                            debug_execution_state <= CPU_STATE_JSR_PUSH_HIGH;
                        end else if (instruction_is_load ||
                                     instruction_uses_alu) begin
                            debug_execution_state <= CPU_STATE_MEMORY_READ;
                        end else if (instruction_is_store) begin
                            debug_execution_state <= CPU_STATE_MEMORY_WRITE;
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else begin
                        debug_execution_state <= CPU_STATE_TRAP;
                    end
                end

                CPU_STATE_POINTER_LOW: begin
                    pointer_low            <= bus_read_data;
                    debug_execution_state <= CPU_STATE_POINTER_HIGH;
                end

                CPU_STATE_POINTER_HIGH: begin
                    pointer_high           <= bus_read_data;
                    pointer_data_valid     <= 1'b1;
                    debug_execution_state <= CPU_STATE_ADDRESS;
                end

                CPU_STATE_MEMORY_READ: begin
                    data_latch             <= bus_read_data;
                    if (instruction_is_load) begin
                        debug_execution_state <= CPU_STATE_WRITEBACK;
                    end else if (instruction_uses_alu) begin
                        debug_execution_state <= CPU_STATE_ALU_EXECUTE;
                    end else begin
                        debug_execution_state <= CPU_STATE_TRAP;
                    end
                end

                CPU_STATE_MEMORY_WRITE: begin
                    // The external bus consumes the sole write on this edge.
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_WRITEBACK: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_LDA: debug_a <= data_latch;
                        CPU_INSTR_LDX: debug_x <= data_latch;
                        CPU_INSTR_LDY: debug_y <= data_latch;
                        default: begin
                            // Decode prevents non-load writeback states.
                        end
                    endcase
                    debug_status.negative <= data_latch[7];
                    debug_status.zero     <= (data_latch == 8'h00);
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_TRANSFER: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_TAX: begin
                            debug_x               <= debug_a;
                            debug_status.negative <= debug_a[7];
                            debug_status.zero     <= (debug_a == 8'h00);
                        end

                        CPU_INSTR_TAY: begin
                            debug_y               <= debug_a;
                            debug_status.negative <= debug_a[7];
                            debug_status.zero     <= (debug_a == 8'h00);
                        end

                        CPU_INSTR_TXA: begin
                            debug_a               <= debug_x;
                            debug_status.negative <= debug_x[7];
                            debug_status.zero     <= (debug_x == 8'h00);
                        end

                        CPU_INSTR_TYA: begin
                            debug_a               <= debug_y;
                            debug_status.negative <= debug_y[7];
                            debug_status.zero     <= (debug_y == 8'h00);
                        end

                        CPU_INSTR_TSX: begin
                            debug_x               <= debug_sp;
                            debug_status.negative <= debug_sp[7];
                            debug_status.zero     <= (debug_sp == 8'h00);
                        end

                        CPU_INSTR_TXS: begin
                            debug_sp <= debug_x;
                        end

                        default: begin
                            // Decode prevents invalid transfer states.
                        end
                    endcase
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_ALU_EXECUTE: begin
                    // Apply only the flags explicitly owned by this ALU
                    // operation. In particular CMP has no result writeback
                    // and logic/shift operations preserve V as advertised.
                    if (alu_n_valid) begin
                        debug_status.negative <= alu_negative;
                    end
                    if (alu_v_valid) begin
                        debug_status.overflow <= alu_overflow;
                    end
                    if (alu_z_valid) begin
                        debug_status.zero <= alu_zero;
                    end
                    if (alu_c_valid) begin
                        debug_status.carry <= alu_carry;
                    end

                    if (instruction_is_compare) begin
                        if (alu_n_valid && alu_z_valid && alu_c_valid &&
                            !alu_v_valid) begin
                            debug_execution_state <= CPU_STATE_FETCH;
                        end else begin
                            debug_execution_state <= CPU_STATE_TRAP;
                        end
                    end else if (!alu_result_valid) begin
                        debug_execution_state <= CPU_STATE_TRAP;
                    end else begin
                        case (debug_decoded_instruction)
                            CPU_INSTR_ADC,
                            CPU_INSTR_SBC,
                            CPU_INSTR_AND,
                            CPU_INSTR_ORA,
                            CPU_INSTR_EOR: begin
                                debug_a <= alu_result;
                                debug_execution_state <= CPU_STATE_FETCH;
                            end

                            CPU_INSTR_INX,
                            CPU_INSTR_DEX: begin
                                debug_x <= alu_result;
                                debug_execution_state <= CPU_STATE_FETCH;
                            end

                            CPU_INSTR_INY,
                            CPU_INSTR_DEY: begin
                                debug_y <= alu_result;
                                debug_execution_state <= CPU_STATE_FETCH;
                            end

                            CPU_INSTR_INC,
                            CPU_INSTR_DEC: begin
                                if (instruction_is_rmw) begin
                                    data_latch <= alu_result;
                                    debug_execution_state <= CPU_STATE_RMW_WRITE;
                                end else begin
                                    debug_execution_state <= CPU_STATE_TRAP;
                                end
                            end

                            CPU_INSTR_ASL,
                            CPU_INSTR_LSR,
                            CPU_INSTR_ROL,
                            CPU_INSTR_ROR: begin
                                if (debug_addressing_mode ==
                                    CPU_ADDR_ACCUMULATOR) begin
                                    debug_a <= alu_result;
                                    debug_execution_state <= CPU_STATE_FETCH;
                                end else if (instruction_is_rmw) begin
                                    data_latch <= alu_result;
                                    debug_execution_state <= CPU_STATE_RMW_WRITE;
                                end else begin
                                    debug_execution_state <= CPU_STATE_TRAP;
                                end
                            end

                            default: begin
                                debug_execution_state <= CPU_STATE_TRAP;
                            end
                        endcase
                    end
                end

                CPU_STATE_RMW_WRITE: begin
                    // The transformed value is committed exactly once by the
                    // external bus consumer on this enabled edge.
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_BRANCH_DECIDE: begin
                    if (branch_taken) begin
                        debug_pc <= debug_effective_address;
                    end
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_STACK_PUSH: begin
                    // PHA/PHP write at the current S, then decrement it.
                    debug_sp <= debug_sp - 8'd1;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_STACK_PULL: begin
                    // PLA/PLP pre-increment S before presenting the read.
                    debug_sp <= debug_sp + 8'd1;
                    debug_execution_state <= CPU_STATE_STACK_READ;
                end

                CPU_STATE_STACK_READ: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_PLA: begin
                            debug_a               <= bus_read_data;
                            debug_status.negative <= bus_read_data[7];
                            debug_status.zero     <= (bus_read_data == 8'h00);
                            debug_execution_state <= CPU_STATE_FETCH;
                        end

                        CPU_INSTR_PLP: begin
                            // B is discarded and U is forced high; the six
                            // physical status fields come from the stack.
                            debug_status <= cpu_status_normalize(bus_read_data);
                            debug_execution_state <= CPU_STATE_FETCH;
                        end

                        default: debug_execution_state <= CPU_STATE_TRAP;
                    endcase
                end

                CPU_STATE_JSR_PUSH_HIGH: begin
                    // The stack receives return high first, then S decrements.
                    debug_sp <= debug_sp - 8'd1;
                    debug_execution_state <= CPU_STATE_JSR_PUSH_LOW;
                end

                CPU_STATE_JSR_PUSH_LOW: begin
                    debug_sp <= debug_sp - 8'd1;
                    debug_pc <= debug_effective_address;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_RTS_PULL: begin
                    // First pull pre-increments S, exactly like PLA/PLP.
                    debug_sp <= debug_sp + 8'd1;
                    debug_execution_state <= CPU_STATE_RTS_PULL_LOW;
                end

                CPU_STATE_RTS_PULL_LOW: begin
                    rts_low_byte <= bus_read_data;
                    // Prepare S for the following high-byte pull.
                    debug_sp <= debug_sp + 8'd1;
                    debug_execution_state <= CPU_STATE_RTS_PULL_HIGH;
                end

                CPU_STATE_RTS_PULL_HIGH: begin
                    operand_high <= bus_read_data;
                    debug_execution_state <= CPU_STATE_RTS_COMPLETE;
                end

                CPU_STATE_RTS_COMPLETE: begin
                    // JSR stored the address of its last operand; RTS adds one
                    // after rebuilding the 16-bit return address.
                    debug_pc <= {operand_high, rts_low_byte} + 16'd1;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_RESET_VECTOR_LOW: begin
                    operand_low <= bus_read_data;
                    debug_execution_state <= CPU_STATE_RESET_VECTOR_HIGH;
                end

                CPU_STATE_RESET_VECTOR_HIGH: begin
                    debug_pc <= {bus_read_data, operand_low};
                    interrupt_source <= CPU_INTERRUPT_NONE;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_BRK_PADDING: begin
                    // BRK consumes a padding/signature byte. The stacked PC
                    // therefore points two bytes beyond the BRK opcode.
                    debug_pc <= debug_pc + 16'd1;
                    return_address <= debug_pc + 16'd1;
                    interrupt_source <= CPU_INTERRUPT_BRK;
                    debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_HIGH;
                end

                CPU_STATE_INTERRUPT_PUSH_HIGH: begin
                    debug_sp <= debug_sp - 8'd1;
                    debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_LOW;
                end

                CPU_STATE_INTERRUPT_PUSH_LOW: begin
                    debug_sp <= debug_sp - 8'd1;
                    debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_STATUS;
                end

                CPU_STATE_INTERRUPT_PUSH_STATUS: begin
                    debug_sp <= debug_sp - 8'd1;
                    debug_status.interrupt_disable <= 1'b1;
                    debug_execution_state <= CPU_STATE_INTERRUPT_VECTOR_LOW;
                end

                CPU_STATE_INTERRUPT_VECTOR_LOW: begin
                    operand_low <= bus_read_data;
                    debug_execution_state <= CPU_STATE_INTERRUPT_VECTOR_HIGH;
                end

                CPU_STATE_INTERRUPT_VECTOR_HIGH: begin
                    debug_pc <= {bus_read_data, operand_low};
                    interrupt_source <= CPU_INTERRUPT_NONE;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_RTI_PULL: begin
                    // RTI, like every pull operation, increments S before the
                    // first stack read.
                    debug_sp <= debug_sp + 8'd1;
                    debug_execution_state <= CPU_STATE_RTI_PULL_STATUS;
                end

                CPU_STATE_RTI_PULL_STATUS: begin
                    debug_status <= cpu_status_normalize(bus_read_data);
                    debug_sp <= debug_sp + 8'd1;
                    debug_execution_state <= CPU_STATE_RTI_PULL_LOW;
                end

                CPU_STATE_RTI_PULL_LOW: begin
                    rts_low_byte <= bus_read_data;
                    debug_sp <= debug_sp + 8'd1;
                    debug_execution_state <= CPU_STATE_RTI_PULL_HIGH;
                end

                CPU_STATE_RTI_PULL_HIGH: begin
                    operand_high <= bus_read_data;
                    debug_execution_state <= CPU_STATE_RTI_COMPLETE;
                end

                CPU_STATE_RTI_COMPLETE: begin
                    // Unlike RTS, RTI resumes at the stacked address exactly.
                    debug_pc <= {operand_high, rts_low_byte};
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_TRAP: begin
                    // Unsupported opcode: safely halt until reset.
                    debug_execution_state <= CPU_STATE_TRAP;
                end

                default: begin
                    // Corrupt state cannot cause a write; fail closed.
                    debug_execution_state <= CPU_STATE_TRAP;
                end
            endcase
        end
    end

    // A bus cycle remains active between CPU enable pulses. The consumer must
    // commit a write once, on the enabled edge that completes MEMORY_WRITE or
    // RMW_WRITE.
    always_comb begin
        bus_address      = debug_pc;
        bus_write_data   = 8'h00;
        bus_write_enable = 1'b0;
        bus_valid        = 1'b0;

        if (reset) begin
            bus_address = CPU_RESET_PC;
        end else begin
            case (debug_execution_state)
                CPU_STATE_FETCH: begin
                    bus_address = debug_pc;
                    // Recognition occurs before opcode consumption. Suppress
                    // the speculative fetch when an interrupt wins priority.
                    bus_valid = !interrupt_boundary_request;
                end

                CPU_STATE_OPERAND_LOW,
                CPU_STATE_OPERAND_HIGH: begin
                    bus_address = debug_pc;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_POINTER_LOW: begin
                    bus_address = address_response.pointer_low_address;
                    bus_valid   = address_response.pointer_addresses_valid;
                end

                CPU_STATE_POINTER_HIGH: begin
                    bus_address = address_response.pointer_high_address;
                    bus_valid   = address_response.pointer_addresses_valid;
                end

                CPU_STATE_MEMORY_READ: begin
                    bus_address = debug_effective_address;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_MEMORY_WRITE: begin
                    bus_address      = debug_effective_address;
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                    case (debug_decoded_instruction)
                        CPU_INSTR_STA: bus_write_data = debug_a;
                        CPU_INSTR_STX: bus_write_data = debug_x;
                        CPU_INSTR_STY: bus_write_data = debug_y;
                        default: begin
                            bus_write_data   = 8'h00;
                            bus_write_enable = 1'b0;
                            bus_valid        = 1'b0;
                        end
                    endcase
                end

                CPU_STATE_RMW_WRITE: begin
                    bus_address      = debug_effective_address;
                    bus_write_data   = data_latch;
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                end

                CPU_STATE_STACK_PUSH: begin
                    bus_address      = {8'h01, debug_sp};
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                    case (debug_decoded_instruction)
                        CPU_INSTR_PHA: bus_write_data = debug_a;
                        CPU_INSTR_PHP:
                            bus_write_data = cpu_status_for_php(debug_status);
                        default: begin
                            bus_write_data   = 8'h00;
                            bus_write_enable = 1'b0;
                            bus_valid        = 1'b0;
                        end
                    endcase
                end

                CPU_STATE_STACK_READ,
                CPU_STATE_RTS_PULL_LOW,
                CPU_STATE_RTS_PULL_HIGH: begin
                    bus_address = {8'h01, debug_sp};
                    bus_valid   = 1'b1;
                end

                CPU_STATE_JSR_PUSH_HIGH: begin
                    bus_address      = {8'h01, debug_sp};
                    bus_write_data   = return_address[15:8];
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                end

                CPU_STATE_JSR_PUSH_LOW: begin
                    bus_address      = {8'h01, debug_sp};
                    bus_write_data   = return_address[7:0];
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                end

                CPU_STATE_RESET_VECTOR_LOW: begin
                    bus_address = CPU_VECTOR_RESET_LOW;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_RESET_VECTOR_HIGH: begin
                    bus_address = CPU_VECTOR_RESET_LOW + 16'd1;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_BRK_PADDING: begin
                    bus_address = debug_pc;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_INTERRUPT_PUSH_HIGH: begin
                    bus_address      = {8'h01, debug_sp};
                    bus_write_data   = return_address[15:8];
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                end

                CPU_STATE_INTERRUPT_PUSH_LOW: begin
                    bus_address      = {8'h01, debug_sp};
                    bus_write_data   = return_address[7:0];
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                end

                CPU_STATE_INTERRUPT_PUSH_STATUS: begin
                    bus_address = {8'h01, debug_sp};
                    if (interrupt_source == CPU_INTERRUPT_BRK) begin
                        bus_write_data = cpu_status_for_php(debug_status);
                    end else begin
                        bus_write_data =
                            cpu_status_for_interrupt(debug_status);
                    end
                    bus_write_enable = 1'b1;
                    bus_valid        = 1'b1;
                end

                CPU_STATE_INTERRUPT_VECTOR_LOW: begin
                    bus_address = interrupt_vector_low_address;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_INTERRUPT_VECTOR_HIGH: begin
                    bus_address = interrupt_vector_low_address + 16'd1;
                    bus_valid   = 1'b1;
                end

                CPU_STATE_RTI_PULL_STATUS,
                CPU_STATE_RTI_PULL_LOW,
                CPU_STATE_RTI_PULL_HIGH: begin
                    bus_address = {8'h01, debug_sp};
                    bus_valid   = 1'b1;
                end

                default: begin
                    // Internal-only states and TRAP have no bus cycle.
                end
            endcase
        end
    end
endmodule
