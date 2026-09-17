`timescale 1ns/1ps

package cpu_pkg;
    // Deterministic post-reset architectural values. PC remains zero while
    // reset is asserted, then is loaded only by the bus-visible $FFFC/$FFFD
    // reset-vector sequence.
    localparam logic [7:0]  CPU_RESET_A      = 8'h00;
    localparam logic [7:0]  CPU_RESET_X      = 8'h00;
    localparam logic [7:0]  CPU_RESET_Y      = 8'h00;
    localparam logic [7:0]  CPU_RESET_SP     = 8'hFD;
    localparam logic [15:0] CPU_RESET_PC     = 16'h0000;
    localparam logic [7:0]  CPU_RESET_STATUS = 8'h24;
    localparam logic [7:0]  CPU_RESET_IR     = 8'h00;

    // Packed in the 6502 processor-status order: N V U B D I Z C.
    typedef struct packed {
        logic negative;
        logic overflow;
        logic unused;
        logic break_command;
        logic decimal;
        logic interrupt_disable;
        logic zero;
        logic carry;
    } cpu_status_t;

    localparam logic [7:0] CPU_STATUS_BREAK_MASK  = 8'h10;
    localparam logic [7:0] CPU_STATUS_UNUSED_MASK = 8'h20;

    localparam logic [15:0] CPU_VECTOR_NMI_LOW   = 16'hFFFA;
    localparam logic [15:0] CPU_VECTOR_RESET_LOW = 16'hFFFC;
    localparam logic [15:0] CPU_VECTOR_IRQ_LOW   = 16'hFFFE;

    // B is not persistent processor state on NMOS 6502-family hardware; it is
    // synthesized when status is pushed. Keep stored B clear and U set. The D
    // bit remains stored for architectural compatibility, although the 2A03
    // will never perform decimal arithmetic.
    function automatic logic [7:0] cpu_status_normalize(
        input logic [7:0] value
    );
        cpu_status_normalize =
            (value | CPU_STATUS_UNUSED_MASK) & ~CPU_STATUS_BREAK_MASK;
    endfunction

    // PHP does not expose the normalized internal byte verbatim. NMOS 6502
    // hardware synthesizes both B and U high for the value written to the
    // stack while B remains nonpersistent internally.
    function automatic logic [7:0] cpu_status_for_php(
        input logic [7:0] value
    );
        cpu_status_for_php = cpu_status_normalize(value) |
                             CPU_STATUS_BREAK_MASK;
    endfunction

    // Hardware interrupt entry writes B=0 and U=1. PHP and BRK instead use
    // cpu_status_for_php(), which synthesizes B=1 and U=1.
    function automatic logic [7:0] cpu_status_for_interrupt(
        input logic [7:0] value
    );
        cpu_status_for_interrupt = cpu_status_normalize(value);
    endfunction

    // Explicit micro-operation boundaries. Each state advances
    // only on cpu_enable; bus states remain stable between enable pulses.
    typedef enum logic [5:0] {
        CPU_STATE_RESET                 = 6'd0,
        CPU_STATE_FETCH                 = 6'd1,
        CPU_STATE_DECODE                = 6'd2,
        CPU_STATE_OPERAND_LOW           = 6'd3,
        CPU_STATE_OPERAND_HIGH          = 6'd4,
        CPU_STATE_ADDRESS               = 6'd5,
        CPU_STATE_POINTER_LOW           = 6'd6,
        CPU_STATE_POINTER_HIGH          = 6'd7,
        CPU_STATE_MEMORY_READ           = 6'd8,
        CPU_STATE_MEMORY_WRITE          = 6'd9,
        CPU_STATE_WRITEBACK             = 6'd10,
        CPU_STATE_TRANSFER              = 6'd11,
        CPU_STATE_TRAP                  = 6'd12,
        CPU_STATE_ALU_EXECUTE           = 6'd13,
        CPU_STATE_RMW_WRITE             = 6'd14,
        CPU_STATE_BRANCH_DECIDE         = 6'd15,
        CPU_STATE_STACK_PUSH            = 6'd16,
        CPU_STATE_STACK_PULL            = 6'd17,
        CPU_STATE_STACK_READ            = 6'd18,
        CPU_STATE_JSR_PUSH_HIGH         = 6'd19,
        CPU_STATE_JSR_PUSH_LOW          = 6'd20,
        CPU_STATE_RTS_PULL              = 6'd21,
        CPU_STATE_RTS_PULL_LOW          = 6'd22,
        CPU_STATE_RTS_PULL_HIGH         = 6'd23,
        CPU_STATE_RTS_COMPLETE          = 6'd24,
        CPU_STATE_RESET_VECTOR_LOW      = 6'd25,
        CPU_STATE_RESET_VECTOR_HIGH     = 6'd26,
        CPU_STATE_INTERRUPT_PUSH_HIGH   = 6'd27,
        CPU_STATE_INTERRUPT_PUSH_LOW    = 6'd28,
        CPU_STATE_INTERRUPT_PUSH_STATUS = 6'd29,
        CPU_STATE_INTERRUPT_VECTOR_LOW  = 6'd30,
        CPU_STATE_INTERRUPT_VECTOR_HIGH = 6'd31,
        CPU_STATE_BRK_PADDING           = 6'd32,
        CPU_STATE_RTI_PULL              = 6'd33,
        CPU_STATE_RTI_PULL_STATUS       = 6'd34,
        CPU_STATE_RTI_PULL_LOW          = 6'd35,
        CPU_STATE_RTI_PULL_HIGH         = 6'd36,
        CPU_STATE_RTI_COMPLETE          = 6'd37
    } cpu_execution_state_t;

    typedef enum logic [5:0] {
        CPU_INSTR_INVALID = 6'd0,
        CPU_INSTR_LDA     = 6'd1,
        CPU_INSTR_LDX     = 6'd2,
        CPU_INSTR_LDY     = 6'd3,
        CPU_INSTR_STA     = 6'd4,
        CPU_INSTR_STX     = 6'd5,
        CPU_INSTR_STY     = 6'd6,
        CPU_INSTR_TAX     = 6'd7,
        CPU_INSTR_TAY     = 6'd8,
        CPU_INSTR_TXA     = 6'd9,
        CPU_INSTR_TYA     = 6'd10,
        CPU_INSTR_TSX     = 6'd11,
        CPU_INSTR_TXS     = 6'd12,
        CPU_INSTR_ADC     = 6'd13,
        CPU_INSTR_SBC     = 6'd14,
        CPU_INSTR_AND     = 6'd15,
        CPU_INSTR_ORA     = 6'd16,
        CPU_INSTR_EOR     = 6'd17,
        CPU_INSTR_CMP     = 6'd18,
        CPU_INSTR_CPX     = 6'd19,
        CPU_INSTR_CPY     = 6'd20,
        CPU_INSTR_INX     = 6'd21,
        CPU_INSTR_INY     = 6'd22,
        CPU_INSTR_DEX     = 6'd23,
        CPU_INSTR_DEY     = 6'd24,
        CPU_INSTR_INC     = 6'd25,
        CPU_INSTR_DEC     = 6'd26,
        CPU_INSTR_ASL     = 6'd27,
        CPU_INSTR_LSR     = 6'd28,
        CPU_INSTR_ROL     = 6'd29,
        CPU_INSTR_ROR     = 6'd30,
        CPU_INSTR_JMP     = 6'd31,
        CPU_INSTR_JSR     = 6'd32,
        CPU_INSTR_RTS     = 6'd33,
        CPU_INSTR_BCC     = 6'd34,
        CPU_INSTR_BCS     = 6'd35,
        CPU_INSTR_BEQ     = 6'd36,
        CPU_INSTR_BMI     = 6'd37,
        CPU_INSTR_BNE     = 6'd38,
        CPU_INSTR_BPL     = 6'd39,
        CPU_INSTR_BVC     = 6'd40,
        CPU_INSTR_BVS     = 6'd41,
        CPU_INSTR_PHA     = 6'd42,
        CPU_INSTR_PLA     = 6'd43,
        CPU_INSTR_PHP     = 6'd44,
        CPU_INSTR_PLP     = 6'd45,
        CPU_INSTR_BRK     = 6'd46,
        CPU_INSTR_RTI     = 6'd47
    } cpu_instruction_t;

    typedef enum logic [2:0] {
        CPU_INTERRUPT_NONE  = 3'd0,
        CPU_INTERRUPT_RESET = 3'd1,
        CPU_INTERRUPT_NMI   = 3'd2,
        CPU_INTERRUPT_IRQ   = 3'd3,
        CPU_INTERRUPT_BRK   = 3'd4
    } cpu_interrupt_source_t;

    typedef enum logic [3:0] {
        CPU_ALU_ADD = 4'd0,
        CPU_ALU_SUB = 4'd1,
        CPU_ALU_AND = 4'd2,
        CPU_ALU_OR  = 4'd3,
        CPU_ALU_XOR = 4'd4,
        CPU_ALU_ASL = 4'd5,
        CPU_ALU_LSR = 4'd6,
        CPU_ALU_ROL = 4'd7,
        CPU_ALU_ROR = 4'd8,
        CPU_ALU_INC = 4'd9,
        CPU_ALU_DEC = 4'd10,
        CPU_ALU_CMP = 4'd11
    } cpu_alu_operation_t;

    // Phase 2C addressing-mode identifiers are independent of opcode decode.
    // The request carries a raw 4-bit value so reserved encodings can be
    // rejected deterministically instead of being hidden by an enum cast.
    typedef enum logic [3:0] {
        CPU_ADDR_IMPLIED            = 4'd0,
        CPU_ADDR_ACCUMULATOR        = 4'd1,
        CPU_ADDR_IMMEDIATE          = 4'd2,
        CPU_ADDR_ZERO_PAGE          = 4'd3,
        CPU_ADDR_ZERO_PAGE_X        = 4'd4,
        CPU_ADDR_ZERO_PAGE_Y        = 4'd5,
        CPU_ADDR_ABSOLUTE           = 4'd6,
        CPU_ADDR_ABSOLUTE_X         = 4'd7,
        CPU_ADDR_ABSOLUTE_Y         = 4'd8,
        CPU_ADDR_INDIRECT           = 4'd9,
        CPU_ADDR_INDEXED_INDIRECT_X = 4'd10,
        CPU_ADDR_INDIRECT_INDEXED_Y = 4'd11,
        CPU_ADDR_RELATIVE           = 4'd12
    } cpu_addressing_mode_t;

    typedef struct packed {
        logic [3:0]  addressing_mode;
        logic [15:0] base_address;
        logic [7:0]  operand_byte;
        logic [7:0]  x_index;
        logic [7:0]  y_index;
        logic [7:0]  pointer_low_byte;
        logic [7:0]  pointer_high_byte;
        logic        pointer_data_valid;
    } cpu_address_request_t;

    typedef struct packed {
        logic [15:0] effective_address;
        logic        effective_address_valid;
        logic [15:0] pointer_low_address;
        logic [15:0] pointer_high_address;
        logic        pointer_addresses_valid;
        logic [15:0] branch_target;
        logic        branch_target_valid;
        logic [7:0]  immediate_value;
        logic        immediate_valid;
        logic        page_cross;
        logic        page_cross_valid;
        logic        uses_accumulator;
        logic        is_implied;
        logic        mode_valid;
        logic        result_valid;
    } cpu_address_result_t;

    typedef struct packed {
        cpu_instruction_t instruction;
        cpu_alu_operation_t alu_operation;
        logic [3:0]       addressing_mode;
        logic [1:0]       operand_bytes;
        logic             is_load;
        logic             is_store;
        logic             is_transfer;
        logic             uses_alu;
        logic             is_compare;
        logic             is_rmw;
        logic             is_branch;
        logic             is_jump;
        logic             is_stack;
        logic             is_interrupt;
        logic             valid;
    } cpu_decode_result_t;
endpackage
