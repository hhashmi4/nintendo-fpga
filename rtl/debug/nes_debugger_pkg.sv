`timescale 1ns/1ps
package nes_debugger_pkg;
    typedef enum logic [2:0] {
        DBG_RUN = 3'd0, DBG_PAUSE = 3'd1,
        DBG_STEP_I = 3'd2, DBG_STEP_F = 3'd3
    } debugger_command_t;
    typedef enum logic [2:0] {
        DBG_RUNNING = 3'd0, DBG_PAUSE_REQUESTED = 3'd1,
        DBG_PAUSED = 3'd2, DBG_INSTRUCTION_STEP = 3'd3,
        DBG_FRAME_STEP = 3'd4
    } debugger_state_t;
    localparam logic [1:0] DBG_OK = 2'd0;
    localparam logic [1:0] DBG_WRONG_STATE = 2'd1;
    localparam logic [1:0] DBG_BUSY = 2'd2;
    localparam logic [1:0] DBG_BAD_COMMAND = 2'd3;
endpackage
