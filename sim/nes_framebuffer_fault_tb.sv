`timescale 1ns/1ps

module nes_framebuffer_fault_tb;
    logic write_clk = 1'b0;
    logic read_clk = 1'b0;
    logic write_reset = 1'b1;
    logic read_reset = 1'b1;
    logic write_frame_start = 1'b0;
    logic write_valid = 1'b0;
    logic [7:0] write_x = 8'd0;
    logic [7:0] write_y = 8'd0;
    logic [5:0] write_color = 6'd0;
    logic [2:0] write_emphasis = 3'd0;
    logic capture_freeze = 1'b0;
    logic capture_active, capture_complete, capture_pending;
    logic [1:0] write_bank, read_bank;
    logic [15:0] captured_frames, displayed_frames;
    logic write_range_error, write_sequence_error;
    logic read_frame_end = 1'b0;
    logic [15:0] read_address = 16'd0;
    logic [8:0] read_pixel;
    logic display_valid, swap_complete;

    always #5 write_clk = !write_clk;
    always #7 read_clk = !read_clk;

    nes_framebuffer dut (.*);

    task automatic write_sample(
        input logic start,
        input logic [7:0] x,
        input logic [7:0] y
    );
        begin
            @(negedge write_clk);
            write_frame_start = start;
            write_valid = 1'b1;
            write_x = x;
            write_y = y;
            @(negedge write_clk);
            write_frame_start = 1'b0;
            write_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge write_clk);
        write_reset = 1'b0;
        repeat (3) @(posedge read_clk);
        read_reset = 1'b0;

        capture_freeze = 1'b1;
        write_sample(1'b1, 8'd0, 8'd0);
        if (capture_active || captured_frames != 0)
            $fatal(1, "capture freeze accepted a frame");

        capture_freeze = 1'b0;
        write_sample(1'b1, 8'd0, 8'd0);
        write_sample(1'b0, 8'd2, 8'd0);
        write_sample(1'b0, 8'd0, 8'd240);
        if (!write_sequence_error || !write_range_error)
            $fatal(1, "fault status did not latch");
        if (display_valid || captured_frames != 0 || displayed_frames != 0)
            $fatal(1, "a partial or invalid frame became visible");

        write_reset = 1'b1;
        repeat (2) @(posedge write_clk);
        write_reset = 1'b0;
        @(posedge write_clk);
        if (capture_active || write_sequence_error || write_range_error ||
            captured_frames != 0)
            $fatal(1, "write reset did not clear partial/error state");

        read_reset = 1'b1;
        repeat (2) @(posedge read_clk);
        read_reset = 1'b0;
        @(posedge read_clk);
        if (display_valid || swap_complete || displayed_frames != 0)
            $fatal(1, "read reset did not clear display state");

        $display("PASS: framebuffer freeze, partial-frame reset, and fault latches checked");
        $finish;
    end
endmodule
