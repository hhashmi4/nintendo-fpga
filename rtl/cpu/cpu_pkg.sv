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
endpackage
