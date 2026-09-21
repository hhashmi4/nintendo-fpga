`timescale 1ns/1ps

module nes_controller_phase4c_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] controller1_buttons = 8'h00;
    logic [7:0] controller2_buttons = 8'h00;
    logic cpu_port = 1'b0;
    logic cpu_read = 1'b0;
    logic cpu_write = 1'b0;
    logic [7:0] cpu_write_data = 8'h00;
    logic [7:0] cpu_read_data;
    logic debug_strobe;
    logic [7:0] debug_live_controller1;
    logic [7:0] debug_live_controller2;
    logic [7:0] debug_shift_controller1;
    logic [7:0] debug_shift_controller2;
    logic [3:0] debug_index_controller1;
    logic [3:0] debug_index_controller2;
    logic debug_serial_controller1;
    logic debug_serial_controller2;
    logic debug_read_4016;
    logic debug_read_4017;
    logic debug_latch_event;
    logic [7:0] async_buttons = 8'h00;
    logic [7:0] synced_buttons;
    int checks = 0;

    always #5 clk <= !clk;

    nes_controller dut (
        .clk(clk),
        .reset(reset),
        .controller1_buttons(controller1_buttons),
        .controller2_buttons(controller2_buttons),
        .cpu_port(cpu_port),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_write_data(cpu_write_data),
        .cpu_read_data(cpu_read_data),
        .debug_strobe(debug_strobe),
        .debug_live_controller1(debug_live_controller1),
        .debug_live_controller2(debug_live_controller2),
        .debug_shift_controller1(debug_shift_controller1),
        .debug_shift_controller2(debug_shift_controller2),
        .debug_index_controller1(debug_index_controller1),
        .debug_index_controller2(debug_index_controller2),
        .debug_serial_controller1(debug_serial_controller1),
        .debug_serial_controller2(debug_serial_controller2),
        .debug_read_4016(debug_read_4016),
        .debug_read_4017(debug_read_4017),
        .debug_latch_event(debug_latch_event)
    );

    controller_input_sync #(.WIDTH(8)) input_synchronizer (
        .clk(clk),
        .reset(reset),
        .async_buttons(async_buttons),
        .synced_buttons(synced_buttons)
    );

    task automatic write_strobe(input logic value);
        @(negedge clk);
        cpu_port = 1'b0;
        cpu_read = 1'b0;
        cpu_write_data = {7'h00, value};
        cpu_write = 1'b1;
        #1;
        if (debug_strobe && !value)
            assert (debug_latch_event);
        @(posedge clk);
        #1;
        cpu_write = 1'b0;
        checks++;
    endtask

    task automatic latch_controllers;
        write_strobe(1'b1);
        assert (debug_strobe);
        write_strobe(1'b0);
        assert (!debug_strobe);
        assert (debug_index_controller1 == 4'd0);
        assert (debug_index_controller2 == 4'd0);
        assert (debug_live_controller1 == controller1_buttons);
        assert (debug_live_controller2 == controller2_buttons);
    endtask

    task automatic read_serial(
        input logic port,
        output logic value
    );
        @(negedge clk);
        cpu_port = port;
        cpu_write = 1'b0;
        cpu_read = 1'b1;
        #1;
        value = cpu_read_data[0];
        assert (value == (port ? debug_serial_controller2 :
                                debug_serial_controller1));
        assert (cpu_read_data[7:1] == 7'h00);
        assert (port ? debug_read_4017 : debug_read_4016);
        assert (!(port ? debug_read_4016 : debug_read_4017));
        @(posedge clk);
        #1;
        cpu_read = 1'b0;
        checks++;
    endtask

    task automatic check_port(
        input logic port,
        input logic [7:0] state
    );
        logic value;
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            read_serial(port, value);
            assert (value == state[bit_index])
                else $fatal(1, "port=%0d state=%02x bit=%0d got=%0d",
                            port, state, bit_index, value);
        end
        for (int extra = 0; extra < 4; extra++) begin
            read_serial(port, value);
            assert (value == 1'b1)
                else $fatal(1, "port=%0d post-eight read was zero", port);
        end
        assert (port ? debug_index_controller2 == 4'd8 :
                       debug_index_controller1 == 4'd8);
    endtask

    initial begin
        $dumpfile("build/sim/nes_controller_phase4c.fst");
        $dumpvars(0, nes_controller_phase4c_tb);

        // Reset wins over active-looking bus inputs and produces no events.
        cpu_read = 1'b1;
        cpu_write = 1'b1;
        cpu_port = 1'b1;
        cpu_write_data = 8'h01;
        repeat (3) @(posedge clk);
        #1;
        assert (cpu_read_data == 8'h00);
        assert (!debug_strobe);
        assert (debug_shift_controller1 == 8'h00);
        assert (debug_shift_controller2 == 8'h00);
        assert (debug_index_controller1 == 4'd0);
        assert (debug_index_controller2 == 4'd0);
        assert (!(debug_read_4016 || debug_read_4017 || debug_latch_event));
        cpu_read = 1'b0;
        cpu_write = 1'b0;
        reset = 1'b0;

        // The physical-input boundary is a deterministic two-flop pipeline.
        @(negedge clk);
        async_buttons = 8'h5a;
        @(posedge clk);
        #1;
        assert (synced_buttons == 8'h00);
        @(posedge clk);
        #1;
        assert (synced_buttons == 8'h5a);
        async_buttons = 8'ha5;
        @(posedge clk);
        #1;
        assert (synced_buttons == 8'h5a);
        @(posedge clk);
        #1;
        assert (synced_buttons == 8'ha5);
        checks += 4;

        // High strobe follows the live A buttons and never advances indices.
        write_strobe(1'b1);
        for (int state = 0; state < 4; state++) begin
            logic value;
            controller1_buttons = state[0] ? 8'h01 : 8'hfe;
            controller2_buttons = state[1] ? 8'hff : 8'h00;
            read_serial(1'b0, value);
            assert (value == controller1_buttons[0]);
            read_serial(1'b1, value);
            assert (value == controller2_buttons[0]);
            assert (debug_index_controller1 == 4'd0);
            assert (debug_index_controller2 == 4'd0);
        end

        // Exhaust all 256 button combinations on each independent port.
        for (int state = 0; state < 256; state++) begin
            controller1_buttons = state[7:0];
            controller2_buttons = ~state[7:0];
            latch_controllers();
            assert (debug_shift_controller1 == state[7:0]);
            assert (debug_shift_controller2 == ~state[7:0]);
            check_port(1'b0, state[7:0]);
            assert (debug_index_controller2 == 4'd0);
        end
        for (int state = 0; state < 256; state++) begin
            controller1_buttons = state[7:0] ^ 8'ha5;
            controller2_buttons = state[7:0];
            latch_controllers();
            check_port(1'b1, state[7:0]);
            assert (debug_index_controller1 == 4'd0);
        end

        // Interleave reads to prove that each port shifts only itself.
        controller1_buttons = 8'h81;
        controller2_buttons = 8'h42;
        latch_controllers();
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            logic value;
            read_serial(1'b0, value);
            assert (value == controller1_buttons[bit_index]);
            assert (debug_index_controller1 == bit_index[3:0] + 4'd1);
            assert (debug_index_controller2 == bit_index[3:0]);
            read_serial(1'b1, value);
            assert (value == controller2_buttons[bit_index]);
        end

        // Input changes after a latch do not affect the current serial poll.
        controller1_buttons = 8'h3c;
        controller2_buttons = 8'hc3;
        latch_controllers();
        controller1_buttons = 8'ha5;
        controller2_buttons = 8'h5a;
        check_port(1'b0, 8'h3c);
        check_port(1'b1, 8'hc3);
        latch_controllers();
        check_port(1'b0, 8'ha5);
        check_port(1'b1, 8'h5a);

        $display("PASS: Phase 4C NES controllers (checks=%0d exhaustive_states=512)",
                 checks);
        $finish;
    end
endmodule
