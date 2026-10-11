`timescale 1ns/1ps

module video_720p_timing_tb;
    localparam int unsigned FRAME_PIXELS = 1650 * 750;

    logic pixel_clk = 1'b0;
    logic reset = 1'b1;
    logic [10:0] x;
    logic [9:0] y;
    logic active_video, hsync, vsync;
    logic line_start, line_end, frame_start, frame_end;
    longint unsigned active_count, hsync_count, vsync_count;
    longint unsigned line_start_count, line_end_count;
    longint unsigned frame_start_count, frame_end_count;
    integer artifact;
    integer index;

    always #1 pixel_clk = !pixel_clk;

    video_720p_timing dut (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .x(x),
        .y(y),
        .active_video(active_video),
        .hsync(hsync),
        .vsync(vsync),
        .line_start(line_start),
        .line_end(line_end),
        .frame_start(frame_start),
        .frame_end(frame_end)
    );

    initial begin
        repeat (3) @(posedge pixel_clk);
        @(negedge pixel_clk);
        reset = 1'b0;

        active_count = 0;
        hsync_count = 0;
        vsync_count = 0;
        line_start_count = 0;
        line_end_count = 0;
        frame_start_count = 0;
        frame_end_count = 0;

        for (index = 0; index < FRAME_PIXELS; index = index + 1) begin
            if (x !== 11'(index % 1650) || y !== 10'(index / 1650))
                $fatal(1, "timing coordinate mismatch at pixel %0d", index);
            if (active_video) active_count += 1;
            if (hsync) hsync_count += 1;
            if (vsync) vsync_count += 1;
            if (line_start) line_start_count += 1;
            if (line_end) line_end_count += 1;
            if (frame_start) frame_start_count += 1;
            if (frame_end) frame_end_count += 1;
            @(negedge pixel_clk);
        end

        if ({x, y} !== {11'd0, 10'd0})
            $fatal(1, "timing did not wrap at one complete frame");
        if (active_count != 1280 * 720 || hsync_count != 40 * 750 ||
            vsync_count != 5 * 1650 || line_start_count != 750 ||
            line_end_count != 750 || frame_start_count != 1 ||
            frame_end_count != 1)
            $fatal(1, "720p timing pulse counts are incorrect");

        reset = 1'b1;
        repeat (2) @(posedge pixel_clk);
        @(negedge pixel_clk);
        if ({x, y} !== {11'd0, 10'd0})
            $fatal(1, "reset did not restore the frame origin");

        artifact = $fopen("build/sim/phase6b_shared_video_rtl.txt", "w");
        $fwrite(artifact, "TIMING %0d %0d %0d %0d %0d %0d %0d %0d\n",
                FRAME_PIXELS, active_count, hsync_count, vsync_count,
                line_start_count, line_end_count, frame_start_count,
                frame_end_count);
        $fclose(artifact);
        $display("PASS: 720p timing checked across %0d pixels", FRAME_PIXELS);
        $finish;
    end
endmodule
