`timescale 1ns/1ps

module hdmi_rgb_output_tb;
    logic pixel_clk = 1'b0;
    logic pixel_reset = 1'b1;
    logic video_enable_async = 1'b0;
    logic developer_layout_async = 1'b0;
    logic [15:0] framebuffer_address;
    logic [9:0] panel_x, panel_y;
    logic panel_request;
    logic pipeline_frame_start, pipeline_frame_end;
    logic pipeline_line_start, pipeline_line_end;
    logic [10:0] scan_x;
    logic [9:0] scan_y;
    logic [7:0] source_nes_x, source_nes_y;
    logic pipeline_de, pipeline_hsync, pipeline_vsync;
    logic pipeline_pixel_clock;
    logic [23:0] pipeline_rgb;
    logic tx_pixel_clock;
    logic [23:0] tx_rgb;
    logic tx_hsync, tx_vsync, tx_data_enable, tx_frame_start;
    logic frame_toggle;
    logic previous_frame_toggle;
    integer failures = 0;
    integer output_frames = 0;
    integer pixels_in_frame = 0;
    integer active_pixels = 0;
    integer hsync_pixels = 0;
    integer vsync_pixels = 0;
    integer pillar_pixels = 0;
    logic developer_panel_seen = 1'b0;
    logic sampling_started = 1'b0;
    integer metrics_file;

    always #7 pixel_clk = !pixel_clk;

    /* verilator lint_off PINCONNECTEMPTY */
    nes_720p_video video (
        .pixel_clk(pixel_clk),
        .reset(pixel_reset),
        .test_pattern_async(1'b0),
        .developer_layout_async(developer_layout_async),
        .framebuffer_valid(1'b1),
        .framebuffer_pixel(9'b000000001),
        .framebuffer_address(framebuffer_address),
        .panel_valid(1'b1),
        .panel_rgb(24'h00aa55),
        .panel_x(panel_x),
        .panel_y(panel_y),
        .panel_request(panel_request),
        .framebuffer_frame_end(),
        .frame_start(pipeline_frame_start),
        .frame_end(pipeline_frame_end),
        .line_start(pipeline_line_start),
        .line_end(pipeline_line_end),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .source_nes_x(source_nes_x),
        .source_nes_y(source_nes_y),
        .active_video(pipeline_de),
        .hsync(pipeline_hsync),
        .vsync(pipeline_vsync),
        .pixel_clock(pipeline_pixel_clock),
        .rgb(pipeline_rgb)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    hdmi_rgb_output adapter (
        .pixel_clk(pixel_clk),
        .pixel_reset(pixel_reset),
        .video_enable_async(video_enable_async),
        .pipeline_rgb(pipeline_rgb),
        .pipeline_hsync(pipeline_hsync),
        .pipeline_vsync(pipeline_vsync),
        .pipeline_de(pipeline_de),
        .pipeline_frame_start(pipeline_frame_start),
        .tx_pixel_clock(tx_pixel_clock),
        .tx_rgb(tx_rgb),
        .tx_hsync(tx_hsync),
        .tx_vsync(tx_vsync),
        .tx_data_enable(tx_data_enable),
        .tx_frame_start(tx_frame_start),
        .frame_toggle(frame_toggle)
    );

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL: %s at x=%0d y=%0d frame=%0d",
                     message, scan_x, scan_y, output_frames);
            failures = failures + 1;
        end
    endtask

    always @(posedge tx_pixel_clock) begin
        if (!pixel_reset && !sampling_started) begin
            if (tx_frame_start) begin
                sampling_started = 1'b1;
                output_frames = 1;
                previous_frame_toggle = frame_toggle;
            end
        end else if (!pixel_reset && video_enable_async) begin
            check(tx_hsync == (scan_x >= 11'd1390 && scan_x < 11'd1430),
                  "HSYNC is aligned to RGB coordinates");
            check(tx_vsync == (scan_y >= 10'd725 && scan_y < 10'd730),
                  "VSYNC is aligned to RGB coordinates");
            check(tx_data_enable == (scan_x < 11'd1280 && scan_y < 10'd720),
                  "DE is aligned to active-video coordinates");
            check(pipeline_line_start == (scan_x == 0),
                  "line-start metadata remains aligned");
            check(pipeline_line_end == (scan_x == 1649),
                  "line-end metadata remains aligned");
            check(pipeline_frame_end ==
                  (scan_x == 1649 && scan_y == 749),
                  "frame-end metadata remains aligned");
            if (tx_data_enable) active_pixels = active_pixels + 1;
            if (tx_hsync) hsync_pixels = hsync_pixels + 1;
            if (tx_vsync) vsync_pixels = vsync_pixels + 1;
            if (tx_data_enable &&
                (scan_x < 11'd160 || scan_x >= 11'd1120)) begin
                pillar_pixels = pillar_pixels + 1;
                check(tx_rgb == 24'h000000, "4:3 pillarbox remains black");
            end
            if (!tx_data_enable)
                check(tx_rgb == 24'h000000, "blanking RGB is black");
            if (developer_layout_async && output_frames >= 5 &&
                scan_x == 11'd928 && scan_y == 10'd0) begin
                check(tx_rgb == 24'h00aa55,
                      "Developer Mode panel reaches transmitter unchanged");
                check(panel_request, "Developer Mode panel request is active");
                developer_panel_seen = 1'b1;
            end
            if (tx_data_enable && scan_x == 11'd160) begin
                check(source_nes_x == 0 &&
                      10'(source_nes_y) == scan_y / 3,
                      "NES source coordinates remain aligned");
            end
            pixels_in_frame = pixels_in_frame + 1;
            if (tx_frame_start) begin
                check(pixels_in_frame == 1_237_500,
                      "exact 1650x750 frame length");
                check(active_pixels == 1280 * 720,
                      "exact active pixel count");
                check(hsync_pixels == 40 * 750,
                      "exact HSYNC width across frame");
                check(vsync_pixels == 5 * 1650,
                      "exact VSYNC duration across frame");
                check(pillar_pixels == 2 * 160 * 720,
                      "exact normal-mode black borders");
                check(frame_toggle != previous_frame_toggle,
                      "one frame toggle per transmitted frame");
                previous_frame_toggle = frame_toggle;
                output_frames = output_frames + 1;
                pixels_in_frame = 0;
                active_pixels = 0;
                hsync_pixels = 0;
                vsync_pixels = 0;
                pillar_pixels = 0;
            end
        end
    end

    initial begin
        previous_frame_toggle = 1'b0;
        repeat (5) @(posedge pixel_clk);
        pixel_reset = 1'b0;
        video_enable_async = 1'b1;
        wait (output_frames == 4);
        developer_layout_async = 1'b1;
        // Ten complete frames exercise both layouts across every raster edge.
        wait (output_frames == 11);
        check(developer_panel_seen, "Developer Mode panel was sampled");
        check(framebuffer_address < 16'd61440,
              "framebuffer address remains bounded");
        check(panel_x >= 10'd512 && panel_x < 10'd640,
              "panel coordinate remains bounded");
        check(panel_y < 10'd480, "panel row remains bounded");
        check(pipeline_pixel_clock == pixel_clk,
              "Phase 6B clock remains unchanged");
        video_enable_async = 1'b0;
        repeat (4) @(posedge pixel_clk);
        @(posedge tx_pixel_clock);
        check(!tx_data_enable && tx_rgb == 0,
              "safe disable removes active video");

        metrics_file = $fopen("build/sim/phase6c_hdmi_rgb_rtl.txt", "w");
        check(metrics_file != 0, "open RGB RTL/model comparison metrics");
        $fdisplay(metrics_file, "frames=%0d", 10);
        $fdisplay(metrics_file, "frame_pixels=%0d", 1_237_500);
        $fdisplay(metrics_file, "active_pixels=%0d", 1280 * 720);
        $fdisplay(metrics_file, "hsync_pixels=%0d", 40 * 750);
        $fdisplay(metrics_file, "vsync_pixels=%0d", 5 * 1650);
        $fdisplay(metrics_file, "pillar_pixels=%0d", 2 * 160 * 720);
        $fclose(metrics_file);

        if (failures == 0) begin
            $display("Phase 6C ten-frame RGB/sync/DE/border/Developer test passed");
            $finish;
        end else begin
            $fatal(1, "Phase 6C RGB output test failed: %0d checks", failures);
        end
    end
endmodule
