#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p build/sim build/verilator

WAVEFORM="build/sim/platform_foundation.fst"
rm -f "$WAVEFORM"

RTL_FILES=(
    rtl/platform/platform_config_pkg.sv
    rtl/platform/platform_clock.sv
    rtl/platform/reset_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/platform/platform_core.sv
    rtl/diagnostic/platform_diagnostic.sv
)

verilator --binary --timing --trace-fst --Wall -Wno-fatal \
    --Mdir build/verilator \
    --top-module platform_foundation_tb \
    -o platform_foundation_tb \
    "${RTL_FILES[@]}" \
    sim/platform_foundation_tb.sv

build/verilator/platform_foundation_tb

if [[ ! -s "$WAVEFORM" ]]; then
    echo "ERROR: simulation did not generate a non-empty $WAVEFORM" >&2
    exit 1
fi

echo "Waveform: $ROOT_DIR/$WAVEFORM"
