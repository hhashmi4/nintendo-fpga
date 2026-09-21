# Phase 4D-A OAM DMA extraction and internal bus master

## Scope and measured baseline

Phase 4D-A extracts the already verified OAM DMA sequencer from `nes_core`
without redesigning its externally visible behavior. The CPU, PPU, NMI,
Mapper 0, controllers, scheduler, framebuffer, and VGA implementations remain
the same modules.

The starting point was clean `phase4/controllers` commit
`8b74c18abe6803df3ac444714a0c97b62804a311`, exactly synchronized with
`origin/phase4/controllers`. Before modification, the complete suite produced:

- 1,163 passing Python tests;
- all CPU, PPU, DMA/NMI, VGA, Phase 4A, Phase 4B, and Phase 4C RTL tests
  passing;
- six integrated DMA completions, 1,536 reads, 1,536 OAM writes, and measured
  transfer lengths of 514 and 513 CPU slots;
- clean Verilator lint;
- a successful Quartus synthesis, fitter, assembler, timing, and RBF flow;
- 2,888 ALMs, 3,308 logic ALUTs, 590 memory ALUTs, 1,248 registers, 230
  M10Ks, and 1,871,872 block-memory bits; and
- worst cross-corner setup/hold slack of +0.374 ns/+0.139 ns, zero TNS, and
  no unconstrained setup or hold paths.

## Why OAM DMA exists

The PPU renders sprites from 256 bytes of Object Attribute Memory (OAM).
Software commonly prepares those bytes in a CPU page and writes the page
number to `$4014`. Hardware then copies the complete page to the PPU. This is
faster and more regular than executing 256 explicit load/store pairs.

The CPU and DMA cannot independently use the same NES memory paths at the same
time. DMA therefore stalls CPU architectural execution and temporarily becomes
the internal bus owner. The PPU continues to run.

## Previous architecture

Before extraction, `nes_core` contained all of the following directly:

- `$4014` trigger and page capture;
- `idle`, `dummy`, `align`, `read`, and `write` state registers;
- byte index, data latch, parity, elapsed-slot, read, and write counters;
- CPU-enable suppression;
- a second CPU-address decoder for DMA sources;
- RAM read-address, PPU register-port, and cartridge-port muxing; and
- completion and diagnostic assertions.

The trigger was the accepted Phase 4A bus write to `$4014`. That CPU write
completed normally. DMA began stalling on following scheduled CPU slots.

## Extracted architecture

The functionality now has two explicit modules:

```text
CPU -> nes_cpu_bus -- $4014 trigger/page --> nes_oam_dma
 |                                             |
 | CPU requests                                | DMA requests
 +-------------------+   +---------------------+
                     v   v
              nes_internal_bus_arbiter
                |        |         |
                v        v         v
             CPU RAM   PPU port   cartridge
                          |
                          +-- $2004 OAM writes
```

`nes_oam_dma` owns only transfer sequencing and diagnostics. It receives a
trigger, initiating CPU parity, scheduled CPU-slot enable, and returned source
data. It produces a source address/request, one `$2004` write event per byte,
CPU stall, and passive state/counter observations.

`nes_internal_bus_arbiter` owns shared-resource selection. Its owner is
`none` during reset, `CPU` normally, and `DMA` while a transfer is active. It
instantiates the existing address decoder rather than duplicating NES mapping
rules in the DMA engine.

Both modules use the existing 50 MHz clock. `cpu_cycle_slot` is a clock enable,
not a generated clock.

## Exact state and timing behavior

The preserved state sequence is:

```text
$4014 trigger -> dummy -> [optional alignment] -> read -> write x 256 -> idle
```

The trigger captures the page and current CPU parity. The triggering write is
not included in `elapsed_cpu_cycles`.

- Even modeled start: one dummy plus 512 data slots = 513 stalled CPU slots.
- Odd modeled start: dummy plus alignment plus 512 data slots = 514 slots.

Every read latches one byte. The following write presents that byte to the
existing PPU CPU register port as a canonical `$2004` write. Only after the
write does the eight-bit byte index advance. Index `$FF` completes the
transfer, releases the CPU, and produces a one-cycle completion event.

## Source addressing and synchronous-memory preparation

For page `P`, the address output is `{P, byte_index}`. It therefore visits:

```text
P00, P01, ... PFE, PFF
```

`source_read_request` remains high for the whole read phase. This establishes
the address early enough for the existing registered RAM and Mapper 0 memories.
`source_read_event` is the single scheduled CPU slot that consumes the byte.
This distinction fixes cartridge-source timing cleanly without adding a console
cycle.

## Source policy and arbitration

| DMA source | Behavior |
|---|---|
| `$0000-$1FFF` | One physical 2 KiB RAM, address `source & $07FF` |
| `$2000-$3FFF` | Existing canonical PPU register read, `source[2:0]` |
| `$4000-$4013`, `$4015` | Deterministic zero; no APU strobe |
| `$4014` | Deterministic zero; no recursive trigger |
| `$4016-$4017` | Deterministic zero; no controller read/shift |
| `$4018-$401F` | Deterministic zero |
| `$4020-$FFFF` | Existing cartridge CPU-read interface |

PPU-source reads deliberately preserve the prior Phase 4A behavior. They issue
exactly one canonical PPU register read event and therefore retain the same
CPU-facing PPU register semantics, including documented read side effects.
They cannot overlap a CPU PPU request. Unsupported I/O regions never inherit a
frozen CPU request and never strobe APU or controller logic.

During a DMA read phase the arbiter precharges the selected RAM or cartridge
address. During the read event it returns data from exactly one decoded owner.
During the write event it exclusively selects `$2004`. Assertions reject
simultaneous cartridge read/write and mixed DMA PPU/cartridge responses.

## CPU stall and NMI

`dma_cpu_stall` is the DMA active state. `cpu_enable` is the scheduled CPU slot
AND NOT this stall. Consequently PC, A, X, Y, SP, status, execution state, and
the frozen CPU bus request do not advance during DMA. After completion the next
ordinary CPU slot resumes the interrupted instruction stream; the trigger
instruction is neither repeated nor skipped.

The CPU's NMI synchronizer and pending latch run on the fabric clock even while
`cpu_enable` is low. A rising NMI during DMA becomes pending, but architectural
interrupt entry waits until CPU ownership returns. Directed testing covers NMI
before DMA, early during DMA, near completion, and immediately after release.

## OAM destination

DMA does not write the OAM array directly. Each write goes through the PPU's
existing `$2004` path, preserving:

- the current OAMADDR starting point;
- automatic OAMADDR increment and wrap;
- the PPU's established rendering-time collision policy; and
- the single ownership point for primary OAM.

Exactly 256 source events and 256 destination events are required before
completion. First, last, order, duplicate, and dropped-byte checks are present
in both standalone and integrated verification.

## Controller and cartridge independence

DMA never drives `$4016/$4017` controller strobes. The Phase 4C shared strobe,
shift registers, read indices, and synchronized live inputs are unchanged.

Cartridge reads use the Phase 4B interface and decoder. The Mapper 0 module is
not duplicated or specialized for DMA. NROM-128/NROM-256, PRG ROM/RAM, CHR,
mirroring, and reset-vector behavior remain behind the same interface.

## Passive debug observations

`nes_core` now exposes:

- active/stall and start/complete events;
- source page, full source address, decoded target, and returned source data;
- byte index and latched OAM write data;
- phase, dummy, alignment, read, and write observations;
- initiating parity, elapsed CPU slots, read count, and write count; and
- current internal bus owner (`none`, `CPU`, or `DMA`).

These outputs do not feed functional decisions and are suitable for the future
Developer Mode renderer.

## Verification architecture

The independent Python model describes every page's 256-address sequence,
513/514 phase traces, RAM mirrors, source-target ownership, deterministic I/O
zeroes, and byte order.

The standalone RTL DMA test covers pages `$00`, `$02`, `$0A`, `$20`, `$40`,
and `$80`, six complete transfers, both alignments, all 1,536 reads and writes,
fabric-clock holds between CPU slots, idle reset, and reset abort. The arbiter
test performs 1,556 checks across base/mirrored RAM, PPU aliases, the full
reserved I/O edge, and cartridge pages.

The owned `phase4d_dma_nrom128` program:

1. fills RAM `$0200-$02FF` with `index XOR $5A`;
2. writes `$02` to `$4014` and resumes to marker `$11`;
3. writes `$80` to `$4014` and resumes to marker `$22`;
4. writes `$40` to `$4014` and resumes to marker `$33`; and
5. loops normally.

The integrated test observes real CPU instructions, two Mapper 0 cartridge
paths, system-bus trigger, exclusive ownership, PPU OAM contents, controller
isolation, and CPU continuation. It never forces CPU, RAM, DMA, or OAM results.

Waveforms are generated as:

- `build/sim/nes_oam_dma_phase4d.fst`;
- `build/sim/nes_internal_bus_arbiter_phase4d.fst`;
- `build/sim/nes_phase4d_dma_integration.fst`; and
- `build/sim/nes_phase4d_dma_nmi.fst`.

## Final qualification and resource comparison

The final complete `scripts/test.sh` run passed all 1,168 Python tests, every
Verilator lint target, and every retained CPU, PPU, Phase 3J DMA/NMI, Phase 3K
VGA, Phase 4A bus, Phase 4B cartridge, and Phase 4C controller simulation.
The new standalone DMA run completed six transfers with 1,536 reads and 1,536
writes. The integrated owned-cartridge run completed three transfers with 768
reads, 768 writes, measured lengths of 514/513/513 slots, 480 cartridge-source
reads, and post-DMA marker `$33`. The directed NMI run delivered and serviced
all four events around the DMA boundary. The original Phase 3J integration
still completed six transfers with 1,536 reads, 1,536 writes, both 514/513
lengths, and four NMI handlers.

Quartus Prime Lite 23.1std.1 completed synthesis, fitting, assembly, timing
analysis, SOF generation, and RBF conversion with zero errors:

| Fitted result | Phase 4C baseline | Phase 4D-A | Delta |
|---|---:|---:|---:|
| ALMs | 2,888 | 2,906 | +18 |
| logic ALUTs | 3,308 | 3,329 | +21 |
| memory ALUTs | 590 | 590 | 0 |
| registers | 1,248 | 1,229 | -19 |
| M10Ks | 230 | 230 | 0 |
| block-memory bits | 1,871,872 | 1,871,872 | 0 |
| DSPs | 0 | 0 | 0 |
| PLLs | 1 | 1 | 0 |

The register reduction is a post-synthesis result, not removed functional
state: the standalone module retains the page, byte/data, phase, parity, and
diagnostic counters. Unobserved board-level diagnostic fanout is optimized in
the same normal manner as the preceding image.

Across all four timing corners, setup slack improved from +0.374 ns to
+1.084 ns, a +0.710 ns margin change. Worst hold slack changed from +0.139 ns
to +0.118 ns, remaining positive by 0.118 ns. Setup and hold TNS are both
zero, setup and hold are fully constrained, and 19 synchronizer chains remain
recognized. The slow-85 C setup-critical path is from the CPU execution-state
decode through the existing CPU/PPU/CIRAM read path to sprite-renderer
`pattern_high[7][0]`; no standalone-DMA or arbitration register is on it.
Thus the extraction improves setup margin and does not introduce a new DMA
critical path. The exact Phase 4C endpoint was not retained, so the baseline
comparison is to its executed and recorded worst-corner slack rather than an
unverifiable endpoint claim.

The full compilation emitted the same 17 understood warnings as Phase 4C:
ten mapping, five fitting, and two timing warnings. They cover the inferred
read-only ROMs' unused write-side inputs, one unused diagnostic aggregate,
connectivity reporting, constant-low `VGA_SYNC_N`, deliberately incomplete
unused board-pin assignments, the Lite-edition LogicLock notice, automatic
PLL compensation, and two IRQ synchronizer filters whose registers optimize
away. No new DMA warning, inferred latch, multiple driver, timing failure, or
unconstrained path was reported.

The hardware-ready build artifacts are:

- `build/quartus_de1_soc_nes_vga/output_files/de1_soc_nes_vga.sof`:
  6,690,502 bytes, SHA-256
  `f55dd80a8f516f5c19ff1fb55e98df5c2f3ec0651b72aeb0c0b3cbd83cdeb44d`;
- `build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf`: 7,007,204 bytes,
  SHA-256
  `9a196ca035b73b862bc81d3477600f93003f722e889b3fe36184e0826bd241e6`.

The artifacts were built and inspected but were not programmed onto a
physical board in this phase.

## Hardware validation boundary

The Quartus flow produces the normal DE1-SoC SOF and RBF. This phase's
simulation and build results do not claim that a board was programmed. For a
physical smoke test, program the image, confirm VGA/controller operation,
observe the DMA heartbeat on LEDR6, and verify the existing moving sprite still
updates once per NMI-driven DMA.

## Phase 4D-B recommendation

Validate a legally redistributable, playable Mapper 0 homebrew ROM without
changing the architecture first. Add a reproducible ROM import target, a
deterministic boot/controller/frame trace, selected frame hashes, and a board
checklist covering reset, controller polling, NMI, OAM DMA, CHR rendering, and
VGA. Treat discrepancies as compatibility bugs with focused regressions; do
not add a new mapper, APU, or developer UI until that NROM execution path is
demonstrably stable.
