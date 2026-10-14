`timescale 1ns/1ps

// Independent procedural canvas; existing 6x8 font, no UI framebuffer.
// Prepare one character row at canvas x=0, before the safe-area text begins.
// This breaks row selection from glyph decode without adding RGB latency.
// The existing one-stage early render coordinates and output register remain.
module nes_console_renderer #(parameter bit REDUCED_MOTION=0) (
    input logic pixel_clk, reset, frame_end,
    input logic [9:0] x, y,
    input logic active, status_valid,
    input logic [31:0] status,
    input logic [7:0] buttons,
    input logic held_reset, focus,
    output logic [23:0] rgb
);
    import debug_font_pkg::*;
    import nes_console_style_pkg::*;
    logic splash;
    logic [4:0] phase;
    nes_console_animation #(.REDUCED_MOTION(REDUCED_MOTION)) animation (
        .pixel_clk(pixel_clk), .reset(reset), .frame_end(frame_end),
        .status(status), .status_valid(status_valid), .buttons(buttons), .focus(focus), .splash(splash), .phase(phase)
    );
    logic [255:0] text_line, line_text;
    logic [23:0] line_ink;
    logic [9:0] line_tx, line_ty;
    logic line_large, line_enabled;
    logic [7:0] character;
    logic [5:0] glyph;
    logic [9:0] tx, ty, dx, dy;
    logic [5:0] column;
    logic [2:0] gx, gy;
    logic large_text, text_enabled;
    logic [23:0] next_rgb, ink;
    integer panel_right, selected_y;
    always_comb begin
        next_rgb=UI_BG;
        ink=UI_TEXT;
        tx=10'(UI_TEXT_X); ty=0;
        text_line={32{8'h20}};
        large_text=0; text_enabled=0;
        panel_right=status[3:0]==7 ? 496 : UI_WIDTH-UI_MARGIN;
        selected_y=UI_FIRST_Y + (focus ? UI_ROW_STEP : 0);
        if (int'(x) >= UI_MARGIN && int'(x) < panel_right && int'(y) >= UI_PANEL_TOP && int'(y) < UI_PANEL_BOTTOM)
            next_rgb=UI_SURFACE;
        if (int'(x) >= UI_MARGIN && int'(x) < UI_WIDTH-UI_MARGIN && int'(y) >= UI_RULE_Y && int'(y) < UI_RULE_Y+2)
            next_rgb=UI_PURPLE;
        if (int'(x) >= UI_MARGIN && int'(x) < UI_MARGIN+UI_RULE_WIDTH && int'(y) >= UI_RULE_Y && int'(y) < UI_RULE_Y+2)
            next_rgb=UI_RED;
        if (status[3:0]==1 && int'(x) >= UI_MARGIN+UI_FOCUS_INSET && int'(x) < panel_right-UI_FOCUS_INSET &&
            int'(y) >= selected_y-UI_FOCUS_INSET && int'(y) < selected_y-UI_FOCUS_INSET+UI_FOCUS_HEIGHT) begin
            next_rgb=UI_PURPLE;
            if (int'(x) < UI_MARGIN+UI_FOCUS_INSET+UI_FOCUS_BAR) next_rgb=UI_TEXT;
        end
        if (int'(y) >= UI_BRAND_Y && int'(y) < UI_BRAND_Y+UI_CELL) begin
            ty=10'(UI_BRAND_Y); text_enabled=1; text_line="NINTENDO FPGA                   ";
        end else if (int'(y) >= UI_SUBTITLE_Y && int'(y) < UI_SUBTITLE_Y+UI_CELL) begin
            ty=10'(UI_SUBTITLE_Y); text_enabled=1; ink=UI_MUTED; text_line=status[3:0]==1 ? "START PLAY / SELECT DEV         " : "CONSOLE / SYSTEM                ";
        end else if (int'(y) >= UI_TITLE_Y && int'(y) < UI_TITLE_Y+16) begin
            ty=10'(UI_TITLE_Y); text_enabled=1;
            case(status[3:0])
                4'd0: text_line="INITIALIZING                    ";
                4'd1: text_line="READY TO PLAY                   ";
                4'd2: text_line="LOADING CARTRIDGE               ";
                4'd3: text_line="STARTING GAME                   ";
                4'd4: text_line="GAME ACTIVE                     ";
                4'd5: text_line="RETURNING TO MENU               ";
                4'd6: text_line="LOAD NEEDS ATTENTION            ";
                4'd7: text_line="DEVELOPER MODE                  ";
                default: text_line="STATUS UNAVAILABLE              ";
            endcase
            if(status[3:0]==6) ink=UI_ERROR;
        end else if (int'(y) >= UI_FIRST_Y && int'(y) < UI_FIRST_Y+16) begin
            ty=10'(UI_FIRST_Y); text_enabled=1;
            case(status[3:0])
                0: text_line="PREPARING CONSOLE               ";
                1: begin
                    text_line=status[8] ? "PLAY GAME                       " : "PLAY GAME - UNAVAILABLE         ";
                    if(!status[8]) ink=UI_MUTED;
                end
                2: begin
                    case(status[11:10])
                        2'd0: text_line="WAITING FOR HPS TRANSFER        ";
                        2'd1: text_line="RECEIVING GAME DATA             ";
                        2'd2: text_line="IMAGE READY TO ACTIVATE         ";
                        2'd3: text_line="CHECKING LOAD RESULT            ";
                    endcase
                end
                3: text_line="WAITING FOR COMPLETE FRAME      ";
                4: text_line="GAME OWNS DISPLAY               ";
                5: text_line="RESTORING SYSTEM DISPLAY        ";
                6: begin
                    case(status[15:12])
                        4'd0: text_line="NO ERROR REPORTED               ";
                        4'd1: text_line="WRONG LOADER STATE              ";
                        4'd2: text_line="LOADER ALREADY BUSY             ";
                        4'd3: text_line="INVALID LOADER COMMAND          ";
                        4'd4: text_line="INVALID WRITE TARGET            ";
                        4'd5: text_line="INVALID WRITE ADDRESS           ";
                        4'd6: text_line="EMPTY CARTRIDGE LOAD            ";
                        4'd7: text_line="INVALID ROM MANIFEST            ";
                        4'd8: text_line="UNSUPPORTED MAPPER              ";
                        4'd9: text_line="UNSUPPORTED PRG SIZE            ";
                        4'd10: text_line="UNSUPPORTED CHR SIZE            ";
                        4'd11: text_line="OUT OF ORDER WRITE              ";
                        4'd12: text_line="PRG DATA INCOMPLETE             ";
                        4'd13: text_line="CHR DATA INCOMPLETE             ";
                        4'd14: text_line="ACTIVATION INVALID              ";
                        4'd15: text_line="GAME FRAME TIMEOUT              ";
                    endcase
                    if(status[15:12]==14 && status[11:10]!=3) text_line="HOST LOAD REQUEST FAILED        ";
                end
                7: text_line="DEVELOPER MODE                  ";
                default: text_line="STATUS UNAVAILABLE              ";
            endcase
        end else if (int'(y) >= UI_FIRST_Y+UI_ROW_STEP && int'(y) < UI_FIRST_Y+UI_ROW_STEP+16) begin
            ty=10'(UI_FIRST_Y+UI_ROW_STEP); text_enabled=1;
            text_line=status[3:0]==1 ? "DEVELOPER MODE                  " : "B - RETURN TO MENU              ";
            if(status[3:0]==0 || status[3:0]==3 || status[3:0]==4 || status[3:0]==5)
                text_line="DISPLAY HANDOFF IN PROGRESS     ";
        end else if (int'(y) >= UI_DETAIL_Y && int'(y) < UI_DETAIL_Y+16) begin
            ty=10'(UI_DETAIL_Y); text_enabled=1; ink=UI_MUTED;
            case(status[3:0])
                1: text_line="LIBRARY / SETTINGS - LATER      ";
                2: text_line="TRANSFER CONTROLLED BY HPS      ";
                6: begin
                    text_line="ERROR 0  LOADER  0              ";
                    text_line[255-6*8 -: 8]=debug_hex_char(status[15:12]);
                    text_line[255-17*8 -: 8]=debug_hex_char({2'd0,status[11:10]});
                end
                7: begin
                    text_line="RESET 0  LOAD  0  ERROR 0       ";
                    text_line[255-6*8 -: 8]=debug_bit_char(held_reset);
                    text_line[255-15*8 -: 8]=debug_hex_char({2'd0,status[11:10]});
                    text_line[255-24*8 -: 8]=debug_hex_char(status[15:12]);
                end
                default: text_line="INDEPENDENT SYSTEM DISPLAY      ";
            endcase
        end else if (int'(y) >= UI_STATUS_Y && int'(y) < UI_STATUS_Y+16) begin
            ty=10'(UI_STATUS_Y); text_enabled=1;
            text_line=status[8] ? "CARTRIDGE READY                 " : "NO CARTRIDGE AVAILABLE          ";
            ink=status[8] ? UI_SUCCESS : UI_WARNING;
            if(status[3:0]==6) begin text_line="RETRY WITH A COMPLETE LOAD      "; ink=UI_WARNING; end
            if(status[3:0]==7) begin
                text_line="EPOCH 0000 BUTTONS  00          "; ink=UI_MUTED;
                text_line[255-6*8 -: 8]=debug_hex_char(status[31:28]);
                text_line[255-7*8 -: 8]=debug_hex_char(status[27:24]);
                text_line[255-8*8 -: 8]=debug_hex_char(status[23:20]);
                text_line[255-9*8 -: 8]=debug_hex_char(status[19:16]);
                text_line[255-20*8 -: 8]=debug_hex_char(buttons[7:4]);
                text_line[255-21*8 -: 8]=debug_hex_char(buttons[3:0]);
            end
        end else if (int'(y) >= UI_HINT_Y && int'(y) < UI_HINT_Y+16) begin
            ty=10'(UI_HINT_Y); text_enabled=1; ink=UI_MUTED;
            case(status[3:0])
                4'd0: text_line="SYSTEM INITIALIZATION           ";
                4'd1: text_line="UP/DOWN FOCUS  A SELECT         ";
                4'd2: text_line="RELOAD AFTER INTERRUPTION       ";
                4'd3: text_line="FIRST FRAME REQUIRED            ";
                4'd4: text_line="HPS MENU TO RETURN              ";
                4'd5: text_line="PLEASE WAIT                     ";
                4'd6: text_line="SELECT - DEVELOPER              ";
                4'd7: text_line="DIAGNOSTICS REMAIN AVAILABLE    ";
                default: text_line={32{8'h20}};
            endcase
        end
        // Four discrete dots are indeterminate activity, never a percentage.
        if((status[3:0]==2 || status[3:0]==3 || status[3:0]==5) &&
           int'(y)>=UI_DOT_Y && int'(y)<UI_DOT_Y+UI_DOT_SIZE && int'(x) >=UI_TEXT_X && int'(x) <UI_TEXT_X+4*UI_DOT_STEP) begin
            if((x-10'(UI_TEXT_X)) % 10'(UI_DOT_STEP) < 10'(UI_DOT_SIZE))
                next_rgb=((x-10'(UI_TEXT_X))/10'(UI_DOT_STEP) == {8'd0,phase[4:3]}) ? UI_TEXT : UI_PURPLE;
        end
        if(splash) begin
            next_rgb=UI_BG; text_enabled=0; ink=UI_TEXT;
            if(int'(x)>=UI_SPLASH_MARK_X && int'(x)<UI_SPLASH_MARK_X+2*UI_SPLASH_MARK_SIZE &&
               int'(y)>=UI_SPLASH_MARK_Y && int'(y)<UI_SPLASH_MARK_Y+UI_SPLASH_MARK_SIZE) next_rgb=int'(x)<UI_SPLASH_MARK_X+UI_SPLASH_MARK_SIZE ? UI_PURPLE : UI_RED;
            if(int'(y)>=UI_SPLASH_TEXT_Y && int'(y)<UI_SPLASH_TEXT_Y+2*UI_CELL) begin
                tx=10'(UI_SPLASH_TEXT_X); ty=10'(UI_SPLASH_TEXT_Y); large_text=1; text_enabled=1; text_line="NINTENDO FPGA                   ";
            end
            if(int'(y)>=UI_SPLASH_SUB_Y && int'(y)<UI_SPLASH_SUB_Y+UI_CELL) begin
                tx=10'(UI_SPLASH_SUB_X); ty=10'(UI_SPLASH_SUB_Y); text_enabled=1; ink=UI_MUTED; text_line="A NEW WAY TO PLAY               ";
            end
            if(int'(y)>=UI_SPLASH_RULE_Y && int'(y)<UI_SPLASH_RULE_Y+4 && int'(x)>=UI_SPLASH_MARK_X && int'(x)<UI_SPLASH_MARK_X+2*UI_SPLASH_MARK_SIZE)
                next_rgb=UI_PURPLE;
            if(int'(y)>=UI_SPLASH_RULE_Y && int'(y)<UI_SPLASH_RULE_Y+4 && int'(x)>=UI_SPLASH_MARK_X && int'(x)<UI_SPLASH_MARK_X+UI_DOT_STEP+32'({phase[4:3],4'd0}))
                next_rgb=UI_RED;
        end
        dx=x-line_tx; dy=y-line_ty;
        column=line_large ? {1'b0,dx[9:5]} : dx[9:4];
        gx=line_large ? dx[4:2] : dx[3:1];
        gy=line_large ? dy[4:2] : dy[3:1];
        character=column<32 ? line_text[255-int'(column)*8 -: 8] : 8'h20;
        glyph=debug_font_row(character,gy);
        if(line_enabled && x>=line_tx && column<32 && gx<6 && glyph[5-gx]) next_rgb=line_ink;
        if(!active || !status_valid) next_rgb=0;
    end
    // Every supported text origin is inside the safe area (x>=32). At x=0
    // the previous row cannot contribute a text pixel; by x=1 this bank is
    // coherent for the entire scanline. No generated clock or line RAM.
    always_ff @(posedge pixel_clk) begin
        if(reset) begin
            line_text <= {32{8'h20}};
            line_ink <= UI_TEXT;
            line_tx <= 10'(UI_TEXT_X);
            line_ty <= 0;
            line_large <= 0;
            line_enabled <= 0;
        end else if(x==0) begin
            line_text <= text_line;
            line_ink <= ink;
            line_tx <= tx;
            line_ty <= ty;
            line_large <= large_text;
            line_enabled <= text_enabled;
        end
    end
    always_ff @(posedge pixel_clk) begin
        if(reset) rgb<=0;
        else rgb<=next_rgb;
    end
endmodule
