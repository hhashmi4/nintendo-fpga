#!/usr/bin/env python3
"""Independent UI pixel expectations, using the retained Python font table."""

from pathlib import Path

from verification.debug_renderer import FONT_5X8


def main():
    directory = Path("build/phase8a/vectors")
    directory.mkdir(parents=True, exist_ok=True)
    state_names = ["INITIALIZING", "MENU READY", "LOADING", "WAITING FOR GAME FRAME",
                   "GAME ACTIVE", "RETURNING TO MENU", "RECOVERABLE ERROR", "DEVELOPER MODE"]
    for state, state_name in enumerate(state_names):
        # Explicit bench fixture: loader ERROR, runtime selected, unavailable,
        # error 8, epoch 1234, SYSTEM ownership and buttons A5.
        lines = {
            0: "NINTENDO FPGA", 1: "CONSOLE SYSTEM",
            3: "STATE: " + state_name, 5: "VIDEO: SYSTEM",
            6: "GAME READY: 0   RUNTIME: 1", 7: "LOADER: 3       ERROR: 8",
            8: "INPUT OWNER: 0 BUTTONS: A5", 9: "NES RESET: 1   EPOCH: 1234",
            11: "START PLAY / SELECT DEV", 12: "B - RETURN FROM DEVELOPER",
        }
        pixels = [0x382448 if y < 96 else 0xC43B46 if y < 100 else 0x242229
                  for y in range(480) for _ in range(640)]
        # Paint glyphs on a canvas, rather than recreating the RTL pixel mux.
        for row, line in lines.items():
            for column, character in enumerate(line):
                for gy, bits in enumerate(FONT_5X8[character]):
                    for gx, bit in enumerate(bits):
                        if bit == "1":
                            for dy in range(2):
                                for dx in range(2):
                                    x, y = 32 + column * 16 + gx * 2 + dx, 32 + row * 32 + gy * 2 + dy
                                    if x < 640 and y < 480:
                                        pixels[y * 640 + x] = 0xECE5D8
        (directory / f"ui-{state}.hex").write_text("".join(f"{p:06x}\n" for p in pixels))


if __name__ == "__main__":
    main()
