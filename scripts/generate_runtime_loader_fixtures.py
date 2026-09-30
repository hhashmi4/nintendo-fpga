#!/usr/bin/env python3
"""Generate original synthetic Phase 4F-E iNES fixtures."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.runtime_loader_fixtures import (  # noqa: E402
    write_valid_runtime_images,
)


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: generate_runtime_loader_fixtures.py OUTPUT_DIR",
            file=sys.stderr,
        )
        return 2
    for path in write_valid_runtime_images(sys.argv[1]):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
