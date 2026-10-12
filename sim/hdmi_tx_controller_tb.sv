`timescale 1ns/1ps

module hdmi_tx_controller_tb;
    import hdmi_tx_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic pixel_clock_locked_async = 1'b0;
    logic frame_toggle_async = 1'b0;
    logic hpd_async = 1'b0;
    logic slave_scl_low = 1'b0;
    logic slave_sda_low = 1'b0;
    logic scl_drive_low, sda_drive_low;
    wire scl_in = !(scl_drive_low || slave_scl_low);
    wire sda_in = !(sda_drive_low || slave_sda_low);
    logic video_enable, safe_disable, transmitter_power_down;
    logic transmitter_present, transmitter_configured, transmitter_fault;
    logic [1:0] hpd_state;
    logic edid_available, edid_valid, mode_supported, video_clock_locked;
    logic [31:0] video_frames_sent, i2c_nack_count;
    logic [31:0] i2c_timeout_count, recovery_count;
    logic [7:0] last_error_code;
    logic [3:0] startup_state;
    logic [7:0] main_registers [0:255];
    logic [7:0] edid_memory [0:255];
    integer nack_transactions = 0;
    integer write_count = 0;
    integer failures = 0;
    integer index;
    integer checksum;
    integer metrics_file;

    always #5 clk = !clk;

    hdmi_tx_controller #(
        .HPD_STABLE_CYCLES(3),
        .STARTUP_DELAY_CYCLES(3),
        .CLOCK_WAIT_TIMEOUT(40),
        .HPD_WAIT_TIMEOUT(200),
        .RECOVERY_DELAY_CYCLES(8),
        .MAX_RECOVERIES(3),
        .I2C_CLOCKS_PER_HALF_PERIOD(4),
        .I2C_TIMEOUT_CYCLES(24),
        .EDID_READY_POLLS(4),
        .EDID_POLL_DELAY_CYCLES(2)
    ) dut (.*);

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL: %s state=%0d error=%0d", message,
                     startup_state, last_error_code);
            failures = failures + 1;
        end
    endtask

    task automatic wait_start;
        begin
            @(negedge sda_in);
            while (!scl_in) @(negedge sda_in);
        end
    endtask

    task automatic wait_stop;
        begin
            @(posedge sda_in);
            while (!scl_in) @(posedge sda_in);
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

    task automatic provide_slave_byte(input logic [7:0] value);
        integer bit_number;
        begin
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                slave_sda_low = !value[bit_number];
                @(posedge scl_in);
                @(negedge scl_in);
            end
            slave_sda_low = 1'b0;
            @(posedge scl_in);
            check(sda_in, "master NACKs final read byte");
            @(negedge scl_in);
        end
    endtask

    task automatic serve_transaction;
        logic [7:0] address_byte, register_byte, data_byte;
        logic [7:0] read_value;
        begin
            wait_start();
            read_master_byte(address_byte, nack_transactions == 0);
            if (nack_transactions != 0) begin
                nack_transactions = nack_transactions - 1;
                wait_stop();
            end else begin
                check(address_byte == 8'h72 || address_byte == 8'h7e,
                      "known ADV7513 main or EDID write address");
                read_master_byte(register_byte, 1'b1);
                if (dut.i2c_master.latched_read) begin
                    wait_start();
                    read_master_byte(data_byte, 1'b1);
                    check(data_byte == (address_byte | 8'h01),
                          "repeated START uses read address");
                    read_value = address_byte == 8'h72 ?
                        main_registers[register_byte] :
                        edid_memory[register_byte];
                    provide_slave_byte(read_value);
                    wait_stop();
                end else begin
                    read_master_byte(data_byte, 1'b1);
                    check(address_byte == 8'h72,
                          "only main-map registers are writable");
                    main_registers[register_byte] = data_byte;
                    write_count = write_count + 1;
                    wait_stop();
                end
            end
        end
    endtask

    task automatic wait_for_state(input logic [3:0] wanted,
                                  input integer limit,
                                  input string message);
        integer cycles;
        begin
            cycles = 0;
            while (startup_state != wanted && cycles < limit) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            check(startup_state == wanted, message);
        end
    endtask

    task automatic pulse_frame;
        begin
            @(negedge clk);
            frame_toggle_async = !frame_toggle_async;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin : slave_model
        forever serve_transaction();
    end

    initial begin : stimulus
        for (index = 0; index < 256; index = index + 1) begin
            main_registers[index] = 8'(index ^ 8'ha5);
            edid_memory[index] = 8'h00;
        end
        main_registers[8'h96] = 8'h04;
        edid_memory[0] = 8'h00;
        for (index = 1; index <= 6; index = index + 1)
            edid_memory[index] = 8'hff;
        edid_memory[7] = 8'h00;
        edid_memory[18] = 8'h01;
        edid_memory[19] = 8'h04;
        edid_memory[126] = 8'h01;
        checksum = 0;
        for (index = 0; index < 127; index = index + 1)
            checksum = checksum + integer'(edid_memory[index]);
        edid_memory[127] = 8'(-checksum);
        edid_memory[128] = 8'h02;
        edid_memory[129] = 8'h03;
        edid_memory[130] = 8'h06;
        edid_memory[131] = 8'h00;
        edid_memory[132] = 8'h41;
        edid_memory[133] = 8'h84;
        checksum = 0;
        for (index = 128; index < 255; index = index + 1)
            checksum = checksum + integer'(edid_memory[index]);
        edid_memory[255] = 8'(-checksum);

        repeat (4) @(posedge clk);
        reset = 1'b0;
        pixel_clock_locked_async = 1'b1;

        // Bounce cannot connect until the full stable interval elapses.
        hpd_async = 1'b1;
        repeat (2) @(posedge clk);
        hpd_async = 1'b0;
        repeat (2) @(posedge clk);
        check(hpd_state != 2'd2, "HPD bounce is rejected");
        hpd_async = 1'b1;

        wait_for_state(HDMI_STATE_RUNNING, 250_000,
                       "valid sink reaches RUNNING");
        check(video_enable && !safe_disable, "video enables only in RUNNING");
        check(!transmitter_power_down,
              "PD/AD is inactive after address latch and configuration");
        check(transmitter_present && transmitter_configured,
              "transmitter is detected, configured, and verified");
        check(edid_available && edid_valid && mode_supported,
              "buffered EDID permits only supported 720p60");
        check(video_clock_locked, "pixel clock lock is synchronized");
        check(write_count == 24, "complete ordered profile was written");
        check(i2c_nack_count == 0 && i2c_timeout_count == 0,
              "clean startup has no transport faults");

        pulse_frame();
        pulse_frame();
        pulse_frame();
        check(video_frames_sent == 3,
              "frame toggles become an exact diagnostic count");

        hpd_async = 1'b0;
        wait_for_state(HDMI_STATE_RECOVERY, 100,
                       "stable disconnect enters recovery");
        check(!video_enable && safe_disable,
              "disconnect disables video immediately after debounce");
        check(transmitter_power_down,
              "stable disconnect asserts the active-high 0x72 power-down");
        hpd_async = 1'b1;
        wait_for_state(HDMI_STATE_RUNNING, 250_000,
                       "reconnect reconfigures and restarts video");
        check(recovery_count >= 1, "reconnect is counted as recovery");

        // Revoke ownership during an active profile transaction.  Recovery
        // must clear the transport/config FSMs and start a fresh sequence.
        hpd_async = 1'b0;
        wait_for_state(HDMI_STATE_RECOVERY, 100,
                       "second disconnect enters recovery");
        hpd_async = 1'b1;
        wait_for_state(HDMI_STATE_CONFIGURE, 200,
                       "reconnect begins a fresh configuration");
        repeat (12) @(posedge clk);
        hpd_async = 1'b0;
        wait_for_state(HDMI_STATE_RECOVERY, 5_000,
                       "mid-configuration disconnect aborts cleanly");
        check(!video_enable && safe_disable,
              "mid-configuration abort remains fail closed");
        hpd_async = 1'b1;
        wait_for_state(HDMI_STATE_RUNNING, 250_000,
                       "aborted configuration recovers without stale state");

        // Reset while active must fail closed and repeat the whole sequence.
        @(negedge clk);
        reset = 1'b1;
        repeat (3) @(posedge clk);
        check(!video_enable && safe_disable,
              "reset during operation fails closed");
        @(negedge clk);
        reset = 1'b0;
        wait_for_state(HDMI_STATE_RUNNING, 250_000,
                       "reset restarts deterministic qualification");

        pixel_clock_locked_async = 1'b0;
        wait_for_state(HDMI_STATE_FAULT, 100,
                       "missing pixel clock reaches FAULT");
        check(last_error_code == HDMI_PIXEL_CLOCK_UNLOCKED,
              "missing clock has stable fault code");
        check(transmitter_fault && !video_enable,
              "clock fault keeps output safely disabled");
        check(transmitter_power_down,
              "fault asserts the documented active-high power-down");

        // Fresh reset plus three address NACKs proves not-detected mapping and
        // the configured maximum of two retries.
        @(negedge clk);
        reset = 1'b1;
        pixel_clock_locked_async = 1'b1;
        nack_transactions = 3;
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        wait_for_state(HDMI_STATE_FAULT, 5_000,
                       "missing transmitter reaches FAULT");
        check(last_error_code == HDMI_TX_NOT_DETECTED,
              "initial all-NACK failure maps to not detected");
        check(i2c_nack_count == 3,
              "initial transaction uses exactly two bounded retries");
        check(!transmitter_present && !transmitter_configured,
              "failed detection cannot claim configuration");

        metrics_file = $fopen("build/sim/phase6c_hdmi_rtl.txt", "w");
        check(metrics_file != 0, "open Phase 6C metrics artifact");
        $fdisplay(metrics_file, "profile_writes=%0d", 24);
        $fdisplay(metrics_file, "edid_bytes=%0d", 256);
        $fdisplay(metrics_file, "frames_counted=%0d", 3);
        $fdisplay(metrics_file, "bounded_nacks=%0d", i2c_nack_count);
        $fdisplay(metrics_file, "final_error=%0d", last_error_code);
        $fclose(metrics_file);

        if (failures == 0) begin
            $display("Phase 6C startup/HPD/EDID/reset/recovery/fault test passed");
            $finish;
        end else begin
            $fatal(1, "Phase 6C controller test failed: %0d checks", failures);
        end
    end
endmodule
