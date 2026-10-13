`timescale 1ns/1ps

// Model one additional sampling cycle on the bundled read-bank return. The
// acknowledgement must not release its reservation before that bus settles.
module phase6g_ownership_tb;
    logic write_clk = 0, read_clk = 0, write_reset = 1, read_reset = 1;
    logic write_frame_start = 0, write_valid = 0, capture_freeze = 0;
    logic [7:0] write_x = 0, write_y = 0;
    logic [5:0] write_color = 1;
    logic [2:0] write_emphasis = 0;
    logic capture_active, capture_complete, capture_pending;
    logic [1:0] write_bank, read_bank;
    logic [15:0] captured_frames, displayed_frames;
    logic write_range_error, write_sequence_error;
    logic read_frame_end = 0;
    logic [15:0] read_address = 0;
    logic [8:0] read_pixel;
    logic display_valid, swap_complete;
    integer cycles = 0;
    always #5 write_clk = !write_clk;
    always #7 read_clk = !read_clk;
    always @(posedge write_clk) cycles++;
    nes_framebuffer dut (.*);
    initial begin
        repeat (5) @(negedge write_clk);
        write_reset = 0; read_reset = 0;
        for (integer pixel = 0; pixel < 61440; pixel++) begin
            @(negedge write_clk);
            write_frame_start = pixel == 0; write_valid = 1;
            write_x = 8'(pixel); write_y = 8'(pixel >> 8);
        end
        @(negedge write_clk); write_frame_start = 0; write_valid = 0;
        assert (captured_frames == 1 && capture_pending && !display_valid);
        force dut.read_bank_meta = 2'd0;
        @(negedge read_clk); read_frame_end = 1;
        @(posedge dut.acknowledge_toggle);
        @(posedge write_clk); #1;
        @(negedge write_clk); release dut.read_bank_meta;
        @(posedge write_clk); #1;
        // A two-stage acknowledgement would now drop capture_pending while
        // read_bank_sync still contains the old bank, allowing a collision.
        assert (capture_pending && dut.read_bank_sync == 0 && read_bank == 1);
        @(negedge write_clk); write_frame_start = 1;
        @(posedge write_clk); #1;
        assert (capture_active && write_bank == 2 && write_bank != read_bank);
        assert (!write_range_error && !write_sequence_error);
        $display("PASS: Phase6G ownership return skew cycles=%0d reservation preserved; mismatches=0", cycles);
        $finish;
    end
    initial begin #1ms; $fatal(1, "ownership skew watchdog"); end
endmodule
