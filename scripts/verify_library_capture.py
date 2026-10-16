#!/usr/bin/env python3
import sys
from pathlib import Path
from verification.library_video import fixtures, library_pixels
from scripts.verify_console_capture import png

root=Path('build/phase8c')
if '--unit' in sys.argv:
    for i,(packet,status) in enumerate(fixtures()):
        actual=[int(p,16) for p in (root/f'library-{i}.hex').read_text().split()]
        assert actual==library_pixels(packet,status)
        png(root/f'library-{i}.png',actual)
    print('Converted 20 verified RTL library frames to PNG')
else:
    for name,w,h in [('vga',640,480),('hdmi',1280,720)]:
        status,packet=[int(p,16) for p in (root/f'{name}-library-status.txt').read_text().split()]
        assert status&15==1 and packet&255==1 and (packet>>8)&511==5
        canvas=library_pixels(packet,status)
        expected=canvas if name=='vga' else [canvas[(y-120)*640+x-320] if 320<=x<960 and 120<=y<600 else 0 for y in range(h) for x in range(w)]
        actual=[int(p,16) for p in (root/f'{name}-library.hex').read_text().split()]
        assert actual==expected,f'{name} production library pixel mismatch'
        png(root/f'production-{name}-library.png',actual,w,h)
        print(f'PASS: Phase 8C production {name} library {len(actual)} exact output pixels')
