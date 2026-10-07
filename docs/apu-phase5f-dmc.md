# Phase 5F — NES APU Delta Modulation Channel

Phase 5F adds the fifth and final NES APU source: the DMC reader, one-byte
sample buffer, output shifter, delta DAC, terminal IRQ, and an acknowledged
memory-fetch path through the existing CPU address decoder. It also adds a
dedicated 3/4-slot DMC DMA timing front-end and deterministic arbitration with
the established OAM DMA master. The five raw channel codes remain independent;
this phase does not add a nonlinear mixer or any audio-output pipeline.

```text
 $4010-$4013 / $4015
            |
            v
  +----------------------+       held request / one acknowledge
  | DMC reader + buffer  |--------------------------------------+
  | output shifter + DAC |                                      |
  +----------+-----------+                                      v
             |                                         +----------------+
             v                                         | DMC DMA timing |
       raw code 0..127                                 +--------+-------+
                                                               |
                     CPU < OAM DMA < DMC priority              v
                +----------------------------------- system arbiter
                |                                              |
                +---- CPU RAM / PPU / cartridge CPU-space -----+
                                                               |
                                                        runtime Mapper 0
```

The channel is `rtl/apu/nes_apu_dmc.sv`; `nes_apu.sv` supplies the existing
accepted-write decode and owns `$4015` status/enable integration. The DMA
front-end is `rtl/dma/nes_dmc_dma.sv`. `nes_core.sv` coordinates CPU stall,
OAM hold, and DMC acknowledgement, while `nes_internal_bus_arbiter.sv` remains
the sole owner of CPU-address-space routing. DMC does not decode cartridge,
RAM, PPU, or controller addresses itself and does not bypass Mapper 0.

## Registers and status

| Address | Bits | Behavior |
|---|---|---|
| `$4010` | 7 | terminal-sample IRQ enable; clearing it clears DMC IRQ |
| `$4010` | 6 | sample loop enable |
| `$4010` | 3:0 | NTSC output-bit rate index |
| `$4011` | 6:0 | direct seven-bit DAC load |
| `$4012` | 7:0 | sample address register |
| `$4013` | 7:0 | sample length register |
| `$4015` | 4 write | stop reader, or restart it when no bytes remain |
| `$4015` | 4 read | active when `bytes_remaining != 0` |
| `$4015` | 7 read | DMC IRQ latch |

The programmed reader values are pure integer expansions:

```text
start address = $C000 | ($4012 << 6)       $C000 .. $FFC0
sample length = ($4013 << 4) | 1           1 .. 4081 bytes
```

`$4011` changes only the DAC level. It neither starts nor restarts the reader.
Clearing `$4015` bit 4 sets bytes remaining to zero but deliberately leaves an
already buffered/output byte intact. Setting bit 4 reloads the programmed
address and length only if no bytes remain. Every `$4015` write clears DMC IRQ;
a `$4015` read clears only frame IRQ, not DMC IRQ. The APU IRQ output is now the
OR of frame IRQ and the internally owned DMC IRQ latch. CPU IRQ consumption at
the production top remains the separately planned interrupt-integration phase.

The earlier APU test-only `channel_active[4]` and `dmc_irq_flag` inputs remain
as compatibility status injectors for retained Phase 5A–5E vectors. Production
ties both low; real bit 4, bit 7, and APU IRQ behavior come from the DMC.

## NTSC rate table

`APU_DMC_RATE_TABLE` in `nes_apu_pkg.sv` is the one centralized NTSC table.
The timer advances on every complete CPU/APU slot and reloads with period minus
one, yielding exactly the listed number of CPU cycles between output bits.

| Index | Cycles | Index | Cycles |
|---:|---:|---:|---:|
| 0 | 428 | 8 | 190 |
| 1 | 380 | 9 | 160 |
| 2 | 340 | 10 | 142 |
| 3 | 320 | 11 | 128 |
| 4 | 286 | 12 | 106 |
| 5 | 254 | 13 | 85 |
| 6 | 226 | 14 | 72 |
| 7 | 214 | 15 | 54 |

No PAL values or duplicated timing constants exist in the channel.

## Sample reader and output unit

The reader asserts `dmc_mem_request` only when the one-byte sample buffer is
empty and bytes remain. The request and address are registered and remain
stable until exactly one `dmc_mem_acknowledge`. On that acknowledgement the
reader accepts one byte, increments the address, and decrements the remaining
count once. `$FFFF` advances to `$8000`; ordinary 16-bit wrap to `$0000` is
explicitly prevented.

Fetching the last byte has three possible outcomes:

- loop set: reload the programmed start address and length, without IRQ;
- loop clear and IRQ enabled: stop the reader and latch DMC IRQ;
- loop clear and IRQ disabled: stop without IRQ.

The output unit shifts least-significant bit first. At each timer expiration a
non-silent one bit adds two if the DAC is at most 125; a zero bit subtracts two
if the DAC is at least two. The seven-bit output therefore saturates in place
and never wraps. Every eighth bit, the shifter reloads from a full sample
buffer and marks it empty. An empty buffer selects silence while retaining the
DAC. An acknowledgement arriving on the reload edge is forwarded directly to
the shifter, avoiding a manufactured silent byte.

## DMA timing, CPU stall, and arbitration

`nes_dmc_dma` converts a held reader request into one CPU-space read:

```text
HALT -> DUMMY -> [optional ALIGN] -> READ/ACK
```

The transaction consumes three or four scheduled CPU slots according to the
captured CPU-cycle parity. A CPU write is allowed to finish before HALT, so the
stall cannot duplicate or truncate writes. During the transaction the CPU core
does not advance, accepted CPU bus strobes are suppressed, and one read event
generates one acknowledgement. The following CPU slot resumes the same core
normally—there is no reset, instruction skip, or compensating double step.

Bus priority is deterministic: DMC, then OAM DMA, then CPU. DMC holds its
address for the complete DMA transaction so the existing synchronous M10K RAM
and runtime PRG storage are precharged before the read event. If OAM DMA is
active, its state, index, elapsed count, and strobes are held for every DMC
slot. It then resumes at the same read or write phase. OAM's own counted
transfer remains exactly 513/514 slots; wall-clock completion extends by each
DMC transaction. There is no simultaneous DMC read, OAM source read, or OAM
destination write.

This is a deliberately documented accuracy boundary. Real 2A03 DMA can overlap
some DMC halt/dummy slots with OAM activity and usually steals a narrower
get/alignment window. Real hardware also has model-specific repeated CPU-read
effects, including controller-port corruption. Phase 5F implements the correct
held request, parity-based 3/4-slot transaction, write-safe CPU halt, exclusive
bus read, and lossless OAM pause, but it does not claim transistor-level DMA
overlap or controller-conflict emulation. Suppressing accepted CPU strobes
during stalls guarantees the project does not accidentally duplicate
controller/APU/PPU reads. Exact conflict quirks remain outside this phase.

## Runtime cartridge, pause, step, and reset

DMC reads use the same decoder targets as OAM source reads. Programmed DMC
addresses naturally select cartridge space and traverse the production runtime
Mapper-0 address and synchronous PRG-storage path. The path also remains valid
for decoded RAM/PPU addresses in directed arbitration tests; unsupported I/O
targets return deterministic zero without emitting peripheral strobes.

Debugger pause removes scheduled CPU/APU slots. A pending channel request and
captured DMA phase therefore remain stable; the timer, shifter, buffer, address,
and remaining-byte count do not progress on fabric clocks alone. One authorized
CPU-time slot advances at most one DMA phase or DMC timer slot. A transaction
accepted before pause completes on that accepted edge; one not yet accepted
remains pending.

Functional reset—including runtime-game activation—immediately masks request,
active, IRQ, and DAC outputs, and synchronously clears reader, buffer, shifter,
timer, DMA, and stall state. The Phase 5F runtime test begins replacement while
DMC and OAM are live, proves both cancel, activates a second generated NROM
image, and observes no stale fetch afterward.

## Verification

The independent `DmcModel` in `verification/apu.py` models registers, table,
reader, buffer, shifter, silence, looping, IRQ, request/acknowledge, pause, and
reset. `DmcDmaModel` in `verification/nes_system.py` independently models the
halt/dummy/alignment/read sequence and combined OAM hold policy.

The dedicated DMC oracle/RTL comparison uses seed `0x005F2026`:

| Counter | Value |
|---|---:|
| Compared cycles | 143,324 |
| Paused cycles | 23,780 |
| Held-request observations | 4,555 |
| Fetch acknowledgements | 155 |
| Timer expirations | 1,289 |
| DAC changes | 1,296 |
| RTL/model mismatches | 0 |

Directed coverage includes all 16 rates; address/length extremes; all four
registers; direct DAC values; request stability; exactly-once fetch; buffer and
shifter boundaries; silence; both delta directions and saturation limits;
terminal, loop, and IRQ paths; `$4015` status/clear semantics; 17-byte and
65-byte samples; and the explicit `$FFFF->$8000` transition.

Additional tests prove:

- standalone three/four-slot DMA and CPU-write deferral;
- request/phase stability across debugger pause and single-step behavior;
- DMC priority before, during, and near OAM completion;
- undamaged OAM copies and retained 513/514 internal transfer counts;
- centralized RAM, mirrored PPU, cartridge, and unsupported-I/O routing;
- generated runtime NROM sample bytes through real synchronous PRG storage;
- controller reads are never duplicated during DMC stalls;
- active DMC/OAM cancellation during runtime image replacement;
- retained Phase 5A–5E APU comparisons and the complete NES regression.

Waveforms are written to:

- `build/sim/nes_apu_dmc_phase5f.fst`
- `build/sim/nes_dmc_dma_phase5f.fst`
- `build/sim/nes_dmc_system_phase5f.fst`

Reference behavior and timing were cross-checked against the
[NESdev DMC channel](https://www.nesdev.org/wiki/APU_DMC),
[NESdev DMC DMA](https://www.nesdev.org/wiki/DMA), and
[NESdev APU status](https://www.nesdev.org/wiki/APU) descriptions.

## Quartus results

The production `de1_soc_nes_vga` build completed with Quartus Prime Lite
23.1std.1. The SOF and RBF were generated, every timing corner was fully
constrained, and no path had negative slack.

| Metric | Phase 5E baseline | Phase 5F | Change |
| --- | ---: | ---: | ---: |
| ALMs | 5,612 | 5,703 | +91 |
| logic ALUTs | 7,542 | 7,649 | +107 |
| route-through ALUTs | 1,087 | 1,082 | -5 |
| total registers | 5,885 | 5,990 | +105 |
| dedicated logic registers | 5,659 | 5,764 | +105 |
| M10K blocks | 270 | 270 | 0 |
| block-memory bits | 2,199,552 | 2,199,552 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| DSP blocks | 0 | 0 | 0 |
| PLLs | 1 | 1 | 0 |
| worst setup slack | +1.219 ns | +1.457 ns | +0.238 ns |
| worst hold slack | +0.077 ns | +0.077 ns | 0 ns |
| worst TNS | 0 ns | 0 ns | 0 ns |

The warning profile is unchanged from the Phase 5E production baseline:
101 Analysis & Synthesis, 150 Fitter, 0 Assembler, and 146 Timing Analyzer
warnings. The build reports no inferred latch, multiple-driver, or
unconstrained-path failure.

## Scope boundary

Phase 5F intentionally stops at the raw 0..127 DMC code and safe memory-fetch
integration. It does not implement the nonlinear NES mixer, resampling, WAV
generation, I2S, HDMI audio, or the DE1-SoC codec, and it does not begin the
next phase.
