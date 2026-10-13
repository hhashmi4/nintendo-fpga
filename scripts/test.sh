#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! python3 -m pytest --version >/dev/null 2>&1; then
    echo "ERROR: pytest is required. Install the pinned development dependencies:" >&2
    echo "       python3 -m pip install -r requirements-dev.txt" >&2
    exit 1
fi

echo "[1/5] Python references, Phase 5A-6G audio/video/diagnostics, and Phase 4F software tests"
python3 scripts/generate_runtime_loader_mmio_defs.py --check
python3 scripts/generate_diagnostic_mmio_defs.py --check
python3 scripts/generate_apu_audio_fir.py --check
python3 -m scripts.generate_audio_phase5k_coefficients --check
python3 -m pytest

echo "[2/5] Verilator RTL lint"
scripts/lint.sh

echo "[3/5] Verilator platform, CPU/PPU/system, Phase 5A-6E audio/video/diagnostics, and retained integration simulations"
scripts/sim.sh

echo "[4/5] Phase 4E-E debugger command CDC, execution control, and playable integration"
scripts/test_debug_command_cdc.sh
scripts/test_debugger.sh

echo "[5/5] Phase 6G complete-system startup, reset, A/V and fault recovery"
scripts/test_system_integration.sh
