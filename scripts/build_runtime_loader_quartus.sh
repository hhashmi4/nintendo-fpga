#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/quartus"
REPORT_PATH="$ROOT_DIR/build/quartus_runtime_loader/output_files/nes_runtime_loader.map.rpt"

mkdir -p "$(dirname "$REPORT_PATH")"
cd "$PROJECT_DIR"
quartus_map nes_runtime_loader \
    --read_settings_files=on --write_settings_files=off

if [[ ! -f "$REPORT_PATH" ]]; then
    echo "ERROR: runtime-loader synthesis produced no $REPORT_PATH" >&2
    exit 1
fi

if ! grep -q "Analysis & Synthesis was successful" "$REPORT_PATH"; then
    echo "ERROR: runtime-loader synthesis report is not successful" >&2
    exit 1
fi

if grep -Eqi "inferred latch|multiple constant drivers|multiple drivers" \
    "$REPORT_PATH"; then
    echo "ERROR: runtime-loader synthesis has a latch or multiple-driver warning" >&2
    exit 1
fi

echo "Runtime-loader synthesis report: $REPORT_PATH"
grep -E "^; (Estimate of Logic utilization|Combinational ALUT usage|Dedicated logic registers|Total registers|Total DSP Blocks|Total PLLs)" \
    "$REPORT_PATH" || true
