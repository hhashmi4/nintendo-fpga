create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks

set video_pixel_clock [get_clocks {
    *pixel_clock_720p_pll*PLL_OUTPUT_COUNTER|divclk
}]
if {[get_collection_size $video_pixel_clock] != 1} {
    post_message -type error "Phase 6C 74.25 MHz PLL clock was not discovered"
}

set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group [get_clocks {*pixel_clock_720p_pll*}]

# Phase 6B framebuffer CDC remains unchanged inside the standalone wrapper.
set_false_path -to [get_registers -nowarn {
    *shared_video|pipeline|framebuffer|acknowledge_sync[0]
    *shared_video|pipeline|framebuffer|request_sync[0]
    *shared_video|pipeline|framebuffer|completed_bank_meta*
    *shared_video|pipeline|framebuffer|read_bank_meta*
}]

# Cut only the first stage of each explicit asynchronous synchronizer.
set_false_path -to [get_registers -nowarn {
    *shared_video|capture_freeze_sync[0]
    *shared_video|pipeline|video|test_pattern_sync[0]
    *shared_video|pipeline|video|developer_layout_sync[0]
    *controller|hpd_filter|hpd_sync[0]
    *controller|pixel_lock_sync[0]
    *controller|frame_toggle_sync[0]
    *controller|i2c_master|scl_meta
    *controller|i2c_master|sda_meta
    *rgb_adapter|video_enable_sync[0]
}]
set_false_path -from [get_ports {
    DEVELOPER_LAYOUT TEST_PATTERN CAPTURE_FREEZE HDMI_HPD
    HDMI_I2C_SCL_IN HDMI_I2C_SDA_IN RESET_N
}]

# ADV7513 captures D[23:0]/sync/DE on rising CLK.  HDMI_PCLK is inverted, so
# that edge is the source PLL falling edge, one half-pixel after data launch.
# The external budget includes the 1.8 ns setup and 1.3 ns hold requirements
# plus 1 ns of provisional carrier skew.  Physical timing must be re-run with
# real package/PCB delays before hardware approval.  Model the forwarded clock
# at its output rather than an ideal internal falling edge so clock-tree and
# output-route skew are included in the source-synchronous analysis.
set video_pixel_clock_target [get_clock_info -targets $video_pixel_clock]
create_generated_clock -name HDMI_TX_CAPTURE \
    -source $video_pixel_clock_target -invert [get_ports {HDMI_PCLK}]
set hdmi_capture_clock [get_clocks {HDMI_TX_CAPTURE}]
set_output_delay -clock $hdmi_capture_clock -max 2.800 \
    [get_ports {HDMI_RGB[*] HDMI_HSYNC HDMI_VSYNC HDMI_DE HDMI_FRAME_START}]
set_output_delay -clock $hdmi_capture_clock -min -2.300 \
    [get_ports {HDMI_RGB[*] HDMI_HSYNC HDMI_VSYNC HDMI_DE HDMI_FRAME_START}]

set_output_delay -clock [get_clocks {CLOCK_50}] -max 5.000 \
    [get_ports {HDMI_I2C_SCL_DRIVE_LOW HDMI_I2C_SDA_DRIVE_LOW HDMI_PD
                HDMI_VIDEO_ENABLED HDMI_TX_PRESENT HDMI_TX_CONFIGURED
                HDMI_TX_FAULT HDMI_HPD_STATE[*] HDMI_EDID_VALID
                HDMI_MODE_SUPPORTED HDMI_STARTUP_STATE[*] HDMI_LAST_ERROR[*]
                HDMI_VIDEO_FRAMES[*] HDMI_I2C_NACKS[*]
                HDMI_I2C_TIMEOUTS[*] HDMI_RECOVERIES[*] VIDEO_ERROR}]
set_output_delay -clock [get_clocks {CLOCK_50}] -min -1.000 \
    [get_ports {HDMI_I2C_SCL_DRIVE_LOW HDMI_I2C_SDA_DRIVE_LOW HDMI_PD
                HDMI_VIDEO_ENABLED HDMI_TX_PRESENT HDMI_TX_CONFIGURED
                HDMI_TX_FAULT HDMI_HPD_STATE[*] HDMI_EDID_VALID
                HDMI_MODE_SUPPORTED HDMI_STARTUP_STATE[*] HDMI_LAST_ERROR[*]
                HDMI_VIDEO_FRAMES[*] HDMI_I2C_NACKS[*]
                HDMI_I2C_TIMEOUTS[*] HDMI_RECOVERIES[*] VIDEO_ERROR}]
set_false_path -to [get_ports {HDMI_PCLK VIDEO_LOCKED}]

derive_clock_uncertainty
