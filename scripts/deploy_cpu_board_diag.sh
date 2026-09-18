#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="cpu_board_diag"
RBF_PATH="$ROOT_DIR/build/quartus_cpu_board_diag/${PROJECT_NAME}.rbf"

MAC_USER="${MAC_USER:-humzahashmi}"
MAC_HOST="${MAC_HOST:-100.104.79.92}"
MAC_KEY="${MAC_KEY:-$HOME/.ssh/mac_fpga}"
MAC_DIR="${MAC_DIR:-/Users/humzahashmi/fpga/bitstreams}"
MAC_FW="${MAC_FW:-/Users/humzahashmi/fpga/firmware/blaster_6810.hex}"
OPENFPGALOADER="${OPENFPGALOADER:-/opt/homebrew/bin/openFPGALoader}"

cd "$ROOT_DIR"

echo "[1/5] Running complete regression"
scripts/test.sh
echo "[2/5] Building the dedicated Phase 2K board image"
scripts/build_cpu_board_diag_quartus.sh
echo "[3/5] Preparing remote bitstream directory"
ssh -i "$MAC_KEY" "$MAC_USER@$MAC_HOST" "mkdir -p '$MAC_DIR'"
echo "[4/5] Transferring the Phase 2K RBF"
scp -i "$MAC_KEY" "$RBF_PATH" "$MAC_USER@$MAC_HOST:$MAC_DIR/"
echo "[5/5] Volatile Cyclone V programming at JTAG chain index 1"
ssh -i "$MAC_KEY" "$MAC_USER@$MAC_HOST" \
    "$OPENFPGALOADER -c usb-blasterII --probe-firmware '$MAC_FW' --index-chain 1 '$MAC_DIR/${PROJECT_NAME}.rbf'"

echo "PROGRAMMING PASS — PHYSICAL FUNCTIONAL CONFIRMATION REQUIRED"
echo "Expected PASS: LEDR1=1, LEDR2=0, LEDR4=1, LEDR5=1, LEDR7=1, HEX=83F04C"
