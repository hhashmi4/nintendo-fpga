#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! python3 -m pytest --version >/dev/null 2>&1; then
    echo "ERROR: pytest is required. Install the pinned development dependencies:" >&2
    echo "       python3 -m pip install -r requirements-dev.txt" >&2
    exit 1
fi

echo "[1/4] Python reference and Phase 4F-E/F loader/MMIO tests"
python3 scripts/generate_runtime_loader_mmio_defs.py --check
python3 -m pytest

echo "[2/4] Verilator RTL lint"
scripts/lint.sh

echo "[3/4] Verilator platform, PPU, CPU, Phase 3J-4F-F system/cartridge/controller/DMA/video/debug/loader/MMIO, ALU, address, and Phase 2D-2K simulations"
scripts/sim.sh

echo "[4/4] Phase 4E-E debugger command CDC, execution control, and playable integration"
scripts/test_debug_command_cdc.sh
scripts/test_debugger.sh
