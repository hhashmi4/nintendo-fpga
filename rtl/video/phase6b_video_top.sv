`timescale 1ns/1ps

// Standalone synthesis/fitting qualification harness for the Phase 6B video
// pipeline. It writes a deterministic synthetic NES frame stream into the
// real multi-clock framebuffer so Quartus cannot optimize away RAM or CDC.
// This is not a board HDMI pinout and contains no TMDS signaling.
module phase6b_video_top (
    input  logic       CLOCK_50,
    input  logic       RESET_N,
    input  logic       DEVELOPER_LAYOUT,
    input  logic       TEST_PATTERN,
    input  logic       CAPTURE_FREEZE,
    output logic       VIDEO_PCLK,
    output logic       VIDEO_HSYNC,
    output logic       VIDEO_VSYNC,
    output logic       VIDEO_DE,
    output logic       VIDEO_FRAME_START,
    output logic [7:0] VIDEO_R,
    output logic [7:0] VIDEO_G,
    output logic [7:0] VIDEO_B,
    output logic       VIDEO_LOCKED,
    output logic       VIDEO_ERROR
);
    logic pixel_clk, pll_locked;
    logic source_reset, pixel_reset;
    logic [7:0] source_x, source_y;
    logic source_frame_start;
    logic [5:0] source_color;
    logic [2:0] source_emphasis;
    logic [7:0] frame_number;
    logic [23:0] digital_rgb;
    logic write_range_error, write_sequence_error;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] capture_freeze_sync;

    video_720p_pll pll (
        .ref_clk(CLOCK_50),
        .reset_n(RESET_N),
        .pixel_clk(pixel_clk),
        .locked(pll_locked)
    );

    reset_sync source_reset_synchronizer (
        .clk(CLOCK_50),
        .async_reset_n(RESET_N),
        .reset(source_reset)
    );

    reset_sync pixel_reset_synchronizer (
        .clk(pixel_clk),
        .async_reset_n(RESET_N && pll_locked),
        .reset(pixel_reset)
    );

    always_ff @(posedge CLOCK_50) begin
        if (source_reset) begin
            source_x <= 8'd0;
            source_y <= 8'd0;
            frame_number <= 8'd0;
            capture_freeze_sync <= 2'b00;
        end else if (source_x == 8'd255) begin
            capture_freeze_sync <= {capture_freeze_sync[0], CAPTURE_FREEZE};
            source_x <= 8'd0;
            if (source_y == 8'd239) begin
                source_y <= 8'd0;
                frame_number <= frame_number + 1'b1;
            end else begin
                source_y <= source_y + 1'b1;
            end
        end else begin
            capture_freeze_sync <= {capture_freeze_sync[0], CAPTURE_FREEZE};
            source_x <= source_x + 1'b1;
        end
    end

    assign source_frame_start = source_x == 8'd0 && source_y == 8'd0;
    assign source_color = source_x[5:0] ^ source_y[5:0] ^ frame_number[5:0];
    assign source_emphasis = frame_number[2:0];

    nes_digital_video_pipeline pipeline (
        .source_clk(CLOCK_50),
        .source_reset(source_reset),
        .source_frame_start(source_frame_start),
        .source_pixel_valid(!source_reset),
        .source_pixel_x(source_x),
        .source_pixel_y(source_y),
        .source_pixel_color(source_color),
        .source_pixel_emphasis(source_emphasis),
        .capture_freeze(capture_freeze_sync[1]),
        .pixel_clk(pixel_clk),
        .pixel_reset(pixel_reset),
        .test_pattern_async(TEST_PATTERN),
        .developer_layout_async(DEVELOPER_LAYOUT),
        .panel_valid(1'b0),
        .panel_rgb(24'd0),
        .panel_x(),
        .panel_y(),
        .panel_request(),
        .rgb(digital_rgb),
        .hsync(VIDEO_HSYNC),
        .vsync(VIDEO_VSYNC),
        .active_video(VIDEO_DE),
        .video_pixel_clock(VIDEO_PCLK),
        .frame_start(VIDEO_FRAME_START),
        .frame_end(),
        .line_start(),
        .line_end(),
        .scan_x(),
        .scan_y(),
        .source_nes_x(),
        .source_nes_y(),
        .capture_active(),
        .capture_complete(),
        .capture_pending(),
        .capture_write_bank(),
        .captured_frames(),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .display_valid(),
        .swap_complete(),
        .display_bank(),
        .displayed_frames()
    );

    assign VIDEO_R = digital_rgb[23:16];
    assign VIDEO_G = digital_rgb[15:8];
    assign VIDEO_B = digital_rgb[7:0];
    assign VIDEO_LOCKED = pll_locked;
    assign VIDEO_ERROR = write_range_error || write_sequence_error;
endmodule
