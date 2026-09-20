# Phase 3G: PPU sprite renderer

## Objective

Phase 3G turns the eight metadata slots selected by Phase 3F into a logical
sprite-pixel stream. It calculates sprite CHR addresses, reads real pattern
bytes through the Phase 3C cartridge-facing memory path, applies both flip
axes, and implements the eight X counters and pattern-shifter pairs used to
select the first opaque sprite in OAM order.

The result is a sprite candidate for Phase 3H. This phase deliberately does
not mix that candidate with the background, set sprite-zero hit, read the
final palette entry, or generate video.

## Data flow

```text
OAM metadata
    |
    v
tile number + row
    |
    v
CHR address
    |
    v
Cartridge CHR ROM/RAM
    |
    v
low/high pattern bytes
    |
    v
flip logic
    |
    v
X counter + sprite shifters
    |
    v
sprite candidate pixel
    |
    v
Phase 3H mixer
```

`ppu_oam` remains the sole owner of primary and secondary OAM. Its second
read-only secondary-OAM view gives `ppu_sprite_renderer` the selected slot's
Y, tile, attributes, X, original primary-OAM index, and validity. Sprite
artwork is never stored in production renderer RTL. Pattern reads pass through
the integrated PPU memory arbiter and the existing `chr_addr`, `chr_read`, and
`chr_read_data` cartridge interface. Deterministic CHR arrays exist only in
simulation and reference code.

## Fetch window and cadence

Every rendered visible scanline processes exactly eight slots during dots
257-320. Each slot owns eight PPU dots:

| Relative dots | Fetch | Completion |
|---:|---|---|
| 0-1 | first garbage nametable read | relative dot 1 |
| 2-3 | second garbage nametable read | relative dot 3 |
| 4-5 | pattern low byte | relative dot 5 |
| 6-7 | pattern high byte | relative dot 7 |

This preserves the established two-dot memory transaction cadence. Garbage
reads use the current background nametable-fetch address so the external PPU
bus carries a meaningful nametable address. The low and high phases carry the
calculated `$0000-$1FFF` CHR addresses. Pattern data are captured on the
second dot of their transaction. Invalid slots are cleared at the start of
their group and load as invalid with zero pattern data.

The loaded eight-slot state is consumed only on the following raster line.
Background fetches retain dots 1-256, 321-336, and 337-340; ordinary
background work does not use dots 257-320.

## Row and CHR addressing

The renderer uses the Phase 3F convention without a second interpretation of
the OAM Y byte:

```text
relative_row = (evaluation/fetch scanline - OAM Y) modulo 256
```

For an unflipped sprite, the selected row is the relative row. Vertical flip
maps it to `7-relative_row` in 8x8 mode or `15-relative_row` in 8x16 mode.

For 8x8 sprites, PPUCTRL bit 3 selects the pattern table:

```text
low  = {PPUCTRL[3], tile[7:0], 1'b0, selected_row[2:0]}
high = low + 8
```

For 8x16 sprites, PPUCTRL bit 3 is ignored. Tile bit 0 selects `$0000` or
`$1000`; the remaining bits select an even/odd 8x8 tile pair:

```text
selected_tile = (tile & $FE) + selected_row[3]
low  = {tile[0], selected_tile[7:0], 1'b0, selected_row[2:0]}
high = low + 8
```

Applying vertical flip before choosing `selected_row[3]` naturally exchanges
the top and bottom 8x8 tiles and reverses the row inside each tile. Every
generated address remains within `$0000-$1FFF`.

The Python and RTL address tests independently check 16,384 8x8 plane
addresses and 16,384 8x16 plane addresses, 32,768 total. Coverage includes
both 8x8 pattern tables, every tile byte, every legal row, both vertical-flip
states, and both planes. Directed 8x16 checks use tiles `$00`, `$01`, `$7E`,
`$7F`, `$FE`, and `$FF` and prove that PPUCTRL bit 3 has no effect.

## Pattern state and horizontal flip

Each slot has an eight-bit low-plane register, eight-bit high-plane register,
eight-bit X counter, palette bits, background-priority metadata, original OAM
index, and validity bit. Normal NES pattern bytes are consumed MSB first.
Horizontal flip reverses both bytes once at fetch capture, allowing every slot
to use the same MSB-first shifter afterward.

The bit-reversal tests include `$80`, `$40`, `$01`, `$81`, `$AA`, `$55`, and
`$FF`, plus asymmetric two-plane rows. Flip changes artwork orientation only;
the X counter and on-screen starting coordinate do not change.

## X counters and pixel selection

At the end of a slot's fetch group its X counter receives the sprite X byte.
On each enabled visible pixel:

- a nonzero counter decrements and its pattern registers do not shift;
- a zero counter exposes the two current MSBs and shifts both registers;
- after eight shifts, zero fill makes all later pixels transparent.

All counters and shifters are inside the `ppu_enable` state update. A stalled
fabric cycle neither decrements nor shifts. Exhaustive reference tests cover
all 256 starting X values and prove the first possible pixel occurs exactly at
the programmed coordinate, including partial rows at X=248 and X=255.

For every pixel, slots are inspected from 0 through 7. The first valid slot
whose two pattern bits are nonzero wins. A transparent earlier sprite allows a
later opaque sprite through, but no later slot can replace an earlier opaque
one. The output preserves:

- two pattern bits and two sprite-palette bits;
- logical `{palette, pattern}` sprite palette index;
- background-priority attribute bit;
- winning secondary-OAM slot;
- original primary-OAM index;
- `sprite_is_zero`, derived only from original index zero.

Pattern `00` is transparent regardless of all attribute metadata.

## PPUMASK behavior

PPUMASK sprite enable gates the final Phase 3G candidate only. It does not
disable the background pipeline. When sprite display is disabled no opaque
sprite is emitted. When PPUMASK sprite-left enable is clear, visible X=0-7 is
transparent and X=8 onward is unchanged. This is independent of the
background-left control.

The renderer emits logical candidates only for visible coordinates X=0-255,
Y=0-239. Fetch and shifter state may continue to operate according to render
timing, but `sprite_pixel_valid` identifies only the visible stream.

## Memory arbitration

`ppu_background_core` now arbitrates CPU `$2007`, background renderer, and
sprite renderer requests. CPU requests retain deterministic priority. In
ordinary timing the two renderer clients cannot overlap because their dot
windows are disjoint; individual grants identify the owner, and an explicit
conflict signal plus assertions prove that both renderer clients are never
granted together. Renderer accesses are read-only and cannot generate a PPU
memory write.

If CPU `$2007` traffic collides with a rendering read, the CPU wins and the
renderer sees no grant. Cleared sprite bytes remain transparent if a useful
fetch is denied. This is deterministic and verified, but it is not presented
as transistor-level 2C02 render/`$2007` conflict accuracy. Phase 3F's
deterministic active-render `$2004` policy is unchanged.

## Verification

The independent semantic implementation is
`verification/ppu_sprite_render.py`. It models addressing, flips, CHR bytes,
all eight slots, X countdown, shifting, first-opaque selection, metadata,
PPUMASK, and clipping without duplicating RTL statement structure.

Directed Python coverage includes single sprites at X=0, 1, 7, 8, 100, 248,
and 255; asymmetric horizontal flip; every 8x8 and 8x16 vertical row; all X
counters; eight coincident sprites; transparent fall-through; PPUMASK states;
fetch cadence; deterministic 256-pixel scanlines; and primary-OAM selection
feeding CHR-based rendering.

The standalone randomized RTL/reference run uses seed `0x37202601` and checks:

- 186,214 fabric cycles, 153,600 enabled PPU ticks, and 32,612 stalls;
- 3,840 slot loads, 3,584 low captures, 3,589 high captures, and 7,242
  completed dummy transactions;
- 239,563 X-counter decrements and 249,653 sprite shifts;
- 9,036 opaque candidates, 1,094 overlaps, and 2,200 sprite-zero candidates;
- 1,869 deterministic CPU/render memory collisions;
- zero RTL/reference mismatches.

A compact machine-compared fetch trace records scanline, dot, slot, fetch
type, tile, selected row, CHR address, and data without retaining a frame-sized
artifact.

The integrated full-frame test uses seed `0x3F37A6E1` and exercises the real
path from primary OAM through Phase 3F evaluation, secondary OAM, Phase 3G CHR
fetching, and pixel selection. Across 61,440 visible coordinates it reports
4,684 opaque pixels, 56,756 transparent pixels, 89 sprite-zero candidates,
184 clipped candidate pixels, 1,920 slot loads, 1,920 low fetches, 1,920 high
fetches, 3,840 dummy fetches, and zero mismatches. The retained independent
Phase 3E 61,440-pixel background-frame comparison also remains exact.

Assertions cover CHR address range, stall suppression, output gating,
invalid-slot transparency, first-opaque priority, original sprite-zero
identity, read-only renderer behavior, and exclusive renderer ownership.

## Synthesis

The integrated `ppu_sprite_core` fits Cyclone V `5CSEMA5F31C6` with one
50 MHz fabric clock and no PLL:

| Resource/timing | Phase 3F | Phase 3G |
|---|---:|---:|
| ALMs | 1,888 | 2,227 / 32,070 |
| logic ALUTs | 1,273 | 1,824 |
| routing-only ALUTs | 61 | 62 |
| memory ALUTs | 584 | 584 |
| registers | 524 | 796 |
| RAM bits | 18,688 | 18,688 |
| MLABs | 73 | 73 |
| M10K | 0 | 0 |
| DSP | 0 | 0 |
| PLL | 0 | 0 |
| worst setup slack | +4.554 ns | +3.499 ns |
| worst hold slack | +0.169 ns | +0.161 ns |
| setup/hold TNS | 0 / 0 ns | 0 / 0 ns |
| worst minimum pulse-width slack | not retained | +8.626 ns |

All four reported timing corners have positive setup, hold, and minimum
pulse-width slack. The standalone build is
`scripts/build_ppu_phase3g_quartus.sh`.

## Limitations and deferred work

Phase 3G does not implement final background/sprite selection, background
priority application, sprite-zero hit, final palette RAM lookup, NES color to
RGB, VGA/HDMI/framebuffer output, OAM DMA, APU, mapper banking, cartridge
loading, the final CPU/PPU 3:1 scheduler, NMI edge/suppression behavior, or
transistor-level PPU memory conflicts.

Phase 3F intentionally does not evaluate sprites on the pre-render line, so
the first visible scanline has no fabricated sprite data. Phase 3G preserves
that limitation. Phase 2K physical LED/HEX confirmation also remains
outstanding and is not hardware-verified by this work.
