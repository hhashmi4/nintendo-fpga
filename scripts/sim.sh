#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p \
    build/sim \
    build/verilator/platform \
    build/verilator/cpu \
    build/verilator/alu \
    build/verilator/address \
    build/verilator/cpu_phase2d \
    build/verilator/cpu_phase2e \
    build/verilator/cpu_phase2f \
    build/verilator/cpu_phase2g \
    build/verilator/cpu_phase2h

PLATFORM_WAVEFORM="build/sim/platform_foundation.fst"
CPU_WAVEFORM="build/sim/cpu_phase2a.fst"
ALU_WAVEFORM="build/sim/cpu_alu.fst"
ADDRESS_WAVEFORM="build/sim/cpu_address_gen.fst"
CPU_PHASE2D_WAVEFORM="build/sim/cpu_phase2d.fst"
CPU_PHASE2E_WAVEFORM="build/sim/cpu_phase2e.fst"
CPU_PHASE2F_WAVEFORM="build/sim/cpu_phase2f.fst"
CPU_PHASE2G_WAVEFORM="build/sim/cpu_phase2g.fst"
CPU_PHASE2H_WAVEFORM="build/sim/cpu_phase2h.fst"
rm -f \
    "$PLATFORM_WAVEFORM" \
    "$CPU_WAVEFORM" \
    "$ALU_WAVEFORM" \
    "$ADDRESS_WAVEFORM" \
    "$CPU_PHASE2D_WAVEFORM" \
    "$CPU_PHASE2E_WAVEFORM" \
    "$CPU_PHASE2F_WAVEFORM" \
    "$CPU_PHASE2G_WAVEFORM" \
    "$CPU_PHASE2H_WAVEFORM"

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

echo "Platform waveform: $ROOT_DIR/$PLATFORM_WAVEFORM"
echo "CPU waveform: $ROOT_DIR/$CPU_WAVEFORM"
echo "ALU waveform: $ROOT_DIR/$ALU_WAVEFORM"
echo "Address waveform: $ROOT_DIR/$ADDRESS_WAVEFORM"
echo "Phase 2D waveform: $ROOT_DIR/$CPU_PHASE2D_WAVEFORM"
echo "Phase 2E waveform: $ROOT_DIR/$CPU_PHASE2E_WAVEFORM"
echo "Phase 2F waveform: $ROOT_DIR/$CPU_PHASE2F_WAVEFORM"
echo "Phase 2G waveform: $ROOT_DIR/$CPU_PHASE2G_WAVEFORM"
echo "Phase 2H waveform: $ROOT_DIR/$CPU_PHASE2H_WAVEFORM"
