#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PYTHONPATH=.
python3 scripts/generate_usbc_power_vectors.py
for test in power power_cdc; do
    top="usbc_${test}_tb"
    directory="build/verilator/usbc_${test}"
    verilator --binary --timing --assert --Wall -Wno-BLKSEQ -j 4 \
        --Mdir "$directory" --top-module "$top" -o "$top" \
        rtl/platform/reset_sync.sv rtl/power/usbc_power_status_cdc.sv \
        rtl/power/usbc_power_supervisor.sv "sim/${top}.sv"
    "$directory/$top"
done
# Production availability tie-off uses the same append-only MMIO/CDC RTL.
directory=build/verilator/phase6e_diagnostic_unavailable
verilator --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
    -Wno-UNUSEDPARAM -j 4 --Mdir "$directory" \
    --top-module nes_diagnostic_phase5m_tb -GPOWER_AVAILABLE=0 \
    -o diagnostic_unavailable rtl/diagnostic/nes_diagnostic_mmio_pkg.sv \
    rtl/diagnostic/nes_diagnostic_subsystem.sv sim/nes_diagnostic_phase5m_tb.sv
"$directory/diagnostic_unavailable"
