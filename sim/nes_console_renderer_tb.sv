`timescale 1ns/1ps

module nes_console_renderer_tb;
    logic clk=0, reset=1, active=0;
    always #10 clk=!clk;
    logic [9:0] x=0,y=0;
    logic [31:0] status=0;
    logic [23:0] rgb;
    logic [23:0] expected[0:307199];
    nes_console_renderer dut (.pixel_clk(clk), .reset(reset), .x(x), .y(y),
        .active(active), .status(status), .buttons(8'ha5), .held_reset(1'b1), .rgb(rgb));
    initial begin
        repeat(3) @(negedge clk);
        reset=0;
        for (int state_index=0; state_index<8; state_index++) begin
            $readmemh($sformatf("build/phase8a/vectors/ui-%0d.hex",state_index),expected);
            status=32'h12348e00 | 32'(state_index);
            active=1;
            for (int py=0;py<480;py++) begin
                for (int px=0;px<640;px++) begin
                    x=10'(px); y=10'(py);
                    @(negedge clk);
                    if(rgb != expected[py*640+px])
                        $fatal(1,"UI state=%0d pixel=%0d,%0d got=%h expected=%h",
                               state_index,px,py,rgb,expected[py*640+px]);
                end
            end
            active=0;
            @(negedge clk);
            if(rgb != 0) $fatal(1,"UI blanking");
        end
        $display("PASS: Phase 8A independent renderer 2457600 Python-reference pixels, all eight states, no NES input");
        $finish;
    end
endmodule
