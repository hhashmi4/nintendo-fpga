`timescale 1ns/1ps

module nes_vga_video (
    input  logic        pixel_clk,
    input  logic        reset,
    input  logic        test_pattern,
    input  logic        framebuffer_valid,
    input  logic [8:0]  framebuffer_pixel,
    output logic [15:0] framebuffer_address,
    output logic        frame_start,
    output logic        frame_end,
    output logic        line_start,
    output logic [9:0]  scan_x,
    output logic [9:0]  scan_y,
    output logic [7:0]  source_nes_x,
    output logic [7:0]  source_nes_y,
    output logic        active_video,
    output logic        hsync_n,
    output logic        vsync_n,
    output logic        blank_n,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    logic [9:0] timing_x;
    logic [9:0] timing_y;
    logic timing_active;
    logic timing_hsync_n;
    logic timing_vsync_n;
    logic timing_line_start;
    logic timing_frame_start;
    logic timing_frame_end;
    logic scaler_nes_region;
    logic [7:0] scaler_nes_x;
    logic [7:0] scaler_nes_y;

    logic [9:0] delayed_x;
    logic [9:0] delayed_y;
    logic delayed_active;
    logic delayed_hsync_n;
    logic delayed_vsync_n;
    logic delayed_nes_region;
    logic [7:0] delayed_nes_x;
    logic [7:0] delayed_nes_y;
    logic delayed_test_pattern;
    logic delayed_framebuffer_valid;
    logic [9:0] output_x;
    logic [9:0] output_y;
    logic output_active;
    logic output_hsync_n;
    logic output_vsync_n;
    logic [7:0] output_nes_x;
    logic [7:0] output_nes_y;
    logic [7:0] palette_red;
    logic [7:0] palette_green;
    logic [7:0] palette_blue;
    logic [2:0] pattern_bar;
    logic [7:0] next_red;
    logic [7:0] next_green;
    logic [7:0] next_blue;

    vga_timing timing (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .x(timing_x),
        .y(timing_y),
        .active_video(timing_active),
        .hsync_n(timing_hsync_n),
        .vsync_n(timing_vsync_n),
        .line_start(timing_line_start),
        .frame_start(timing_frame_start),
        .frame_end(timing_frame_end)
    );

    vga_nes_scaler scaler (
        .vga_x(timing_x),
        .vga_y(timing_y),
        .active_video(timing_active),
        .nes_region(scaler_nes_region),
        .nes_x(scaler_nes_x),
        .nes_y(scaler_nes_y),
        .framebuffer_address(framebuffer_address)
    );

    nes_palette_rgb palette (
        .nes_color(framebuffer_pixel[5:0]),
        .emphasis(framebuffer_pixel[8:6]),
        .red(palette_red),
        .green(palette_green),
        .blue(palette_blue)
    );

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            delayed_x <= 10'd0;
            delayed_y <= 10'd0;
            delayed_active <= 1'b0;
            delayed_hsync_n <= 1'b1;
            delayed_vsync_n <= 1'b1;
            delayed_nes_region <= 1'b0;
            delayed_nes_x <= 8'd0;
            delayed_nes_y <= 8'd0;
            delayed_test_pattern <= 1'b0;
            delayed_framebuffer_valid <= 1'b0;
            output_x <= 10'd0;
            output_y <= 10'd0;
            output_active <= 1'b0;
            output_hsync_n <= 1'b1;
            output_vsync_n <= 1'b1;
            output_nes_x <= 8'd0;
            output_nes_y <= 8'd0;
            red <= 8'd0;
            green <= 8'd0;
            blue <= 8'd0;
        end else begin
            delayed_x <= timing_x;
            delayed_y <= timing_y;
            delayed_active <= timing_active;
            delayed_hsync_n <= timing_hsync_n;
            delayed_vsync_n <= timing_vsync_n;
            delayed_nes_region <= scaler_nes_region;
            delayed_nes_x <= scaler_nes_x;
            delayed_nes_y <= scaler_nes_y;
            delayed_test_pattern <= test_pattern;
            delayed_framebuffer_valid <= framebuffer_valid;
            // A second pipeline stage registers DAC data and the matching
            // metadata. RGB then has a half pixel clock to settle before the
            // externally inverted VGA_CLK rising edge.
            output_x <= delayed_x;
            output_y <= delayed_y;
            output_active <= delayed_active;
            output_hsync_n <= delayed_hsync_n;
            output_vsync_n <= delayed_vsync_n;
            output_nes_x <= delayed_nes_x;
            output_nes_y <= delayed_nes_y;
            red <= next_red;
            green <= next_green;
            blue <= next_blue;
        end
    end

    always_comb begin
        pattern_bar = 3'((delayed_x - 10'd64) >> 6);
        next_red = 8'h00;
        next_green = 8'h00;
        next_blue = 8'h00;

        if (delayed_active && delayed_nes_region) begin
            if (delayed_test_pattern) begin
                case (pattern_bar)
                    3'd0: begin next_red = 8'hff; next_green = 8'hff; next_blue = 8'hff; end
                    3'd1: begin next_red = 8'hff; next_green = 8'hff; next_blue = 8'h00; end
                    3'd2: begin next_red = 8'h00; next_green = 8'hff; next_blue = 8'hff; end
                    3'd3: begin next_red = 8'h00; next_green = 8'hff; next_blue = 8'h00; end
                    3'd4: begin next_red = 8'hff; next_green = 8'h00; next_blue = 8'hff; end
                    3'd5: begin next_red = 8'hff; next_green = 8'h00; next_blue = 8'h00; end
                    3'd6: begin next_red = 8'h00; next_green = 8'h00; next_blue = 8'hff; end
                    default: begin
                        next_red = 8'h80;
                        next_green = 8'h80;
                        next_blue = 8'h80;
                    end
                endcase
            end else if (delayed_framebuffer_valid) begin
                next_red = palette_red;
                next_green = palette_green;
                next_blue = palette_blue;
            end
        end
    end

    assign scan_x = output_x;
    assign scan_y = output_y;
    assign source_nes_x = output_nes_x;
    assign source_nes_y = output_nes_y;
    assign active_video = output_active;
    assign hsync_n = output_hsync_n;
    assign vsync_n = output_vsync_n;
    assign blank_n = output_active;
    assign frame_start = timing_frame_start;
    assign frame_end = timing_frame_end;
    assign line_start = timing_line_start;

`ifndef SYNTHESIS
    always_ff @(posedge pixel_clk) begin
        if (!reset) begin
            assert (framebuffer_address < 16'd61440);
            if (!output_active)
                assert ({red, green, blue} == 24'h000000);
        end
    end
`endif
endmodule
