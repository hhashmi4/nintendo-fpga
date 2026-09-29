#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build/sim build/verilator/nes_debugger_system
python3 scripts/prepare_phase4db_cartridge.py \
    roms/phase4db_playable_nrom128.nes build/cartridge/phase4db_playable_nrom128
verilator --binary --timing --trace-fst --trace-max-array 32 --Wall \
    -Wno-UNUSEDSIGNAL -Wno-BLKSEQ --assert \
    --Mdir build/verilator/nes_framebuffer_pause --top-module nes_framebuffer_pause_tb \
    -o nes_framebuffer_pause_tb rtl/video/nes_framebuffer.sv sim/nes_framebuffer_pause_tb.sv
build/verilator/nes_framebuffer_pause/nes_framebuffer_pause_tb
test -s build/sim/nes_framebuffer_pause.fst
mapfile -t RTL_FILES < <(sed -n 's|^set_global_assignment -name SYSTEMVERILOG_FILE ../||p' quartus/de1_soc_nes_vga.qsf)
verilator --binary --timing --trace-fst --trace-depth 2 --trace-max-array 32 --Wall \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-BLKSEQ --assert \
    --Mdir build/verilator/nes_debugger_system --top-module nes_debugger_system_tb \
    -o nes_debugger_system_tb "${RTL_FILES[@]}" sim/nes_debugger_system_tb.sv
stdbuf -oL build/verilator/nes_debugger_system/nes_debugger_system_tb
test -s build/sim/nes_debugger_system.fst
mkdir -p build/verilator/nes_debugger_playable
verilator --binary --timing --trace-fst --trace-depth 2 --trace-max-array 32 --Wall \
    -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-BLKSEQ --assert \
    --Mdir build/verilator/nes_debugger_playable --top-module nes_debugger_playable_tb \
    -o nes_debugger_playable_tb "${RTL_FILES[@]}" sim/nes_debugger_playable_tb.sv
stdbuf -oL build/verilator/nes_debugger_playable/nes_debugger_playable_tb
test -s build/sim/nes_debugger_playable.fst
python3 scripts/verify_phase4ec_playable_frame.py \
    build/sim/phase4ee_paused_combined_pixels.txt \
    build/sim/phase4ee_paused_snapshot.txt build/sim/phase4ee_paused.ppm
