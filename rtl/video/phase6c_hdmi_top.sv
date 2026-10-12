`timescale 1ns/1ps

// Standalone synthesis/fitting harness for the Phase 6C logical transmitter
// boundary.  HDMI_* are virtual, board-level signals: this module neither
// implements TMDS nor assigns pins on the stock DE1-SoC.
module phase6c_hdmi_top (
    input  logic        CLOCK_50,
    input  logic        RESET_N,
    input  logic        DEVELOPER_LAYOUT,
    input  logic        TEST_PATTERN,
    input  logic        CAPTURE_FREEZE,
    input  logic        HDMI_HPD,
    input  logic        HDMI_I2C_SCL_IN,
    input  logic        HDMI_I2C_SDA_IN,
    output logic        HDMI_I2C_SCL_DRIVE_LOW,
    output logic        HDMI_I2C_SDA_DRIVE_LOW,
    output logic        HDMI_PD,
    output logic        HDMI_PCLK,
    output logic [23:0] HDMI_RGB,
    output logic        HDMI_HSYNC,
    output logic        HDMI_VSYNC,
    output logic        HDMI_DE,
    output logic        HDMI_FRAME_START,
    output logic        HDMI_VIDEO_ENABLED,
    output logic        HDMI_TX_PRESENT,
    output logic        HDMI_TX_CONFIGURED,
    output logic        HDMI_TX_FAULT,
    output logic [1:0]  HDMI_HPD_STATE,
    output logic        HDMI_EDID_VALID,
    output logic        HDMI_MODE_SUPPORTED,
    output logic [3:0]  HDMI_STARTUP_STATE,
    output logic [7:0]  HDMI_LAST_ERROR,
    output logic [31:0] HDMI_VIDEO_FRAMES,
    output logic [31:0] HDMI_I2C_NACKS,
    output logic [31:0] HDMI_I2C_TIMEOUTS,
    output logic [31:0] HDMI_RECOVERIES,
    output logic        VIDEO_LOCKED,
    output logic        VIDEO_ERROR
);
    logic control_reset, pixel_reset;
    logic pipeline_pclk, pipeline_hsync, pipeline_vsync, pipeline_de;
    logic pipeline_frame_start;
    logic [7:0] pipeline_r, pipeline_g, pipeline_b;
    logic video_enable, safe_disable, frame_toggle;
    logic edid_available, video_clock_locked;

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

    hdmi_tx_controller controller (
        .clk(CLOCK_50),
        .reset(control_reset),
        .pixel_clock_locked_async(VIDEO_LOCKED),
        .frame_toggle_async(frame_toggle),
        .hpd_async(HDMI_HPD),
        .scl_in(HDMI_I2C_SCL_IN),
        .sda_in(HDMI_I2C_SDA_IN),
        .audio_clock_locked_async(1'b0),
        .audio_configuration_allowed(1'b0),
        .audio_transport_primed(1'b0),
        .audio_user_mute(1'b0),
        .audio_fault_clear(1'b0),
        .audio_fifo_underruns(32'b0),
        .audio_fifo_overruns(32'b0),
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
        .hdmi_audio_configured(),
        .hdmi_audio_enabled(),
        .hdmi_audio_muted(),
        .hdmi_audio_clock_locked(),
        .hdmi_audio_accept_samples(),
        .hdmi_audio_stream_enable(),
        .hdmi_audio_fifo_flush(),
        .hdmi_audio_fault(),
        .hdmi_audio_state(),
        .hdmi_audio_reconnect_count(),
        .hdmi_audio_last_error()
    );

    assign HDMI_VIDEO_ENABLED = video_enable && !safe_disable &&
                                edid_available && video_clock_locked;
endmodule
