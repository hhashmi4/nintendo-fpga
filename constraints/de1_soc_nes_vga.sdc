# Board oscillator and PLL-derived VGA scan clock.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks

set vga_domain_clocks [get_clocks {*pixel_clock_pll*}]
set vga_pixel_clock [get_clocks {
    *pixel_clock_source*PLL_OUTPUT_COUNTER|divclk
}]
if {[get_collection_size $vga_pixel_clock] != 1} {
    post_message -type error "Phase 3K VGA PLL clock was not discovered"
}

set audio_domain_clocks [get_clocks {*audio_clock_source*}]
set audio_master_clock [get_clocks {
    *audio_clock_source*PLL_OUTPUT_COUNTER|divclk
}]
if {[get_collection_size $audio_master_clock] != 1} {
    post_message -type error "Phase 5K 12.000 MHz audio PLL clock was not discovered"
}

# The frame memory is an intentional dual-clock CDC. Toggle handshakes and
# stable bundled bank identifiers are explicitly synchronized in RTL.
set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group $vga_domain_clocks
set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group $audio_domain_clocks
set_clock_groups -asynchronous \
    -group $vga_domain_clocks \
    -group $audio_domain_clocks

# Platform Designer constrains the HPS-generated loader/MMIO clock at its hard
# HPS source pin. It is asynchronous to both board oscillators. HPS-to-loader
# crossings are constrained individually below so their bundled payloads keep
# a finite routing bound instead of being hidden by a blanket false path.
set hps_loader_clocks [get_clocks {*h2f_user0_clk}]
if {[get_collection_size $hps_loader_clocks] != 1} {
    post_message -type error "Phase 4F-F HPS loader clock was not discovered"
}
set_clock_groups -asynchronous \
    -group $hps_loader_clocks \
    -group $vga_domain_clocks
set_clock_groups -asynchronous \
    -group $hps_loader_clocks \
    -group $audio_domain_clocks

# The HPS peripheral pins terminate in Cyclone V hard-HPS I/O rather than FPGA
# fabric. Platform Designer emits these false paths for its generated wrapper
# port names; repeat the intent for the board-level names used by this top.
# HPS DDR3 is deliberately excluded because its generated UniPHY constraints
# provide full external-interface timing analysis.
create_clock -name HPS_USB_ULPI_CLK -period 16.667 \
    [get_ports {HPS_USB_CLKOUT}]
create_clock -name HPS_I2C1_SCL -period 2500.000 \
    [get_ports {HPS_I2C1_SCLK}]
create_clock -name HPS_I2C2_SCL -period 2500.000 \
    [get_ports {HPS_I2C2_SCLK}]
set hps_hard_peripheral_ports [get_ports {
    HPS_ENET_* HPS_FLASH_* HPS_SD_* HPS_USB_* HPS_SPIM_* HPS_UART_*
    HPS_I2C* HPS_GSENSOR_INT HPS_KEY_N HPS_LED HPS_LTC_GPIO
}]
set_false_path -from $hps_hard_peripheral_ports
set_false_path -to $hps_hard_peripheral_ports

# Request/acknowledge toggles use explicit three-flop synchronizers. The
# payload banks are held until the corresponding synchronized toggle is
# acknowledged. A 20 ns datapath bound ensures every bundled data bit settles
# before a toggle can traverse the three receiving-domain stages.
set loader_cdc_first_stage_registers [get_registers {
    *runtime_loader_mailbox|request_sync[0]
    *runtime_loader_mailbox|acknowledge_sync[0]
    *runtime_loader_mailbox|status_request_sync[0]
    *runtime_loader_mailbox|status_acknowledge_sync[0]
}]
set_false_path -to $loader_cdc_first_stage_registers

set loader_cdc_command_bank [get_registers {
    *runtime_loader_mailbox|command_bank*
    *runtime_loader_mailbox|target_bank*
    *runtime_loader_mailbox|address_bank*
    *runtime_loader_mailbox|data_bank*
    *runtime_loader_mailbox|manifest_valid_bank*
    *runtime_loader_mailbox|manifest_mapper_bank*
    *runtime_loader_mailbox|manifest_prg_bytes_bank*
    *runtime_loader_mailbox|manifest_chr_bytes_bank*
    *runtime_loader_mailbox|manifest_chr_is_ram_bank*
    *runtime_loader_mailbox|manifest_mirroring_bank*
}]
set loader_cdc_destination_payload [get_registers {
    *runtime_loader_mailbox|destination_command*
    *runtime_loader_mailbox|destination_target*
    *runtime_loader_mailbox|destination_address*
    *runtime_loader_mailbox|destination_data*
    *runtime_loader_mailbox|destination_manifest_valid*
    *runtime_loader_mailbox|destination_manifest_mapper*
    *runtime_loader_mailbox|destination_manifest_prg_bytes*
    *runtime_loader_mailbox|destination_manifest_chr_bytes*
    *runtime_loader_mailbox|destination_manifest_chr_is_ram*
    *runtime_loader_mailbox|destination_manifest_mirroring*
}]
set_max_delay 20.000 \
    -from $loader_cdc_command_bank -to $loader_cdc_destination_payload

set loader_cdc_return_bank [get_registers {
    *runtime_loader_mailbox|response_bank*
    *runtime_loader_mailbox|status_bank*
}]
set loader_cdc_source_capture [get_registers {
    *runtime_loader_mailbox|source_response_state*
    *runtime_loader_mailbox|source_response_error*
    *runtime_loader_mailbox|source_response_error_code*
    *runtime_loader_mailbox|source_status_bank*
}]
set_max_delay 20.000 \
    -from $loader_cdc_return_bank -to $loader_cdc_source_capture

# KEY0 asserts reset asynchronously; every slide switch enters a two-flop
# synchronizer before its value is used in the corresponding clock domain.
set_false_path -from [get_ports {KEY0 SW0 SW1 SW2 SW3 SW4 SW5 SW6 SW7 SW8 SW9}]

# WM8731 slave-mode signals are generated from audio_clk with clock enables:
# XCK=12 MHz. A 64/125 half-edge accumulator gives BCLK=3.072 MHz and
# LRCK=BCLK/64=48 kHz exactly in the codec's 250fs USB mode. The datasheet
# requires data/LRCK changes on falling BCLK and samples on rising BCLK;
# ten nanoseconds is a conservative board-level output budget.
set_output_delay -clock $audio_master_clock -max 10.000 \
    [get_ports {AUD_BCLK AUD_DACLRCK AUD_DACDAT}]
set_output_delay -clock $audio_master_clock -min -2.000 \
    [get_ports {AUD_BCLK AUD_DACLRCK AUD_DACDAT}]
set_false_path -to [get_ports {AUD_XCK}]

# The 100 kHz open-drain control bus is sampled near the middle of each
# half-cycle, thousands of fabric cycles after codec transitions.  It is an
# explicitly asynchronous external control interface, not an audio clock.
set_false_path -from [get_ports {FPGA_I2C_SCLK FPGA_I2C_SDAT}]
set_false_path -to [get_ports {FPGA_I2C_SCLK FPGA_I2C_SDAT}]

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
