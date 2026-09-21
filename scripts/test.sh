#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! python3 -m pytest --version >/dev/null 2>&1; then
    echo "ERROR: pytest is required. Install the pinned development dependencies:" >&2
    echo "       python3 -m pip install -r requirements-dev.txt" >&2
    exit 1
fi

echo "[1/3] Python reference tests"
python3 -m pytest

echo "[2/3] Verilator RTL lint"
scripts/lint.sh

echo "[3/3] Verilator platform, PPU, CPU, Phase 3J-4E-B system/cartridge/controller/DMA/video/debug, ALU, address, and Phase 2D-2K simulations"
scripts/sim.sh
