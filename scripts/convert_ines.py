#!/usr/bin/env python3
"""Convert a validated Mapper 0 iNES image into FPGA build artifacts."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ines import INESError, convert_ines  # noqa: E402


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.nes OUTPUT_PREFIX")
    try:
        outputs = convert_ines(sys.argv[1], sys.argv[2])
    except INESError as error:
        raise SystemExit(f"ERROR: {error}") from error
    for kind, path in outputs.items():
        print(f"{kind}: {path}")


if __name__ == "__main__":
    main()
