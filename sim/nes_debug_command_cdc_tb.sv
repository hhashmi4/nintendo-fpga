`timescale 1ns/1ps

module nes_debug_command_cdc_tb;
    logic source_clk = 1'b0;
    logic destination_clk = 1'b0;
    logic source_reset = 1'b1;
    logic destination_reset = 1'b1;
    logic source_valid = 1'b1;
    logic [2:0] source_command = 3'd3;
    logic source_ready, source_busy, source_ack;
    logic [15:0] source_ack_sequence;
    logic [2:0] source_ack_state;
    logic [1:0] source_ack_result;
    logic destination_valid, destination_done = 1'b0;
    logic [2:0] destination_command;
    logic [15:0] destination_sequence;
    logic [2:0] destination_state = 3'd0;
    logic [1:0] destination_result = 2'd0;
    integer acknowledgements = 0;
    integer completions = 0;

    always #7 source_clk = !source_clk;
    always #11 destination_clk = !destination_clk;

    nes_debug_command_cdc dut (.*);

    always @(posedge source_clk) begin
        if (source_reset)
            acknowledgements <= 0;
        else if (source_ack)
            acknowledgements <= acknowledgements + 1;
    end
    always @(posedge destination_clk) begin
        if (destination_reset)
            completions <= 0;
        else if (destination_valid && destination_done)
            completions <= completions + 1;
    end

    task automatic arm_source;
        @(negedge source_clk);
        source_valid = 1'b0;
        do @(negedge source_clk); while (!source_ready);
    endtask

    task automatic transaction(input integer sequence_id);
        logic [2:0] command_value;
        logic [2:0] state_value;
        logic [1:0] result_value;
        command_value = 3'(sequence_id);
        state_value = 3'(sequence_id / 2);
        result_value = 2'(sequence_id / 3);
        arm_source();
        source_command = command_value;
        source_valid = 1'b1;
        do @(negedge source_clk); while (!source_busy);
        assert (!source_ready);
        // The producer may change its data after acceptance. Only the held
        // internal payload bank may be observed across the clock boundary.
        source_command = ~command_value;
        do @(negedge destination_clk); while (!destination_valid);
        repeat ((sequence_id % 7) + 1) begin
            assert (destination_command == command_value);
            assert (destination_sequence == 16'(sequence_id));
            assert (source_busy && !source_ack && !source_ready);
            @(negedge destination_clk);
        end
        destination_state = state_value;
        destination_result = result_value;
        destination_done = 1'b1;
        @(negedge destination_clk);
        destination_done = 1'b0;
        destination_state = ~state_value;
        destination_result = ~result_value;
        do @(negedge source_clk); while (!source_ack);
        assert (!source_busy);
        assert (source_ack_sequence == 16'(sequence_id));
        assert (source_ack_state == state_value);
        assert (source_ack_result == result_value);
        // Keeping valid asserted after acknowledgement cannot repeat a step.
        repeat (12) begin
            @(negedge source_clk);
            assert (!source_busy && !source_ack && !source_ready);
            assert (!destination_valid);
        end
        assert (acknowledgements == sequence_id);
        assert (completions == sequence_id);
    endtask

    initial begin
        $dumpfile("build/sim/nes_debug_command_cdc.fst");
        $dumpvars(0, nes_debug_command_cdc_tb);
        #200;
        @(negedge source_clk);
        source_reset = 1'b0;
        @(negedge destination_clk);
        destination_reset = 1'b0;
        // A control held high through reset must not create a phantom token.
        repeat (12) @(negedge source_clk);
        assert (!source_ready && !source_busy && !destination_valid);
        assert (acknowledgements == 0 && completions == 0);
        for (integer sequence_id = 1; sequence_id <= 48; sequence_id++)
            transaction(sequence_id);

        // Abort a request in flight with the shared board reset. The source
        // must rearm and the first new request must restart at sequence 1.
        arm_source();
        source_valid = 1'b1;
        source_command = 3'd2;
        do @(negedge destination_clk); while (!destination_valid);
        assert (destination_sequence == 16'd49);
        source_reset = 1'b1;
        destination_reset = 1'b1;
        #200;
        @(negedge source_clk);
        source_reset = 1'b0;
        @(negedge destination_clk);
        destination_reset = 1'b0;
        repeat (12) @(negedge source_clk);
        assert (!source_busy && !source_ack && !destination_valid);
        assert (source_ack_sequence == 16'd0);
        transaction(1);
        $display("PASS: debugger command CDC asynchronous clocks tokens=49 held-valid reset-in-flight payload/response/ack coherence");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "debugger command CDC timeout");
    end
endmodule
