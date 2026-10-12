`timescale 1ns/1ps
module hdmi_audio_edid_tb;
    logic clk = 0, reset = 1, start = 0, byte_valid = 0;
    logic [7:0] byte_index = 0, byte_data = 0;
    logic supports_pcm;
    always #10 clk = !clk;
    hdmi_audio_edid dut (.*);
    task automatic send(input integer index, input logic [7:0] value);
        @(negedge clk);
        byte_valid = 1;
        byte_index = 8'(index);
        byte_data = value;
        @(negedge clk);
        byte_valid = 0;
    endtask
    task automatic header(input logic [7:0] tag, last_byte, flags);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        send(128, tag); send(129, 3); send(130, last_byte); send(131, flags);
    endtask
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        header(2, 4, 0);
        if (supports_pcm) $fatal(1, "video-only sink accepted");
        header(2, 4, 8'h40);
        if (!supports_pcm) $fatal(1, "basic audio rejected");
        header(1, 4, 8'h40);
        if (supports_pcm) $fatal(1, "non-CTA accepted");
        for (integer trial = 0; trial < 8; trial++) begin
            header(2, 8, 0);
            send(132, 8'h23);
            send(133, trial[0] ? 8'h09 : 8'h11); // LPCM vs compressed
            send(134, trial[1] ? 8'h04 : 8'h02); // 48 vs 44.1 kHz
            send(135, trial[2] ? 8'h01 : 8'h04); // 16 vs 24 bit only
            if (supports_pcm !== (trial == 7)) $fatal(1, "SAD trial=%0d", trial);
        end
        header(2, 0, 0); // No data block collection; bytes are not SADs.
        send(132, 8'h23); send(133, 8'h09); send(134, 4); send(135, 1);
        if (supports_pcm) $fatal(1, "empty CTA accepted stale data");
        header(2, 7, 0); // Truncated descriptor
        send(132, 8'h23); send(133, 8'h09); send(134, 4); send(135, 1);
        if (supports_pcm) $fatal(1, "truncated SAD accepted");
        header(2, 255, 0); // Malformed end must not admit the checksum byte.
        send(252, 8'h23); send(253, 8'h09); send(254, 4); send(255, 1);
        if (supports_pcm) $fatal(1, "checksum byte used as SAD payload");
        $display("Phase 6D audio EDID passed: 14 capability cases");
        $finish;
    end
endmodule
