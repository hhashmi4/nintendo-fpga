`timescale 1ns/1ps

// Reusable digital scanout for a synchronous 256x240x9 NES framebuffer. RGB,
// syncs, data enable, coordinates, and boundary strobes are registered and
// aligned. Mode controls cross through two flops and take effect only between
// complete output frames. No serializer or electrical interface lives here.
module nes_720p_video (
    input  logic        pixel_clk,
    input  logic        reset,
    input  logic        test_pattern_async,
    input  logic        developer_layout_async,
    input  logic        framebuffer_valid,
    input  logic [8:0]  framebuffer_pixel,
    output logic [15:0] framebuffer_address,
    input  logic        panel_valid,
    input  logic [23:0] panel_rgb,
    output logic [9:0]  panel_x,
    output logic [9:0]  panel_y,
    output logic        panel_request,
    output logic        framebuffer_frame_end,
    output logic        frame_start,
    output logic        frame_end,
    output logic        line_start,
    output logic        line_end,
    output logic [10:0] scan_x,
    output logic [9:0]  scan_y,
    output logic [7:0]  source_nes_x,
    output logic [7:0]  source_nes_y,
    output logic        active_video,
    output logic        hsync,
    output logic        vsync,
    output logic        pixel_clock,
    output logic [23:0] rgb
);
    logic [10:0] timing_x;
    logic [9:0] timing_y;
    logic timing_active;
    logic timing_hsync, timing_vsync;
    logic timing_frame_end;
    logic scaler_nes_region, scaler_panel_region;
    logic [7:0] scaler_nes_x, scaler_nes_y;
    logic [9:0] scaler_panel_x, scaler_panel_y;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] test_pattern_sync, developer_layout_sync;
    logic active_test_pattern, active_developer_layout;

    logic [10:0] delayed_x, output_x;
    logic [9:0] delayed_y, output_y;
    logic delayed_active, delayed_hsync, delayed_vsync;
    logic delayed_nes_region, delayed_panel_region;
    logic delayed_framebuffer_valid, delayed_panel_valid;
    logic delayed_test_pattern;
    logic delayed_metadata_valid;
    logic [7:0] delayed_nes_x, delayed_nes_y;
    logic [23:0] delayed_panel_rgb;
    logic output_active, output_hsync, output_vsync;
    logic [7:0] output_nes_x, output_nes_y;
    logic [7:0] palette_red, palette_green, palette_blue;
    logic [2:0] pattern_bar;
    logic [23:0] next_rgb;

    /* verilator lint_off PINCONNECTEMPTY */
    video_720p_timing timing (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .x(timing_x),
        .y(timing_y),
        .active_video(timing_active),
        .hsync(timing_hsync),
        .vsync(timing_vsync),
        .line_start(),
        .line_end(),
        .frame_start(),
        .frame_end(timing_frame_end)
    );

    nes_720p_scaler scaler (
        .video_x(timing_x),
        .video_y(timing_y),
        .active_video(timing_active),
        .developer_layout(active_developer_layout),
        .canvas_region(),
        .nes_region(scaler_nes_region),
        .panel_region(scaler_panel_region),
        .nes_x(scaler_nes_x),
        .nes_y(scaler_nes_y),
        .panel_x(scaler_panel_x),
        .panel_y(scaler_panel_y),
        .framebuffer_address(framebuffer_address)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    nes_palette_rgb palette (
        .nes_color(framebuffer_pixel[5:0]),
        .emphasis(framebuffer_pixel[8:6]),
        .red(palette_red),
        .green(palette_green),
        .blue(palette_blue)
    );

    always_comb begin
        if (delayed_x < 11'd280) pattern_bar = 3'd0;
        else if (delayed_x < 11'd400) pattern_bar = 3'd1;
        else if (delayed_x < 11'd520) pattern_bar = 3'd2;
        else if (delayed_x < 11'd640) pattern_bar = 3'd3;
        else if (delayed_x < 11'd760) pattern_bar = 3'd4;
        else if (delayed_x < 11'd880) pattern_bar = 3'd5;
        else if (delayed_x < 11'd1000) pattern_bar = 3'd6;
        else pattern_bar = 3'd7;
        next_rgb = 24'h000000;
        if (delayed_active && delayed_nes_region) begin
            if (delayed_test_pattern) begin
                case (pattern_bar)
                    3'd0: next_rgb = 24'hffffff;
                    3'd1: next_rgb = 24'hffff00;
                    3'd2: next_rgb = 24'h00ffff;
                    3'd3: next_rgb = 24'h00ff00;
                    3'd4: next_rgb = 24'hff00ff;
                    3'd5: next_rgb = 24'hff0000;
                    3'd6: next_rgb = 24'h0000ff;
                    default: next_rgb = 24'h808080;
                endcase
            end else if (delayed_framebuffer_valid) begin
                next_rgb = {palette_red, palette_green, palette_blue};
            end
        end else if (delayed_active && delayed_panel_region &&
                     delayed_panel_valid) begin
            next_rgb = delayed_panel_rgb;
        end
    end

    always_ff @(posedge pixel_clk) begin
        test_pattern_sync <= {test_pattern_sync[0], test_pattern_async};
        developer_layout_sync <= {developer_layout_sync[0],
                                  developer_layout_async};

        if (reset) begin
            test_pattern_sync <= 2'b00;
            developer_layout_sync <= 2'b00;
            active_test_pattern <= 1'b0;
            active_developer_layout <= 1'b0;
            delayed_x <= 11'd0;
            delayed_y <= 10'd0;
            delayed_active <= 1'b0;
            delayed_hsync <= 1'b0;
            delayed_vsync <= 1'b0;
            delayed_nes_region <= 1'b0;
            delayed_panel_region <= 1'b0;
            delayed_framebuffer_valid <= 1'b0;
            delayed_panel_valid <= 1'b0;
            delayed_test_pattern <= 1'b0;
            delayed_metadata_valid <= 1'b0;
            delayed_nes_x <= 8'd0;
            delayed_nes_y <= 8'd0;
            delayed_panel_rgb <= 24'd0;
            output_x <= 11'd0;
            output_y <= 10'd0;
            output_active <= 1'b0;
            output_hsync <= 1'b0;
            output_vsync <= 1'b0;
            output_nes_x <= 8'd0;
            output_nes_y <= 8'd0;
            line_start <= 1'b0;
            line_end <= 1'b0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            rgb <= 24'd0;
        end else begin
            if (timing_frame_end) begin
                active_test_pattern <= test_pattern_sync[1];
                active_developer_layout <= developer_layout_sync[1];
            end

            delayed_x <= timing_x;
            delayed_y <= timing_y;
            delayed_active <= timing_active;
            delayed_hsync <= timing_hsync;
            delayed_vsync <= timing_vsync;
            delayed_nes_region <= scaler_nes_region;
            delayed_panel_region <= scaler_panel_region;
            delayed_framebuffer_valid <= framebuffer_valid;
            delayed_panel_valid <= panel_valid;
            delayed_test_pattern <= active_test_pattern;
            delayed_metadata_valid <= 1'b1;
            delayed_nes_x <= scaler_nes_x;
            delayed_nes_y <= scaler_nes_y;
            delayed_panel_rgb <= panel_rgb;

            output_x <= delayed_x;
            output_y <= delayed_y;
            output_active <= delayed_active;
            output_hsync <= delayed_hsync;
            output_vsync <= delayed_vsync;
            output_nes_x <= delayed_nes_x;
            output_nes_y <= delayed_nes_y;
            line_start <= delayed_metadata_valid && delayed_x == 11'd0;
            line_end <= delayed_metadata_valid && delayed_x == 11'd1649;
            frame_start <= delayed_metadata_valid && delayed_x == 11'd0 &&
                           delayed_y == 10'd0;
            frame_end <= delayed_metadata_valid && delayed_x == 11'd1649 &&
                         delayed_y == 10'd749;
            rgb <= next_rgb;
        end
    end

    assign panel_x = scaler_panel_x;
    assign panel_y = scaler_panel_y;
    assign panel_request = scaler_panel_region;
    assign framebuffer_frame_end = timing_frame_end;
    assign scan_x = output_x;
    assign scan_y = output_y;
    assign source_nes_x = output_nes_x;
    assign source_nes_y = output_nes_y;
    assign active_video = output_active;
    assign hsync = output_hsync;
    assign vsync = output_vsync;
    assign pixel_clock = pixel_clk;

`ifndef SYNTHESIS
    always_ff @(posedge pixel_clk) begin
        if (!reset) begin
            assert (framebuffer_address < 16'd61440);
            if (!output_active)
                assert (rgb == 24'h000000);
            if (frame_start)
                assert (active_video);
        end
    end
`endif
endmodule
