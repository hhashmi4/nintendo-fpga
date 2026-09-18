#!/usr/bin/env python3
"""Convert Intel HEX to the flat readmemh format used by cpu_program_tb."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.cpu_program import load_intel_hex, write_readmemh  # noqa: E402


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.hex OUTPUT.mem")
    write_readmemh(load_intel_hex(sys.argv[1]), sys.argv[2])


if __name__ == "__main__":
    main()
