#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROFILE="${1:---full}"
if [[ "$PROFILE" != "--quick" && "$PROFILE" != "--full" &&
      "$PROFILE" != "--demo" ]]; then
    echo "Usage: $0 [--quick|--full|--demo]" >&2
    exit 2
fi

BUILD_DIR="build/verilator/nes_apu_audio_phase5j"
CAPTURE_DIR="build/audio"
TESTBENCH="$BUILD_DIR/nes_apu_audio_phase5j_tb"
mkdir -p "$BUILD_DIR" "$CAPTURE_DIR" build/sim

python3 scripts/generate_apu_audio_phase5j_roms.py --output-dir build/sim

verilator --binary --timing --Wall -Wno-fatal \
    -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINMISSING \
    -Wno-PINCONNECTEMPTY -Wno-BLKSEQ --assert \
    --Mdir "$BUILD_DIR" \
    --top-module nes_apu_audio_phase5j_tb \
    -o nes_apu_audio_phase5j_tb \
    rtl/apu/nes_apu_pkg.sv \
    rtl/apu/nes_apu_pulse.sv \
    rtl/apu/nes_apu_triangle.sv \
    rtl/apu/nes_apu_noise.sv \
    rtl/apu/nes_apu_dmc.sv \
    rtl/apu/nes_apu_mixer_lut_pkg.sv \
    rtl/apu/nes_apu_mixer.sv \
    rtl/apu/nes_apu.sv \
    rtl/cpu/cpu_pkg.sv \
    rtl/cpu/cpu_alu.sv \
    rtl/cpu/cpu_decoder.sv \
    rtl/cpu/cpu_address_gen.sv \
    rtl/cpu/cpu_core.sv \
    rtl/system/nes_system_pkg.sv \
    rtl/system/nes_cpu_address_decoder.sv \
    rtl/system/nes_cpu_ram.sv \
    rtl/system/nes_cpu_bus.sv \
    rtl/dma/nes_oam_dma.sv \
    rtl/dma/nes_dmc_dma.sv \
    rtl/system/nes_internal_bus_arbiter.sv \
    rtl/ppu/ppu_timing.sv \
    rtl/ppu/ppu_scroll.sv \
    rtl/ppu/ppu_registers.sv \
    rtl/ppu/ppu_core.sv \
    rtl/ppu/ppu_memory.sv \
    rtl/ppu/ppu_background.sv \
    rtl/ppu/ppu_background_core.sv \
    rtl/ppu/ppu_sprite_range.sv \
    rtl/ppu/ppu_oam.sv \
    rtl/ppu/ppu_sprite_address.sv \
    rtl/ppu/ppu_sprite_renderer.sv \
    rtl/ppu/ppu_pixel_mixer.sv \
    rtl/ppu/ppu_sprite_core.sv \
    rtl/nes_core.sv \
    rtl/controller/nes_controller.sv \
    rtl/cartridge/nes_mapper0_address.sv \
    rtl/cartridge/nes_mapper.sv \
    rtl/cartridge/nes_mapper0.sv \
    rtl/cartridge/nes_cartridge.sv \
    sim/nes_apu_audio_phase5j_tb.sv

run_capture() {
    local scenario="$1"
    local cpu_cycles="$2"
    shift 2
    "$TESTBENCH" \
        "+SCENARIO=$scenario" \
        "+ROM=build/sim/phase5j_${scenario}.prg.hex" \
        "+CAPTURE=$CAPTURE_DIR/phase5j_${scenario}.apucap" \
        "+CPU_CYCLES=$cpu_cycles" \
        "$@"
}

if [[ "$PROFILE" == "--quick" ]]; then
    run_capture pulse1 178977
    run_capture dmc 178977
    run_capture silence 178977
    python3 scripts/verify_apu_audio_phase5j.py \
        --capture-dir "$CAPTURE_DIR" \
        --scenarios pulse1,dmc,silence
elif [[ "$PROFILE" == "--demo" ]]; then
    run_capture melody 5369318
    python3 scripts/verify_apu_audio_phase5j.py \
        --capture-dir "$CAPTURE_DIR" \
        --scenarios melody
    echo "Playable original demo: $ROOT_DIR/$CAPTURE_DIR/phase5j_melody.wav"
else
    run_capture pulse1 178977
    run_capture pulse2 178977
    run_capture triangle 178977
    run_capture noise 178977
    run_capture dmc 178977
    run_capture combined 178977 +PAUSE_AT=80000
    run_capture silence 178977
    run_capture silence_transition 1073864 +RESET_AT=950000
    run_capture melody 5369318

    "$TESTBENCH" \
        +SCENARIO=combined \
        +ROM=build/sim/phase5j_combined.prg.hex \
        +CAPTURE="$CAPTURE_DIR/phase5j_combined_repeat.apucap" \
        +CPU_CYCLES=178977 \
        +PAUSE_AT=80000

    python3 scripts/verify_apu_audio_phase5j.py \
        --capture-dir "$CAPTURE_DIR" \
        --determinism-copy "$CAPTURE_DIR/phase5j_combined_repeat.apucap"
    echo "Playable original demo: $ROOT_DIR/$CAPTURE_DIR/phase5j_melody.wav"
fi
