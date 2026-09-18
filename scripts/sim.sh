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
    rtl/ppu/ppu_sprite_core.sv \
    sim/ppu_phase3f_tb.sv

build/verilator/ppu_phase3f/ppu_phase3f_tb

if [[ ! -s "$PPU_PHASE3F_WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $PPU_PHASE3F_WAVEFORM" >&2
    exit 1
fi

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
