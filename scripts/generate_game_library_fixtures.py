#!/usr/bin/env python3
"""Generate an original mixed Phase 4F-H game-library fixture."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.runtime_loader_fixtures import write_game_library  # noqa: E402


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: generate_game_library_fixtures.py OUTPUT_DIR", file=sys.stderr)
        return 2
    for path in write_game_library(sys.argv[1]).values():
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
