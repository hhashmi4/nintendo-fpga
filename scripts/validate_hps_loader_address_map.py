#!/usr/bin/env python3
"""Cross-check both HPS lightweight slaves against their MMIO contracts."""

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
    parser.add_argument("--diagnostic-contract", type=Path, required=True)
    parser.add_argument("--qsys", type=Path, required=True)
    parser.add_argument("--regmap", type=Path, required=True)
    args = parser.parse_args()

    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    diagnostic_contract = json.loads(
        args.diagnostic_contract.read_text(encoding="utf-8")
    )
    qsys_root = ET.parse(args.qsys).getroot()
    regmap_root = ET.parse(args.regmap).getroot()

    if module_parameter(qsys_root, "hps_0", "LWH2F_Enable") != "true":
        raise ValueError("the lightweight HPS-to-FPGA bridge is not enabled")
    if module_parameter(qsys_root, "hps_0", "S2FCLK_USER0CLK_Enable") != "true":
        raise ValueError("the HPS-to-FPGA user clock is not enabled")
    def validate_bridge(
        module_name: str, contract_data: dict[str, object], address_width: str
    ) -> int:
        expected_parameters = {
            "DATA_WIDTH": "32",
            "SYMBOL_WIDTH": "8",
            "ADDRESS_WIDTH": address_width,
            "ADDRESS_UNITS": "SYMBOLS",
        }
        for name, expected in expected_parameters.items():
            actual = module_parameter(qsys_root, module_name, name)
            if actual != expected:
                raise ValueError(
                    f"{module_name}.{name} is {actual!r}, expected {expected!r}"
                )
        connection = qsys_root.find(
            "./connection[@start='hps_0.h2f_lw_axi_master']"
            f"[@end='{module_name}.s0']"
        )
        if connection is None:
            raise ValueError(f"missing lightweight-HPS-to-{module_name} connection")
        base_parameter = connection.find("./parameter[@name='baseAddress']")
        if base_parameter is None:
            raise ValueError(f"{module_name} connection has no base address")
        qsys_offset = integer(base_parameter.attrib["value"])
        contract_offset = integer(contract_data["slave_offset"])
        if qsys_offset != contract_offset:
            raise ValueError(
                f"{module_name} offset {qsys_offset:#x} != contract "
                f"{contract_offset:#x}"
            )
        span = integer(contract_data["span_bytes"])
        if span > (1 << int(address_width)):
            raise ValueError(f"{module_name} span exceeds its bridge address width")
        registers = contract_data.get("registers", {})
        offsets = [integer(value) for value in registers.values()]
        if len(offsets) != len(set(offsets)):
            raise ValueError(f"{module_name} contract has duplicate registers")
        if any(offset < 0 or offset % 4 or offset + 4 > span for offset in offsets):
            raise ValueError(f"{module_name} contract has an invalid register offset")
        return qsys_offset

    qsys_offset = validate_bridge("loader_mmio_bridge", contract, "6")
    diagnostic_offset = validate_bridge(
        "diagnostic_mmio_bridge", diagnostic_contract, "9"
    )

    loader_end = qsys_offset + integer(contract["span_bytes"])
    diagnostic_end = diagnostic_offset + integer(diagnostic_contract["span_bytes"])
    if max(qsys_offset, diagnostic_offset) < min(loader_end, diagnostic_end):
        raise ValueError("loader and diagnostic MMIO apertures overlap")

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
    diagnostic_base = generated_window + diagnostic_offset
    if diagnostic_end > 0x200000:
        raise ValueError(
            "diagnostic register span exceeds the Cyclone V lightweight window"
        )
    if integer(diagnostic_contract["hps_lightweight_window_base"]) != generated_window:
        raise ValueError("diagnostic contract uses the wrong HPS window")
    print(
        "Validated HPS diagnostic MMIO map: "
        f"window={generated_window:#010x}, slave_offset={diagnostic_offset:#x}, "
        f"physical_base={diagnostic_base:#010x}, "
        f"span={diagnostic_contract['span_bytes']} bytes"
    )


if __name__ == "__main__":
    main()
