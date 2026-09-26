#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build/sim build/verilator/nes_debug_command_cdc
verilator --lint-only --Wall --top-module nes_debug_command_cdc \
    rtl/debug/nes_debug_command_cdc.sv
verilator --binary --timing --trace-fst --Wall -Wno-BLKSEQ --assert \
    --Mdir build/verilator/nes_debug_command_cdc \
    --top-module nes_debug_command_cdc_tb -o nes_debug_command_cdc_tb \
    rtl/debug/nes_debug_command_cdc.sv sim/nes_debug_command_cdc_tb.sv
build/verilator/nes_debug_command_cdc/nes_debug_command_cdc_tb
test -s build/sim/nes_debug_command_cdc.fst
