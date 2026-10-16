`timescale 1ns/1ps
module nes_console_renderer_tb;
    logic clk=0, reset=1, active=0, boundary=0, focus=0, status_valid=0;
    always #10 clk=!clk;
    logic [9:0] x=0,y=0;
    logic [31:0] status=0;
    logic [7:0] buttons=0;
    logic [23:0] rgb, still_rgb;
    logic [23:0] expected[0:307199], still_expected[0:307199];
    logic [39:0] fixtures[0:35];
    integer fd;
    nes_console_renderer dut (
        .library_packet(928'd0),.pixel_clk(clk), .reset(reset), .frame_end(boundary),
        .status_valid(status_valid), .x(x), .y(y), .active(active), .status(status), .buttons(buttons),
        .held_reset(1'b1), .focus(focus), .rgb(rgb));
    nes_console_renderer #(.REDUCED_MOTION(1)) reduced (
        .library_packet(928'd0),
        .pixel_clk(clk), .reset(reset), .frame_end(boundary), .status_valid(status_valid),
        .x(x), .y(y), .active(active), .status(status), .buttons(buttons),
        .held_reset(1'b1), .focus(focus), .rgb(still_rgb));
    task automatic frame;
        boundary=1;@(negedge clk);boundary=0;@(negedge clk);
    endtask
    initial begin
        $readmemh("build/phase8b/vectors/fixtures.hex",fixtures);
        repeat(3) @(negedge clk);
        reset=0;active=1;x=128;y=120;@(negedge clk);
        assert(rgb==0) else $fatal(1,"uninitialized display exposed");
        status_valid=1;
        for(int fixture=0;fixture<36;fixture++) begin
            // The original eight state fixtures transition without resetting
            // the row bank, detecting stale text across successive screens.
            if(fixture==0 || fixture>=8) begin
                reset=1;@(negedge clk);reset=0;
            end
            status=fixtures[fixture][39:8];focus=fixtures[fixture][1];
            buttons=fixtures[fixture][0] ? 0 : 8'ha5;
            repeat(int'(fixtures[fixture][6:2])) frame();
            @(negedge clk);
            assert(dut.splash==fixtures[fixture][0] && dut.phase==fixtures[fixture][6:2])
                else $fatal(1,"fixture presentation phase %0d",fixture);
            buttons=fixtures[fixture][0] ? 0 : 8'ha5;
            $readmemh($sformatf("build/phase8b/vectors/ui-%0d.hex",fixture),expected);
            $readmemh($sformatf("build/phase8b/vectors/ui-still-%0d.hex",fixture),still_expected);
            fd=$fopen($sformatf("build/phase8b/ui-%0d.hex",fixture),"w");
            active=1;
            for(int py=0;py<480;py++) begin
                for(int px=0;px<640;px++) begin
                    x=10'(px);y=10'(py);@(negedge clk);
                    if(rgb!=expected[py*640+px])
                        $fatal(1,"UI fixture=%0d pixel=%0d,%0d got=%h expected=%h",
                               fixture,px,py,rgb,expected[py*640+px]);
                    if(still_rgb!=still_expected[py*640+px])
                        $fatal(1,"reduced UI fixture=%0d pixel=%0d,%0d",fixture,px,py);
                    $fdisplay(fd,"%06h",rgb);
                end
            end
            $fclose(fd);
            active=0;@(negedge clk);assert(rgb==0) else $fatal(1,"UI blanking");
            active=1;
            if(fixture>=7) begin
                reset=1;@(negedge clk);assert(rgb==0) else $fatal(1,"UI reset");
            end
        end
        $display("PASS: Phase 8B independent renderer 22118400 normal/reduced-motion Python-reference pixels, eight states, all errors, splash, focus and activity phases");
        $finish;
    end
endmodule
