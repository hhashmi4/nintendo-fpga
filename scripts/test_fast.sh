#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! python3 -m pytest --version >/dev/null 2>&1; then
    echo "ERROR: pytest is required. Install the pinned development dependencies:" >&2
    echo "       python3 -m pip install -r requirements-dev.txt" >&2
    exit 1
fi

echo "[FAST 1/3] Complete Python reference and software verification"
python3 scripts/generate_runtime_loader_mmio_defs.py --check
python3 scripts/generate_diagnostic_mmio_defs.py --check
python3 scripts/generate_apu_audio_fir.py --check
python3 -m pytest

echo "[FAST 2/3] Complete Verilator RTL lint"
scripts/lint.sh

echo "[FAST 3/3] Focused platform, APU, runtime-loader, Phase 5M diagnostic, and Phase 6C HDMI RTL smoke"
scripts/sim.sh --fast
