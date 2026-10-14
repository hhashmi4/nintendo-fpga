#!/usr/bin/env python3
"""Convert and recheck actual production renderer simulation dumps."""
from pathlib import Path
from scripts.verify_console_capture import png
from verification.console_video import console_pixels, visual_fixtures


def main():
    root = Path("build/phase8b")
    for number, (status, focus, splash, phase) in enumerate(visual_fixtures()):
        actual = [int(word, 16) for word in (root / f"ui-{number}.hex").read_text().split()]
        expected = console_pixels(status, 0xA5, True, focus=focus, splash=splash, phase=phase)
        assert actual == expected, f"renderer dump {number} differs from independent reference"
        png(root / f"ui-{number}.png", actual)
    print(f"Rendered {len(visual_fixtures())} inspectable PNGs from verified RTL RGB dumps in {root}")


if __name__ == "__main__":
    main()
