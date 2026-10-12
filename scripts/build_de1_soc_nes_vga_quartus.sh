#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="de1_soc_nes_vga"
PROJECT_DIR="$ROOT_DIR/quartus"
BUILD_DIR="$ROOT_DIR/build/quartus_de1_soc_nes_vga"
OUTPUT_DIR="$BUILD_DIR/output_files"
RBF_PATH="$BUILD_DIR/${PROJECT_NAME}.rbf"

mkdir -p "$OUTPUT_DIR"
PLAYABLE_ROM="$ROOT_DIR/roms/phase4db_playable_nrom128.nes"
REGENERATED_ROM="$ROOT_DIR/build/cartridge/phase4db_regenerated.nes"
PLAYABLE_PREFIX="$ROOT_DIR/build/cartridge/phase4db_playable_nrom128"
python3 "$ROOT_DIR/scripts/generate_phase4db_playable_rom.py" \
    "$REGENERATED_ROM"
if ! cmp -s "$PLAYABLE_ROM" "$REGENERATED_ROM"; then
    echo "ERROR: committed playable ROM differs from its project-owned source" >&2
    exit 1
fi
python3 "$ROOT_DIR/scripts/prepare_phase4db_cartridge.py" \
    "$PLAYABLE_ROM" "$PLAYABLE_PREFIX"
"$ROOT_DIR/scripts/generate_hps_loader_system.sh"
cd "$PROJECT_DIR"
quartus_sh --flow compile "$PROJECT_NAME"

SOF_PATH="$OUTPUT_DIR/${PROJECT_NAME}.sof"
MAP_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.map.rpt"
FIT_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.fit.rpt"
STA_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.sta.rpt"
STA_SUMMARY="$OUTPUT_DIR/${PROJECT_NAME}.sta.summary"

for required in "$SOF_PATH" "$MAP_REPORT" "$FIT_REPORT" "$STA_REPORT" "$STA_SUMMARY"; do
    if [[ ! -f "$required" ]]; then
        echo "ERROR: DE1-SoC NES/VGA build did not produce $required" >&2
        exit 1
    fi
done

if ! grep -q "Analysis & Synthesis was successful" "$MAP_REPORT"; then
    echo "ERROR: DE1-SoC NES/VGA analysis and synthesis did not succeed" >&2
    exit 1
fi
if ! grep -q "Fitter was successful" "$FIT_REPORT"; then
    echo "ERROR: DE1-SoC NES/VGA fitter did not succeed" >&2
    exit 1
fi
if ! grep -q "Assembler was successful" "$OUTPUT_DIR/${PROJECT_NAME}.asm.rpt"; then
    echo "ERROR: DE1-SoC NES/VGA assembler did not succeed" >&2
    exit 1
fi
if ! grep -q "Design is fully constrained for setup requirements" "$STA_REPORT" ||
   ! grep -q "Design is fully constrained for hold requirements" "$STA_REPORT"; then
    echo "ERROR: DE1-SoC NES/VGA timing has unconstrained setup or hold paths" >&2
    exit 1
fi
if grep -q "Timing requirements not met" "$STA_REPORT"; then
    echo "ERROR: DE1-SoC NES/VGA timing fails in at least one corner" >&2
    exit 1
fi
if ! awk '
    /^Slack :/ { seen = 1; if (($3 + 0) < 0) failed = 1 }
    END { exit !(seen && !failed) }
' "$STA_SUMMARY"; then
    echo "ERROR: DE1-SoC NES/VGA timing has negative or missing slack" >&2
    exit 1
fi
if grep -Eqi "inferred latch|multiple constant drivers|multiple drivers" "$MAP_REPORT"; then
    echo "ERROR: DE1-SoC NES/VGA synthesis has a latch or multiple-driver warning" >&2
    exit 1
fi
if ! grep -q "Total PLLs[[:space:]]*; 2" "$FIT_REPORT"; then
    echo "ERROR: DE1-SoC NES/VGA/audio build does not report exactly two PLLs" >&2
    exit 1
fi

quartus_sta -t "$ROOT_DIR/scripts/report_de1_soc_nes_vga_timing.tcl"

quartus_cpf -c "$SOF_PATH" "$RBF_PATH"
if [[ ! -f "$RBF_PATH" ]]; then
    echo "ERROR: DE1-SoC NES/VGA RBF was not generated" >&2
    exit 1
fi

echo "DE1-SoC NES/VGA SOF: $SOF_PATH"
echo "DE1-SoC NES/VGA RBF: $RBF_PATH"
echo "DE1-SoC NES/VGA timing: fully constrained with non-negative reported slack"
grep -E "^; (Logic utilization|Combinational ALUT usage|Memory ALUT usage|Dedicated logic registers|Total registers|M10K blocks|Total MLAB memory bits|Total block memory bits|Total RAM Blocks|Total DSP Blocks|Total PLLs)" \
    "$FIT_REPORT" || true
cat "$STA_SUMMARY"
