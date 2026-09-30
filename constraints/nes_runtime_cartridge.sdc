# Standalone Phase 4F-C timing/resource proof. The HPS bridge remains outside
# this module, so its eventual CDC and I/O timing contract are not modeled.
create_clock -name clk -period 20.000 [get_ports {clk}]

set_false_path -from [get_ports {
    reset command_valid command[*] command_target[*] command_address[*]
    command_data[*] manifest_valid manifest_mapper[*] manifest_prg_bytes[*]
    manifest_chr_bytes[*] manifest_chr_is_ram manifest_mirroring[*]
    nrom_256 chr_is_ram cpu_address[*] cpu_read cpu_write
    cpu_write_data[*] chr_address[*] chr_read chr_write chr_write_data[*]
}]

set_false_path -to [get_ports {
    command_ready command_accepted cpu_read_data[*] chr_read_data[*]
    loader_state[*] loader_busy loader_completed loader_error
    loader_error_code[*] nes_hold_reset debug_prg_address[*]
    image_valid image_mapper[*] image_prg_bytes[*] image_chr_bytes[*]
    image_chr_is_ram image_mirroring[*]
    debug_prg_data[*] debug_chr_address[*] debug_chr_data[*]
    debug_prg_read debug_prg_write debug_chr_read debug_chr_write
}]

derive_clock_uncertainty
