"""Independent UI canvas expectations; never reads RTL or DUT pixels."""

from .debug_renderer import FONT_5X8


def console_pixels(status: int, buttons: int, held_reset: bool) -> list[int]:
    names = ["INITIALIZING", "MENU READY", "LOADING", "WAITING FOR GAME FRAME",
             "GAME ACTIVE", "RETURNING TO MENU", "RECOVERABLE ERROR", "DEVELOPER MODE"]
    sources = ["SYSTEM", "GAME", "DEVELOPER"]
    lines = {
        0: "NINTENDO FPGA", 1: "CONSOLE SYSTEM",
        3: "STATE: " + names[status & 15],
        5: "VIDEO: " + sources[(status >> 6) & 3],
        6: f"GAME READY: {(status >> 8) & 1}   RUNTIME: {(status >> 9) & 1}",
        7: f"LOADER: {(status >> 10) & 3:X}       ERROR: {(status >> 12) & 15:X}",
        8: f"INPUT OWNER: {(status >> 4) & 3:X} BUTTONS: {buttons:02X}",
        9: f"NES RESET: {int(held_reset)}   EPOCH: {status >> 16:04X}",
        11: "START PLAY / SELECT DEV", 12: "B - RETURN FROM DEVELOPER",
    }
    pixels = [0x382448 if y < 96 else 0xC43B46 if y < 100 else 0x242229
              for y in range(480) for _ in range(640)]
    # Paint complete glyphs onto a canvas, independently of the RTL pixel mux.
    for row, line in lines.items():
        for column, character in enumerate(line):
            for gy, bits in enumerate(FONT_5X8[character]):
                for gx, bit in enumerate(bits):
                    if bit == "1":
                        for dy in range(2):
                            for dx in range(2):
                                x = 32 + column * 16 + gx * 2 + dx
                                y = 32 + row * 32 + gy * 2 + dy
                                if x < 640 and y < 480:
                                    pixels[y * 640 + x] = 0xECE5D8
    return pixels
