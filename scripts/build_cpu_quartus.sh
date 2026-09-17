#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/quartus"
REPORT_PATH="$ROOT_DIR/build/quartus_cpu/output_files/cpu_core.map.rpt"

mkdir -p "$(dirname "$REPORT_PATH")"
cd "$PROJECT_DIR"
quartus_map cpu_core --read_settings_files=on --write_settings_files=off

if [[ ! -f "$REPORT_PATH" ]]; then
    echo "ERROR: standalone CPU synthesis produced no $REPORT_PATH" >&2
    exit 1
fi

if ! grep -q "Analysis & Synthesis was successful" "$REPORT_PATH"; then
    echo "ERROR: standalone CPU synthesis report is not successful" >&2
    exit 1
fi

echo "Standalone CPU synthesis report: $REPORT_PATH"
grep -E "^; (Estimate of Logic utilization|Combinational ALUT usage|Dedicated logic registers|Total registers|Total DSP Blocks|Total PLLs)" \
    "$REPORT_PATH" || true
