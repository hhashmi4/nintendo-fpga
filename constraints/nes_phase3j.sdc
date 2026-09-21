# Phase 3J retains one 50 MHz fabric clock. CPU and PPU timing are expressed
# exclusively with synchronous clock enables inside this domain.
create_clock -name clk -period 20.000 [get_ports {clk}]

set_false_path -from [get_ports {
    reset nes_enable irq mirroring_mode[*] cart_cpu_read_data[*] chr_read_data[*]
}]

set_false_path -to [get_ports {
    cart_cpu_address[*] cart_cpu_read cart_cpu_write cart_cpu_write_data[*]
    chr_addr[*] chr_read chr_write chr_write_data[*]
    ppu_enable cpu_cycle_slot cpu_enable scheduler_phase[*]
    cpu_address[*] cpu_write_data[*] cpu_read_data[*] cpu_write_enable
    cpu_bus_valid cpu_debug_a[*] cpu_debug_x[*] cpu_debug_y[*]
    cpu_debug_sp[*] cpu_debug_pc[*] dma_active dma_phase[*] dma_page[*]
    dma_index[*] dma_data[*] dma_stall_cycles[*] dma_read_count[*]
    dma_write_count[*] dma_read_event dma_write_event dma_complete_event
    ppu_dot[*] ppu_scanline[*] ppu_frame_odd ppu_frame_start ppu_frame_end
    ppu_status_vblank ppu_status_sprite_zero_hit ppu_status_sprite_overflow
    ppu_ctrl[*] ppu_mask[*] ppu_nmi_level ppu_nmi_event
    ppu_nmi_suppressed ppu_oam_addr[*] ppu_oam_write_commit
    ppu_oam_collision pixel_valid pixel_x[*] pixel_y[*]
    pixel_palette_address[*] pixel_nes_color[*] pixel_color_emphasis[*]
    pixel_source[*]
}]

# cpu_core's architectural state advances only on cpu_enable, which is true on
# every third fabric edge. The interrupt synchronizer/pending flops deliberately
# run on every fabric edge and remain single-cycle paths. Apply the architectural
# three-edge relationship at the endpoints, with the paired hold adjustment.
set cpu_arch_registers [get_registers {cpu_core:cpu|*}]
set cpu_sync_registers [get_registers {
    cpu_core:cpu|nmi_meta cpu_core:cpu|nmi_sync
    cpu_core:cpu|nmi_sync_delayed cpu_core:cpu|nmi_pending
    cpu_core:cpu|irq_meta cpu_core:cpu|irq_sync
}]
set cpu_arch_registers [remove_from_collection \
    $cpu_arch_registers $cpu_sync_registers]
set_multicycle_path -setup 3 -to $cpu_arch_registers
set_multicycle_path -hold 2 -to $cpu_arch_registers

derive_clock_uncertainty
