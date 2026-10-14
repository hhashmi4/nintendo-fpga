`timescale 1ns/1ps

// 640x480 logical canvas. Reuses the debugger's 6x8 font at 2x size;
// registers RGB with the existing scanout's early render coordinates.
module nes_console_renderer (
    input logic pixel_clk, reset,
    input logic [9:0] x, y,
    input logic active,
    input logic [31:0] status,
    input logic [7:0] buttons,
    input logic held_reset,
    output logic [23:0] rgb
);
    import debug_font_pkg::*;
    logic [319:0] text_line;
    logic [7:0] character;
    logic [5:0] glyph;
    logic [9:0] local_x, local_y;
    logic [5:0] column;
    logic [3:0] row;
    logic [23:0] next_rgb;
    always_comb begin
        local_x = x - 10'd32;
        local_y = y - 10'd32;
        column = local_x[9:4];
        row = local_y[8:5];
        text_line = {40{8'h20}};
        case (row)
            4'd0: text_line = "NINTENDO FPGA                           ";
            4'd1: text_line = "CONSOLE SYSTEM                          ";
            4'd3: text_line = "STATE: INITIALIZING                     ";
            4'd5: text_line = "VIDEO: SYSTEM                           ";
            4'd6: text_line = "GAME READY: 0   RUNTIME: 0              ";
            4'd7: text_line = "LOADER: 0       ERROR: 0                ";
            4'd8: text_line = "INPUT OWNER: 0 BUTTONS: 00              ";
            4'd9: text_line = "NES RESET: 1   EPOCH: 0000              ";
            4'd11: text_line = "START PLAY / SELECT DEV                 ";
            4'd12: text_line = "B - RETURN FROM DEVELOPER               ";
            default: text_line = {40{8'h20}};
        endcase
        if (row == 3) begin
            case (status[3:0])
                4'd0: text_line = "STATE: INITIALIZING                     ";
                4'd1: text_line = "STATE: MENU READY                       ";
                4'd2: text_line = "STATE: LOADING                          ";
                4'd3: text_line = "STATE: WAITING FOR GAME FRAME           ";
                4'd4: text_line = "STATE: GAME ACTIVE                      ";
                4'd5: text_line = "STATE: RETURNING TO MENU                ";
                4'd6: text_line = "STATE: RECOVERABLE ERROR                ";
                4'd7: text_line = "STATE: DEVELOPER MODE                   ";
                default: text_line = {40{8'h20}};
            endcase
        end
        if (row == 5) begin
            case (status[7:6])
                2'd0: text_line = "VIDEO: SYSTEM                           ";
                2'd1: text_line = "VIDEO: GAME                             ";
                2'd2: text_line = "VIDEO: DEVELOPER                        ";
                default: text_line = {40{8'h20}};
            endcase
        end
        if (row == 6) begin
            text_line[319-12*8 -: 8] = debug_bit_char(status[8]);
            text_line[319-25*8 -: 8] = debug_bit_char(status[9]);
        end
        if (row == 7) begin
            text_line[319-8*8 -: 8] = debug_hex_char({2'd0,status[11:10]});
            text_line[319-23*8 -: 8] = debug_hex_char(status[15:12]);
        end
        if (row == 8) begin
            text_line[319-13*8 -: 8] = debug_hex_char({2'd0,status[5:4]});
            text_line[319-24*8 -: 8] = debug_hex_char(buttons[7:4]);
            text_line[319-25*8 -: 8] = debug_hex_char(buttons[3:0]);
        end
        if (row == 9) begin
            text_line[319-11*8 -: 8] = debug_bit_char(held_reset);
            text_line[319-22*8 -: 8] = debug_hex_char(status[31:28]);
            text_line[319-23*8 -: 8] = debug_hex_char(status[27:24]);
            text_line[319-24*8 -: 8] = debug_hex_char(status[23:20]);
            text_line[319-25*8 -: 8] = debug_hex_char(status[19:16]);
        end
        character = column < 40 ? text_line[319-int'(column)*8 -: 8] : 8'h20;
        glyph = debug_font_row(character, local_y[3:1]);
        next_rgb = y < 96 ? 24'h382448 : 24'h242229;
        if (y >= 96 && y < 100) next_rgb = 24'hc43b46;
        if (x >= 32 && y >= 32 && y < 448 && local_y[4] == 0 &&
            local_x[3:1] < 6 && glyph[5-local_x[3:1]])
            next_rgb = 24'hece5d8;
        if (!active) next_rgb = 0;
    end
    logic unused_subpixels;
    assign unused_subpixels = ^{local_x[0], local_y[9], local_y[0]};
    always_ff @(posedge pixel_clk) begin
        if (reset) rgb <= 0;
        else rgb <= next_rgb;
    end
endmodule
