`timescale 1ns/1ps

// Phase 6C deterministic ADV7513 qualification controller.  The control
// clock remains alive when the video PLL stops, allowing missing-clock faults
// and fail-closed recovery to remain observable.
module hdmi_tx_controller #(
    parameter integer HPD_STABLE_CYCLES = 250_000,
    // ADV7513 requires 200 ms after all supplies are valid before the first
    // I2C transaction.  RESET release is the board-level power-good boundary.
    parameter integer STARTUP_DELAY_CYCLES = 10_000_000,
    parameter integer CLOCK_WAIT_TIMEOUT = 50_000_000,
    parameter integer HPD_WAIT_TIMEOUT = 250_000_000,
    parameter integer RECOVERY_DELAY_CYCLES = 5_000_000,
    parameter integer MAX_RECOVERIES = 3,
    parameter integer I2C_CLOCKS_PER_HALF_PERIOD = 250,
    parameter integer I2C_TIMEOUT_CYCLES = 50_000,
    parameter integer EDID_READY_POLLS = 256,
    parameter integer EDID_POLL_DELAY_CYCLES = 50_000,
    parameter integer AUDIO_CLOCK_WAIT_TIMEOUT = 50_000_000,
    parameter integer AUDIO_PRIME_TIMEOUT = 5_000_000,
    parameter integer AUDIO_RECOVERY_DELAY_CYCLES = 5_000_000,
    parameter integer AUDIO_MAX_RECOVERIES = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        pixel_clock_locked_async,
    input  logic        frame_toggle_async,
    input  logic        hpd_async,
    input  logic        scl_in,
    input  logic        sda_in,
    input  logic        audio_clock_locked_async,
    input  logic        audio_configuration_allowed,
    input  logic        audio_transport_primed,
    input  logic        audio_user_mute,
    input  logic        audio_fault_clear,
    input  logic [31:0] audio_fifo_underruns,
    input  logic [31:0] audio_fifo_overruns,
    output logic        scl_drive_low,
    output logic        sda_drive_low,
    output logic        video_enable,
    output logic        safe_disable,
    // Active-high only for the documented 0x72 (7-bit 0x39) PD/AD strap.
    // It stays low during the initial address-latch interval.
    output logic        transmitter_power_down,
    output logic        transmitter_present,
    output logic        transmitter_configured,
    output logic        transmitter_fault,
    output logic [1:0]  hpd_state,
    output logic        edid_available,
    output logic        edid_valid,
    output logic        mode_supported,
    output logic        video_clock_locked,
    output logic [31:0] video_frames_sent,
    output logic [31:0] i2c_nack_count,
    output logic [31:0] i2c_timeout_count,
    output logic [31:0] recovery_count,
    output logic [7:0]  last_error_code,
    output logic [3:0]  startup_state,
    output logic        hdmi_audio_configured,
    output logic        hdmi_audio_enabled,
    output logic        hdmi_audio_muted,
    output logic        hdmi_audio_clock_locked,
    output logic        hdmi_audio_accept_samples,
    output logic        hdmi_audio_stream_enable,
    output logic        hdmi_audio_fifo_flush,
    output logic        hdmi_audio_fault,
    output logic [3:0]  hdmi_audio_state,
    output logic [31:0] hdmi_audio_reconnect_count,
    output logic [7:0]  hdmi_audio_last_error
);
    import hdmi_tx_pkg::*;
    import hdmi_audio_pkg::*;

    hdmi_startup_state_t state;
    logic [31:0] state_timer;
    logic [31:0] startup_timer;
    logic [31:0] recovery_attempts;
    logic terminal_recovery_failure;
    logic address_latched;
    logic video_enable_request;
    logic hpd_stable, hpd_connected, hpd_disconnected;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] pixel_lock_sync, frame_toggle_sync;
    logic previous_frame_toggle;

    logic config_start, verify_start, config_done, config_failed;
    logic [7:0] config_failure_code;
    logic config_transmitter_seen;
    logic config_command_valid, config_command_ready, config_command_read;
    logic [6:0] config_command_device;
    logic [7:0] config_command_register, config_command_write_data;

    logic edid_start, reader_done, reader_failed;
    logic [7:0] reader_failure_code;
    logic reader_byte_valid;
    logic [7:0] reader_byte_index, reader_byte_data;
    logic reader_command_valid, reader_command_ready, reader_command_read;
    logic [6:0] reader_command_device;
    logic [7:0] reader_command_register, reader_command_write_data;
    logic validator_done;
    logic validator_edid_valid, validator_mode_supported;

    logic master_command_valid, master_command_ready, master_command_read;
    logic [6:0] master_command_device;
    logic [7:0] master_command_register, master_command_write_data;
    logic master_response_valid;
    logic master_response_nack, master_response_timeout;
    logic [7:0] master_response_read_data;
    logic bus_recovery_pulse;
    logic config_owner, reader_owner, audio_owner;
    logic engine_reset;
    logic audio_command_valid, audio_command_ready, audio_command_read;
    logic [6:0] audio_command_device;
    logic [7:0] audio_command_register, audio_command_write_data;
    logic video_ready_for_audio;
    logic sink_supports_audio;

    assign startup_state = state;
    assign video_clock_locked = pixel_lock_sync[1];
    assign transmitter_present = config_transmitter_seen;
    assign transmitter_fault = state == HDMI_STATE_FAULT;
    assign video_enable = video_enable_request && hpd_stable &&
                          video_clock_locked;
    assign safe_disable = !video_enable;
    assign transmitter_power_down = address_latched &&
        (state == HDMI_STATE_WAIT_HPD || state == HDMI_STATE_FAULT ||
         state == HDMI_STATE_RECOVERY);
    assign config_owner = state == HDMI_STATE_CONFIGURE ||
                          state == HDMI_STATE_VERIFY_CONFIG;
    assign reader_owner = state == HDMI_STATE_CHECK_DISPLAY_CAPABILITY;
    assign audio_owner = state == HDMI_STATE_RUNNING;
    assign video_ready_for_audio = state == HDMI_STATE_RUNNING &&
        video_enable && transmitter_configured && edid_valid && mode_supported &&
        sink_supports_audio && audio_configuration_allowed;
    // An HPD loss can revoke bus ownership in the middle of any transaction.
    // Clear every subordinate FSM while output is safely disabled so no stale
    // response or half-finished command can survive into the next attempt.
    assign engine_reset = reset || state == HDMI_STATE_FAULT ||
                          state == HDMI_STATE_RECOVERY;

    // Once a disconnect is qualified, do not begin another transaction.  An
    // already-active transfer is allowed to reach its documented STOP before
    // ownership is revoked and the subordinate FSMs are cleared.
    assign master_command_valid = hpd_stable &&
                                  (config_owner ? config_command_valid :
                                   reader_owner ? reader_command_valid :
                                   audio_owner ? audio_command_valid : 1'b0);
    assign master_command_read = config_owner ? config_command_read :
                                 reader_owner ? reader_command_read :
                                 audio_command_read;
    assign master_command_device = config_owner ? config_command_device :
                                   reader_owner ? reader_command_device :
                                   audio_command_device;
    assign master_command_register = config_owner ? config_command_register :
                                     reader_owner ? reader_command_register :
                                     audio_command_register;
    assign master_command_write_data = config_owner ?
        config_command_write_data : reader_owner ?
        reader_command_write_data : audio_command_write_data;
    assign config_command_ready = config_owner && hpd_stable &&
                                  master_command_ready;
    assign reader_command_ready = reader_owner && hpd_stable &&
                                  master_command_ready;
    assign audio_command_ready = audio_owner && hpd_stable &&
                                 master_command_ready;

    hdmi_hpd_filter #(
        .STABLE_CYCLES(HPD_STABLE_CYCLES)
    ) hpd_filter (
        .clk(clk),
        .reset(reset),
        .hpd_async(hpd_async),
        .hpd_stable(hpd_stable),
        .hpd_state(hpd_state),
        .connected_pulse(hpd_connected),
        .disconnected_pulse(hpd_disconnected)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    i2c_register_master #(
        .CLOCKS_PER_HALF_PERIOD(I2C_CLOCKS_PER_HALF_PERIOD),
        .STRETCH_TIMEOUT_CYCLES(I2C_TIMEOUT_CYCLES)
    ) i2c_master (
        .clk(clk),
        .reset(reset),
        .command_valid(master_command_valid),
        .command_ready(master_command_ready),
        .command_read(master_command_read),
        .command_device_address(master_command_device),
        .command_register_address(master_command_register),
        .command_write_data(master_command_write_data),
        .response_valid(master_response_valid),
        .response_ack(),
        .response_nack(master_response_nack),
        .response_timeout(master_response_timeout),
        .response_read_data(master_response_read_data),
        .bus_recovery_pulse(bus_recovery_pulse),
        .scl_in(scl_in),
        .sda_in(sda_in),
        .scl_drive_low(scl_drive_low),
        .sda_drive_low(sda_drive_low)
    );

    adv7513_config_engine config_engine (
        .clk(clk),
        .reset(engine_reset),
        .start_config(config_start),
        .start_verify(verify_start),
        .busy(),
        .done(config_done),
        .failed(config_failed),
        .failure_code(config_failure_code),
        .transmitter_seen(config_transmitter_seen),
        .command_valid(config_command_valid),
        .command_ready(config_command_ready),
        .command_read(config_command_read),
        .command_device_address(config_command_device),
        .command_register_address(config_command_register),
        .command_write_data(config_command_write_data),
        .response_valid(master_response_valid && config_owner),
        .response_nack(master_response_nack),
        .response_timeout(master_response_timeout),
        .response_read_data(master_response_read_data)
    );

    adv7513_edid_reader #(
        .READY_POLLS(EDID_READY_POLLS),
        .POLL_DELAY_CYCLES(EDID_POLL_DELAY_CYCLES)
    ) edid_reader (
        .clk(clk),
        .reset(engine_reset),
        .start(edid_start),
        .busy(),
        .done(reader_done),
        .failed(reader_failed),
        .failure_code(reader_failure_code),
        .edid_available(edid_available),
        .byte_valid(reader_byte_valid),
        .byte_index(reader_byte_index),
        .byte_data(reader_byte_data),
        .command_valid(reader_command_valid),
        .command_ready(reader_command_ready),
        .command_read(reader_command_read),
        .command_device_address(reader_command_device),
        .command_register_address(reader_command_register),
        .command_write_data(reader_command_write_data),
        .response_valid(master_response_valid && reader_owner),
        .response_nack(master_response_nack),
        .response_timeout(master_response_timeout),
        .response_read_data(master_response_read_data)
    );

    edid_720p_validator edid_validator (
        .clk(clk),
        .reset(engine_reset),
        .start(edid_start),
        .byte_valid(reader_byte_valid),
        .byte_index(reader_byte_index),
        .byte_data(reader_byte_data),
        .finish(reader_done),
        .busy(),
        .done(validator_done),
        .edid_valid(validator_edid_valid),
        .mode_supported(validator_mode_supported)
    );

    hdmi_audio_controller #(
        .CLOCK_WAIT_TIMEOUT(AUDIO_CLOCK_WAIT_TIMEOUT),
        .PRIME_TIMEOUT(AUDIO_PRIME_TIMEOUT),
        .RECOVERY_DELAY_CYCLES(AUDIO_RECOVERY_DELAY_CYCLES),
        .MAX_RECOVERIES(AUDIO_MAX_RECOVERIES)
    ) audio_controller (
        .clk(clk),
        .reset(reset),
        .video_ready(video_ready_for_audio),
        .hpd_stable(hpd_stable),
        .audio_clock_locked_async(audio_clock_locked_async),
        .transport_primed(audio_transport_primed),
        .user_mute(audio_user_mute),
        .clear_fault(audio_fault_clear),
        .fifo_underruns(audio_fifo_underruns),
        .fifo_overruns(audio_fifo_overruns),
        .configured(hdmi_audio_configured),
        .enabled(hdmi_audio_enabled),
        .muted(hdmi_audio_muted),
        .clock_locked(hdmi_audio_clock_locked),
        .accept_samples(hdmi_audio_accept_samples),
        .stream_enable(hdmi_audio_stream_enable),
        .fifo_flush(hdmi_audio_fifo_flush),
        .fault(hdmi_audio_fault),
        .state_debug(hdmi_audio_state),
        .reconnect_count(hdmi_audio_reconnect_count),
        .last_error(hdmi_audio_last_error),
        .command_valid(audio_command_valid),
        .command_ready(audio_command_ready),
        .command_read(audio_command_read),
        .command_device_address(audio_command_device),
        .command_register_address(audio_command_register),
        .command_write_data(audio_command_write_data),
        .response_valid(master_response_valid && audio_owner),
        .response_nack(master_response_nack),
        .response_timeout(master_response_timeout),
        .response_read_data(master_response_read_data)
    );

    hdmi_audio_edid audio_capability (
        .clk(clk), .reset(engine_reset), .start(edid_start),
        .byte_valid(reader_byte_valid), .byte_index(reader_byte_index),
        .byte_data(reader_byte_data), .supports_pcm(sink_supports_audio)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= HDMI_STATE_RESET;
            state_timer <= '0;
            startup_timer <= '0;
            recovery_attempts <= '0;
            terminal_recovery_failure <= 1'b0;
            address_latched <= 1'b0;
            pixel_lock_sync <= 2'b00;
            frame_toggle_sync <= 2'b00;
            previous_frame_toggle <= 1'b0;
            config_start <= 1'b0;
            verify_start <= 1'b0;
            edid_start <= 1'b0;
            video_enable_request <= 1'b0;
            transmitter_configured <= 1'b0;
            edid_valid <= 1'b0;
            mode_supported <= 1'b0;
            video_frames_sent <= '0;
            i2c_nack_count <= '0;
            i2c_timeout_count <= '0;
            recovery_count <= '0;
            last_error_code <= HDMI_ERROR_NONE;
        end else begin
            pixel_lock_sync <= {pixel_lock_sync[0],
                                pixel_clock_locked_async};
            frame_toggle_sync <= {frame_toggle_sync[0], frame_toggle_async};
            previous_frame_toggle <= frame_toggle_sync[1];
            config_start <= 1'b0;
            verify_start <= 1'b0;
            edid_start <= 1'b0;

            if (frame_toggle_sync[1] != previous_frame_toggle)
                video_frames_sent <= video_frames_sent + 1'b1;
            if (master_response_valid && master_response_nack)
                i2c_nack_count <= i2c_nack_count + 1'b1;
            if (master_response_valid && master_response_timeout)
                i2c_timeout_count <= i2c_timeout_count + 1'b1;
            if (bus_recovery_pulse)
                recovery_count <= recovery_count + 1'b1;

            if (hpd_disconnected) begin
                video_enable_request <= 1'b0;
                transmitter_configured <= 1'b0;
                edid_valid <= 1'b0;
                mode_supported <= 1'b0;
            end

            unique case (state)
                HDMI_STATE_RESET: begin
                    video_enable_request <= 1'b0;
                    state_timer <= '0;
                    startup_timer <= '0;
                    state <= HDMI_STATE_WAIT_CLOCK;
                end
                HDMI_STATE_WAIT_CLOCK: begin
                    video_enable_request <= 1'b0;
                    if (video_clock_locked) begin
                        state_timer <= '0;
                        if (STARTUP_DELAY_CYCLES <= 1 ||
                            startup_timer == STARTUP_DELAY_CYCLES - 1) begin
                            startup_timer <= '0;
                            address_latched <= 1'b1;
                            state <= HDMI_STATE_WAIT_HPD;
                        end else begin
                            startup_timer <= startup_timer + 1'b1;
                        end
                    end else if (CLOCK_WAIT_TIMEOUT <= 1 ||
                                 state_timer == CLOCK_WAIT_TIMEOUT - 1) begin
                        last_error_code <= HDMI_PIXEL_CLOCK_UNLOCKED;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end else begin
                        startup_timer <= '0;
                        state_timer <= state_timer + 1'b1;
                    end
                end
                HDMI_STATE_WAIT_HPD: begin
                    if (!video_clock_locked) begin
                        last_error_code <= HDMI_PIXEL_CLOCK_UNLOCKED;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end else if (hpd_stable) begin
                        state_timer <= '0;
                        transmitter_configured <= 1'b0;
                        edid_valid <= 1'b0;
                        mode_supported <= 1'b0;
                        config_start <= 1'b1;
                        state <= HDMI_STATE_CONFIGURE;
                    end else if (HPD_WAIT_TIMEOUT <= 1 ||
                                 state_timer == HPD_WAIT_TIMEOUT - 1) begin
                        last_error_code <= HDMI_HPD_TIMEOUT;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                HDMI_STATE_CONFIGURE: begin
                    if (!hpd_stable) begin
                        if (master_command_ready) begin
                            state_timer <= '0;
                            recovery_attempts <= recovery_attempts + 1'b1;
                            recovery_count <= recovery_count + 1'b1;
                            state <= HDMI_STATE_RECOVERY;
                        end
                    end else if (config_failed) begin
                        last_error_code <=
                            (!config_transmitter_seen &&
                             config_failure_code == HDMI_TX_I2C_NACK) ?
                            HDMI_TX_NOT_DETECTED : config_failure_code;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end else if (config_done) begin
                        verify_start <= 1'b1;
                        state <= HDMI_STATE_VERIFY_CONFIG;
                    end
                end
                HDMI_STATE_VERIFY_CONFIG: begin
                    if (!hpd_stable) begin
                        if (master_command_ready) begin
                            state_timer <= '0;
                            recovery_attempts <= recovery_attempts + 1'b1;
                            recovery_count <= recovery_count + 1'b1;
                            state <= HDMI_STATE_RECOVERY;
                        end
                    end else if (config_failed) begin
                        last_error_code <= config_failure_code;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end else if (config_done) begin
                        transmitter_configured <= 1'b1;
                        edid_start <= 1'b1;
                        state <= HDMI_STATE_CHECK_DISPLAY_CAPABILITY;
                    end
                end
                HDMI_STATE_CHECK_DISPLAY_CAPABILITY: begin
                    if (!hpd_stable) begin
                        if (master_command_ready) begin
                            state_timer <= '0;
                            recovery_attempts <= recovery_attempts + 1'b1;
                            recovery_count <= recovery_count + 1'b1;
                            state <= HDMI_STATE_RECOVERY;
                        end
                    end else if (reader_failed) begin
                        last_error_code <= reader_failure_code;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end else if (validator_done) begin
                        edid_valid <= validator_edid_valid;
                        mode_supported <= validator_mode_supported;
                        if (!validator_edid_valid) begin
                            last_error_code <= HDMI_EDID_INVALID;
                            state_timer <= '0;
                            state <= HDMI_STATE_FAULT;
                        end else if (!validator_mode_supported) begin
                            last_error_code <= HDMI_MODE_UNSUPPORTED;
                            state_timer <= '0;
                            state <= HDMI_STATE_FAULT;
                        end else begin
                            state <= HDMI_STATE_ENABLE_VIDEO;
                        end
                    end
                end
                HDMI_STATE_ENABLE_VIDEO: begin
                    if (!hpd_stable || !video_clock_locked) begin
                        last_error_code <= !video_clock_locked ?
                            HDMI_PIXEL_CLOCK_UNLOCKED : last_error_code;
                        state_timer <= '0;
                        recovery_attempts <= recovery_attempts + 1'b1;
                        recovery_count <= recovery_count + 1'b1;
                        state <= HDMI_STATE_RECOVERY;
                    end else begin
                        video_enable_request <= 1'b1;
                        terminal_recovery_failure <= 1'b0;
                        recovery_attempts <= '0;
                        state <= HDMI_STATE_RUNNING;
                    end
                end
                HDMI_STATE_RUNNING: begin
                    if (!hpd_stable) begin
                        video_enable_request <= 1'b0;
                        state_timer <= '0;
                        recovery_attempts <= recovery_attempts + 1'b1;
                        recovery_count <= recovery_count + 1'b1;
                        state <= HDMI_STATE_RECOVERY;
                    end else if (!video_clock_locked) begin
                        video_enable_request <= 1'b0;
                        last_error_code <= HDMI_PIXEL_CLOCK_UNLOCKED;
                        state_timer <= '0;
                        state <= HDMI_STATE_FAULT;
                    end
                end
                HDMI_STATE_FAULT: begin
                    video_enable_request <= 1'b0;
                    transmitter_configured <= 1'b0;
                    if (terminal_recovery_failure && hpd_connected) begin
                        terminal_recovery_failure <= 1'b0;
                        recovery_attempts <= '0;
                        state_timer <= '0;
                        state <= HDMI_STATE_WAIT_CLOCK;
                    end else if (!terminal_recovery_failure &&
                        (RECOVERY_DELAY_CYCLES <= 1 ||
                         state_timer == RECOVERY_DELAY_CYCLES - 1 ||
                         !hpd_stable)) begin
                        state_timer <= '0;
                        if (recovery_attempts >= MAX_RECOVERIES) begin
                            last_error_code <= HDMI_RECOVERY_FAILED;
                            terminal_recovery_failure <= 1'b1;
                        end else begin
                            recovery_attempts <= recovery_attempts + 1'b1;
                            recovery_count <= recovery_count + 1'b1;
                            state <= HDMI_STATE_RECOVERY;
                        end
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                HDMI_STATE_RECOVERY: begin
                    video_enable_request <= 1'b0;
                    transmitter_configured <= 1'b0;
                    edid_valid <= 1'b0;
                    mode_supported <= 1'b0;
                    if ((RECOVERY_DELAY_CYCLES <= 1 ||
                        state_timer >= RECOVERY_DELAY_CYCLES - 1) &&
                        master_command_ready) begin
                        state_timer <= '0;
                        state <= HDMI_STATE_WAIT_CLOCK;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                default: state <= HDMI_STATE_RESET;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset && video_enable) begin
            assert (state == HDMI_STATE_RUNNING);
            assert (transmitter_configured && edid_valid && mode_supported);
            assert (hpd_stable && video_clock_locked);
        end
    end
`endif
endmodule
