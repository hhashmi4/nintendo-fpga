`timescale 1ns/1ps

package nes_runtime_loader_pkg;
    localparam integer LOADER_ADDRESS_BITS = 16;
    localparam logic [15:0] LOADER_PRG_NROM128_BYTES = 16'h4000;
    localparam logic [15:0] LOADER_PRG_NROM256_BYTES = 16'h8000;
    localparam logic [15:0] LOADER_CHR_ROM_BYTES = 16'h2000;
    localparam logic [15:0] LOADER_PRG_LAST_ADDRESS = 16'h7fff;
    localparam logic [15:0] LOADER_CHR_LAST_ADDRESS = 16'h1fff;

    localparam logic [1:0] LOADER_MIRROR_VERTICAL = 2'd0;
    localparam logic [1:0] LOADER_MIRROR_HORIZONTAL = 2'd1;

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

    typedef enum logic [3:0] {
        LOADER_ERROR_NONE               = 4'd0,
        LOADER_ERROR_WRONG_STATE        = 4'd1,
        LOADER_ERROR_BEGIN_BUSY         = 4'd2,
        LOADER_ERROR_BAD_COMMAND        = 4'd3,
        LOADER_ERROR_BAD_TARGET         = 4'd4,
        LOADER_ERROR_BAD_ADDRESS        = 4'd5,
        LOADER_ERROR_EMPTY_LOAD         = 4'd6,
        LOADER_ERROR_INVALID_MANIFEST   = 4'd7,
        LOADER_ERROR_UNSUPPORTED_MAPPER = 4'd8,
        LOADER_ERROR_UNSUPPORTED_PRG    = 4'd9,
        LOADER_ERROR_UNSUPPORTED_CHR    = 4'd10,
        LOADER_ERROR_UNEXPECTED_ADDRESS = 4'd11,
        LOADER_ERROR_PRG_INCOMPLETE     = 4'd12,
        LOADER_ERROR_CHR_INCOMPLETE     = 4'd13
    } loader_error_t;
endpackage
