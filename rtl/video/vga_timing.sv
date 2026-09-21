`timescale 1ns/1ps

// VESA-compatible 640x480 progressive timing at a 25.2 MHz pixel clock.
module vga_timing (
    input  logic       pixel_clk,
    input  logic       reset,
    output logic [9:0] x,
    output logic [9:0] y,
    output logic       active_video,
    output logic       hsync_n,
    output logic       vsync_n,
    output logic       line_start,
    output logic       frame_start,
    output logic       frame_end
);
    localparam logic [9:0] H_ACTIVE = 10'd640;
    localparam logic [9:0] H_FRONT  = 10'd16;
    localparam logic [9:0] H_SYNC   = 10'd96;
    localparam logic [9:0] H_BACK   = 10'd48;
    localparam logic [9:0] H_TOTAL  =
        H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam logic [9:0] V_ACTIVE = 10'd480;
    localparam logic [9:0] V_FRONT  = 10'd10;
    localparam logic [9:0] V_SYNC   = 10'd2;
    localparam logic [9:0] V_BACK   = 10'd33;
    localparam logic [9:0] V_TOTAL  =
        V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    always_comb begin
        active_video = x < H_ACTIVE && y < V_ACTIVE;
        hsync_n = !(x >= H_ACTIVE + H_FRONT &&
                    x < H_ACTIVE + H_FRONT + H_SYNC);
        vsync_n = !(y >= V_ACTIVE + V_FRONT &&
                    y < V_ACTIVE + V_FRONT + V_SYNC);
        line_start = x == 10'd0;
        frame_start = x == 10'd0 && y == 10'd0;
        frame_end = x == H_TOTAL - 1 && y == V_TOTAL - 1;
    end

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 10'd0;
            y <= y == V_TOTAL - 1 ? 10'd0 : y + 10'd1;
        end else begin
            x <= x + 10'd1;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge pixel_clk) begin
        if (!reset) begin
            assert (x < H_TOTAL);
            assert (y < V_TOTAL);
            if (active_video)
                assert (x < H_ACTIVE && y < V_ACTIVE);
            if (!hsync_n)
                assert (x >= H_ACTIVE + H_FRONT &&
                        x < H_ACTIVE + H_FRONT + H_SYNC);
            if (!vsync_n)
                assert (y >= V_ACTIVE + V_FRONT &&
                        y < V_ACTIVE + V_FRONT + V_SYNC);
        end
    end
`endif
endmodule
