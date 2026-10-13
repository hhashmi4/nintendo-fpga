#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build/phase6g build/sim
export PYTHONPATH=.
python3 scripts/generate_phase6g_vectors.py
FLAGS=(--binary --timing --Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -j 4)
# Malformed-coordinate tests use explicit fatal checks, as in the retained
# Phase 6B fault bench; normal DUT input assertions prohibit these stimuli.
verilator "${FLAGS[@]}" --Mdir build/verilator/phase6g_frame \
    --top-module phase6g_frame_recovery_tb -o phase6g_frame_recovery_tb \
    rtl/video/nes_framebuffer.sv sim/phase6g_frame_recovery_tb.sv
build/verilator/phase6g_frame/phase6g_frame_recovery_tb
verilator "${FLAGS[@]}" --assert --Mdir build/verilator/phase6g_ownership \
    --top-module phase6g_ownership_tb -o phase6g_ownership_tb \
    rtl/video/nes_framebuffer.sv sim/phase6g_ownership_tb.sv
build/verilator/phase6g_ownership/phase6g_ownership_tb
verilator "${FLAGS[@]}" --assert --Mdir build/verilator/phase6g_hdmi_enable \
    --top-module phase6g_hdmi_enable_tb -o phase6g_hdmi_enable_tb \
    rtl/video/hdmi_rgb_output.sv sim/phase6g_hdmi_enable_tb.sv
build/verilator/phase6g_hdmi_enable/phase6g_hdmi_enable_tb
verilator "${FLAGS[@]}" --assert --Mdir build/verilator/phase6g_diagnostics \
    --top-module nes_diagnostic_phase5m_tb -o phase6g_diagnostics_tb \
    rtl/diagnostic/nes_diagnostic_mmio_pkg.sv \
    rtl/diagnostic/nes_diagnostic_subsystem.sv sim/nes_diagnostic_phase5m_tb.sv
build/verilator/phase6g_diagnostics/phase6g_diagnostics_tb +phase6g_counters
verilator "${FLAGS[@]}" --assert --Mdir build/verilator/phase6g_video_reset \
    --top-module nes_digital_video_pipeline_tb -o phase6g_video_reset_tb \
    rtl/platform/reset_sync.sv rtl/video/video_720p_timing.sv \
    rtl/video/nes_720p_scaler.sv rtl/video/nes_palette_rgb.sv \
    rtl/video/nes_framebuffer.sv rtl/video/nes_720p_video.sv \
    rtl/video/nes_digital_video_pipeline.sv sim/nes_digital_video_pipeline_tb.sv
build/verilator/phase6g_video_reset/phase6g_video_reset_tb +phase6g_reset

# Reuse the original CPU-driven melody capture and its independent FIR model.
# FULL already produced it; the focused command can also run from a clean tree.
if [[ ! -s build/audio/phase5j_melody.apucap ]]; then
    scripts/run_apu_audio_phase5j.sh --demo
fi
python3 scripts/generate_hdmi_audio_vectors.py build/sim/phase6d_phase5k_pcm.hex \
    --capture build/audio/phase5j_melody.apucap
verilator "${FLAGS[@]}" --assert -Wno-PINCONNECTEMPTY \
    --Mdir build/verilator/phase6g_audio \
    --top-module hdmi_audio_pcm_integration_tb -o phase6g_audio_tb \
    rtl/platform/reset_sync.sv rtl/audio/audio_pll.sv \
    rtl/audio/audio_async_fifo.sv rtl/audio/hdmi_i2s_tx.sv \
    rtl/audio/hdmi_audio_transport.sv rtl/audio/nes_audio_fir_coeff_pkg.sv \
    rtl/audio/nes_audio_resampler.sv rtl/audio/nes_audio_conditioner.sv \
    rtl/audio/wm8731_i2c_init.sv rtl/audio/wm8731_i2s_tx.sv \
    rtl/audio/nes_audio_output.sv sim/hdmi_audio_pcm_integration_tb.sv
build/verilator/phase6g_audio/phase6g_audio_tb +phase6g_reset

python3 scripts/prepare_phase4db_cartridge.py \
    roms/phase4db_playable_nrom128.nes build/cartridge/phase4db_playable_nrom128
python3 scripts/generate_phase6g_system.py
# Use the production manifests so the integrated bench cannot silently omit
# a production dependency. The second framebuffer exists only in simulation.
mapfile -t SYSTEM_RTL < <(sed -n \
    's|^set_global_assignment -name SYSTEMVERILOG_FILE ../||p' \
    quartus/de1_soc_nes_vga.qsf quartus/phase6d_hdmi_audio.qsf | awk '!seen[$0]++')
verilator "${FLAGS[@]}" --assert -Wno-PINCONNECTEMPTY \
    --Mdir build/verilator/phase6g_system --top-module phase6g_system_tb \
    -o phase6g_system_tb "${SYSTEM_RTL[@]}" rtl/power/usbc_power_supervisor.sv \
    sim/phase6g_hdmi_sink.sv sim/phase6g_system_tb.sv
stdbuf -oL build/verilator/phase6g_system/phase6g_system_tb
