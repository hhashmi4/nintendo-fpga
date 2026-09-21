#!/usr/bin/env python3
"""Rebuild the project-owned Phase 4D-B playable iNES ROM."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.generate_phase4b_fixtures import (  # noqa: E402
    make_ines,
    playable_demo_chr,
    playable_demo_prg,
)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT.nes")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(
        make_ines(playable_demo_prg(), playable_demo_chr(), vertical=False)
    )
    print(f"playable ROM: {output}")


if __name__ == "__main__":
    main()
