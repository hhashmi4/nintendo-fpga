"""Static qualification of the generated Phase 2K board diagnostic."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_generated_board_diagnostic_rom_is_current() -> None:
    subprocess.run(
        [sys.executable, "scripts/generate_cpu_board_diag_program.py", "--check"],
        cwd=ROOT,
        check=True,
    )


def test_board_program_contains_required_instruction_families() -> None:
    include = (ROOT / "rtl/diagnostic/cpu_board_diag_program.svh").read_text(
        encoding="ascii"
    )
    comments = set(re.findall(r"// [0-9A-F]{4}: ([A-Z]+)", include))
    required = {
        "LDA", "LDX", "LDY", "STA", "TAX", "TAY", "TXA", "TYA",
        "TSX", "TXS", "ADC", "SBC", "AND", "ORA", "EOR", "BIT",
        "CMP", "CPX", "CPY", "INC", "DEC", "INX", "INY", "DEX",
        "DEY", "ASL", "LSR", "ROL", "ROR", "BCC", "BCS", "BEQ",
        "BMI", "BNE", "BVC", "BVS", "PHA", "PLA", "PHP", "PLP",
        "JSR", "RTS", "JMP", "BRK", "RTI", "CLC", "SEC", "CLI",
        "SEI", "CLV", "CLD", "SED", "NOP",
    }
    assert required <= comments


def test_phase2k_pin_map_is_complete_and_unique() -> None:
    qsf = (ROOT / "quartus/cpu_board_diag.qsf").read_text(encoding="ascii")
    assert 'set_global_assignment -name DEVICE 5CSEMA5F31C6' in qsf
    assert 'set_global_assignment -name TOP_LEVEL_ENTITY cpu_board_diag_top' in qsf

    outputs = re.findall(
        r"set_location_assignment (PIN_[A-Z0-9]+) -to ((?:LEDR|HEX[0-5])\[\d+\])",
        qsf,
    )
    assert len(outputs) == 52
    assert len({signal for _, signal in outputs}) == 52
    assert len({pin for pin, _ in outputs}) == 52
    assert "set_location_assignment PIN_AF14 -to CLOCK_50" in qsf
    assert "set_location_assignment PIN_AA14 -to KEY0" in qsf
    assert "set_location_assignment PIN_AB12 -to SW0" in qsf
