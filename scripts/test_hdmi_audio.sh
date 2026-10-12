#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PYTHONPATH=.
python3 scripts/generate_hdmi_audio_vectors.py build/sim/phase6d_random_pcm.hex
python3 scripts/generate_hdmi_audio_vectors.py build/sim/phase6d_melody_pcm.hex \
    --wav build/audio/phase5j_melody.wav --count 512
python3 scripts/generate_hdmi_audio_vectors.py build/sim/phase6d_phase5k_pcm.hex \
    --capture build/audio/phase5j_melody.apucap
for test in transport control random cdc_random edid av_longrun melody pcm_integration; do
    top="hdmi_audio_${test}_tb"
    directory="build/verilator/hdmi_audio_${test}_phase6d"
    mkdir -p "$directory"
    verilator --binary --timing --assert --Wall -Wno-BLKSEQ \
        -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -j 4 \
        --Mdir "$directory" --top-module "$top" -o "$top" \
        rtl/platform/reset_sync.sv rtl/audio/audio_pll.sv \
        rtl/video/hdmi_tx_pkg.sv rtl/audio/hdmi_audio_pkg.sv \
        rtl/audio/audio_async_fifo.sv rtl/audio/hdmi_i2s_tx.sv \
        rtl/audio/hdmi_audio_transport.sv rtl/audio/adv7513_audio_profile.sv \
        rtl/audio/hdmi_audio_edid.sv \
        rtl/audio/adv7513_audio_config_engine.sv rtl/audio/hdmi_audio_controller.sv \
        rtl/audio/nes_audio_fir_coeff_pkg.sv rtl/audio/nes_audio_resampler.sv \
        rtl/audio/nes_audio_conditioner.sv rtl/audio/wm8731_i2c_init.sv \
        rtl/audio/wm8731_i2s_tx.sv rtl/audio/nes_audio_output.sv \
        rtl/video/video_720p_timing.sv rtl/video/vga_timing.sv \
        "sim/${top}.sv"
    "$directory/$top"
    if [[ "$test" == av_longrun ]]; then
        "$directory/$top" +fitted_video_clock
    fi
done
