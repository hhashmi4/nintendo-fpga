`timescale 1ns/1ps

module nes_console_control_tb;
    logic clk = 0;
    always #10 clk = !clk;
    logic reset = 1, bridge_reset = 0;
    logic loader_begin = 0, activated = 0, loader_hold = 0, runtime_active = 0;
    logic [1:0] loader_state = 0;
    logic [3:0] loader_error = 0;
    logic [7:0] buttons = 0;
    logic valid = 0, done;
    logic [31:0] command = 0, response, status, video_request, video_response = 0;
    logic [1:0] result;
    logic video_ack = 0, core_hold, inhibit;
    logic [7:0] game_buttons, navigation;

    nes_console_control #(.START_TIMEOUT_CYCLES(100)) dut (
        .clk(clk), .reset(reset), .bridge_reset(bridge_reset),
        .loader_begin(loader_begin), .activation_accepted(activated),
        .loader_hold(loader_hold), .runtime_active(runtime_active),
        .loader_state(loader_state), .loader_error_code(loader_error),
        .buttons(buttons), .command_valid(valid), .command_word(command),
        .command_done(done), .command_result(result), .command_status(response),
        .video_ack(video_ack), .video_response(video_response),
        .video_request(video_request), .status(status),
        .core_hold(core_hold), .inhibit_game(inhibit),
        .game_buttons(game_buttons), .navigation(navigation)
    );

    task automatic tick;
        @(posedge clk); #1;
        @(negedge clk);
    endtask

    task automatic check_state(input logic [3:0] expected);
        if (status[3:0] != expected)
            $fatal(1, "state expected=%0d actual=%0d", expected, status[3:0]);
    endtask

    task automatic submit(input logic [3:0] opcode, input logic [15:0] epoch,
                          input logic [1:0] expected_result);
        command = {epoch, 12'd0, opcode};
        valid = 1;
        tick();
        if (!done || result != expected_result)
            $fatal(1, "command %0d result=%0d expected=%0d done=%b", opcode,
                   result, expected_result, done);
        valid = 0;
        tick();
    endtask

    task automatic display_ack(input logic [1:0] source);
        video_response = video_request;
        video_response[7:6] = source;
        video_ack = 1;
        tick();
        video_ack = 0;
        tick();
    endtask

    initial begin
        repeat (3) tick();
        reset = 0;
        tick();
        if (!core_hold || !inhibit) $fatal(1, "boot not isolated");
        display_ack(0);
        check_state(1);
        submit(2, status[31:16] - 16'd1, 1);
        check_state(1);
        submit(15, status[31:16], 2);
        buttons = 8'h81;
        submit(2, status[31:16], 0);
        check_state(3);
        if (core_hold || game_buttons != 0) $fatal(1, "starting input/reset");
        display_ack(0);
        check_state(3);
        display_ack(1);
        check_state(4);
        if (game_buttons != 0) $fatal(1, "held menu buttons leaked");
        buttons = 0; tick();
        buttons = 8'h81; #1;
        if (game_buttons != 8'h81) $fatal(1, "game path added a cycle");
        submit(1, status[31:16], 0);
        check_state(5);
        if (!core_hold || !inhibit || game_buttons != 0) $fatal(1, "return isolation");
        display_ack(0);
        check_state(1);
        if (navigation != 0) $fatal(1, "held game button became menu press");
        buttons = 0; tick();
        submit(4, status[31:16], 0);
        check_state(2);
        submit(2, status[31:16], 2);
        loader_begin = 1; loader_hold = 1; loader_state = 3; loader_error = 8;
        tick(); loader_begin = 0; tick();
        check_state(6);
        if (status[15:12] != 8) $fatal(1, "mapper error not preserved");
        submit(5,status[31:16],0);
        if (status[15:12] != 8) $fatal(1, "host reporting hid loader error");
        submit(3, status[31:16], 0);
        check_state(7);
        display_ack(2);
        if (status[7:6] != 2 || game_buttons != 0) $fatal(1, "developer ownership");
        submit(1, status[31:16], 0); display_ack(0);
        submit(2, status[31:16], 3);
        submit(4, status[31:16], 0);
        loader_begin = 1; loader_state = 1; loader_error = 0; tick();
        loader_begin = 0; tick();
        loader_state = 2; runtime_active = 1; activated = 1; tick();
        activated = 0; loader_hold = 0; tick();
        display_ack(0); check_state(1);
        submit(2, status[31:16], 0);
        // No complete PPU frame: bounded recovery while the UI stays owned.
        repeat (105) tick();
        check_state(6);
        if (!core_hold || !inhibit) $fatal(1, "frame timeout isolation");
        for (int n = 0; n < 16; n++) begin
            submit(1, status[31:16], 0); display_ack(0);
            submit(2, status[31:16], 0); display_ack(1);
            check_state(4);
            submit(3, status[31:16], 0); display_ack(2);
            check_state(7);
        end
        submit(1, status[31:16], 0); display_ack(0);
        submit(2, status[31:16], 0);
        video_response = video_request;
        video_response[7:6] = 1;
        bridge_reset = 1; tick(); bridge_reset = 0; tick();
        video_ack = 1; tick(); video_ack = 0;
        if (status[3:0] == 4 || !core_hold) $fatal(1, "stale display ack after reset");
        display_ack(0); check_state(1);
        submit(2, status[31:16], 0);
        reset = 1; tick(); reset = 0; tick();
        if (!core_hold) $fatal(1, "reset during launch");
        display_ack(0); check_state(1);
        // Simultaneous local START + SELECT chooses Developer Mode; a
        // simultaneous HPS MENU intention has priority over both.
        buttons=0; tick(); buttons=8'h0c; tick();
        check_state(7);
        buttons=0; tick();
        submit(1,status[31:16],0); display_ack(0); tick();
        buttons=8'h0c;
        submit(1,status[31:16],0); check_state(5);
        buttons=0; display_ack(0); check_state(1);
        // Loader BEGIN wins even when an otherwise valid LAUNCH arrives.
        loader_begin=1;
        submit(2,status[31:16],1); check_state(2);
        loader_begin=0; tick();
        submit(1,status[31:16],0); display_ack(0); check_state(1);
        // A permanently unavailable HPS must not hold console navigation in
        // INITIALIZING. Gameplay availability remains independently false.
        bridge_reset=1; tick(); display_ack(0); check_state(1);
        if(status[8]) $fatal(1,"game available while bridge reset");
        buttons=0;tick();buttons=8'h04;tick();check_state(7);
        display_ack(2);buttons=0;tick();buttons=8'h02;tick();
        display_ack(0);check_state(1);
        bridge_reset=0;buttons=0;tick();
        // Exhaustive software intention/state matrix. Reach every state via
        // public events; never deposit a state register or emulate the DUT.
        for(int start_state=0;start_state<8;start_state++) begin
            for(int opcode=0;opcode<6;opcode++) begin
                logic [1:0] expected_result;
                logic [3:0] expected_state;
                reset=1;loader_state=0;loader_hold=0;loader_error=0;
                runtime_active=0;tick();reset=0;tick();
                if(start_state!=0) display_ack(0);
                case(start_state)
                    2: submit(4,status[31:16],0);
                    3: submit(2,status[31:16],0);
                    4: begin submit(2,status[31:16],0);display_ack(1);end
                    5: submit(1,status[31:16],0);
                    6: submit(5,status[31:16],0);
                    7: begin submit(3,status[31:16],0);display_ack(2);end
                    default: begin end
                endcase
                check_state(4'(start_state));
                expected_result=0;expected_state=4'(start_state);
                case(opcode)
                    1: expected_state=5;
                    2: if(start_state==1 || start_state==7) expected_state=3;
                       else expected_result=2;
                    3: expected_state=7;
                    4: if(start_state==1 || start_state==6 || start_state==7) expected_state=2;
                       else expected_result=2;
                    5: expected_state=6;
                    default: begin end
                endcase
                submit(4'(opcode),status[31:16],expected_result);
                check_state(expected_state);
            end
        end
        $display("PASS: Phase 8A supervisor all 48 state/command pairs, stale requests, input handoff, loading, recovery, developer and reset");
        $finish;
    end
endmodule
