`timescale 1ns/1ps

module adv7513_config_engine_tb;
    import hdmi_tx_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start_config = 1'b0;
    logic start_verify = 1'b0;
    logic busy, done, failed;
    logic [7:0] failure_code;
    logic transmitter_seen;
    logic command_valid;
    logic command_ready = 1'b1;
    logic command_read;
    logic [6:0] command_device_address;
    logic [7:0] command_register_address, command_write_data;
    logic response_valid = 1'b0;
    logic response_nack = 1'b0;
    logic response_timeout = 1'b0;
    logic [7:0] response_read_data = '0;
    logic pending = 1'b0;
    logic pending_read;
    logic [7:0] pending_register, pending_write_data;
    logic [7:0] registers [0:255];
    integer inject_nacks = 0;
    integer inject_timeouts = 0;
    integer command_count = 0;
    integer write_count = 0;
    integer failures = 0;
    integer index;

    always #5 clk = !clk;

    adv7513_config_engine dut (.*);

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL: %s", message);
            failures = failures + 1;
        end
    endtask

    always_ff @(posedge clk) begin
        response_valid <= pending;
        response_nack <= 1'b0;
        response_timeout <= 1'b0;
        if (pending) begin
            if (inject_timeouts > 0) begin
                response_timeout <= 1'b1;
                inject_timeouts <= inject_timeouts - 1;
            end else if (inject_nacks > 0) begin
                response_nack <= 1'b1;
                inject_nacks <= inject_nacks - 1;
            end else if (pending_read) begin
                response_read_data <= registers[pending_register];
            end else begin
                registers[pending_register] <= pending_write_data;
                write_count <= write_count + 1;
            end
        end
        pending <= command_valid && command_ready;
        if (command_valid && command_ready) begin
            check(command_device_address == ADV7513_MAIN_ADDRESS,
                  "profile accesses only the ADV7513 main map");
            pending_read <= command_read;
            pending_register <= command_register_address;
            pending_write_data <= command_write_data;
            command_count <= command_count + 1;
        end
    end

    task automatic pulse_config;
        begin
            @(negedge clk);
            start_config = 1'b1;
            @(negedge clk);
            start_config = 1'b0;
        end
    endtask

    task automatic pulse_verify;
        begin
            @(negedge clk);
            start_verify = 1'b1;
            @(negedge clk);
            start_verify = 1'b0;
        end
    endtask

    task automatic wait_result;
        integer cycles;
        begin
            cycles = 0;
            while (!done && !failed && cycles < 2000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check(done || failed, "configuration operation is bounded");
            check(!busy, "engine leaves busy state after result");
        end
    endtask

    initial begin
        for (index = 0; index < 256; index = index + 1)
            registers[index] = 8'(index ^ 8'h5a);
        repeat (4) @(posedge clk);
        reset = 1'b0;

        pulse_config();
        wait_result();
        check(done && !failed, "ordered configuration completes");
        check(command_count == 48 && write_count == 24,
              "24 read/modify/write entries are executed");
        check(registers[8'h98] == 8'h03, "fixed register is programmed");
        check((registers[8'h3c] & 8'h3f) == 8'h04,
              "720p60 VIC is programmed");
        check((registers[8'haf] & 8'h82) == 8'h02,
              "HDMI enabled with HDCP disabled");
        check((registers[8'h0b] & 8'h80) == 0 &&
              (registers[8'h0c] & 8'h3c) == 0,
              "audio remains disabled for Phase 6C");
        check(transmitter_seen, "successful access detects transmitter");

        command_count = 0;
        write_count = 0;
        pulse_verify();
        wait_result();
        check(done && command_count == 24 && write_count == 0,
              "readback is a distinct read-only pass");

        registers[8'h98] = 8'h02;
        pulse_verify();
        wait_result();
        check(failed && failure_code == HDMI_CONFIG_VERIFY_FAILED,
              "readback mismatch has stable failure code");
        registers[8'h98] = 8'h03;

        inject_nacks = 3;
        pulse_verify();
        wait_result();
        check(failed && failure_code == HDMI_TX_I2C_NACK,
              "NACK retries are bounded and typed");

        inject_timeouts = 3;
        pulse_verify();
        wait_result();
        check(failed && failure_code == HDMI_TX_I2C_TIMEOUT,
              "timeout retries are bounded and typed");

        if (failures == 0) begin
            $display("Phase 6C ADV7513 configuration/readback/failure test passed");
            $finish;
        end else begin
            $fatal(1, "Phase 6C configuration test failed: %0d checks", failures);
        end
    end
endmodule
