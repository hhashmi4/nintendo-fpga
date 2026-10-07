# Phase 5G — complete APU accuracy and interaction closure

Phase 5G closes the complete raw NES APU before mixing. Pulse 1, Pulse 2,
Triangle, Noise, and DMC remain five independent digital outputs; no nonlinear
mixer, sample-rate conversion, WAV path, I2S interface, or board codec is added.

The audit found no production-RTL defect that required a behavioral change.
The Phase 5A–5F channel implementations already agree with the independent
model at their shared boundaries. Phase 5G therefore adds the missing
complete-APU proof: a readable combined model snapshot, directed interaction
tests, a 759,254-cycle full-state RTL comparison, and stronger DMC/OAM/
controller/runtime-cartridge integration coverage.

## Audited architecture

All APU state is synchronous to the 50 MHz fabric clock and advances only on
`cpu_cycle_enable`, the complete scheduled NES CPU-time stream. CPU bus events
are accepted only on enabled slots. This distinction is what lets audio time
continue during OAM DMA while debugger pause freezes the complete APU.

The audited register ownership is:

| Address | Write owner | Read owner / policy |
| --- | --- | --- |
| `$4000-$4003` | Pulse 1 | deterministic zero |
| `$4004-$4007` | Pulse 2 | deterministic zero |
| `$4008`, `$400A-$400B` | Triangle | deterministic zero |
| `$4009` | unused; accepted without channel state change | deterministic zero |
| `$400C`, `$400E-$400F` | Noise | deterministic zero |
| `$400D` | unused; accepted without channel state change | deterministic zero |
| `$4010-$4013` | DMC | deterministic zero |
| `$4014` | OAM DMA, never APU | OAM-DMA/system policy |
| `$4015` | five channel enables and DMC IRQ clear | five active bits plus frame/DMC IRQ |
| `$4016` | controller strobe, never APU | Controller 1 |
| `$4017` | APU frame counter | Controller 2 |

The direction-sensitive `$4017` decode and the independent `$4014`/`$4016`
owners remain in the centralized CPU decoder. Dense writes across the entire
window prove that a single accepted CPU write causes one intended update and
that pauses or DMA stalls do not replay it.

The five raw output ranges remain:

| Source | Raw range |
| --- | ---: |
| Pulse 1 | 0..15 |
| Pulse 2 | 0..15 |
| Triangle | 0..15 |
| Noise | 0..15 |
| DMC | 0..127 |

## `$4015` closure

Bits 0 through 4 independently enable Pulse 1, Pulse 2, Triangle, Noise, and
DMC. A Pulse/Triangle/Noise enable bit does not create activity: its status bit
is set only while the corresponding length counter is nonzero. DMC status is
set only while bytes remain in the sample reader. Enabling an idle DMC restarts
the programmed address and length; enabling an already-active DMC does not
reload it.

Reads report the five internal activity sources in bits 0 through 4, zero in
bit 5 under the project open-bus policy, frame IRQ in bit 6, and DMC IRQ in bit
7. A read clears frame IRQ after returning its current value and does not clear
DMC IRQ or alter any activity source. Every write clears DMC IRQ and does not
clear frame IRQ. Directed tests cover all 32 channel masks, repeated reads,
both IRQs independently and together, and both clear orders.

The retained `channel_active[4]` and `dmc_irq_flag` inputs are compatibility
injection points for the earlier phase vector suites. Production ties them
low. Phase 5G comparisons also hold them low so all observed activity and IRQ
state originates in the implemented channels.

## Frame-counter and collision ordering

The existing frame sequencer remains the single source of quarter- and
half-frame clocks for all controlled units. Phase 5G re-verifies:

- exact NTSC 4-step and 5-step event positions;
- the three-cycle terminal frame-IRQ window in 4-step mode;
- no frame IRQ in 5-step mode or while inhibit is active;
- immediate inhibit/latched-frame-IRQ clear on an accepted `$4017` write;
- parity-dependent delayed sequence reset after three or four later CPU slots;
- one immediate quarter-plus-half event when delayed 5-step mode applies; and
- suppression of an adjacent duplicate clock when a natural event occurs just
  before delayed 5-step application.

Channel and frame sequential logic use the repository's established
pre-edge-event ordering. On a collision, a quarter/half event consumes old
channel state, then an accepted register write wins for fields it assigns.
Consequences covered directly include:

- a same-event timer-high write leaves envelope start set for the next quarter;
- a length load on a half event wins over decrement of the old length;
- a same-half sweep write leaves reload set for the next half event;
- a Triangle timer-high write leaves linear reload set for the next quarter;
- a `$4017` write supersedes an older pending frame-control value; and
- an IRQ set at the terminal event wins over a same-cycle `$4015` read-clear.

Before, same-cycle, and after-event tests exercise both quarter and half
boundaries using real channels, not only frame tick outputs.

## IRQ boundary

The module-level APU IRQ is exactly:

```text
frame_irq || dmc_irq
```

It remains asserted until both active sources are cleared by their respective
mechanisms. Reset masks and clears both sources deterministically.

CPU IRQ entry is intentionally not added here. `nes_core` already has the CPU
IRQ input and CPU interrupt machinery, but the production top continues to tie
that input inactive:

```text
nes_apu.irq
    |
    +-- verified Phase 5G module boundary
    |
    +-- future Phase 5I production qualification/wiring
            |
            +-- nes_core.irq -> CPU IRQ entry
```

Pulling CPU-visible interrupt behavior into Phase 5G would change playable
software behavior and bypass the separately planned Phase 5I system work.

## DMC DMA, OAM DMA, controllers, and runtime cartridges

Phase 5G retains the documented Phase 5F accuracy target: a stable held DMC
request becomes one acknowledged read after a write-safe halt, dummy slot,
optional parity alignment slot, and read slot. Address and request remain
stable until acknowledgement. Exactly one byte is consumed; the reader then
increments with `$FFFF->$8000` wrap, decrements bytes remaining once, and
selects stop, loop, or terminal IRQ correctly.

DMC has deterministic priority over OAM DMA. OAM holds its current read/write
phase during each three/four-slot DMC transaction, then resumes without a
dropped or duplicated byte. Directed tests place DMC requests before OAM,
at start, during alternating read/write phases, near completion, and after
completion. They also start OAM while the DMC request is pending and while the
DMC transaction is in progress. Every run preserves all 256 OAM bytes and
exactly one DMC acknowledgement.

Accepted CPU peripheral strobes are suppressed throughout a DMC stall. A held
controller read therefore shifts at most once after the stall; no accidental
duplicate read is introduced. The model does not emulate the physical 2A03's
model-dependent DMC/controller corruption quirk.

The integration test now runs all five channels while CPU code repeatedly
starts OAM DMA and reads a controller. Game A is a generated runtime NROM-128;
DMC reads are checked against the mirrored 16 KiB PRG mapping. Replacement
begins with DMC and OAM live. Functional reset cancels both DMA engines and
clears channel enables, both IRQs, all lengths, envelope/linear state, Noise to
the defined LFSR seed, and all DMC reader/buffer/shifter state. Game B is a
generated NROM-256; it boots from the new vector, proves no stale fetch/data,
and checks DMC reads against the independent upper 16 KiB bank.

## Deferred-issue inventory

Every limitation or future boundary recorded in the Phase 5A–5F documents was
classified before implementation:

| Class | Item | Phase 5G disposition |
| --- | --- | --- |
| A — close in 5G | Complete `$4000-$4017` ownership and register isolation | Closed by directed decode/isolation and dense-write tests. |
| A — close in 5G | Five real `$4015` activity sources and enable/activity distinction | Closed, including all 32 masks and DMC restart semantics. |
| A — close in 5G | Frame events driving all real channels, `$4017` parity/reset, and event/write collisions | Closed by directed channel-state and complete RTL/model comparisons. |
| A — close in 5G | Frame/DMC IRQ coexistence and independent clear rules | Closed at the APU module boundary. |
| A — close in 5G | Complete pause, step, OAM-time, reset, and runtime-replacement behavior | Closed in model, RTL, and real system integration tests. |
| A — close in 5G | DMC/OAM/controller/Mapper-0 interaction at the Phase 5F accuracy target | Closed with systematic collision, non-duplication, NROM-128, and NROM-256 tests. |
| B — Phase 5H | Nonlinear NES pulse and TND mixing | Deliberately untouched; raw codes remain separate. |
| C — Phase 5I | Production `apu_irq` connection and CPU-visible IRQ-entry qualification | Deliberately retained as a verified boundary, not wired here. |
| D — Phase 5J+ | Deterministic sample generation, PCM/WAV reference output, resampling, and 44.1/48 kHz pipeline | Deliberately untouched. |
| D — later output pipeline | I2S and HDMI audio transport | Deliberately untouched. |
| E — physical board | DE1-SoC audio codec integration and physical audible-game validation | Requires board/output phases; not claimed by simulation. |
| F — project policy | Open-bus values, including `$4015` bit 5 and unused APU reads | Deterministic zero remains the documented project-wide policy. |
| F — documented quirk not targeted | Transistor-level DMC/OAM overlap timing | The safe exclusive 3/4-slot transaction and lossless OAM pause remain the explicit accuracy boundary. |
| F — documented quirk not targeted | Hardware DMC/controller repeated-read corruption | Not emulated; the project instead proves no accidental duplicate controller read. |
| F — compatibility only | Earlier-phase external DMC activity/IRQ injectors | Retained for old vectors, tied low in production and in the Phase 5G oracle run. |

Nothing classified A remains open.

## Independent model and verification

`verification/apu.py` now exposes `ApuModel` and `CompleteApuState`, combining
frame/status, both pulses, Triangle, Noise, and DMC transaction/IRQ state.
`ApuFoundationModel` remains an alias so Phase 5A–5F tests retain their stable
interface. `DmcState` now includes the IRQ latch, allowing the complete state
to be compared without reaching into model internals.

`tests/python/test_apu_complete.py` adds 78 directed/parameterized cases. They
cover the required status masks, IRQ combinations, frame modes, parity,
collisions, simultaneous operation, disable/re-enable, reset, pause, step,
OAM timing, DMC/OAM positions, controller shifting, runtime replacement,
NROM mapping, unused-register isolation, dense writes, and long-run invariants.

`scripts/generate_apu_complete_phase5g_vectors.py` uses fixed seed
`0x00572026`. Its packed vectors compare all event outputs plus 377 bits of
post-edge architectural state in `sim/nes_apu_complete_phase5g_tb.sv`:

| Counter | Result |
| --- | ---: |
| Compared cycles | 759,254 |
| Randomized cycles | 600,000 |
| Paused cycles | 109,784 |
| Reset cycles | 49 |
| Accepted reads | 15,720 |
| Accepted writes | 67,405 |
| DMC acknowledgements | 398 |
| Quarter-frame events generated | 1,358 |
| Half-frame events generated | 1,351 |
| All-five-active observations | 39,552 |
| All-five-raw-nonzero observations | 40,501 |
| RTL/model mismatches | 0 |

The strengthened system run reports 12 DMC fetches: eight through NROM-128
mirroring and four through the NROM-256 upper bank. It observes ten DMC/OAM
collisions, eight completed OAM transfers, eight controller reads, 128 paused
fabric cycles, one live runtime replacement, 15,667 all-active cycles, and
4,458 all-raw-nonzero cycles.

Waveforms are written to:

- `build/sim/nes_apu_complete_phase5g.fst`
- `build/sim/nes_dmc_system_phase5f.fst`

The retained Phase 5A–5F comparisons still run independently so a complete
comparison cannot hide a channel-local regression.

## Pre-change baseline

The clean `ecf8586` baseline used Python 3.14.4, Verilator 5.032, and Quartus
Prime Lite / Platform Designer 23.1std.1 Build 993. It passed 1,767 Python
tests, complete lint, every retained simulation, the 300-frame playable run,
83-frame production VGA/Developer Mode run, and 132-frame/187-command debugger
run.

The six APU comparisons passed with zero mismatches:

| Phase | Cycles | Paused/stall cycles |
| --- | ---: | ---: |
| 5A frame/status | 142,214 | 17,531 |
| 5B Pulse 1 | 220,195 | 42,982 |
| 5C Pulse 2 | 272,426 | 51,438 |
| 5D Triangle | 314,560 | 58,023 |
| 5E Noise | 371,608 | 66,769 |
| 5F DMC | 143,324 | 23,780 |

The production build completed with 5,703 ALMs, 7,649 logic ALUTs, 1,082
route-through ALUTs, 5,990 total registers, 5,764 dedicated logic registers,
270 M10Ks, 18,880 MLAB bits, and 2,199,552 block-memory bits. Worst setup was
+1.457 ns, worst hold +0.077 ns, and every timing TNS was 0.000 ns. Map/Fitter/
Assembler/Timing warnings were 100/150/0/146, all in the established generated
IP, board-pin, connectivity, constraint, constant-pin, or clock-advisory
classes.

## Post-change qualification

The final full repository run passed 1,845 Python tests, complete Verilator
lint, every retained simulation, and the new Phase 5G comparison with zero
mismatches. The playable regression completed 300 frames with 297 NMI/OAM-DMA
events. The production VGA/Developer Mode regression completed 83 frames, and
the mixed debugger run completed 132 frames and 187 acknowledged commands.

The production Quartus build also completed successfully. Phase 5G changes no
production RTL, so its fitted resource totals are identical to the baseline:
5,703 ALMs, 7,649 logic ALUTs, 1,082 route-through ALUTs, 5,990 total
registers, 5,764 dedicated logic registers, 270 M10Ks, 18,880 MLAB bits, and
2,199,552 block-memory bits. Multicorner timing closes with +1.457 ns worst
setup slack, +0.077 ns worst hold slack, and 0.000 ns design-wide TNS. The
Map/Fitter/Assembler/Timing warning counts remain 100/150/0/146 with no new
warning class.

## Scope boundary

Phase 5G ends with five independently verified raw channel codes and the
verified APU IRQ/DMC-memory boundaries. It does not implement the nonlinear
mixer and does not begin Phase 5H.

Behavior was cross-checked against the Phase 5A–5F references, including the
[NESdev APU status](https://www.nesdev.org/wiki/APU_Status),
[NESdev APU frame counter](https://www.nesdev.org/wiki/APU_Frame_Counter),
[NESdev DMC](https://www.nesdev.org/wiki/APU_DMC), and
[NESdev DMA](https://www.nesdev.org/wiki/DMA) descriptions.
