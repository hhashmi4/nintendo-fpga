# Project-owned playable ROM

`phase4db_playable_nrom128.nes` is generated specifically for this repository
by `scripts/generate_phase4db_playable_rom.py`. Its program, graphics, and
binary image are licensed under the MIT license in this directory. It contains
no commercial Nintendo program or graphics data.

Rebuild the byte-identical iNES image with:

```bash
python3 scripts/generate_phase4db_playable_rom.py \
  roms/phase4db_playable_nrom128.nes
```

The ROM is an NROM-128 image with 16 KiB PRG ROM, 8 KiB CHR ROM, horizontal
mirroring, VBlank NMI, per-frame OAM DMA, background tiles, one player sprite,
and bounded movement. Press Start to reveal the player. The D-pad moves it; A
and Select choose persistent sprite palettes; B chooses the action sprite.
