`timescale 1ns/1ps

module nes_console_mmio_tb;
    logic focus;
    logic hps_clk=0, fabric_clk=0;
    always #7 hps_clk=!hps_clk;
    always #10 fabric_clk=!fabric_clk;
    logic reset=1, bridge_reset=1;
    logic [4:0] address=0;
    logic rd=0, wr=0, waitrequest, readvalid;
    logic [31:0] writedata=0, readdata;
    logic [3:0] byteenable=15;
    logic submit, ready, ack, valid, done;
    logic [31:0] request, command, response_status, status, video_request;
    logic [1:0] result;
    logic [33:0] response;
    logic hold_core, inhibit;
    logic [7:0] game_buttons, navigation;
    logic loader_begin=0;

    nes_console_mmio registers (
        .clk(hps_clk), .reset(bridge_reset), .avs_address(address),
        .avs_read(rd), .avs_write(wr), .avs_writedata(writedata),
        .avs_byteenable(byteenable), .avs_waitrequest(waitrequest),
        .avs_readdatavalid(readvalid), .avs_readdata(readdata),
        .submit(submit), .request_word(request), .channel_ready(ready),
        .channel_ack(ack), .channel_response(response)
    );
    nes_console_mailbox #(.RESPONSE_BITS(34)) channel (
        .source_clk(hps_clk), .source_reset(bridge_reset), .source_valid(submit),
        .source_data(request), .source_ready(ready), .source_ack(ack),
        .source_response(response), .destination_clk(fabric_clk),
        .destination_reset(bridge_reset), .destination_valid(valid),
        .destination_data(command), .destination_done(done),
        .destination_response({result,response_status})
    );
    nes_console_control control (
        .library_enabled(1'b0), .library_open(1'b0), .library_load_request(1'b0), .library_cancel(1'b0),
        .clk(fabric_clk), .reset(reset), .bridge_reset(bridge_reset),
        .loader_begin(loader_begin), .activation_accepted(1'b0),
        .loader_hold(loader_begin), .runtime_active(1'b0), .loader_state(2'd0),
        .loader_error_code(4'd0), .buttons(8'd0),
        .command_valid(valid), .command_word(command), .command_done(done),
        .command_result(result), .command_status(response_status),
        .video_ack(1'b1), .video_response(video_request),
        .video_request(video_request), .status(status), .core_hold(hold_core),
        .inhibit_game(inhibit), .game_buttons(game_buttons), .navigation(navigation), .focus(focus)
    );
    task automatic write_word(input logic [31:0] value);
        @(negedge hps_clk); address=5'h10; writedata=value; wr=1;
        @(negedge hps_clk); wr=0;
    endtask
    task automatic read_word(input logic [4:0] offset, output logic [31:0] value);
        @(negedge hps_clk); address=offset; rd=1;
        @(negedge hps_clk);
        if (!readvalid || waitrequest) $fatal(1, "Avalon read contract");
        value=readdata; rd=0;
    endtask
    logic [31:0] count_before, count_after, data_word;
    task automatic transact(input logic [31:0] value, input logic [1:0] expected);
        read_word(5'h1c,count_before);
        write_word(value);
        count_after=count_before;
        for(int n=0;n<100 && count_after==count_before;n++) read_word(5'h1c,count_after);
        if (count_after != count_before+1) $fatal(1, "missing/duplicate command");
        read_word(5'h18,data_word);
        if (data_word != {30'd0,expected}) $fatal(1, "bad result %h",data_word);
    endtask
    initial begin
        repeat(5) @(negedge fabric_clk);
        reset=0; bridge_reset=0;
        repeat(10) @(negedge hps_clk);
        read_word(0,data_word);
        if (data_word != 32'h4e455343) $fatal(1, "console identity");
        read_word(4,data_word);
        if (data_word != 32'h00010000) $fatal(1, "console version");
        transact(0,0);
        read_word(5'h14,data_word);
        if (data_word[3:0] != 1) $fatal(1, "boot menu status");
        transact({data_word[31:16],16'd2},0);
        if (status[3:0] != 4) $fatal(1, "launch not acknowledged");
        transact(32'hffff0001,1);
        transact({status[31:16],16'd1},0);
        if (!hold_core) $fatal(1, "menu did not stop game");
        // Full-word commands prevent torn epoch/opcode staging.
        byteenable=1; write_word(2); byteenable=15;
        read_word(5'h0c,data_word);
        if (!data_word[2]) $fatal(1, "partial write accepted");
        // Occupied mailbox must retain its first immutable command bank.
        write_word({status[31:16],16'd3});
        write_word({status[31:16],16'd2});
        repeat(25) @(negedge hps_clk);
        read_word(5'h0c,data_word);
        if (!data_word[2] || status[3:0] != 7) $fatal(1, "busy command overwritten");
        // An unrelated BEGIN invalidates already observed software epochs.
        transact(0,0); read_word(5'h14,data_word);
        @(negedge fabric_clk); loader_begin=1;
        @(negedge fabric_clk); loader_begin=0;
        transact({data_word[31:16],16'd2},1);
        // Reset a request before delivery, then start a fresh transaction.
        write_word({status[31:16],16'd2});
        bridge_reset=1;
        repeat(5) @(negedge fabric_clk);
        bridge_reset=0;
        repeat(20) @(negedge hps_clk);
        if (!hold_core) $fatal(1, "old command executed after bridge reset");
        transact(0,0);
        read_word(5'h14,data_word);
        if (data_word[3:0] != 1) $fatal(1, "bridge reset recovery");
        $display("PASS: Phase 8A actual Avalon registers and asynchronous command CDC, busy/partial/stale rejection and interruption");
        $finish;
    end
endmodule
