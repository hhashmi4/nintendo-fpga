`timescale 1ns/1ps
module nes_library_renderer_tb;
    logic clk=0,source_clk=0,reset=1,frame_end=0,active=1;
    always #7 clk=~clk;
    always #10 source_clk=~source_clk;
    logic [9:0] x=0,y=0;
    logic [10:0] hx=0;
    logic [9:0] hy=0;
    logic [927:0] packet=0;
    logic [31:0] status=0;
    logic [23:0] rgb,hd_rgb,normal_rgb;
    logic ack;
    logic [31:0] response;
    logic [1:0] source;
    logic [959:0] cases[0:19];
    logic [23:0] expected[0:307199];
    nes_console_renderer #(.REDUCED_MOTION(1)) dut(
        .library_packet(packet),.pixel_clk(clk),.reset(reset),.frame_end(frame_end),
        .x(x),.y(y),.active(active),.status_valid(1'b1),.status(status),.buttons(8'd0),
        .held_reset(1'b1),.focus(1'b0),.rgb(rgb));
    nes_console_renderer normal (
        .library_packet(packet),.pixel_clk(clk),.reset(reset),.frame_end(frame_end),
        .x(x),.y(y),.active(active),.status_valid(1'b1),.status(status),.buttons(8'd0),
        .held_reset(1'b1),.focus(1'b0),.rgb(normal_rgb));
    nes_console_720p_overlay #(.REDUCED_MOTION(1)) hdmi(
        .library_packet(packet),.source_clk(source_clk),.source_reset(reset),
        .requested_status(status),.buttons(8'd0),.held_reset(1'b1),.inhibit_game(1'b1),.focus(1'b0),
        .source_ack(ack),.source_response(response),.pixel_clk(clk),.pixel_reset(reset),.content_reset(1'b1),
        .frame_end(frame_end),.framebuffer_valid(1'b0),.render_x(hx),.render_y(hy),.render_active(1'b1),
        .game_rgb(24'd0),.rgb(hd_rgb),.selected_source(source));
    initial begin
        integer fd;
        logic [23:0] digits;
        reset=1;repeat(8) @(negedge clk);reset=0;
        for(int value=0;value<512;value++) begin
            packet=0;packet[16:8]=9'(value);
            packet[231:224]=8'(value);packet[239:232]=8'(value);packet[247:240]=8'(value);
            repeat(22) @(negedge clk);
            digits={8'(48+value/100),8'(48+(value/10)%10),8'(48+value%10)};
            assert(dut.decimal_text[0]==digits && normal.decimal_text[0]==digits);
            assert(dut.decimal_text[1]==(value==0 ? "000" : "001"));
            digits={8'(48+(value%256)/100),8'(48+((value%256)/10)%10),8'(48+(value%256)%10)};
            for(int field=2;field<5;field++) assert(dut.decimal_text[field]==digits);
        end
        $readmemh("build/phase8c/vectors/fixtures.hex",cases);
        for(int fixture=0;fixture<20;fixture++) begin
            reset=1;repeat(8) @(negedge clk);reset=0;
            packet=cases[fixture][959:32];status=cases[fixture][31:0];
            repeat(4) begin
                repeat(32) @(negedge clk);frame_end=1;@(negedge clk);frame_end=0;
            end
            assert(hdmi.displayed_library==packet && hdmi.displayed_status==status);
            assert(!normal.splash) else $fatal(1,"library did not skip optional splash");
            $readmemh($sformatf("build/phase8c/vectors/library-%0d.hex",fixture),expected);
            fd=$fopen($sformatf("build/phase8c/library-%0d.hex",fixture),"w");
            active=1;
            for(int py=0;py<480;py++) for(int px=0;px<640;px++) begin
                x=10'(px);y=10'(py);hx=11'(px+320);hy=10'(py+120);@(negedge clk);
                assert(rgb==expected[py*640+px]) else $fatal(1,"library fixture=%0d pixel=%0d,%0d got=%h want=%h",fixture,px,py,rgb,expected[py*640+px]);
                assert(normal_rgb==expected[py*640+px]) else $fatal(1,"normal-motion library fixture=%0d pixel=%0d,%0d",fixture,px,py);
                assert(hd_rgb==expected[py*640+px]) else $fatal(1,"HDMI library fixture=%0d pixel=%0d,%0d",fixture,px,py);
                $fdisplay(fd,"%06h",rgb);
            end
            $fclose(fd);active=0;hx=0;hy=0;@(negedge clk);assert(rgb==0 && hd_rgb==0);
        end
        // Updating the wide source packet cannot tear a displayed frame.
        packet=cases[2][959:32];repeat(64) @(negedge clk);
        assert(hdmi.displayed_library==cases[19][959:32]);
        repeat(4) begin repeat(32) @(negedge clk);frame_end=1;@(negedge clk);frame_end=0;end
        assert(hdmi.displayed_library==packet);
        reset=1;repeat(8) @(negedge clk);assert(!hdmi.displayed_valid && hdmi.displayed_library==0);
        $display("PASS: Phase 8C production renderer and coherent logical HDMI: 18432000 exact normal/reduced-motion pixels across 20 empty/focus/page/clipping/unsupported/loading/error fixtures");
        $finish;
    end
endmodule
