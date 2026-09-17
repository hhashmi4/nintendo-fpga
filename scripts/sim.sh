#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p \
    build/sim \
    build/verilator/platform \
    build/verilator/cpu \
    build/verilator/alu

PLATFORM_WAVEFORM="build/sim/platform_foundation.fst"
CPU_WAVEFORM="build/sim/cpu_phase2a.fst"
ALU_WAVEFORM="build/sim/cpu_alu.fst"
rm -f "$PLATFORM_WAVEFORM" "$CPU_WAVEFORM" "$ALU_WAVEFORM"

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

echo "Platform waveform: $ROOT_DIR/$PLATFORM_WAVEFORM"
echo "CPU waveform: $ROOT_DIR/$CPU_WAVEFORM"
echo "ALU waveform: $ROOT_DIR/$ALU_WAVEFORM"
