#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PLATFORM_RTL_FILES=(
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
    "${PLATFORM_RTL_FILES[@]}"

verilator --lint-only --Wall \
    --top-module ppu_timing \
    rtl/ppu/ppu_timing.sv

CPU_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
)

verilator --lint-only --Wall -Wno-fatal \
    --top-module cpu_core \
    "${CPU_RTL_FILES[@]}"

ALU_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
)

# The standalone ALU top does not consume Phase 2A reset constants from the
# shared package; cpu_core's separate lint target checks their real consumer.
verilator --lint-only --Wall -Wno-fatal -Wno-UNUSEDPARAM \
    --top-module cpu_alu \
    "${ALU_RTL_FILES[@]}"

ADDRESS_RTL_FILES=(
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_address_gen.sv
)

# The standalone address top also leaves earlier-phase package constants
# unused; their real consumers remain covered by the other lint targets.
verilator --lint-only --Wall -Wno-fatal -Wno-UNUSEDPARAM \
    --top-module cpu_address_gen \
    "${ADDRESS_RTL_FILES[@]}"

CPU_BOARD_DIAG_RTL_FILES=(
    rtl/platform/platform_config_pkg.sv
    rtl/platform/platform_clock.sv
    rtl/platform/reset_sync.sv
    rtl/platform/level_sync.sv
    rtl/platform/nes_timing_gen.sv
    rtl/cpu/cpu_pkg.sv
    rtl/cpu/cpu_alu.sv
    rtl/cpu/cpu_decoder.sv
    rtl/cpu/cpu_address_gen.sv
    rtl/cpu/cpu_core.sv
    rtl/diagnostic/cpu_board_diag_pkg.sv
    rtl/diagnostic/cpu_board_diag_memory.sv
    rtl/diagnostic/cpu_board_diag.sv
    rtl/diagnostic/hex7seg.sv
    rtl/cpu_board_diag_top.sv
)

# The diagnostic top intentionally leaves internal trace-only ports open, and
# the shared CPU package contains constants unused by some hierarchy leaves.
verilator --lint-only --Wall -Wno-fatal \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    -Irtl/diagnostic \
    --top-module cpu_board_diag_top \
    "${CPU_BOARD_DIAG_RTL_FILES[@]}"
