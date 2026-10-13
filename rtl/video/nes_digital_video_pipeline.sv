`timescale 1ns/1ps

// Complete reusable NES-to-digital-video path. The lossless indexed triple
// framebuffer is the only multi-clock storage: a completed bank is published
// with a toggle and remains stable until the scanout acknowledges a swap at a
// frame boundary. RGB888 conversion happens after the read port, saving RAM.
module nes_digital_video_pipeline (
    input  logic        source_clk,
    input  logic        source_reset,
    input  logic        source_frame_start,
    input  logic        source_pixel_valid,
    input  logic [7:0]  source_pixel_x,
    input  logic [7:0]  source_pixel_y,
    input  logic [5:0]  source_pixel_color,
    input  logic [2:0]  source_pixel_emphasis,
    input  logic        capture_freeze,

    input  logic        pixel_clk,
    input  logic        pixel_reset,
    input  logic        test_pattern_async,
    input  logic        developer_layout_async,
    input  logic        panel_valid,
    input  logic [23:0] panel_rgb,
    output logic [9:0]  panel_x,
    output logic [9:0]  panel_y,
    output logic        panel_request,

    output logic [23:0] rgb,
    output logic        hsync,
    output logic        vsync,
    output logic        active_video,
    output logic        video_pixel_clock,
    output logic        frame_start,
    output logic        frame_end,
    output logic        line_start,
    output logic        line_end,
    output logic [10:0] scan_x,
    output logic [9:0]  scan_y,
    output logic [7:0]  source_nes_x,
    output logic [7:0]  source_nes_y,

    output logic        capture_active,
    output logic        capture_complete,
    output logic        capture_pending,
    output logic [1:0]  capture_write_bank,
    output logic [15:0] captured_frames,
    output logic        write_range_error,
    output logic        write_sequence_error,
    output logic        display_valid,
    output logic        swap_complete,
    output logic [1:0]  display_bank,
    output logic [15:0] displayed_frames
);
    logic [15:0] framebuffer_address;
    logic [8:0] framebuffer_pixel;
    logic framebuffer_frame_end;
    logic framebuffer_source_reset, framebuffer_pixel_reset;

    // Either endpoint losing its epoch invalidates ownership at both ends.
    // Reset only content on a source restart; the raster continues running.
    reset_sync source_content_reset (
        .clk(source_clk), .async_reset_n(!source_reset && !pixel_reset),
        .reset(framebuffer_source_reset)
    );
    reset_sync pixel_content_reset (
        .clk(pixel_clk), .async_reset_n(!source_reset && !pixel_reset),
        .reset(framebuffer_pixel_reset)
    );

    nes_framebuffer framebuffer (
        .write_clk(source_clk),
        .write_reset(framebuffer_source_reset),
        .write_frame_start(source_frame_start),
        .write_valid(source_pixel_valid),
        .write_x(source_pixel_x),
        .write_y(source_pixel_y),
        .write_color(source_pixel_color),
        .write_emphasis(source_pixel_emphasis),
        .capture_freeze(capture_freeze),
        .capture_active(capture_active),
        .capture_complete(capture_complete),
        .capture_pending(capture_pending),
        .write_bank(capture_write_bank),
        .captured_frames(captured_frames),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .read_clk(pixel_clk),
        .read_reset(framebuffer_pixel_reset),
        .read_frame_end(framebuffer_frame_end),
        .read_address(framebuffer_address),
        .read_pixel(framebuffer_pixel),
        .display_valid(display_valid),
        .swap_complete(swap_complete),
        .read_bank(display_bank),
        .displayed_frames(displayed_frames)
    );

    nes_720p_video video (
        .pixel_clk(pixel_clk),
        .reset(pixel_reset),
        .test_pattern_async(test_pattern_async),
        .developer_layout_async(developer_layout_async),
        .framebuffer_valid(display_valid),
        .framebuffer_pixel(framebuffer_pixel),
        .framebuffer_address(framebuffer_address),
        .panel_valid(panel_valid),
        .panel_rgb(panel_rgb),
        .panel_x(panel_x),
        .panel_y(panel_y),
        .panel_request(panel_request),
        .framebuffer_frame_end(framebuffer_frame_end),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .line_start(line_start),
        .line_end(line_end),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .source_nes_x(source_nes_x),
        .source_nes_y(source_nes_y),
        .active_video(active_video),
        .hsync(hsync),
        .vsync(vsync),
        .pixel_clock(video_pixel_clock),
        .rgb(rgb)
    );
endmodule
