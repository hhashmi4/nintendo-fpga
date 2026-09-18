`timescale 1ns/1ps

module ppu_timing (
    input  logic       clk,
    input  logic       reset,
    input  logic       ppu_enable,
    input  logic       rendering_enabled,
    output logic [8:0] dot = 9'd0,
    output logic [8:0] scanline = 9'd0,
    output logic       frame_odd = 1'b0,
    output logic       visible_pixel,
    output logic [7:0] pixel_x,
    output logic [7:0] pixel_y,
    output logic       vblank = 1'b0,
    output logic       frame_start,
    output logic       frame_end,
    output logic       scanline_start,
    output logic       vblank_start,
    output logic       vblank_end,
    output logic       pre_render,
    output logic       post_render
);
    localparam logic [8:0] LAST_DOT = 9'd340;
    localparam logic [8:0] ODD_FRAME_LAST_DOT = 9'd339;
    localparam logic [8:0] LAST_SCANLINE = 9'd261;

    logic odd_frame_short_tick;
    logic terminal_tick;

    // dot/scanline identify the PPU tick presented to downstream logic. Event
    // outputs are qualified by ppu_enable, so a consumer samples an event only
    // on the edge that consumes that coordinate. Region outputs are levels.
    always_comb begin
        odd_frame_short_tick = rendering_enabled && frame_odd &&
                               scanline == LAST_SCANLINE &&
                               dot == ODD_FRAME_LAST_DOT;
        terminal_tick = odd_frame_short_tick ||
                        (scanline == LAST_SCANLINE && dot == LAST_DOT);

        visible_pixel = !reset && ppu_enable && scanline < 9'd240 &&
                        dot >= 9'd1 && dot <= 9'd256;
        pixel_x = 8'd0;
        pixel_y = 8'd0;
        if (scanline < 9'd240 && dot >= 9'd1 && dot <= 9'd256) begin
            pixel_x = dot[7:0] - 8'd1;
            pixel_y = scanline[7:0];
        end

        frame_start = !reset && ppu_enable &&
                      scanline == 9'd0 && dot == 9'd0;
        frame_end = !reset && ppu_enable && terminal_tick;
        scanline_start = !reset && ppu_enable && dot == 9'd0;
        vblank_start = !reset && ppu_enable &&
                       scanline == 9'd241 && dot == 9'd1;
        vblank_end = !reset && ppu_enable &&
                     scanline == LAST_SCANLINE && dot == 9'd1;
        pre_render = scanline == LAST_SCANLINE;
        post_render = scanline == 9'd240;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            dot       <= 9'd0;
            scanline  <= 9'd0;
            frame_odd <= 1'b0;
            vblank    <= 1'b0;
        end else if (ppu_enable) begin
            if (terminal_tick) begin
                dot       <= 9'd0;
                scanline  <= 9'd0;
                frame_odd <= !frame_odd;
            end else if (dot == LAST_DOT) begin
                dot      <= 9'd0;
                scanline <= scanline + 9'd1;
            end else begin
                dot <= dot + 9'd1;
            end

            // Change the stored vblank state while entering the specified
            // coordinate, so the level and event agree at dots 241:1/261:1.
            if (scanline == 9'd241 && dot == 9'd0) begin
                vblank <= 1'b1;
            end else if (scanline == LAST_SCANLINE && dot == 9'd0) begin
                vblank <= 1'b0;
            end
        end
    end
endmodule
