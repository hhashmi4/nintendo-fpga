create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks

set video_pixel_clock [get_clocks {
    *pixel_clock_720p_pll*PLL_OUTPUT_COUNTER|divclk
}]
if {[get_collection_size $video_pixel_clock] != 1} {
    post_message -type error "Phase 6B 74.25 MHz PLL clock was not discovered"
}

# The framebuffer owns all crossings between the asynchronous NES producer
# and scanout. Toggle synchronizers qualify bank identifiers that remain
# stable until acknowledgement.
set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group [get_clocks {*pixel_clock_720p_pll*}]

set framebuffer_cdc_first_stage_registers [get_registers {
    *pipeline|framebuffer|acknowledge_sync[0]
    *pipeline|framebuffer|request_sync[0]
    *pipeline|framebuffer|completed_bank_meta*
    *pipeline|framebuffer|read_bank_meta*
}]
set_false_path -to $framebuffer_cdc_first_stage_registers

# Asynchronous controls terminate at explicit two-flop synchronizers. Cut only
# their first stages; all downstream control and frame-latching paths remain
# timed. RESET_N asserts asynchronously into reset synchronizers.
set async_control_first_stages [get_registers {
    *capture_freeze_sync[0]
    *console_hold_sync[0]
    *pipeline|video|test_pattern_sync[0]
    *pipeline|video|developer_layout_sync[0]
}]
set_false_path -from [get_ports {
    DEVELOPER_LAYOUT TEST_PATTERN CAPTURE_FREEZE CONSOLE_HOLD
}] -to $async_control_first_stages
set_false_path -from [get_ports {RESET_N}]

# This qualification harness does not represent a PCB transmitter interface;
# these conservative virtual output delays keep the RGB/control path timed.
set_output_delay -clock $video_pixel_clock -max 3.000 \
    [get_ports {VIDEO_R[*] VIDEO_G[*] VIDEO_B[*] VIDEO_HSYNC VIDEO_VSYNC VIDEO_DE VIDEO_FRAME_START}]
set_output_delay -clock $video_pixel_clock -min -1.000 \
    [get_ports {VIDEO_R[*] VIDEO_G[*] VIDEO_B[*] VIDEO_HSYNC VIDEO_VSYNC VIDEO_DE VIDEO_FRAME_START}]
set_false_path -to [get_ports {VIDEO_PCLK VIDEO_LOCKED VIDEO_ERROR}]

derive_clock_uncertainty

# Synchronous logical-only library injection, timed rather than exempted.
set_input_delay -clock CLOCK_50 -max 2.000 [get_ports {LIBRARY_WORD[*] LIBRARY_SHIFT}]
set_input_delay -clock CLOCK_50 -min 0.000 [get_ports {LIBRARY_WORD[*] LIBRARY_SHIFT}]
