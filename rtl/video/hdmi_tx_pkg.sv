`timescale 1ns/1ps

// Phase 6C transmitter-control contract.  Fault values are kept independent
// from the older system diagnostic fault namespace so the complete HDMI cause
// is observable in HDMI_LAST_ERROR without consuming all remaining sticky
// system-fault bits.
package hdmi_tx_pkg;
    typedef enum logic [3:0] {
        HDMI_STATE_RESET                    = 4'd0,
        HDMI_STATE_WAIT_CLOCK               = 4'd1,
        HDMI_STATE_WAIT_HPD                 = 4'd2,
        HDMI_STATE_CONFIGURE                = 4'd3,
        HDMI_STATE_VERIFY_CONFIG            = 4'd4,
        HDMI_STATE_CHECK_DISPLAY_CAPABILITY = 4'd5,
        HDMI_STATE_ENABLE_VIDEO             = 4'd6,
        HDMI_STATE_RUNNING                  = 4'd7,
        HDMI_STATE_FAULT                    = 4'd8,
        HDMI_STATE_RECOVERY                 = 4'd9
    } hdmi_startup_state_t;

    typedef enum logic [7:0] {
        HDMI_ERROR_NONE                    = 8'd0,
        HDMI_TX_NOT_DETECTED               = 8'd1,
        HDMI_TX_I2C_NACK                   = 8'd2,
        HDMI_TX_I2C_TIMEOUT                = 8'd3,
        HDMI_HPD_TIMEOUT                   = 8'd4,
        HDMI_EDID_INVALID                  = 8'd5,
        HDMI_MODE_UNSUPPORTED              = 8'd6,
        HDMI_PIXEL_CLOCK_UNLOCKED          = 8'd7,
        HDMI_CONFIG_VERIFY_FAILED          = 8'd8,
        HDMI_RECOVERY_FAILED               = 8'd9
    } hdmi_error_t;

    localparam logic [6:0] ADV7513_MAIN_ADDRESS = 7'h39;
    localparam logic [6:0] ADV7513_EDID_ADDRESS = 7'h3f;
endpackage
