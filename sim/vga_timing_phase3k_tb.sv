`timescale 1ns/1ps

module vga_timing_phase3k_tb;
    logic pixel_clk = 1'b0;
    logic reset = 1'b1;
    logic [9:0] x;
    logic [9:0] y;
    logic active_video;
    logic hsync_n;
    logic vsync_n;
    logic line_start;
    logic frame_start;
    logic frame_end;
    integer active_count;
    integer hsync_low_count;
    integer vsync_low_count;
    integer line_count;
    integer frame_start_count;
    integer frame_end_count;

    always #20 pixel_clk <= !pixel_clk;

    vga_timing dut (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .x(x),
        .y(y),
        .active_video(active_video),
        .hsync_n(hsync_n),
        .vsync_n(vsync_n),
        .line_start(line_start),
        .frame_start(frame_start),
        .frame_end(frame_end)
    );

    task automatic reset_at(input logic [9:0] target_x,
                            input logic [9:0] target_y);
        begin
            while (!(x == target_x && y == target_y))
                @(negedge pixel_clk);
            reset = 1'b1;
            repeat (3) @(posedge pixel_clk);
            @(negedge pixel_clk);
            assert (x == 0 && y == 0 && hsync_n && vsync_n);
            reset = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge pixel_clk);
        reset = 1'b0;

        // Active picture, horizontal blanking, and vertical blanking resets.
        reset_at(100, 100);
        reset_at(700, 100);
        reset_at(100, 500);

        active_count = 0;
        hsync_low_count = 0;
        vsync_low_count = 0;
        line_count = 0;
        frame_start_count = 0;
        frame_end_count = 0;
        while (!frame_start)
            @(negedge pixel_clk);
        for (integer sample = 0; sample < 420000; sample = sample + 1) begin
            if (active_video) active_count = active_count + 1;
            if (!hsync_n) hsync_low_count = hsync_low_count + 1;
            if (!vsync_n) vsync_low_count = vsync_low_count + 1;
            if (line_start) line_count = line_count + 1;
            if (frame_start) frame_start_count = frame_start_count + 1;
            if (frame_end) frame_end_count = frame_end_count + 1;
            @(negedge pixel_clk);
        end
        assert (active_count == 640 * 480);
        assert (hsync_low_count == 96 * 525);
        assert (vsync_low_count == 2 * 800);
        assert (line_count == 525);
        assert (frame_start_count == 1 && frame_end_count == 1);
        assert (x == 0 && y == 0 && hsync_n && vsync_n);
        $display("Phase 3K VGA timing/reset test passed");
        $display("pixels=420000 active=%0d hsync_low=%0d vsync_low=%0d lines=%0d",
                 active_count, hsync_low_count, vsync_low_count, line_count);
        $finish;
    end
endmodule
