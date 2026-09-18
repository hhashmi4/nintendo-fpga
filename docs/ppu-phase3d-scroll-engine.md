# Phase 3D: rendering-time PPU scroll engine

## Objective

Phase 3D adds the cycle-accurate rendering-time updates of the NES PPU loopy
scroll address. It combines Phase 3A timing, Phase 3B CPU programming, and
Phase 3C memory access without adding background fetches, shifters, sprites,
or pixels.

## State and ownership

The established 15-bit `v` and `t` layout is:

```text
yyy NN YYYYY XXXXX
||| || ||||| +---- coarse X: bits 4:0
||| || +---------- coarse Y: bits 9:5
||| |+------------ horizontal nametable: bit 10
||| +------------- vertical nametable: bit 11
+++--------------- fine Y: bits 14:12
```

Fine X remains the separate three-bit `x` register, and `w` remains the shared
CPU `$2005/$2006` write toggle. `ppu_registers` remains the only sequential
owner of `v`, `t`, `x`, and `w`. The new `ppu_scroll` module is purely
combinational: it calculates scheduled next-state values, the active-render
`$2007` increment, event qualifiers, and future fetch-address helpers. This
avoids multiple drivers while leaving the algorithms independently testable.

There is one fabric `clk`. Timing state and automatic scroll operations consume
only edges with `ppu_enable=1`; CPU transactions remain independently gated by
`cpu_enable && cpu_bus_valid`.

## Rendering eligibility and timing

Rendering operations are enabled by the existing Phase 3B condition
`PPUMASK.background_enable || PPUMASK.sprite_enable`. Eligible scanlines are
visible lines 0-239 and the pre-render line 261. Post-render line 240 and
vblank lines 241-260 never perform automatic scrolling.

```text
visible or pre-render scanline

dot:  1 .... 8 .... 16 .... 248  256  257 .... 280 ..... 304 .... 328 .. 336 .. 340
             X++    X++       X++  X++   H copy                    X++    X++
                                   Y++

pre-render line 261 only:
                                             280 ======== 304
                                               vertical t -> v each enabled dot
```

The dot labels are the current Phase 3A coordinates consumed at the active
edge. At dot 256, horizontal increment is applied first and vertical increment
second; the operations touch disjoint fields, so neither result is lost.

## Horizontal increment and reload

Coarse X increments at dots 8, 16, ..., 248, 256, 328, and 336. Values 0-30
increment normally. Value 31 wraps to zero and toggles horizontal nametable bit
`v[10]`; every vertical field is preserved.

At dot 257, `v[4:0] <- t[4:0]` and `v[10] <- t[10]`. Coarse Y, fine Y, and the
vertical nametable bit are preserved.

## Vertical increment and reload

At dot 256, fine Y increments while below seven. On a fine-Y 7 wrap:

- coarse Y 29 becomes 0 and toggles `v[11]`;
- coarse Y 31 becomes 0 without toggling `v[11]`;
- every other coarse Y increments normally, including 30 becoming 31.

During pre-render dots 280-304 inclusive, the engine copies `t[9:5]`, `t[11]`,
and `t[14:12]` into `v` on every enabled PPU dot. Repetition is intentional: a
CPU change to `t` in the window is observed by subsequent eligible dots.

Fine X `x` never increments automatically. It remains the future background
shifter phase selection programmed by the first `$2005` write.

## PPUDATA behavior and deterministic collision priority

Outside visible/pre-render rendering, `$2007` retains the Phase 3B/3C linear
increment of 1 or 32 selected by PPUCTRL bit 2. During an eligible rendering
scanline with either renderer enabled, every accepted `$2007` access instead
applies one coarse-X increment followed by one vertical increment, independent
of PPUCTRL. The memory access itself still uses pre-edge `v[13:0]` and emits
exactly one accepted read or write.

Pathological same-edge CPU/internal conflicts have a deterministic Phase 3D
policy:

1. scheduled scroll logic computes from pre-edge `v` and `t`;
2. an accepted second `$2006` write or `$2007` access has priority for `v`;
3. other CPU writes may update `t/x/w` while the scheduled `v` operation still
   uses the old `t`; repeated pre-render reloads see the new `t` on later dots.

This policy is verified at dots 256, 257, 280-304, 328, and 336. It is not a
claim of transistor-level compatibility for the real PPU's internal bus
conflicts on those exact dots; that remains a later accuracy audit item.

## Future background-fetch helpers

The core exposes, without issuing a memory request:

```text
nametable = $2000 | (v & $0FFF)

attribute = $23C0
          | (v & $0C00)
          | ((v >> 4) & $0038)
          | ((v >> 2) & $0007)
```

Phase 3E can use these addresses for fetch scheduling. Attribute-byte quadrant
selection and palette-bit extraction are not implemented here.

## Verification

The independent behavioral model in `verification/ppu_scroll.py` expresses
field operations semantically and is integrated into the existing register
model. The Python suite adds 13 tests covering all 64 coarse-X/nametable
combinations, all 512 fine-Y/coarse-Y/vertical-nametable combinations, every
one of the 32,768 possible helper-address inputs, copies, timing coordinates,
rendering gates, `$2007` modes, and collision priority.

The standalone RTL/reference trace checks 53,344 cases:

- 64 exhaustive coarse-X cases;
- 512 exhaustive vertical cases;
- 32,768 exhaustive fetch-helper addresses;
- 20,000 directed/random boundary and gating cases with seed `0x3D5EED01`.

The integrated timing/register/memory/scroll trace checks 758,097 fabric
cycles with seeds `0x3D200701` and `0x3D57A110`:

- 660,273 enabled PPU ticks and 97,812 PPU stalls;
- six complete frames, including disabled, background-only, sprite-only,
  combined-rendering, odd rendered, and randomly stalled cases;
- 83,718 accepted CPU transactions;
- 45,830 scroll-register transactions and 22,518 PPUDATA transactions;
- 49,713 automatic X increments and 1,463 automatic Y increments;
- 1,465 horizontal copies and 145 vertical copies;
- 1,306 CPU/internal-operation collision cases;
- zero RTL/reference mismatches and all assertions passing.

Retained Phase 1-3C simulation, CPU exhaustive verification, and whole-project
Verilator lint remain part of `scripts/test.sh` and CI.

## Synthesis

The integrated Phase 3D hierarchy was fitted for Cyclone V `5CSEMA5F31C6`
with one 50 MHz fabric clock:

- 1,205 ALMs of 32,070 (4%);
- 508 combinational logic ALUTs plus 12 routing-only ALUTs;
- 520 memory ALUTs and 97 registers;
- 16,640 MLAB memory bits in 65 MLABs, with 0 M10Ks;
- 0 DSP blocks and 0 PLLs;
- worst setup slack `+10.417 ns`, setup TNS 0;
- worst hold slack `+0.171 ns`, hold TNS 0;
- worst minimum-pulse-width slack `+8.627 ns`.

Relative to Phase 3C, the combinational scroll/address logic adds 72 ALMs and
70 logic ALUTs. Register and memory usage are unchanged because no second copy
of scroll state or memory was introduced. CIRAM and palette RAM remain inferred
as MLAB RAM.

## Limitations and next phase

Phase 3D does not schedule or perform background nametable, attribute, or
pattern fetches; implement background or attribute shifters; render pixels;
select attribute quadrants; implement sprites, OAM, or DMA; implement mapper
banking; produce video; add APU or NMI-edge behavior; arbitrate a renderer with
CPU PPUDATA; or model exact same-dot PPU internal bus conflicts.

The recommended next phase is Phase 3E: use the verified timing, scroll state,
address helpers, and memory boundary to implement the background fetch and
shift pipeline.
