# Board oscillator and PLL-derived VGA scan clock.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks

set vga_domain_clocks [get_clocks {*pixel_clock_pll*}]
set vga_pixel_clock [get_clocks {*PLL_OUTPUT_COUNTER|divclk}]
if {[get_collection_size $vga_pixel_clock] != 1} {
    post_message -type error "Phase 3K VGA PLL clock was not discovered"
}

# The frame memory is an intentional dual-clock CDC. Toggle handshakes and
# stable bundled bank identifiers are explicitly synchronized in RTL.
set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group $vga_domain_clocks

# KEY0 asserts reset asynchronously; every slide switch enters a two-flop
# synchronizer before its value is used in the corresponding clock domain.
set_false_path -from [get_ports {KEY0 SW0 SW1 SW2 SW3 SW4 SW5 SW6 SW7 SW8 SW9}]

# Give the external ADV7123 RGB/sync inputs a conservative eight-nanosecond
# setup budget. VGA_CLK is the inverted pixel clock, providing a half-cycle of
# physical setup; its clock output path itself has no synchronous receiver in
# the FPGA timing graph.
set_output_delay -clock $vga_pixel_clock -clock_fall -max 8.000 \
    [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N}]
set_output_delay -clock $vga_pixel_clock -clock_fall -min -1.000 \
    [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N}]
set_false_path -to [get_ports {VGA_CLK}]

# Human-visible debug outputs have no synchronous external receiver.
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]

# cpu_core architectural state can change only on cpu_enable. Even in the
# faster Phase 3J logical scheduler those updates are separated by three
# fabric edges; the Phase 3K NTSC enable spaces them farther apart. Retain the
# proven conservative three-edge relationship while leaving interrupt
# synchronizers and the NMI/IRQ pending flops as ordinary single-cycle paths.
set cpu_arch_registers [get_registers {nes_core:nes|cpu_core:cpu|*}]
set cpu_sync_registers [get_registers {
    nes_core:nes|cpu_core:cpu|nmi_meta
    nes_core:nes|cpu_core:cpu|nmi_sync
    nes_core:nes|cpu_core:cpu|nmi_sync_delayed
    nes_core:nes|cpu_core:cpu|nmi_pending
    nes_core:nes|cpu_core:cpu|irq_meta
    nes_core:nes|cpu_core:cpu|irq_sync
}]
set cpu_arch_registers [remove_from_collection \
    $cpu_arch_registers $cpu_sync_registers]
set_multicycle_path -setup 3 -to $cpu_arch_registers
set_multicycle_path -hold 2 -to $cpu_arch_registers

derive_clock_uncertainty
