#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
    build/verilator/nes_phase3j \
    build/verilator/nes_phase3j_nmi \
    build/verilator/vga_timing_phase3k \
    build/verilator/vga_phase3k \
    build/verilator/nes_vga_phase3k \
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
    build/verilator/cpu_board_diag

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
NES_PHASE3J_WAVEFORM="build/sim/nes_phase3j.fst"
VGA_PHASE3K_WAVEFORM="build/sim/vga_phase3k.fst"
VGA_PHASE3K_TRACE="build/sim/vga_phase3k_pixels.txt"
NES_VGA_PHASE3K_TRACE="build/sim/nes_vga_phase3k_pixels.txt"
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
    "$NES_PHASE3J_WAVEFORM" \
    "$VGA_PHASE3K_WAVEFORM" \
    "$VGA_PHASE3K_TRACE" \
    "$NES_VGA_PHASE3K_TRACE" \
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
    "$CPU_BOARD_DIAG_WAVEFORM"

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
echo "NES Phase 3J waveform: $ROOT_DIR/$NES_PHASE3J_WAVEFORM"
echo "VGA Phase 3K waveform: $ROOT_DIR/$VGA_PHASE3K_WAVEFORM"
echo "VGA Phase 3K static trace: $ROOT_DIR/$VGA_PHASE3K_TRACE"
echo "NES/VGA Phase 3K trace: $ROOT_DIR/$NES_VGA_PHASE3K_TRACE"
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
