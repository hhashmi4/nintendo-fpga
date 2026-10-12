`timescale 1ns/1ps

module hdmi_audio_control_tb;
    import hdmi_audio_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic video_ready = 1'b0;
    logic hpd_stable = 1'b0;
    logic audio_clock_locked = 1'b0;
    logic primed = 1'b0;
    logic user_mute = 1'b0;
    logic clear_fault = 1'b0;
    logic [31:0] underruns = '0, overruns = '0;
    logic configured, enabled, muted, clock_locked;
    logic accept_samples, stream_enable, fifo_flush, fault;
    logic [3:0] state_debug;
    logic [31:0] reconnect_count;
    logic [7:0] last_error;
    logic command_valid, command_ready, command_read;
    logic [6:0] command_device;
    logic [7:0] command_register, command_write_data;
    logic response_valid = 1'b0;
    logic response_nack = 1'b0;
    logic response_timeout = 1'b0;
    logic [7:0] response_read_data = '0;
    logic [7:0] registers [0:255];
    logic pending = 1'b0;
    logic pending_read;
    logic [7:0] pending_register, pending_write_data;
    integer force_nacks = 0;
    integer force_timeouts = 0;
    logic corrupt_verify = 1'b0;
    logic [3:0] previous_state = 4'hf;
    logic [15:0] random_samples [0:255];
    integer test_cycles = 0;

    always #10 clk = !clk;
    assign command_ready = !pending;

    always_ff @(posedge clk) begin
        test_cycles <= test_cycles + 1;
        if (state_debug != previous_state) begin
            $display("audio state=%0d error=%0d time=%0t", state_debug,
                     last_error, $time);
            previous_state <= state_debug;
        end
    end

    hdmi_audio_controller #(
        .CLOCK_WAIT_TIMEOUT(20),
        .PRIME_TIMEOUT(40),
        .RECOVERY_DELAY_CYCLES(4),
        .MAX_RECOVERIES(1)
    ) dut (
        .clk(clk), .reset(reset), .video_ready(video_ready),
        .hpd_stable(hpd_stable),
        .audio_clock_locked_async(audio_clock_locked),
        .transport_primed(primed), .user_mute(user_mute),
        .clear_fault(clear_fault), .fifo_underruns(underruns),
        .fifo_overruns(overruns), .configured(configured),
        .enabled(enabled), .muted(muted), .clock_locked(clock_locked),
        .accept_samples(accept_samples), .stream_enable(stream_enable),
        .fifo_flush(fifo_flush), .fault(fault), .state_debug(state_debug),
        .reconnect_count(reconnect_count), .last_error(last_error),
        .command_valid(command_valid), .command_ready(command_ready),
        .command_read(command_read),
        .command_device_address(command_device),
        .command_register_address(command_register),
        .command_write_data(command_write_data),
        .response_valid(response_valid), .response_nack(response_nack),
        .response_timeout(response_timeout),
        .response_read_data(response_read_data)
    );

    always_ff @(posedge clk) begin
        response_valid <= 1'b0;
        response_nack <= 1'b0;
        response_timeout <= 1'b0;
        if (pending) begin
            pending <= 1'b0;
            response_valid <= 1'b1;
            if (force_timeouts > 0) begin
                force_timeouts <= force_timeouts - 1;
                response_timeout <= 1'b1;
            end else if (force_nacks > 0) begin
                force_nacks <= force_nacks - 1;
                response_nack <= 1'b1;
            end else if (pending_read) begin
                response_read_data <= registers[pending_register] ^
                    ((corrupt_verify &&
                      state_debug == HDMI_AUDIO_STATE_VERIFY_CONFIG &&
                      pending_register == 8'h15) ? 8'h10 : 8'h00);
            end else begin
                registers[pending_register] <= pending_write_data;
            end
        end
        if (command_valid && command_ready) begin
            if (command_device != 7'h39)
                $fatal(1, "unexpected audio I2C device address");
            pending <= 1'b1;
            pending_read <= command_read;
            pending_register <= command_register;
            pending_write_data <= command_write_data;
        end
    end

    task automatic wait_state(input logic [3:0] wanted);
        integer guard;
        begin
            guard = 0;
            while (state_debug != wanted && guard < 5000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (state_debug != wanted)
                $fatal(1, "state timeout wanted=%0d got=%0d error=%0d configured=%0b",
                       wanted, state_debug, last_error, configured);
        end
    endtask

    initial begin
        for (integer index = 0; index < 256; index = index + 1)
            registers[index] = 8'h5a;
        repeat (5) @(posedge clk);
        reset = 1'b0;
        wait_state(HDMI_AUDIO_STATE_WAIT_VIDEO);
        if (!muted || !fifo_flush)
            $fatal(1, "startup must be muted and flushed");

        hpd_stable = 1'b1;
        video_ready = 1'b1;
        audio_clock_locked = 1'b1;
        wait_state(HDMI_AUDIO_STATE_PRIME_AUDIO);
        if (!configured || !accept_samples || stream_enable)
            $fatal(1, "prime state contract failed");
        if ((registers[8'h44] & 8'h68) != 8'h68 ||
            (registers[8'h4a] & 8'h20) != 0 ||
            registers[8'h0c] != 8'hc4)
            $fatal(1, "documented audio register profile mismatch");

        primed = 1'b1;
        wait_state(HDMI_AUDIO_STATE_RUNNING);
        if (!enabled || muted || !stream_enable)
            $fatal(1, "running enable contract failed");

        @(negedge clk);
        user_mute = 1'b1;
        wait_state(HDMI_AUDIO_STATE_MUTED);
        if (!enabled || !muted || !stream_enable)
            $fatal(1, "user mute must retain transport consumption");
        @(negedge clk);
        user_mute = 1'b0;
        wait_state(HDMI_AUDIO_STATE_RUNNING);

        @(negedge clk);
        hpd_stable = 1'b0;
        video_ready = 1'b0;
        wait_state(HDMI_AUDIO_STATE_WAIT_VIDEO);
        if (last_error != HDMI_AUDIO_LINK_LOST || !fifo_flush)
            $fatal(1, "disconnect did not latch/flush");
        @(negedge clk);
        hpd_stable = 1'b1;
        video_ready = 1'b1;
        primed = 1'b0;
        wait_state(HDMI_AUDIO_STATE_PRIME_AUDIO);
        if (reconnect_count != 1)
            $fatal(1, "reconnect counter mismatch");
        primed = 1'b1;
        wait_state(HDMI_AUDIO_STATE_RUNNING);

        @(negedge clk);
        clear_fault = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear_fault = 1'b0;
        if (last_error != HDMI_AUDIO_ERROR_NONE)
            $fatal(1, "explicit fault clear failed");

        @(negedge clk);
        underruns = underruns + 1'b1;
        wait_state(HDMI_AUDIO_STATE_RECOVERY);
        if (last_error != HDMI_AUDIO_FIFO_UNDERRUN || !muted)
            $fatal(1, "underrun recovery contract failed");

        // A fresh controller instance is unnecessary for NACK/timeout mapping:
        // force a disconnect/reconnect, then exhaust the config retry budget.
        @(negedge clk);
        video_ready = 1'b0;
        hpd_stable = 1'b0;
        wait_state(HDMI_AUDIO_STATE_WAIT_VIDEO);
        @(negedge clk);
        video_ready = 1'b1;
        hpd_stable = 1'b1;
        force_nacks = 3;
        wait_state(HDMI_AUDIO_STATE_FAULT);
        if (last_error != HDMI_AUDIO_CONFIG_NACK)
            $fatal(1, "NACK mapping mismatch code=%0d", last_error);

        // Timeout and independent readback corruption have distinct codes.
        reset = 1'b1;
        video_ready = 1'b0;
        hpd_stable = 1'b0;
        primed = 1'b0;
        repeat (4) @(posedge clk);
        reset = 1'b0;
        video_ready = 1'b1;
        hpd_stable = 1'b1;
        force_timeouts = 3;
        wait_state(HDMI_AUDIO_STATE_FAULT);
        if (last_error != HDMI_AUDIO_CONFIG_TIMEOUT)
            $fatal(1, "timeout mapping mismatch code=%0d", last_error);

        reset = 1'b1;
        video_ready = 1'b0;
        hpd_stable = 1'b0;
        repeat (4) @(posedge clk);
        reset = 1'b0;
        corrupt_verify = 1'b1;
        video_ready = 1'b1;
        hpd_stable = 1'b1;
        wait_state(HDMI_AUDIO_STATE_FAULT);
        if (last_error != HDMI_AUDIO_CONFIG_VERIFY_FAILED)
            $fatal(1, "verify mapping mismatch code=%0d", last_error);

        // Finally establish a fresh stream and revoke its audio clock.
        reset = 1'b1;
        video_ready = 1'b0;
        hpd_stable = 1'b0;
        corrupt_verify = 1'b0;
        repeat (4) @(posedge clk);
        reset = 1'b0;
        video_ready = 1'b1;
        hpd_stable = 1'b1;
        primed = 1'b1;
        wait_state(HDMI_AUDIO_STATE_RUNNING);
        @(negedge clk);
        audio_clock_locked = 1'b0;
        wait_state(HDMI_AUDIO_STATE_RECOVERY);
        if (last_error != HDMI_AUDIO_CLOCK_UNLOCKED || enabled)
            $fatal(1, "audio clock unlock did not fail closed");

        $readmemh("build/sim/phase6d_random_pcm.hex", random_samples);
        for (integer trial = 0; trial < 16; trial++) begin
            @(negedge clk);
            reset = 1;
            video_ready = 0; hpd_stable = 0; primed = 0;
            force_nacks = 0; force_timeouts = 0; corrupt_verify = 0;
            audio_clock_locked = 1;
            repeat (4) @(negedge clk);
            reset = 0;
            repeat (2 + int'(random_samples[trial][3:0])) @(negedge clk);
            video_ready = 1; hpd_stable = 1;
            case (random_samples[trial][5:4])
                0: force_nacks = 3;
                1: force_timeouts = 3;
                2: corrupt_verify = 1;
                3: force_nacks = 1; // A transient NACK must recover in-stage.
            endcase
            if (random_samples[trial][5:4] != 3) begin
                wait_state(HDMI_AUDIO_STATE_FAULT);
                if (last_error != 8'(2 + int'(random_samples[trial][5:4])))
                    $fatal(1, "random config fault mapping trial=%0d code=%0d", trial, last_error);
                corrupt_verify = 0;
            end
            wait_state(HDMI_AUDIO_STATE_PRIME_AUDIO);
            repeat (1 + int'(random_samples[trial][9:6])) @(negedge clk);
            primed = 1;
            wait_state(HDMI_AUDIO_STATE_RUNNING);
            @(negedge clk); user_mute = 1;
            wait_state(HDMI_AUDIO_STATE_MUTED);
            repeat (1 + int'(random_samples[trial][13:10])) @(negedge clk);
            user_mute = 0;
            wait_state(HDMI_AUDIO_STATE_RUNNING);
            @(negedge clk); overruns = overruns + 1;
            wait_state(HDMI_AUDIO_STATE_RECOVERY);
            if (last_error != HDMI_AUDIO_FIFO_OVERRUN) $fatal(1, "overrun fault");
            @(negedge clk); hpd_stable = 0; video_ready = 0;
            wait_state(HDMI_AUDIO_STATE_WAIT_VIDEO);
            repeat (1 + int'(random_samples[trial][15:12])) @(negedge clk);
            video_ready = 1; hpd_stable = 1;
            wait_state(HDMI_AUDIO_STATE_RUNNING);
        end
        // Persistent readback failure exhausts the recovery budget. Clear is
        // explicit, after removing the detectable cause, then normal startup.
        @(negedge clk); hpd_stable = 0; video_ready = 0;
        wait_state(HDMI_AUDIO_STATE_WAIT_VIDEO);
        @(negedge clk); hpd_stable = 1; video_ready = 1; corrupt_verify = 1;
        repeat (3000) @(negedge clk);
        if (last_error != HDMI_AUDIO_RECOVERY_FAILED || enabled || !muted)
            $fatal(1, "recovery exhaustion did not fail closed");
        corrupt_verify = 0; clear_fault = 1;
        @(negedge clk); clear_fault = 0;
        wait_state(HDMI_AUDIO_STATE_RUNNING);
        if (last_error != HDMI_AUDIO_ERROR_NONE) $fatal(1, "recovery clear failed");

        $display("Phase 6D randomized control passed: seed=0x6d480001 trials=16 cycles=%0d mismatches=0", test_cycles);

        $display("Phase 6D HDMI audio control passed: reconnects=%0d last_error=%0d",
                 reconnect_count, last_error);
        $finish;
    end
endmodule
