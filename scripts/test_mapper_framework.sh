#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build/verilator/mapper_framework
verilator --binary --timing --assert --Wall -Wno-BLKSEQ -j 4 \
    --Mdir build/verilator/mapper_framework --top-module mapper_framework_tb \
    -o mapper_framework_tb rtl/cartridge/nes_mapper0_address.sv \
    rtl/cartridge/nes_mapper.sv sim/mapper_framework_tb.sv
build/verilator/mapper_framework/mapper_framework_tb
verilator --binary --timing --assert --Wall -Wno-BLKSEQ -Wno-PINCONNECTEMPTY -j 4 \
    --Mdir build/verilator/mapper_lifecycle --top-module mapper_lifecycle_tb \
    -o mapper_lifecycle_tb rtl/loader/nes_runtime_loader_pkg.sv \
    rtl/loader/nes_runtime_loader.sv rtl/cartridge/nes_mapper0_address.sv \
    rtl/cartridge/nes_mapper.sv rtl/cartridge/nes_runtime_cartridge_storage.sv \
    rtl/cartridge/nes_runtime_mapper.sv rtl/cartridge/nes_runtime_cartridge.sv \
    sim/mapper_lifecycle_tb.sv
build/verilator/mapper_lifecycle/mapper_lifecycle_tb
