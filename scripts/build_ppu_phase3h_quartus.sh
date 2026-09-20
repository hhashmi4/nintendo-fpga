#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="ppu_phase3h"
PROJECT_DIR="$ROOT_DIR/quartus"
OUTPUT_DIR="$ROOT_DIR/build/quartus_ppu_phase3h/output_files"

mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"
quartus_sh --flow compile "$PROJECT_NAME"

MAP_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.map.rpt"
FIT_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.fit.rpt"
STA_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.sta.rpt"
STA_SUMMARY="$OUTPUT_DIR/${PROJECT_NAME}.sta.summary"

for required in "$MAP_REPORT" "$FIT_REPORT" "$STA_REPORT" "$STA_SUMMARY"; do
    if [[ ! -f "$required" ]]; then
        echo "ERROR: Phase 3H Quartus build did not produce $required" >&2
        exit 1
    fi
done

if ! grep -q "Analysis & Synthesis was successful" "$MAP_REPORT"; then
    echo "ERROR: Phase 3H analysis and synthesis did not succeed" >&2
    exit 1
fi

if ! grep -q "Design is fully constrained for setup requirements" "$STA_REPORT" ||
   ! grep -q "Design is fully constrained for hold requirements" "$STA_REPORT"; then
    echo "ERROR: Phase 3H timing report has unconstrained setup or hold paths" >&2
    exit 1
fi

if ! awk '
    /^Slack :/ { seen = 1; if (($3 + 0) < 0) failed = 1 }
    END { exit !(seen && !failed) }
' "$STA_SUMMARY"; then
    echo "ERROR: Phase 3H timing report has negative or missing slack" >&2
    exit 1
fi

if grep -Eqi "inferred latch|multiple constant drivers|multiple drivers" "$MAP_REPORT"; then
    echo "ERROR: Phase 3H synthesis report contains a latch or multiple-driver warning" >&2
    exit 1
fi

if ! grep -q "Total PLLs[[:space:]]*; 0" "$FIT_REPORT"; then
    echo "ERROR: Phase 3H build unexpectedly uses a PLL or lacks the PLL report" >&2
    exit 1
fi

echo "Phase 3H integrated PPU pixel mixer: $FIT_REPORT"
echo "Phase 3H timing: fully constrained with non-negative reported slack"
grep -E "^; (Logic utilization|Combinational ALUT usage|Memory ALUT usage|Dedicated logic registers|Total registers|M10K blocks|Total MLAB memory bits|Total block memory bits|Total RAM Blocks|Total DSP Blocks|Total PLLs)" \
    "$FIT_REPORT" || true
cat "$STA_SUMMARY"
