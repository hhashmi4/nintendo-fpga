`timescale 1ns/1ps

// Compact Phase 4E-C renderer for the 128x480 Developer Mode side panel.
// Every displayed value comes from the Phase 4E-A frame-stable video-domain
// snapshot bank. There is deliberately no NES pixel or live-core input. RGB
// is registered so the character/glyph tree has one full pixel-clock period.
module nes_debug_panel_renderer #(
    parameter int unsigned STALE_FRAME_LIMIT = 4
) (
    input  logic                                        pixel_clk,
    input  logic                                        reset,
    input  logic                                        snapshot_valid,
    input  logic                                        snapshot_update,
    input  nes_debug_snapshot_pkg::nes_debug_snapshot_t snapshot,
    input  logic                                        frame_start,
    input  logic [9:0]                                  scan_x,
    input  logic [9:0]                                  scan_y,
    input  logic                                        active_video,
    output logic                                        snapshot_stale,
    output logic [7:0]                                  red,
    output logic [7:0]                                  green,
    output logic [7:0]                                  blue
);
    import debug_font_pkg::*;

    localparam logic [23:0] COLOR_BACKGROUND = 24'h081020;
    localparam logic [23:0] COLOR_HEADER_BG  = 24'h102844;
    localparam logic [23:0] COLOR_TEXT       = 24'hd0e0e8;
    localparam logic [23:0] COLOR_HEADING    = 24'h50e8f0;
    localparam logic [23:0] COLOR_SECTION    = 24'hf0d050;
    localparam logic [23:0] COLOR_GOOD       = 24'h60f080;
    localparam logic [23:0] COLOR_BAD        = 24'hff5060;
    localparam logic [23:0] COLOR_BORDER     = 24'h287090;

    localparam logic [5:0] WORD_DEV_MODE = 6'd0;
    localparam logic [5:0] WORD_VALID    = 6'd1;
    localparam logic [5:0] WORD_INVALID  = 6'd2;
    localparam logic [5:0] WORD_STALE    = 6'd3;
    localparam logic [5:0] WORD_CPU      = 6'd4;
    localparam logic [5:0] WORD_PPU      = 6'd5;
    localparam logic [5:0] WORD_CART     = 6'd6;
    localparam logic [5:0] WORD_PAD1     = 6'd7;
    localparam logic [5:0] WORD_DMA      = 6'd8;
    localparam logic [5:0] WORD_SYSTEM   = 6'd9;
    localparam logic [5:0] WORD_RUN      = 6'd10;
    localparam logic [5:0] WORD_STALL    = 6'd11;
    localparam logic [5:0] WORD_ACTIVE   = 6'd12;
    localparam logic [5:0] WORD_IDLE     = 6'd13;
    localparam logic [5:0] WORD_NONE     = 6'd14;

    logic [7:0] stale_frame_count;
    logic [7:0] display_character;
    logic [5:0] glyph_row;
    logic [23:0] foreground_color;
    logic [23:0] panel_color;
    logic [3:0] cell_column;
    logic [4:0] cell_row;
    logic [2:0] glyph_column;
    logic [2:0] glyph_row_index;
    logic inside_panel;
    logic separator_pixel;
    logic [6:0] panel_x;

    function automatic logic [7:0] word_character(
        input logic [5:0] word,
        input logic [4:0] index
    );
        logic [63:0] text;
        logic [4:0] length;
        begin
            text = '0;
            length = 5'd0;
            case (word)
                WORD_DEV_MODE: begin text = "DEV MODE"; length = 5'd8; end
                WORD_VALID:    begin text = "VALID";    length = 5'd5; end
                WORD_INVALID:  begin text = "INVALID";  length = 5'd7; end
                WORD_STALE:    begin text = "STALE";    length = 5'd5; end
                WORD_CPU:      begin text = "CPU";      length = 5'd3; end
                WORD_PPU:      begin text = "PPU";      length = 5'd3; end
                WORD_CART:     begin text = "CART";     length = 5'd4; end
                WORD_PAD1:     begin text = "PAD1";     length = 5'd4; end
                WORD_DMA:      begin text = "DMA";      length = 5'd3; end
                WORD_SYSTEM:   begin text = "SYSTEM";   length = 5'd6; end
                WORD_RUN:      begin text = "RUN";      length = 5'd3; end
                WORD_STALL:    begin text = "STALL";    length = 5'd5; end
                WORD_ACTIVE:   begin text = "ACTIVE";   length = 5'd6; end
                WORD_IDLE:     begin text = "IDLE";     length = 5'd4; end
                WORD_NONE:     begin text = "NONE";     length = 5'd4; end
                default: begin text = '0; length = 5'd0; end
            endcase
            if (index < length)
                word_character = text[((length - index) * 8) - 1 -: 8];
            else
                word_character = 8'h20;
        end
    endfunction

    function automatic logic [7:0] value_hex_character(
        input logic [31:0] value,
        input logic [3:0] digits,
        input logic [4:0] index
    );
        /* verilator lint_off WIDTHEXPAND */
        value_hex_character = debug_hex_char(
            value[((digits - index) * 4) - 1 -: 4]
        );
        /* verilator lint_on WIDTHEXPAND */
    endfunction

    function automatic logic [7:0] owner_character(
        input logic [1:0] owner,
        input logic [4:0] index
    );
        case (owner)
            2'd1: owner_character = word_character(WORD_CPU, index);
            2'd2: owner_character = word_character(WORD_DMA, index);
            default: owner_character = word_character(WORD_NONE, index);
        endcase
    endfunction

    function automatic logic [7:0] pad_character(
        input logic [7:0] buttons,
        input logic [2:0] index
    );
        logic [7:0] label_character;
        begin
            case (index)
                3'd0: label_character = 8'h41; // A
                3'd1: label_character = 8'h42; // B
                3'd2: label_character = 8'h53; // Select
                3'd3: label_character = 8'h54; // sTart
                3'd4: label_character = 8'h55; // Up
                3'd5: label_character = 8'h44; // Down
                3'd6: label_character = 8'h4c; // Left
                default: label_character = 8'h52; // Right
            endcase
            pad_character = buttons[index] ? label_character : 8'h2d;
        end
    endfunction

    always_ff @(posedge pixel_clk) begin
        if (reset || !snapshot_valid) begin
            stale_frame_count <= 8'd0;
            snapshot_stale <= 1'b0;
        end else if (snapshot_update) begin
            stale_frame_count <= 8'd0;
            snapshot_stale <= 1'b0;
        end else if (frame_start) begin
            if (stale_frame_count < STALE_FRAME_LIMIT[7:0])
                stale_frame_count <= stale_frame_count + 8'd1;
            if ((stale_frame_count + 8'd1) >= STALE_FRAME_LIMIT[7:0])
                snapshot_stale <= 1'b1;
        end
    end

    always_comb begin
        inside_panel = active_video && (scan_x >= 10'd512) &&
                       (scan_x < 10'd640) && (scan_y < 10'd480);
        panel_x = scan_x[6:0];
        cell_column = panel_x[6:3];
        cell_row = scan_y[8:4];
        glyph_column = panel_x[2:0];
        glyph_row_index = scan_y[3:1];

        display_character = 8'h20;
        foreground_color = COLOR_TEXT;

        if (inside_panel) begin
            case (cell_row)
                5'd0: begin
                    foreground_color = COLOR_HEADING;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd9))
                        display_character = word_character(
                            WORD_DEV_MODE, cell_column - 4'd1);
                end
                5'd1: begin
                    if (!snapshot_valid && (cell_column >= 4'd1) &&
                        (cell_column < 4'd8)) begin
                        display_character = word_character(
                            WORD_INVALID, cell_column - 4'd1);
                        foreground_color = COLOR_BAD;
                    end else if (snapshot_stale &&
                                 (cell_column >= 4'd1) &&
                                 (cell_column < 4'd6)) begin
                        display_character = word_character(
                            WORD_STALE, cell_column - 4'd1);
                        foreground_color = COLOR_BAD;
                    end else if (snapshot_valid &&
                                 (cell_column >= 4'd1) &&
                                 (cell_column < 4'd6)) begin
                        display_character = word_character(
                            WORD_VALID, cell_column - 4'd1);
                        foreground_color = COLOR_GOOD;
                    end
                end
                5'd2: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd4))
                        display_character = word_character(
                            WORD_CPU, cell_column - 4'd1);
                end
                5'd3: begin
                    if (cell_column == 4'd1) display_character = 8'h50;
                    else if (cell_column == 4'd2) display_character = 8'h43;
                    else if ((cell_column >= 4'd4) && (cell_column < 4'd8))
                        display_character = value_hex_character(
                            {16'h0, snapshot.cpu.pc}, 4'd4,
                            cell_column - 4'd4);
                end
                5'd4: begin
                    if (cell_column == 4'd1) display_character = 8'h41;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd5))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.a}, 4'd2,
                            cell_column - 4'd3);
                    else if (cell_column == 4'd6) display_character = 8'h58;
                    else if ((cell_column >= 4'd8) && (cell_column < 4'd10))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.x}, 4'd2,
                            cell_column - 4'd8);
                    else if (cell_column == 4'd11) display_character = 8'h59;
                    else if ((cell_column >= 4'd13) && (cell_column < 4'd15))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.y}, 4'd2,
                            cell_column - 4'd13);
                end
                5'd5: begin
                    if (cell_column == 4'd1) display_character = 8'h53;
                    else if (cell_column == 4'd2) display_character = 8'h50;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd5))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.sp}, 4'd2,
                            cell_column - 4'd3);
                    else if (cell_column == 4'd6) display_character = 8'h50;
                    else if ((cell_column >= 4'd7) && (cell_column < 4'd9))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.status}, 4'd2,
                            cell_column - 4'd7);
                    else if (cell_column == 4'd10) display_character = 8'h4f;
                    else if (cell_column == 4'd11) display_character = 8'h50;
                    else if ((cell_column >= 4'd12) && (cell_column < 4'd14))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.opcode}, 4'd2,
                            cell_column - 4'd12);
                end
                5'd6: begin
                    if (snapshot.cpu.stalled && (cell_column >= 4'd1) &&
                        (cell_column < 4'd6)) begin
                        display_character = word_character(
                            WORD_STALL, cell_column - 4'd1);
                        foreground_color = COLOR_BAD;
                    end else if (!snapshot.cpu.stalled &&
                                 (cell_column >= 4'd1) &&
                                 (cell_column < 4'd4)) begin
                        display_character = word_character(
                            WORD_RUN, cell_column - 4'd1);
                        foreground_color = COLOR_GOOD;
                    end else if ((cell_column >= 4'd7) &&
                                 (cell_column < 4'd11))
                        display_character = owner_character(
                            snapshot.cpu.bus_owner, cell_column - 4'd7);
                end
                5'd8: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd4))
                        display_character = word_character(
                            WORD_PPU, cell_column - 4'd1);
                end
                5'd9: begin
                    if (cell_column == 4'd1) display_character = 8'h53;
                    else if (cell_column == 4'd2) display_character = 8'h4c;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd6))
                        display_character = value_hex_character(
                            {23'h0, snapshot.ppu.scanline}, 4'd3,
                            cell_column - 4'd3);
                    else if (cell_column == 4'd7) display_character = 8'h44;
                    else if (cell_column == 4'd8) display_character = 8'h54;
                    else if ((cell_column >= 4'd9) && (cell_column < 4'd12))
                        display_character = value_hex_character(
                            {23'h0, snapshot.ppu.dot}, 4'd3,
                            cell_column - 4'd9);
                end
                5'd10: begin
                    if (cell_column == 4'd1) display_character = 8'h43;
                    else if ((cell_column >= 4'd2) && (cell_column < 4'd4))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.ctrl}, 4'd2,
                            cell_column - 4'd2);
                    else if (cell_column == 4'd5) display_character = 8'h4d;
                    else if ((cell_column >= 4'd6) && (cell_column < 4'd8))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.mask}, 4'd2,
                            cell_column - 4'd6);
                    else if (cell_column == 4'd9) display_character = 8'h53;
                    else if ((cell_column >= 4'd10) && (cell_column < 4'd12))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.status}, 4'd2,
                            cell_column - 4'd10);
                end
                5'd11: begin
                    if (cell_column == 4'd1) display_character = 8'h4e;
                    else if (cell_column == 4'd2)
                        display_character = debug_bit_char(snapshot.ppu.nmi_level);
                    else if (cell_column == 4'd4) display_character = 8'h56;
                    else if (cell_column == 4'd5)
                        display_character = debug_bit_char(snapshot.ppu.vblank);
                    else if (cell_column == 4'd7) display_character = 8'h5a;
                    else if (cell_column == 4'd8)
                        display_character = debug_bit_char(
                            snapshot.ppu.sprite_zero_hit);
                end
                5'd13: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd5))
                        display_character = word_character(
                            WORD_CART, cell_column - 4'd1);
                end
                5'd14: begin
                    if (cell_column == 4'd1) display_character = 8'h4d;
                    else if (cell_column == 4'd2) display_character = 8'h41;
                    else if (cell_column == 4'd3) display_character = 8'h50;
                    else if ((cell_column >= 4'd4) && (cell_column < 4'd6))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cartridge.mapper_number}, 4'd2,
                            cell_column - 4'd4);
                    else if (cell_column == 4'd7) display_character = 8'h4e;
                    else if (cell_column == 4'd8)
                        display_character = snapshot.cartridge.nrom_256 ?
                                            8'h32 : 8'h31;
                    else if (cell_column == 4'd9)
                        display_character = snapshot.cartridge.nrom_256 ?
                                            8'h35 : 8'h32;
                    else if (cell_column == 4'd10)
                        display_character = snapshot.cartridge.nrom_256 ?
                                            8'h36 : 8'h38;
                end
                5'd15: begin
                    if (cell_column == 4'd1) display_character = 8'h50;
                    else if (cell_column == 4'd2) display_character = 8'h52;
                    else if (cell_column == 4'd3) display_character = 8'h47;
                    else if ((cell_column >= 4'd4) && (cell_column < 4'd8))
                        display_character = value_hex_character(
                            {17'h0, snapshot.cartridge.prg_address}, 4'd4,
                            cell_column - 4'd4);
                end
                5'd16: begin
                    if (cell_column == 4'd1) display_character = 8'h43;
                    else if (cell_column == 4'd2) display_character = 8'h48;
                    else if (cell_column == 4'd3) display_character = 8'h52;
                    else if ((cell_column >= 4'd4) && (cell_column < 4'd8))
                        display_character = value_hex_character(
                            {19'h0, snapshot.cartridge.chr_address}, 4'd4,
                            cell_column - 4'd4);
                    else if (cell_column == 4'd9) display_character = 8'h4d;
                    else if (cell_column == 4'd10) display_character = 8'h49;
                    else if (cell_column == 4'd11) display_character = 8'h52;
                    else if (cell_column == 4'd12)
                        display_character =
                            (snapshot.cartridge.mirroring == 2'd1) ?
                            8'h48 : 8'h56;
                end
                5'd18: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd5))
                        display_character = word_character(
                            WORD_PAD1, cell_column - 4'd1);
                end
                5'd19: begin
                    if ((cell_column >= 4'd1) && (cell_column < 4'd9))
                        display_character = pad_character(
                            snapshot.controller.live1,
                            3'(cell_column - 4'd1));
                end
                5'd21: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd4))
                        display_character = word_character(
                            WORD_DMA, cell_column - 4'd1);
                    else if (snapshot.dma.active &&
                             (cell_column >= 4'd5) &&
                             (cell_column < 4'd11)) begin
                        display_character = word_character(
                            WORD_ACTIVE, cell_column - 4'd5);
                        foreground_color = COLOR_BAD;
                    end else if (!snapshot.dma.active &&
                                 (cell_column >= 4'd5) &&
                                 (cell_column < 4'd9)) begin
                        display_character = word_character(
                            WORD_IDLE, cell_column - 4'd5);
                        foreground_color = COLOR_GOOD;
                    end
                end
                5'd22: begin
                    if (cell_column == 4'd1) display_character = 8'h50;
                    else if (cell_column == 4'd2) display_character = 8'h47;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd5))
                        display_character = value_hex_character(
                            {24'h0, snapshot.dma.source_page}, 4'd2,
                            cell_column - 4'd3);
                    else if (cell_column == 4'd6) display_character = 8'h49;
                    else if (cell_column == 4'd7) display_character = 8'h58;
                    else if ((cell_column >= 4'd8) && (cell_column < 4'd10))
                        display_character = value_hex_character(
                            {24'h0, snapshot.dma.byte_index}, 4'd2,
                            cell_column - 4'd8);
                end
                5'd23: begin
                    if (cell_column == 4'd1) display_character = 8'h43;
                    else if (cell_column == 4'd2) display_character = 8'h54;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd11))
                        display_character = value_hex_character(
                            snapshot.system.dma_count, 4'd8,
                            cell_column - 4'd3);
                end
                5'd25: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd7))
                        display_character = word_character(
                            WORD_SYSTEM, cell_column - 4'd1);
                end
                5'd26: begin
                    if (cell_column == 4'd1) display_character = 8'h46;
                    else if (cell_column == 4'd2) display_character = 8'h52;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd11))
                        display_character = value_hex_character(
                            snapshot.system.source_frame_number, 4'd8,
                            cell_column - 4'd3);
                end
                5'd27: begin
                    if (cell_column == 4'd1) display_character = 8'h49;
                    else if (cell_column == 4'd2) display_character = 8'h44;
                    else if ((cell_column >= 4'd3) && (cell_column < 4'd11))
                        display_character = value_hex_character(
                            snapshot.system.snapshot_id, 4'd8,
                            cell_column - 4'd3);
                end
                5'd28: begin
                    if (cell_column == 4'd1) display_character = 8'h4e;
                    else if (cell_column == 4'd2) display_character = 8'h4d;
                    else if (cell_column == 4'd3) display_character = 8'h49;
                    else if ((cell_column >= 4'd4) && (cell_column < 4'd12))
                        display_character = value_hex_character(
                            snapshot.system.nmi_count, 4'd8,
                            cell_column - 4'd4);
                end
                5'd29: begin
                    if (cell_column == 4'd1) display_character = 8'h44;
                    else if (cell_column == 4'd2) display_character = 8'h4d;
                    else if (cell_column == 4'd3) display_character = 8'h41;
                    else if ((cell_column >= 4'd4) && (cell_column < 4'd12))
                        display_character = value_hex_character(
                            snapshot.system.dma_count, 4'd8,
                            cell_column - 4'd4);
                end
                default: display_character = 8'h20;
            endcase
        end

        glyph_row = debug_font_row(display_character, glyph_row_index);
        separator_pixel = (scan_y == 10'd32) || (scan_y == 10'd120) ||
                          (scan_y == 10'd200) || (scan_y == 10'd280) ||
                          (scan_y == 10'd328) || (scan_y == 10'd392) ||
                          (scan_y == 10'd479);
        panel_color = (scan_y < 10'd32) ? COLOR_HEADER_BG : COLOR_BACKGROUND;
        if (inside_panel && ((scan_x == 10'd512) || (scan_x == 10'd639) ||
                             separator_pixel))
            panel_color = COLOR_BORDER;
        if (inside_panel && (glyph_column < 3'd6) &&
            glyph_row[3'd5 - glyph_column])
            panel_color = foreground_color;
        if (!inside_panel)
            panel_color = 24'h000000;

    end

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            red <= 8'h00;
            green <= 8'h00;
            blue <= 8'h00;
        end else begin
            red <= panel_color[23:16];
            green <= panel_color[15:8];
            blue <= panel_color[7:0];
        end
    end
endmodule
