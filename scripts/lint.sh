#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RTL_FILES=(
    rtl/platform/platform_config_pkg.sv
    rtl/platform/platform_clock.sv
    rtl/platform/reset_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/platform/platform_core.sv
    rtl/diagnostic/platform_diagnostic.sv
    rtl/de1_soc_top.sv
)

verilator --lint-only --Wall -Wno-fatal \
    --top-module de1_soc_top \
    "${RTL_FILES[@]}"
