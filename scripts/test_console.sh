#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build/phase8a
export PYTHONPATH=.
FLAGS=(--binary --timing --assert --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -j 4)
RTL=(rtl/platform/reset_sync.sv rtl/debug/debug_font_pkg.sv rtl/console/nes_console_mailbox.sv
     rtl/console/nes_console_control.sv rtl/console/nes_console_mmio.sv
     rtl/console/nes_console_video.sv rtl/console/nes_console_renderer.sv)
python3 scripts/generate_console_vectors.py
for unit in control mmio video renderer; do
    verilator "${FLAGS[@]}" --Mdir "build/verilator/console_$unit" \
        --top-module "nes_console_${unit}_tb" -o test \
        "${RTL[@]}" "sim/nes_console_${unit}_tb.sv"
    "build/verilator/console_$unit/test"
done
if [[ "${1:-}" == --unit ]]; then exit 0; fi
python3 scripts/prepare_phase4db_cartridge.py \
    roms/phase4db_playable_nrom128.nes build/cartridge/phase4db_playable_nrom128
python3 scripts/generate_phase6g_system.py
mapfile -t SYSTEM_RTL < <(sed -n \
    's|^set_global_assignment -name SYSTEMVERILOG_FILE ../||p' \
    quartus/de1_soc_nes_vga.qsf quartus/phase6d_hdmi_audio.qsf | awk '!seen[$0]++')
verilator "${FLAGS[@]}" -Wno-PINCONNECTEMPTY \
    --Mdir build/verilator/console_system --top-module nes_console_system_tb \
    -o test "${SYSTEM_RTL[@]}" sim/nes_console_system_tb.sv
stdbuf -oL build/verilator/console_system/test
python3 scripts/verify_console_capture.py
