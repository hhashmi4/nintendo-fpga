`timescale 1ns/1ps

// Same independent UI on a centered, unscaled 640x480 canvas in 720p.
// RGB latency matches nes_720p_video. No timing, link-enable or RAM ownership
// is changed. A logical target has no rich gameplay debugger snapshot here.
module nes_console_720p_overlay #(parameter bit REDUCED_MOTION=0) (
    input logic source_clk, source_reset,
    input logic [927:0] library_packet,
    input logic [31:0] requested_status,
    input logic [7:0] buttons,
    input logic held_reset, inhibit_game, focus,
    output logic source_ack,
    output logic [31:0] source_response,
    input logic pixel_clk, pixel_reset, content_reset,
    input logic frame_end, framebuffer_valid,
    input logic [10:0] render_x,
    input logic [9:0] render_y,
    input logic render_active,
    input logic [23:0] game_rgb,
    output logic [23:0] rgb,
    output logic [1:0] selected_source
);
    logic [31:0] displayed_status;
    logic [927:0] displayed_library;
    logic [7:0] displayed_buttons;
    import nes_console_style_pkg::*;
    logic displayed_reset, displayed_focus, displayed_valid, game_visible;
    logic [23:0] ui_rgb;
    nes_console_video ownership (
        .library_packet(library_packet), .displayed_library(displayed_library),
        .source_clk(source_clk), .source_reset(source_reset),
        .requested_status(requested_status), .buttons(buttons),
        .held_reset(held_reset), .inhibit_game(inhibit_game), .focus(focus),
        .source_ack(source_ack), .source_response(source_response),
        .pixel_clk(pixel_clk), .pixel_reset(pixel_reset), .content_reset(content_reset),
        .frame_end(frame_end), .framebuffer_valid(framebuffer_valid),
        .selected_source(selected_source), .displayed_status(displayed_status),
        .displayed_buttons(displayed_buttons), .displayed_reset(displayed_reset),
        .displayed_focus(displayed_focus), .displayed_valid(displayed_valid),
        .game_visible(game_visible)
    );
    nes_console_renderer #(.REDUCED_MOTION(REDUCED_MOTION)) renderer (
        .library_packet(displayed_library),
        .pixel_clk(pixel_clk), .reset(pixel_reset), .frame_end(frame_end),
        .focus(displayed_focus), .status_valid(displayed_valid),
        .x(10'(render_x - 11'(UI_HDMI_X))), .y(render_y - 10'(UI_HDMI_Y)),
        .active(render_active && int'(render_x) >= UI_HDMI_X && int'(render_x) < UI_HDMI_X+UI_WIDTH &&
                int'(render_y) >= UI_HDMI_Y && int'(render_y) < UI_HDMI_Y+UI_HEIGHT),
        .status(displayed_status), .buttons(displayed_buttons),
        .held_reset(displayed_reset), .rgb(ui_rgb)
    );
    assign rgb = selected_source == 1 ? (game_visible ? game_rgb : 24'd0) : ui_rgb;
endmodule
