`timescale 1ns/1ps

module nes_console_video_tb;
    logic fabric_clk=0, pixel_clk=0;
    always #10 fabric_clk=!fabric_clk;
    always #7 pixel_clk=!pixel_clk;
    logic source_reset=1, pixel_reset=1, content_reset=1, inhibit=1, held=1;
    wire reset=source_reset || pixel_reset;
    logic [31:0] requested=32'h00010001;
    logic [7:0] buttons=0;
    logic frame_end=0, framebuffer_valid=0, ack, visible, display_reset;
    logic [31:0] response, displayed;
    logic [1:0] source;
    logic [7:0] displayed_buttons;
    int acknowledgements=0;
    logic displayed_focus, displayed_valid;
    logic focus=0;
    nes_console_video dut (
        .focus(focus), .displayed_focus(displayed_focus), .displayed_valid(displayed_valid),
        .source_clk(fabric_clk), .source_reset(source_reset),
        .requested_status(requested), .buttons(buttons), .held_reset(held),
        .inhibit_game(inhibit), .source_ack(ack), .source_response(response),
        .pixel_clk(pixel_clk), .pixel_reset(pixel_reset), .content_reset(content_reset),
        .frame_end(frame_end), .framebuffer_valid(framebuffer_valid),
        .selected_source(source), .displayed_status(displayed),
        .displayed_buttons(displayed_buttons), .displayed_reset(display_reset),
        .game_visible(visible)
    );
    logic [1:0] previous_source=0;
    logic previous_boundary=0, previous_focus=0, previous_valid=0;
    always @(negedge pixel_clk) begin
        if (!reset && source != previous_source && !previous_boundary)
            $fatal(1, "source changed outside raster boundary");
        if (!reset && (displayed_focus != previous_focus || displayed_valid != previous_valid) && !previous_boundary)
            $fatal(1,"presentation metadata changed outside raster boundary");
        previous_focus=displayed_focus;
        previous_valid=displayed_valid;
        previous_source = source;
    end
    always @(posedge pixel_clk) previous_boundary <= frame_end;
    always @(negedge fabric_clk) if (!reset && ack) acknowledgements++;

    task automatic clocks(input int n);
        repeat(n) @(negedge pixel_clk);
    endtask
    task automatic boundary;
        frame_end=1; clocks(1); frame_end=0; clocks(12);
    endtask
    task automatic settle_frame;
        clocks(20); boundary(); clocks(20); boundary();
    endtask
    initial begin
        clocks(4); source_reset=0; pixel_reset=0;
        settle_frame();
        if (source != 0 || displayed != requested || !display_reset)
            $fatal(1, "UI not live while NES is held reset");
        assert(displayed_valid) else $fatal(1,"status never became valid");
        focus=1;settle_frame();assert(displayed_focus);
        focus=0;settle_frame();assert(!displayed_focus);
        // Epoch zero is legal after wrap; validity is a separate display bit.
        requested=32'h00000101;settle_frame();
        assert(displayed_valid && displayed[31:16]==0);
        buttons=8'ha5; requested=32'h00020143;
        held=0; inhibit=0; content_reset=0;
        settle_frame();
        if (source != 0 || visible) $fatal(1, "invalid frame admitted");
        framebuffer_valid=1;
        settle_frame();
        if (source != 1 || !visible || displayed_buttons != 8'ha5)
            $fatal(1, "game frame not admitted coherently");
        content_reset=1;
        clocks(1);
        if (visible) $fatal(1, "old gameplay leaked through content reset");
        requested=32'h00030005; inhibit=1; held=1;
        settle_frame();
        if (source != 0 || visible) $fatal(1, "menu ownership");
        requested=32'h000400a7;
        settle_frame();
        if (source != 2 || displayed[31:16] != 4)
            $fatal(1, "developer blocked by content reset");
        for (int n=0;n<32;n++) begin
            requested={16'(n+5),16'h0143};
            inhibit=0; content_reset=0;
            clocks(n+1); boundary();
            content_reset=1; inhibit=1;
            requested={16'(n+6),16'h0006};
            clocks(n%7+1); boundary();
            if (visible) $fatal(1, "recovery gameplay leakage");
        end
        // Common mailbox reset discards an unacknowledged old game request.
        requested=32'h00ff0143; inhibit=0; content_reset=0; clocks(15);
        source_reset=1; pixel_reset=1; clocks(4); requested=32'h00010001; inhibit=1;
        source_reset=0; pixel_reset=0; content_reset=1;
        settle_frame();
        if (source != 0 || displayed[31:16] != 1 || visible)
            $fatal(1, "old epoch survived reset");
        for(int endpoint=0;endpoint<2;endpoint++) begin
            requested=32'h0fff0143; inhibit=0;content_reset=0;clocks(15);
            source_reset=(endpoint==0);pixel_reset=(endpoint==1);clocks(5);
            requested=32'h00020001;inhibit=1;content_reset=1;
            source_reset=0;pixel_reset=0;settle_frame();
            if(source!=0 || visible || displayed[31:16]!=2)
                $fatal(1,"unilateral console mailbox reset failed");
        end
        if (acknowledgements < 20) $fatal(1, "insufficient handshake exercise");
        $display("PASS: Phase 8A independent video CDC, frame-boundary ownership, missing frames and 32 recovery phases");
        $finish;
    end
endmodule
