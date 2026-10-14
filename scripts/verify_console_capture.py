#!/usr/bin/env python3
"""Compare actual production VGA/logical HDMI UI pixels with Python."""

from pathlib import Path
import struct
import zlib

from verification.console_video import console_pixels


def png(path: Path, pixels: list[int], width: int = 640, height: int = 480):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    data = b"".join(b"\0" + b"".join(p.to_bytes(3, "big") for p in pixels[y*width:(y+1)*width])
                    for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(data)) + chunk(b"IEND", b""))


def main():
    root = Path("build/phase8a")
    for output in ["vga", "hdmi"]:
        status, buttons, reset = [int(word, 16) for word in (root / f"{output}-ui-status.txt").read_text().split()]
        assert status & 15 == 1 and reset == 1, "capture must prove MENU with NES held reset"
        canvas = console_pixels(status, buttons, bool(reset))
        expected = canvas if output == "vga" else [
            canvas[(y-120)*640+x-320] if 320 <= x < 960 and 120 <= y < 600 else 0
            for y in range(720) for x in range(1280)]
        actual = [int(word, 16) for word in (root / f"{output}-ui.hex").read_text().split()]
        assert len(actual) == len(expected), f"{output} active pixel count"
        for index, (got, want) in enumerate(zip(actual, expected)):
            assert got == want, f"{output} pixel {index}: {got:06x} != {want:06x}"
        if output == "vga":
            png(root / "console-menu.png", actual)
        else:
            png(root / "console-hdmi.png", actual, 1280, 720)
        print(f"PASS: Phase 8A production {output} UI: {len(actual)} independent expected pixels, NES held reset")

    for output, width, height in [("vga",640,480),("hdmi",1280,720)]:
        root=Path("build/phase8b")
        status,buttons,reset,focus,splash,phase=[int(word,16) for word in
            (root/f"{output}-splash-status.txt").read_text().split()]
        assert status & 15 == 1 and reset and splash, "splash must coexist with menu-ready and NES reset"
        canvas=console_pixels(status,buttons,bool(reset),focus=bool(focus),splash=bool(splash),phase=phase)
        expected=canvas if output=="vga" else [
            canvas[(y-120)*640+x-320] if 320<=x<960 and 120<=y<600 else 0
            for y in range(height) for x in range(width)]
        actual=[int(word,16) for word in (root/f"{output}-splash.hex").read_text().split()]
        assert actual==expected, f"{output} simulated splash mismatch"
        png(root/f"production-{output}-splash.png",actual,width,height)
        print(f"PASS: Phase 8B production {output} splash: {len(actual)} exact pixels, menu ready during animation")


if __name__ == "__main__":
    main()
