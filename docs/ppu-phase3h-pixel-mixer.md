# Phase 3H: PPU pixel mixer and palette lookup

## Objective

Phase 3H combines the logical background candidate from Phase 3E with the
logical sprite candidate from Phase 3G, selects the NES palette address, reads
the existing Phase 3C palette RAM, and emits a video-facing logical pixel. It
also generates sprite-zero hit and connects that event to the existing
PPUSTATUS bit-6 latch.

```text
Background pixel ----\
                      > Pixel mixer -> Palette RAM -> NES color
Sprite pixel --------/
```

The boundary exported for later video work is deliberately small:
`final_pixel_valid`, X/Y, a six-bit NES color code, and three emphasis bits.
The future VGA and HDMI paths do not need to understand CHR, nametables,
scrolling, OAM, or sprite priority.

## Inputs and ownership

`ppu_pixel_mixer` consumes the already-generated Phase 3E and Phase 3G
candidates. It does not fetch CHR artwork, update scrolling, evaluate OAM, or
duplicate either rendering pipeline.

The background input contains pattern and attribute-palette bits, opacity,
validity, and coordinates. The sprite input contains pattern and
sprite-palette bits, opacity, front/behind priority, original primary-OAM
identity, winning secondary slot, validity, and coordinates. Both upstream
pipelines already apply their independent PPUMASK enable and left-edge rules;
the mixer qualifies those controls again at its architectural boundary so a
suppressed candidate cannot affect source selection or sprite-zero hit.

## Transparency and priority

The selection table is explicit:

| Background | Sprite | Selected source |
|---|---|---|
| transparent | transparent | universal background |
| opaque | transparent | background |
| transparent | opaque | sprite, for either priority attribute |
| opaque | opaque | sprite when front, background when behind |

Pattern `00` is always transparent, even if an upstream opacity flag is set.
The behind-background attribute matters only when both candidates are opaque;
it cannot hide a sprite behind a transparent background pixel.

If both candidates are transparent, the mixer selects `$3F00`. This is a real
lookup of the universal-background palette entry, not a hard-coded color-zero
result.

## Palette addressing and lookup

Opaque background pixels select:

```text
$3F00 | (background_palette << 2) | background_pattern
```

This yields `$3F01-$3F03`, `$3F05-$3F07`, `$3F09-$3F0B`, or
`$3F0D-$3F0F`. Opaque sprite pixels similarly select:

```text
$3F10 | (sprite_palette << 2) | sprite_pattern
```

This yields `$3F11-$3F13`, `$3F15-$3F17`, `$3F19-$3F1B`, or
`$3F1D-$3F1F`. Transparent pattern-zero entries never become visible colors.

`ppu_memory` remains the single RTL owner of palette storage. Phase 3H adds a
read-only rendering view of that same array and reuses the authoritative Phase
3C canonical-index function, so `$3F10/$14/$18/$1C` continue to alias
`$3F00/$04/$08/$0C`. CPU writes and storage semantics are unchanged. Quartus
implements the extra asynchronous read view with one additional 192-bit MLAB
copy; it is not separate writable architectural state.

Palette RAM continues to store eight-bit bytes. Normal output takes bits 5:0.
When PPUMASK grayscale is set, the final interpretation is
`palette_byte[5:0] & $30`, matching the NES palette mask while leaving the
stored byte untouched. PPUMASK bits 7:5 are forwarded as blue, green, and red
emphasis metadata; Phase 3H does not attempt analog or RGB emphasis modeling.

## Visible output

A final pixel pulse requires an enabled PPU tick, visible timing, matching
valid background and sprite coordinates, X in 0-255, and Y in 0-239. The
output stream therefore has exactly 61,440 events per complete visible frame.
Fetch-only, post-render, vblank, and pre-render cycles produce no final pixel.
When `ppu_enable` is low the combinational output and hit event are suppressed,
so a fabric stall cannot duplicate an event or advance either upstream
renderer.

The interface also exposes palette address, selected source, winning sprite
slot, and winning sprite-zero identity as optional debug metadata. These are
not required by a future video protocol.

## Sprite-zero hit

The event is independent of the displayed winner. It occurs only when all of
the following are true on an enabled visible pixel:

- the mask-qualified background candidate is opaque and pattern-nonzero;
- the mask-qualified sprite candidate is opaque and pattern-nonzero;
- the candidate carries original primary-OAM index zero;
- background and sprite rendering are enabled;
- any X=0-7 candidate is permitted by its respective left-edge mask;
- X is not 255.

Consequently, sprite zero still hits when its priority bit places the displayed
sprite behind an opaque background. A nonzero original OAM sprite never hits,
even if it occupies secondary slot zero. X=254 remains eligible, while X=255
only suppresses the status event and does not suppress the displayed pixel.

The event feeds the existing `ppu_registers` status latch. It sets PPUSTATUS
bit 6 and remains set for the frame. Reading PPUSTATUS clears vblank and the
write toggle as before, but does not clear sprite-zero hit or sprite overflow.
The established pre-render dot-1 clear resets all three status flags
independently.

## Verification

The independent semantic model is `verification/ppu_pixel_mixer.py`. It models
source selection, both palette-address functions, canonical palette aliases,
grayscale, emphasis, visible qualification, left-edge masks, X=255, and the
sprite-zero event without following RTL statement order.

Python tests exhaust all background/sprite opacity, sprite priority, and
sprite-zero combinations; all 24 opaque background/sprite palette addresses;
the eight canonical alias addresses; every left-mask combination at X=0-7;
X=8, X=254, and X=255; representative palette bytes `$00`, `$01`, `$0F`,
`$10`, `$21`, `$2A`, `$30`, `$3F`, and `$FF`; stalls; and coordinate
validity. The complete Python suite passes 587 tests.

The standalone RTL/reference test uses seed `0x38202601` and covers:

- 120,306 fabric cycles, 94,008 enabled PPU ticks, and 26,298 stalls;
- 68,825 final pixels and palette reads;
- 45,878 universal, 11,600 background, and 11,347 sprite selections;
- 246 sprite-zero-hit events and 34,515 grayscale pixels;
- an explicit deterministic 256-pixel scanline;
- zero RTL/reference mismatches.

The deterministic integrated scene uses seed `0x3F38A6E1` and stall seed
`0x38A1105E`. It loads only simulation-side CHR, CIRAM, OAM, and palette
contents, then exercises the actual Phase 3A timing, Phase 3D scrolling, Phase
3C memory, Phase 3E background, Phase 3F evaluation, Phase 3G sprite renderer,
Phase 3H mixer, and palette RAM path. The scene includes several background
palettes and patterns, left-edge content, front and behind sprites, overlaps,
flips, sprite-zero crossing, an X=255 overlap, and sprite overflow.

Across 102,055 fabric cycles it observes 81,756 enabled PPU ticks and 20,299
stalls. All 61,440 visible pixels and palette reads match: 23,126 universal,
37,583 background, and 731 sprite winners. The 36 sprite-zero events all
include the deliberate behind-background overlap, proving that display
priority does not gate the hit. Grayscale is covered by the standalone random
run; this frame keeps it disabled. Coordinate, source, palette address, color,
emphasis, hit event, status persistence/read behavior, overflow independence,
vblank independence, and pre-render clearing have zero mismatches.

The retained Phase 3E 61,440-pixel background frame, Phase 3G 61,440-coordinate
sprite frame, exhaustive 591,876-vector ALU run, exhaustive 1,508,186-vector
CPU address run, and all Phase 1 through Phase 3G regressions remain exact.

Assertions cover palette range, all four transparency/priority rules,
behind-priority over transparency, invalid/stalled output suppression,
sprite-zero identity, and X=255 exclusion.

## Synthesis

The integrated `ppu_sprite_core` fits Cyclone V `5CSEMA5F31C6` with exactly
one 50 MHz fabric clock and no PLL:

| Resource/timing | Phase 3G | Phase 3H |
|---|---:|---:|
| ALMs | 2,227 | 2,297 / 32,070 |
| logic ALUTs | 1,824 | 1,873 |
| routing-only ALUTs | 62 | 65 |
| memory ALUTs | 584 | 590 |
| registers | 796 | 796 |
| MLAB RAM bits | 18,688 | 18,880 |
| MLABs | 73 | 74 |
| M10K | 0 | 0 |
| DSP | 0 | 0 |
| PLL | 0 | 0 |
| worst setup slack | +3.499 ns | +3.740 ns |
| worst hold slack | +0.161 ns | +0.158 ns |
| setup/hold TNS | 0 / 0 ns | 0 / 0 ns |
| worst minimum pulse-width slack | not retained | +8.625 ns |

All timing corners have positive setup, hold, and minimum-pulse-width slack.
The Phase 3H build is `scripts/build_ppu_phase3h_quartus.sh`. Retained Phase
3E, integrated PPU, standalone CPU, Phase 1 board, and Phase 2K diagnostic
builds also pass.

## Video modularity and limitations

The logical stream can feed independent future output modules:

```text
PPU final pixel stream
        |
        +--> future VGA output module
        |
        +--> future HDMI output module
```

A VGA-to-HDMI converter likewise requires no change to the PPU stream. This
phase does not implement RGB conversion, analog NTSC composite generation,
VGA timing or DAC pins, native HDMI, a framebuffer, exact analog emphasis,
OAM DMA `$4014`, APU, mapper banking, cartridge loading/parsing, the final
CPU/PPU 3:1 scheduler, completed NMI edge/suppression races, or
transistor-level PPU bus conflicts.

Phase 3F's intentional lack of pre-render sprite evaluation remains, so no
sprite data are fabricated for the first visible line. Phase 2K physical
LED/HEX confirmation also remains outstanding and is not hardware-verified by
this work.
