#!/usr/bin/env python3
"""Original runtime ROMs and software MMIO plans for the production-top test."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.generate_phase4b_fixtures import Program, make_ines, put
from scripts.generate_phase4fg_runtime_boot import (
    game_a_prg, game_a_chr, game_b_prg, create_transport,
    write_valid_trace, write_failed_replacement_trace,
)
from verification.video import palette_rgb
from verification.shared_video import scale_720p


def system_prg() -> bytes:
    """Retain the owned checkerboard ROM; add five-channel audio and both pads."""
    prg = bytearray(game_a_prg())
    original_entry = bytes(prg[:5])
    prg[:5] = bytes((0x4C, 0x00, 0x83, 0xEA, 0xEA))
    setup = Program(0x8300)
    setup.emit(*original_entry)
    registers = (
        (0x4017, 0x40), (0x4015, 0x0F),
        (0x4000, 0xBF), (0x4002, 0xFD), (0x4003, 0x08),
        (0x4004, 0x7C), (0x4006, 0xA9), (0x4007, 0x08),
        (0x4008, 0xFF), (0x400A, 0x7E), (0x400B, 0x08),
        (0x400C, 0x3A), (0x400E, 0x04), (0x400F, 0x08),
        (0x4010, 0x4F), (0x4011, 0x40), (0x4012, 0x80),
        (0x4013, 0x01), (0x4015, 0x1F),
    )
    for address, value in registers:
        setup.emit(0xA9, value, 0x8D, address & 255, address >> 8)
    setup.emit(0x4C, 0x05, 0x80)
    put(prg, 0x8300, setup.resolve())
    signature = bytes.fromhex("a9018d1640a9008d1640ad1640")
    offset = prg.index(signature)
    prg[offset:offset+3] = bytes((0x4C, 0x00, 0x84))
    pads = Program(0x8400)
    pads.label("poll")
    pads.emit(0xA9, 1, 0x8D, 0x16, 0x40, 0xA9, 0, 0x8D, 0x16, 0x40)
    pads.emit(0xA2, 8)
    pads.label("bit")
    for port, destination in ((0x16, 0x30), (0x17, 0x31)):
        pads.emit(0xAD, port, 0x40, 0x4A, 0x66, destination)
    pads.emit(0xCA)
    pads.branch(0xD0, "bit")
    pads.emit(0xA5, 0x30, 0x85, 0x32, 0xA5, 0x31, 0x85, 0x33)
    pads.emit(0xA5, 0x30, 0x29, 1, 0x85, 0x11)
    pads.absolute(0x4C, "poll")
    put(prg, 0x8400, pads.resolve())
    put(prg, 0xA000, bytes.fromhex("55aa0ff033cc699687781ee14bb425da5a"))
    return bytes(prg)


def generate(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    a, b = output / "game_a.nes", output / "game_b.nes"
    a.write_bytes(make_ines(system_prg(), game_a_chr(), vertical=False))
    b.write_bytes(make_ines(game_b_prg(), b"", vertical=True))
    context = create_transport()
    write_valid_trace(a, output / "game_a.mmio", context)
    write_failed_replacement_trace(a, output / "failed_replacement.mmio", context)
    write_valid_trace(b, output / "game_b.mmio", context)
    write_valid_trace(a, output / "reload_a.mmio", context)
    for name, width, height in (("vga", 640, 480), ("hdmi", 1280, 720)):
        with (output / f"{name}.hex").open("w") as stream:
            for y in range(height):
                for x in range(width):
                    if name == "vga":
                        enabled, nx, ny = 64 <= x < 576, (x - 64) // 2, y // 2
                    else:
                        sample = scale_720p(x, y)
                        enabled, nx, ny = sample.nes, sample.nes_x, sample.nes_y
                    color = 1 if (nx + ny) % 2 else 15
                    rgb = palette_rgb(color, 0) if enabled else (0, 0, 0)
                    stream.write(bytes(rgb).hex() + "\n")
    print("Phase6G owned NROM128/audio/two-pad + NROM256/CHR-RAM MMIO plans generated")


if __name__ == "__main__":
    generate(Path("build/phase6g/system"))
