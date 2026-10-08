`timescale 1ns/1ps

module nes_audio_phase5k_tb;
    logic clk = 1'b0;
    logic audio_clk = 1'b0;
    logic fifo_write_clk = 1'b0;
    logic fifo_read_clk = 1'b0;
    always #10 clk = !clk;
    always #27 audio_clk = !audio_clk;
    always #11 fifo_write_clk = !fifo_write_clk;
    always #17 fifo_read_clk = !fifo_read_clk;

    logic reset = 1'b1;
    logic resampler_reset;

    logic input_tick;
    logic [19:0] mixed_audio;
    logic resampler_valid;
    logic signed [31:0] filtered_sample;
    logic resampler_busy;
    logic schedule_overrun;
    logic [13:0] phase_debug;
    integer resampler_count;
    logic signed [31:0] expected_resampler_value;

    nes_audio_resampler resampler (
        .clk(clk), .reset(resampler_reset), .input_tick(input_tick),
        .mixed_audio(mixed_audio), .sample_valid(resampler_valid),
        .filtered_sample(filtered_sample), .busy(resampler_busy),
        .schedule_overrun(schedule_overrun), .phase_debug(phase_debug)
    );

    logic conditioner_reset;
    logic conditioner_valid;
    logic signed [31:0] conditioner_input;
    logic test_tone_enable;
    logic pcm_valid;
    logic signed [15:0] pcm_sample;
    logic saturation_event;

    nes_audio_conditioner conditioner (
        .clk(clk), .reset(conditioner_reset),
        .sample_valid(conditioner_valid),
        .filtered_sample(conditioner_input),
        .test_tone_enable(test_tone_enable), .pcm_valid(pcm_valid),
        .pcm_sample(pcm_sample), .saturation_event(saturation_event)
    );

    logic fifo_write_reset;
    logic fifo_write_enable;
    logic [15:0] fifo_write_data;
    logic fifo_full;
    logic fifo_overflow;
    logic [3:0] fifo_write_level;
    logic fifo_read_reset;
    logic fifo_read_enable;
    logic [15:0] fifo_read_data;
    logic fifo_empty;
    logic fifo_underflow;
    logic [3:0] fifo_read_level;

    audio_async_fifo #(.WIDTH(16), .DEPTH(8)) fifo (
        .write_clk(fifo_write_clk), .write_reset(fifo_write_reset),
        .write_enable(fifo_write_enable), .write_data(fifo_write_data),
        .full(fifo_full), .overflow_event(fifo_overflow),
        .write_level(fifo_write_level), .read_clk(fifo_read_clk),
        .read_reset(fifo_read_reset), .read_enable(fifo_read_enable),
        .read_data(fifo_read_data), .empty(fifo_empty),
        .underflow_event(fifo_underflow), .read_level(fifo_read_level)
    );

    logic i2s_reset;
    logic i2s_stream_enable;
    logic i2s_fifo_empty;
    logic signed [15:0] i2s_fifo_data;
    logic i2s_fifo_read;
    logic aud_bclk;
    logic aud_lrck;
    logic aud_data;
    logic i2s_muted;
    logic i2s_frame;
    logic i2s_transmitted;
    logic i2s_underrun;

    wm8731_i2s_tx serializer (
        .audio_clk(audio_clk), .reset(i2s_reset),
        .stream_enable(i2s_stream_enable), .fifo_empty(i2s_fifo_empty),
        .fifo_read_data(i2s_fifo_data), .fifo_read_enable(i2s_fifo_read),
        .aud_bclk(aud_bclk), .aud_daclrck(aud_lrck),
        .aud_dacdat(aud_data), .muted(i2s_muted),
        .frame_event(i2s_frame),
        .sample_transmitted_event(i2s_transmitted),
        .underrun_event(i2s_underrun)
    );

    logic cfg_scl_low;
    logic cfg_sda_low;
    logic cfg_slave_ack;
    wire cfg_scl = cfg_scl_low ? 1'b0 : 1'b1;
    wire cfg_sda = cfg_sda_low ? 1'b0 : (cfg_slave_ack ? 1'b0 : 1'b1);
    logic cfg_busy;
    logic cfg_done;
    logic cfg_error;
    logic [31:0] cfg_acks;
    logic [31:0] cfg_nacks;
    logic [31:0] cfg_timeouts;
    logic [31:0] cfg_retries;
    logic [7:0] cfg_fault;
    logic [3:0] cfg_index;

    wm8731_i2c_init #(
        .CLOCK_HZ(100), .I2C_HZ(10), .LOCK_TIMEOUT_CYCLES(50),
        .BUS_TIMEOUT_CYCLES(50), .MAX_RETRIES(2)
    ) codec_config (
        .clk(clk), .reset(reset), .pll_locked(1'b1),
        .retry_request(1'b0), .i2c_scl_in(cfg_scl),
        .i2c_sda_in(cfg_sda), .i2c_scl_drive_low(cfg_scl_low),
        .i2c_sda_drive_low(cfg_sda_low), .codec_init_busy(cfg_busy),
        .codec_init_done(cfg_done), .codec_init_error(cfg_error),
        .ack_count(cfg_acks), .nack_count(cfg_nacks),
        .timeout_count(cfg_timeouts), .retry_count(cfg_retries),
        .last_fault_code(cfg_fault), .register_index_debug(cfg_index)
    );

    logic nack_scl_low;
    logic nack_sda_low;
    wire nack_scl = nack_scl_low ? 1'b0 : 1'b1;
    wire nack_sda = nack_sda_low ? 1'b0 : 1'b1;
    logic nack_done;
    logic nack_error;
    logic [31:0] nack_count;
    logic [31:0] nack_retries;
    logic [7:0] nack_fault;

    wm8731_i2c_init #(
        .CLOCK_HZ(100), .I2C_HZ(10), .LOCK_TIMEOUT_CYCLES(50),
        .BUS_TIMEOUT_CYCLES(50), .MAX_RETRIES(2)
    ) codec_nack (
        .clk(clk), .reset(reset), .pll_locked(1'b1),
        .retry_request(1'b0), .i2c_scl_in(nack_scl),
        .i2c_sda_in(nack_sda), .i2c_scl_drive_low(nack_scl_low),
        .i2c_sda_drive_low(nack_sda_low), .codec_init_busy(),
        .codec_init_done(nack_done), .codec_init_error(nack_error),
        .ack_count(), .nack_count(nack_count), .timeout_count(),
        .retry_count(nack_retries), .last_fault_code(nack_fault),
        .register_index_debug()
    );

    logic timeout_scl_low;
    logic timeout_sda_low;
    logic timeout_error;
    logic [31:0] timeout_count;
    logic [7:0] timeout_fault;
    wm8731_i2c_init #(
        .CLOCK_HZ(100), .I2C_HZ(10), .LOCK_TIMEOUT_CYCLES(20),
        .BUS_TIMEOUT_CYCLES(20), .MAX_RETRIES(0)
    ) codec_timeout (
        .clk(clk), .reset(reset), .pll_locked(1'b1),
        .retry_request(1'b0), .i2c_scl_in(1'b0), .i2c_sda_in(1'b1),
        .i2c_scl_drive_low(timeout_scl_low),
        .i2c_sda_drive_low(timeout_sda_low), .codec_init_busy(),
        .codec_init_done(), .codec_init_error(timeout_error),
        .ack_count(), .nack_count(), .timeout_count(timeout_count),
        .retry_count(), .last_fault_code(timeout_fault),
        .register_index_debug()
    );

    logic pll_error;
    logic [7:0] pll_fault;
    wm8731_i2c_init #(
        .CLOCK_HZ(100), .I2C_HZ(10), .LOCK_TIMEOUT_CYCLES(20),
        .BUS_TIMEOUT_CYCLES(20), .MAX_RETRIES(0)
    ) codec_no_pll (
        .clk(clk), .reset(reset), .pll_locked(1'b0),
        .retry_request(1'b0), .i2c_scl_in(1'b1), .i2c_sda_in(1'b1),
        .i2c_scl_drive_low(), .i2c_sda_drive_low(), .codec_init_busy(),
        .codec_init_done(), .codec_init_error(pll_error), .ack_count(),
        .nack_count(), .timeout_count(), .retry_count(),
        .last_fault_code(pll_fault), .register_index_debug()
    );

    logic stuck_error;
    logic [31:0] stuck_timeout_count;
    logic [7:0] stuck_fault;
    wm8731_i2c_init #(
        .CLOCK_HZ(100), .I2C_HZ(10), .LOCK_TIMEOUT_CYCLES(20),
        .BUS_TIMEOUT_CYCLES(20), .MAX_RETRIES(0)
    ) codec_stuck_bus (
        .clk(clk), .reset(reset), .pll_locked(1'b1),
        .retry_request(1'b0), .i2c_scl_in(1'b1), .i2c_sda_in(1'b0),
        .i2c_scl_drive_low(), .i2c_sda_drive_low(), .codec_init_busy(),
        .codec_init_done(), .codec_init_error(stuck_error), .ack_count(),
        .nack_count(), .timeout_count(stuck_timeout_count), .retry_count(),
        .last_fault_code(stuck_fault), .register_index_debug()
    );

    integer monitor_clock;
    integer monitor_transactions;
    logic monitor_active;
    logic [23:0] monitor_word;

    function automatic logic [15:0] expected_register_word(input integer index);
        case (index)
            0: expected_register_word = {7'd15, 9'h000};
            1: expected_register_word = {7'd9,  9'h000};
            2: expected_register_word = {7'd5,  9'h008};
            3: expected_register_word = {7'd6,  9'h007};
            4: expected_register_word = {7'd2,  9'h1f0};
            5: expected_register_word = {7'd4,  9'h012};
            6: expected_register_word = {7'd7,  9'h002};
            7: expected_register_word = {7'd8,  9'h001};
            8: expected_register_word = {7'd9,  9'h001};
            9: expected_register_word = {7'd5,  9'h000};
            default: expected_register_word = '0;
        endcase
    endfunction

    always @(negedge cfg_sda) begin
        if (cfg_scl && !monitor_active) begin
            monitor_active = 1'b1;
            monitor_clock = 0;
            monitor_word = '0;
        end
    end

    always @(negedge cfg_scl) begin
        if (monitor_active)
            cfg_slave_ack = (monitor_clock == 8) ||
                            (monitor_clock == 17) ||
                            (monitor_clock == 26);
    end

    always @(posedge cfg_scl) begin
        if (monitor_active) begin
            if ((monitor_clock != 8) && (monitor_clock != 17) &&
                (monitor_clock != 26))
                monitor_word = {monitor_word[22:0], cfg_sda};
            if (monitor_clock == 26) begin
                if (monitor_word !==
                    {8'h34, expected_register_word(monitor_transactions)})
                    $fatal(1, "WM8731 transaction %0d mismatch: %h",
                           monitor_transactions, monitor_word);
                monitor_transactions = monitor_transactions + 1;
            end
            monitor_clock = monitor_clock + 1;
        end
    end

    always @(posedge cfg_sda) begin
        if (cfg_scl && monitor_active) begin
            monitor_active = 1'b0;
            cfg_slave_ack = 1'b0;
        end
    end

    task automatic pulse_conditioner(input logic signed [31:0] value);
        begin
            @(negedge clk);
            conditioner_input = value;
            conditioner_valid = 1'b1;
            @(negedge clk);
            conditioner_valid = 1'b0;
            wait (pcm_valid);
            if (!pcm_valid)
                $fatal(1, "conditioner did not assert pcm_valid");
        end
    endtask

    task automatic fifo_write(input logic [15:0] value);
        begin
            @(negedge fifo_write_clk);
            fifo_write_data = value;
            fifo_write_enable = 1'b1;
            @(negedge fifo_write_clk);
            fifo_write_enable = 1'b0;
        end
    endtask

    task automatic fifo_read_and_check(input logic [15:0] expected);
        begin
            wait (!fifo_empty);
            @(negedge fifo_read_clk);
            if (fifo_read_data !== expected)
                $fatal(1, "FIFO expected %h got %h", expected, fifo_read_data);
            fifo_read_enable = 1'b1;
            @(negedge fifo_read_clk);
            fifo_read_enable = 1'b0;
        end
    endtask

    integer tick_index;
    integer bit_index;
    integer audio_master_cycles;
    integer previous_frame_cycle;
    integer observed_frames;
    logic [15:0] left_word;
    logic [15:0] right_word;
    initial begin
        input_tick = 1'b0;
        mixed_audio = 20'h34567;
        resampler_reset = 1'b1;
        resampler_count = 0;
        expected_resampler_value = 32'sh00034567;
        conditioner_reset = 1'b1;
        conditioner_valid = 1'b0;
        conditioner_input = '0;
        test_tone_enable = 1'b0;
        fifo_write_reset = 1'b1;
        fifo_read_reset = 1'b1;
        fifo_write_enable = 1'b0;
        fifo_write_data = '0;
        fifo_read_enable = 1'b0;
        i2s_reset = 1'b1;
        i2s_stream_enable = 1'b0;
        i2s_fifo_empty = 1'b0;
        i2s_fifo_data = 16'shA55A;
        cfg_slave_ack = 1'b0;
        monitor_clock = 0;
        monitor_transactions = 0;
        monitor_active = 1'b0;
        monitor_word = '0;
        audio_master_cycles = 0;
        previous_frame_cycle = 0;
        observed_frames = 0;

        repeat (8) @(posedge clk);
        reset = 1'b0;
        resampler_reset = 1'b0;
        conditioner_reset = 1'b0;
        fifo_write_reset = 1'b0;
        fifo_read_reset = 1'b0;
        i2s_reset = 1'b0;

        // PCM reset, gain, signed rounding, saturation, and diagnostic tone.
        pulse_conditioner(32'sd1000);
        if (pcm_sample !== 16'sd0)
            $fatal(1, "conditioner startup must be zero");
        pulse_conditioner(32'sd1049576);
        if (pcm_sample !== 16'sd24576)
            $fatal(1, "positive gain mismatch: %0d", pcm_sample);
        conditioner_reset = 1'b1;
        repeat (2) @(posedge clk);
        conditioner_reset = 1'b0;
        pulse_conditioner(32'sd0);
        pulse_conditioner(32'sd16777216);
        if ((pcm_sample !== 16'sh7fff) || !saturation_event)
            $fatal(1, "positive saturation mismatch");
        test_tone_enable = 1'b1;
        pulse_conditioner(32'sd0);
        if (pcm_sample !== 16'sd8192)
            $fatal(1, "test tone mismatch");
        test_tone_enable = 1'b0;

        // Async FIFO ordering and underflow/overflow fault pulses.
        fifo_write(16'h1001);
        fifo_write(16'h1002);
        fifo_write(16'h1003);
        fifo_read_and_check(16'h1001);
        fifo_read_and_check(16'h1002);
        fifo_read_and_check(16'h1003);
        @(negedge fifo_read_clk);
        fifo_read_enable = 1'b1;
        @(negedge fifo_read_clk);
        fifo_read_enable = 1'b0;
        if (!fifo_underflow)
            $fatal(1, "FIFO underflow was not reported");
        fifo_write_reset = 1'b1;
        fifo_read_reset = 1'b1;
        repeat (3) @(posedge fifo_write_clk);
        fifo_write_reset = 1'b0;
        fifo_read_reset = 1'b0;
        for (tick_index = 0; tick_index < 8; tick_index = tick_index + 1)
            fifo_write(16'(tick_index));
        fifo_write(16'hffff);
        if (!fifo_overflow)
            $fatal(1, "FIFO overflow was not reported");

        // I2S: one-bit delay, 16-bit MSB-first word, zero padding, duplicate R.
        i2s_stream_enable = 1'b1;
        @(posedge i2s_transmitted);
        left_word = '0;
        right_word = '0;
        for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin
            @(posedge aud_bclk);
            if (bit_index < 32 && aud_lrck !== 1'b0)
                $fatal(1, "left LRCK phase mismatch at %0d", bit_index);
            if (bit_index >= 32 && aud_lrck !== 1'b1)
                $fatal(1, "right LRCK phase mismatch at %0d", bit_index);
            if ((bit_index >= 1) && (bit_index <= 16))
                left_word = {left_word[14:0], aud_data};
            if ((bit_index >= 33) && (bit_index <= 48))
                right_word = {right_word[14:0], aud_data};
            if ((bit_index == 0 || bit_index == 32) && aud_data)
                $fatal(1, "I2S one-bit delay was not zero");
        end
        if ((left_word !== 16'hA55A) || (right_word !== 16'hA55A))
            $fatal(1, "I2S stereo mismatch L=%h R=%h", left_word, right_word);
        i2s_fifo_empty = 1'b1;
        @(posedge i2s_underrun);
        wait (observed_frames >= 2);
        if (observed_frames < 2)
            $fatal(1, "I2S exact-rate frame cadence was not observed");
        i2s_reset = 1'b1;
        repeat (3) @(posedge audio_clk);
        if (!i2s_muted || aud_data)
            $fatal(1, "serializer reset did not mute output");

        // Causal impulse alignment: tick 9 is lag 28 at the first output.
        // Its Q18-scaled impulse must therefore reproduce coefficient 28 (-1).
        expected_resampler_value = -32'sd1;
        for (tick_index = 0; tick_index < 38; tick_index = tick_index + 1) begin
            if (tick_index == 9)
                mixed_audio = 20'h40000;
            else
                mixed_audio = '0;
            repeat (27) @(posedge clk);
            input_tick = 1'b1;
            @(posedge clk);
            input_tick = 1'b0;
        end
        wait (resampler_count == 1);
        while (resampler_busy) @(posedge clk);

        // Reset just the converter and run a complete rational period with a
        // constant input to check unity DC gain and the no-drift deadline.
        resampler_reset = 1'b1;
        repeat (2) @(posedge clk);
        resampler_count = 0;
        mixed_audio = 20'h34567;
        expected_resampler_value = 32'sh00034567;
        resampler_reset = 1'b0;
        for (tick_index = 0; tick_index < 13125; tick_index = tick_index + 1) begin
            repeat (27) @(posedge clk);
            input_tick = 1'b1;
            @(posedge clk);
            input_tick = 1'b0;
        end
        while (resampler_busy) @(posedge clk);
        repeat (5) @(posedge clk);
        if (resampler_count != 352)
            $fatal(1, "48 kHz cadence expected 352 got %0d", resampler_count);
        if (schedule_overrun)
            $fatal(1, "FIR engine missed a rational sample deadline");
        if (phase_debug != 0)
            $fatal(1, "rational accumulator did not return to zero");

        wait (cfg_done || cfg_error);
        if (cfg_error || !cfg_done || cfg_acks != 30 || cfg_nacks != 0 ||
            cfg_retries != 0 || cfg_timeouts != 0 ||
            monitor_transactions != 10)
            $fatal(1, "codec ACK sequence failed");
        wait (nack_error);
        if (nack_done || nack_count != 3 || nack_retries != 2 ||
            nack_fault != 8'h02)
            $fatal(1, "codec NACK/retry status mismatch");
        wait (timeout_error);
        if (timeout_count == 0 || timeout_fault != 8'h03)
            $fatal(1, "codec timeout status mismatch");
        wait (pll_error);
        if (pll_fault != 8'h01)
            $fatal(1, "PLL timeout status mismatch");
        wait (stuck_error);
        if (stuck_timeout_count == 0 || stuck_fault != 8'h04)
            $fatal(1, "malformed/stuck control bus status mismatch");

        $display("NES audio Phase 5K directed/long-run test passed");
        $finish;
    end

    always @(posedge clk) begin
        if (resampler_valid) begin
            resampler_count <= resampler_count + 1;
            if (filtered_sample !== expected_resampler_value)
                $fatal(1, "FIR response expected %h got %h",
                       expected_resampler_value, filtered_sample);
        end
    end

    always @(posedge audio_clk) begin
        audio_master_cycles <= audio_master_cycles + 1;
        if (i2s_frame) begin
            if ((observed_frames != 0) &&
                ((audio_master_cycles - previous_frame_cycle) != 250))
                $fatal(1, "I2S frame period was not 250 MCLK cycles");
            previous_frame_cycle <= audio_master_cycles;
            observed_frames <= observed_frames + 1;
        end
    end

    initial begin
        #20ms;
        $fatal(1, "Phase 5K testbench timeout");
    end
endmodule
