`timescale 1ns/1ps

package cpu_pkg;
    // Deterministic Phase 2A architectural reset values. PC is a placeholder;
    // a later CPU phase will replace it with the 6502 reset-vector sequence.
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

    // Only RESET and FETCH are active in Phase 2A. The remaining encodings
    // reserve clean boundaries for later instruction-engine phases.
    typedef enum logic [2:0] {
        CPU_STATE_RESET     = 3'd0,
        CPU_STATE_FETCH     = 3'd1,
        CPU_STATE_DECODE    = 3'd2,
        CPU_STATE_EXECUTE   = 3'd3,
        CPU_STATE_MEMORY    = 3'd4,
        CPU_STATE_WRITEBACK = 3'd5
    } cpu_execution_state_t;

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
endpackage
