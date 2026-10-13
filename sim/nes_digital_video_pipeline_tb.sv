`timescale 1ns/1ps

module nes_digital_video_pipeline_tb;
    logic source_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic source_reset = 1'b1;
    logic pixel_reset = 1'b1;
    logic source_frame_start = 1'b0;
    logic source_pixel_valid = 1'b0;
    logic [7:0] source_pixel_x = 8'd0;
    logic [7:0] source_pixel_y = 8'd0;
    logic [5:0] source_pixel_color = 6'd0;
    logic [2:0] source_pixel_emphasis = 3'd0;
    logic capture_freeze = 1'b0;
    logic test_pattern_async = 1'b0;
    logic developer_layout_async = 1'b0;
    logic panel_valid = 1'b1;
    logic [23:0] panel_rgb = 24'h123456;
    logic [9:0] panel_x, panel_y;
    logic panel_request;
    logic [23:0] rgb;
    logic hsync, vsync, active_video, video_pixel_clock;
    logic frame_start, frame_end, line_start, line_end;
    logic [10:0] scan_x;
    logic [9:0] scan_y;
    logic [7:0] source_nes_x, source_nes_y;
    logic capture_active, capture_complete, capture_pending;
    logic [1:0] capture_write_bank, display_bank;
    logic [15:0] captured_frames, displayed_frames;
    logic write_range_error, write_sequence_error;
    logic display_valid, swap_complete;
    longint unsigned checked_game_pixels;
    longint unsigned checked_border_pixels;
    longint unsigned checked_panel_pixels;
    integer artifact;

    always #10 source_clk = !source_clk;
    always #6.734 pixel_clk = !pixel_clk;

    nes_digital_video_pipeline dut (
        .source_clk(source_clk),
        .source_reset(source_reset),
        .source_frame_start(source_frame_start),
        .source_pixel_valid(source_pixel_valid),
        .source_pixel_x(source_pixel_x),
        .source_pixel_y(source_pixel_y),
        .source_pixel_color(source_pixel_color),
        .source_pixel_emphasis(source_pixel_emphasis),
        .capture_freeze(capture_freeze),
        .pixel_clk(pixel_clk),
        .pixel_reset(pixel_reset),
        .test_pattern_async(test_pattern_async),
        .developer_layout_async(developer_layout_async),
        .panel_valid(panel_valid),
        .panel_rgb(panel_rgb),
        .panel_x(panel_x),
        .panel_y(panel_y),
        .panel_request(panel_request),
        .rgb(rgb),
        .hsync(hsync),
        .vsync(vsync),
        .active_video(active_video),
        .video_pixel_clock(video_pixel_clock),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .line_start(line_start),
        .line_end(line_end),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .source_nes_x(source_nes_x),
        .source_nes_y(source_nes_y),
        .capture_active(capture_active),
        .capture_complete(capture_complete),
        .capture_pending(capture_pending),
        .capture_write_bank(capture_write_bank),
        .captured_frames(captured_frames),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .display_valid(display_valid),
        .swap_complete(swap_complete),
        .display_bank(display_bank),
        .displayed_frames(displayed_frames)
    );

    task automatic write_uniform_frame(input logic [5:0] color);
        integer address;
        begin
            for (address = 0; address < 61440; address = address + 1) begin
                @(negedge source_clk);
                source_frame_start = address == 0;
                source_pixel_valid = 1'b1;
                source_pixel_x = 8'(address & 255);
                source_pixel_y = 8'(address >> 8);
                source_pixel_color = color;
                source_pixel_emphasis = 3'd0;
            end
            @(negedge source_clk);
            source_frame_start = 1'b0;
            source_pixel_valid = 1'b0;
        end
    endtask

    task automatic check_normal_frame(input logic [23:0] expected_rgb);
        logic done;
        begin
            done = 1'b0;
            while (!frame_start)
                @(negedge pixel_clk);
            while (!done) begin
                if (active_video) begin
                    if (scan_x >= 160 && scan_x < 1120) begin
                        if (rgb !== expected_rgb)
                            $fatal(1, "game RGB mismatch at %0d,%0d: %h",
                                   scan_x, scan_y, rgb);
                        checked_game_pixels += 1;
                    end else begin
                        if (rgb !== 24'h000000)
                            $fatal(1, "pillarbox was not black");
                        checked_border_pixels += 1;
                    end
                end else if (rgb !== 24'h000000) begin
                    $fatal(1, "blanking RGB was not black");
                end
                done = frame_end;
                @(negedge pixel_clk);
            end
        end
    endtask

    task automatic check_developer_frame(input logic [23:0] expected_rgb);
        logic done;
        begin
            done = 1'b0;
            while (!frame_start)
                @(negedge pixel_clk);
            while (!done) begin
                if (active_video && scan_x >= 160 && scan_x < 928) begin
                    if (rgb !== expected_rgb)
                        $fatal(1, "Developer Mode game RGB mismatch");
                    checked_game_pixels += 1;
                end else if (active_video && scan_x >= 928 && scan_x < 1120) begin
                    if (rgb !== 24'h123456)
                        $fatal(1, "Developer Mode panel RGB mismatch");
                    checked_panel_pixels += 1;
                end else if (active_video) begin
                    if (rgb !== 24'h000000)
                        $fatal(1, "Developer Mode pillarbox was not black");
                    checked_border_pixels += 1;
                end
                done = frame_end;
                @(negedge pixel_clk);
            end
        end
    endtask

    initial begin
        checked_game_pixels = 0;
        checked_border_pixels = 0;
        checked_panel_pixels = 0;
        repeat (5) @(posedge source_clk);
        source_reset = 1'b0;
        repeat (7) @(posedge pixel_clk);
        pixel_reset = 1'b0;
        // Content ownership releases synchronously in both domains. Preserve
        // the same two complete frame transactions after that startup barrier.
        repeat (4) @(negedge source_clk);

        fork
            begin
                write_uniform_frame(6'h01);
                write_uniform_frame(6'h21);
            end
            begin
                wait (display_valid);
                check_normal_frame(24'h001c95);
                // Change layout in the middle of a frame. It must not affect
                // that frame and is sampled only at the next boundary.
                fork
                    begin
                        wait (scan_y == 10'd300 && scan_x == 11'd400);
                        developer_layout_async = 1'b1;
                    end
                    check_normal_frame(24'h57a5ff);
                join
                check_developer_frame(24'h57a5ff);
            end
        join

        if (captured_frames != 2 || displayed_frames != 2)
            $fatal(1, "unexpected capture/display counts: %0d/%0d",
                   captured_frames, displayed_frames);
        if (write_range_error || write_sequence_error)
            $fatal(1, "unexpected framebuffer error status");
        if (checked_game_pixels != 2 * 960 * 720 + 768 * 720 ||
            checked_border_pixels != 3 * 320 * 720 ||
            checked_panel_pixels != 192 * 720)
            $fatal(1, "unexpected checked-region totals");

        artifact = $fopen("build/sim/phase6b_shared_video_rtl.txt", "a");
        $fwrite(artifact, "PIPELINE %0d %0d %0d %0d %0d\n",
                captured_frames, displayed_frames, checked_game_pixels,
                checked_border_pixels, checked_panel_pixels);
        $fclose(artifact);
        if ($test$plusargs("phase6g_reset")) begin : reset_epochs
            logic [10:0] before_x;
            for (integer epoch = 0; epoch < 6; epoch++) begin
                // Reset one endpoint while both a displayed and partial
                // source frame exist. Either reset must revoke all ownership.
                @(negedge source_clk);
                source_frame_start = 1;
                source_pixel_valid = 1;
                source_pixel_x = 0; source_pixel_y = 0;
                @(negedge source_clk);
                source_frame_start = 0; source_pixel_valid = 0;
                before_x = scan_x;
                if (epoch % 2 == 0) source_reset = 1;
                else pixel_reset = 1;
                repeat (8) @(negedge source_clk);
                if (display_valid || capture_active || capture_pending || captured_frames != 0)
                    $fatal(1, "Phase6G content reset failed epoch=%0d", epoch);
                if (epoch % 2 == 0 && scan_x == before_x)
                    $fatal(1, "source reset stopped video timing");
                source_reset = 0; pixel_reset = 0;
                repeat (8) @(negedge source_clk);
                write_uniform_frame(6'h21);
                wait (display_valid);
                if (captured_frames != 1 || displayed_frames != 1 ||
                    write_range_error || write_sequence_error)
                    $fatal(1, "Phase6G reset recovery failed epoch=%0d", epoch);
                // A new display bank must still hold the entire recovered image.
                check_developer_frame(24'h57a5ff);
            end
            $display("PASS: Phase6G asynchronous content reset epochs=6 mismatches=0");
        end
        $display("PASS: asynchronous pipeline displayed two atomic frames and Developer Mode");
        $finish;
    end
endmodule
