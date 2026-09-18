# Phase 3B: CPU-facing PPU register interface

## Objective

Phase 3B adds the programmer-visible `$2000`-`$2007` PPU registers and the
internal address/scroll state that later PPU phases will consume.  It integrates
that state with the Phase 3A timing engine but does not add a renderer, PPU
memory, OAM RAM, DMA, NMI generation, or a complete NES system bus.

## Architecture

The integrated `ppu_core` contains the unchanged Phase 3A `ppu_timing` module
and the new independently testable `ppu_registers` module:

```text
CPU bus
   |
   v
+-----------------------+
| PPU register decoder  |<------ Phase 3A vblank events
| $2000-$2007           |                   |
+-----------+-----------+                   v
            |                            PPUSTATUS
       +----+--------------------------+
       |                               |
       v                               v
 PPUCTRL / MASK                  SCROLL ADDRESS
 PPUSTATUS                      v / t / x / w
 OAMADDR                              |
       |                              v
       |                           PPUDATA
       |                              |
       v                              v
 Future OAM                    Future PPU memory

PPUMASK[4:3] --OR--> rendering_enabled --> Phase 3A timing
```

There remains one FPGA fabric `clk`.  `ppu_enable` advances timing only.
Register transactions commit only when all of the following are true on an
edge:

```text
!reset && cpu_enable && cpu_bus_valid && ($2000 <= cpu_address <= $3FFF)
```

Thus a CPU bus held during intervening 50 MHz fabric clocks has no repeated
effect while `cpu_enable` is low.  CPU transaction gating and `ppu_enable` are
independent; timing may advance during a CPU stall.

Reset deterministically clears the timing state, all register storage,
`v/t/x/w`, the PPUDATA read buffer, and the digital I/O latch.

## Address decode and mirroring

The decoder selects the PPU only for `$2000` through `$3FFF`.  Within that
range, `cpu_address[2:0]` selects one of eight registers, yielding 1,024 aliases
per register and 8,192 decoded addresses in total.  `$4014` is deliberately not
decoded; OAM DMA is deferred.

| Index | Register | CPU behavior implemented in Phase 3B |
| ---: | --- | --- |
| 0 | `$2000` PPUCTRL | Full-byte storage and decoded control outputs |
| 1 | `$2001` PPUMASK | Full-byte storage and timing render-enable control |
| 2 | `$2002` PPUSTATUS | Status/open-bus read and read side effects |
| 3 | `$2003` OAMADDR | 8-bit address storage |
| 4 | `$2004` OAMDATA | Abstract OAM read/write port |
| 5 | `$2005` PPUSCROLL | First/second scroll programming writes |
| 6 | `$2006` PPUADDR | First/second VRAM-address programming writes |
| 7 | `$2007` PPUDATA | Abstract buffered PPU-memory access |

Reads from write-only ports return the current PPU I/O latch and do not cause
register side effects.

## Register behavior

### PPUCTRL `$2000`

All eight bits are stored and exposed as NMI enable, master/slave, sprite size,
background pattern-table selection, sprite pattern-table selection, VRAM
increment, and base nametable selection.  Bit 2 selects a PPUDATA increment of
1 or 32.  Every accepted write also performs `t[11:10] <- data[1:0]`.  Phase 3B
stores the NMI-enable bit but does not generate NMI.

### PPUMASK `$2001`

All eight mask/emphasis bits are stored and individually exposed.  The timing
control is:

```text
rendering_enabled = PPUMASK[3] || PPUMASK[4]
```

Either background or sprite enable therefore activates the Phase 3A odd-frame
shortening behavior.  No pixel or sprite rendering is implied.

### PPUSTATUS `$2002`

Bits 7, 6, and 5 are separate vblank, sprite-zero-hit, and sprite-overflow
latches.  Phase 3A's `vblank_start` event sets bit 7; its pre-render
`vblank_end` event clears all three flags.  Future-facing event inputs allow
later sprite logic to set bits 6 and 5.

An accepted status read returns the previous status flags in bits 7:5 and the
previous I/O latch in bits 4:0, then loads that returned byte into the I/O
latch, clears only the CPU-visible vblank latch, and sets `w` to zero.  It does
not alter the Phase 3A timing-region vblank level and does not clear the two
sprite flags.  Exact NMI/vblank race-cycle behavior is deferred.

### Digital I/O latch

Every accepted CPU write to a PPU port loads its byte into the eight-bit I/O
latch.  Reads of PPUSTATUS, OAMDATA, and PPUDATA load the byte they return.
Reads of write-only registers return the existing latch.  This is a fully
deterministic digital open-bus model; analog charge decay is intentionally not
modeled.

### OAMADDR/OAMDATA `$2003/$2004`

OAMADDR stores eight bits.  The external OAM interface presents `oam_addr`,
`oam_read_data`, `oam_write_data`, and a one-transaction
`oam_write_enable`.  A normal OAMDATA read returns the external byte without
incrementing OAMADDR.  A write emits one write request and increments OAMADDR
modulo 256.  No OAM RAM is instantiated, and active-rendering OAM quirks are
outside this phase.

## Internal scroll/address state

The canonical PPU programming state is directly exposed for future logic:

- `v`: 15-bit current VRAM/scroll address
- `t`: 15-bit temporary VRAM/scroll address
- `x`: 3-bit fine-X scroll
- `w`: shared first/second-write toggle

Phase 3B implements CPU programming only.  Rendering-time coarse/fine
increments and `t`-to-`v` horizontal/vertical copies are deferred.

### PPUSCROLL `$2005`

With `w=0`, a write loads coarse X into `t[4:0]`, fine X into `x[2:0]`, and
sets `w`.  With `w=1`, it loads coarse Y into `t[9:5]`, fine Y into
`t[14:12]`, and clears `w`.  All unrelated `t` fields are preserved.

### PPUADDR `$2006`

With `w=0`, a write loads `t[13:8]` from `data[5:0]`, forces `t[14]` low, and
sets `w`.  With `w=1`, it loads `t[7:0]`, copies the newly completed value—not
the old low byte—into `v`, and clears `w`.

PPUSCROLL and PPUADDR share the same `w`; mixed `$2005/$2006` sequences are
therefore intentional.  Every accepted PPUSTATUS read restores `w=0`.

## PPUDATA `$2007` and memory abstraction

The external address is always `v[13:0]`.  Accepted reads emit
`ppu_memory_read_request`; accepted writes emit `ppu_memory_write_request` with
the current address and CPU byte.  Either access increments the 15-bit `v` once
by the PPUCTRL-selected 1 or 32.  No request is emitted for a CPU stall, invalid
bus cycle, read/write mismatch, or non-PPU CPU address.

Two read-data inputs keep the interface compatible with a later real memory
implementation:

- `ppu_memory_read_data` is the byte at `v[13:0]`.
- `ppu_memory_buffer_read_data` is the byte at the supplied
  `ppu_memory_buffer_address`, used to refill the buffer on a palette read.

For addresses below `$3F00`, a read returns the old internal buffer and then
refills it from `ppu_memory_read_data`.  For `$3F00-$3FFF`, it returns
`ppu_memory_read_data` immediately while refilling the buffer from the
corresponding `$2F00-$2FFF` address (`address - $1000`).  The two explicit
addresses/data inputs avoid hard-coded placeholders and permit Phase 3C to
attach actual PPU memory cleanly.

## Timing integration proof

The integrated RTL measured the following enabled-tick frame lengths:

| PPUMASK condition | Even frame | Odd frame |
| --- | ---: | ---: |
| Rendering disabled | 89,342 | 89,342 |
| Background enabled | 89,342 | 89,341 |
| Sprites enabled | 89,342 | 89,341 |
| Background and sprites enabled | 89,342 | 89,341 |

Disabling PPUMASK before an odd frame restored the 89,342-tick frame.  The
vblank integration test consumed the `241:1` event, observed CPU-visible status
bit 7 set, read `$2002` as `$F5` (all three flags plus prior latch `$15`), and
verified that the read cleared bit 7 and `w` without stopping timing or clearing
the sprite flags.  The `261:1` event then cleared all status flags.

## Verification

`verification/ppu_registers.py` is a semantic transaction model rather than a
translation of the RTL case statement.  Python tests cover every register,
every PPUCTRL/PPUMASK bit, field preservation, all required shared-toggle
orders, deterministic randomized `$2002/$2005/$2006` interleaving, PPUDATA
buffering, palette refill, wrap behavior, and rejected transactions.

The RTL test consumes 208,249 Python-generated fabric-cycle expectations:

- all 8,192 mirrored CPU addresses plus five boundary/non-PPU addresses;
- 48 directed trace cycles with 37 accepted accesses;
- 200,000 randomized cycles using seed `0x3B5EED01`;
- 76,207 accepted randomized transactions and 123,793 rejected/stalled cycles;
- 134,135 randomized PPU-enable ticks;
- accepted register counts `[9489, 9482, 9413, 9432, 9668, 9772, 9482, 9469]`.

State and bus outputs are compared after every accepted or rejected cycle.
Testbench assertions enforce stall stability, request direction, address width,
single increments, decoded control outputs, and model equality.  Ten complete
integrated frame cases separately prove PPUMASK-to-timing behavior.  The full
retained Phase 1, Phase 2A-2K, and Phase 3A tests continue to run from
`scripts/test.sh`, which is already the GitHub Actions verification entry.

The final local regression passed 488/488 Python tests, Verilator lint, the
Phase 1 platform simulation, Phase 2A, the 591,876-vector Phase 2B ALU run, the
1,508,186-vector Phase 2C address run, Phase 2D through Phase 2K, the
1,336,451-cycle Phase 3A timing trace, and the Phase 3B checks above.  Standalone
CPU synthesis, Phase 3A synthesis, the unchanged Phase 1 board build, and the
unchanged Phase 2K board-diagnostic build also passed after implementation.

## Standalone synthesis

The production `ppu_timing + ppu_registers` hierarchy was synthesized without
fake OAM or PPU memory on the Cyclone V `5CSEMA5F31C6` at 50 MHz:

- 234 ALMs of 32,070
- 163 combinational logic ALUTs plus 19 routing-only ALUTs
- 97 registers
- 0 RAM bits / 0 RAM blocks
- 0 DSP blocks
- 0 PLLs
- worst setup slack `+15.623 ns`, setup TNS `0`
- worst hold slack `+0.171 ns`, hold TNS `0`
- worst minimum-pulse-width slack `+9.069 ns`

The build remains a small, entirely synchronous one-clock design.  Constant
middle bits of the decoded 1-or-32 increment output are expected synthesis
constants, not stuck state.

## Limitations and next phase

Phase 3B does not implement background fetching, shifters, pixels, sprites,
sprite evaluation, real OAM RAM, `$4014` DMA, CHR memory, nametable/attribute
RAM, palette RAM, PPU memory mirroring, cartridges/mappers, video output, APU,
the complete system bus, final CPU/PPU scheduling, NMI edge generation or
suppression races, active-rendering OAMDATA quirks, the PPU power-up write-ignore
interval, or analog open-bus decay.

The recommended next phase is Phase 3C: implement the standalone PPU memory
map behind the explicit PPUDATA memory interface while retaining these register
and timing contracts.
