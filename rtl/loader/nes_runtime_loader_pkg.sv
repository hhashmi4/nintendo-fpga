`timescale 1ns/1ps

package nes_runtime_loader_pkg;
    localparam integer LOADER_ADDRESS_BITS = 16;
    localparam logic [15:0] LOADER_PRG_LAST_ADDRESS = 16'h7fff;
    localparam logic [15:0] LOADER_CHR_LAST_ADDRESS = 16'h1fff;

    typedef enum logic [1:0] {
        LOADER_COMMAND_BEGIN    = 2'd0,
        LOADER_COMMAND_WRITE    = 2'd1,
        LOADER_COMMAND_COMMIT   = 2'd2,
        LOADER_COMMAND_RESERVED = 2'd3
    } loader_command_t;

    typedef enum logic [1:0] {
        LOADER_TARGET_NONE     = 2'd0,
        LOADER_TARGET_PRG      = 2'd1,
        LOADER_TARGET_CHR      = 2'd2,
        LOADER_TARGET_RESERVED = 2'd3
    } loader_target_t;

    typedef enum logic [1:0] {
        LOADER_STATE_IDLE    = 2'd0,
        LOADER_STATE_LOADING = 2'd1,
        LOADER_STATE_READY   = 2'd2,
        LOADER_STATE_ERROR   = 2'd3
    } loader_state_t;

    typedef enum logic [2:0] {
        LOADER_ERROR_NONE          = 3'd0,
        LOADER_ERROR_WRONG_STATE   = 3'd1,
        LOADER_ERROR_BEGIN_BUSY    = 3'd2,
        LOADER_ERROR_BAD_COMMAND   = 3'd3,
        LOADER_ERROR_BAD_TARGET    = 3'd4,
        LOADER_ERROR_BAD_ADDRESS   = 3'd5,
        LOADER_ERROR_EMPTY_LOAD    = 3'd6
    } loader_error_t;
endpackage
