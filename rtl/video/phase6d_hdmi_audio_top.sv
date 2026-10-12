`timescale 1ns/1ps

// Standalone logical Phase 6D boundary. The actual Phase 5K PCM stream and
// its existing PLL feed both codec and HDMI. No extra PLL/resampler is added.
// HDMI_* remain virtual because the stock DE1-SoC has no ADV7513 connection.
module phase6d_hdmi_audio_top #(
    // Explicit logical-verification opt-in. No physical enable is permitted
    // by default until the documented profile and carrier are qualified.
    parameter bit ALLOW_UNQUALIFIED_AUDIO = 1'b0
) (
    input  logic               CLOCK_50,
    input  logic               RESET_N,
    input  logic               DEVELOPER_LAYOUT,
    input  logic               TEST_PATTERN,
    input  logic               CAPTURE_FREEZE,
    input  logic               HDMI_HPD,
    input  logic               HDMI_I2C_SCL_IN,
    input  logic               HDMI_I2C_SDA_IN,
    input  logic [19:0]        APU_MIXED_AUDIO,
    input  logic               APU_TICK,
    input  logic               SOURCE_RESET,
    input  logic               CODEC_SCL_IN,
    input  logic               CODEC_SDA_IN,
    output logic               CODEC_SCL_DRIVE_LOW,
    output logic               CODEC_SDA_DRIVE_LOW,
    output logic               AUD_XCK,
    output logic               AUD_BCLK,
    output logic               AUD_DACLRCK,
    output logic               AUD_DACDAT,
    input  logic               HDMI_AUDIO_USER_MUTE,
    input  logic               HDMI_AUDIO_FAULT_CLEAR,
    output logic               PCM_READY,
    output logic               HDMI_I2C_SCL_DRIVE_LOW,
    output logic               HDMI_I2C_SDA_DRIVE_LOW,
    output logic               HDMI_PD,
    output logic               HDMI_PCLK,
    output logic [23:0]        HDMI_RGB,
    output logic               HDMI_HSYNC,
    output logic               HDMI_VSYNC,
    output logic               HDMI_DE,
    output logic               HDMI_FRAME_START,
    output logic               HDMI_VIDEO_ENABLED,
    output logic               HDMI_TX_PRESENT,
    output logic               HDMI_TX_CONFIGURED,
    output logic               HDMI_TX_FAULT,
    output logic [1:0]         HDMI_HPD_STATE,
    output logic               HDMI_EDID_VALID,
    output logic               HDMI_MODE_SUPPORTED,
    output logic [3:0]         HDMI_STARTUP_STATE,
    output logic [7:0]         HDMI_LAST_ERROR,
    output logic [31:0]        HDMI_VIDEO_FRAMES,
    output logic [31:0]        HDMI_I2C_NACKS,
    output logic [31:0]        HDMI_I2C_TIMEOUTS,
    output logic [31:0]        HDMI_RECOVERIES,
    output logic               HDMI_AUDIO_BCLK,
    output logic               HDMI_AUDIO_LRCLK,
    output logic               HDMI_AUDIO_I2S,
    output logic               HDMI_AUDIO_CONFIGURED,
    output logic               HDMI_AUDIO_ENABLED,
    output logic               HDMI_AUDIO_MUTED,
    output logic               HDMI_AUDIO_CLOCK_LOCKED,
    output logic               HDMI_AUDIO_FAULT,
    output logic [3:0]         HDMI_AUDIO_STATE,
    output logic [31:0]        HDMI_AUDIO_SAMPLE_COUNT,
    output logic [15:0]        HDMI_AUDIO_FIFO_OCCUPANCY,
    output logic [31:0]        HDMI_AUDIO_FIFO_UNDERRUNS,
    output logic [31:0]        HDMI_AUDIO_FIFO_OVERRUNS,
    output logic [31:0]        HDMI_AUDIO_RECONNECT_COUNT,
    output logic [7:0]         HDMI_AUDIO_LAST_ERROR,
    output logic               VIDEO_LOCKED,
    output logic               VIDEO_ERROR
);
    logic control_reset, pixel_reset, audio_reset;
    logic pipeline_pclk, pipeline_hsync, pipeline_vsync, pipeline_de;
    logic pipeline_frame_start;
    logic [7:0] pipeline_r, pipeline_g, pipeline_b;
    logic video_enable, safe_disable, frame_toggle;
    logic edid_available, video_clock_locked;
    logic audio_accept_samples, audio_stream_enable, audio_fifo_flush;
    logic audio_transport_primed;
    logic AUDIO_CLK_50M, AUDIO_PLL_LOCKED, PCM_RESET, PCM_VALID;
    logic signed [15:0] PCM_SAMPLE;

    /* verilator lint_off PINCONNECTEMPTY */
    nes_audio_output #(.ENABLE_HDMI_CLOCK(1'b1)) pcm_source (
        .clk(CLOCK_50), .reset(control_reset), .source_reset(SOURCE_RESET),
        .input_tick(APU_TICK), .mixed_audio(APU_MIXED_AUDIO),
        .test_tone_enable(1'b0), .codec_retry_request(1'b0),
        .i2c_scl_in(CODEC_SCL_IN), .i2c_sda_in(CODEC_SDA_IN),
        .i2c_scl_drive_low(CODEC_SCL_DRIVE_LOW),
        .i2c_sda_drive_low(CODEC_SDA_DRIVE_LOW),
        .aud_xck(AUD_XCK), .aud_bclk(AUD_BCLK),
        .aud_daclrck(AUD_DACLRCK), .aud_dacdat(AUD_DACDAT),
        .audio_pll_locked(AUDIO_PLL_LOCKED), .hdmi_audio_clk(AUDIO_CLK_50M),
        .pcm_output_sample(PCM_SAMPLE), .pcm_output_valid(PCM_VALID),
        .pcm_output_reset(PCM_RESET), .codec_init_busy(), .codec_init_done(),
        .codec_init_error(), .diag_i2c_ack_count(), .diag_i2c_nack_count(),
        .diag_init_retry_count(), .diag_i2c_timeout_count(),
        .diag_samples_generated(), .diag_samples_transmitted(),
        .diag_fifo_underruns(), .diag_fifo_overruns(), .diag_saturation_count(),
        .diag_fifo_occupancy(), .diag_sample_rate(), .diag_muted(),
        .diag_last_fault()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    phase6b_video_top shared_video (
        .CLOCK_50(CLOCK_50),
        .RESET_N(RESET_N),
        .DEVELOPER_LAYOUT(DEVELOPER_LAYOUT),
        .TEST_PATTERN(TEST_PATTERN),
        .CAPTURE_FREEZE(CAPTURE_FREEZE),
        .VIDEO_PCLK(pipeline_pclk),
        .VIDEO_HSYNC(pipeline_hsync),
        .VIDEO_VSYNC(pipeline_vsync),
        .VIDEO_DE(pipeline_de),
        .VIDEO_FRAME_START(pipeline_frame_start),
        .VIDEO_R(pipeline_r),
        .VIDEO_G(pipeline_g),
        .VIDEO_B(pipeline_b),
        .VIDEO_LOCKED(VIDEO_LOCKED),
        .VIDEO_ERROR(VIDEO_ERROR)
    );

    reset_sync control_reset_synchronizer (
        .clk(CLOCK_50),
        .async_reset_n(RESET_N),
        .reset(control_reset)
    );

    reset_sync pixel_reset_synchronizer (
        .clk(pipeline_pclk),
        .async_reset_n(RESET_N && VIDEO_LOCKED),
        .reset(pixel_reset)
    );

    reset_sync audio_reset_synchronizer (
        .clk(AUDIO_CLK_50M),
        .async_reset_n(RESET_N && AUDIO_PLL_LOCKED && !PCM_RESET),
        .reset(audio_reset)
    );

    hdmi_rgb_output rgb_adapter (
        .pixel_clk(pipeline_pclk),
        .pixel_reset(pixel_reset),
        .video_enable_async(video_enable),
        .pipeline_rgb({pipeline_r, pipeline_g, pipeline_b}),
        .pipeline_hsync(pipeline_hsync),
        .pipeline_vsync(pipeline_vsync),
        .pipeline_de(pipeline_de),
        .pipeline_frame_start(pipeline_frame_start),
        .tx_pixel_clock(HDMI_PCLK),
        .tx_rgb(HDMI_RGB),
        .tx_hsync(HDMI_HSYNC),
        .tx_vsync(HDMI_VSYNC),
        .tx_data_enable(HDMI_DE),
        .tx_frame_start(HDMI_FRAME_START),
        .frame_toggle(frame_toggle)
    );

    hdmi_audio_transport transport (
        .source_clk(CLOCK_50),
        .source_reset(control_reset || PCM_RESET),
        .pcm_sample(PCM_SAMPLE),
        .pcm_valid(PCM_VALID),
        .accept_samples(audio_accept_samples),
        .fifo_flush(audio_fifo_flush),
        .sample_ready(PCM_READY),
        .audio_clk(AUDIO_CLK_50M),
        .audio_reset(audio_reset),
        .stream_enable(audio_stream_enable),
        .mute(HDMI_AUDIO_MUTED),
        .i2s_bclk(HDMI_AUDIO_BCLK),
        .i2s_lrclk(HDMI_AUDIO_LRCLK),
        .i2s_data(HDMI_AUDIO_I2S),
        .primed(audio_transport_primed),
        .fifo_occupancy(HDMI_AUDIO_FIFO_OCCUPANCY),
        .sample_count(HDMI_AUDIO_SAMPLE_COUNT),
        .fifo_underruns(HDMI_AUDIO_FIFO_UNDERRUNS),
        .fifo_overruns(HDMI_AUDIO_FIFO_OVERRUNS)
    );

    hdmi_tx_controller controller (
        .clk(CLOCK_50),
        .reset(control_reset),
        .pixel_clock_locked_async(VIDEO_LOCKED),
        .frame_toggle_async(frame_toggle),
        .hpd_async(HDMI_HPD),
        .scl_in(HDMI_I2C_SCL_IN),
        .sda_in(HDMI_I2C_SDA_IN),
        .audio_clock_locked_async(AUDIO_PLL_LOCKED && !PCM_RESET),
        .audio_configuration_allowed(ALLOW_UNQUALIFIED_AUDIO),
        .audio_transport_primed(audio_transport_primed),
        .audio_user_mute(HDMI_AUDIO_USER_MUTE),
        .audio_fault_clear(HDMI_AUDIO_FAULT_CLEAR),
        .audio_fifo_underruns(HDMI_AUDIO_FIFO_UNDERRUNS),
        .audio_fifo_overruns(HDMI_AUDIO_FIFO_OVERRUNS),
        .scl_drive_low(HDMI_I2C_SCL_DRIVE_LOW),
        .sda_drive_low(HDMI_I2C_SDA_DRIVE_LOW),
        .video_enable(video_enable),
        .safe_disable(safe_disable),
        .transmitter_power_down(HDMI_PD),
        .transmitter_present(HDMI_TX_PRESENT),
        .transmitter_configured(HDMI_TX_CONFIGURED),
        .transmitter_fault(HDMI_TX_FAULT),
        .hpd_state(HDMI_HPD_STATE),
        .edid_available(edid_available),
        .edid_valid(HDMI_EDID_VALID),
        .mode_supported(HDMI_MODE_SUPPORTED),
        .video_clock_locked(video_clock_locked),
        .video_frames_sent(HDMI_VIDEO_FRAMES),
        .i2c_nack_count(HDMI_I2C_NACKS),
        .i2c_timeout_count(HDMI_I2C_TIMEOUTS),
        .recovery_count(HDMI_RECOVERIES),
        .last_error_code(HDMI_LAST_ERROR),
        .startup_state(HDMI_STARTUP_STATE),
        .hdmi_audio_configured(HDMI_AUDIO_CONFIGURED),
        .hdmi_audio_enabled(HDMI_AUDIO_ENABLED),
        .hdmi_audio_muted(HDMI_AUDIO_MUTED),
        .hdmi_audio_clock_locked(HDMI_AUDIO_CLOCK_LOCKED),
        .hdmi_audio_accept_samples(audio_accept_samples),
        .hdmi_audio_stream_enable(audio_stream_enable),
        .hdmi_audio_fifo_flush(audio_fifo_flush),
        .hdmi_audio_fault(HDMI_AUDIO_FAULT),
        .hdmi_audio_state(HDMI_AUDIO_STATE),
        .hdmi_audio_reconnect_count(HDMI_AUDIO_RECONNECT_COUNT),
        .hdmi_audio_last_error(HDMI_AUDIO_LAST_ERROR)
    );

    assign HDMI_VIDEO_ENABLED = video_enable && !safe_disable &&
                                edid_available && video_clock_locked;
endmodule
