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
python3 -m pytest

echo "[FAST 2/3] Complete Verilator RTL lint"
scripts/lint.sh

echo "[FAST 3/3] Focused platform, Phase 5A/5B/5C/5D APU, and runtime-loader RTL smoke"
scripts/sim.sh --fast
