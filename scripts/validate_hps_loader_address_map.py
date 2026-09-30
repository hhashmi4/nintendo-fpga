#!/usr/bin/env python3
"""Cross-check the generated Platform Designer map against the MMIO contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def integer(value: object) -> int:
    return int(str(value), 0)


def module_parameter(root: ET.Element, module_name: str, name: str) -> str:
    module = root.find(f"./module[@name='{module_name}']")
    if module is None:
        raise ValueError(f"missing Platform Designer module {module_name!r}")
    parameter = module.find(f"./parameter[@name='{name}']")
    if parameter is None:
        raise ValueError(f"missing {module_name}.{name} parameter")
    return parameter.attrib["value"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--qsys", type=Path, required=True)
    parser.add_argument("--regmap", type=Path, required=True)
    args = parser.parse_args()

    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    qsys_root = ET.parse(args.qsys).getroot()
    regmap_root = ET.parse(args.regmap).getroot()

    if module_parameter(qsys_root, "hps_0", "LWH2F_Enable") != "true":
        raise ValueError("the lightweight HPS-to-FPGA bridge is not enabled")
    if module_parameter(qsys_root, "hps_0", "S2FCLK_USER0CLK_Enable") != "true":
        raise ValueError("the HPS-to-FPGA user clock is not enabled")
    expected_parameters = {
        "DATA_WIDTH": "32",
        "SYMBOL_WIDTH": "8",
        "ADDRESS_WIDTH": "6",
        "ADDRESS_UNITS": "SYMBOLS",
    }
    for name, expected in expected_parameters.items():
        actual = module_parameter(qsys_root, "loader_mmio_bridge", name)
        if actual != expected:
            raise ValueError(
                f"loader_mmio_bridge.{name} is {actual!r}, expected {expected!r}"
            )

    connection = qsys_root.find(
        "./connection[@start='hps_0.h2f_lw_axi_master']"
        "[@end='loader_mmio_bridge.s0']"
    )
    if connection is None:
        raise ValueError("missing lightweight-HPS-to-loader Avalon connection")
    base_parameter = connection.find("./parameter[@name='baseAddress']")
    if base_parameter is None:
        raise ValueError("Platform Designer connection has no base address")
    qsys_offset = integer(base_parameter.attrib["value"])
    contract_offset = integer(contract["slave_offset"])
    if qsys_offset != contract_offset:
        raise ValueError(
            f"Qsys slave offset {qsys_offset:#x} != contract {contract_offset:#x}"
        )

    lightweight_peripherals = [
        peripheral
        for peripheral in regmap_root.findall("./peripherals/peripheral")
        if (peripheral.findtext("name") or "").endswith("_lwfpgaslaves")
    ]
    if len(lightweight_peripherals) != 1:
        raise ValueError(
            "generated register map must contain exactly one lwfpgaslaves window"
        )
    generated_window = integer(
        lightweight_peripherals[0].findtext("baseAddress") or ""
    )
    contract_window = integer(contract["hps_lightweight_window_base"])
    if generated_window != contract_window:
        raise ValueError(
            f"generated HPS window {generated_window:#x} != contract "
            f"{contract_window:#x}"
        )

    physical_base = generated_window + qsys_offset
    if physical_base + integer(contract["span_bytes"]) > generated_window + 0x200000:
        raise ValueError("loader register span exceeds the Cyclone V lightweight window")
    print(
        "Validated HPS loader MMIO map: "
        f"window={generated_window:#010x}, slave_offset={qsys_offset:#x}, "
        f"physical_base={physical_base:#010x}, span={contract['span_bytes']} bytes"
    )


if __name__ == "__main__":
    main()
