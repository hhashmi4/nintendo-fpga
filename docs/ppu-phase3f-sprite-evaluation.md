# Phase 3F: PPU sprite storage and evaluation

## Objective

Phase 3F adds real primary OAM, secondary OAM, and the visible-scanline sprite
evaluator behind the Phase 3B `$2003/$2004` interface. It selects the first
eight in-range sprites, preserves their original OAM indices, and generates
the PPUSTATUS sprite-overflow event. It does not fetch sprite pattern bytes or
produce sprite pixels.

## Architecture

```text
CPU $2003/$2004                    Phase 3A timing / PPUMASK
       |                                      |
       v                                      v
+--------------+                       +--------------+
| OAMADDR and  |                       | dots 1-64   |
| access pulse |                       | OAM2 clear  |
+------+-------+                       +------+-------+
       |                                      |
       +------------+   +---------------------+
                    v   v
             +----------------+
             | 256-byte OAM1  |
             | single owner   |
             +-------+--------+
                     |
                 dots 65-256
                     |
                     v
             +----------------+
             | n/m evaluator  |-----> PPUSTATUS overflow
             +-------+--------+
                     |
                     v
             +----------------+
             | 32-byte OAM2   |
             | + 8 indices    |
             +-------+--------+
                     |
                     v
             Phase 3G slot interface
```

`ppu_oam` is the only writer of primary and secondary OAM. `ppu_registers`
continues to own the one architectural OAMADDR register and produces one
accepted `$2004` write pulse. `ppu_sprite_core` composes the unchanged Phase
3E background hierarchy with OAM, routes real OAM read data back to `$2004`,
and routes the evaluator's overflow pulse to PPUSTATUS. This avoids a second
owner for either OAMADDR or status state.

The entire hierarchy uses the existing `clk`. Automatic OAM activity requires
`ppu_enable`; CPU accesses independently require the established accepted CPU
transaction. No generated clock or PLL exists.

## Primary OAM and CPU access

Primary OAM is a synthesizable `256 x 8` array. Address `4*n+m` contains sprite
`n` byte `m`:

| Byte | Meaning |
|---:|---|
| 0 | Y coordinate |
| 1 | tile index |
| 2 | attributes |
| 3 | X coordinate |

Outside rendering, `$2004` reads `OAM[OAMADDR]` without incrementing. An
accepted write stores one byte and lets the already-verified register block
increment OAMADDR modulo 256. Held bus signals with `cpu_enable=0` cannot
produce a storage write or address increment.

Primary OAM is intentionally not reset or initialized in production RTL.
Software cannot depend on NES OAM power-up contents, and clearing all 256 bytes
would defeat compact RAM inference. Testbenches explicitly initialize or load
OAM before observation.

### Active-render policy

Exact 2C02 `$2004` behavior during rendering includes OAM-bus exposure and
corruption/address quirks. Phase 3F uses this deterministic policy:

- writes during a rendered visible or pre-render scanline do not modify OAM;
- the Phase 3B OAMADDR register still performs its ordinary modulo-256 write
  increment;
- reads during visible dots 1-64 return `$FF`;
- reads during visible dots 65-256 expose the evaluator's primary-OAM byte;
- reads outside those windows use ordinary `OAM[OAMADDR]` data.

This policy prevents multiple storage writers and duplicate writes. It is not
a claim of transistor-level OAM corruption or the hardware's glitchy OAMADDR
increment behavior.

## Secondary OAM

Secondary OAM contains 32 bytes, eight four-byte sprite slots. Eight six-bit
metadata entries retain the original primary sprite number. The Phase 3G
interface accepts a slot number and returns Y, tile, attributes, X, original
index, and a validity bit derived from the selected count.

Secondary OAM is cleared through actual writes, not by reset. On each rendered
visible line, even dots 2, 4, ..., 64 write `$FF` to successive bytes. Thus the
hardware models the two-dot cadence across the full dots 1-64 interval and all
32 bytes are `$FF` after dot 64. Per-line count/index metadata is reset at dot
1. A `ppu_enable` stall holds the dot and suppresses the write.

## Range semantics

Evaluation on visible scanline `N` prepares the next raster line. The OAM Y
byte identifies the line immediately before the sprite's first displayed line,
so the semantic row calculation is:

```text
relative_row = (N - sprite_y) modulo 256
in_range     = relative_row < (sprite_size_16 ? 16 : 8)
```

The subtraction is explicitly eight-bit. This preserves wrap behavior for Y
values near `$FF`; it is not a signed or unbounded integer comparison.

PPUCTRL bit 5 selects height 8 or 16. The helper exposes the current relative
row and height and was checked for all `2 * 240 * 256 = 122,880` combinations.

## Evaluation timing and state machine

Normal evaluation runs only when either PPUMASK background or sprite rendering
is enabled and the current line is visible (0-239).

| Dots | Phase | Operation |
|---:|---|---|
| 1-64 | `CLEAR` | `$FF` to one OAM2 byte on each even dot |
| 65-256 | `EVALUATE_Y` | odd-dot OAM1 read, even-dot range decision |
| 65-256 | `COPY_SPRITE` | copy remaining bytes of an in-range sprite |
| 65-256 | `OVERFLOW_SCAN` | post-full `n/m` comparisons |
| 65-256 | `OVERFLOW_TAIL` | three trailing reads after overflow |
| 65-256 | `DONE` | failed-copy/dummy Y reads until HBLANK |
| 257-320 | handoff | selected slots stay stable for Phase 3G |

The evaluator starts at `n=0,m=0`. Odd dots latch `OAM1[n][m]`; even dots
consume that byte. An out-of-range Y advances to the next sprite. An in-range
Y and its following three bytes are copied to the next free OAM2 slot. Count
increments only when all four bytes are present. After all 64 candidates or
the overflow tail is complete, failed-copy/dummy reads retain the two-dot OAM
bus cadence without changing OAM2.

Only the first eight in-range primary sprites are copied, in original OAM
order. Later candidates cannot displace them. Unused slots retain the `$FF`
clear value.

Evaluation does not run on post-render line 240, vblank lines 241-260, or the
pre-render line 261. Consequently there is no invented pre-render selection
pass for scanline 0; this preserves the documented first-visible-line pipeline
limitation.

## Sprite zero metadata

When primary sprite 0 is accepted into the first eight, its original index is
stored with its slot and `sprite_zero_in_secondary` is set for the scanline.
Identity is never inferred from sprite contents. Phase 3F does not generate a
sprite-zero hit; Phase 3H will combine this metadata with fetched sprite and
background pixels.

## Sprite overflow

After eight sprites fill OAM2, the implementation uses the documented `n/m`
overflow bug rather than `count > 8`:

1. Treat `OAM[n][m]` as a candidate Y value.
2. If it is out of range, increment `n` and `m` independently, with no carry
   from `m` into `n`. This walks diagonally through tile, attribute, and X
   bytes.
3. If it is in range, pulse sprite overflow and perform the three trailing
   linear reads before entering the dummy-read phase.

This produces both a directed false positive (a non-Y byte compares in range)
and a directed false negative (a real later Y is skipped after diagonal drift)
in addition to ordinary true overflow. The pulse feeds the existing PPUSTATUS
bit-5 latch. A PPUSTATUS read does not clear bit 5; the Phase 3B pre-render
status-clear event does.

The model captures the documented cycle algorithm. It does not claim exact
transistor-delay behavior, OAM decay, mid-scanline rendering-toggle corruption,
or every `$2004` collision quirk.

## Verification

The independent semantic model is `verification/ppu_sprite_eval.py`.
The final retained Python suite passes all 556 tests, and whole-project
Verilator lint is clean.

Python verification includes:

- all 256 primary-OAM byte mappings;
- all 122,880 range cases for 8x8 and 8x16 modes;
- two-dot OAM2 clear cadence and stalls;
- zero, one, exactly eight, and 9/10/16/64 in-range scenarios;
- first-eight order and sprite-zero identity;
- row 7/8/15/16 boundaries;
- diagonal overflow true, false-positive, and false-negative vectors;
- 240 visible-line sweeps in both sprite-size modes.

Standalone OAM RTL/reference comparison uses seed `0x3F5EED01` and checks:

- 326,919 fabric cycles;
- 283,471 enabled PPU ticks and 43,414 stalls;
- 39,650 CPU-side OAM accesses, 37,061 committed writes, and 1,993
  active-render collisions;
- 34,240 secondary clear writes and 12,168 evaluation writes;
- 3,042 completed sprite selections and 44 overflow-set events;
- four 240-line deterministic layout sweeps (two 8x8 and two 8x16);
- zero RTL/reference mismatches.

Integrated timing/register/background/OAM comparison uses seed `0x3F200401`
and checks:

- 581,648 fabric cycles;
- 516,819 PPU ticks and 64,809 PPU stalls;
- 111,775 accepted CPU transactions;
- 49,616 OAM transactions: 23,709 reads and 25,907 writes;
- 9,289 primary-OAM commits and 33,301 active-render collisions;
- 41,367 clear writes, 10,655 evaluation writes, 2,593 selections, 57
  overflow events, and 36 sprite-zero selections;
- four complete timing-frame transitions and 1,273 rendered visible-line
  evaluations;
- PPUSTATUS overflow read persistence and pre-render clearing;
- zero RTL/reference mismatches and all testbench assertions passing.

The retained Phase 3E test still performs its exact 61,440-pixel background
frame comparison, proving that OAM evaluation did not take over dots 321-340
or disturb background fetches.

## Synthesis

The integrated `ppu_sprite_core` fits Cyclone V `5CSEMA5F31C6` with one 50 MHz
clock and no PLL:

| Resource/timing | Phase 3F |
|---|---:|
| ALMs | 1,888 / 32,070 |
| logic ALUTs | 1,273 |
| routing-only ALUTs | 61 |
| memory ALUTs | 584 |
| registers | 524 |
| MLAB bits | 18,688 |
| MLABs | 73 |
| M10K / DSP / PLL | 0 / 0 / 0 |
| worst setup slack | +4.554 ns |
| worst hold slack | +0.169 ns |
| setup / hold TNS | 0 / 0 |
| minimum-pulse-width slack | +8.627 ns |

Primary OAM inferred as 2,048 bits of MLAB/LUTRAM, adding 8 MLABs to the Phase
3E memory total. CIRAM and palette remain in their existing 65 MLABs.
Secondary OAM is implemented in registers: the future Phase 3G interface reads
all four bytes of a selected slot concurrently, while the evaluator writes a
single byte. That small 256-bit bank plus 48 bits of original-index metadata
accounts for most of the register increase. No reset network clears either OAM
array.

## Limitations and next phase

Phase 3F does not implement sprite pattern addressing/fetches, horizontal or
vertical flip, sprite shift registers, X counters, sprite pixels, sprite
priority, sprite-zero hit, left-edge sprite clipping, the final pixel mixer,
OAM DMA `$4014`, exact active-render OAM corruption/open-bus behavior, OAM
decay, RGB/video output, mappers, APU, the final CPU/PPU scheduler, or NMI edge
behavior.

Phase 3G should consume the stable eight-slot interface during dots 257-320 to
add sprite pattern addressing, fetches, flip handling, X counters, and sprite
pixel shift state without changing OAM ownership.

## References

- [NESdev PPU sprite evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation)
- [NESdev PPU programmer reference](https://www.nesdev.org/wiki/PPU_programmer_reference)
