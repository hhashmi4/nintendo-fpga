#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="phase6b_video"
PROJECT_DIR="$ROOT_DIR/quartus"
BUILD_DIR="$ROOT_DIR/build/quartus_phase6b_video"
OUTPUT_DIR="$BUILD_DIR/output_files"

mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"
quartus_sh --flow compile "$PROJECT_NAME"

MAP_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.map.rpt"
FIT_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.fit.rpt"
ASM_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.asm.rpt"
STA_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.sta.rpt"
STA_SUMMARY="$OUTPUT_DIR/${PROJECT_NAME}.sta.summary"
SOF_PATH="$OUTPUT_DIR/${PROJECT_NAME}.sof"

for required in "$SOF_PATH" "$MAP_REPORT" "$FIT_REPORT" "$ASM_REPORT" \
                "$STA_REPORT" "$STA_SUMMARY"; do
    if [[ ! -f "$required" ]]; then
        echo "ERROR: Phase 6B build did not produce $required" >&2
        exit 1
    fi
done

grep -q "Analysis & Synthesis was successful" "$MAP_REPORT"
grep -q "Fitter was successful" "$FIT_REPORT"
grep -q "Assembler was successful" "$ASM_REPORT"
grep -q "Design is fully constrained for setup requirements" "$STA_REPORT"
grep -q "Design is fully constrained for hold requirements" "$STA_REPORT"
if grep -q "Timing requirements not met" "$STA_REPORT"; then
    echo "ERROR: Phase 6B timing fails in at least one corner" >&2
    exit 1
fi
if ! awk '
    /^Slack :/ { seen = 1; if (($3 + 0) < 0) failed = 1 }
    END { exit !(seen && !failed) }
' "$STA_SUMMARY"; then
    echo "ERROR: Phase 6B timing has negative or missing slack" >&2
    exit 1
fi
if grep -Eqi "inferred latch|multiple constant drivers|multiple drivers" \
        "$MAP_REPORT"; then
    echo "ERROR: Phase 6B synthesis has a latch or multiple-driver warning" >&2
    exit 1
fi
if ! grep -q "Total PLLs[[:space:]]*; 1" "$FIT_REPORT"; then
    echo "ERROR: Phase 6B standalone build does not report exactly one PLL" >&2
    exit 1
fi

echo "Phase 6B shared-video SOF: $SOF_PATH"
echo "Phase 6B timing: fully constrained with non-negative reported slack"
grep -E "^; (Logic utilization|Combinational ALUT usage|Memory ALUT usage|Dedicated logic registers|Total registers|M10K blocks|Total block memory bits|Total RAM Blocks|Total DSP Blocks|Total PLLs)" \
    "$FIT_REPORT" || true
cat "$STA_SUMMARY"
