`timescale 1ns/1ps
// Deliberately delayed VGA handoffs reproduce the phase shift caused by pause.
module nes_framebuffer_pause_tb;
    logic wc=0, rc=0, reset=1, start=0, valid=0, frame_end=0;
    logic [7:0] x=0,y=0;
    logic [5:0] color=0;
    logic active, complete, pending, range_error, sequence_error, display_valid, swap;
    logic [1:0] write_bank, read_bank;
    logic [15:0] captured, displayed, address=0;
    logic [8:0] pixel;
    always #5 wc=~wc;
    always #7 rc=~rc;
    nes_framebuffer dut(.write_clk(wc),.write_reset(reset),.write_frame_start(start),
        .write_valid(valid),.write_x(x),.write_y(y),.write_color(color),.write_emphasis(3'd0),
        .capture_freeze(1'b0),.capture_active(active),.capture_complete(complete),
        .capture_pending(pending),.write_bank(write_bank),.captured_frames(captured),
        .write_range_error(range_error),.write_sequence_error(sequence_error),
        .read_clk(rc),.read_reset(reset),.read_frame_end(frame_end),.read_address(address),
        .read_pixel(pixel),.display_valid(display_valid),.swap_complete(swap),
        .read_bank(read_bank),.displayed_frames(displayed));
    task automatic frame(input logic [5:0] value);
        @(negedge wc); start=1;
        @(negedge wc); start=0;
        for(integer i=0;i<61440;i++) begin
            valid=1; x=8'(i); y=8'(i>>8); color=value;
            @(negedge wc);
        end
        valid=0;
    endtask
    task automatic scanout;
        repeat(8) @(negedge rc);
        frame_end=1;
        @(negedge rc); frame_end=0;
        repeat(8) @(negedge wc);
    endtask
    initial begin
        $dumpfile("build/sim/nes_framebuffer_pause.fst");
        $dumpvars(0,nes_framebuffer_pause_tb);
        repeat(5) @(negedge wc); reset=0;
        frame(6'd17); assert(pending && captured==1);
        frame(6'd29); assert(dut.completed_waiting && captured==1 && !active);
        // No free bank: an incoming whole frame is skipped without overwriting
        // either complete frame or reporting a malformed pixel sequence.
        frame(6'd42); assert(dut.completed_waiting && captured==1);
        assert(!range_error && !sequence_error);
        scanout(); assert(displayed==1 && captured==2 && pending);
        assert(pixel==9'd17);
        scanout(); assert(displayed==2 && !pending && !dut.completed_waiting);
        for(integer i=0;i<61440;i++) begin
            @(negedge rc); address=16'(i);
            repeat(2) @(negedge rc);
            assert(pixel==9'd29);
        end
        frame(6'd51); scanout(); assert(displayed==3 && captured==3 && pixel==9'd51);
        assert(!range_error && !sequence_error);
        $display("PASS: paused-phase framebuffer queued=2 skipped=1 recovered=1 verified_pixels=61440");
        $finish;
    end
endmodule
