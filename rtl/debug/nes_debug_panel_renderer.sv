`timescale 1ns/1ps

// Compact Phase 4E-D page-aware renderer for the 128x480 Developer Mode panel.
// Every displayed value comes from the Phase 4E-A frame-stable video-domain
// snapshot bank. There is deliberately no NES pixel or live-core input. RGB
// is registered so the character/glyph tree has one full pixel-clock period.
module nes_debug_panel_renderer #(
    parameter int unsigned STALE_FRAME_LIMIT = 4,
    parameter logic [23:0] COLOR_BACKGROUND = 24'h081020,
    parameter logic [23:0] COLOR_HEADER_BG  = 24'h102844,
    parameter logic [23:0] COLOR_TEXT       = 24'hd0e0e8,
    parameter logic [23:0] COLOR_HEADING    = 24'h50e8f0,
    parameter logic [23:0] COLOR_SECTION    = 24'hf0d050,
    parameter logic [23:0] COLOR_GOOD       = 24'h60f080,
    parameter logic [23:0] COLOR_BAD        = 24'hff5060,
    parameter logic [23:0] COLOR_BORDER     = 24'h287090
) (
    input  logic                                        pixel_clk,
    input  logic                                        reset,
    input  logic                                        snapshot_valid,
    input  logic                                        snapshot_update,
    input  nes_debug_snapshot_pkg::nes_debug_snapshot_t snapshot,
    input  logic [2:0]                                  page_select,
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
    localparam logic [5:0] WORD_OVERVIEW = 6'd15;
    localparam logic [5:0] WORD_CPU_BUS  = 6'd16;
    localparam logic [5:0] WORD_PPU_CART = 6'd17;
    localparam logic [5:0] WORD_DMA_PAD  = 6'd18;

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
                WORD_OVERVIEW: begin text = "OVERVIEW"; length = 5'd8; end
                WORD_CPU_BUS:  begin text = "CPU/BUS";  length = 5'd7; end
                WORD_PPU_CART: begin text = "PPU/CART"; length = 5'd8; end
                WORD_DMA_PAD:  begin text = "DMA/PAD";  length = 5'd7; end
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

    function automatic logic [7:0] literal_character(
        input logic [127:0] text,
        input logic [4:0] length,
        input logic [3:0] index
    );
        begin
            if ({1'b0, index} < length)
                literal_character = text[((length - index) * 8) - 1 -: 8];
            else
                literal_character = 8'h20;
        end
    endfunction

    function automatic logic [7:0] target_character(
        input logic [15:0] address,
        input logic [3:0] index
    );
        begin
            if (address < 16'h2000)
                target_character = literal_character("RAM", 5'd3, index);
            else if (address < 16'h4000)
                target_character = literal_character("PPU", 5'd3, index);
            else if (address == 16'h4016)
                target_character = literal_character("PAD1", 5'd4, index);
            else if (address == 16'h4017)
                target_character = literal_character("PAD2", 5'd4, index);
            else if (address < 16'h4020)
                target_character = literal_character("IO", 5'd2, index);
            else
                target_character = literal_character("CART", 5'd4, index);
        end
    endfunction

    // Pages 1..4 share the same glyph, hex, color, and snapshot machinery as
    // the Overview page. This function only selects compact cell contents.
    function automatic logic [7:0] detail_page_character(
        input logic [2:0] page,
        input logic [4:0] row,
        input logic [3:0] column
    );
        logic [7:0] result;
        begin
            result = 8'h20;

            if (row == 5'd0) begin
                if ((column >= 4'd1) && (column < 4'd9)) begin
                    case (page)
                        3'd1: result = word_character(WORD_CPU_BUS,
                                                     column - 4'd1);
                        3'd2: result = word_character(WORD_PPU_CART,
                                                     column - 4'd1);
                        3'd3: result = word_character(WORD_DMA_PAD,
                                                     column - 4'd1);
                        default: result = word_character(WORD_SYSTEM,
                                                        column - 4'd1);
                    endcase
                end else if (column == 4'd12) begin
                    result = debug_hex_char({1'b0, page} + 4'd1);
                end else if (column == 4'd13) begin
                    result = 8'h2f;
                end else if (column == 4'd14) begin
                    result = 8'h35;
                end
            end else if (row == 5'd1) begin
                if (!snapshot_valid && (column >= 4'd1) &&
                    (column < 4'd8))
                    result = word_character(WORD_INVALID, column - 4'd1);
                else if (snapshot_stale && (column >= 4'd1) &&
                         (column < 4'd6))
                    result = word_character(WORD_STALE, column - 4'd1);
                else if (snapshot_valid && (column >= 4'd1) &&
                         (column < 4'd6))
                    result = word_character(WORD_VALID, column - 4'd1);
            end else begin
                case (page)
                    3'd1: begin : cpu_bus_page
                        case (row)
                            5'd2: if ((column >= 4'd1) && (column < 4'd8))
                                result = word_character(WORD_CPU_BUS,
                                                        column - 4'd1);
                            5'd3: begin
                                if (column < 4'd3)
                                    result = literal_character("PC", 5'd2,
                                                               column - 4'd1);
                                if ((column >= 4'd4) && (column < 4'd8))
                                    result = value_hex_character(
                                        {16'h0, snapshot.cpu.pc}, 4'd4,
                                        column - 4'd4);
                            end
                            5'd4: begin
                                if (column == 4'd1) result = 8'h41;
                                else if ((column >= 4'd3) && (column < 4'd5))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.a}, 4'd2,
                                        column - 4'd3);
                                else if (column == 4'd6) result = 8'h58;
                                else if ((column >= 4'd8) && (column < 4'd10))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.x}, 4'd2,
                                        column - 4'd8);
                                else if (column == 4'd11) result = 8'h59;
                                else if ((column >= 4'd13) && (column < 4'd15))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.y}, 4'd2,
                                        column - 4'd13);
                            end
                            5'd5: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("SP", 5'd2,
                                                               column - 4'd1);
                                else if ((column >= 4'd4) && (column < 4'd6))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.sp}, 4'd2,
                                        column - 4'd4);
                                else if (column == 4'd7) result = 8'h50;
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.status}, 4'd2,
                                        column - 4'd9);
                                else if ((column >= 4'd12) && (column < 4'd14))
                                    result = literal_character("OP", 5'd2,
                                                               column - 4'd12);
                                else if (column >= 4'd14)
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.opcode}, 4'd2,
                                        column - 4'd14);
                            end
                            5'd7: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("ADDR", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd6) && (column < 4'd10))
                                    result = value_hex_character(
                                        {16'h0, snapshot.cpu.address}, 4'd4,
                                        column - 4'd6);
                            end
                            5'd8: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("RD", 5'd2,
                                                               column - 4'd1);
                                else if ((column >= 4'd4) && (column < 4'd6))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.read_data}, 4'd2,
                                        column - 4'd4);
                                else if ((column >= 4'd8) && (column < 4'd10))
                                    result = literal_character("WR", 5'd2,
                                                               column - 4'd8);
                                else if ((column >= 4'd11) && (column < 4'd13))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cpu.write_data}, 4'd2,
                                        column - 4'd11);
                            end
                            5'd9: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("RW", 5'd2,
                                                               column - 4'd1);
                                else if (column == 4'd4)
                                    result = snapshot.cpu.write ? 8'h57 :
                                             snapshot.cpu.read ? 8'h52 : 8'h49;
                                else if (column == 4'd7) result = 8'h56;
                                else if (column == 4'd8)
                                    result = debug_bit_char(snapshot.cpu.bus_valid);
                            end
                            5'd10: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = snapshot.cpu.stalled ?
                                        word_character(WORD_STALL,
                                                       column - 4'd1) :
                                        word_character(WORD_RUN,
                                                       column - 4'd1);
                            end
                            5'd12: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = literal_character("OWNER", 5'd5,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd11))
                                    result = owner_character(
                                        snapshot.cpu.bus_owner, column - 4'd7);
                            end
                            5'd13: begin
                                if ((column >= 4'd1) && (column < 4'd7))
                                    result = literal_character("TARGET", 5'd6,
                                                               column - 4'd1);
                                else if ((column >= 4'd8) && (column < 4'd12))
                                    result = target_character(
                                        snapshot.cpu.address, column - 4'd8);
                            end
                            5'd15: begin
                                if (column == 4'd1) result = 8'h52;
                                else if (column == 4'd2)
                                    result = debug_bit_char(snapshot.cpu.read);
                                else if (column == 4'd5) result = 8'h57;
                                else if (column == 4'd6)
                                    result = debug_bit_char(snapshot.cpu.write);
                                else if ((column >= 4'd9) && (column < 4'd12))
                                    result = owner_character(
                                        snapshot.dma.bus_owner, column - 4'd9);
                            end
                            default: result = 8'h20;
                        endcase
                    end
                    3'd2: begin : ppu_cart_page
                        case (row)
                            5'd2: if ((column >= 4'd1) && (column < 4'd4))
                                result = word_character(WORD_PPU,
                                                        column - 4'd1);
                            5'd3: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("SL", 5'd2,
                                                               column - 4'd1);
                                else if ((column >= 4'd4) && (column < 4'd7))
                                    result = value_hex_character(
                                        {23'h0, snapshot.ppu.scanline}, 4'd3,
                                        column - 4'd4);
                                else if ((column >= 4'd8) && (column < 4'd10))
                                    result = literal_character("DT", 5'd2,
                                                               column - 4'd8);
                                else if ((column >= 4'd11) && (column < 4'd14))
                                    result = value_hex_character(
                                        {23'h0, snapshot.ppu.dot}, 4'd3,
                                        column - 4'd11);
                            end
                            5'd4: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("PAR", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.ppu.frame_odd);
                                else if ((column >= 4'd8) && (column < 4'd10))
                                    result = literal_character("FR", 5'd2,
                                                               column - 4'd8);
                                else if ((column >= 4'd11) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.source_frame_number,
                                        4'd4, column - 4'd11);
                            end
                            5'd5: begin
                                if (column == 4'd1) result = 8'h43;
                                else if ((column >= 4'd3) && (column < 4'd5))
                                    result = value_hex_character(
                                        {24'h0, snapshot.ppu.ctrl}, 4'd2,
                                        column - 4'd3);
                                else if (column == 4'd7) result = 8'h4d;
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = value_hex_character(
                                        {24'h0, snapshot.ppu.mask}, 4'd2,
                                        column - 4'd9);
                            end
                            5'd6: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("STAT", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd6) && (column < 4'd8))
                                    result = value_hex_character(
                                        {24'h0, snapshot.ppu.status}, 4'd2,
                                        column - 4'd6);
                            end
                            5'd7: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("VB", 5'd2,
                                                               column - 4'd1);
                                else if (column == 4'd3)
                                    result = debug_bit_char(snapshot.ppu.vblank);
                                else if ((column >= 4'd5) && (column < 4'd8))
                                    result = literal_character("NMI", 5'd3,
                                                               column - 4'd5);
                                else if (column == 4'd8)
                                    result = debug_bit_char(snapshot.ppu.nmi_level);
                                else if ((column >= 4'd10) && (column < 4'd12))
                                    result = literal_character("EN", 5'd2,
                                                               column - 4'd10);
                                else if (column == 4'd12)
                                    result = debug_bit_char(snapshot.ppu.nmi_enabled);
                            end
                            5'd8: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("NE", 5'd2,
                                                               column - 4'd1);
                                else if (column == 4'd3)
                                    result = debug_bit_char(snapshot.ppu.nmi_event);
                                else if ((column >= 4'd5) && (column < 4'd8))
                                    result = literal_character("SUP", 5'd3,
                                                               column - 4'd5);
                                else if (column == 4'd8)
                                    result = debug_bit_char(snapshot.ppu.nmi_suppressed);
                                else if (column == 4'd10) result = 8'h5a;
                                else if (column == 4'd11)
                                    result = debug_bit_char(snapshot.ppu.sprite_zero_hit);
                                else if (column == 4'd13) result = 8'h4f;
                                else if (column == 4'd14)
                                    result = debug_bit_char(snapshot.ppu.sprite_overflow);
                            end
                            5'd9: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("PIX", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd7))
                                    result = value_hex_character(
                                        {26'h0, snapshot.ppu.pixel_color}, 4'd2,
                                        column - 4'd5);
                                else if ((column >= 4'd9) && (column < 4'd12))
                                    result = literal_character("PAL", 5'd3,
                                                               column - 4'd9);
                                else if (column >= 4'd12)
                                    result = value_hex_character(
                                        {18'h0, snapshot.ppu.palette_address},
                                        4'd4, column - 4'd12);
                            end
                            5'd10: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("XY", 5'd2,
                                                               column - 4'd1);
                                else if ((column >= 4'd4) && (column < 4'd6))
                                    result = value_hex_character(
                                        {24'h0, snapshot.ppu.pixel_x}, 4'd2,
                                        column - 4'd4);
                                else if ((column >= 4'd7) && (column < 4'd9))
                                    result = value_hex_character(
                                        {24'h0, snapshot.ppu.pixel_y}, 4'd2,
                                        column - 4'd7);
                                else if (column == 4'd11) result = 8'h56;
                                else if (column == 4'd12)
                                    result = debug_bit_char(snapshot.ppu.pixel_valid);
                            end
                            5'd12: if ((column >= 4'd1) && (column < 4'd5))
                                result = word_character(WORD_CART,
                                                        column - 4'd1);
                            5'd13: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("PRES", 5'd4,
                                                               column - 4'd1);
                                else if (column == 4'd6)
                                    result = debug_bit_char(snapshot.cartridge.present);
                                else if ((column >= 4'd8) && (column < 4'd11))
                                    result = literal_character("MAP", 5'd3,
                                                               column - 4'd8);
                                else if ((column >= 4'd12) && (column < 4'd14))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cartridge.mapper_number},
                                        4'd2, column - 4'd12);
                            end
                            5'd14: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("NROM", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd6) && (column < 4'd9))
                                    result = snapshot.cartridge.nrom_256 ?
                                        literal_character("256", 5'd3,
                                                          column - 4'd6) :
                                        literal_character("128", 5'd3,
                                                          column - 4'd6);
                            end
                            5'd16: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("PRG", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd9))
                                    result = value_hex_character(
                                        {17'h0, snapshot.cartridge.prg_address},
                                        4'd4, column - 4'd5);
                                else if (column == 4'd9) result = 8'h3a;
                                else if ((column >= 4'd10) && (column < 4'd12))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cartridge.prg_data},
                                        4'd2, column - 4'd10);
                            end
                            5'd17: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("CHR", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd9))
                                    result = value_hex_character(
                                        {19'h0, snapshot.cartridge.chr_address},
                                        4'd4, column - 4'd5);
                                else if (column == 4'd9) result = 8'h3a;
                                else if ((column >= 4'd10) && (column < 4'd12))
                                    result = value_hex_character(
                                        {24'h0, snapshot.cartridge.chr_data},
                                        4'd2, column - 4'd10);
                            end
                            5'd18: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("PR", 5'd2,
                                                               column - 4'd1);
                                else if (column == 4'd3)
                                    result = debug_bit_char(snapshot.cartridge.prg_read);
                                else if ((column >= 4'd5) && (column < 4'd7))
                                    result = literal_character("PW", 5'd2,
                                                               column - 4'd5);
                                else if (column == 4'd7)
                                    result = debug_bit_char(snapshot.cartridge.prg_write);
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = literal_character("CR", 5'd2,
                                                               column - 4'd9);
                                else if (column == 4'd11)
                                    result = debug_bit_char(snapshot.cartridge.chr_read);
                                else if ((column >= 4'd13) && (column < 4'd15))
                                    result = literal_character("CW", 5'd2,
                                                               column - 4'd13);
                                else if (column == 4'd15)
                                    result = debug_bit_char(snapshot.cartridge.chr_write);
                            end
                            5'd19: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("MIR", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = (snapshot.cartridge.mirroring == 2'd1) ?
                                             8'h48 : 8'h56;
                                else if ((column >= 4'd8) && (column < 4'd11))
                                    result = literal_character("CHR", 5'd3,
                                                               column - 4'd8);
                                else if ((column >= 4'd12) && (column < 4'd15))
                                    result = snapshot.cartridge.chr_is_ram ?
                                        literal_character("RAM", 5'd3,
                                                          column - 4'd12) :
                                        literal_character("ROM", 5'd3,
                                                          column - 4'd12);
                            end
                            default: result = 8'h20;
                        endcase
                    end
                    3'd3: begin : dma_pad_page
                        case (row)
                            5'd2: if ((column >= 4'd1) && (column < 4'd4))
                                result = word_character(WORD_DMA,
                                                        column - 4'd1);
                            5'd3: if ((column >= 4'd1) && (column < 4'd7))
                                result = snapshot.dma.active ?
                                    word_character(WORD_ACTIVE, column - 4'd1) :
                                    word_character(WORD_IDLE, column - 4'd1);
                            5'd4: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("PAGE", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd6) && (column < 4'd8))
                                    result = value_hex_character(
                                        {24'h0, snapshot.dma.source_page}, 4'd2,
                                        column - 4'd6);
                            end
                            5'd5: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("ADDR", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd6) && (column < 4'd10))
                                    result = value_hex_character(
                                        {16'h0, snapshot.dma.source_address},
                                        4'd4, column - 4'd6);
                            end
                            5'd6: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("DAT", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd7))
                                    result = value_hex_character(
                                        {24'h0, snapshot.dma.source_data}, 4'd2,
                                        column - 4'd5);
                                else if ((column >= 4'd9) && (column < 4'd12))
                                    result = literal_character("OAM", 5'd3,
                                                               column - 4'd9);
                                else if ((column >= 4'd13) && (column < 4'd15))
                                    result = value_hex_character(
                                        {24'h0, snapshot.dma.oam_data}, 4'd2,
                                        column - 4'd13);
                            end
                            5'd7: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("IDX", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd7))
                                    result = value_hex_character(
                                        {24'h0, snapshot.dma.byte_index}, 4'd2,
                                        column - 4'd5);
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = literal_character("PH", 5'd2,
                                                               column - 4'd9);
                                else if (column == 4'd12)
                                    result = debug_hex_char({1'b0,
                                                            snapshot.dma.phase});
                            end
                            5'd8: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("ODD", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.dma.started_odd);
                                else if ((column >= 4'd8) && (column < 4'd12))
                                    result = literal_character("SLOT", 5'd4,
                                                               column - 4'd8);
                                else if ((column >= 4'd12) && (column < 4'd15))
                                    result = value_hex_character(
                                        {22'h0, snapshot.dma.elapsed_slots},
                                        4'd3, column - 4'd12);
                            end
                            5'd9: begin
                                if ((column >= 4'd1) && (column < 4'd3))
                                    result = literal_character("RD", 5'd2,
                                                               column - 4'd1);
                                else if ((column >= 4'd4) && (column < 4'd7))
                                    result = value_hex_character(
                                        {23'h0, snapshot.dma.read_count}, 4'd3,
                                        column - 4'd4);
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = literal_character("WR", 5'd2,
                                                               column - 4'd9);
                                else if ((column >= 4'd12) && (column < 4'd15))
                                    result = value_hex_character(
                                        {23'h0, snapshot.dma.write_count}, 4'd3,
                                        column - 4'd12);
                            end
                            5'd10: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("EVT", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.dma.start_event);
                                else if (column == 4'd7)
                                    result = debug_bit_char(snapshot.dma.read_event);
                                else if (column == 4'd9)
                                    result = debug_bit_char(snapshot.dma.write_event);
                                else if (column == 4'd11)
                                    result = debug_bit_char(snapshot.dma.complete_event);
                            end
                            5'd11: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("CYC", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.dma.dummy_cycle);
                                else if (column == 4'd7)
                                    result = debug_bit_char(snapshot.dma.alignment_cycle);
                                else if ((column >= 4'd9) && (column < 4'd12))
                                    result = owner_character(
                                        snapshot.dma.bus_owner, column - 4'd9);
                            end
                            5'd12: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = literal_character("STALL", 5'd5,
                                                               column - 4'd1);
                                else if (column == 4'd7)
                                    result = debug_bit_char(snapshot.dma.cpu_stall);
                            end
                            5'd14: if ((column >= 4'd1) && (column < 4'd5))
                                result = word_character(WORD_PAD1,
                                                        column - 4'd1);
                            5'd15: if ((column >= 4'd1) && (column < 4'd9))
                                result = pad_character(snapshot.controller.live1,
                                                       3'(column - 4'd1));
                            5'd16: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("LAT", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd7))
                                    result = value_hex_character(
                                        {24'h0, snapshot.controller.shift1},
                                        4'd2, column - 4'd5);
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = literal_character("IX", 5'd2,
                                                               column - 4'd9);
                                else if (column == 4'd12)
                                    result = debug_hex_char(snapshot.controller.index1);
                            end
                            5'd17: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("SER", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.controller.serial1);
                                else if ((column >= 4'd8) && (column < 4'd12))
                                    result = literal_character("PAD2", 5'd4,
                                                               column - 4'd8);
                            end
                            5'd18: if ((column >= 4'd1) && (column < 4'd9))
                                result = pad_character(snapshot.controller.live2,
                                                       3'(column - 4'd1));
                            5'd19: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("LAT", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd7))
                                    result = value_hex_character(
                                        {24'h0, snapshot.controller.shift2},
                                        4'd2, column - 4'd5);
                                else if ((column >= 4'd9) && (column < 4'd11))
                                    result = literal_character("IX", 5'd2,
                                                               column - 4'd9);
                                else if (column == 4'd12)
                                    result = debug_hex_char(snapshot.controller.index2);
                            end
                            5'd20: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("SER", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.controller.serial2);
                                else if ((column >= 4'd8) && (column < 4'd11))
                                    result = literal_character("STB", 5'd3,
                                                               column - 4'd8);
                                else if (column == 4'd12)
                                    result = debug_bit_char(snapshot.controller.strobe);
                            end
                            5'd21: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("R16", 5'd3,
                                                               column - 4'd1);
                                else if (column == 4'd5)
                                    result = debug_bit_char(snapshot.controller.read_4016);
                                else if ((column >= 4'd8) && (column < 4'd11))
                                    result = literal_character("R17", 5'd3,
                                                               column - 4'd8);
                                else if (column == 4'd12)
                                    result = debug_bit_char(snapshot.controller.read_4017);
                            end
                            5'd22: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = literal_character("LATCH", 5'd5,
                                                               column - 4'd1);
                                else if (column == 4'd7)
                                    result = debug_bit_char(snapshot.controller.latch_event);
                            end
                            5'd24: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("POLL", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd6) && (column < 4'd14))
                                    result = value_hex_character(
                                        snapshot.system.controller_poll_count,
                                        4'd8, column - 4'd6);
                            end
                            5'd25: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("DMA", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd5) && (column < 4'd13))
                                    result = value_hex_character(
                                        snapshot.system.dma_count, 4'd8,
                                        column - 4'd5);
                            end
                            default: result = 8'h20;
                        endcase
                    end
                    default: begin : system_page
                        case (row)
                            5'd2: if ((column >= 4'd1) && (column < 4'd7))
                                result = word_character(WORD_SYSTEM,
                                                        column - 4'd1);
                            5'd3: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = literal_character("FRAME", 5'd5,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.source_frame_number,
                                        4'd8, column - 4'd7);
                            end
                            5'd4: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("SNAP", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.snapshot_id, 4'd8,
                                        column - 4'd7);
                            end
                            5'd5: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("NMI", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.nmi_count, 4'd8,
                                        column - 4'd7);
                            end
                            5'd6: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("DMA", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.dma_count, 4'd8,
                                        column - 4'd7);
                            end
                            5'd7: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("POLL", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.controller_poll_count,
                                        4'd8, column - 4'd7);
                            end
                            5'd8: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("CPU", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.cpu_slot_count, 4'd8,
                                        column - 4'd7);
                            end
                            5'd9: begin
                                if ((column >= 4'd1) && (column < 4'd4))
                                    result = literal_character("PPU", 5'd3,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.ppu_cycle_count, 4'd8,
                                        column - 4'd7);
                            end
                            5'd10: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = literal_character("PRG R", 5'd5,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.prg_read_count, 4'd8,
                                        column - 4'd7);
                            end
                            5'd11: begin
                                if ((column >= 4'd1) && (column < 4'd6))
                                    result = literal_character("CHR R", 5'd5,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.chr_read_count, 4'd8,
                                        column - 4'd7);
                            end
                            5'd12: begin
                                if ((column >= 4'd1) && (column < 4'd5))
                                    result = literal_character("MISS", 5'd4,
                                                               column - 4'd1);
                                else if ((column >= 4'd7) && (column < 4'd15))
                                    result = value_hex_character(
                                        snapshot.system.missed_capture_count,
                                        4'd8, column - 4'd7);
                            end
                            5'd15: begin
                                if ((column >= 4'd1) && (column < 4'd9))
                                    result = literal_character("SNAPSHOT", 5'd8,
                                                               column - 4'd1);
                            end
                            5'd16: begin
                                if (!snapshot_valid && (column >= 4'd1) &&
                                    (column < 4'd8))
                                    result = word_character(WORD_INVALID,
                                                            column - 4'd1);
                                else if (snapshot_stale && (column >= 4'd1) &&
                                         (column < 4'd6))
                                    result = word_character(WORD_STALE,
                                                            column - 4'd1);
                                else if (snapshot_valid && (column >= 4'd1) &&
                                         (column < 4'd6))
                                    result = word_character(WORD_VALID,
                                                            column - 4'd1);
                            end
                            default: result = 8'h20;
                        endcase
                    end
                endcase
            end
            detail_page_character = result;
        end
    endfunction

    function automatic logic detail_section_row(
        input logic [2:0] page,
        input logic [4:0] row
    );
        case (page)
            3'd1: detail_section_row = (row == 5'd2);
            3'd2: detail_section_row = (row == 5'd2) || (row == 5'd12);
            3'd3: detail_section_row = (row == 5'd2) || (row == 5'd14);
            default: detail_section_row = (row == 5'd2) || (row == 5'd15);
        endcase
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

    function automatic logic [7:0] debugger_state_character(input logic [3:0] index);
        case (snapshot.debugger.state)
            3'd0: debugger_state_character = literal_character("RUN", 5'd3, index);
            3'd1: debugger_state_character = literal_character("WAIT", 5'd4, index);
            3'd2: debugger_state_character = literal_character("PAUSE", 5'd5, index);
            3'd3: debugger_state_character = literal_character("STEP-I", 5'd6, index);
            3'd4: debugger_state_character = literal_character("STEP-F", 5'd6, index);
            default: debugger_state_character = 8'h3f;
        endcase
    endfunction

    function automatic logic [7:0] debugger_character(
        input logic [4:0] row, input logic [3:0] column);
        logic [127:0] label_text;
        logic [4:0] label_length;
        logic [15:0] value;
        begin
            label_text = '0;
            label_length = 5'd0;
            value = 16'd0;
            case (row)
                5'd0: begin label_text = "DEBUG"; label_length = 5'd5; end
                5'd2: begin label_text = "SEQ"; label_length = 5'd3; value = snapshot.debugger.sequence_id; end
                5'd3: begin label_text = "STEP-I"; label_length = 5'd6; value = snapshot.debugger.instruction_steps; end
                5'd4: begin label_text = "STEP-F"; label_length = 5'd6; value = snapshot.debugger.frame_steps; end
                5'd5: begin label_text = "PRE"; label_length = 5'd3; value = snapshot.debugger.pc_before; end
                5'd6: begin label_text = "POST"; label_length = 5'd4; value = snapshot.debugger.pc_after; end
                5'd7: begin label_text = "OVER"; label_length = 5'd4; value = snapshot.debugger.frame_overrun; end
                5'd8: begin label_text = "BOUND"; label_length = 5'd5; value = {13'd0, snapshot.debugger.boundary}; end
                default: begin end
            endcase
            debugger_character = 8'h20;
            if (column >= 4'd1 && {1'b0,column} <= label_length)
                debugger_character = literal_character(label_text, label_length, column - 4'd1);
            if (row >= 5'd2 && column >= 4'd9 && column < 4'd13)
                debugger_character = value_hex_character({16'd0,value},4'd4,{1'b0,column} - 5'd9);
            if (row == 5'd1) begin
                case (column)
                    4'd1: debugger_character = "S";
                    4'd2: debugger_character = debug_hex_char({1'b0,snapshot.debugger.state});
                    4'd4: debugger_character = "C";
                    4'd5: debugger_character = debug_hex_char({1'b0,snapshot.debugger.last_command});
                    4'd7: debugger_character = "R";
                    4'd8: debugger_character = debug_hex_char({2'd0,snapshot.debugger.result});
                    default: begin end
                endcase
            end
        end
    endfunction

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
            if (page_select == 3'd0) begin
              case (cell_row)
                5'd0: begin
                    foreground_color = COLOR_HEADING;
                    if ((cell_column >= 4'd1) && (cell_column < 4'd9))
                        display_character = word_character(
                            WORD_OVERVIEW, cell_column - 4'd1);
                    else if (cell_column == 4'd12)
                        display_character = 8'h31;
                    else if (cell_column == 4'd13)
                        display_character = 8'h2f;
                    else if (cell_column == 4'd14)
                        display_character = 8'h35;
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
            end else begin
                display_character = detail_page_character(
                    page_select, cell_row, cell_column);
                if (cell_row == 5'd0)
                    foreground_color = COLOR_HEADING;
                else if (cell_row == 5'd1)
                    foreground_color = (!snapshot_valid || snapshot_stale) ?
                                       COLOR_BAD : COLOR_GOOD;
                else if (detail_section_row(page_select, cell_row))
                    foreground_color = COLOR_SECTION;
                else if ((page_select == 3'd3) && (cell_row == 5'd3))
                    foreground_color = snapshot.dma.active ?
                                       COLOR_BAD : COLOR_GOOD;
                else if ((page_select == 3'd1) && (cell_row == 5'd10))
                    foreground_color = snapshot.cpu.stalled ?
                                       COLOR_BAD : COLOR_GOOD;
                else if ((page_select == 3'd4) && (cell_row == 5'd16))
                    foreground_color = (!snapshot_valid || snapshot_stale) ?
                                       COLOR_BAD : COLOR_GOOD;
            end
        end

        if (inside_panel && cell_row == 5'd1 && cell_column >= 4'd9) begin
            display_character = debugger_state_character(cell_column - 4'd9);
            foreground_color = COLOR_TEXT;
        end
        if (inside_panel &&
            ((page_select == 3'd1 && cell_row >= 5'd18 && cell_row <= 5'd26) ||
             (page_select == 3'd4 && cell_row >= 5'd19 && cell_row <= 5'd27))) begin
            display_character = debugger_character(
                cell_row - (page_select == 3'd1 ? 5'd18 : 5'd19), cell_column);
            foreground_color = cell_row == (page_select == 3'd1 ? 5'd18 : 5'd19) ?
                               COLOR_SECTION : COLOR_TEXT;
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
