`timescale 1ns/1ps

// Phase 6D audio lifecycle controller.  Video ownership remains with Phase 6C;
// this client configures audio only after the video/EDID path is running.
module hdmi_audio_controller #(
    parameter integer CLOCK_WAIT_TIMEOUT = 50_000_000,
    parameter integer PRIME_TIMEOUT = 5_000_000,
    parameter integer RECOVERY_DELAY_CYCLES = 5_000_000,
    parameter integer MAX_RECOVERIES = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        video_ready,
    input  logic        hpd_stable,
    input  logic        audio_clock_locked_async,
    input  logic        transport_primed,
    input  logic        user_mute,
    input  logic        clear_fault,
    input  logic [31:0] fifo_underruns,
    input  logic [31:0] fifo_overruns,
    output logic        configured,
    output logic        enabled,
    output logic        muted,
    output logic        clock_locked,
    output logic        accept_samples,
    output logic        stream_enable,
    output logic        fifo_flush,
    output logic        fault,
    output logic [3:0]  state_debug,
    output logic [31:0] reconnect_count,
    output logic [7:0]  last_error,
    output logic        command_valid,
    input  logic        command_ready,
    output logic        command_read,
    output logic [6:0]  command_device_address,
    output logic [7:0]  command_register_address,
    output logic [7:0]  command_write_data,
    input  logic        response_valid,
    input  logic        response_nack,
    input  logic        response_timeout,
    input  logic [7:0]  response_read_data
);
    import hdmi_audio_pkg::*;

    hdmi_audio_state_t state;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] audio_lock_sync;
    logic [31:0] state_timer, recovery_attempts;
    logic [31:0] previous_underruns, previous_overruns;
    logic config_start, verify_start, config_done, config_failed;
    logic [7:0] config_failure_code;
    logic saw_link_loss;

    assign state_debug = state;
    assign enabled = (state == HDMI_AUDIO_STATE_RUNNING ||
                      state == HDMI_AUDIO_STATE_MUTED) &&
                     video_ready && hpd_stable && audio_lock_sync[1];
    assign muted = !enabled || state == HDMI_AUDIO_STATE_MUTED;
    assign accept_samples = state == HDMI_AUDIO_STATE_PRIME_AUDIO ||
                            state == HDMI_AUDIO_STATE_ENABLE_AUDIO || enabled;
    assign stream_enable = state == HDMI_AUDIO_STATE_ENABLE_AUDIO || enabled;
    assign fifo_flush = !accept_samples;
    assign fault = last_error != HDMI_AUDIO_ERROR_NONE;
    assign clock_locked = audio_lock_sync[1];

    /* verilator lint_off PINCONNECTEMPTY */
    adv7513_audio_config_engine config_engine (
        .clk(clk),
        .reset(reset || state == HDMI_AUDIO_STATE_RECOVERY ||
               state == HDMI_AUDIO_STATE_FAULT),
        .start_config(config_start),
        .start_verify(verify_start),
        .busy(),
        .done(config_done),
        .failed(config_failed),
        .failure_code(config_failure_code),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_read(command_read),
        .command_device_address(command_device_address),
        .command_register_address(command_register_address),
        .command_write_data(command_write_data),
        .response_valid(response_valid),
        .response_nack(response_nack),
        .response_timeout(response_timeout),
        .response_read_data(response_read_data)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= HDMI_AUDIO_STATE_RESET;
            audio_lock_sync <= '0;
            state_timer <= '0;
            recovery_attempts <= '0;
            previous_underruns <= '0;
            previous_overruns <= '0;
            config_start <= 1'b0;
            verify_start <= 1'b0;
            configured <= 1'b0;
            reconnect_count <= '0;
            last_error <= HDMI_AUDIO_ERROR_NONE;
            saw_link_loss <= 1'b0;
        end else begin
            audio_lock_sync <= {audio_lock_sync[0],
                                audio_clock_locked_async};
            config_start <= 1'b0;
            verify_start <= 1'b0;
            previous_underruns <= fifo_underruns;
            previous_overruns <= fifo_overruns;
            if (clear_fault)
                last_error <= HDMI_AUDIO_ERROR_NONE;

            unique case (state)
                HDMI_AUDIO_STATE_RESET: begin
                    configured <= 1'b0;
                    state_timer <= '0;
                    state <= HDMI_AUDIO_STATE_WAIT_VIDEO;
                end
                HDMI_AUDIO_STATE_WAIT_VIDEO: begin
                    configured <= 1'b0;
                    recovery_attempts <= '0;
                    state_timer <= '0;
                    if (video_ready && hpd_stable) begin
                        if (saw_link_loss) begin
                            reconnect_count <= reconnect_count + 1'b1;
                            saw_link_loss <= 1'b0;
                        end
                        state <= HDMI_AUDIO_STATE_WAIT_CLOCK;
                    end
                end
                HDMI_AUDIO_STATE_WAIT_CLOCK: begin
                    if (!video_ready || !hpd_stable) begin
                        saw_link_loss <= 1'b1;
                        last_error <= HDMI_AUDIO_LINK_LOST;
                        state <= HDMI_AUDIO_STATE_WAIT_VIDEO;
                    end else if (audio_lock_sync[1]) begin
                        state_timer <= '0;
                        config_start <= 1'b1;
                        state <= HDMI_AUDIO_STATE_CONFIGURE;
                    end else if (CLOCK_WAIT_TIMEOUT <= 1 ||
                                 state_timer == CLOCK_WAIT_TIMEOUT - 1) begin
                        last_error <= HDMI_AUDIO_CLOCK_UNLOCKED;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_FAULT;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                HDMI_AUDIO_STATE_CONFIGURE: begin
                    if (!video_ready || !hpd_stable) begin
                        saw_link_loss <= 1'b1;
                        last_error <= HDMI_AUDIO_LINK_LOST;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (config_failed) begin
                        last_error <= config_failure_code;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_FAULT;
                    end else if (config_done) begin
                        verify_start <= 1'b1;
                        state <= HDMI_AUDIO_STATE_VERIFY_CONFIG;
                    end
                end
                HDMI_AUDIO_STATE_VERIFY_CONFIG: begin
                    if (!video_ready || !hpd_stable) begin
                        saw_link_loss <= 1'b1;
                        last_error <= HDMI_AUDIO_LINK_LOST;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (config_failed) begin
                        last_error <= config_failure_code;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_FAULT;
                    end else if (config_done) begin
                        configured <= 1'b1;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_PRIME_AUDIO;
                    end
                end
                HDMI_AUDIO_STATE_PRIME_AUDIO: begin
                    if (!video_ready || !hpd_stable || !audio_lock_sync[1]) begin
                        last_error <= !audio_lock_sync[1] ?
                            HDMI_AUDIO_CLOCK_UNLOCKED : HDMI_AUDIO_LINK_LOST;
                        saw_link_loss <= !hpd_stable || !video_ready;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (transport_primed) begin
                        state_timer <= '0;
                        previous_underruns <= fifo_underruns;
                        previous_overruns <= fifo_overruns;
                        state <= HDMI_AUDIO_STATE_ENABLE_AUDIO;
                    end else if (PRIME_TIMEOUT <= 1 ||
                                 state_timer == PRIME_TIMEOUT - 1) begin
                        last_error <= HDMI_AUDIO_FIFO_UNDERRUN;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_FAULT;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                HDMI_AUDIO_STATE_ENABLE_AUDIO: begin
                    if (!video_ready || !hpd_stable || !audio_lock_sync[1]) begin
                        last_error <= !audio_lock_sync[1] ?
                            HDMI_AUDIO_CLOCK_UNLOCKED : HDMI_AUDIO_LINK_LOST;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else begin
                        recovery_attempts <= '0;
                        state <= user_mute ? HDMI_AUDIO_STATE_MUTED :
                                             HDMI_AUDIO_STATE_RUNNING;
                    end
                end
                HDMI_AUDIO_STATE_RUNNING,
                HDMI_AUDIO_STATE_MUTED: begin
                    if (!video_ready || !hpd_stable) begin
                        configured <= 1'b0;
                        last_error <= HDMI_AUDIO_LINK_LOST;
                        saw_link_loss <= 1'b1;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (!audio_lock_sync[1]) begin
                        configured <= 1'b0;
                        last_error <= HDMI_AUDIO_CLOCK_UNLOCKED;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (fifo_underruns != previous_underruns) begin
                        last_error <= HDMI_AUDIO_FIFO_UNDERRUN;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (fifo_overruns != previous_overruns) begin
                        last_error <= HDMI_AUDIO_FIFO_OVERRUN;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (user_mute) begin
                        state <= HDMI_AUDIO_STATE_MUTED;
                    end else begin
                        state <= HDMI_AUDIO_STATE_RUNNING;
                    end
                end
                HDMI_AUDIO_STATE_FAULT: begin
                    configured <= 1'b0;
                    if (clear_fault) begin
                        recovery_attempts <= '0;
                        state_timer <= '0;
                        state <= HDMI_AUDIO_STATE_RECOVERY;
                    end else if (!video_ready || !hpd_stable) begin
                        saw_link_loss <= 1'b1;
                        state <= HDMI_AUDIO_STATE_WAIT_VIDEO;
                    end else if (RECOVERY_DELAY_CYCLES <= 1 ||
                                 state_timer == RECOVERY_DELAY_CYCLES - 1) begin
                        state_timer <= '0;
                        if (recovery_attempts >= MAX_RECOVERIES) begin
                            last_error <= HDMI_AUDIO_RECOVERY_FAILED;
                        end else begin
                            recovery_attempts <= recovery_attempts + 1'b1;
                            state <= HDMI_AUDIO_STATE_RECOVERY;
                        end
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                HDMI_AUDIO_STATE_RECOVERY: begin
                    configured <= 1'b0;
                    if ((RECOVERY_DELAY_CYCLES <= 1 ||
                        state_timer >= RECOVERY_DELAY_CYCLES - 1) &&
                        (!video_ready || command_ready)) begin
                        state_timer <= '0;
                        state <= (video_ready && hpd_stable) ?
                            HDMI_AUDIO_STATE_WAIT_CLOCK :
                            HDMI_AUDIO_STATE_WAIT_VIDEO;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end
                default: state <= HDMI_AUDIO_STATE_RESET;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset && enabled) begin
            assert (configured && video_ready && hpd_stable);
            assert (audio_lock_sync[1]);
        end
    end
`endif
endmodule
