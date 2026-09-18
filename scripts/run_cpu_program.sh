#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "usage: $0 PROGRAM.mem START_PC_HEX PASS_PC_HEX [MAX_CYCLES]" >&2
    exit 2
fi

PROGRAM_FILE="$1"
START_PC="$2"
PASS_PC="$3"
MAX_CYCLES="${4:-100000000}"
mkdir -p build/verilator/cpu_program

verilator --binary --timing --Wall -Wno-fatal --assert \
    --Mdir build/verilator/cpu_program \
    --top-module cpu_program_tb \
    -o cpu_program_tb \
    rtl/cpu/cpu_pkg.sv \
    rtl/cpu/cpu_alu.sv \
    rtl/cpu/cpu_decoder.sv \
    rtl/cpu/cpu_address_gen.sv \
    rtl/cpu/cpu_core.sv \
    sim/cpu_test_memory.sv \
    sim/cpu_program_tb.sv

build/verilator/cpu_program/cpu_program_tb \
    +PROGRAM="$PROGRAM_FILE" \
    +START_PC="$START_PC" \
    +PASS_PC="$PASS_PC" \
    +MAX_CYCLES="$MAX_CYCLES"
