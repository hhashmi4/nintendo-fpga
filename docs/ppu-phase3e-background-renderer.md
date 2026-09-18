# Phase 3E: PPU background renderer

## Objective

Phase 3E turns the verified Phase 3A timing, Phase 3C memory map, and Phase 3D
scroll address into a cycle-scheduled digital NES background pixel stream. It
adds the nametable, attribute, and pattern fetch pipeline; tile latches; rolling
pattern and attribute shifters; fine-X selection; and PPUMASK background gates.
It does not add sprites or a final video signal.

## Architecture

```text
 Phase 3A timing       Phase 3B registers       Phase 3D scroll
 dot / scanline       PPUCTRL / PPUMASK           v / x
        |                       |                    |
        +-----------------------+--------------------+
                                |
                        +-------v--------+
                        | background     |
                        | fetch schedule |
                        +-------+--------+
                                |
                    renderer memory request
                                |
 CPU $2007 request --->+--------v---------+
                       | CPU-priority     |
                       | memory arbiter   |
                       +--------+---------+
                                |
                    +-----------v-----------+
                    | Phase 3C PPU memory   |
                    | CIRAM / CHR routing   |
                    +-----------+-----------+
                                |
                 tile ID / attribute / patterns
                                |
                    +-----------v-----------+
                    | four 16-bit shifters  |
                    +-----------+-----------+
                                | fine x
                         logical BG pixel
```

`ppu_background` owns only fetch latches and background shifters. The existing
`ppu_registers` block remains the single sequential owner of `v/t/x/w`, and
the Phase 3A, 3B, 3C, and 3D RTL is unchanged. `ppu_background_core` composes
the existing `ppu_core`, `ppu_memory`, and the new renderer around one fabric
`clk`. No generated clock or PLL is used. Every renderer request, capture,
shift, and load requires `ppu_enable`.

## Memory latency and fetch sequence

Phase 3C CIRAM and CHR inputs have an unregistered combinational read path;
Quartus continues to infer CIRAM/palette as asynchronous-read MLAB memory.
Phase 3E deliberately presents each address for a two-enabled-dot pair and
captures on the second dot. This represents the NES two-dot fetch cadence and
leaves an explicit address phase before every capture:

```text
dot modulo 8:   1        2       3       4       5       6       7       0
operation:     NT addr  NT cap  AT addr  AT cap  PL addr  PL cap  PH addr  PH cap/load
```

Named phase constants define this schedule. The main windows are dots 1-256
and 321-336 on visible scanlines 0-239 and pre-render scanline 261. Shifters
advance on every enabled dot in these windows. Pattern-high capture and tile
load occur together at dots 8, 16, ..., 256, 328, and 336, aligned with the
already verified Phase 3D coarse-X increments. The newly captured high plane
is forwarded to the load on that edge; nonblocking assignment order cannot
accidentally load the prior tile's high byte.

Dots 257-320 remain available for the future sprite pipeline. Dots 337-340
produce two complete dummy nametable bus reads, captured on dots 338 and 340;
they intentionally do not change tile latches or shifters.

## Addresses and fetched state

Nametable and attribute addresses use the Phase 3D verified helpers:

```text
NT = $2000 | (v & $0FFF)

AT = $23C0
   | (v & $0C00)
   | ((v >> 4) & $0038)
   | ((v >> 2) & $0007)
```

Because these requests go through `ppu_memory`, CIRAM accesses naturally obey
vertical, horizontal, single-screen-lower, and single-screen-upper mirroring.
The attribute quadrant is selected from coarse-X bit 1 and coarse-Y bit 1:

```text
Y X   quadrant       attribute bits
0 0   top-left       1:0
0 1   top-right      3:2
1 0   bottom-left    5:4
1 1   bottom-right   7:6
```

PPUCTRL bit 4 selects pattern table `$0000` or `$1000`. For tile ID `n`, fine
Y `y`, and plane `p`, the CHR address is:

```text
base + n * 16 + y + p * 8
```

It always lies in `$0000-$1FFF` and is visible on the production cartridge CHR
interface. There is no production CHR array in the PPU.

The fetch latches are `next_tile_id`, `next_tile_attribute`,
`next_tile_pattern_low`, and `next_tile_pattern_high`. A completed eight-dot
group commits the pattern bytes and eight replicated attribute bits to the
future half of the shifters without overwriting the active pixels.

## Shifters and pixels

Two 16-bit pattern shifters carry the low and high CHR planes. Two more 16-bit
shifters carry the low and high attribute palette bits. Every tile load fills
the low/future byte; the high byte remains the active eight-pixel slice after
the same-edge shift. NES bit orientation is MSB first: CHR bit 7 is the first
pixel and bit 0 is the eighth.

Fine X remains the Phase 3B/3D three-bit `x` state. It does not increment; it
selects shifter bit `15-x`. The logical outputs are:

- `bg_pattern[1:0]`: two CHR pattern-plane bits;
- `bg_palette[1:0]`: selected attribute palette, zero when transparent;
- `bg_opaque`: true only for an enabled, unclipped nonzero pattern;
- `bg_index[3:0]`: `{palette, pattern}` for opaque pixels, otherwise zero;
- `bg_pixel_valid`, `bg_x`, and `bg_y`: Phase 3A visible coordinates only.

PPUMASK bit 3 enables background pixels. PPUMASK bit 1 independently enables
background in X=0-7. With the main background bit clear, or with the left bit
clear at X=0-7, the output is transparent and zero. Sprite-only rendering still
keeps the timing, scroll, and fetch pipeline active through the established
overall `background || sprites` rendering condition, but it never emits an
opaque background pixel.

Pre-render dots 321-336 load the two tiles needed at the start of scanline 0;
every visible line performs the same prefetch for the following line. Tests
start from reset and obtain the first scanline through this real pipeline; no
shifter pixel data is preloaded by the testbench.

## CPU/renderer memory arbitration

The Phase 3C storage remains one logical PPU memory port. If an accepted CPU
`$2007` access and renderer request coincide, the CPU request has priority.
The renderer still reports its scheduled request and a collision, but it is
not granted and captures no memory value. A high-plane collision at a load
boundary deterministically loads the last successfully captured high byte.
CPU writes remain exactly once and all retained PPUDATA tests keep their prior
semantics.

This policy is deliberately deterministic and extensively reference-checked.
It is not a transistor-level claim for pathological CPU access during active
rendering; exact CPU/render bus conflicts remain deferred. The explicit
request/grant/collision boundary also permits a sprite requestor to join the
arbiter in a later phase.

## Verification

`verification/ppu_background.py` is a semantic Python model integrated with
the existing independent timing, register, scroll, and memory models. It
describes the fetch types and pixel rules rather than copying RTL statement
order.

The Python suite adds 10 tests and raises the retained count to 543. It checks:

- all 1,024 attribute-byte/quadrant cases;
- all 8,192 table/tile/fine-Y/plane pattern addresses;
- all 32,768 `v` values for both Phase 3D address helpers;
- bit orientation with `$80`, `$40`, `$01`, `$FF`, `$AA`, `$55`, and `$81`;
- every scanline/dot fetch classification, PPUMASK cases, sprite-only gating,
  nonvisible output, and stall stability.

The standalone RTL/reference trace checks 65,492 rows: the exhaustive helper
sets plus 50,000 deterministic randomized states using seed `0x3E5EED01`. It
observes 6,195 nametable, 3,107 attribute, 2,132 pattern-low, 2,205
pattern-high, and 130 dummy fetch completions; 2,584 loads; 33,521 shifts; and
zero mismatches.

The integrated Phase 3A-3E trace checks 1,075,191 fabric cycles:

- 1,018,972 enabled PPU ticks and 56,215 stalls;
- 87,482 accepted CPU transactions and 9,507 CPU/renderer collisions;
- 89,824 nametable, 89,830 attribute, 89,819 pattern-low, 89,823 pattern-high,
  and 5,258 dummy completed fetches;
- 90,990 tile loads and 727,859 shifter operations;
- 11 frame transitions;
- one exact 61,440-visible-pixel full-frame comparison after a complete
  pre-render warm-up, including all 256 scanline-0 pixels;
- eight scrolling/mirroring frames plus 256 boundary pixels, totaling 491,776
  scrolling-scene pixels across fine X 0-7, both pattern tables, X/Y wraps,
  and all four CIRAM mirroring modes;
- all four dynamic PPUMASK cases;
- zero RTL/reference or compact fetch-trace mismatches.

The randomized portion uses seed `0x3E200701` for 180,000 fabric cycles. It
contains 123,852 PPU ticks, 56,148 stalls, 87,415 accepted CPU transactions,
9,507 collisions, 30,992 principal fetch completions plus 435 dummy
completions, 8,914 tile loads, 71,251 shifts, and 87,364 visible pixel samples.
Assertions cover legal regions, phase/type/address relationships, valid CHR
and CIRAM regions, stalls, grant/collision exclusivity, masking, no renderer
writes, one-destination writes, coordinate validity, and full scenario counts.

Retained Phase 1 through Phase 3D simulation, exhaustive CPU ALU/address tests,
and whole-project Verilator lint remain in `scripts/test.sh` and CI.

## Synthesis

The integrated Phase 3E hierarchy was fitted for Cyclone V `5CSEMA5F31C6`
using one real 50 MHz fabric clock:

- 1,399 ALMs of 32,070 (4%);
- 660 combinational logic ALUTs plus 35 routing-only ALUTs;
- 520 memory ALUTs and 187 registers;
- 16,640 MLAB memory bits in 65 MLABs, with 0 M10Ks;
- 0 DSP blocks and 0 PLLs;
- worst setup slack `+5.526 ns`, setup TNS 0;
- worst hold slack `+0.169 ns`, hold TNS 0;
- worst minimum-pulse-width slack `+8.627 ns`.

Relative to Phase 3D, the renderer adds 194 ALMs, 152 logic ALUTs, 23
routing-only ALUTs, and 90 registers. RAM usage is unchanged: the four
background shifters and fetch latches are registers, while CIRAM and palette
remain in the same inferred MLAB storage. The growth is consistent with the
four 16-bit shifters, fetched-byte state, pixel selection, and bus arbitration.

## Limitations and next phase

Phase 3E does not implement primary or secondary OAM, OAM DMA, sprite
evaluation, sprite overflow generation, sprite fetches or shifters, sprite
priority, sprite zero hit, the final background/sprite mixer, palette-to-RGB,
VGA, HDMI, a framebuffer, composite video, APU, mapper banking, cartridge
loading, the final CPU/PPU scheduler, NMI edges/races, sprite-region dummy bus
activity, or transistor-level CPU/render memory conflicts.

The output is logical background pattern/palette data, not final video. A
later sprite phase can use the preserved dots 257-320 and the explicit memory
request/grant architecture before a final pixel mixer is added.
