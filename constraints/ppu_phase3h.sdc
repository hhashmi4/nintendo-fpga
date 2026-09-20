# Additive Phase 3H constraints. The integrated project retains the Phase 3F
# 50 MHz clock and I/O timing; these logical video/debug ports are observed by
# verification now and will feed a separately constrained video stage later.
set_false_path -to [get_ports {
    final_pixel_valid final_pixel_x[*] final_pixel_y[*]
    final_palette_address[*] final_nes_color[*] final_color_emphasis[*]
    final_pixel_source[*] sprite_zero_hit_event
    final_winning_sprite_slot[*] final_winning_sprite_zero
}]
