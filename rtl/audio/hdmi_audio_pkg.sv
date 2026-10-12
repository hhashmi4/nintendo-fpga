`timescale 1ns/1ps

package hdmi_audio_pkg;
    typedef enum logic [3:0] {
        HDMI_AUDIO_STATE_RESET          = 4'd0,
        HDMI_AUDIO_STATE_WAIT_VIDEO     = 4'd1,
        HDMI_AUDIO_STATE_WAIT_CLOCK     = 4'd2,
        HDMI_AUDIO_STATE_CONFIGURE      = 4'd3,
        HDMI_AUDIO_STATE_VERIFY_CONFIG  = 4'd4,
        HDMI_AUDIO_STATE_PRIME_AUDIO    = 4'd5,
        HDMI_AUDIO_STATE_ENABLE_AUDIO   = 4'd6,
        HDMI_AUDIO_STATE_RUNNING        = 4'd7,
        HDMI_AUDIO_STATE_MUTED          = 4'd8,
        HDMI_AUDIO_STATE_FAULT          = 4'd9,
        HDMI_AUDIO_STATE_RECOVERY       = 4'd10
    } hdmi_audio_state_t;

    typedef enum logic [7:0] {
        HDMI_AUDIO_ERROR_NONE                 = 8'd0,
        HDMI_AUDIO_CLOCK_UNLOCKED             = 8'd1,
        HDMI_AUDIO_CONFIG_NACK                = 8'd2,
        HDMI_AUDIO_CONFIG_TIMEOUT             = 8'd3,
        HDMI_AUDIO_CONFIG_VERIFY_FAILED       = 8'd4,
        HDMI_AUDIO_FIFO_UNDERRUN              = 8'd5,
        HDMI_AUDIO_FIFO_OVERRUN               = 8'd6,
        HDMI_AUDIO_LINK_LOST                  = 8'd7,
        HDMI_AUDIO_RECOVERY_FAILED            = 8'd8
    } hdmi_audio_error_t;
endpackage
