# Standalone Phase 3A timing-core proof. Integration continues to use the same
# 50 MHz fabric clock and a PPU clock enable; there is no generated PPU clock.
create_clock -name clk -period 20.000 [get_ports {clk}]

# These inputs will be produced synchronously in the integrated system. The
# standalone project has no board-level input timing contract for them.
set_false_path -from [get_ports {reset ppu_enable rendering_enabled}]

# Standalone observability ports have no external synchronous receiver. Core
# register-to-register paths remain timed by the 50 MHz primary clock.
set_false_path -to [get_ports {
    dot[*] scanline[*] frame_odd visible_pixel pixel_x[*] pixel_y[*] vblank
    frame_start frame_end scanline_start vblank_start vblank_end
    pre_render post_render
}]

derive_clock_uncertainty
