# Additive Phase 3I interface constraints. The base Phase 3F constraint owns
# the single 50 MHz clock and all established PPU ports.
set_false_path -to [get_ports {
    ppu_nmi_level ppu_nmi_event ppu_nmi_suppressed
}]
