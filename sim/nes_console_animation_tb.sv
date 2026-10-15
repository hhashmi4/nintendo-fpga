`timescale 1ns/1ps
module nes_console_animation_tb;
    logic clk=0, reset=1, boundary=0, focus=0, status_valid=0;
    always #10 clk=!clk;
    logic [31:0] status=0;
    logic [7:0] buttons=0;
    logic splash, still_splash;
    logic [4:0] phase, still_phase;
    nes_console_animation dut (.pixel_clk(clk), .reset(reset), .frame_end(boundary),
        .status(status), .status_valid(status_valid), .buttons(buttons), .focus(focus), .splash(splash), .phase(phase));
    nes_console_animation #(.REDUCED_MOTION(1)) reduced (
        .pixel_clk(clk), .reset(reset), .frame_end(boundary), .status(status), .status_valid(status_valid),
        .buttons(buttons), .focus(focus), .splash(still_splash), .phase(still_phase));
    task automatic tick;
        @(negedge clk);
    endtask
    task automatic frame;
        boundary=1; tick(); boundary=0; tick();
        assert(!still_splash && still_phase==0) else $fatal(1,"reduced motion moved");
    endtask
    initial begin
        tick();reset=0;tick();
        repeat(32) frame();
        assert(!splash && phase==0) else $fatal(1,"invalid startup animated");
        status_valid=1;status=32'h00010100;tick();
        assert(splash) else $fatal(1,"valid initialization splash absent");
        status=32'h00010101; // MENU can be ready while splash is still visible.
        frame();assert(splash && phase==1);
        repeat(23) begin
            logic [4:0] saved;
            saved=phase;
            repeat(13) tick();
            assert(phase==saved) else $fatal(1,"animation changed within frame");
            frame();
        end
        assert(!splash && dut.boot_frames==24) else $fatal(1,"splash not exactly 24 boundaries");
        repeat(100) frame(); assert(!splash);
        reset=1;tick();reset=0;tick();assert(splash && phase==0);
        buttons=1;frame();assert(!splash);buttons=0;frame();assert(!splash);
        reset=1;tick();reset=0;tick();focus=1;frame();assert(!splash);
        focus=0;reset=1;tick();reset=0;tick();
        status=32'h00020606;tick();assert(!splash); // immediate error bypass
        frame();assert(phase==1);
        // Emulate the ownership bank changing status just after frame_end.
        status=32'h00030402;tick();assert(phase==0);
        for(int n=1;n<=64;n++) begin
            frame();assert(phase==5'(n)) else $fatal(1,"activity period");
        end
        reset=1;tick();assert(phase==0 && !dut.skipped);
        reset=0;status=32'h00010101;tick();assert(splash);
        $display("PASS: Phase 8B animation 24-frame splash, 8-frame steps, 32-frame period, frame stability, skip, reset and reduced motion");
        $finish;
    end
endmodule
