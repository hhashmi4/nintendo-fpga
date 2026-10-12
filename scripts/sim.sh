#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIM_PROFILE="${1:-full}"
if [[ "$SIM_PROFILE" != "full" && "$SIM_PROFILE" != "--fast" ]]; then
    echo "Usage: $0 [--fast]" >&2
    exit 2
fi

mkdir -p \
    build/sim \
    build/verilator/platform \
    build/verilator/ppu \
    build/verilator/ppu_phase3b \
    build/verilator/ppu_memory \
    build/verilator/ppu_phase3c \
    build/verilator/ppu_scroll \
    build/verilator/ppu_phase3d \
    build/verilator/ppu_background \
    build/verilator/ppu_phase3e \
    build/verilator/ppu_sprite_range \
    build/verilator/ppu_oam \
    build/verilator/ppu_phase3f \
    build/verilator/ppu_sprite_address \
    build/verilator/ppu_sprite_renderer \
    build/verilator/ppu_phase3g \
    build/verilator/ppu_pixel_mixer \
    build/verilator/ppu_phase3h \
    build/verilator/ppu_phase3i \
    build/verilator/nes_phase4a_bus \
    build/verilator/mapper0_phase4b \
    build/verilator/nes_phase4b_boot \
    build/verilator/nes_controller_phase4c \
    build/verilator/nes_phase4c_controller \
    build/verilator/nes_oam_dma_phase4d \
    build/verilator/nes_internal_bus_arbiter_phase4d \
    build/verilator/nes_phase4d_dma_integration \
    build/verilator/nes_phase4d_dma_nmi \
    build/verilator/nes_phase4db_playable \
    build/verilator/nes_apu_mixer_phase5h \
    build/verilator/nes_audio_phase5k \
    build/verilator/nes_diagnostic_phase5m \
    build/verilator/nes_runtime_loader_phase4fa \
    build/verilator/nes_runtime_cartridge_phase4fb \
    build/verilator/nes_runtime_image_phase4fc \
    build/verilator/nes_runtime_activation_phase4fd \
    build/verilator/nes_runtime_loader_mmio_phase4ff \
    build/verilator/nes_runtime_boot_phase4fg \
    build/verilator/nes_debug_snapshot \
    build/verilator/nes_debug_renderer \
    build/verilator/nes_developer_side_panel \
    build/verilator/nes_debug_pages \
    build/verilator/nes_phase3j \
    build/verilator/nes_phase3j_nmi \
    build/verilator/vga_timing_phase3k \
    build/verilator/vga_phase3k \
    build/verilator/nes_vga_phase3k \
    build/verilator/nes_vga_phase4db \
    build/verilator/nes_vga_phase4ec \
    build/verilator/nes_apu_phase5a \
    build/verilator/nes_apu_pulse1_phase5b \
    build/verilator/nes_apu_pulse2_phase5c \
    build/verilator/nes_apu_triangle_phase5d \
    build/verilator/nes_apu_noise_phase5e \
    build/verilator/nes_apu_dmc_phase5f \
    build/verilator/nes_apu_complete_phase5g \
    build/verilator/nes_dmc_dma_phase5f \
    build/verilator/nes_dmc_system_phase5f \
    build/verilator/nes_apu_cpu_phase5i \
    build/verilator/cpu \
    build/verilator/alu \
    build/verilator/address \
    build/verilator/cpu_phase2d \
    build/verilator/cpu_phase2e \
    build/verilator/cpu_phase2f \
    build/verilator/cpu_phase2g \
    build/verilator/cpu_phase2h \
    build/verilator/cpu_phase2i \
    build/verilator/cpu_phase2j \
    build/verilator/cpu_board_diag \
    build/verilator/video_720p_timing_phase6b \
    build/verilator/nes_720p_scaler_phase6b \
    build/verilator/nes_digital_video_phase6b \
    build/verilator/nes_framebuffer_fault_phase6b \
    build/verilator/i2c_register_master_phase6c \
    build/verilator/edid_720p_validator_phase6c \
    build/verilator/adv7513_config_engine_phase6c \
    build/verilator/hdmi_tx_controller_phase6c \
    build/verilator/hdmi_rgb_output_phase6c

PLATFORM_WAVEFORM="build/sim/platform_foundation.fst"
PPU_WAVEFORM="build/sim/ppu_timing.fst"
PPU_REFERENCE="build/sim/ppu_timing_reference.txt"
PPU_PHASE3B_WAVEFORM="build/sim/ppu_phase3b.fst"
PPU_PHASE3B_REFERENCE="build/sim/ppu_register_reference.txt"
PPU_MEMORY_WAVEFORM="build/sim/ppu_memory.fst"
PPU_MEMORY_REFERENCE="build/sim/ppu_memory_reference.txt"
PPU_PHASE3C_WAVEFORM="build/sim/ppu_phase3c.fst"
PPU_PHASE3C_REFERENCE="build/sim/ppu_phase3c_reference.txt"
PPU_SCROLL_WAVEFORM="build/sim/ppu_scroll.fst"
PPU_SCROLL_REFERENCE="build/sim/ppu_scroll_reference.txt"
PPU_PHASE3D_WAVEFORM="build/sim/ppu_phase3d.fst"
PPU_PHASE3D_REFERENCE="build/sim/ppu_phase3d_reference.txt"
PPU_BACKGROUND_WAVEFORM="build/sim/ppu_background.fst"
PPU_BACKGROUND_REFERENCE="build/sim/ppu_background_reference.txt"
PPU_PHASE3E_WAVEFORM="build/sim/ppu_phase3e.fst"
PPU_PHASE3E_REFERENCE="build/sim/ppu_phase3e_reference.txt"
PPU_PHASE3E_FETCH_REFERENCE="build/sim/ppu_phase3e_fetch_reference.txt"
PPU_PHASE3E_FETCH_RTL="build/sim/ppu_phase3e_fetch_rtl.txt"
PPU_SPRITE_RANGE_REFERENCE="build/sim/ppu_sprite_range_reference.txt"
PPU_OAM_WAVEFORM="build/sim/ppu_oam.fst"
PPU_OAM_REFERENCE="build/sim/ppu_oam_reference.txt"
PPU_PHASE3F_WAVEFORM="build/sim/ppu_phase3f.fst"
PPU_PHASE3F_REFERENCE="build/sim/ppu_phase3f_reference.txt"
PPU_SPRITE_ADDRESS_REFERENCE="build/sim/ppu_sprite_address_reference.txt"
PPU_SPRITE_RENDERER_WAVEFORM="build/sim/ppu_sprite_renderer.fst"
PPU_SPRITE_RENDERER_REFERENCE="build/sim/ppu_sprite_renderer_reference.txt"
PPU_SPRITE_RENDERER_STATS="build/sim/ppu_sprite_renderer_stats.txt"
PPU_SPRITE_FETCH_REFERENCE="build/sim/ppu_sprite_fetch_reference.txt"
PPU_SPRITE_FETCH_RTL="build/sim/ppu_sprite_fetch_rtl.txt"
PPU_PHASE3G_WAVEFORM="build/sim/ppu_phase3g.fst"
PPU_PHASE3G_OAM="build/sim/ppu_phase3g_oam.hex"
PPU_PHASE3G_CHR="build/sim/ppu_phase3g_chr.hex"
PPU_PHASE3G_PIXELS="build/sim/ppu_phase3g_pixels_reference.txt"
PPU_PHASE3G_STATS="build/sim/ppu_phase3g_frame_stats.txt"
PPU_PIXEL_MIXER_REFERENCE="build/sim/ppu_pixel_mixer_reference.txt"
PPU_PIXEL_MIXER_STATS="build/sim/ppu_pixel_mixer_stats.txt"
PPU_PHASE3H_WAVEFORM="build/sim/ppu_phase3h.fst"
PPU_PHASE3H_CIRAM="build/sim/ppu_phase3h_ciram.hex"
PPU_PHASE3H_CHR="build/sim/ppu_phase3h_chr.hex"
PPU_PHASE3H_OAM="build/sim/ppu_phase3h_oam.hex"
PPU_PHASE3H_PALETTE="build/sim/ppu_phase3h_palette.hex"
PPU_PHASE3H_PIXELS="build/sim/ppu_phase3h_pixels_reference.txt"
PPU_PHASE3H_STATS="build/sim/ppu_phase3h_frame_stats.txt"
PPU_PHASE3I_WAVEFORM="build/sim/ppu_phase3i.fst"
PPU_PHASE3I_REFERENCE="build/sim/ppu_phase3i_reference.txt"
PPU_PHASE3I_STATS="build/sim/ppu_phase3i_stats.txt"
NES_PHASE4A_BUS_WAVEFORM="build/sim/nes_phase4a_bus.fst"
NES_PHASE4A_BUS_REFERENCE="build/sim/nes_phase4a_bus_reference.txt"
MAPPER0_PHASE4B_WAVEFORM="build/sim/mapper0_phase4b.fst"
NES_PHASE4B_BOOT_WAVEFORM="build/sim/nes_phase4b_boot.fst"
NES_CONTROLLER_PHASE4C_WAVEFORM="build/sim/nes_controller_phase4c.fst"
NES_PHASE4C_CONTROLLER_WAVEFORM="build/sim/nes_phase4c_controller.fst"
NES_OAM_DMA_PHASE4D_WAVEFORM="build/sim/nes_oam_dma_phase4d.fst"
NES_INTERNAL_BUS_ARBITER_PHASE4D_WAVEFORM="build/sim/nes_internal_bus_arbiter_phase4d.fst"
NES_PHASE4D_DMA_INTEGRATION_WAVEFORM="build/sim/nes_phase4d_dma_integration.fst"
NES_PHASE4D_DMA_NMI_WAVEFORM="build/sim/nes_phase4d_dma_nmi.fst"
NES_PHASE4DB_WAVEFORM="build/sim/nes_phase4db_playable.fst"
NES_PHASE4DB_BOOT_TRACE="build/sim/phase4db_boot_trace.txt"
NES_RUNTIME_LOADER_PHASE4FA_WAVEFORM="build/sim/nes_runtime_loader_phase4fa.fst"
NES_RUNTIME_LOADER_PHASE4FA_REFERENCE="build/sim/runtime_loader_reference.txt"
NES_RUNTIME_CARTRIDGE_PHASE4FB_WAVEFORM="build/sim/nes_runtime_cartridge_phase4fb.fst"
NES_RUNTIME_CARTRIDGE_PHASE4FB_REFERENCE="build/sim/runtime_cartridge_reference.txt"
NES_RUNTIME_IMAGE_PHASE4FC_WAVEFORM="build/sim/nes_runtime_image_phase4fc.fst"
NES_RUNTIME_ACTIVATION_PHASE4FD_WAVEFORM="build/sim/nes_runtime_activation_phase4fd.fst"
NES_RUNTIME_LOADER_MMIO_PHASE4FF_WAVEFORM="build/sim/nes_runtime_loader_mmio_phase4ff.fst"
NES_RUNTIME_BOOT_PHASE4FG_WAVEFORM="build/sim/nes_runtime_boot_phase4fg.fst"
NES_RUNTIME_BOOT_PHASE4FG_FRAME="build/sim/phase4fg_game_a.hex"
NES_RUNTIME_BOOT_PHASE4FG_PPM="build/sim/phase4fg_game_a.ppm"
NES_DEBUG_SNAPSHOT_WAVEFORM="build/sim/nes_debug_snapshot.fst"
NES_DEBUG_RENDERER_WAVEFORM="build/sim/nes_debug_renderer.fst"
NES_DEBUG_RENDERER_FONT_REFERENCE="build/sim/debug_font_reference.txt"
NES_DEBUG_RENDERER_TRACE="build/sim/phase4eb_developer_pixels.txt"
NES_DEBUG_RENDERER_FRAME="build/sim/phase4eb_developer_mode.ppm"
NES_DEVELOPER_SIDE_PANEL_WAVEFORM="build/sim/nes_developer_side_panel.fst"
NES_DEVELOPER_SIDE_PANEL_TRACE="build/sim/phase4ec_combined_pixels.txt"
NES_DEVELOPER_SIDE_PANEL_FRAME="build/sim/phase4ec_combined.ppm"
NES_DEBUG_PAGES_WAVEFORM="build/sim/nes_debug_pages.fst"
NES_DEBUG_PAGES_ARTIFACT_DIR="build/sim/phase4ed_pages"
NES_PHASE3J_WAVEFORM="build/sim/nes_phase3j.fst"
VGA_PHASE3K_WAVEFORM="build/sim/vga_phase3k.fst"
VGA_PHASE3K_TRACE="build/sim/vga_phase3k_pixels.txt"
NES_VGA_PHASE3K_TRACE="build/sim/nes_vga_phase3k_pixels.txt"
NES_VGA_PHASE4DB_TRACE="build/sim/phase4db_vga_pixels.txt"
NES_VGA_PHASE4EC_TRACE="build/sim/phase4ec_playable_combined_pixels.txt"
NES_VGA_PHASE4EC_METADATA="build/sim/phase4ec_playable_snapshot.txt"
NES_VGA_PHASE4EC_FRAME="build/sim/phase4ec_playable_combined.ppm"
NES_APU_PHASE5A_WAVEFORM="build/sim/nes_apu_phase5a.fst"
NES_APU_PHASE5A_REFERENCE="build/sim/nes_apu_phase5a_reference.txt"
NES_APU_PULSE1_PHASE5B_WAVEFORM="build/sim/nes_apu_pulse1_phase5b.fst"
NES_APU_PULSE1_PHASE5B_REFERENCE="build/sim/nes_apu_pulse1_phase5b_reference.txt"
NES_APU_PULSE2_PHASE5C_WAVEFORM="build/sim/nes_apu_pulse2_phase5c.fst"
NES_APU_PULSE2_PHASE5C_REFERENCE="build/sim/nes_apu_pulse2_phase5c_reference.txt"
NES_APU_TRIANGLE_PHASE5D_WAVEFORM="build/sim/nes_apu_triangle_phase5d.fst"
NES_APU_TRIANGLE_PHASE5D_REFERENCE="build/sim/nes_apu_triangle_phase5d_reference.txt"
NES_APU_NOISE_PHASE5E_WAVEFORM="build/sim/nes_apu_noise_phase5e.fst"
NES_APU_NOISE_PHASE5E_REFERENCE="build/sim/nes_apu_noise_phase5e_reference.txt"
NES_APU_DMC_PHASE5F_WAVEFORM="build/sim/nes_apu_dmc_phase5f.fst"
NES_APU_DMC_PHASE5F_REFERENCE="build/sim/nes_apu_dmc_phase5f_reference.txt"
NES_APU_COMPLETE_PHASE5G_WAVEFORM="build/sim/nes_apu_complete_phase5g.fst"
NES_APU_COMPLETE_PHASE5G_REFERENCE="build/sim/nes_apu_complete_phase5g_reference.txt"
NES_APU_MIXER_PHASE5H_WAVEFORM="build/sim/nes_apu_mixer_phase5h.fst"
NES_APU_MIXER_PHASE5H_REFERENCE="build/sim/nes_apu_mixer_phase5h_reference.txt"
NES_DMC_DMA_PHASE5F_WAVEFORM="build/sim/nes_dmc_dma_phase5f.fst"
NES_DMC_SYSTEM_PHASE5F_WAVEFORM="build/sim/nes_dmc_system_phase5f.fst"
NES_APU_CPU_PHASE5I_WAVEFORM="build/sim/nes_apu_cpu_phase5i.fst"
NES_APU_CPU_PHASE5I_GAME_A_HEX="build/sim/phase5i_game_a.prg.hex"
NES_APU_CPU_PHASE5I_GAME_B_HEX="build/sim/phase5i_game_b.prg.hex"
NES_APU_CPU_PHASE5I_GAME_A_ROM="build/sim/phase5i_game_a.nes"
NES_APU_CPU_PHASE5I_GAME_B_ROM="build/sim/phase5i_game_b.nes"
NES_APU_CPU_PHASE5I_REFERENCE="build/sim/phase5i_rom_reference.txt"
CPU_WAVEFORM="build/sim/cpu_phase2a.fst"
ALU_WAVEFORM="build/sim/cpu_alu.fst"
ADDRESS_WAVEFORM="build/sim/cpu_address_gen.fst"
CPU_PHASE2D_WAVEFORM="build/sim/cpu_phase2d.fst"
CPU_PHASE2E_WAVEFORM="build/sim/cpu_phase2e.fst"
CPU_PHASE2F_WAVEFORM="build/sim/cpu_phase2f.fst"
CPU_PHASE2G_WAVEFORM="build/sim/cpu_phase2g.fst"
CPU_PHASE2H_WAVEFORM="build/sim/cpu_phase2h.fst"
CPU_PHASE2I_WAVEFORM="build/sim/cpu_phase2i.fst"
CPU_PHASE2J_WAVEFORM="build/sim/cpu_phase2j.fst"
CPU_BOARD_DIAG_WAVEFORM="build/sim/cpu_board_diag.fst"
SHARED_VIDEO_RESULTS="build/sim/phase6b_shared_video_rtl.txt"
HDMI_CONTROLLER_RESULTS="build/sim/phase6c_hdmi_rtl.txt"
HDMI_RGB_RESULTS="build/sim/phase6c_hdmi_rgb_rtl.txt"
rm -f \
    "$PLATFORM_WAVEFORM" \
    "$PPU_WAVEFORM" \
    "$PPU_REFERENCE" \
    "$PPU_PHASE3B_WAVEFORM" \
    "$PPU_PHASE3B_REFERENCE" \
    "$PPU_MEMORY_WAVEFORM" \
    "$PPU_MEMORY_REFERENCE" \
    "$PPU_PHASE3C_WAVEFORM" \
    "$PPU_PHASE3C_REFERENCE" \
    "$PPU_SCROLL_WAVEFORM" \
    "$PPU_SCROLL_REFERENCE" \
    "$PPU_PHASE3D_WAVEFORM" \
    "$PPU_PHASE3D_REFERENCE" \
    "$PPU_BACKGROUND_WAVEFORM" \
    "$PPU_BACKGROUND_REFERENCE" \
    "$PPU_PHASE3E_WAVEFORM" \
    "$PPU_PHASE3E_REFERENCE" \
    "$PPU_PHASE3E_FETCH_REFERENCE" \
    "$PPU_PHASE3E_FETCH_RTL" \
    "$PPU_SPRITE_RANGE_REFERENCE" \
    "$PPU_OAM_WAVEFORM" \
    "$PPU_OAM_REFERENCE" \
    "$PPU_PHASE3F_WAVEFORM" \
    "$PPU_PHASE3F_REFERENCE" \
    "$PPU_SPRITE_ADDRESS_REFERENCE" \
    "$PPU_SPRITE_RENDERER_WAVEFORM" \
    "$PPU_SPRITE_RENDERER_REFERENCE" \
    "$PPU_SPRITE_RENDERER_STATS" \
    "$PPU_SPRITE_FETCH_REFERENCE" \
    "$PPU_SPRITE_FETCH_RTL" \
    "$PPU_PHASE3G_WAVEFORM" \
    "$PPU_PHASE3G_OAM" \
    "$PPU_PHASE3G_CHR" \
    "$PPU_PHASE3G_PIXELS" \
    "$PPU_PHASE3G_STATS" \
    "$PPU_PIXEL_MIXER_REFERENCE" \
    "$PPU_PIXEL_MIXER_STATS" \
    "$PPU_PHASE3H_WAVEFORM" \
    "$PPU_PHASE3H_CIRAM" \
    "$PPU_PHASE3H_CHR" \
    "$PPU_PHASE3H_OAM" \
    "$PPU_PHASE3H_PALETTE" \
    "$PPU_PHASE3H_PIXELS" \
    "$PPU_PHASE3H_STATS" \
    "$PPU_PHASE3I_WAVEFORM" \
    "$PPU_PHASE3I_REFERENCE" \
    "$PPU_PHASE3I_STATS" \
    "$NES_PHASE4A_BUS_WAVEFORM" \
    "$NES_PHASE4A_BUS_REFERENCE" \
    "$MAPPER0_PHASE4B_WAVEFORM" \
    "$NES_PHASE4B_BOOT_WAVEFORM" \
    "$NES_CONTROLLER_PHASE4C_WAVEFORM" \
    "$NES_PHASE4C_CONTROLLER_WAVEFORM" \
    "$NES_OAM_DMA_PHASE4D_WAVEFORM" \
    "$NES_INTERNAL_BUS_ARBITER_PHASE4D_WAVEFORM" \
    "$NES_PHASE4D_DMA_INTEGRATION_WAVEFORM" \
    "$NES_PHASE4D_DMA_NMI_WAVEFORM" \
    "$NES_PHASE4DB_WAVEFORM" \
    "$NES_PHASE4DB_BOOT_TRACE" \
    "$NES_RUNTIME_LOADER_PHASE4FA_WAVEFORM" \
    "$NES_RUNTIME_LOADER_PHASE4FA_REFERENCE" \
    "$NES_RUNTIME_CARTRIDGE_PHASE4FB_WAVEFORM" \
    "$NES_RUNTIME_CARTRIDGE_PHASE4FB_REFERENCE" \
    "$NES_RUNTIME_IMAGE_PHASE4FC_WAVEFORM" \
    "$NES_RUNTIME_ACTIVATION_PHASE4FD_WAVEFORM" \
    "$NES_RUNTIME_LOADER_MMIO_PHASE4FF_WAVEFORM" \
    "$NES_RUNTIME_BOOT_PHASE4FG_WAVEFORM" \
    "$NES_RUNTIME_BOOT_PHASE4FG_FRAME" \
    "$NES_RUNTIME_BOOT_PHASE4FG_PPM" \
    "$NES_DEBUG_SNAPSHOT_WAVEFORM" \
    "$NES_DEBUG_RENDERER_WAVEFORM" \
    "$NES_DEBUG_RENDERER_FONT_REFERENCE" \
    "$NES_DEBUG_RENDERER_TRACE" \
    "$NES_DEBUG_RENDERER_FRAME" \
    "$NES_DEVELOPER_SIDE_PANEL_WAVEFORM" \
    "$NES_DEVELOPER_SIDE_PANEL_TRACE" \
    "$NES_DEVELOPER_SIDE_PANEL_FRAME" \
    "$NES_DEBUG_PAGES_WAVEFORM" \
    "$NES_PHASE3J_WAVEFORM" \
    "$VGA_PHASE3K_WAVEFORM" \
    "$VGA_PHASE3K_TRACE" \
    "$NES_VGA_PHASE3K_TRACE" \
    "$NES_VGA_PHASE4DB_TRACE" \
    "$NES_VGA_PHASE4EC_TRACE" \
    "$NES_VGA_PHASE4EC_METADATA" \
    "$NES_VGA_PHASE4EC_FRAME" \
    "$NES_APU_PHASE5A_WAVEFORM" \
    "$NES_APU_PHASE5A_REFERENCE" \
    "$NES_APU_PULSE1_PHASE5B_WAVEFORM" \
    "$NES_APU_PULSE1_PHASE5B_REFERENCE" \
    "$NES_APU_PULSE2_PHASE5C_WAVEFORM" \
    "$NES_APU_PULSE2_PHASE5C_REFERENCE" \
    "$NES_APU_TRIANGLE_PHASE5D_WAVEFORM" \
    "$NES_APU_TRIANGLE_PHASE5D_REFERENCE" \
    "$NES_APU_NOISE_PHASE5E_WAVEFORM" \
    "$NES_APU_NOISE_PHASE5E_REFERENCE" \
    "$NES_APU_DMC_PHASE5F_WAVEFORM" \
    "$NES_APU_DMC_PHASE5F_REFERENCE" \
    "$NES_APU_COMPLETE_PHASE5G_WAVEFORM" \
    "$NES_APU_COMPLETE_PHASE5G_REFERENCE" \
    "$NES_APU_MIXER_PHASE5H_WAVEFORM" \
    "$NES_APU_MIXER_PHASE5H_REFERENCE" \
    "$NES_DMC_DMA_PHASE5F_WAVEFORM" \
    "$NES_DMC_SYSTEM_PHASE5F_WAVEFORM" \
    "$NES_APU_CPU_PHASE5I_WAVEFORM" \
    "$NES_APU_CPU_PHASE5I_GAME_A_HEX" \
    "$NES_APU_CPU_PHASE5I_GAME_B_HEX" \
    "$NES_APU_CPU_PHASE5I_GAME_A_ROM" \
    "$NES_APU_CPU_PHASE5I_GAME_B_ROM" \
    "$NES_APU_CPU_PHASE5I_REFERENCE" \
    "$CPU_WAVEFORM" \
    "$ALU_WAVEFORM" \
    "$ADDRESS_WAVEFORM" \
    "$CPU_PHASE2D_WAVEFORM" \
    "$CPU_PHASE2E_WAVEFORM" \
    "$CPU_PHASE2F_WAVEFORM" \
    "$CPU_PHASE2G_WAVEFORM" \
    "$CPU_PHASE2H_WAVEFORM" \
    "$CPU_PHASE2I_WAVEFORM" \
    "$CPU_PHASE2J_WAVEFORM" \
    "$CPU_BOARD_DIAG_WAVEFORM" \
    "$SHARED_VIDEO_RESULTS" \
    "$HDMI_CONTROLLER_RESULTS" \
    "$HDMI_RGB_RESULTS"

RTL_FILES=(
    rtl/platform/platform_config_pkg.sv
    rtl/platform/platform_clock.sv
    rtl/platform/reset_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/platform/platform_core.sv
    rtl/diagnostic/platform_diagnostic.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/platform \
    --top-module platform_foundation_tb \
    -o platform_foundation_tb \
    "${RTL_FILES[@]}" \
    sim/platform_foundation_tb.sv

build/verilator/platform/platform_foundation_tb

if [[ ! -s "$PLATFORM_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PLATFORM_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_apu_phase5a_vectors.py \
    "$NES_APU_PHASE5A_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_phase5a \
    --top-module nes_apu_phase5a_tb \
    -o nes_apu_phase5a_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    sim/nes_apu_phase5a_tb.sv

build/verilator/nes_apu_phase5a/nes_apu_phase5a_tb

if [[ ! -s "$NES_APU_PHASE5A_WAVEFORM" ]]; then
    echo "ERROR: Phase 5A APU waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_pulse1_phase5b_vectors.py \
    "$NES_APU_PULSE1_PHASE5B_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_pulse1_phase5b \
    --top-module nes_apu_pulse1_phase5b_tb \
    -o nes_apu_pulse1_phase5b_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    sim/nes_apu_pulse1_phase5b_tb.sv

build/verilator/nes_apu_pulse1_phase5b/nes_apu_pulse1_phase5b_tb

if [[ ! -s "$NES_APU_PULSE1_PHASE5B_WAVEFORM" ]]; then
    echo "ERROR: Phase 5B Pulse 1 waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_pulse2_phase5c_vectors.py \
    "$NES_APU_PULSE2_PHASE5C_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_pulse2_phase5c \
    --top-module nes_apu_pulse2_phase5c_tb \
    -o nes_apu_pulse2_phase5c_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    sim/nes_apu_pulse2_phase5c_tb.sv

build/verilator/nes_apu_pulse2_phase5c/nes_apu_pulse2_phase5c_tb

if [[ ! -s "$NES_APU_PULSE2_PHASE5C_WAVEFORM" ]]; then
    echo "ERROR: Phase 5C dual-pulse waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_triangle_phase5d_vectors.py \
    "$NES_APU_TRIANGLE_PHASE5D_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_triangle_phase5d \
    --top-module nes_apu_triangle_phase5d_tb \
    -o nes_apu_triangle_phase5d_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    sim/nes_apu_triangle_phase5d_tb.sv

build/verilator/nes_apu_triangle_phase5d/nes_apu_triangle_phase5d_tb

if [[ ! -s "$NES_APU_TRIANGLE_PHASE5D_WAVEFORM" ]]; then
    echo "ERROR: Phase 5D Triangle waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_noise_phase5e_vectors.py \
    "$NES_APU_NOISE_PHASE5E_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_noise_phase5e \
    --top-module nes_apu_noise_phase5e_tb \
    -o nes_apu_noise_phase5e_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    sim/nes_apu_noise_phase5e_tb.sv

build/verilator/nes_apu_noise_phase5e/nes_apu_noise_phase5e_tb

if [[ ! -s "$NES_APU_NOISE_PHASE5E_WAVEFORM" ]]; then
    echo "ERROR: Phase 5E Noise waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_dmc_phase5f_vectors.py \
    "$NES_APU_DMC_PHASE5F_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_dmc_phase5f \
    --top-module nes_apu_dmc_phase5f_tb \
    -o nes_apu_dmc_phase5f_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_dmc.sv \
    sim/nes_apu_dmc_phase5f_tb.sv

build/verilator/nes_apu_dmc_phase5f/nes_apu_dmc_phase5f_tb

if [[ ! -s "$NES_APU_DMC_PHASE5F_WAVEFORM" ]]; then
    echo "ERROR: Phase 5F DMC waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_complete_phase5g_vectors.py \
    "$NES_APU_COMPLETE_PHASE5G_REFERENCE"

verilator --binary --timing --trace-fst --Wall -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_apu_complete_phase5g \
    --top-module nes_apu_complete_phase5g_tb \
    -o nes_apu_complete_phase5g_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    sim/nes_apu_complete_phase5g_tb.sv

build/verilator/nes_apu_complete_phase5g/nes_apu_complete_phase5g_tb

if [[ ! -s "$NES_APU_COMPLETE_PHASE5G_WAVEFORM" ]]; then
    echo "ERROR: Phase 5G complete APU waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_mixer_luts.py --check
python3 scripts/generate_apu_mixer_phase5h_vectors.py \
    "$NES_APU_MIXER_PHASE5H_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_apu_mixer_phase5h \
    --top-module nes_apu_mixer_phase5h_tb \
    -o nes_apu_mixer_phase5h_tb \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    sim/nes_apu_mixer_phase5h_tb.sv

build/verilator/nes_apu_mixer_phase5h/nes_apu_mixer_phase5h_tb

if [[ ! -s "$NES_APU_MIXER_PHASE5H_WAVEFORM" ]]; then
    echo "ERROR: Phase 5H mixer waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_runtime_loader_vectors.py \
    "$NES_RUNTIME_LOADER_PHASE4FA_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_runtime_loader_phase4fa \
    --top-module nes_runtime_loader_phase4fa_tb \
    -o nes_runtime_loader_phase4fa_tb \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    sim/nes_runtime_loader_phase4fa_tb.sv

build/verilator/nes_runtime_loader_phase4fa/nes_runtime_loader_phase4fa_tb

if [[ ! -s "$NES_RUNTIME_LOADER_PHASE4FA_WAVEFORM" ]]; then
    echo "ERROR: Phase 4F-A loader waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_runtime_cartridge_vectors.py \
    "$NES_RUNTIME_CARTRIDGE_PHASE4FB_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_runtime_cartridge_phase4fb \
    --top-module nes_runtime_cartridge_phase4fb_tb \
    -o nes_runtime_cartridge_phase4fb_tb \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    sim/nes_runtime_cartridge_phase4fb_tb.sv

build/verilator/nes_runtime_cartridge_phase4fb/nes_runtime_cartridge_phase4fb_tb

if [[ ! -s "$NES_RUNTIME_CARTRIDGE_PHASE4FB_WAVEFORM" ]]; then
    echo "ERROR: Phase 4F-B runtime-cartridge waveform is missing" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_runtime_image_phase4fc \
    --top-module nes_runtime_image_phase4fc_tb \
    -o nes_runtime_image_phase4fc_tb \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    sim/nes_runtime_image_phase4fc_tb.sv

build/verilator/nes_runtime_image_phase4fc/nes_runtime_image_phase4fc_tb

if [[ ! -s "$NES_RUNTIME_IMAGE_PHASE4FC_WAVEFORM" ]]; then
    echo "ERROR: Phase 4F-C runtime-image waveform is missing" >&2
    exit 1
fi

verilator --binary --timing --Wall -Wno-fatal \
    -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/nes_diagnostic_phase5m \
    --top-module nes_diagnostic_phase5m_tb \
    -o nes_diagnostic_phase5m_tb \
    rtl/diagnostic/nes_diagnostic_mmio_pkg.sv \
    rtl/diagnostic/nes_diagnostic_subsystem.sv \
    sim/nes_diagnostic_phase5m_tb.sv

build/verilator/nes_diagnostic_phase5m/nes_diagnostic_phase5m_tb
python3 scripts/verify_diagnostic_phase5m.py \
    build/sim/phase5m_diagnostic_rtl.txt

HDMI_TX_RTL_FILES=(
    rtl/video/hdmi_tx_pkg.sv
    rtl/video/hdmi_hpd_filter.sv
    rtl/video/i2c_register_master.sv
    rtl/video/adv7513_720p_profile.sv
    rtl/video/adv7513_config_engine.sv
    rtl/video/adv7513_edid_reader.sv
    rtl/video/edid_720p_validator.sv
    rtl/video/hdmi_tx_controller.sv
)

verilator --binary --timing --Wall -Wno-BLKSEQ --assert \
    --Mdir build/verilator/i2c_register_master_phase6c \
    --top-module i2c_register_master_tb \
    -o i2c_register_master_tb \
    rtl/video/i2c_register_master.sv \
    sim/i2c_register_master_tb.sv
build/verilator/i2c_register_master_phase6c/i2c_register_master_tb

verilator --binary --timing --Wall -Wno-BLKSEQ --assert \
    --Mdir build/verilator/edid_720p_validator_phase6c \
    --top-module edid_720p_validator_tb \
    -o edid_720p_validator_tb \
    rtl/video/edid_720p_validator.sv \
    sim/edid_720p_validator_tb.sv
build/verilator/edid_720p_validator_phase6c/edid_720p_validator_tb

verilator --binary --timing --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM --assert \
    --Mdir build/verilator/adv7513_config_engine_phase6c \
    --top-module adv7513_config_engine_tb \
    -o adv7513_config_engine_tb \
    rtl/video/hdmi_tx_pkg.sv \
    rtl/video/adv7513_720p_profile.sv \
    rtl/video/adv7513_config_engine.sv \
    sim/adv7513_config_engine_tb.sv
build/verilator/adv7513_config_engine_phase6c/adv7513_config_engine_tb

verilator --binary --timing --Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM --assert \
    --Mdir build/verilator/hdmi_tx_controller_phase6c \
    --top-module hdmi_tx_controller_tb \
    -o hdmi_tx_controller_tb \
    "${HDMI_TX_RTL_FILES[@]}" \
    sim/hdmi_tx_controller_tb.sv
build/verilator/hdmi_tx_controller_phase6c/hdmi_tx_controller_tb

verilator --binary --timing --Wall -Wno-BLKSEQ -Wno-PINCONNECTEMPTY \
    --assert \
    --Mdir build/verilator/hdmi_rgb_output_phase6c \
    --top-module hdmi_rgb_output_tb \
    -o hdmi_rgb_output_tb \
    rtl/video/video_720p_timing.sv \
    rtl/video/nes_720p_scaler.sv \
    rtl/video/nes_palette_rgb.sv \
    rtl/video/nes_720p_video.sv \
    rtl/video/hdmi_rgb_output.sv \
    sim/hdmi_rgb_output_tb.sv
build/verilator/hdmi_rgb_output_phase6c/hdmi_rgb_output_tb

python3 scripts/verify_hdmi_transmitter.py \
    "$HDMI_CONTROLLER_RESULTS" "$HDMI_RGB_RESULTS"

if [[ "$SIM_PROFILE" == "--fast" ]]; then
    echo "FAST RTL smoke passed: platform, Phase 5A-5G APU, Phase 4F-A/B/C loading, Phase 5M diagnostics, and Phase 6C HDMI"
    exit 0
fi

python3 scripts/generate_nes_phase4a_vectors.py "$NES_PHASE4A_BUS_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase4a_bus \
    --top-module nes_phase4a_bus_tb \
    -o nes_phase4a_bus_tb \
    rtl/system/nes_system_pkg.sv \
    rtl/system/nes_cpu_address_decoder.sv \
    rtl/system/nes_cpu_ram.sv \
    rtl/system/nes_cpu_bus.sv \
    sim/nes_phase4a_bus_tb.sv

build/verilator/nes_phase4a_bus/nes_phase4a_bus_tb

if [[ ! -s "$NES_PHASE4A_BUS_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_PHASE4A_BUS_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_phase4b_fixtures.py build/cartridge
python3 scripts/generate_phase4db_playable_rom.py \
    build/cartridge/phase4db_regenerated.nes
if ! cmp -s roms/phase4db_playable_nrom128.nes \
             build/cartridge/phase4db_regenerated.nes; then
    echo "ERROR: committed playable ROM differs from its project-owned source" >&2
    exit 1
fi
python3 scripts/prepare_phase4db_cartridge.py \
    roms/phase4db_playable_nrom128.nes \
    build/cartridge/phase4db_playable_nrom128

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/mapper0_phase4b \
    --top-module mapper0_phase4b_tb \
    -o mapper0_phase4b_tb \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    sim/mapper0_phase4b_tb.sv

build/verilator/mapper0_phase4b/mapper0_phase4b_tb

if [[ ! -s "$MAPPER0_PHASE4B_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $MAPPER0_PHASE4B_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_controller_phase4c \
    --top-module nes_controller_phase4c_tb \
    -o nes_controller_phase4c_tb \
    rtl/controller/controller_input_sync.sv \
    rtl/controller/nes_controller.sv \
    sim/nes_controller_phase4c_tb.sv

build/verilator/nes_controller_phase4c/nes_controller_phase4c_tb

if [[ ! -s "$NES_CONTROLLER_PHASE4C_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_CONTROLLER_PHASE4C_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_timing_vectors.py "$PPU_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu \
    --top-module ppu_timing_tb \
    -o ppu_timing_tb \
    rtl/ppu/ppu_timing.sv \
    sim/ppu_timing_tb.sv

build/verilator/ppu/ppu_timing_tb

if [[ ! -s "$PPU_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_register_vectors.py "$PPU_PHASE3B_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3b \
    --top-module ppu_phase3b_tb \
    -o ppu_phase3b_tb \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    sim/ppu_phase3b_tb.sv

build/verilator/ppu_phase3b/ppu_phase3b_tb

if [[ ! -s "$PPU_PHASE3B_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3B_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_memory_vectors.py "$PPU_MEMORY_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_memory \
    --top-module ppu_memory_tb \
    -o ppu_memory_tb \
    rtl/ppu/ppu_memory.sv \
    sim/ppu_memory_tb.sv

build/verilator/ppu_memory/ppu_memory_tb

if [[ ! -s "$PPU_MEMORY_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_MEMORY_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_phase3c_vectors.py "$PPU_PHASE3C_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3c \
    --top-module ppu_phase3c_tb \
    -o ppu_phase3c_tb \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_memory_core.sv \
    sim/ppu_phase3c_tb.sv

build/verilator/ppu_phase3c/ppu_phase3c_tb

if [[ ! -s "$PPU_PHASE3C_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3C_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_scroll_vectors.py "$PPU_SCROLL_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_scroll \
    --top-module ppu_scroll_tb \
    -o ppu_scroll_tb \
    rtl/ppu/ppu_scroll.sv \
    sim/ppu_scroll_tb.sv

build/verilator/ppu_scroll/ppu_scroll_tb

if [[ ! -s "$PPU_SCROLL_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_SCROLL_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_phase3d_vectors.py "$PPU_PHASE3D_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3d \
    --top-module ppu_phase3d_tb \
    -o ppu_phase3d_tb \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_memory_core.sv \
    sim/ppu_phase3d_tb.sv

build/verilator/ppu_phase3d/ppu_phase3d_tb

if [[ ! -s "$PPU_PHASE3D_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3D_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_background_vectors.py "$PPU_BACKGROUND_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_background \
    --top-module ppu_background_tb \
    -o ppu_background_tb \
    rtl/ppu/ppu_background.sv \
    sim/ppu_background_tb.sv

build/verilator/ppu_background/ppu_background_tb

if [[ ! -s "$PPU_BACKGROUND_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_BACKGROUND_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_phase3e_vectors.py \
    "$PPU_PHASE3E_REFERENCE" \
    "$PPU_PHASE3E_FETCH_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3e \
    --top-module ppu_phase3e_tb \
    -o ppu_phase3e_tb \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_background.sv \
    rtl/ppu/ppu_background_core.sv \
    sim/ppu_phase3e_tb.sv

build/verilator/ppu_phase3e/ppu_phase3e_tb
cmp "$PPU_PHASE3E_FETCH_REFERENCE" "$PPU_PHASE3E_FETCH_RTL"

if [[ ! -s "$PPU_PHASE3E_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3E_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_sprite_range_vectors.py \
    "$PPU_SPRITE_RANGE_REFERENCE"

verilator --binary --timing --Wall \
    --assert \
    --Mdir build/verilator/ppu_sprite_range \
    --top-module ppu_sprite_range_tb \
    -o ppu_sprite_range_tb \
    rtl/ppu/ppu_sprite_range.sv \
    sim/ppu_sprite_range_tb.sv

build/verilator/ppu_sprite_range/ppu_sprite_range_tb

python3 scripts/generate_ppu_oam_vectors.py "$PPU_OAM_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_oam \
    --top-module ppu_oam_tb \
    -o ppu_oam_tb \
    rtl/ppu/ppu_sprite_range.sv \
    rtl/ppu/ppu_oam.sv \
    sim/ppu_oam_tb.sv

build/verilator/ppu_oam/ppu_oam_tb

if [[ ! -s "$PPU_OAM_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_OAM_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_phase3f_vectors.py "$PPU_PHASE3F_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3f \
    --top-module ppu_phase3f_tb \
    -o ppu_phase3f_tb \
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
    rtl/ppu/ppu_sprite_core.sv \
    sim/ppu_phase3f_tb.sv

build/verilator/ppu_phase3f/ppu_phase3f_tb

if [[ ! -s "$PPU_PHASE3F_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3F_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_sprite_address_vectors.py \
    "$PPU_SPRITE_ADDRESS_REFERENCE"

verilator --binary --timing --Wall \
    --assert \
    --Mdir build/verilator/ppu_sprite_address \
    --top-module ppu_sprite_address_tb \
    -o ppu_sprite_address_tb \
    rtl/ppu/ppu_sprite_address.sv \
    sim/ppu_sprite_address_tb.sv

build/verilator/ppu_sprite_address/ppu_sprite_address_tb

python3 scripts/generate_ppu_sprite_renderer_vectors.py \
    "$PPU_SPRITE_RENDERER_REFERENCE" \
    "$PPU_SPRITE_FETCH_REFERENCE" \
    "$PPU_SPRITE_RENDERER_STATS"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_sprite_renderer \
    --top-module ppu_sprite_renderer_tb \
    -o ppu_sprite_renderer_tb \
    rtl/ppu/ppu_sprite_address.sv \
    rtl/ppu/ppu_sprite_renderer.sv \
    sim/ppu_sprite_renderer_tb.sv

build/verilator/ppu_sprite_renderer/ppu_sprite_renderer_tb
cmp "$PPU_SPRITE_FETCH_REFERENCE" "$PPU_SPRITE_FETCH_RTL"

if [[ ! -s "$PPU_SPRITE_RENDERER_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_SPRITE_RENDERER_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_phase3g_frame.py \
    "$PPU_PHASE3G_OAM" \
    "$PPU_PHASE3G_CHR" \
    "$PPU_PHASE3G_PIXELS" \
    "$PPU_PHASE3G_STATS"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3g \
    --top-module ppu_phase3g_tb \
    -o ppu_phase3g_tb \
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
    rtl/ppu/ppu_sprite_core.sv \
    sim/ppu_phase3g_tb.sv

build/verilator/ppu_phase3g/ppu_phase3g_tb

if [[ ! -s "$PPU_PHASE3G_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3G_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_pixel_mixer_vectors.py \
    "$PPU_PIXEL_MIXER_REFERENCE" \
    "$PPU_PIXEL_MIXER_STATS"

verilator --binary --timing --Wall \
    --assert \
    --Mdir build/verilator/ppu_pixel_mixer \
    --top-module ppu_pixel_mixer_tb \
    -o ppu_pixel_mixer_tb \
    rtl/ppu/ppu_pixel_mixer.sv \
    sim/ppu_pixel_mixer_tb.sv

build/verilator/ppu_pixel_mixer/ppu_pixel_mixer_tb

python3 scripts/generate_ppu_phase3h_frame.py \
    "$PPU_PHASE3H_CIRAM" \
    "$PPU_PHASE3H_CHR" \
    "$PPU_PHASE3H_OAM" \
    "$PPU_PHASE3H_PALETTE" \
    "$PPU_PHASE3H_PIXELS" \
    "$PPU_PHASE3H_STATS"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3h \
    --top-module ppu_phase3h_tb \
    -o ppu_phase3h_tb \
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
    rtl/ppu/ppu_sprite_core.sv \
    sim/ppu_phase3h_tb.sv

build/verilator/ppu_phase3h/ppu_phase3h_tb

if [[ ! -s "$PPU_PHASE3H_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3H_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_ppu_phase3i_vectors.py \
    "$PPU_PHASE3I_REFERENCE" \
    "$PPU_PHASE3I_STATS"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/ppu_phase3i \
    --top-module ppu_phase3i_tb \
    -o ppu_phase3i_tb \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    sim/ppu_phase3i_tb.sv

build/verilator/ppu_phase3i/ppu_phase3i_tb

if [[ ! -s "$PPU_PHASE3I_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3I_WAVEFORM" >&2
    exit 1
fi

NES_PHASE3J_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
    rtl/system/nes_system_pkg.sv
    rtl/system/nes_cpu_address_decoder.sv
    rtl/system/nes_cpu_ram.sv
    rtl/system/nes_cpu_bus.sv
    rtl/dma/nes_oam_dma.sv
    rtl/dma/nes_dmc_dma.sv
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

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_oam_dma_phase4d \
    --top-module nes_oam_dma_phase4d_tb \
    -o nes_oam_dma_phase4d_tb \
    rtl/system/nes_system_pkg.sv \
    rtl/dma/nes_oam_dma.sv \
    sim/nes_oam_dma_phase4d_tb.sv

build/verilator/nes_oam_dma_phase4d/nes_oam_dma_phase4d_tb

if [[ ! -s "$NES_OAM_DMA_PHASE4D_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_OAM_DMA_PHASE4D_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_dmc_dma_phase5f \
    --top-module nes_dmc_dma_phase5f_tb \
    -o nes_dmc_dma_phase5f_tb \
    rtl/system/nes_system_pkg.sv \
    rtl/dma/nes_dmc_dma.sv \
    sim/nes_dmc_dma_phase5f_tb.sv

build/verilator/nes_dmc_dma_phase5f/nes_dmc_dma_phase5f_tb

if [[ ! -s "$NES_DMC_DMA_PHASE5F_WAVEFORM" ]]; then
    echo "ERROR: Phase 5F DMC DMA waveform is missing" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_internal_bus_arbiter_phase4d \
    --top-module nes_internal_bus_arbiter_phase4d_tb \
    -o nes_internal_bus_arbiter_phase4d_tb \
    rtl/system/nes_system_pkg.sv \
    rtl/system/nes_cpu_address_decoder.sv \
    rtl/system/nes_internal_bus_arbiter.sv \
    sim/nes_internal_bus_arbiter_phase4d_tb.sv

build/verilator/nes_internal_bus_arbiter_phase4d/nes_internal_bus_arbiter_phase4d_tb

if [[ ! -s "$NES_INTERNAL_BUS_ARBITER_PHASE4D_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_INTERNAL_BUS_ARBITER_PHASE4D_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase4b_boot \
    --top-module nes_phase4b_boot_tb \
    -o nes_phase4b_boot_tb \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    sim/nes_phase4b_boot_tb.sv

build/verilator/nes_phase4b_boot/nes_phase4b_boot_tb

if [[ ! -s "$NES_PHASE4B_BOOT_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_PHASE4B_BOOT_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_runtime_activation_phase4fd \
    --top-module nes_runtime_activation_phase4fd_tb \
    -o nes_runtime_activation_phase4fd_tb \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    rtl/cartridge/nes_cartridge_runtime_mux.sv \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    sim/nes_runtime_activation_phase4fd_tb.sv

build/verilator/nes_runtime_activation_phase4fd/nes_runtime_activation_phase4fd_tb

if [[ ! -s "$NES_RUNTIME_ACTIVATION_PHASE4FD_WAVEFORM" ]]; then
    echo "ERROR: Phase 4F-D runtime-activation waveform is missing" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_dmc_system_phase5f \
    --top-module nes_dmc_system_phase5f_tb \
    -o nes_dmc_system_phase5f_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/controller/nes_controller.sv \
    sim/nes_dmc_system_phase5f_tb.sv

build/verilator/nes_dmc_system_phase5f/nes_dmc_system_phase5f_tb

if [[ ! -s "$NES_DMC_SYSTEM_PHASE5F_WAVEFORM" ]]; then
    echo "ERROR: Phase 5F DMC system waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_apu_cpu_phase5i_roms.py --output-dir build/sim

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_apu_cpu_phase5i \
    --top-module nes_apu_cpu_phase5i_tb \
    -o nes_apu_cpu_phase5i_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/controller/nes_controller.sv \
    sim/nes_apu_cpu_phase5i_tb.sv

build/verilator/nes_apu_cpu_phase5i/nes_apu_cpu_phase5i_tb

if [[ ! -s "$NES_APU_CPU_PHASE5I_WAVEFORM" ||
      ! -s "$NES_APU_CPU_PHASE5I_GAME_A_ROM" ||
      ! -s "$NES_APU_CPU_PHASE5I_GAME_B_ROM" ]]; then
    echo "ERROR: Phase 5I CPU/APU integration artifacts are missing" >&2
    exit 1
fi

# Phase 5J uses the real CPU/APU/cartridge path above, but deliberately keeps
# its bounded captures and playable WAV files in ignored build output.
scripts/run_apu_audio_phase5j.sh --full

verilator --binary --timing --Wall -Wno-fatal \
    -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    -Wno-PINCONNECTEMPTY --assert \
    --Mdir build/verilator/nes_audio_phase5k \
    --top-module nes_audio_phase5k_tb \
    -o nes_audio_phase5k_tb \
    rtl/audio/nes_audio_fir_coeff_pkg.sv \
    rtl/audio/nes_audio_resampler.sv \
    rtl/audio/nes_audio_conditioner.sv \
    rtl/audio/audio_async_fifo.sv \
    rtl/audio/wm8731_i2c_init.sv \
    rtl/audio/wm8731_i2s_tx.sv \
    sim/nes_audio_phase5k_tb.sv

build/verilator/nes_audio_phase5k/nes_audio_phase5k_tb

verilator --binary --timing --trace-fst --Wall \
    -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_runtime_loader_mmio_phase4ff \
    --top-module nes_runtime_loader_mmio_phase4ff_tb \
    -o nes_runtime_loader_mmio_phase4ff_tb \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader_mmio_pkg.sv \
    rtl/loader/nes_runtime_loader_mmio.sv \
    rtl/loader/nes_runtime_loader_cdc.sv \
    rtl/loader/nes_runtime_loader.sv \
    sim/nes_runtime_loader_mmio_phase4ff_tb.sv

build/verilator/nes_runtime_loader_mmio_phase4ff/nes_runtime_loader_mmio_phase4ff_tb

if [[ ! -s "$NES_RUNTIME_LOADER_MMIO_PHASE4FF_WAVEFORM" ]]; then
    echo "ERROR: Phase 4F-F MMIO/CDC waveform is missing" >&2
    exit 1
fi

python3 scripts/generate_phase4fg_runtime_boot.py build/runtime_e2e

verilator --binary --timing --trace-fst --Wall \
    -Wno-PINCONNECTEMPTY -Wno-PINMISSING -Wno-UNUSEDSIGNAL \
    -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_runtime_boot_phase4fg \
    --top-module nes_runtime_boot_phase4fg_tb \
    -o nes_runtime_boot_phase4fg_tb \
    rtl/platform/platform_config_pkg.sv \
    rtl/platform/nes_timing_gen.sv \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/controller/controller_input_sync.sv \
    rtl/controller/nes_controller.sv \
    rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader_mmio_pkg.sv \
    rtl/loader/nes_runtime_loader_mmio.sv \
    rtl/loader/nes_runtime_loader_cdc.sv \
    rtl/loader/nes_runtime_loader.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper0.sv \
    rtl/cartridge/nes_runtime_cartridge.sv \
    rtl/cartridge/nes_cartridge_runtime_mux.sv \
    sim/nes_runtime_boot_phase4fg_tb.sv

build/verilator/nes_runtime_boot_phase4fg/nes_runtime_boot_phase4fg_tb

if [[ ! -s "$NES_RUNTIME_BOOT_PHASE4FG_WAVEFORM" ||
      ! -s "$NES_RUNTIME_BOOT_PHASE4FG_FRAME" ]]; then
    echo "ERROR: Phase 4F-G runtime-boot artifacts are missing" >&2
    exit 1
fi
python3 scripts/verify_phase4fg_frame.py \
    "$NES_RUNTIME_BOOT_PHASE4FG_FRAME" \
    "$NES_RUNTIME_BOOT_PHASE4FG_PPM"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase4c_controller \
    --top-module nes_phase4c_controller_tb \
    -o nes_phase4c_controller_tb \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/controller/nes_controller.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    sim/nes_phase4c_controller_tb.sv

build/verilator/nes_phase4c_controller/nes_phase4c_controller_tb

if [[ ! -s "$NES_PHASE4C_CONTROLLER_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_PHASE4C_CONTROLLER_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase4d_dma_integration \
    --top-module nes_phase4d_dma_integration_tb \
    -o nes_phase4d_dma_integration_tb \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/controller/nes_controller.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    sim/nes_phase4d_dma_integration_tb.sv

build/verilator/nes_phase4d_dma_integration/nes_phase4d_dma_integration_tb

if [[ ! -s "$NES_PHASE4D_DMA_INTEGRATION_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_PHASE4D_DMA_INTEGRATION_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase4d_dma_nmi \
    --top-module nes_phase4d_dma_nmi_tb \
    -o nes_phase4d_dma_nmi_tb \
    rtl/cpu/cpu_pkg.sv \
    rtl/cpu/cpu_alu.sv \
    rtl/cpu/cpu_decoder.sv \
    rtl/cpu/cpu_address_gen.sv \
    rtl/cpu/cpu_core.sv \
    rtl/system/nes_system_pkg.sv \
    rtl/dma/nes_oam_dma.sv \
    sim/nes_phase4d_dma_nmi_tb.sv

build/verilator/nes_phase4d_dma_nmi/nes_phase4d_dma_nmi_tb

if [[ ! -s "$NES_PHASE4D_DMA_NMI_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_PHASE4D_DMA_NMI_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase4db_playable \
    --top-module nes_phase4db_playable_tb \
    -o nes_phase4db_playable_tb \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/nes_debug_snapshot.sv \
    rtl/debug/nes_debugger_pkg.sv \
    rtl/debug/nes_debugger.sv \
    rtl/controller/controller_input_sync.sv \
    rtl/controller/nes_controller.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    sim/nes_phase4db_playable_tb.sv

build/verilator/nes_phase4db_playable/nes_phase4db_playable_tb

if [[ ! -s "$NES_PHASE4DB_WAVEFORM" ||
      ! -s "$NES_PHASE4DB_BOOT_TRACE" ]]; then
    echo "ERROR: Phase 4D-B playable simulation artifacts are missing" >&2
    exit 1
fi
python3 scripts/verify_phase4db_frames.py build/sim

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_debug_snapshot \
    --top-module nes_debug_snapshot_tb \
    -o nes_debug_snapshot_tb \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/nes_debug_snapshot.sv \
    sim/nes_debug_snapshot_tb.sv

build/verilator/nes_debug_snapshot/nes_debug_snapshot_tb

if [[ ! -s "$NES_DEBUG_SNAPSHOT_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_DEBUG_SNAPSHOT_WAVEFORM" >&2
    exit 1
fi

python3 scripts/generate_debug_font_vectors.py \
    "$NES_DEBUG_RENDERER_FONT_REFERENCE"

verilator --binary --timing --trace-fst --Wall \
    -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_debug_renderer \
    --top-module nes_debug_renderer_tb \
    -o nes_debug_renderer_tb \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/debug_font_pkg.sv \
    rtl/debug/nes_debug_renderer.sv \
    sim/nes_debug_renderer_tb.sv

build/verilator/nes_debug_renderer/nes_debug_renderer_tb

if [[ ! -s "$NES_DEBUG_RENDERER_WAVEFORM" ||
      ! -s "$NES_DEBUG_RENDERER_TRACE" ]]; then
    echo "ERROR: Phase 4E-B renderer simulation artifacts are missing" >&2
    exit 1
fi
python3 scripts/verify_phase4eb_renderer.py \
    "$NES_DEBUG_RENDERER_TRACE" "$NES_DEBUG_RENDERER_FRAME"

verilator --binary --timing --trace-fst --Wall \
    -Wno-fatal -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_developer_side_panel \
    --top-module nes_developer_side_panel_tb \
    -o nes_developer_side_panel_tb \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/debug_font_pkg.sv \
    rtl/debug/nes_debug_panel_renderer.sv \
    rtl/video/nes_developer_compositor.sv \
    sim/nes_developer_side_panel_tb.sv

build/verilator/nes_developer_side_panel/nes_developer_side_panel_tb

if [[ ! -s "$NES_DEVELOPER_SIDE_PANEL_WAVEFORM" ||
      ! -s "$NES_DEVELOPER_SIDE_PANEL_TRACE" ]]; then
    echo "ERROR: Phase 4E-C panel/compositor simulation artifacts are missing" >&2
    exit 1
fi
python3 scripts/verify_phase4ec_compositor.py \
    "$NES_DEVELOPER_SIDE_PANEL_TRACE" "$NES_DEVELOPER_SIDE_PANEL_FRAME"

verilator --binary --timing --trace-fst --Wall \
    -Wno-fatal -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_debug_pages \
    --top-module nes_debug_pages_tb \
    -o nes_debug_pages_tb \
    rtl/debug/nes_debug_snapshot_pkg.sv \
    rtl/debug/debug_font_pkg.sv \
    rtl/debug/nes_debug_page_select.sv \
    rtl/debug/nes_debug_panel_renderer.sv \
    rtl/video/nes_developer_compositor.sv \
    sim/nes_debug_pages_tb.sv

build/verilator/nes_debug_pages/nes_debug_pages_tb

if [[ ! -s "$NES_DEBUG_PAGES_WAVEFORM" ]]; then
    echo "ERROR: Phase 4E-D page simulation waveform is missing" >&2
    exit 1
fi
python3 scripts/verify_phase4ed_pages.py \
    build/sim "$NES_DEBUG_PAGES_ARTIFACT_DIR"

verilator --binary --timing --trace-fst --Wall \
    --assert \
    --Mdir build/verilator/nes_phase3j \
    --top-module nes_phase3j_tb \
    -o nes_phase3j_tb \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    sim/nes_phase3j_tb.sv

build/verilator/nes_phase3j/nes_phase3j_tb

if [[ ! -s "$NES_PHASE3J_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $NES_PHASE3J_WAVEFORM" >&2
    exit 1
fi

verilator --binary --timing --Wall \
    --assert \
    --Mdir build/verilator/nes_phase3j_nmi \
    --top-module nes_phase3j_nmi_tb \
    -o nes_phase3j_nmi_tb \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    sim/nes_phase3j_nmi_tb.sv

build/verilator/nes_phase3j_nmi/nes_phase3j_nmi_tb

CPU_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu \
    --top-module cpu_phase2a_tb \
    -o cpu_phase2a_tb \
    "${CPU_RTL_FILES[@]}" \
    sim/cpu_phase2a_tb.sv

build/verilator/cpu/cpu_phase2a_tb

if [[ ! -s "$CPU_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_WAVEFORM" >&2
    exit 1
fi

ALU_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
)

# Suppress only shared-package reset constants unused by this standalone top.
verilator --binary --timing --trace-fst --Wall -Wno-fatal -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/alu \
    --top-module cpu_alu_tb \
    -o cpu_alu_tb \
    "${ALU_RTL_FILES[@]}" \
    sim/cpu_alu_tb.sv

build/verilator/alu/cpu_alu_tb

if [[ ! -s "$ALU_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $ALU_WAVEFORM" >&2
    exit 1
fi

ADDRESS_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_address_gen.sv
)

# Suppress only shared-package constants unused by this standalone top.
verilator --binary --timing --trace-fst --Wall -Wno-fatal -Wno-UNUSEDPARAM \
    --assert \
    --Mdir build/verilator/address \
    --top-module cpu_address_gen_tb \
    -o cpu_address_gen_tb \
    "${ADDRESS_RTL_FILES[@]}" \
    sim/cpu_address_gen_tb.sv

build/verilator/address/cpu_address_gen_tb

if [[ ! -s "$ADDRESS_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $ADDRESS_WAVEFORM" >&2
    exit 1
fi

PHASE2D_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2d \
    --top-module cpu_phase2d_tb \
    -o cpu_phase2d_tb \
    "${PHASE2D_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2d_tb.sv

build/verilator/cpu_phase2d/cpu_phase2d_tb

if [[ ! -s "$CPU_PHASE2D_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2D_WAVEFORM" >&2
    exit 1
fi

PHASE2E_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2e \
    --top-module cpu_phase2e_tb \
    -o cpu_phase2e_tb \
    "${PHASE2E_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2e_tb.sv

build/verilator/cpu_phase2e/cpu_phase2e_tb

if [[ ! -s "$CPU_PHASE2E_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2E_WAVEFORM" >&2
    exit 1
fi

PHASE2F_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2f \
    --top-module cpu_phase2f_tb \
    -o cpu_phase2f_tb \
    "${PHASE2F_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2f_tb.sv

build/verilator/cpu_phase2f/cpu_phase2f_tb

if [[ ! -s "$CPU_PHASE2F_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2F_WAVEFORM" >&2
    exit 1
fi

PHASE2G_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2g \
    --top-module cpu_phase2g_tb \
    -o cpu_phase2g_tb \
    "${PHASE2G_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2g_tb.sv

build/verilator/cpu_phase2g/cpu_phase2g_tb

if [[ ! -s "$CPU_PHASE2G_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2G_WAVEFORM" >&2
    exit 1
fi

PHASE2H_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2h \
    --top-module cpu_phase2h_tb \
    -o cpu_phase2h_tb \
    "${PHASE2H_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2h_tb.sv

build/verilator/cpu_phase2h/cpu_phase2h_tb

if [[ ! -s "$CPU_PHASE2H_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2H_WAVEFORM" >&2
    exit 1
fi

PHASE2I_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2i \
    --top-module cpu_phase2i_tb \
    -o cpu_phase2i_tb \
    "${PHASE2I_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2i_tb.sv

build/verilator/cpu_phase2i/cpu_phase2i_tb

if [[ ! -s "$CPU_PHASE2I_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2I_WAVEFORM" >&2
    exit 1
fi

PHASE2J_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --assert \
    --Mdir build/verilator/cpu_phase2j \
    --top-module cpu_phase2j_tb \
    -o cpu_phase2j_tb \
    "${PHASE2J_RTL_FILES[@]}" \
    sim/cpu_test_memory.sv \
    sim/cpu_phase2j_tb.sv

build/verilator/cpu_phase2j/cpu_phase2j_tb

if [[ ! -s "$CPU_PHASE2J_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_PHASE2J_WAVEFORM" >&2
    exit 1
fi

CPU_BOARD_DIAG_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
    rtl/diagnostic/cpu_board_diag_pkg.sv
    rtl/diagnostic/cpu_board_diag_memory.sv
    rtl/diagnostic/cpu_board_diag.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --assert -Irtl/diagnostic \
    --Mdir build/verilator/cpu_board_diag \
    --top-module cpu_board_diag_tb \
    -o cpu_board_diag_tb \
    "${CPU_BOARD_DIAG_RTL_FILES[@]}" \
    sim/cpu_board_diag_tb.sv

build/verilator/cpu_board_diag/cpu_board_diag_tb

if [[ ! -s "$CPU_BOARD_DIAG_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $CPU_BOARD_DIAG_WAVEFORM" >&2
    exit 1
fi

SHARED_VIDEO_RTL_FILES=(
    rtl/video/video_720p_timing.sv
    rtl/video/nes_720p_scaler.sv
    rtl/video/nes_palette_rgb.sv
    rtl/video/nes_framebuffer.sv
    rtl/video/nes_720p_video.sv
    rtl/video/nes_digital_video_pipeline.sv
)

verilator --binary --timing --Wall -Wno-BLKSEQ --assert \
    --Mdir build/verilator/video_720p_timing_phase6b \
    --top-module video_720p_timing_tb \
    -o video_720p_timing_tb \
    rtl/video/video_720p_timing.sv \
    sim/video_720p_timing_tb.sv

build/verilator/video_720p_timing_phase6b/video_720p_timing_tb

verilator --binary --timing --Wall --assert \
    --Mdir build/verilator/nes_720p_scaler_phase6b \
    --top-module nes_720p_scaler_tb \
    -o nes_720p_scaler_tb \
    rtl/video/nes_720p_scaler.sv \
    sim/nes_720p_scaler_tb.sv

build/verilator/nes_720p_scaler_phase6b/nes_720p_scaler_tb

verilator --binary --timing --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
    --assert \
    --Mdir build/verilator/nes_digital_video_phase6b \
    --top-module nes_digital_video_pipeline_tb \
    -o nes_digital_video_pipeline_tb \
    "${SHARED_VIDEO_RTL_FILES[@]}" \
    sim/nes_digital_video_pipeline_tb.sv

build/verilator/nes_digital_video_phase6b/nes_digital_video_pipeline_tb

# Assertions intentionally remain disabled in this one target so directed
# malformed write coordinates can verify the synthesizable sticky fault flags.
verilator --binary --timing --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
    --Mdir build/verilator/nes_framebuffer_fault_phase6b \
    --top-module nes_framebuffer_fault_tb \
    -o nes_framebuffer_fault_tb \
    rtl/video/nes_framebuffer.sv \
    sim/nes_framebuffer_fault_tb.sv

build/verilator/nes_framebuffer_fault_phase6b/nes_framebuffer_fault_tb
python3 scripts/verify_shared_video.py "$SHARED_VIDEO_RESULTS"

VIDEO_PHASE3K_RTL_FILES=(
    rtl/video/vga_timing.sv
    rtl/video/vga_nes_scaler.sv
    rtl/video/nes_palette_rgb.sv
    rtl/video/nes_framebuffer.sv
    rtl/video/nes_vga_video.sv
)

verilator --binary --timing --Wall --assert \
    --Mdir build/verilator/vga_timing_phase3k \
    --top-module vga_timing_phase3k_tb \
    -o vga_timing_phase3k_tb \
    rtl/video/vga_timing.sv \
    sim/vga_timing_phase3k_tb.sv

build/verilator/vga_timing_phase3k/vga_timing_phase3k_tb

verilator --binary --timing --trace-fst --Wall --assert \
    --Mdir build/verilator/vga_phase3k \
    --top-module vga_phase3k_tb \
    -o vga_phase3k_tb \
    "${VIDEO_PHASE3K_RTL_FILES[@]}" \
    sim/vga_phase3k_tb.sv

build/verilator/vga_phase3k/vga_phase3k_tb

if [[ ! -s "$VGA_PHASE3K_WAVEFORM" || ! -s "$VGA_PHASE3K_TRACE" ]]; then
    echo "ERROR: Phase 3K static VGA simulation artifacts are missing" >&2
    exit 1
fi
python3 scripts/verify_vga_trace.py "$VGA_PHASE3K_TRACE"

verilator --binary --timing --Wall -Wno-fatal \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
    --assert \
    --Mdir build/verilator/nes_vga_phase3k \
    --top-module nes_vga_phase3k_tb \
    -o nes_vga_phase3k_tb \
    rtl/platform/platform_config_pkg.sv \
    rtl/platform/nes_timing_gen.sv \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/diagnostic/nes_vga_diag_memory.sv \
    "${VIDEO_PHASE3K_RTL_FILES[@]}" \
    sim/nes_vga_phase3k_tb.sv

build/verilator/nes_vga_phase3k/nes_vga_phase3k_tb

if [[ ! -s "$NES_VGA_PHASE3K_TRACE" ]]; then
    echo "ERROR: Phase 3K integrated NES/VGA trace is missing" >&2
    exit 1
fi
python3 scripts/verify_nes_vga_trace.py "$NES_VGA_PHASE3K_TRACE"

verilator --binary --timing --Wall -Wno-fatal \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
    --assert \
    --Mdir build/verilator/nes_vga_phase4db \
    --top-module nes_vga_phase4db_tb \
    -o nes_vga_phase4db_tb \
    rtl/platform/platform_config_pkg.sv \
    rtl/platform/nes_timing_gen.sv \
    "${NES_PHASE3J_RTL_FILES[@]}" \
    rtl/controller/controller_input_sync.sv \
    rtl/controller/nes_controller.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    "${VIDEO_PHASE3K_RTL_FILES[@]}" \
    sim/nes_vga_phase4db_tb.sv

build/verilator/nes_vga_phase4db/nes_vga_phase4db_tb

if [[ ! -s "$NES_VGA_PHASE4DB_TRACE" ]]; then
    echo "ERROR: Phase 4D-B playable NES/VGA trace is missing" >&2
    exit 1
fi
python3 scripts/verify_nes_vga_trace.py "$NES_VGA_PHASE4DB_TRACE"

PHASE4EC_TOP_RTL_FILES=(
    rtl/apu/nes_apu_pkg.sv
    rtl/apu/nes_apu_pulse.sv
    rtl/apu/nes_apu_triangle.sv
    rtl/apu/nes_apu_noise.sv
    rtl/apu/nes_apu_dmc.sv
    rtl/apu/nes_apu_mixer_lut_pkg.sv
    rtl/apu/nes_apu_mixer.sv
    rtl/apu/nes_apu.sv
    rtl/platform/platform_config_pkg.sv
    rtl/platform/reset_sync.sv
    rtl/platform/level_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/debug/nes_debug_snapshot_pkg.sv
    rtl/debug/nes_debug_snapshot.sv
    rtl/debug/nes_debug_page_select.sv
    rtl/debug/debug_font_pkg.sv
    rtl/debug/nes_debug_panel_renderer.sv
    "${NES_PHASE3J_RTL_FILES[@]}"
    rtl/controller/controller_input_sync.sv
    rtl/controller/nes_controller.sv
    rtl/loader/nes_runtime_loader_pkg.sv
    rtl/loader/nes_runtime_loader_mmio_pkg.sv
    rtl/loader/nes_runtime_loader_mmio.sv
    rtl/loader/nes_runtime_loader_cdc.sv
    rtl/loader/nes_runtime_loader.sv
    rtl/cartridge/nes_mapper0.sv
    rtl/cartridge/nes_cartridge.sv
    rtl/cartridge/nes_runtime_cartridge_storage.sv
    rtl/cartridge/nes_runtime_mapper0.sv
    rtl/cartridge/nes_runtime_cartridge.sv
    rtl/cartridge/nes_cartridge_runtime_mux.sv
    rtl/diagnostic/hex7seg.sv
    rtl/diagnostic/nes_diagnostic_mmio_pkg.sv
    rtl/diagnostic/nes_diagnostic_subsystem.sv
    "${VIDEO_PHASE3K_RTL_FILES[@]}"
    rtl/video/nes_developer_compositor.sv
    rtl/video/video_pll.sv
    rtl/debug/nes_debugger_pkg.sv
    rtl/debug/nes_debug_command_cdc.sv
    rtl/debug/nes_debugger.sv
    rtl/audio/nes_audio_fir_coeff_pkg.sv
    rtl/audio/nes_audio_resampler.sv
    rtl/audio/nes_audio_conditioner.sv
    rtl/audio/audio_async_fifo.sv
    rtl/audio/wm8731_i2c_init.sv
    rtl/audio/wm8731_i2s_tx.sv
    rtl/audio/audio_pll.sv
    rtl/audio/nes_audio_output.sv
    rtl/de1_soc_nes_vga_top.sv
)

verilator --binary --timing --Wall -Wno-fatal \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-BLKSEQ \
    --assert \
    --Mdir build/verilator/nes_vga_phase4ec \
    --top-module nes_vga_phase4ec_tb \
    -o nes_vga_phase4ec_tb \
    "${PHASE4EC_TOP_RTL_FILES[@]}" \
    sim/nes_vga_phase4ec_tb.sv

build/verilator/nes_vga_phase4ec/nes_vga_phase4ec_tb

if [[ ! -s "$NES_VGA_PHASE4EC_TRACE" ||
      ! -s "$NES_VGA_PHASE4EC_METADATA" ]]; then
    echo "ERROR: Phase 4E-C playable combined-frame artifacts are missing" >&2
    exit 1
fi
python3 scripts/verify_phase4ec_playable_frame.py \
    "$NES_VGA_PHASE4EC_TRACE" \
    "$NES_VGA_PHASE4EC_METADATA" \
    "$NES_VGA_PHASE4EC_FRAME"

echo "Platform waveform: $ROOT_DIR/$PLATFORM_WAVEFORM"
echo "PPU timing waveform: $ROOT_DIR/$PPU_WAVEFORM"
echo "PPU Phase 3B waveform: $ROOT_DIR/$PPU_PHASE3B_WAVEFORM"
echo "PPU memory waveform: $ROOT_DIR/$PPU_MEMORY_WAVEFORM"
echo "PPU Phase 3C waveform: $ROOT_DIR/$PPU_PHASE3C_WAVEFORM"
echo "PPU scroll waveform: $ROOT_DIR/$PPU_SCROLL_WAVEFORM"
echo "PPU Phase 3D waveform: $ROOT_DIR/$PPU_PHASE3D_WAVEFORM"
echo "PPU background waveform: $ROOT_DIR/$PPU_BACKGROUND_WAVEFORM"
echo "PPU Phase 3E waveform: $ROOT_DIR/$PPU_PHASE3E_WAVEFORM"
echo "PPU OAM waveform: $ROOT_DIR/$PPU_OAM_WAVEFORM"
echo "PPU Phase 3F waveform: $ROOT_DIR/$PPU_PHASE3F_WAVEFORM"
echo "PPU sprite renderer waveform: $ROOT_DIR/$PPU_SPRITE_RENDERER_WAVEFORM"
echo "PPU Phase 3G waveform: $ROOT_DIR/$PPU_PHASE3G_WAVEFORM"
echo "PPU Phase 3H waveform: $ROOT_DIR/$PPU_PHASE3H_WAVEFORM"
echo "PPU Phase 3I waveform: $ROOT_DIR/$PPU_PHASE3I_WAVEFORM"
echo "NES Phase 4A bus waveform: $ROOT_DIR/$NES_PHASE4A_BUS_WAVEFORM"
echo "Mapper 0 Phase 4B waveform: $ROOT_DIR/$MAPPER0_PHASE4B_WAVEFORM"
echo "NES Phase 4B boot waveform: $ROOT_DIR/$NES_PHASE4B_BOOT_WAVEFORM"
echo "NES controller Phase 4C waveform: $ROOT_DIR/$NES_CONTROLLER_PHASE4C_WAVEFORM"
echo "NES Phase 4C integrated controller waveform: $ROOT_DIR/$NES_PHASE4C_CONTROLLER_WAVEFORM"
echo "NES standalone OAM DMA Phase 4D-A waveform: $ROOT_DIR/$NES_OAM_DMA_PHASE4D_WAVEFORM"
echo "NES internal bus arbiter Phase 4D-A waveform: $ROOT_DIR/$NES_INTERNAL_BUS_ARBITER_PHASE4D_WAVEFORM"
echo "NES integrated DMA Phase 4D-A waveform: $ROOT_DIR/$NES_PHASE4D_DMA_INTEGRATION_WAVEFORM"
echo "NES DMA/NMI Phase 4D-A waveform: $ROOT_DIR/$NES_PHASE4D_DMA_NMI_WAVEFORM"
echo "NES playable Phase 4D-B waveform: $ROOT_DIR/$NES_PHASE4DB_WAVEFORM"
echo "NES playable Phase 4D-B boot trace: $ROOT_DIR/$NES_PHASE4DB_BOOT_TRACE"
echo "NES runtime loader Phase 4F-A waveform: $ROOT_DIR/$NES_RUNTIME_LOADER_PHASE4FA_WAVEFORM"
echo "NES runtime cartridge Phase 4F-B waveform: $ROOT_DIR/$NES_RUNTIME_CARTRIDGE_PHASE4FB_WAVEFORM"
echo "NES runtime image Phase 4F-C waveform: $ROOT_DIR/$NES_RUNTIME_IMAGE_PHASE4FC_WAVEFORM"
echo "NES runtime activation Phase 4F-D waveform: $ROOT_DIR/$NES_RUNTIME_ACTIVATION_PHASE4FD_WAVEFORM"
echo "NES runtime loader MMIO Phase 4F-F waveform: $ROOT_DIR/$NES_RUNTIME_LOADER_MMIO_PHASE4FF_WAVEFORM"
echo "NES runtime boot Phase 4F-G waveform: $ROOT_DIR/$NES_RUNTIME_BOOT_PHASE4FG_WAVEFORM"
echo "NES runtime boot Phase 4F-G frame: $ROOT_DIR/$NES_RUNTIME_BOOT_PHASE4FG_PPM"
echo "NES debug snapshot Phase 4E-A waveform: $ROOT_DIR/$NES_DEBUG_SNAPSHOT_WAVEFORM"
echo "NES debug renderer Phase 4E-B waveform: $ROOT_DIR/$NES_DEBUG_RENDERER_WAVEFORM"
echo "NES debug renderer Phase 4E-B frame: $ROOT_DIR/$NES_DEBUG_RENDERER_FRAME"
echo "NES Developer side-panel Phase 4E-C waveform: $ROOT_DIR/$NES_DEVELOPER_SIDE_PANEL_WAVEFORM"
echo "NES Developer side-panel Phase 4E-C frame: $ROOT_DIR/$NES_DEVELOPER_SIDE_PANEL_FRAME"
echo "NES Developer pages Phase 4E-D waveform: $ROOT_DIR/$NES_DEBUG_PAGES_WAVEFORM"
echo "NES Developer pages Phase 4E-D frames: $ROOT_DIR/$NES_DEBUG_PAGES_ARTIFACT_DIR"
echo "NES Phase 3J waveform: $ROOT_DIR/$NES_PHASE3J_WAVEFORM"
echo "VGA Phase 3K waveform: $ROOT_DIR/$VGA_PHASE3K_WAVEFORM"
echo "VGA Phase 3K static trace: $ROOT_DIR/$VGA_PHASE3K_TRACE"
echo "Phase 6B shared video RTL/model results: $ROOT_DIR/$SHARED_VIDEO_RESULTS"
echo "Phase 6C HDMI controller RTL/model results: $ROOT_DIR/$HDMI_CONTROLLER_RESULTS"
echo "Phase 6C HDMI RGB RTL/model results: $ROOT_DIR/$HDMI_RGB_RESULTS"
echo "NES/VGA Phase 3K trace: $ROOT_DIR/$NES_VGA_PHASE3K_TRACE"
echo "NES/VGA playable Phase 4D-B trace: $ROOT_DIR/$NES_VGA_PHASE4DB_TRACE"
echo "NES/VGA playable Phase 4E-C frame: $ROOT_DIR/$NES_VGA_PHASE4EC_FRAME"
echo "NES APU Phase 5A waveform: $ROOT_DIR/$NES_APU_PHASE5A_WAVEFORM"
echo "NES APU Pulse 1 Phase 5B waveform: $ROOT_DIR/$NES_APU_PULSE1_PHASE5B_WAVEFORM"
echo "NES APU Pulse 2 Phase 5C waveform: $ROOT_DIR/$NES_APU_PULSE2_PHASE5C_WAVEFORM"
echo "NES APU Triangle Phase 5D waveform: $ROOT_DIR/$NES_APU_TRIANGLE_PHASE5D_WAVEFORM"
echo "NES APU Noise Phase 5E waveform: $ROOT_DIR/$NES_APU_NOISE_PHASE5E_WAVEFORM"
echo "NES APU DMC Phase 5F waveform: $ROOT_DIR/$NES_APU_DMC_PHASE5F_WAVEFORM"
echo "NES complete APU Phase 5G waveform: $ROOT_DIR/$NES_APU_COMPLETE_PHASE5G_WAVEFORM"
echo "NES nonlinear mixer Phase 5H waveform: $ROOT_DIR/$NES_APU_MIXER_PHASE5H_WAVEFORM"
echo "NES DMC DMA Phase 5F waveform: $ROOT_DIR/$NES_DMC_DMA_PHASE5F_WAVEFORM"
echo "NES DMC system Phase 5F waveform: $ROOT_DIR/$NES_DMC_SYSTEM_PHASE5F_WAVEFORM"
echo "NES CPU/APU Phase 5I waveform: $ROOT_DIR/$NES_APU_CPU_PHASE5I_WAVEFORM"
echo "NES CPU/APU Phase 5I ROMs: $ROOT_DIR/$NES_APU_CPU_PHASE5I_GAME_A_ROM $ROOT_DIR/$NES_APU_CPU_PHASE5I_GAME_B_ROM"
echo "NES APU Phase 5J metrics: $ROOT_DIR/build/audio/phase5j_metrics.json"
echo "NES APU Phase 5J original demo WAV: $ROOT_DIR/build/audio/phase5j_melody.wav"
echo "NES real-time audio Phase 5K: directed and long-run checks passed"
echo "NES hardware diagnostics Phase 5M: MMIO, counters, faults, trace, and CDC passed"
echo "CPU waveform: $ROOT_DIR/$CPU_WAVEFORM"
echo "ALU waveform: $ROOT_DIR/$ALU_WAVEFORM"
echo "Address waveform: $ROOT_DIR/$ADDRESS_WAVEFORM"
echo "Phase 2D waveform: $ROOT_DIR/$CPU_PHASE2D_WAVEFORM"
echo "Phase 2E waveform: $ROOT_DIR/$CPU_PHASE2E_WAVEFORM"
echo "Phase 2F waveform: $ROOT_DIR/$CPU_PHASE2F_WAVEFORM"
echo "Phase 2G waveform: $ROOT_DIR/$CPU_PHASE2G_WAVEFORM"
echo "Phase 2H waveform: $ROOT_DIR/$CPU_PHASE2H_WAVEFORM"
echo "Phase 2I waveform: $ROOT_DIR/$CPU_PHASE2I_WAVEFORM"
echo "Phase 2J waveform: $ROOT_DIR/$CPU_PHASE2J_WAVEFORM"
echo "Phase 2K board diagnostic waveform: $ROOT_DIR/$CPU_BOARD_DIAG_WAVEFORM"
