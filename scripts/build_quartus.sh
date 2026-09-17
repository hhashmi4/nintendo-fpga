#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="nintendo_fpga"
PROJECT_DIR="$ROOT_DIR/quartus"
OUTPUT_DIR="$ROOT_DIR/build/quartus/output_files"
RBF_PATH="$ROOT_DIR/build/quartus/${PROJECT_NAME}.rbf"

mkdir -p "$OUTPUT_DIR"

cd "$PROJECT_DIR"
quartus_sh --flow compile "$PROJECT_NAME"

SOF_PATH="$OUTPUT_DIR/${PROJECT_NAME}.sof"
STA_REPORT="$OUTPUT_DIR/${PROJECT_NAME}.sta.rpt"
STA_SUMMARY="$OUTPUT_DIR/${PROJECT_NAME}.sta.summary"
if [[ ! -f "$SOF_PATH" ]]; then
    echo "ERROR: Quartus completed without producing $SOF_PATH" >&2
    exit 1
fi

if [[ ! -f "$STA_REPORT" || ! -f "$STA_SUMMARY" ]]; then
    echo "ERROR: Quartus completed without Timing Analyzer reports" >&2
    exit 1
fi

if ! grep -q "Design is fully constrained for setup requirements" "$STA_REPORT" ||
   ! grep -q "Design is fully constrained for hold requirements" "$STA_REPORT"; then
    echo "ERROR: Timing Analyzer reports unconstrained setup or hold paths" >&2
    exit 1
fi

if ! awk '
    /^Slack :/ { seen = 1; if (($3 + 0) < 0) failed = 1 }
    END { exit !(seen && !failed) }
' "$STA_SUMMARY"; then
    echo "ERROR: Timing Analyzer reports negative slack or no slack results" >&2
    exit 1
fi

quartus_cpf -c "$SOF_PATH" "$RBF_PATH"

if [[ ! -f "$RBF_PATH" ]]; then
    echo "ERROR: quartus_cpf completed without producing $RBF_PATH" >&2
    exit 1
fi

echo "SOF: $SOF_PATH"
echo "RBF: $RBF_PATH"
echo "Timing: fully constrained with non-negative reported slack"
