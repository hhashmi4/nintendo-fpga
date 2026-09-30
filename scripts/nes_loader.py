#!/usr/bin/env python3
"""Repository entry point for the Phase 4F-E Linux/HPS iNES loader."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from software.nes_loader.cli import run  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(run())
