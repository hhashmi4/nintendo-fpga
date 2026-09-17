#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="nintendo_fpga"
RBF_PATH="$ROOT_DIR/build/quartus/${PROJECT_NAME}.rbf"

MAC_USER="${MAC_USER:-humzahashmi}"
MAC_HOST="${MAC_HOST:-100.104.79.92}"
MAC_KEY="${MAC_KEY:-$HOME/.ssh/mac_fpga}"
MAC_DIR="${MAC_DIR:-/Users/humzahashmi/fpga/bitstreams}"
MAC_FW="${MAC_FW:-/Users/humzahashmi/fpga/firmware/blaster_6810.hex}"
OPENFPGALOADER="${OPENFPGALOADER:-/opt/homebrew/bin/openFPGALoader}"

cd "$ROOT_DIR"

echo "[1/5] Running software verification"
scripts/test.sh

echo "[2/5] Compiling Quartus project and generating RBF"
scripts/build_quartus.sh

echo "[3/5] Preparing remote bitstream directory"
ssh -i "$MAC_KEY" "$MAC_USER@$MAC_HOST" "mkdir -p '$MAC_DIR'"

echo "[4/5] Transferring RBF over Tailscale/SSH"
scp -i "$MAC_KEY" "$RBF_PATH" "$MAC_USER@$MAC_HOST:$MAC_DIR/"

echo "[5/5] Programming Cyclone V at JTAG chain index 1"
ssh -i "$MAC_KEY" "$MAC_USER@$MAC_HOST" \
    "$OPENFPGALOADER -c usb-blasterII --probe-firmware '$MAC_FW' --index-chain 1 '$MAC_DIR/${PROJECT_NAME}.rbf'"

echo "Platform diagnostic programmed successfully."
