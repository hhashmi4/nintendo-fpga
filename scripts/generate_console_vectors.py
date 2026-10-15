#!/usr/bin/env python3
"""Generate independent visual fixtures without reading RTL or DUT output."""
from pathlib import Path
from verification.console_video import console_pixels, visual_fixtures


def main():
    directory=Path('build/phase8b/vectors')
    directory.mkdir(parents=True, exist_ok=True)
    fixtures=visual_fixtures()
    (directory/'fixtures.hex').write_text(''.join(f'{(status<<8)|(phase<<2)|(focus<<1)|splash:010x}\n'
        for status, focus, splash, phase in fixtures))
    for number,(status,focus,splash,phase) in enumerate(fixtures):
        pixels=console_pixels(status,0xA5,True,focus=focus,splash=splash,phase=phase)
        (directory/f'ui-{number}.hex').write_text(''.join(f'{pixel:06x}\n' for pixel in pixels))
        still=console_pixels(status,0xA5,True,focus=focus,splash=False,phase=0)
        (directory/f'ui-still-{number}.hex').write_text(''.join(f'{pixel:06x}\n' for pixel in still))


if __name__ == '__main__':
    main()
