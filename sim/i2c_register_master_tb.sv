`timescale 1ns/1ps

module i2c_register_master_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic command_valid = 1'b0;
    logic command_ready;
    logic command_read = 1'b0;
    logic [6:0] command_device_address = '0;
    logic [7:0] command_register_address = '0;
    logic [7:0] command_write_data = '0;
    logic response_valid, response_ack, response_nack, response_timeout;
    logic [7:0] response_read_data;
    logic bus_recovery_pulse;
    logic scl_drive_low, sda_drive_low;
    logic slave_scl_low = 1'b0;
    logic slave_sda_low = 1'b0;
    wire scl_in = !(scl_drive_low || slave_scl_low);
    wire sda_in = !(sda_drive_low || slave_sda_low);
    integer starts = 0;
    integer stops = 0;
    integer failures = 0;
    integer test_stage = 0;
    logic recovery_seen = 1'b0;

    always #5 clk = !clk;
    always @(posedge clk) if (bus_recovery_pulse) recovery_seen = 1'b1;
    always @(posedge sda_drive_low) if (scl_in) starts = starts + 1;
    always @(negedge sda_drive_low) if (scl_in) stops = stops + 1;

    i2c_register_master #(
        .CLOCKS_PER_HALF_PERIOD(4),
        .STRETCH_TIMEOUT_CYCLES(24)
    ) dut (.*);

    initial begin
        #2ms;
        $fatal(1, "I2C testbench watchdog expired at stage %0d in state %0d",
               test_stage, dut.state);
    end

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL: %s", message);
            failures = failures + 1;
        end
    endtask

    task automatic read_master_byte(output logic [7:0] value,
                                    input logic acknowledge);
        integer bit_number;
        begin
            value = '0;
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                @(posedge scl_in);
                value[bit_number] = sda_in;
            end
            @(negedge scl_in);
            slave_sda_low = acknowledge;
            @(posedge scl_in);
            @(negedge scl_in);
            slave_sda_low = 1'b0;
        end
    endtask

    task automatic wait_start;
        begin
            @(negedge sda_in);
            while (!scl_in) @(negedge sda_in);
        end
    endtask

    task automatic provide_slave_byte(input logic [7:0] value);
        integer bit_number;
        begin
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                slave_sda_low = !value[bit_number];
                @(posedge scl_in);
                @(negedge scl_in);
            end
            slave_sda_low = 1'b0;
            // Master NACK clock.
            @(posedge scl_in);
            check(sda_in, "master must NACK final read byte");
            @(negedge scl_in);
        end
    endtask

    task automatic issue(input logic read_operation,
                         input logic [7:0] register_value,
                         input logic [7:0] write_value);
        begin
            @(negedge clk);
            check(command_ready, "command accepted only when ready");
            command_read = read_operation;
            command_device_address = 7'h39;
            command_register_address = register_value;
            command_write_data = write_value;
            command_valid = 1'b1;
            @(negedge clk);
            command_valid = 1'b0;
        end
    endtask

    task automatic wait_response;
        integer cycles;
        begin
            cycles = 0;
            while (!response_valid && cycles < 2000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            check(response_valid, "bounded response");
        end
    endtask

    initial begin
        logic [7:0] observed;
        repeat (4) @(posedge clk);
        reset = 1'b0;

        // Complete write with three slave ACKs.
        test_stage = 1;
        fork
            begin
                wait_start();
                read_master_byte(observed, 1'b1);
                check(observed == 8'h72, "write address byte");
                read_master_byte(observed, 1'b1);
                check(observed == 8'h98, "register byte");
                read_master_byte(observed, 1'b1);
                check(observed == 8'h03, "write data byte");
            end
            issue(1'b0, 8'h98, 8'h03);
        join
        wait_response();
        check(response_ack && !response_nack && !response_timeout,
              "write ACK response");
        if (starts != 1 || stops != 1)
            $display("write event counts starts=%0d stops=%0d", starts, stops);
        check(starts == 1 && stops == 1, "one START and STOP for write");

        // Register read must include a repeated START and return one byte.
        test_stage = 2;
        fork
            begin
                wait_start();
                read_master_byte(observed, 1'b1);
                check(observed == 8'h72, "read write-address byte");
                read_master_byte(observed, 1'b1);
                check(observed == 8'h42, "read register byte");
                wait_start();
                read_master_byte(observed, 1'b1);
                check(observed == 8'h73, "read address byte");
                provide_slave_byte(8'h40);
            end
            issue(1'b1, 8'h42, 8'h00);
        join
        wait_response();
        check(response_ack && response_read_data == 8'h40,
              "read response data");
        check(starts == 3 && stops == 2,
              "read contributes START, repeated START, and STOP");

        // Address NACK still terminates with STOP and a typed response.
        test_stage = 3;
        fork
            begin
                wait_start();
                read_master_byte(observed, 1'b0);
            end
            issue(1'b0, 8'h00, 8'h00);
        join
        wait_response();
        check(response_nack && !response_ack, "NACK response");

        // A held-low SCL is a bounded clock-stretch timeout.
        test_stage = 4;
        slave_scl_low = 1'b1;
        issue(1'b0, 8'h00, 8'h00);
        wait_response();
        check(response_timeout, "clock stretching timeout");
        slave_scl_low = 1'b0;
        repeat (4) @(posedge clk);

        // A stuck SDA invokes bus clear.  Release it on the fourth pulse and
        // then serve the original command normally.
        test_stage = 5;
        slave_sda_low = 1'b1;
        repeat (3) @(posedge clk);
        fork
            begin
                repeat (4) @(posedge scl_in);
                @(negedge scl_in);
                slave_sda_low = 1'b0;
                wait_start();
                read_master_byte(observed, 1'b1);
                read_master_byte(observed, 1'b1);
                read_master_byte(observed, 1'b1);
            end
            issue(1'b0, 8'h9c, 8'h30);
        join
        wait_response();
        check(response_ack, "transaction succeeds after bus recovery");
        check(recovery_seen, "bus recovery is reported");

        if (failures == 0) begin
            $display("Phase 6C I2C START/STOP/ACK/NACK/read/timeout/recovery passed");
            $finish;
        end else begin
            $fatal(1, "Phase 6C I2C test failed: %0d checks", failures);
        end
    end
endmodule
