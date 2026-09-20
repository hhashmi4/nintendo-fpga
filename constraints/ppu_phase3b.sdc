# Standalone Phase 3B integrated timing/register proof.  There is one 50 MHz
# fabric clock and no generated CPU or PPU clock.
create_clock -name clk -period 20.000 [get_ports {clk}]

# Inputs will be synchronous producers in the later system integration.  The
# standalone core has no board-level arrival-time contract for abstract buses.
set_false_path -from [get_ports {
    reset ppu_enable cpu_enable cpu_bus_valid cpu_bus_write cpu_address[*]
    cpu_write_data[*] sprite_zero_hit_set sprite_overflow_set oam_read_data[*]
    ppu_memory_read_data[*] ppu_memory_buffer_read_data[*]
}]

# Standalone observability/abstract consumer ports have no physical receiver.
# Register-to-register paths remain constrained by the primary 50 MHz clock.
set_false_path -to [get_ports {
    cpu_read_data[*] cpu_register_selected cpu_register_index[*]
    oam_addr[*] oam_write_data[*] oam_write_enable ppu_memory_address[*]
    ppu_memory_buffer_address[*] ppu_memory_read_request
    ppu_memory_write_request ppu_memory_write_data[*] dot[*] scanline[*]
    frame_odd visible_pixel pixel_x[*] pixel_y[*] timing_vblank frame_start
    frame_end scanline_start vblank_start vblank_end pre_render post_render
    ppuctrl[*] ppumask[*] status_vblank status_sprite_zero_hit
    status_sprite_overflow vram_address[*] temp_vram_address[*] fine_x[*]
    write_toggle ppu_data_read_buffer[*] ppu_io_latch[*] nmi_enable
    ppu_nmi_level ppu_nmi_event ppu_nmi_suppressed
    ppu_master_slave sprite_size_16 background_pattern_table
    sprite_pattern_table vram_increment[*] base_nametable[*] mask_grayscale
    mask_show_background_left mask_show_sprites_left mask_show_background
    mask_show_sprites mask_emphasize_red mask_emphasize_green
    mask_emphasize_blue rendering_enabled rendering_scanline
    active_render_period coarse_x_increment_event vertical_increment_event
    horizontal_copy_event vertical_copy_event automatic_scroll_event
    nametable_fetch_address[*] attribute_fetch_address[*]
}]

derive_clock_uncertainty
