`timescale 1ns/1ps

module vga_phase3k_tb;
    logic write_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic write_reset = 1'b1;
    logic read_reset = 1'b1;
    logic write_frame_start = 1'b0;
    logic write_valid = 1'b0;
    logic [7:0] write_x = 8'd0;
    logic [7:0] write_y = 8'd0;
    logic [5:0] write_color = 6'd0;
    logic [2:0] write_emphasis = 3'd0;
    logic test_pattern = 1'b0;
    logic capture_complete;
    logic capture_pending;
    logic [15:0] captured_frames;
    logic write_range_error;
    logic write_sequence_error;
    logic [15:0] framebuffer_address;
    logic [8:0] framebuffer_pixel;
    logic display_valid;
    logic frame_end;
    logic [1:0] read_bank;
    logic [15:0] displayed_frames;
    logic [9:0] scan_x;
    logic [9:0] scan_y;
    logic active_video;
    logic blank_n;
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;
    integer trace_file;
    integer compared_pixels = 0;
    integer diagnostic_pixels = 0;

    always #10 write_clk <= !write_clk;
    always #20 pixel_clk <= !pixel_clk;

    /* verilator lint_off PINCONNECTEMPTY */
    nes_framebuffer framebuffer (
        .write_clk(write_clk),
        .write_reset(write_reset),
        .write_frame_start(write_frame_start),
        .write_valid(write_valid),
        .write_x(write_x),
        .write_y(write_y),
        .write_color(write_color),
        .write_emphasis(write_emphasis),
        .capture_freeze(1'b0),
        .capture_active(),
        .capture_complete(capture_complete),
        .capture_pending(capture_pending),
        .write_bank(),
        .captured_frames(captured_frames),
        .write_range_error(write_range_error),
        .write_sequence_error(write_sequence_error),
        .read_clk(pixel_clk),
        .read_reset(read_reset),
        .read_frame_end(frame_end),
        .read_address(framebuffer_address),
        .read_pixel(framebuffer_pixel),
        .display_valid(display_valid),
        .swap_complete(),
        .read_bank(read_bank),
        .displayed_frames(displayed_frames)
    );

    nes_vga_video video (
        .pixel_clk(pixel_clk),
        .reset(read_reset),
        .test_pattern(test_pattern),
        .framebuffer_valid(display_valid),
        .framebuffer_pixel(framebuffer_pixel),
        .framebuffer_address(framebuffer_address),
        .frame_start(),
        .frame_end(frame_end),
        .line_start(),
        .scan_x(scan_x),
        .scan_y(scan_y),
        .source_nes_x(),
        .source_nes_y(),
        .active_video(active_video),
        .hsync_n(),
        .vsync_n(),
        .blank_n(blank_n),
        .red(red),
        .green(green),
        .blue(blue)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    task automatic publish_frame(input integer variant);
        integer x;
        integer y;
        begin
            @(negedge write_clk);
            write_frame_start = 1'b1;
            @(posedge write_clk);
            @(negedge write_clk);
            write_frame_start = 1'b0;
            for (y = 0; y < 240; y = y + 1) begin
                for (x = 0; x < 256; x = x + 1) begin
                    write_valid = 1'b1;
                    write_x = 8'(x);
                    write_y = 8'(y);
                    if (variant == 0) begin
                        write_color = 6'((x ^ y) & 63);
                        write_emphasis = 3'((x >> 5) & 7);
                    end else begin
                        write_color = 6'((x + 3 * y) & 63);
                        write_emphasis = 3'((y >> 5) & 7);
                    end
                    @(posedge write_clk);
                    @(negedge write_clk);
                end
            end
            write_valid = 1'b0;
            assert (capture_complete)
                else $fatal(1, "frame did not complete on final pixel");
        end
    endtask

    task automatic trace_active_frame(input integer mode);
        integer x;
        integer y;
        begin
            do @(negedge pixel_clk);
            while (!(active_video && scan_x == 0 && scan_y == 0));
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    assert (active_video && scan_x == 10'(x) &&
                            scan_y == 10'(y))
                        else $fatal(1, "active sequence error at %0d,%0d got %0d,%0d",
                                    x, y, scan_x, scan_y);
                    assert (blank_n)
                        else $fatal(1, "blank asserted inside active video");
                    $fwrite(trace_file, "%0d %0d %0d %02x%02x%02x\n",
                            mode, x, y, red, green, blue);
                    if (mode == 0)
                        compared_pixels = compared_pixels + 1;
                    else
                        diagnostic_pixels = diagnostic_pixels + 1;
                    if (x != 639)
                        @(negedge pixel_clk);
                    else if (y != 479) begin
                        do @(negedge pixel_clk);
                        while (!(active_video && scan_x == 0 &&
                                 scan_y == 10'(y + 1)));
                    end
                end
            end
        end
    endtask

    initial begin
        logic [1:0] previous_bank;
        integer verified_captures;
        integer verified_displays;

        $dumpfile("build/sim/vga_phase3k.fst");
        $dumpvars(0, vga_phase3k_tb);
        trace_file = $fopen("build/sim/vga_phase3k_pixels.txt", "w");
        assert (trace_file != 0) else $fatal(1, "could not open VGA trace");

        repeat (6) @(posedge write_clk);
        write_reset = 1'b0;
        repeat (4) @(posedge pixel_clk);
        read_reset = 1'b0;

        publish_frame(0);
        wait (display_valid);
        trace_active_frame(0);
        assert (compared_pixels == 307200);
        assert (!write_range_error && !write_sequence_error);

        // Publish the other bank while VGA owns the first. Ownership must not
        // change until the next frame-end handshake.
        previous_bank = read_bank;
        publish_frame(1);
        assert (capture_pending);
        while (!frame_end) begin
            @(negedge pixel_clk);
            assert (read_bank == previous_bank)
                else $fatal(1, "framebuffer bank changed before frame end");
        end
        @(negedge pixel_clk);
        assert (read_bank != previous_bank);
        wait (!capture_pending);

        test_pattern = 1'b1;
        trace_active_frame(1);
        assert (diagnostic_pixels == 307200);
        assert (captured_frames == 16'd2);
        assert (displayed_frames == 16'd2);
        assert (!write_range_error && !write_sequence_error);
        verified_captures = int'(captured_frames);
        verified_displays = int'(displayed_frames);

        // Reset both domains during an in-progress NES frame capture. The
        // partial bank must never become display-valid after reset.
        @(negedge write_clk);
        write_frame_start = 1'b1;
        @(posedge write_clk);
        @(negedge write_clk);
        write_frame_start = 1'b0;
        write_valid = 1'b1;
        write_y = 8'd0;
        for (integer reset_x = 0; reset_x < 100; reset_x = reset_x + 1) begin
            write_x = 8'(reset_x);
            write_color = 6'(reset_x & 63);
            @(posedge write_clk);
            @(negedge write_clk);
        end
        write_valid = 1'b0;
        write_reset = 1'b1;
        read_reset = 1'b1;
        repeat (4) @(posedge write_clk);
        repeat (3) @(posedge pixel_clk);
        assert (!display_valid && captured_frames == 0 && displayed_frames == 0);
        assert (scan_x == 0 && scan_y == 0 && !active_video);

        $fclose(trace_file);
        $display("Phase 3K static framebuffer/VGA pipeline passed");
        $display("framebuffer_pixels=%0d diagnostic_pixels=%0d captured=%0d displayed=%0d",
                 compared_pixels, diagnostic_pixels,
                 verified_captures, verified_displays);
        $finish;
    end
endmodule
