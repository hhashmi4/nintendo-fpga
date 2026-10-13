`timescale 1ns/1ps

// Malformed inputs intentionally exercise the synthesizable error path.
// Checks use $fatal independently of the normal DUT input assertions.
module phase6g_frame_recovery_tb;
    logic write_clk = 0, read_clk = 0;
    logic write_reset = 1, read_reset;
    logic write_frame_start = 0, write_valid = 0, capture_freeze = 0;
    logic [7:0] write_x = 0, write_y = 0;
    logic [5:0] write_color;
    logic [2:0] write_emphasis;
    logic capture_active, capture_complete, capture_pending;
    logic [1:0] write_bank, read_bank;
    logic [15:0] captured_frames, displayed_frames;
    logic write_range_error, write_sequence_error;
    logic read_frame_end = 1;
    logic [15:0] read_address = 0;
    logic [8:0] read_pixel;
    logic display_valid, swap_complete;
    integer rows = 0, verified_pixels = 0, epochs = 0;
    logic previous_reset = 0;
    assign read_reset = write_reset;
    assign write_color = write_x[5:0] ^ write_y[5:0];
    assign write_emphasis = write_y[2:0];
    always #5 write_clk = !write_clk;
    always #7 read_clk = !read_clk;
    nes_framebuffer dut (.*);

    initial begin
        integer fd, parsed, rst, start, valid, frozen, x, y;
        integer complete, captures, seq_error, range_error;
        logic [8:0] expected_pixel;
        fd = $fopen("build/phase6g/vectors/frames.txt", "r");
        if (fd == 0) $fatal(1, "missing Phase 6G framebuffer vectors");
        while (!$feof(fd)) begin
            parsed = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d\n",
                             rst, start, valid, frozen, x, y, complete,
                             captures, seq_error, range_error);
            if (parsed != 10) $fatal(1, "malformed frame vector %0d", rows);
            @(negedge write_clk);
            write_reset = 1'(rst); write_frame_start = 1'(start);
            write_valid = 1'(valid); capture_freeze = 1'(frozen);
            write_x = 8'(x); write_y = 8'(y);
            if (write_reset && !previous_reset) epochs++;
            previous_reset = write_reset;
            @(posedge write_clk); #1;
            if (capture_complete != 1'(complete) || captured_frames != 16'(captures) ||
                write_sequence_error != 1'(seq_error) || write_range_error != 1'(range_error))
                $fatal(1, "Phase6G frame row=%0d got complete/count/sequence/range=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d",
                       rows, capture_complete, captured_frames, write_sequence_error,
                       write_range_error, complete, captures, seq_error, range_error);
            if (!write_reset && capture_active && write_bank == read_bank)
                $fatal(1, "writer owns displayed bank");
            rows++;
        end
        $fclose(fd);
        repeat (10) @(negedge read_clk);
        if (!display_valid || displayed_frames != 1) $fatal(1, "recovery frame missing");
        for (integer address = 0; address < 61440; address++) begin
            @(negedge read_clk); read_address = 16'(address);
            @(posedge read_clk); #1;
            expected_pixel = {3'((address >> 8) & 7),
                              6'((address & 63) ^ ((address >> 8) & 63))};
            if (read_pixel != expected_pixel) $fatal(1, "recovery pixel %0d", address);
            verified_pixels++;
        end
        $display("PASS: Phase6G frame recovery cycles=%0d epochs=%0d verified_pixels=%0d mismatches=0", rows, epochs, verified_pixels);
        $finish;
    end
endmodule
