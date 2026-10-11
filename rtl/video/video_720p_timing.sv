`timescale 1ns/1ps

// CTA-861 1280x720p60 timing. A 74.250 MHz pixel clock produces exactly
// 60.000 frames/s from 1650x750 total pixels. Both sync polarities are
// positive, as specified for this video mode.
module video_720p_timing (
    input  logic        pixel_clk,
    input  logic        reset,
    output logic [10:0] x,
    output logic [9:0]  y,
    output logic        active_video,
    output logic        hsync,
    output logic        vsync,
    output logic        line_start,
    output logic        line_end,
    output logic        frame_start,
    output logic        frame_end
);
    localparam logic [10:0] H_ACTIVE = 11'd1280;
    localparam logic [10:0] H_FRONT  = 11'd110;
    localparam logic [10:0] H_SYNC   = 11'd40;
    localparam logic [10:0] H_BACK   = 11'd220;
    localparam logic [10:0] H_TOTAL  =
        H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam logic [9:0] V_ACTIVE = 10'd720;
    localparam logic [9:0] V_FRONT  = 10'd5;
    localparam logic [9:0] V_SYNC   = 10'd5;
    localparam logic [9:0] V_BACK   = 10'd20;
    localparam logic [9:0] V_TOTAL  =
        V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    always_comb begin
        active_video = x < H_ACTIVE && y < V_ACTIVE;
        hsync = x >= H_ACTIVE + H_FRONT &&
                x < H_ACTIVE + H_FRONT + H_SYNC;
        vsync = y >= V_ACTIVE + V_FRONT &&
                y < V_ACTIVE + V_FRONT + V_SYNC;
        line_start = x == 11'd0;
        line_end = x == H_TOTAL - 1'b1;
        frame_start = line_start && y == 10'd0;
        frame_end = line_end && y == V_TOTAL - 1'b1;
    end

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            x <= 11'd0;
            y <= 10'd0;
        end else if (line_end) begin
            x <= 11'd0;
            y <= y == V_TOTAL - 1'b1 ? 10'd0 : y + 1'b1;
        end else begin
            x <= x + 1'b1;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge pixel_clk) begin
        if (!reset) begin
            assert (x < H_TOTAL);
            assert (y < V_TOTAL);
            if (active_video)
                assert (x < H_ACTIVE && y < V_ACTIVE);
            if (hsync)
                assert (x >= H_ACTIVE + H_FRONT &&
                        x < H_ACTIVE + H_FRONT + H_SYNC);
            if (vsync)
                assert (y >= V_ACTIVE + V_FRONT &&
                        y < V_ACTIVE + V_FRONT + V_SYNC);
        end
    end
`endif
endmodule
