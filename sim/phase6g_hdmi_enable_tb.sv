`timescale 1ns/1ps

module phase6g_hdmi_enable_tb;
    logic pixel_clk = 0, pixel_reset = 1, video_enable_async = 0;
    logic [23:0] pipeline_rgb = 24'habc123;
    logic pipeline_hsync = 0, pipeline_vsync = 0, pipeline_de = 1;
    logic pipeline_frame_start = 0;
    logic tx_pixel_clock, tx_hsync, tx_vsync, tx_data_enable, tx_frame_start;
    logic [23:0] tx_rgb;
    logic frame_toggle;
    integer cycles = 0;
    always #7 pixel_clk = !pixel_clk;
    always @(posedge pixel_clk) cycles++;
    hdmi_rgb_output dut (.*);
    initial begin
        repeat (5) @(negedge pixel_clk);
        pixel_reset = 0;
        for (integer epoch = 0; epoch < 32; epoch++) begin
            video_enable_async = 1;
            repeat (5 + epoch) begin
                @(negedge pixel_clk);
                if (tx_data_enable || tx_rgb != 0)
                    $fatal(1, "HDMI enabled before frame origin epoch=%0d", epoch);
            end
            pipeline_frame_start = 1;
            #1;
            if (!tx_data_enable || !tx_frame_start || tx_rgb != pipeline_rgb)
                $fatal(1, "first pixel lost after hotplug");
            @(negedge pixel_clk); pipeline_frame_start = 0;
            repeat (8) begin
                @(negedge pixel_clk);
                if (!tx_data_enable || tx_rgb != pipeline_rgb)
                    $fatal(1, "enabled frame interrupted");
            end
            video_enable_async = 0;
            repeat (4) @(negedge pixel_clk);
            if (tx_data_enable || tx_rgb != 0) $fatal(1, "disable failed");
        end
        pixel_reset = 1;
        #1;
        if (tx_data_enable) $fatal(1, "reset must suppress DE");
        $display("PASS: Phase6G HDMI frame enable cycles=%0d reconnects=32 mismatches=0", cycles);
        $finish;
    end
endmodule
