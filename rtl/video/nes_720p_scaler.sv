`timescale 1ns/1ps

// Scale the 256x240 NES picture into a centered 960x720 4:3 presentation.
// Vertical pixels repeat exactly three times. Horizontal pixels use the
// deterministic nearest-neighbor mapping floor(relative_x * 4 / 15), so each
// source pixel occupies three or four output pixels with no filtering.
//
// Developer layout retains the VGA logical composition: a 512x480 game area
// plus a 128x480 panel. It is scaled into the same 960x720 canvas, using exact
// 3x NES pixels and a 3:2 nearest-neighbor panel scale.
module nes_720p_scaler (
    input  logic [10:0] video_x,
    input  logic [9:0]  video_y,
    input  logic        active_video,
    input  logic        developer_layout,
    output logic        canvas_region,
    output logic        nes_region,
    output logic        panel_region,
    output logic [7:0]  nes_x,
    output logic [7:0]  nes_y,
    output logic [9:0]  panel_x,
    output logic [9:0]  panel_y,
    output logic [15:0] framebuffer_address
);
    localparam logic [10:0] CANVAS_LEFT = 11'd160;
    localparam logic [10:0] CANVAS_RIGHT = 11'd1120;
    localparam logic [10:0] DEVELOPER_GAME_RIGHT = 11'd928;

    logic [10:0] relative_x;
    logic [10:0] panel_relative_x;
    // Exact reciprocal multiplies over the bounded coordinate ranges:
    // floor(n/3) == (n*683)>>11 and floor(n/15) == (n*2185)>>15.
    // Expressing the constants explicitly lets Cyclone V use its fast
    // multiplier fabric instead of inferring long combinational dividers.
    (* multstyle = "dsp" *) logic [24:0] normal_x_product;
    (* multstyle = "dsp" *) logic [20:0] developer_x_product;
    (* multstyle = "dsp" *) logic [19:0] nes_y_product;
    (* multstyle = "dsp" *) logic [20:0] panel_y_product;
    (* multstyle = "dsp" *) logic [19:0] panel_x_product;

    always_comb begin
        canvas_region = active_video && video_x >= CANVAS_LEFT &&
                        video_x < CANVAS_RIGHT;
        relative_x = video_x - CANVAS_LEFT;
        panel_relative_x = video_x - DEVELOPER_GAME_RIGHT;
        normal_x_product = relative_x * 14'd8740;
        developer_x_product = relative_x * 10'd683;
        nes_y_product = video_y * 10'd683;
        panel_y_product = video_y * 11'd1366;
        panel_x_product = panel_relative_x * 11'd1366;

        nes_region = 1'b0;
        panel_region = 1'b0;
        nes_x = 8'd0;
        nes_y = 8'd0;
        panel_x = 10'd512;
        panel_y = 10'd0;

        if (canvas_region) begin
            if (developer_layout) begin
                nes_region = video_x < DEVELOPER_GAME_RIGHT;
                panel_region = !nes_region;
                if (nes_region) begin
                    nes_x = 8'(developer_x_product >> 11);
                    nes_y = 8'(nes_y_product >> 11);
                end else begin
                    panel_x = 10'd512 +
                              10'(panel_x_product >> 11);
                    panel_y = 10'(panel_y_product >> 11);
                end
            end else begin
                nes_region = 1'b1;
                nes_x = 8'(normal_x_product >> 15);
                nes_y = 8'(nes_y_product >> 11);
            end
        end

        framebuffer_address = {nes_y, nes_x};
    end

`ifndef SYNTHESIS
    always_comb begin
        if (nes_region) begin
            assert (canvas_region);
            assert (nes_y < 8'd240);
            assert (framebuffer_address < 16'd61440);
        end
        if (panel_region) begin
            assert (developer_layout && canvas_region);
            assert (panel_x >= 10'd512 && panel_x < 10'd640);
            assert (panel_y < 10'd480);
        end
    end
`endif
endmodule
