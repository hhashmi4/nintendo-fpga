#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_FILE="$ROOT_DIR/quartus/nes_hps_loader_system.qsys"
OUTPUT_DIR="$ROOT_DIR/build/qsys_nes_hps_loader_system"

find_qsys_generate() {
    if [[ -n "${QSYS_GENERATE:-}" ]]; then
        printf '%s\n' "$QSYS_GENERATE"
        return
    fi
    if command -v qsys-generate >/dev/null 2>&1; then
        command -v qsys-generate
        return
    fi
    if command -v quartus_sh >/dev/null 2>&1; then
        local quartus_bin
        quartus_bin="$(dirname "$(command -v quartus_sh)")"
        local candidate="$quartus_bin/../sopc_builder/bin/qsys-generate"
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    fi
    echo "ERROR: qsys-generate was not found; set QSYS_GENERATE explicitly" >&2
    return 1
}

QSYS_TOOL="$(find_qsys_generate)"
"$QSYS_TOOL" "$SYSTEM_FILE" \
    --synthesis=VERILOG \
    --clear-output-directory \
    --output-directory="$OUTPUT_DIR"

REGMAP="$OUTPUT_DIR/synthesis/nes_hps_loader_system.regmap"
QIP="$OUTPUT_DIR/synthesis/nes_hps_loader_system.qip"
for required in "$REGMAP" "$QIP"; do
    if [[ ! -f "$required" ]]; then
        echo "ERROR: Platform Designer did not produce $required" >&2
        exit 1
    fi
done

python3 "$ROOT_DIR/scripts/validate_hps_loader_address_map.py" \
    --contract "$ROOT_DIR/config/runtime_loader_mmio.json" \
    --qsys "$SYSTEM_FILE" \
    --regmap "$REGMAP"

echo "Platform Designer QIP: $QIP"
