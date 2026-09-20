# Additive Phase 3G constraints. The project retains the Phase 3F single
# 50 MHz clock and I/O constraints; these are new observability outputs only.
set_false_path -to [get_ports {
    sprite_memory_request sprite_memory_address[*] sprite_memory_grant
    sprite_memory_read_data[*] renderer_owner_conflict sprite_fetch_slot[*]
    sprite_fetch_phase[*] sprite_fetch_type[*] sprite_fetch_complete
    sprite_slot_load sprite_fetch_relative_row[*]
    sprite_fetch_selected_row[*] sprite_pattern_low_address[*]
    sprite_pattern_high_address[*] sprite_decrement_mask[*]
    sprite_shift_mask[*] sprite_pixel_valid sprite_x[*] sprite_y[*]
    sprite_pattern[*] sprite_palette[*] sprite_palette_index[*]
    sprite_opaque sprite_priority_behind_background sprite_is_zero
    sprite_slot[*] sprite_original_index[*]
}]
