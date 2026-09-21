`timescale 1ns/1ps

module nes_debug_renderer #(
    parameter int unsigned STALE_FRAME_LIMIT = 4
) (
    input  logic                                      pixel_clk,
    input  logic                                      reset,
    input  logic                                      developer_mode_enable,
    input  logic                                      snapshot_valid,
    input  logic                                      snapshot_update,
    input  nes_debug_snapshot_pkg::nes_debug_snapshot_t snapshot,
    input  logic                                      frame_start,
    input  logic [9:0]                                scan_x,
    input  logic [9:0]                                scan_y,
    input  logic                                      active_video,
    input  logic [7:0]                                normal_red,
    input  logic [7:0]                                normal_green,
    input  logic [7:0]                                normal_blue,
    output logic                                      snapshot_stale,
    output logic [7:0]                                red,
    output logic [7:0]                                green,
    output logic [7:0]                                blue
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

    localparam logic [6:0] WORD_FPGA_CONSOLE = 7'd0;
    localparam logic [6:0] WORD_DEVELOPER_MODE = 7'd1;
    localparam logic [6:0] WORD_SNAP = 7'd2;
    localparam logic [6:0] WORD_VALID = 7'd3;
    localparam logic [6:0] WORD_INVALID = 7'd4;
    localparam logic [6:0] WORD_STALE = 7'd5;
    localparam logic [6:0] WORD_CPU = 7'd6;
    localparam logic [6:0] WORD_PPU = 7'd7;
    localparam logic [6:0] WORD_CART = 7'd8;
    localparam logic [6:0] WORD_PRESENT = 7'd9;
    localparam logic [6:0] WORD_NROM = 7'd10;
    localparam logic [6:0] WORD_CTRL = 7'd11;
    localparam logic [6:0] WORD_MASK = 7'd12;
    localparam logic [6:0] WORD_STAT = 7'd13;
    localparam logic [6:0] WORD_PAD = 7'd14;
    localparam logic [6:0] WORD_SHIFT = 7'd15;
    localparam logic [6:0] WORD_DMA = 7'd16;
    localparam logic [6:0] WORD_ACTIVE = 7'd17;
    localparam logic [6:0] WORD_IDLE = 7'd18;
    localparam logic [6:0] WORD_SYSTEM = 7'd19;
    localparam logic [6:0] WORD_FRAME = 7'd20;
    localparam logic [6:0] WORD_POLL = 7'd21;
    localparam logic [6:0] WORD_READ_ONLY = 7'd22;
    localparam logic [6:0] WORD_NONE = 7'd23;
    localparam logic [6:0] WORD_RUN = 7'd24;
    localparam logic [6:0] WORD_STALL = 7'd25;
    localparam logic [6:0] WORD_ROM = 7'd26;
    localparam logic [6:0] WORD_RAM = 7'd27;

    logic [7:0] stale_frame_count;
    logic [7:0] display_character;
    logic [5:0] glyph_row;
    logic [23:0] foreground_color;
    logic [23:0] debug_color;
    logic [6:0] cell_column;
    logic [5:0] cell_row;
    logic [2:0] glyph_column;
    logic [2:0] glyph_row_index;
    logic inside_text_grid;
    logic [9:0] text_x;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [9:0] text_y;
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [7:0] word_character(
        input logic [6:0] word,
        input logic [6:0] index
    );
        logic [127:0] text;
        logic [6:0] length;
        begin
            text = '0;
            length = 7'd0;
            case (word)
                WORD_FPGA_CONSOLE:   begin text = "FPGA CONSOLE";    length = 7'd12; end
                WORD_DEVELOPER_MODE: begin text = "DEVELOPER MODE";  length = 7'd14; end
                WORD_SNAP:           begin text = "SNAP";            length = 7'd4;  end
                WORD_VALID:          begin text = "VALID";           length = 7'd5;  end
                WORD_INVALID:        begin text = "INVALID";         length = 7'd7;  end
                WORD_STALE:          begin text = "STALE";           length = 7'd5;  end
                WORD_CPU:            begin text = "CPU";             length = 7'd3;  end
                WORD_PPU:            begin text = "PPU";             length = 7'd3;  end
                WORD_CART:           begin text = "CART";            length = 7'd4;  end
                WORD_PRESENT:        begin text = "PRESENT";         length = 7'd7;  end
                WORD_NROM:           begin text = "NROM";            length = 7'd4;  end
                WORD_CTRL:           begin text = "CTRL";            length = 7'd4;  end
                WORD_MASK:           begin text = "MASK";            length = 7'd4;  end
                WORD_STAT:           begin text = "STAT";            length = 7'd4;  end
                WORD_PAD:            begin text = "CONTROLLER";      length = 7'd10; end
                WORD_SHIFT:          begin text = "SHIFT";           length = 7'd5;  end
                WORD_DMA:            begin text = "DMA";             length = 7'd3;  end
                WORD_ACTIVE:         begin text = "ACTIVE";          length = 7'd6;  end
                WORD_IDLE:           begin text = "IDLE";            length = 7'd4;  end
                WORD_SYSTEM:         begin text = "SYSTEM";          length = 7'd6;  end
                WORD_FRAME:          begin text = "FRAME";           length = 7'd5;  end
                WORD_POLL:           begin text = "POLL";            length = 7'd4;  end
                WORD_READ_ONLY:      begin text = "READ ONLY";       length = 7'd9;  end
                WORD_NONE:           begin text = "NONE";            length = 7'd4;  end
                WORD_RUN:            begin text = "RUN";             length = 7'd3;  end
                WORD_STALL:          begin text = "STALL";           length = 7'd5;  end
                WORD_ROM:            begin text = "ROM";             length = 7'd3;  end
                WORD_RAM:            begin text = "RAM";             length = 7'd3;  end
                default: begin text = '0; length = 7'd0; end
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
        input logic [6:0] index
    );
        /* verilator lint_off WIDTHEXPAND */
        value_hex_character = debug_hex_char(
            value[((digits - index) * 4) - 1 -: 4]
        );
        /* verilator lint_on WIDTHEXPAND */
    endfunction

    function automatic logic [7:0] bus_owner_character(
        input logic [1:0] owner,
        input logic [6:0] index
    );
        case (owner)
            2'd1: bus_owner_character = word_character(WORD_CPU, index);
            2'd2: bus_owner_character = word_character(WORD_DMA, index);
            default: bus_owner_character = word_character(WORD_NONE, index);
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
        inside_text_grid = active_video &&
                           (scan_x >= 10'd8) && (scan_x < 10'd632) &&
                           (scan_y >= 10'd8) && (scan_y < 10'd472);
        text_x = scan_x - 10'd8;
        text_y = scan_y - 10'd8;
        cell_column = text_x[9:3];
        cell_row = text_y[9:4];
        glyph_column = text_x[2:0];
        glyph_row_index = text_y[3:1];

        display_character = 8'h20;
        foreground_color = COLOR_TEXT;

        if (inside_text_grid) begin
            case (cell_row)
                6'd0: begin
                    foreground_color = COLOR_HEADING;
                    if ((cell_column >= 7'd1) && (cell_column < 7'd13))
                        display_character = word_character(
                            WORD_FPGA_CONSOLE, cell_column - 7'd1);
                    else if (cell_column == 7'd14)
                        display_character = 8'h2d;
                    else if ((cell_column >= 7'd16) && (cell_column < 7'd30))
                        display_character = word_character(
                            WORD_DEVELOPER_MODE, cell_column - 7'd16);
                end
                6'd1: begin
                    if ((cell_column >= 7'd1) && (cell_column < 7'd5))
                        display_character = word_character(
                            WORD_SNAP, cell_column - 7'd1);
                    else if (cell_column == 7'd5)
                        display_character = 8'h3d;
                    else if ((cell_column >= 7'd6) && (cell_column < 7'd14))
                        display_character = value_hex_character(
                            snapshot.system.snapshot_id, 4'd8,
                            cell_column - 7'd6);
                    else if (!snapshot_valid &&
                             (cell_column >= 7'd20) && (cell_column < 7'd27)) begin
                        display_character = word_character(
                            WORD_INVALID, cell_column - 7'd20);
                        foreground_color = COLOR_BAD;
                    end else if (snapshot_stale &&
                                 (cell_column >= 7'd20) && (cell_column < 7'd25)) begin
                        display_character = word_character(
                            WORD_STALE, cell_column - 7'd20);
                        foreground_color = COLOR_BAD;
                    end else if (snapshot_valid &&
                                 (cell_column >= 7'd20) && (cell_column < 7'd25)) begin
                        display_character = word_character(
                            WORD_VALID, cell_column - 7'd20);
                        foreground_color = COLOR_GOOD;
                    end
                end
                6'd3: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 7'd1) && (cell_column < 7'd4))
                        display_character = word_character(WORD_CPU, cell_column - 7'd1);
                    else if ((cell_column >= 7'd27) && (cell_column < 7'd30))
                        display_character = word_character(WORD_PPU, cell_column - 7'd27);
                    else if ((cell_column >= 7'd53) && (cell_column < 7'd57))
                        display_character = word_character(WORD_CART, cell_column - 7'd53);
                end
                6'd4: begin
                    if (cell_column == 7'd1) display_character = 8'h50;
                    else if (cell_column == 7'd2) display_character = 8'h43;
                    else if (cell_column == 7'd3) display_character = 8'h3d;
                    else if ((cell_column >= 7'd4) && (cell_column < 7'd8))
                        display_character = value_hex_character(
                            {16'h0000, snapshot.cpu.pc}, 4'd4, cell_column - 7'd4);
                    else if (cell_column == 7'd27) display_character = 8'h53;
                    else if (cell_column == 7'd28) display_character = 8'h4c;
                    else if (cell_column == 7'd29) display_character = 8'h3d;
                    else if ((cell_column >= 7'd30) && (cell_column < 7'd33))
                        display_character = value_hex_character(
                            {23'h0, snapshot.ppu.scanline}, 4'd3, cell_column - 7'd30);
                    else if ((cell_column >= 7'd53) && (cell_column < 7'd60))
                        display_character = word_character(WORD_PRESENT, cell_column - 7'd53);
                    else if (cell_column == 7'd60) display_character = 8'h3d;
                    else if (cell_column == 7'd61)
                        display_character = debug_bit_char(snapshot.cartridge.present);
                end
                6'd5: begin
                    if (cell_column == 7'd1) display_character = 8'h41;
                    else if (cell_column == 7'd2) display_character = 8'h3d;
                    else if ((cell_column >= 7'd3) && (cell_column < 7'd5))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.a}, 4'd2, cell_column - 7'd3);
                    else if (cell_column == 7'd7) display_character = 8'h58;
                    else if (cell_column == 7'd8) display_character = 8'h3d;
                    else if ((cell_column >= 7'd9) && (cell_column < 7'd11))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.x}, 4'd2, cell_column - 7'd9);
                    else if (cell_column == 7'd27) display_character = 8'h44;
                    else if (cell_column == 7'd28) display_character = 8'h4f;
                    else if (cell_column == 7'd29) display_character = 8'h54;
                    else if (cell_column == 7'd30) display_character = 8'h3d;
                    else if ((cell_column >= 7'd31) && (cell_column < 7'd34))
                        display_character = value_hex_character(
                            {23'h0, snapshot.ppu.dot}, 4'd3, cell_column - 7'd31);
                    else if (cell_column == 7'd53) display_character = 8'h4d;
                    else if (cell_column == 7'd54) display_character = 8'h41;
                    else if (cell_column == 7'd55) display_character = 8'h50;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd59))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cartridge.mapper_number}, 4'd2,
                            cell_column - 7'd57);
                end
                6'd6: begin
                    if (cell_column == 7'd1) display_character = 8'h59;
                    else if (cell_column == 7'd2) display_character = 8'h3d;
                    else if ((cell_column >= 7'd3) && (cell_column < 7'd5))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.y}, 4'd2, cell_column - 7'd3);
                    else if (cell_column == 7'd7) display_character = 8'h53;
                    else if (cell_column == 7'd8) display_character = 8'h50;
                    else if (cell_column == 7'd9) display_character = 8'h3d;
                    else if ((cell_column >= 7'd10) && (cell_column < 7'd12))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.sp}, 4'd2, cell_column - 7'd10);
                    else if ((cell_column >= 7'd27) && (cell_column < 7'd31))
                        display_character = word_character(WORD_CTRL, cell_column - 7'd27);
                    else if (cell_column == 7'd31) display_character = 8'h3d;
                    else if ((cell_column >= 7'd32) && (cell_column < 7'd34))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.ctrl}, 4'd2, cell_column - 7'd32);
                    else if ((cell_column >= 7'd53) && (cell_column < 7'd57))
                        display_character = word_character(WORD_NROM, cell_column - 7'd53);
                    else if (cell_column == 7'd57) display_character = 8'h3d;
                    else if (cell_column == 7'd58)
                        display_character = snapshot.cartridge.nrom_256 ? 8'h32 : 8'h31;
                    else if (cell_column == 7'd59)
                        display_character = snapshot.cartridge.nrom_256 ? 8'h35 : 8'h32;
                    else if (cell_column == 7'd60)
                        display_character = snapshot.cartridge.nrom_256 ? 8'h36 : 8'h38;
                end
                6'd7: begin
                    if (cell_column == 7'd1) display_character = 8'h50;
                    else if (cell_column == 7'd2) display_character = 8'h3d;
                    else if ((cell_column >= 7'd3) && (cell_column < 7'd5))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.status}, 4'd2, cell_column - 7'd3);
                    else if (cell_column == 7'd7) display_character = 8'h4f;
                    else if (cell_column == 7'd8) display_character = 8'h50;
                    else if (cell_column == 7'd9) display_character = 8'h3d;
                    else if ((cell_column >= 7'd10) && (cell_column < 7'd12))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.opcode}, 4'd2, cell_column - 7'd10);
                    else if ((cell_column >= 7'd27) && (cell_column < 7'd31))
                        display_character = word_character(WORD_MASK, cell_column - 7'd27);
                    else if (cell_column == 7'd31) display_character = 8'h3d;
                    else if ((cell_column >= 7'd32) && (cell_column < 7'd34))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.mask}, 4'd2, cell_column - 7'd32);
                    else if (cell_column == 7'd53) display_character = 8'h50;
                    else if (cell_column == 7'd54) display_character = 8'h52;
                    else if (cell_column == 7'd55) display_character = 8'h47;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd61))
                        display_character = value_hex_character(
                            {17'h0, snapshot.cartridge.prg_address}, 4'd4,
                            cell_column - 7'd57);
                    else if (cell_column == 7'd61) display_character = 8'h3a;
                    else if ((cell_column >= 7'd62) && (cell_column < 7'd64))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cartridge.prg_data}, 4'd2,
                            cell_column - 7'd62);
                end
                6'd8: begin
                    if ((cell_column >= 7'd1) && (cell_column < 7'd4)) begin
                        case (cell_column)
                            7'd1: display_character = 8'h41;
                            7'd2: display_character = 8'h44;
                            default: display_character = 8'h52;
                        endcase
                    end else if (cell_column == 7'd4) display_character = 8'h3d;
                    else if ((cell_column >= 7'd5) && (cell_column < 7'd9))
                        display_character = value_hex_character(
                            {16'h0, snapshot.cpu.address}, 4'd4, cell_column - 7'd5);
                    else if ((cell_column >= 7'd27) && (cell_column < 7'd31))
                        display_character = word_character(WORD_STAT, cell_column - 7'd27);
                    else if (cell_column == 7'd31) display_character = 8'h3d;
                    else if ((cell_column >= 7'd32) && (cell_column < 7'd34))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.status}, 4'd2, cell_column - 7'd32);
                    else if (cell_column == 7'd53) display_character = 8'h43;
                    else if (cell_column == 7'd54) display_character = 8'h48;
                    else if (cell_column == 7'd55) display_character = 8'h52;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd61))
                        display_character = value_hex_character(
                            {19'h0, snapshot.cartridge.chr_address}, 4'd4,
                            cell_column - 7'd57);
                    else if (cell_column == 7'd61) display_character = 8'h3a;
                    else if ((cell_column >= 7'd62) && (cell_column < 7'd64))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cartridge.chr_data}, 4'd2,
                            cell_column - 7'd62);
                end
                6'd9: begin
                    if (cell_column == 7'd1) display_character = 8'h52;
                    else if (cell_column == 7'd2) display_character = 8'h44;
                    else if (cell_column == 7'd3) display_character = 8'h3d;
                    else if ((cell_column >= 7'd4) && (cell_column < 7'd6))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.read_data}, 4'd2, cell_column - 7'd4);
                    else if (cell_column == 7'd8) display_character = 8'h57;
                    else if (cell_column == 7'd9) display_character = 8'h52;
                    else if (cell_column == 7'd10) display_character = 8'h3d;
                    else if ((cell_column >= 7'd11) && (cell_column < 7'd13))
                        display_character = value_hex_character(
                            {24'h0, snapshot.cpu.write_data}, 4'd2, cell_column - 7'd11);
                    else if (cell_column == 7'd27) display_character = 8'h56;
                    else if (cell_column == 7'd28) display_character = 8'h42;
                    else if (cell_column == 7'd29) display_character = 8'h3d;
                    else if (cell_column == 7'd30)
                        display_character = debug_bit_char(snapshot.ppu.vblank);
                    else if (cell_column == 7'd32) display_character = 8'h4e;
                    else if (cell_column == 7'd33) display_character = 8'h4d;
                    else if (cell_column == 7'd34) display_character = 8'h49;
                    else if (cell_column == 7'd35) display_character = 8'h3d;
                    else if (cell_column == 7'd36)
                        display_character = debug_bit_char(snapshot.ppu.nmi_level);
                    else if (cell_column == 7'd53) display_character = 8'h4d;
                    else if (cell_column == 7'd54) display_character = 8'h49;
                    else if (cell_column == 7'd55) display_character = 8'h52;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if (cell_column == 7'd57)
                        case (snapshot.cartridge.mirroring)
                            2'd0: display_character = 8'h56;
                            2'd1: display_character = 8'h48;
                            default: display_character = 8'h2d;
                        endcase
                end
                6'd10: begin
                    if (cell_column == 7'd1) display_character = 8'h42;
                    else if (cell_column == 7'd2) display_character = 8'h55;
                    else if (cell_column == 7'd3) display_character = 8'h53;
                    else if (cell_column == 7'd4) display_character = 8'h3d;
                    else if ((cell_column >= 7'd5) && (cell_column < 7'd9))
                        display_character = bus_owner_character(
                            snapshot.cpu.bus_owner, cell_column - 7'd5);
                    else if (cell_column == 7'd27) display_character = 8'h5a;
                    else if (cell_column == 7'd28) display_character = 8'h3d;
                    else if (cell_column == 7'd29)
                        display_character = debug_bit_char(snapshot.ppu.sprite_zero_hit);
                    else if (cell_column == 7'd31) display_character = 8'h4f;
                    else if (cell_column == 7'd32) display_character = 8'h56;
                    else if (cell_column == 7'd33) display_character = 8'h3d;
                    else if (cell_column == 7'd34)
                        display_character = debug_bit_char(snapshot.ppu.sprite_overflow);
                    else if (cell_column == 7'd53) display_character = 8'h43;
                    else if (cell_column == 7'd54) display_character = 8'h48;
                    else if (cell_column == 7'd55) display_character = 8'h52;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd60))
                        display_character = word_character(
                            snapshot.cartridge.chr_is_ram ? WORD_RAM : WORD_ROM,
                            cell_column - 7'd57);
                end
                6'd11: begin
                    if (cell_column == 7'd1) display_character = 8'h52;
                    else if (cell_column == 7'd2) display_character = 8'h57;
                    else if (cell_column == 7'd3) display_character = 8'h3d;
                    else if (cell_column == 7'd4)
                        display_character = !snapshot.cpu.bus_valid ? 8'h2d :
                                            snapshot.cpu.write ? 8'h57 :
                                            snapshot.cpu.read ? 8'h52 : 8'h49;
                    else if (cell_column == 7'd27) display_character = 8'h50;
                    else if (cell_column == 7'd28) display_character = 8'h49;
                    else if (cell_column == 7'd29) display_character = 8'h58;
                    else if (cell_column == 7'd30) display_character = 8'h3d;
                    else if ((cell_column >= 7'd31) && (cell_column < 7'd33))
                        display_character = value_hex_character(
                            {26'h0, snapshot.ppu.pixel_color}, 4'd2,
                            cell_column - 7'd31);
                    else if (cell_column == 7'd34) display_character = 8'h2f;
                    else if ((cell_column >= 7'd35) && (cell_column < 7'd37))
                        display_character = value_hex_character(
                            {24'h0, snapshot.ppu.palette_address[7:0]}, 4'd2,
                            cell_column - 7'd35);
                end
                6'd12: begin
                    if ((cell_column >= 7'd1) &&
                        (cell_column < (snapshot.cpu.stalled ? 7'd6 : 7'd4))) begin
                        display_character = word_character(
                            snapshot.cpu.stalled ? WORD_STALL : WORD_RUN,
                            cell_column - 7'd1);
                        foreground_color = snapshot.cpu.stalled ? COLOR_BAD : COLOR_GOOD;
                    end else if (cell_column == 7'd27) display_character = 8'h50;
                    else if (cell_column == 7'd28) display_character = 8'h41;
                    else if (cell_column == 7'd29) display_character = 8'h52;
                    else if (cell_column == 7'd30) display_character = 8'h3d;
                    else if (cell_column == 7'd31)
                        display_character = debug_bit_char(snapshot.ppu.frame_odd);
                end
                6'd16: begin
                    foreground_color = COLOR_SECTION;
                    if ((cell_column >= 7'd1) && (cell_column < 7'd11))
                        display_character = word_character(WORD_PAD, cell_column - 7'd1);
                    else if ((cell_column >= 7'd27) && (cell_column < 7'd30))
                        display_character = word_character(WORD_DMA, cell_column - 7'd27);
                    else if ((cell_column >= 7'd53) && (cell_column < 7'd59))
                        display_character = word_character(WORD_SYSTEM, cell_column - 7'd53);
                end
                6'd17, 6'd18: begin
                    if (cell_column == 7'd1) display_character = 8'h50;
                    else if (cell_column == 7'd2)
                        display_character = (cell_row == 6'd17) ? 8'h31 : 8'h32;
                    else if (cell_column == 7'd3) display_character = 8'h3d;
                    else if ((cell_column >= 7'd4) && (cell_column < 7'd12))
                        display_character = pad_character(
                            (cell_row == 6'd17) ? snapshot.controller.live1 :
                                                snapshot.controller.live2,
                            cell_column[2:0] - 3'd4);
                    else if ((cell_row == 6'd17) &&
                             (cell_column >= 7'd27) &&
                             (cell_column < (snapshot.dma.active ? 7'd33 : 7'd31))) begin
                        display_character = word_character(
                            snapshot.dma.active ? WORD_ACTIVE : WORD_IDLE,
                            cell_column - 7'd27);
                        foreground_color = snapshot.dma.active ? COLOR_BAD : COLOR_GOOD;
                    end else if ((cell_row == 6'd18) && (cell_column == 7'd27))
                        display_character = 8'h50;
                    else if ((cell_row == 6'd18) && (cell_column == 7'd28))
                        display_character = 8'h47;
                    else if ((cell_row == 6'd18) && (cell_column == 7'd29))
                        display_character = 8'h3d;
                    else if ((cell_row == 6'd18) &&
                             (cell_column >= 7'd30) && (cell_column < 7'd32))
                        display_character = value_hex_character(
                            {24'h0, snapshot.dma.source_page}, 4'd2,
                            cell_column - 7'd30);
                    else if ((cell_row == 6'd17) &&
                             (cell_column >= 7'd53) && (cell_column < 7'd57))
                        display_character = word_character(WORD_SNAP, cell_column - 7'd53);
                    else if ((cell_row == 6'd17) && (cell_column == 7'd57))
                        display_character = 8'h3d;
                    else if ((cell_row == 6'd17) &&
                             (cell_column >= 7'd58) && (cell_column < 7'd66))
                        display_character = value_hex_character(
                            snapshot.system.snapshot_id, 4'd8, cell_column - 7'd58);
                    else if ((cell_row == 6'd18) &&
                             (cell_column >= 7'd53) && (cell_column < 7'd58))
                        display_character = word_character(WORD_FRAME, cell_column - 7'd53);
                    else if ((cell_row == 6'd18) && (cell_column == 7'd58))
                        display_character = 8'h3d;
                    else if ((cell_row == 6'd18) &&
                             (cell_column >= 7'd59) && (cell_column < 7'd67))
                        display_character = value_hex_character(
                            snapshot.system.source_frame_number, 4'd8,
                            cell_column - 7'd59);
                end
                6'd19: begin
                    if (cell_column == 7'd1) display_character = 8'h53;
                    else if (cell_column == 7'd2) display_character = 8'h54;
                    else if (cell_column == 7'd3) display_character = 8'h42;
                    else if (cell_column == 7'd4) display_character = 8'h3d;
                    else if (cell_column == 7'd5)
                        display_character = debug_bit_char(snapshot.controller.strobe);
                    else if (cell_column == 7'd27) display_character = 8'h41;
                    else if (cell_column == 7'd28) display_character = 8'h44;
                    else if (cell_column == 7'd29) display_character = 8'h52;
                    else if (cell_column == 7'd30) display_character = 8'h3d;
                    else if ((cell_column >= 7'd31) && (cell_column < 7'd35))
                        display_character = value_hex_character(
                            {16'h0, snapshot.dma.source_address}, 4'd4,
                            cell_column - 7'd31);
                    else if (cell_column == 7'd53) display_character = 8'h4e;
                    else if (cell_column == 7'd54) display_character = 8'h4d;
                    else if (cell_column == 7'd55) display_character = 8'h49;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd65))
                        display_character = value_hex_character(
                            snapshot.system.nmi_count, 4'd8, cell_column - 7'd57);
                end
                6'd20: begin
                    if (cell_column == 7'd1) display_character = 8'h49;
                    else if (cell_column == 7'd2) display_character = 8'h31;
                    else if (cell_column == 7'd3) display_character = 8'h3d;
                    else if (cell_column == 7'd4)
                        display_character = debug_hex_char(snapshot.controller.index1);
                    else if (cell_column == 7'd6) display_character = 8'h49;
                    else if (cell_column == 7'd7) display_character = 8'h32;
                    else if (cell_column == 7'd8) display_character = 8'h3d;
                    else if (cell_column == 7'd9)
                        display_character = debug_hex_char(snapshot.controller.index2);
                    else if (cell_column == 7'd27) display_character = 8'h49;
                    else if (cell_column == 7'd28) display_character = 8'h44;
                    else if (cell_column == 7'd29) display_character = 8'h58;
                    else if (cell_column == 7'd30) display_character = 8'h3d;
                    else if ((cell_column >= 7'd31) && (cell_column < 7'd33))
                        display_character = value_hex_character(
                            {24'h0, snapshot.dma.byte_index}, 4'd2,
                            cell_column - 7'd31);
                    else if (cell_column == 7'd53) display_character = 8'h44;
                    else if (cell_column == 7'd54) display_character = 8'h4d;
                    else if (cell_column == 7'd55) display_character = 8'h41;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd65))
                        display_character = value_hex_character(
                            snapshot.system.dma_count, 4'd8, cell_column - 7'd57);
                end
                6'd21: begin
                    if ((cell_column >= 7'd1) && (cell_column < 7'd6))
                        display_character = word_character(WORD_SHIFT, cell_column - 7'd1);
                    else if (cell_column == 7'd6) display_character = 8'h31;
                    else if (cell_column == 7'd7) display_character = 8'h3d;
                    else if ((cell_column >= 7'd8) && (cell_column < 7'd10))
                        display_character = value_hex_character(
                            {24'h0, snapshot.controller.shift1}, 4'd2,
                            cell_column - 7'd8);
                    else if (cell_column == 7'd27) display_character = 8'h53;
                    else if (cell_column == 7'd28) display_character = 8'h4c;
                    else if (cell_column == 7'd29) display_character = 8'h4f;
                    else if (cell_column == 7'd30) display_character = 8'h54;
                    else if (cell_column == 7'd31) display_character = 8'h3d;
                    else if ((cell_column >= 7'd32) && (cell_column < 7'd35))
                        display_character = value_hex_character(
                            {22'h0, snapshot.dma.elapsed_slots}, 4'd3,
                            cell_column - 7'd32);
                    else if ((cell_column >= 7'd53) && (cell_column < 7'd57))
                        display_character = word_character(WORD_POLL, cell_column - 7'd53);
                    else if (cell_column == 7'd57) display_character = 8'h3d;
                    else if ((cell_column >= 7'd58) && (cell_column < 7'd66))
                        display_character = value_hex_character(
                            snapshot.system.controller_poll_count, 4'd8,
                            cell_column - 7'd58);
                end
                6'd22: begin
                    if ((cell_column >= 7'd1) && (cell_column < 7'd6))
                        display_character = word_character(WORD_SHIFT, cell_column - 7'd1);
                    else if (cell_column == 7'd6) display_character = 8'h32;
                    else if (cell_column == 7'd7) display_character = 8'h3d;
                    else if ((cell_column >= 7'd8) && (cell_column < 7'd10))
                        display_character = value_hex_character(
                            {24'h0, snapshot.controller.shift2}, 4'd2,
                            cell_column - 7'd8);
                    else if (cell_column == 7'd27) display_character = 8'h52;
                    else if (cell_column == 7'd28) display_character = 8'h44;
                    else if (cell_column == 7'd29) display_character = 8'h3d;
                    else if ((cell_column >= 7'd30) && (cell_column < 7'd33))
                        display_character = value_hex_character(
                            {23'h0, snapshot.dma.read_count}, 4'd3,
                            cell_column - 7'd30);
                    else if (cell_column == 7'd34) display_character = 8'h57;
                    else if (cell_column == 7'd35) display_character = 8'h52;
                    else if (cell_column == 7'd36) display_character = 8'h3d;
                    else if ((cell_column >= 7'd37) && (cell_column < 7'd40))
                        display_character = value_hex_character(
                            {23'h0, snapshot.dma.write_count}, 4'd3,
                            cell_column - 7'd37);
                    else if (cell_column == 7'd53) display_character = 8'h43;
                    else if (cell_column == 7'd54) display_character = 8'h50;
                    else if (cell_column == 7'd55) display_character = 8'h55;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd65))
                        display_character = value_hex_character(
                            snapshot.system.cpu_slot_count, 4'd8,
                            cell_column - 7'd57);
                end
                6'd23: begin
                    if (cell_column == 7'd27) display_character = 8'h4f;
                    else if (cell_column == 7'd28) display_character = 8'h57;
                    else if (cell_column == 7'd29) display_character = 8'h4e;
                    else if (cell_column == 7'd30) display_character = 8'h3d;
                    else if ((cell_column >= 7'd31) && (cell_column < 7'd35))
                        display_character = bus_owner_character(
                            snapshot.dma.bus_owner, cell_column - 7'd31);
                    else if (cell_column == 7'd53) display_character = 8'h50;
                    else if (cell_column == 7'd54) display_character = 8'h50;
                    else if (cell_column == 7'd55) display_character = 8'h55;
                    else if (cell_column == 7'd56) display_character = 8'h3d;
                    else if ((cell_column >= 7'd57) && (cell_column < 7'd65))
                        display_character = value_hex_character(
                            snapshot.system.ppu_cycle_count, 4'd8,
                            cell_column - 7'd57);
                end
                6'd27: begin
                    foreground_color = COLOR_HEADING;
                    if ((cell_column >= 7'd1) && (cell_column < 7'd10))
                        display_character = word_character(WORD_READ_ONLY, cell_column - 7'd1);
                    else if (cell_column == 7'd11) display_character = 8'h2d;
                    else if ((cell_column >= 7'd13) && (cell_column < 7'd25))
                        display_character = word_character(
                            WORD_FPGA_CONSOLE, cell_column - 7'd13);
                end
                default: display_character = 8'h20;
            endcase
        end

        glyph_row = debug_font_row(display_character, glyph_row_index);
        debug_color = (scan_y < 10'd48) ? COLOR_HEADER_BG : COLOR_BACKGROUND;
        if (active_video &&
            ((scan_x == 10'd4) || (scan_x == 10'd635) ||
             (scan_y == 10'd4) || (scan_y == 10'd475) ||
             (scan_y == 10'd48) || (scan_y == 10'd248)))
            debug_color = COLOR_BORDER;
        if (inside_text_grid && (glyph_column < 3'd6) &&
            glyph_row[3'd5 - glyph_column])
            debug_color = foreground_color;
        if (!active_video)
            debug_color = 24'h000000;

        if (developer_mode_enable) begin
            red = debug_color[23:16];
            green = debug_color[15:8];
            blue = debug_color[7:0];
        end else begin
            red = normal_red;
            green = normal_green;
            blue = normal_blue;
        end
    end
endmodule
