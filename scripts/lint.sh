#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PLATFORM_RTL_FILES=(
    rtl/platform/platform_config_pkg.sv
    rtl/platform/platform_clock.sv
    rtl/platform/reset_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/platform/platform_core.sv
    rtl/diagnostic/platform_diagnostic.sv
    rtl/de1_soc_top.sv
)

verilator --lint-only --Wall -Wno-fatal \
    --top-module de1_soc_top \
    "${PLATFORM_RTL_FILES[@]}"

verilator --lint-only --Wall \
    --top-module ppu_timing \
    rtl/ppu/ppu_timing.sv

verilator --lint-only --Wall \
    --top-module ppu_scroll \
    rtl/ppu/ppu_scroll.sv

verilator --lint-only --Wall \
    --top-module ppu_background \
    rtl/ppu/ppu_background.sv

verilator --lint-only --Wall \
    --top-module ppu_core \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv

verilator --lint-only --Wall \
    --top-module ppu_memory_core \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_memory_core.sv

verilator --lint-only --Wall \
    --top-module ppu_background_core \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_background.sv \
    rtl/ppu/ppu_background_core.sv

verilator --lint-only --Wall \
    --top-module ppu_oam \
    rtl/ppu/ppu_sprite_range.sv \
    rtl/ppu/ppu_oam.sv

verilator --lint-only --Wall \
    --top-module ppu_sprite_address \
    rtl/ppu/ppu_sprite_address.sv

verilator --lint-only --Wall \
    --top-module ppu_sprite_renderer \
    rtl/ppu/ppu_sprite_address.sv \
    rtl/ppu/ppu_sprite_renderer.sv

verilator --lint-only --Wall \
    --top-module ppu_pixel_mixer \
    rtl/ppu/ppu_pixel_mixer.sv

verilator --lint-only --Wall \
    --top-module ppu_sprite_core \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_background.sv \
    rtl/ppu/ppu_background_core.sv \
    rtl/ppu/ppu_sprite_range.sv \
    rtl/ppu/ppu_oam.sv \
    rtl/ppu/ppu_sprite_address.sv \
    rtl/ppu/ppu_sprite_renderer.sv \
    rtl/ppu/ppu_pixel_mixer.sv \
    rtl/ppu/ppu_sprite_core.sv

CPU_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

SYSTEM_BUS_RTL_FILES=(
    rtl/system/nes_system_pkg.sv
    rtl/system/nes_cpu_address_decoder.sv
    rtl/system/nes_cpu_bus.sv
)

APU_RTL_FILES=(
    rtl/apu/nes_apu_pkg.sv
    rtl/apu/nes_apu.sv
)

# Several package constants intentionally reserve stable names and bit
# positions for later Phase 5 channel modules.
verilator --lint-only --Wall -Wno-UNUSEDPARAM \
    --top-module nes_apu \
    "${APU_RTL_FILES[@]}"

verilator --lint-only --Wall \
    --top-module nes_cpu_bus \
    "${SYSTEM_BUS_RTL_FILES[@]}"

verilator --lint-only --Wall \
    --top-module nes_cpu_ram \
    rtl/system/nes_cpu_ram.sv

verilator --lint-only --Wall \
    --top-module nes_oam_dma \
    rtl/system/nes_system_pkg.sv \
    rtl/dma/nes_oam_dma.sv

verilator --lint-only --Wall \
    --top-module nes_internal_bus_arbiter \
    rtl/system/nes_system_pkg.sv \
    rtl/system/nes_cpu_address_decoder.sv \
    rtl/system/nes_internal_bus_arbiter.sv

CONTROLLER_RTL_FILES=(
    rtl/controller/controller_input_sync.sv
    rtl/controller/nes_controller.sv
)

verilator --lint-only --Wall \
    --top-module nes_controller \
    rtl/controller/nes_controller.sv

verilator --lint-only --Wall \
    --top-module controller_input_sync \
    rtl/controller/controller_input_sync.sv

verilator --lint-only --Wall -Wno-fatal \
    --top-module cpu_core \
    "${CPU_RTL_FILES[@]}"

NES_RTL_FILES=(
    "${CPU_RTL_FILES[@]}"
    "${SYSTEM_BUS_RTL_FILES[@]}"
    rtl/system/nes_cpu_ram.sv
    rtl/dma/nes_oam_dma.sv
    rtl/system/nes_internal_bus_arbiter.sv
    rtl/ppu/ppu_timing.sv
    rtl/ppu/ppu_scroll.sv
    rtl/ppu/ppu_registers.sv
    rtl/ppu/ppu_core.sv
    rtl/ppu/ppu_memory.sv
    rtl/ppu/ppu_background.sv
    rtl/ppu/ppu_background_core.sv
    rtl/ppu/ppu_sprite_range.sv
    rtl/ppu/ppu_oam.sv
    rtl/ppu/ppu_sprite_address.sv
    rtl/ppu/ppu_sprite_renderer.sv
    rtl/ppu/ppu_pixel_mixer.sv
    rtl/ppu/ppu_sprite_core.sv
    rtl/nes_core.sv
)

verilator --lint-only --Wall \
    --top-module nes_core \
    "${NES_RTL_FILES[@]}"

CARTRIDGE_RTL_FILES=(
    rtl/cartridge/nes_mapper0.sv
    rtl/cartridge/nes_cartridge.sv
)

verilator --lint-only --Wall \
    --top-module nes_cartridge \
    "${CARTRIDGE_RTL_FILES[@]}"

verilator --lint-only --Wall \
    --top-module nes_runtime_loader \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv

verilator --lint-only --Wall -Wno-UNUSEDPARAM \
    --top-module nes_runtime_loader_mmio \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader_mmio_pkg.sv \
    rtl/loader/nes_runtime_loader_mmio.sv

verilator --lint-only --Wall -Wno-UNUSEDPARAM \
    --top-module nes_runtime_loader_cdc \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader_cdc.sv

verilator --lint-only --Wall \
    --top-module nes_runtime_cartridge \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv

verilator --lint-only --Wall \
    --top-module nes_cartridge_runtime_mux \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    "${CARTRIDGE_RTL_FILES[@]}" \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    rtl/cartridge/nes_cartridge_runtime_mux.sv

verilator --lint-only --Wall \
    --top-module nes_debug_snapshot \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/nes_debug_snapshot.sv

verilator --lint-only --Wall \
    --top-module nes_debug_command_cdc \
    rtl/debug/nes_debug_command_cdc.sv

verilator --lint-only --Wall \
    --top-module nes_debug_page_select \
    rtl/debug/nes_debug_page_select.sv

verilator --lint-only --Wall -Wno-UNUSEDPARAM \
    --top-module nes_debug_renderer \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/debug_font_pkg.sv \
    rtl/debug/nes_debug_renderer.sv

ALU_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
)

# The standalone ALU top does not consume Phase 2A reset constants from the
# shared package; cpu_core's separate lint target checks their real consumer.
verilator --lint-only --Wall -Wno-fatal -Wno-UNUSEDPARAM \
    --top-module cpu_alu \
    "${ALU_RTL_FILES[@]}"

ADDRESS_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_address_gen.sv
)

# The standalone address top also leaves earlier-phase package constants
# unused; their real consumers remain covered by the other lint targets.
verilator --lint-only --Wall -Wno-fatal -Wno-UNUSEDPARAM \
    --top-module cpu_address_gen \
    "${ADDRESS_RTL_FILES[@]}"

CPU_BOARD_DIAG_RTL_FILES=(
    rtl/platform/platform_config_pkg.sv
    rtl/platform/platform_clock.sv
    rtl/platform/reset_sync.sv
    rtl/platform/level_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
    rtl/diagnostic/cpu_board_diag_pkg.sv
    rtl/diagnostic/cpu_board_diag_memory.sv
    rtl/diagnostic/cpu_board_diag.sv
    rtl/diagnostic/hex7seg.sv
    rtl/cpu_board_diag_top.sv
)

# The diagnostic top intentionally leaves internal trace-only ports open, and
# the shared CPU package contains constants unused by some hierarchy leaves.
verilator --lint-only --Wall -Wno-fatal \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    -Irtl/diagnostic \
    --top-module cpu_board_diag_top \
    "${CPU_BOARD_DIAG_RTL_FILES[@]}"

PHASE3K_RTL_FILES=(
    "${APU_RTL_FILES[@]}"
    rtl/debug/nes_debug_snapshot_pkg.sv
    rtl/debug/nes_debug_snapshot.sv
    rtl/debug/nes_debug_page_select.sv
    rtl/debug/debug_font_pkg.sv
    rtl/debug/nes_debug_renderer.sv
    rtl/debug/nes_debug_panel_renderer.sv
    rtl/platform/platform_config_pkg.sv
    rtl/platform/reset_sync.sv
    rtl/platform/level_sync.sv
    rtl/platform/nes_timing_gen.sv
    "${NES_RTL_FILES[@]}"
    rtl/loader/nes_runtime_loader_pkg.sv
    rtl/loader/nes_runtime_loader_mmio_pkg.sv
    rtl/loader/nes_runtime_loader_mmio.sv
    rtl/loader/nes_runtime_loader_cdc.sv
    rtl/loader/nes_runtime_loader.sv
    "${CARTRIDGE_RTL_FILES[@]}"
    rtl/cartridge/nes_runtime_cartridge_storage.sv
    rtl/cartridge/nes_runtime_mapper0.sv
    rtl/cartridge/nes_runtime_cartridge.sv
    rtl/cartridge/nes_cartridge_runtime_mux.sv
    "${CONTROLLER_RTL_FILES[@]}"
    rtl/diagnostic/hex7seg.sv
    rtl/video/vga_timing.sv
    rtl/video/vga_nes_scaler.sv
    rtl/video/nes_palette_rgb.sv
    rtl/video/nes_framebuffer.sv
    rtl/video/nes_vga_video.sv
    rtl/video/nes_developer_compositor.sv
    rtl/video/video_pll.sv
    rtl/debug/nes_debugger_pkg.sv
    rtl/debug/nes_debug_command_cdc.sv
    rtl/debug/nes_debugger.sv
    rtl/de1_soc_nes_vga_top.sv
)

# The board top deliberately exposes only physical status, leaving the rich
# NES debug interface internal. The PLL uses a behavioral model in Verilator.
verilator --lint-only --Wall -Wno-fatal \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --top-module de1_soc_nes_vga_top \
    "${PHASE3K_RTL_FILES[@]}"
