# Phase 3J: CPU and PPU system integration

## Purpose and system boundary

Phase 3J turns the previously verified CPU and PPU subsystems into one logical
NES core. CPU instructions now reach real PPU registers, the PPU's VBlank
condition reaches the real CPU NMI input, and `$4014` copies CPU-address-space
data into primary OAM while the CPU is stalled.

```text
                 NES CORE
                    |
        +-----------+-----------+
        |                       |
        v                       v
       CPU                     PPU
        |                       |
        | $2000-$3FFF           |
        +---------------------->|
        |                       |
        |<--------- NMI --------+
        |
        | $4014 DMA
        v
     CPU RAM ---------> PPU OAM
```

`rtl/nes_core.sv` contains the system scheduler, 2 KiB RAM, CPU bus decoder,
DMA sequencer, verified CPU instance, and verified PPU instance. It exposes a
CPU-side PRG/cartridge bus, the existing PPU-side CHR/cartridge bus, and the
Phase 3H logical pixel stream. It contains no game ROM, CHR artwork, mapper,
VGA timing, or physical video protocol.

## One-clock 3:1 scheduler

There remains exactly one 50 MHz fabric clock. A two-bit phase counter creates
clock enables with this repeating sequence:

```text
phase 0: PPU
phase 1: PPU
phase 2: PPU + scheduled CPU slot
```

Thus every scheduled CPU slot has exactly three PPU enabled ticks and the
logical ratio cannot drift. When DMA is inactive, `cpu_enable` equals the CPU
slot. During DMA, the slot advances the DMA state machine and `cpu_enable` is
suppressed. `ppu_enable` remains asserted, so pixels, dots, scanlines, VBlank,
and NMI state continue normally.

This phase intentionally does not synthesize the wall-clock NTSC frequencies.
At a continuously enabled 50 MHz fabric clock the logical PPU runs at 50 MHz
and CPU slots average 16.666667 MHz. Phase 3K must provide a safe fractional
master enable or other video-clock integration while retaining the proven 3:1
logical relationship. No generated clock or PLL is used here.

CPU architectural endpoints are given a three-edge timing relationship in the
Phase 3J SDC because those registers update only at CPU slots. The CPU NMI/IRQ
synchronizer and pending registers are explicitly excluded and remain genuine
single-fabric-edge paths. PPU state remains single-cycle.

## CPU memory map

| CPU address | Phase 3J destination | Behavior |
|---|---|---|
| `$0000-$07FF` | internal CPU RAM | physical 2 KiB RAM |
| `$0800-$1FFF` | internal CPU RAM | mirrored with `address[10:0]` |
| `$2000-$3FFF` | PPU registers | low three bits select `$2000-$2007` |
| `$4000-$4013` | unimplemented I/O | deterministic zero reads, ignored writes |
| `$4014` | OAM DMA trigger | write selects the 256-byte source page |
| `$4015-$401F` | unimplemented I/O | deterministic zero reads, ignored writes |
| `$4020-$FFFF` | cartridge/PRG bus | external read/write request and data |

Decode is mutually exclusive. A PPU access is presented exactly once on its
accepted CPU slot. The PPU retains ownership of register mirroring and all
`$2000-$2007` side effects. Simulation uses external program memory; production
RTL exposes only the cartridge bus.

The 2 KiB RAM has one shared registered read port because the CPU is stopped
while DMA owns that port. CPU and DMA addresses are each stable for the two
intervening fabric edges before their next scheduled slot, allowing the memory
to infer as two Cyclone V M10Ks without changing CPU-cycle-visible behavior.

The existing CHR address/read/write/data interface passes straight through the
integrated core. PRG and CHR therefore form separate future mapper boundaries.

## VBlank NMI connection and sampling

Phase 3I's active-high `ppu_nmi_level` connects to the verified CPU's
active-high synchronized, rising-edge-latched NMI input. The event pulse stays
a debug output; it is not used as the CPU input. Consequently:

- one ordinary enabled VBlank produces one CPU recognition;
- a continuously high VBlank condition cannot retrigger the CPU;
- disabling and re-enabling PPUCTRL bit 7 during uncleared VBlank creates a
  new level edge and a second CPU recognition;
- a pending CPU NMI survives CPU stalls, including OAM DMA.

The selected scheduler alignment accepts CPU register transactions every third
PPU tick. With reset starting both counters at zero, CPU accesses around the
VBlank boundary can occur at scanline 241 dot 0 and then dot 3, but not dots 1
or 2. An accepted `$2002` read at 241:0 therefore exercises Phase 3I's
pre-boundary suppression and prevents both VBlank visibility and the ordinary
NMI. A read at 241:3 clears the flag after the PPU condition has been long
enough to pass through the CPU synchronizer, so the CPU still recognizes that
activation. This resolves Phase 3I's sampling question for this one digital
phase alignment; it does not claim all transistor/analog alignments.

The scheduled NMI program ran 24 frames, performed 89,613 real CPU status
reads, reached one 241:0 suppression and six post-set boundary reads, generated
23 PPU NMI events, and executed 23 CPU NMI handlers. Its first handler also
performed a real disable/re-enable sequence during active VBlank and caused the
expected immediate second activation.

## OAM DMA

A CPU write of page `XX` to `$4014` latches `XX`; DMA reads
`$XX00-$XXFF` in index order. Each byte uses one scheduled read slot followed
by one scheduled `$2004` write slot. Routing writes through the existing PPU
register path preserves the single owner of OAMADDR, its increment after each
write, wrapping, and the established active-render collision policy.

The state sequence is:

```text
trigger -> dummy -> [optional alignment] -> read -> write x 256 -> idle
```

The CPU-cycle parity bit toggles on every scheduled CPU slot. A trigger on the
modeled even parity consumes one dummy plus 512 transfer slots, for 513 stalled
CPU slots. A trigger on odd parity adds one alignment slot, for 514. The
triggering CPU write completes normally and is not part of the stall count.

DMA uses the same CPU decoder as normal reads. Internal RAM and all its mirrors
are implemented now; PPU and cartridge-source reads are structurally routed as
well. The directed RTL program proves both 513 and 514 stalls, 256 source reads,
256 destination writes, no missing or repeated index, source pages `$00` and
`$02`/mirrors in the reference tests, and OAMADDR start/wrap at `$FC` and `$00`.

## CPU-driven PPU and dynamic sprite proof

The integrated RTL test runs machine code on `cpu_core`; the testbench does not
inject PPU-register or OAM writes. The program:

1. fills CPU RAM page `$02` and writes sprite-zero Y/tile/attribute/X metadata;
2. writes mirrored PPU registers, PPUSCROLL, PPUADDR, and PPUDATA;
3. performs two initial DMAs covering both parity lengths and OAMADDR wrapping;
4. enables sprite rendering and VBlank NMI;
5. increments a RAM counter in a real NMI handler and returns with RTI;
6. adds eight to the sprite X byte and starts another DMA each frame.

The resulting path is fully integrated:

```text
CPU instructions -> CPU RAM -> $4014 DMA -> primary OAM
 -> sprite evaluation -> cartridge CHR -> sprite shifters
 -> pixel mixer -> final logical NES pixel
```

Across five frames the run produced 192 sprite-winning final pixels and two
machine-checked consecutive frame movements of exactly eight pixels. The run
used 358,367 fabric/PPU ticks, 119,455 scheduled CPU slots, 116,374 CPU run
cycles, six DMA transfers, 1,536 reads, 1,536 OAM writes, four PPU NMI events,
and four completed CPU NMI handlers. All comparisons were exact.

The Phase 3F/3G first-visible-line sprite-preparation limitation is unchanged.

## Reference and regression verification

`verification/nes_system.py` independently models exhaustive 16-bit bus decode,
RAM/PPU mirroring, scheduler phase, DMA dummy/alignment/read/write semantics,
OAMADDR wrapping, and source reads. Python tests exhaust all 65,536 CPU
addresses and every RAM/PPU mirror.

A deterministic randomized reference run uses seed `0x3A102026` for 300,000
fabric/PPU ticks and 100,000 CPU slots. It produces 145 completed DMA transfers,
37,120 reads, 37,120 writes, randomized mirrored-RAM traffic, and zero OAM-data
mismatches. The RTL integration programs add real CPU execution, PPU side
effects, NMI sampling, and final-pixel checks.

The retained suite still covers Phase 1, CPU Phase 2A-2K, PPU Phase 3A-3I,
591,876 exhaustive ALU vectors, 1,508,186 exhaustive CPU-address vectors,
whole-project Verilator lint, exact background/sprite/final 61,440-pixel
streams, CPU synthesis, PPU synthesis, and retained DE1-SoC builds.

## Synthesis

The combined core targets Cyclone V `5CSEMA5F31C6` with one 50 MHz global
fabric clock:

| Resource/timing | Phase 3I PPU | Phase 3J CPU+PPU |
|---|---:|---:|
| ALMs | 2,306 | 2,760 / 32,070 |
| logic ALUTs | 1,881 | 2,918 |
| routing-only ALUTs | 67 | 73 |
| memory ALUTs | 590 | 590 |
| registers | 800 | 983 |
| MLAB RAM bits | 18,880 | 18,880 |
| MLABs | 74 | 74 |
| M10K | 0 | 2 |
| block RAM bits | 0 | 16,384 |
| DSP | 0 | 0 |
| PLL | 0 | 0 |
| worst setup slack | +3.781 ns | +1.268 ns |
| worst hold slack | +0.158 ns | +0.160 ns |
| setup/hold TNS | 0 / 0 ns | 0 / 0 ns |
| worst minimum-pulse-width slack | +8.626 ns | +8.436 ns |

Every analyzed corner has positive setup, hold, and pulse-width slack. The two
M10Ks are exactly the 2 KiB CPU RAM. There is no PLL, generated clock, latch,
multiple driver, or additional clock domain.

## Controller boundary and deferred work

Controller transport is deliberately outside this phase. A later system layer
should expose logical controller-one/controller-two button vectors and let
wired NES, custom wired, or Bluetooth receiver modules translate into those
vectors. Game/system logic must not depend on the physical transport.

Phase 3J does not implement APU audio, controller shift registers or electrical
interfaces, mapper banking, cartridge loading/parsing, a physical cartridge
connector, exact NTSC wall-clock generation, VGA/HDMI timing or pins, scaling,
framebuffer, analog composite video, or transistor-level CPU/PPU bus conflicts.
VGA remains deferred to Phase 3K. Phase 2K physical LED/HEX confirmation also
remains outstanding and is not physically hardware-verified by Phase 3J.
