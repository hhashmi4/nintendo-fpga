create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks

set video_pixel_clock [get_clocks {
    *pixel_clock_720p_pll*PLL_OUTPUT_COUNTER|divclk
}]
if {[get_collection_size $video_pixel_clock] != 1} {
    post_message -type error "Phase 6D 74.25 MHz PLL clock was not discovered"
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

# Two outputs of the existing audio PLL: 12 MHz codec and 50 MHz HDMI.
set audio_clocks [get_clocks {*audio_clock_pll*}]
# Select output clocks by period, independent of auto-generated counter names.
set codec_clock [get_clocks -nowarn {__no_clock__}]
set hdmi_audio_clock [get_clocks -nowarn {__no_clock__}]
foreach_in_collection clock $audio_clocks {
    set period [get_clock_info -period $clock]
    if {$period > 80.0} { set codec_clock $clock }
    if {$period > 19.9 && $period < 20.1} { set hdmi_audio_clock $clock }
}
set_clock_groups -asynchronous -group $audio_clocks -group $video_pixel_clock
# Gray-pointer/sample CDC between reference and PLL outputs. The existing
# Phase 5K codec crosses 50/12 MHz via two-flop synchronizers, not by timing
# the closest rational-clock edge. Bound first-stage routing to one fastest
# domain period; all second stages and ordinary datapaths retain setup/hold.
# This is narrower than the production Phase 5K asynchronous clock groups.
set codec_to_fabric_stage [get_registers {
    *pcm_source|sample_fifo|read_gray_sync1[*]
}]
set fabric_to_codec_stage [get_registers {
    *pcm_source|sample_fifo|write_gray_sync1[*]
    *pcm_source|prefill_sync[0]
}]
set_max_delay 20.000 -from $codec_clock -to $codec_to_fabric_stage
set_min_delay 0.000 -from $codec_clock -to $codec_to_fabric_stage
set_max_delay 20.000 -from [get_clocks {CLOCK_50}] -to $fabric_to_codec_stage
set_min_delay 0.000 -from [get_clocks {CLOCK_50}] -to $fabric_to_codec_stage
# Fabric-domain controls only drive the asynchronous clear inputs of these
# reset synchronizers. Their audio-clock release propagation remains timed.
set audio_reset_stages [get_registers {*audio_reset_generator|sync_ff[*] *audio_reset_synchronizer|sync_ff[*]}]
set_false_path -from [get_clocks {CLOCK_50}] -to $audio_reset_stages
set_false_path -from [get_ports {SOURCE_RESET}] -to $audio_reset_stages
# Phase 6G returns the consumer reset epoch to the producer's reset
# synchronizer. Only its asynchronous clear crosses; release flops stay timed.
set_false_path -from $codec_clock -to [get_registers {
    *pcm_source|stream_reset_generator|sync_ff[*]
}]
set_false_path -to [get_registers -nowarn {
    *controller|audio_controller|audio_lock_sync[0]
    *pcm_source|audio_pll_lock_sync[0]
}]
set_input_delay -clock CLOCK_50 -max 5.0 [get_ports {APU_MIXED_AUDIO[*] APU_TICK SOURCE_RESET HDMI_AUDIO_USER_MUTE HDMI_AUDIO_FAULT_CLEAR CODEC_SCL_IN CODEC_SDA_IN}]
set_input_delay -clock CLOCK_50 -min 0.0 [get_ports {APU_MIXED_AUDIO[*] APU_TICK SOURCE_RESET HDMI_AUDIO_USER_MUTE HDMI_AUDIO_FAULT_CLEAR CODEC_SCL_IN CODEC_SDA_IN}]

set_output_delay -clock CLOCK_50 -max 5.0 [get_ports {PCM_READY CODEC_SCL_DRIVE_LOW CODEC_SDA_DRIVE_LOW HDMI_AUDIO_CONFIGURED HDMI_AUDIO_ENABLED HDMI_AUDIO_MUTED HDMI_AUDIO_CLOCK_LOCKED HDMI_AUDIO_FAULT HDMI_AUDIO_STATE[*] HDMI_AUDIO_SAMPLE_COUNT[*] HDMI_AUDIO_FIFO_OCCUPANCY[*] HDMI_AUDIO_FIFO_UNDERRUNS[*] HDMI_AUDIO_FIFO_OVERRUNS[*] HDMI_AUDIO_RECONNECT_COUNT[*] HDMI_AUDIO_LAST_ERROR[*]}]
set_output_delay -clock CLOCK_50 -min -1.0 [get_ports {PCM_READY CODEC_SCL_DRIVE_LOW CODEC_SDA_DRIVE_LOW HDMI_AUDIO_CONFIGURED HDMI_AUDIO_ENABLED HDMI_AUDIO_MUTED HDMI_AUDIO_CLOCK_LOCKED HDMI_AUDIO_FAULT HDMI_AUDIO_STATE[*] HDMI_AUDIO_SAMPLE_COUNT[*] HDMI_AUDIO_FIFO_OCCUPANCY[*] HDMI_AUDIO_FIFO_UNDERRUNS[*] HDMI_AUDIO_FIFO_OVERRUNS[*] HDMI_AUDIO_RECONNECT_COUNT[*] HDMI_AUDIO_LAST_ERROR[*]}]

# Conservative single-cycle logical I/O budget, not physical carrier timing.
# Data/LRCLK change on BCLK falling edges and have >=160 ns before capture.
# Clock-enable-generated fractional BCLK is verified edge-by-edge in RTL;
# do not pretend it is a fixed integer-divide generated clock in TimeQuest.
set_output_delay -clock $hdmi_audio_clock -max 5.0 [get_ports {HDMI_AUDIO_BCLK HDMI_AUDIO_LRCLK HDMI_AUDIO_I2S}]
set_output_delay -clock $hdmi_audio_clock -min -1.0 [get_ports {HDMI_AUDIO_BCLK HDMI_AUDIO_LRCLK HDMI_AUDIO_I2S}]
set_output_delay -clock $codec_clock -max 5.0 [get_ports {AUD_BCLK AUD_DACLRCK AUD_DACDAT}]
set_output_delay -clock $codec_clock -min -1.0 [get_ports {AUD_BCLK AUD_DACLRCK AUD_DACDAT}]
set_false_path -to [get_ports {AUD_XCK}]
