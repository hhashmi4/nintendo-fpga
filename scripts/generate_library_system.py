#!/usr/bin/env python3
"""Discover original redistributable ROMs and publish production page payloads."""
from pathlib import Path
from scripts.generate_phase6g_system import system_prg
from scripts.generate_phase4b_fixtures import make_ines
from scripts.generate_phase4fg_runtime_boot import game_a_chr, game_b_prg
from software.nes_loader.library import GameLibrary
from software.nes_console.library_protocol import page_words

root=Path('build/phase8c/games');root.mkdir(parents=True,exist_ok=True)
a=make_ines(system_prg(),game_a_chr(),vertical=False)
(root/'01 Signal Test.nes').write_bytes(a)
unsupported=bytearray(a);unsupported[6]|=0x20
(root/'02 Mapper Two.nes').write_bytes(unsupported)
(root/'03 Invalid.nes').write_bytes(b'NOT A ROM')
(root/'04 RAM Demo.nes').write_bytes(make_ines(game_b_prg(),b'',vertical=True))
(root/'05 Long Unicode 星 title for clipping.nes').write_bytes(a)
library=GameLibrary(root);entries=library.scan(limit=256)
assert len(entries)==5 and [e.supported for e in entries]==[True,False,False,True,True]
assert library.load_entry(entries[0]).prg_bytes==system_prg()
for start in (0,4):
    Path(f'build/phase8c/page-{start//4}.hex').write_text(''.join(f'{w:08x}\n' for w in page_words(entries,start)))
print('Phase8C actual discovery produced 5 entries and 2 bounded pages from original generated NROMs')
