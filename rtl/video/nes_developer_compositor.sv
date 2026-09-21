`timescale 1ns/1ps

// Single final RGB compositor. In normal mode this is a literal hard bypass.
// In Developer Mode x=0..511 is the left-aligned exact-2x game path and
// x=512..639 is the independent snapshot-driven panel path.
module nes_developer_compositor (
    input  logic       developer_mode_enable,
    input  logic [9:0] scan_x,
    input  logic       active_video,
    input  logic [7:0] game_red,
    input  logic [7:0] game_green,
    input  logic [7:0] game_blue,
    input  logic [7:0] panel_red,
    input  logic [7:0] panel_green,
    input  logic [7:0] panel_blue,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue
);
    always_comb begin
        if (!developer_mode_enable) begin
            red = game_red;
            green = game_green;
            blue = game_blue;
        end else if (!active_video) begin
            red = 8'h00;
            green = 8'h00;
            blue = 8'h00;
        end else if (scan_x < 10'd512) begin
            red = game_red;
            green = game_green;
            blue = game_blue;
        end else begin
            red = panel_red;
            green = panel_green;
            blue = panel_blue;
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        if (developer_mode_enable && active_video) begin
            if (scan_x < 10'd512) begin
                assert ({red, green, blue} ==
                        {game_red, game_green, game_blue});
            end else begin
                assert ({red, green, blue} ==
                        {panel_red, panel_green, panel_blue});
            end
        end
    end
`endif
endmodule
