#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p build/sim build/verilator/nes_diagnostic_phase5m
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
