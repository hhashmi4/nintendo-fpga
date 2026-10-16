#!/usr/bin/env python3
from pathlib import Path
from verification.library_video import fixtures, library_pixels

root=Path('build/phase8c/vectors');root.mkdir(parents=True,exist_ok=True)
with (root/'fixtures.hex').open('w') as stream:
    for i,(packet,status) in enumerate(fixtures()):
        stream.write(f'{packet:0232x}{status:08x}\n')
        with (root/f'library-{i}.hex').open('w') as output:
            output.writelines(f'{pixel:06x}\n' for pixel in library_pixels(packet,status))
print(f'Generated {len(fixtures())} independent library pixel references')
