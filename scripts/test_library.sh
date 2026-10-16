#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build/phase8c build/verilator
export PYTHONPATH=.
verilator --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -j 4 \
    --Mdir build/verilator/library --top-module nes_library_tb -o test \
    rtl/debug/debug_font_pkg.sv rtl/console/nes_console_mailbox.sv \
    rtl/console/nes_library_mmio.sv rtl/console/nes_library_control.sv sim/nes_library_tb.sv
build/verilator/library/test
python3 scripts/generate_library_vectors.py
verilator --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -j 4 \
    --Mdir build/verilator/library_renderer --top-module nes_library_renderer_tb -o test \
    rtl/platform/reset_sync.sv rtl/debug/debug_font_pkg.sv rtl/console/nes_console_mailbox.sv \
    rtl/console/nes_console_style_pkg.sv rtl/console/nes_console_animation.sv \
    rtl/console/nes_console_renderer.sv rtl/console/nes_console_video.sv \
    rtl/console/nes_console_720p_overlay.sv sim/nes_library_renderer_tb.sv
build/verilator/library_renderer/test
python3 scripts/verify_library_capture.py --unit
