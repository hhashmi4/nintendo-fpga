`timescale 1ns/1ps

module cpu_core #(
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

    /* verilator lint_off UNUSEDSIGNAL */
    cpu_decode_result_t decoded;
    /* verilator lint_on UNUSEDSIGNAL */
    cpu_address_request_t address_request;
    /* verilator lint_off UNUSEDSIGNAL */
    cpu_address_result_t address_response;
    cpu_address_request_t branch_fetch_request;
    cpu_address_result_t branch_fetch_response;
    /* verilator lint_on UNUSEDSIGNAL */

    logic instruction_is_load;
    logic instruction_is_store;
    logic instruction_uses_alu;
    logic instruction_is_compare;
    logic instruction_is_rmw;
    logic [7:0] operand_low;
    logic [7:0] operand_high;
    logic [7:0] pointer_low;
    logic [7:0] pointer_high;
    logic       pointer_data_valid;
    logic [7:0] data_latch;
    logic [7:0] rmw_result;
    logic [15:0] return_address;
    logic [7:0]  rts_low_byte;
    logic        branch_taken;
    cpu_interrupt_source_t interrupt_source;
    logic [15:0] interrupt_vector_low_address;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic nmi_meta, nmi_sync;
    logic nmi_sync_delayed;
    logic nmi_pending;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic irq_meta, irq_sync;
    logic accept_nmi;
    logic accept_irq;
    // PLP, CLI, and SEI change I after their instruction-boundary interrupt
    // poll on NMOS-family CPUs. Preserve the pre-instruction I value for
    // exactly the following FETCH boundary. RTI restores I early enough to
    // use the restored value and therefore never sets this override.
    logic irq_poll_override_valid;
    logic irq_poll_interrupt_disable;

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

    // Decode the fetched memory byte in the opcode cycle itself. This avoids
    // the artificial, bus-idle decode cycle used by the Phase 2A scaffold.
    cpu_decoder decoder (.opcode(bus_read_data), .decoded(decoded));
    cpu_address_gen address_generator (
        .request(address_request), .response(address_response)
    );
    cpu_address_gen branch_fetch_generator (
        .request(branch_fetch_request), .response(branch_fetch_response)
    );
    cpu_alu alu (
        .operation(alu_operation), .operand_a(alu_operand_a),
        .operand_b(alu_operand_b), .carry_in(alu_carry_in),
        .result(alu_result), .result_valid(alu_result_valid),
        .negative(alu_negative), .overflow(alu_overflow),
        .zero(alu_zero), .carry(alu_carry),
        .n_valid(alu_n_valid), .v_valid(alu_v_valid),
        .z_valid(alu_z_valid), .c_valid(alu_c_valid)
    );

    always_comb begin
        address_request                    = '0;
        address_request.addressing_mode    = debug_addressing_mode;
        address_request.base_address       = {operand_high, operand_low};
        if (debug_addressing_mode == CPU_ADDR_RELATIVE) begin
            address_request.base_address = debug_pc;
        end
        address_request.operand_byte       = operand_low;
        address_request.x_index            = debug_x;
        address_request.y_index            = debug_y;
        address_request.pointer_low_byte   = pointer_low;
        address_request.pointer_high_byte  = pointer_high;
        address_request.pointer_data_valid = pointer_data_valid;

        branch_fetch_request = '0;
        branch_fetch_request.addressing_mode = CPU_ADDR_RELATIVE;
        branch_fetch_request.base_address = debug_pc + 16'd1;
        branch_fetch_request.operand_byte = bus_read_data;
    end

    always_comb begin
        accept_nmi = debug_execution_state == CPU_STATE_FETCH && nmi_pending;
        accept_irq = debug_execution_state == CPU_STATE_FETCH &&
                     !nmi_pending && irq_sync &&
                     !(irq_poll_override_valid ?
                       irq_poll_interrupt_disable :
                       debug_status.interrupt_disable);
        case (interrupt_source)
            CPU_INTERRUPT_NMI: interrupt_vector_low_address = CPU_VECTOR_NMI_LOW;
            CPU_INTERRUPT_IRQ,
            CPU_INTERRUPT_BRK: interrupt_vector_low_address = CPU_VECTOR_IRQ_LOW;
            CPU_INTERRUPT_RESET: interrupt_vector_low_address = CPU_VECTOR_RESET_LOW;
            default: interrupt_vector_low_address = 16'h0000;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            nmi_meta <= 1'b0;
            nmi_sync <= 1'b0;
            nmi_sync_delayed <= 1'b0;
            nmi_pending <= 1'b0;
            irq_meta <= 1'b0;
            irq_sync <= 1'b0;
        end else begin
            nmi_meta <= nmi;
            nmi_sync <= nmi_meta;
            nmi_sync_delayed <= nmi_sync;
            irq_meta <= irq;
            irq_sync <= irq_meta;
            if (cpu_enable && accept_nmi) nmi_pending <= 1'b0;
            if (nmi_sync && !nmi_sync_delayed) nmi_pending <= 1'b1;
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
            default: begin end
        endcase
    end

    // Bus-fed operations consume bus_read_data directly. Implied and
    // accumulator forms select their architectural source instead.
    always_comb begin
        alu_operand_a = bus_read_data;
        alu_operand_b = 8'h00;
        alu_carry_in  = 1'b0;
        case (debug_decoded_instruction)
            CPU_INSTR_ADC, CPU_INSTR_SBC, CPU_INSTR_AND,
            CPU_INSTR_ORA, CPU_INSTR_EOR, CPU_INSTR_CMP: begin
                alu_operand_a = debug_a;
                alu_operand_b = bus_read_data;
            end
            CPU_INSTR_CPX: begin alu_operand_a = debug_x; alu_operand_b = bus_read_data; end
            CPU_INSTR_CPY: begin alu_operand_a = debug_y; alu_operand_b = bus_read_data; end
            CPU_INSTR_INX, CPU_INSTR_DEX: alu_operand_a = debug_x;
            CPU_INSTR_INY, CPU_INSTR_DEY: alu_operand_a = debug_y;
            CPU_INSTR_ASL, CPU_INSTR_LSR, CPU_INSTR_ROL, CPU_INSTR_ROR:
                if (debug_addressing_mode == CPU_ADDR_ACCUMULATOR)
                    alu_operand_a = debug_a;
            default: begin end
        endcase
        if (debug_decoded_instruction == CPU_INSTR_ADC ||
            debug_decoded_instruction == CPU_INSTR_SBC ||
            debug_decoded_instruction == CPU_INSTR_ROL ||
            debug_decoded_instruction == CPU_INSTR_ROR)
            alu_carry_in = debug_status.carry;
    end

    task automatic apply_alu_flags;
        begin
            if (alu_n_valid) debug_status.negative <= alu_negative;
            if (alu_v_valid) debug_status.overflow <= alu_overflow;
            if (alu_z_valid) debug_status.zero <= alu_zero;
            if (alu_c_valid) debug_status.carry <= alu_carry;
        end
    endtask

    task automatic complete_read_operand(input logic [7:0] value);
        begin
            if (debug_decoded_instruction == CPU_INSTR_BIT) begin
                debug_status.negative <= value[7];
                debug_status.overflow <= value[6];
                debug_status.zero <= ((debug_a & value) == 8'h00);
                debug_execution_state <= CPU_STATE_FETCH;
            end else if (instruction_is_load) begin
                case (debug_decoded_instruction)
                    CPU_INSTR_LDA: debug_a <= value;
                    CPU_INSTR_LDX: debug_x <= value;
                    CPU_INSTR_LDY: debug_y <= value;
                    default: begin end
                endcase
                debug_status.negative <= value[7];
                debug_status.zero <= (value == 8'h00);
                debug_execution_state <= CPU_STATE_FETCH;
            end else if (instruction_uses_alu && !instruction_is_rmw) begin
                apply_alu_flags();
                if (instruction_is_compare) begin
                    debug_execution_state <= CPU_STATE_FETCH;
                end else if (alu_result_valid) begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_ADC, CPU_INSTR_SBC, CPU_INSTR_AND,
                        CPU_INSTR_ORA, CPU_INSTR_EOR: debug_a <= alu_result;
                        default: begin end
                    endcase
                    debug_execution_state <= CPU_STATE_FETCH;
                end else begin
                    debug_execution_state <= CPU_STATE_TRAP;
                end
            end else begin
                debug_execution_state <= CPU_STATE_TRAP;
            end
        end
    endtask

    task automatic select_memory_cycle;
        begin
            if (instruction_is_store)
                debug_execution_state <= CPU_STATE_MEMORY_WRITE;
            else if (instruction_is_load || instruction_uses_alu ||
                     debug_decoded_instruction == CPU_INSTR_BIT)
                debug_execution_state <= CPU_STATE_MEMORY_READ;
            else
                debug_execution_state <= CPU_STATE_TRAP;
        end
    endtask

    always_ff @(posedge clk) begin
        if (reset) begin
            debug_a <= CPU_RESET_A;
            debug_x <= CPU_RESET_X;
            debug_y <= CPU_RESET_Y;
            debug_sp <= CPU_RESET_SP;
            debug_pc <= CPU_RESET_PC;
            debug_status <= cpu_status_normalize(INITIAL_STATUS);
            debug_instruction <= CPU_RESET_IR;
            debug_execution_state <= CPU_STATE_RESET;
            debug_decoded_instruction <= CPU_INSTR_INVALID;
            debug_addressing_mode <= CPU_ADDR_IMPLIED;
            debug_effective_address <= 16'h0000;
            debug_page_cross <= 1'b0;
            debug_page_cross_valid <= 1'b0;
            instruction_is_load <= 1'b0;
            instruction_is_store <= 1'b0;
            instruction_uses_alu <= 1'b0;
            instruction_is_compare <= 1'b0;
            instruction_is_rmw <= 1'b0;
            alu_operation <= CPU_ALU_ADD;
            operand_low <= 8'h00;
            operand_high <= 8'h00;
            pointer_low <= 8'h00;
            pointer_high <= 8'h00;
            pointer_data_valid <= 1'b0;
            data_latch <= 8'h00;
            rmw_result <= 8'h00;
            return_address <= 16'h0000;
            rts_low_byte <= 8'h00;
            interrupt_source <= CPU_INTERRUPT_RESET;
            irq_poll_override_valid <= 1'b0;
            irq_poll_interrupt_disable <= 1'b1;
        end else if (cpu_enable) begin
            case (debug_execution_state)
                // Seven visible reset cycles: two discarded PC reads, three
                // stack reads/decrements, and the two vector reads.
                CPU_STATE_RESET: debug_execution_state <= CPU_STATE_RESET_DUMMY;
                CPU_STATE_RESET_DUMMY: debug_execution_state <= CPU_STATE_RESET_STACK_1;
                CPU_STATE_RESET_STACK_1: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_RESET_STACK_2; end
                CPU_STATE_RESET_STACK_2: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_RESET_STACK_3; end
                CPU_STATE_RESET_STACK_3: begin
                    debug_sp <= debug_sp - 8'd1;
                    debug_status.interrupt_disable <= 1'b1;
                    debug_execution_state <= CPU_STATE_RESET_VECTOR_LOW;
                end
                CPU_STATE_RESET_VECTOR_LOW: begin operand_low <= bus_read_data; debug_execution_state <= CPU_STATE_RESET_VECTOR_HIGH; end
                CPU_STATE_RESET_VECTOR_HIGH: begin
                    debug_pc <= {bus_read_data, operand_low};
                    debug_sp <= CPU_POST_RESET_SP;
                    interrupt_source <= CPU_INTERRUPT_NONE;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_FETCH: begin
                    // A saved PLP/CLI/SEI mask applies to this boundary only,
                    // whether the boundary accepts an interrupt or fetches
                    // the next opcode.
                    irq_poll_override_valid <= 1'b0;
                    if (accept_nmi || accept_irq) begin
                        return_address <= debug_pc;
                        interrupt_source <= accept_nmi ? CPU_INTERRUPT_NMI : CPU_INTERRUPT_IRQ;
                        debug_decoded_instruction <= CPU_INSTR_INVALID;
                        debug_execution_state <= CPU_STATE_INTERRUPT_DUMMY;
                    end else begin
                        debug_instruction <= bus_read_data;
                        debug_decoded_instruction <= decoded.instruction;
                        debug_addressing_mode <= decoded.addressing_mode;
                        instruction_is_load <= decoded.is_load;
                        instruction_is_store <= decoded.is_store;
                        instruction_uses_alu <= decoded.uses_alu;
                        instruction_is_compare <= decoded.is_compare;
                        instruction_is_rmw <= decoded.is_rmw;
                        alu_operation <= decoded.alu_operation;
                        debug_pc <= debug_pc + 16'd1;
                        debug_page_cross <= 1'b0;
                        debug_page_cross_valid <= 1'b0;
                        operand_low <= 8'h00;
                        operand_high <= 8'h00;
                        pointer_low <= 8'h00;
                        pointer_high <= 8'h00;
                        pointer_data_valid <= 1'b0;
                        data_latch <= 8'h00;
                        rmw_result <= 8'h00;
                        return_address <= 16'h0000;
                        rts_low_byte <= 8'h00;
                        if (!decoded.valid)
                            debug_execution_state <= CPU_STATE_TRAP;
                        else if (decoded.instruction == CPU_INSTR_BRK)
                            debug_execution_state <= CPU_STATE_BRK_PADDING;
                        else if (decoded.instruction == CPU_INSTR_RTI)
                            debug_execution_state <= CPU_STATE_RTI_PULL;
                        else if (decoded.instruction == CPU_INSTR_RTS)
                            debug_execution_state <= CPU_STATE_RTS_PULL;
                        else if (decoded.instruction == CPU_INSTR_JSR)
                            debug_execution_state <= CPU_STATE_OPERAND_LOW;
                        else if (decoded.is_transfer)
                            debug_execution_state <= CPU_STATE_TRANSFER;
                        else if (decoded.is_stack)
                            debug_execution_state <= CPU_STATE_STACK_DUMMY;
                        else if (decoded.uses_alu &&
                                 (decoded.addressing_mode == CPU_ADDR_IMPLIED ||
                                  decoded.addressing_mode == CPU_ADDR_ACCUMULATOR))
                            debug_execution_state <= CPU_STATE_ALU_EXECUTE;
                        else if (decoded.addressing_mode == CPU_ADDR_IMPLIED)
                            debug_execution_state <= CPU_STATE_IMPLIED;
                        else
                            debug_execution_state <= CPU_STATE_OPERAND_LOW;
                    end
                end

                CPU_STATE_OPERAND_LOW: begin
                    operand_low <= bus_read_data;
                    debug_pc <= debug_pc + 16'd1;
                    if (debug_addressing_mode == CPU_ADDR_IMMEDIATE)
                        complete_read_operand(bus_read_data);
                    else if (debug_addressing_mode == CPU_ADDR_RELATIVE) begin
                        debug_effective_address <= branch_fetch_response.branch_target;
                        debug_page_cross <= branch_fetch_response.page_cross;
                        debug_page_cross_valid <= branch_fetch_response.page_cross_valid;
                        if (branch_taken) debug_execution_state <= CPU_STATE_BRANCH_DECIDE;
                        else debug_execution_state <= CPU_STATE_FETCH;
                    end else if (debug_decoded_instruction == CPU_INSTR_JSR)
                        debug_execution_state <= CPU_STATE_JSR_DUMMY;
                    else if (debug_addressing_mode == CPU_ADDR_ZERO_PAGE_X ||
                             debug_addressing_mode == CPU_ADDR_ZERO_PAGE_Y ||
                             debug_addressing_mode == CPU_ADDR_INDEXED_INDIRECT_X)
                        debug_execution_state <= CPU_STATE_INDEX_DUMMY;
                    else if (debug_addressing_mode == CPU_ADDR_INDIRECT_INDEXED_Y)
                        debug_execution_state <= CPU_STATE_POINTER_LOW;
                    else if (debug_addressing_mode == CPU_ADDR_ZERO_PAGE) begin
                        debug_effective_address <= {8'h00, bus_read_data};
                        select_memory_cycle();
                    end else
                        debug_execution_state <= CPU_STATE_OPERAND_HIGH;
                end

                CPU_STATE_OPERAND_HIGH: begin
                    operand_high <= bus_read_data;
                    debug_pc <= debug_pc + 16'd1;
                    if (debug_decoded_instruction == CPU_INSTR_JMP &&
                        debug_addressing_mode == CPU_ADDR_ABSOLUTE) begin
                        debug_effective_address <= {bus_read_data, operand_low};
                        debug_pc <= {bus_read_data, operand_low};
                        debug_execution_state <= CPU_STATE_FETCH;
                    end else if (debug_addressing_mode == CPU_ADDR_INDIRECT)
                        debug_execution_state <= CPU_STATE_POINTER_LOW;
                    else if (debug_addressing_mode == CPU_ADDR_ABSOLUTE_X ||
                             debug_addressing_mode == CPU_ADDR_ABSOLUTE_Y) begin
                        if (instruction_is_store || instruction_is_rmw)
                            debug_execution_state <= CPU_STATE_INDEX_DUMMY;
                        else
                            debug_execution_state <= CPU_STATE_INDEXED_READ;
                    end else
                        select_memory_cycle();
                end

                CPU_STATE_INDEX_DUMMY: begin
                    if (debug_addressing_mode == CPU_ADDR_INDEXED_INDIRECT_X)
                        debug_execution_state <= CPU_STATE_POINTER_LOW;
                    else if (address_response.effective_address_valid) begin
                        debug_effective_address <= address_response.effective_address;
                        debug_page_cross <= address_response.page_cross;
                        debug_page_cross_valid <= address_response.page_cross_valid;
                        select_memory_cycle();
                    end else
                        debug_execution_state <= CPU_STATE_TRAP;
                end

                CPU_STATE_POINTER_LOW: begin pointer_low <= bus_read_data; debug_execution_state <= CPU_STATE_POINTER_HIGH; end
                CPU_STATE_POINTER_HIGH: begin
                    pointer_high <= bus_read_data;
                    pointer_data_valid <= 1'b1;
                    if (debug_addressing_mode == CPU_ADDR_INDIRECT) begin
                        debug_effective_address <= {bus_read_data, pointer_low};
                        debug_pc <= {bus_read_data, pointer_low};
                        debug_execution_state <= CPU_STATE_FETCH;
                    end else if (debug_addressing_mode == CPU_ADDR_INDIRECT_INDEXED_Y)
                        debug_execution_state <= instruction_is_store ? CPU_STATE_INDEX_DUMMY : CPU_STATE_INDEXED_READ;
                    else
                        select_memory_cycle();
                end

                CPU_STATE_INDEXED_READ: begin
                    if (!address_response.effective_address_valid ||
                        !address_response.indexed_tentative_valid)
                        debug_execution_state <= CPU_STATE_TRAP;
                    else begin
                        debug_effective_address <= address_response.effective_address;
                        debug_page_cross <= address_response.page_cross;
                        debug_page_cross_valid <= address_response.page_cross_valid;
                        if (address_response.page_cross)
                            debug_execution_state <= CPU_STATE_MEMORY_READ;
                        else
                            complete_read_operand(bus_read_data);
                    end
                end

                CPU_STATE_MEMORY_READ: begin
                    if (!address_response.effective_address_valid)
                        debug_execution_state <= CPU_STATE_TRAP;
                    else begin
                        debug_effective_address <= address_response.effective_address;
                        if (instruction_is_rmw) begin
                            data_latch <= bus_read_data;
                            rmw_result <= alu_result;
                            apply_alu_flags();
                            debug_execution_state <= CPU_STATE_RMW_DUMMY_WRITE;
                        end else
                            complete_read_operand(bus_read_data);
                    end
                end
                CPU_STATE_MEMORY_WRITE: begin
                    debug_effective_address <= address_response.effective_address;
                    debug_page_cross <= address_response.page_cross;
                    debug_page_cross_valid <= address_response.page_cross_valid;
                    debug_execution_state <= CPU_STATE_FETCH;
                end
                CPU_STATE_RMW_DUMMY_WRITE: debug_execution_state <= CPU_STATE_RMW_WRITE;
                CPU_STATE_RMW_WRITE: debug_execution_state <= CPU_STATE_FETCH;

                CPU_STATE_TRANSFER: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_TAX: begin debug_x <= debug_a; debug_status.negative <= debug_a[7]; debug_status.zero <= (debug_a == 8'h00); end
                        CPU_INSTR_TAY: begin debug_y <= debug_a; debug_status.negative <= debug_a[7]; debug_status.zero <= (debug_a == 8'h00); end
                        CPU_INSTR_TXA: begin debug_a <= debug_x; debug_status.negative <= debug_x[7]; debug_status.zero <= (debug_x == 8'h00); end
                        CPU_INSTR_TYA: begin debug_a <= debug_y; debug_status.negative <= debug_y[7]; debug_status.zero <= (debug_y == 8'h00); end
                        CPU_INSTR_TSX: begin debug_x <= debug_sp; debug_status.negative <= debug_sp[7]; debug_status.zero <= (debug_sp == 8'h00); end
                        CPU_INSTR_TXS: debug_sp <= debug_x;
                        default: begin end
                    endcase
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_IMPLIED: begin
                    case (debug_decoded_instruction)
                        CPU_INSTR_CLC: debug_status.carry <= 1'b0;
                        CPU_INSTR_SEC: debug_status.carry <= 1'b1;
                        CPU_INSTR_CLI: begin
                            irq_poll_override_valid <= 1'b1;
                            irq_poll_interrupt_disable <=
                                debug_status.interrupt_disable;
                            debug_status.interrupt_disable <= 1'b0;
                        end
                        CPU_INSTR_SEI: begin
                            irq_poll_override_valid <= 1'b1;
                            irq_poll_interrupt_disable <=
                                debug_status.interrupt_disable;
                            debug_status.interrupt_disable <= 1'b1;
                        end
                        CPU_INSTR_CLV: debug_status.overflow <= 1'b0;
                        CPU_INSTR_CLD: debug_status.decimal <= 1'b0;
                        CPU_INSTR_SED: debug_status.decimal <= 1'b1;
                        CPU_INSTR_NOP: begin end
                        default: debug_execution_state <= CPU_STATE_TRAP;
                    endcase
                    if (debug_decoded_instruction >= CPU_INSTR_CLC &&
                        debug_decoded_instruction <= CPU_INSTR_NOP)
                        debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_ALU_EXECUTE: begin
                    apply_alu_flags();
                    if (!alu_result_valid)
                        debug_execution_state <= CPU_STATE_TRAP;
                    else begin
                        case (debug_decoded_instruction)
                            CPU_INSTR_INX, CPU_INSTR_DEX: debug_x <= alu_result;
                            CPU_INSTR_INY, CPU_INSTR_DEY: debug_y <= alu_result;
                            CPU_INSTR_ASL, CPU_INSTR_LSR,
                            CPU_INSTR_ROL, CPU_INSTR_ROR: debug_a <= alu_result;
                            default: begin end
                        endcase
                        debug_execution_state <= CPU_STATE_FETCH;
                    end
                end

                CPU_STATE_BRANCH_DECIDE: begin
                    if (!address_response.branch_target_valid)
                        debug_execution_state <= CPU_STATE_TRAP;
                    else begin
                        debug_effective_address <= address_response.branch_target;
                        debug_page_cross <= address_response.page_cross;
                        debug_page_cross_valid <= address_response.page_cross_valid;
                        if (address_response.page_cross) begin
                            debug_pc <= address_response.branch_tentative_address;
                            debug_execution_state <= CPU_STATE_BRANCH_PAGE;
                        end else begin
                            debug_pc <= address_response.branch_target;
                            debug_execution_state <= CPU_STATE_FETCH;
                        end
                    end
                end
                CPU_STATE_BRANCH_PAGE: begin debug_pc <= debug_effective_address; debug_execution_state <= CPU_STATE_FETCH; end

                CPU_STATE_STACK_DUMMY: begin
                    if (debug_decoded_instruction == CPU_INSTR_PHA ||
                        debug_decoded_instruction == CPU_INSTR_PHP)
                        debug_execution_state <= CPU_STATE_STACK_PUSH;
                    else
                        debug_execution_state <= CPU_STATE_STACK_PULL;
                end
                CPU_STATE_STACK_PUSH: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_FETCH; end
                CPU_STATE_STACK_PULL: begin debug_sp <= debug_sp + 8'd1; debug_execution_state <= CPU_STATE_STACK_READ; end
                CPU_STATE_STACK_READ: begin
                    if (debug_decoded_instruction == CPU_INSTR_PLA) begin
                        debug_a <= bus_read_data;
                        debug_status.negative <= bus_read_data[7];
                        debug_status.zero <= (bus_read_data == 8'h00);
                    end else if (debug_decoded_instruction == CPU_INSTR_PLP) begin
                        irq_poll_override_valid <= 1'b1;
                        irq_poll_interrupt_disable <=
                            debug_status.interrupt_disable;
                        debug_status <= cpu_status_normalize(bus_read_data);
                    end
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_JSR_DUMMY: begin return_address <= debug_pc; debug_execution_state <= CPU_STATE_JSR_PUSH_HIGH; end
                CPU_STATE_JSR_PUSH_HIGH: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_JSR_PUSH_LOW; end
                CPU_STATE_JSR_PUSH_LOW: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_JSR_TARGET_HIGH; end
                CPU_STATE_JSR_TARGET_HIGH: begin
                    operand_high <= bus_read_data;
                    debug_effective_address <= {bus_read_data, operand_low};
                    debug_pc <= {bus_read_data, operand_low};
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_RTS_PULL: debug_execution_state <= CPU_STATE_RTS_STACK_DUMMY;
                CPU_STATE_RTS_STACK_DUMMY: begin debug_sp <= debug_sp + 8'd1; debug_execution_state <= CPU_STATE_RTS_PULL_LOW; end
                CPU_STATE_RTS_PULL_LOW: begin rts_low_byte <= bus_read_data; debug_sp <= debug_sp + 8'd1; debug_execution_state <= CPU_STATE_RTS_PULL_HIGH; end
                CPU_STATE_RTS_PULL_HIGH: begin operand_high <= bus_read_data; debug_execution_state <= CPU_STATE_RTS_COMPLETE; end
                CPU_STATE_RTS_COMPLETE: begin debug_pc <= {operand_high, rts_low_byte} + 16'd1; debug_execution_state <= CPU_STATE_FETCH; end

                CPU_STATE_BRK_PADDING: begin
                    debug_pc <= debug_pc + 16'd1;
                    return_address <= debug_pc + 16'd1;
                    interrupt_source <= CPU_INTERRUPT_BRK;
                    debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_HIGH;
                end
                CPU_STATE_INTERRUPT_DUMMY: debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_HIGH;
                CPU_STATE_INTERRUPT_PUSH_HIGH: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_LOW; end
                CPU_STATE_INTERRUPT_PUSH_LOW: begin debug_sp <= debug_sp - 8'd1; debug_execution_state <= CPU_STATE_INTERRUPT_PUSH_STATUS; end
                CPU_STATE_INTERRUPT_PUSH_STATUS: begin
                    debug_sp <= debug_sp - 8'd1;
                    debug_status.interrupt_disable <= 1'b1;
                    debug_execution_state <= CPU_STATE_INTERRUPT_VECTOR_LOW;
                end
                CPU_STATE_INTERRUPT_VECTOR_LOW: begin operand_low <= bus_read_data; debug_execution_state <= CPU_STATE_INTERRUPT_VECTOR_HIGH; end
                CPU_STATE_INTERRUPT_VECTOR_HIGH: begin
                    debug_pc <= {bus_read_data, operand_low};
                    interrupt_source <= CPU_INTERRUPT_NONE;
                    debug_execution_state <= CPU_STATE_FETCH;
                end

                CPU_STATE_RTI_PULL: debug_execution_state <= CPU_STATE_RTI_STACK_DUMMY;
                CPU_STATE_RTI_STACK_DUMMY: begin debug_sp <= debug_sp + 8'd1; debug_execution_state <= CPU_STATE_RTI_PULL_STATUS; end
                CPU_STATE_RTI_PULL_STATUS: begin debug_status <= cpu_status_normalize(bus_read_data); debug_sp <= debug_sp + 8'd1; debug_execution_state <= CPU_STATE_RTI_PULL_LOW; end
                CPU_STATE_RTI_PULL_LOW: begin rts_low_byte <= bus_read_data; debug_sp <= debug_sp + 8'd1; debug_execution_state <= CPU_STATE_RTI_PULL_HIGH; end
                CPU_STATE_RTI_PULL_HIGH: begin debug_pc <= {bus_read_data, rts_low_byte}; debug_execution_state <= CPU_STATE_FETCH; end

                CPU_STATE_TRAP: debug_execution_state <= CPU_STATE_TRAP;
                default: debug_execution_state <= CPU_STATE_TRAP;
            endcase
        end
    end

    // Every active NMOS cycle performs a read or write. Signals remain stable
    // while cpu_enable is low; memory commits writes only on enabled edges.
    always_comb begin
        bus_address = debug_pc;
        bus_write_data = 8'h00;
        bus_write_enable = 1'b0;
        bus_valid = 1'b0;
        if (!reset) begin
            case (debug_execution_state)
                CPU_STATE_RESET, CPU_STATE_RESET_DUMMY, CPU_STATE_FETCH,
                CPU_STATE_TRANSFER, CPU_STATE_ALU_EXECUTE, CPU_STATE_IMPLIED,
                CPU_STATE_STACK_DUMMY, CPU_STATE_RTS_PULL,
                CPU_STATE_RTI_PULL, CPU_STATE_INTERRUPT_DUMMY,
                CPU_STATE_BRK_PADDING: begin bus_address = debug_pc; bus_valid = 1'b1; end

                CPU_STATE_OPERAND_LOW, CPU_STATE_OPERAND_HIGH,
                CPU_STATE_JSR_TARGET_HIGH: begin bus_address = debug_pc; bus_valid = 1'b1; end

                CPU_STATE_RESET_STACK_1, CPU_STATE_RESET_STACK_2,
                CPU_STATE_RESET_STACK_3, CPU_STATE_STACK_PULL,
                CPU_STATE_RTS_STACK_DUMMY, CPU_STATE_RTI_STACK_DUMMY: begin
                    bus_address = {8'h01, debug_sp}; bus_valid = 1'b1;
                end

                CPU_STATE_INDEX_DUMMY: begin
                    if (debug_addressing_mode == CPU_ADDR_ZERO_PAGE_X ||
                        debug_addressing_mode == CPU_ADDR_ZERO_PAGE_Y ||
                        debug_addressing_mode == CPU_ADDR_INDEXED_INDIRECT_X) begin
                        bus_address = {8'h00, operand_low}; bus_valid = 1'b1;
                    end else begin
                        bus_address = address_response.indexed_tentative_address;
                        bus_valid = address_response.indexed_tentative_valid;
                    end
                end
                CPU_STATE_INDEXED_READ: begin
                    bus_address = address_response.indexed_tentative_address;
                    bus_valid = address_response.indexed_tentative_valid;
                end
                CPU_STATE_POINTER_LOW: begin bus_address = address_response.pointer_low_address; bus_valid = address_response.pointer_addresses_valid; end
                CPU_STATE_POINTER_HIGH: begin bus_address = address_response.pointer_high_address; bus_valid = address_response.pointer_addresses_valid; end
                CPU_STATE_MEMORY_READ: begin bus_address = address_response.effective_address; bus_valid = address_response.effective_address_valid; end

                CPU_STATE_MEMORY_WRITE: begin
                    bus_address = address_response.effective_address;
                    bus_valid = address_response.effective_address_valid;
                    bus_write_enable = address_response.effective_address_valid;
                    case (debug_decoded_instruction)
                        CPU_INSTR_STA: bus_write_data = debug_a;
                        CPU_INSTR_STX: bus_write_data = debug_x;
                        CPU_INSTR_STY: bus_write_data = debug_y;
                        default: begin bus_valid = 1'b0; bus_write_enable = 1'b0; end
                    endcase
                end
                CPU_STATE_RMW_DUMMY_WRITE: begin bus_address = debug_effective_address; bus_write_data = data_latch; bus_write_enable = 1'b1; bus_valid = 1'b1; end
                CPU_STATE_RMW_WRITE: begin bus_address = debug_effective_address; bus_write_data = rmw_result; bus_write_enable = 1'b1; bus_valid = 1'b1; end

                CPU_STATE_BRANCH_DECIDE, CPU_STATE_BRANCH_PAGE: begin bus_address = debug_pc; bus_valid = 1'b1; end

                CPU_STATE_STACK_PUSH: begin
                    bus_address = {8'h01, debug_sp}; bus_valid = 1'b1; bus_write_enable = 1'b1;
                    if (debug_decoded_instruction == CPU_INSTR_PHA) bus_write_data = debug_a;
                    else bus_write_data = cpu_status_for_php(debug_status);
                end
                CPU_STATE_STACK_READ, CPU_STATE_RTS_PULL_LOW,
                CPU_STATE_RTS_PULL_HIGH, CPU_STATE_RTI_PULL_STATUS,
                CPU_STATE_RTI_PULL_LOW, CPU_STATE_RTI_PULL_HIGH: begin
                    bus_address = {8'h01, debug_sp}; bus_valid = 1'b1;
                end

                CPU_STATE_JSR_DUMMY: begin bus_address = {8'h01, debug_sp}; bus_valid = 1'b1; end
                CPU_STATE_JSR_PUSH_HIGH: begin bus_address = {8'h01, debug_sp}; bus_write_data = return_address[15:8]; bus_write_enable = 1'b1; bus_valid = 1'b1; end
                CPU_STATE_JSR_PUSH_LOW: begin bus_address = {8'h01, debug_sp}; bus_write_data = return_address[7:0]; bus_write_enable = 1'b1; bus_valid = 1'b1; end
                CPU_STATE_RTS_COMPLETE: begin bus_address = {operand_high, rts_low_byte}; bus_valid = 1'b1; end

                CPU_STATE_INTERRUPT_PUSH_HIGH: begin bus_address = {8'h01, debug_sp}; bus_write_data = return_address[15:8]; bus_write_enable = 1'b1; bus_valid = 1'b1; end
                CPU_STATE_INTERRUPT_PUSH_LOW: begin bus_address = {8'h01, debug_sp}; bus_write_data = return_address[7:0]; bus_write_enable = 1'b1; bus_valid = 1'b1; end
                CPU_STATE_INTERRUPT_PUSH_STATUS: begin
                    bus_address = {8'h01, debug_sp};
                    bus_write_data = interrupt_source == CPU_INTERRUPT_BRK ? cpu_status_for_php(debug_status) : cpu_status_for_interrupt(debug_status);
                    bus_write_enable = 1'b1; bus_valid = 1'b1;
                end
                CPU_STATE_INTERRUPT_VECTOR_LOW: begin bus_address = interrupt_vector_low_address; bus_valid = 1'b1; end
                CPU_STATE_INTERRUPT_VECTOR_HIGH: begin bus_address = interrupt_vector_low_address + 16'd1; bus_valid = 1'b1; end
                CPU_STATE_RESET_VECTOR_LOW: begin bus_address = CPU_VECTOR_RESET_LOW; bus_valid = 1'b1; end
                CPU_STATE_RESET_VECTOR_HIGH: begin bus_address = CPU_VECTOR_RESET_LOW + 16'd1; bus_valid = 1'b1; end
                default: begin end
            endcase
        end
    end
endmodule
