`timescale 1ns/1ps

package cpu_board_diag_pkg;
    localparam logic [15:0] CPU_DIAG_PROGRAM_START    = 16'h8000;
    localparam logic [15:0] CPU_DIAG_PROGRAM_END      = 16'h83FF;
    localparam logic [15:0] CPU_DIAG_IRQ_HANDLER      = 16'h83A0;
    localparam logic [15:0] CPU_DIAG_NMI_HANDLER      = 16'h83B0;
    localparam logic [15:0] CPU_DIAG_FAIL_LOOP        = 16'h83D3;
    localparam logic [15:0] CPU_DIAG_PASS_LOOP        = 16'h83F0;

    // These are diagnostic-only control/status locations. They are not an
    // NES memory-map proposal and remain private to the Phase 2K harness.
    localparam logic [15:0] CPU_DIAG_RESULT_ADDRESS   = 16'h6000;
    localparam logic [15:0] CPU_DIAG_IRQ_CONTROL      = 16'h6001;
    localparam logic [15:0] CPU_DIAG_NMI_CONTROL      = 16'h6002;
    localparam logic [15:0] CPU_DIAG_STALL_CONTROL    = 16'h6003;

    localparam logic [7:0] CPU_DIAG_REQUEST_SIGNATURE = 8'h5A;
    localparam logic [7:0] CPU_DIAG_PASS_SIGNATURE    = 8'hA5;
    localparam logic [7:0] CPU_DIAG_INTERNAL_FAILURE  = 8'hFC;
    localparam logic [7:0] CPU_DIAG_TRAP_FAILURE      = 8'hFE;
endpackage
