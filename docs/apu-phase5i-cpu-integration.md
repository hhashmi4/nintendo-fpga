# Phase 5I — NES CPU/APU system integration

Phase 5I closes the CPU-facing APU boundary. The production DE1-SoC top now
delivers the APU's combined frame/DMC interrupt to the real 2A03 CPU IRQ
input, while the established system bus remains the only path for CPU APU
register accesses. A dedicated system test runs legal generated NROM-128
programs through the runtime cartridge loader and checks actual interrupt,
DMA, controller, debugger, reset, and five-channel audio behavior.

This phase does not add PCM sample-rate conversion, WAV output, I2S, HDMI
audio, the DE1-SoC codec path, or any Phase 5J work.

## Integration audit and closed gap

The pre-change design already contained the required mechanisms:

- `nes_core` routes one CPU transaction at a time through `nes_cpu_bus`, owns
  DMC/OAM arbitration, and exposes an `irq` input to `cpu_core`;
- the bus decodes writes to `$4000-$4013`, `$4015`, and `$4017` to the APU,
  preserves `$4014` for OAM DMA and `$4016` for controller strobe, and decodes
  `$4017` by direction (APU write, Controller 2 read);
- accepted peripheral strobes are gated by `cpu_enable && cpu_bus_valid`, so
  held CPU states during DMA or debugger pause cannot replay a register access;
- `nes_apu` already combines frame and DMC interrupt sources and implements
  their distinct acknowledgement rules; and
- `cpu_core` already implements synchronized level IRQ, edge-latched NMI,
  instruction-boundary polling, I-flag masking, the NMOS CLI/SEI/PLP old-I
  poll behavior, NMI priority, hardware interrupt stacking, BRK, and RTI.

The production top nevertheless tied `nes_core.irq` low. Thus software could
read APU IRQ flags at `$4015`, but the CPU could never enter an APU interrupt
handler. Phase 5I replaces that tie-off with `apu_irq`. The retained Phase 5F
runtime-system bench uses the same real connection so future regressions cannot
silently restore the tie-off.

## CPU/APU register path

The register split is unchanged:

| CPU access | Owner | Meaning |
| --- | --- | --- |
| `$4000-$4013` write | APU | Pulse, Triangle, Noise, and DMC control |
| `$4014` write | OAM DMA | Sprite DMA trigger |
| `$4015` read/write | APU | Status/read-clear and channel/DMC control |
| `$4016` read/write | Controller | Controller 1 read and shared strobe |
| `$4017` read | Controller | Controller 2 serial read |
| `$4017` write | APU | Frame-counter control |

The bus produces a one-fabric-cycle APU strobe only for an accepted CPU bus
cycle. The Phase 5I monitor rejects stretched writes and any APU/controller
strobe while the CPU is DMC-stalled. This covers ordinary execution, OAM/DMC
DMA, pause, CPU-slot stepping, frame stepping, and handler execution.

The project-wide I/O open-bus policy is preserved: `$4015` returns channel
activity in bits 0-4, zero in bit 5, frame IRQ in bit 6, and DMC IRQ in bit 7.
A `$4015` read clears only frame IRQ. A `$4015` write clears DMC IRQ and applies
the five enables. Clearing `$4010.7` also clears DMC IRQ; an inhibited `$4017`
write clears frame IRQ. A terminal frame event concurrent with `$4015` read is
visible in the read and wins the sequential set/clear collision.

## IRQ wiring and CPU sequence

`nes_apu.irq` is a level-sensitive OR of the frame source (including its
current terminal set event) and the DMC channel's registered terminal IRQ.
It enters the existing two-flop CPU IRQ synchronizer. It is neither converted
to a pulse nor routed through reset/NMI logic. If either source remains set,
the CPU continues to see IRQ after synchronization.

At a fetch boundary the CPU accepts IRQ only when no NMI is pending and the
effective interrupt-disable state permits it. Acceptance performs the real
bus sequence: dummy read, PC high push, PC low push, status push, `$FFFE`
read, and `$FFFF` read. Hardware IRQ pushes B=0 and U=1, decrements SP three
times, sets I during entry, and begins at the vector target. The generated
handler acknowledges the relevant APU source, writes a RAM signature, and
executes RTI. RTI normalizes/restores status, pulls PC low/high, restores SP,
and resumes the interrupted program.

The legal test ROM verifies seven hardware IRQ entries:

1. DMC only, acknowledged by `$4015` write;
2. frame only, acknowledged by `$4015` read and an inhibited `$4017` write;
3. both sources, clearing frame first while DMC holds IRQ;
4. both sources, clearing DMC first while frame holds IRQ;
5. frame IRQ retained across a real PPU NMI and accepted after NMI RTI;
6. a deliberately unacknowledged frame IRQ returned from by RTI; and
7. the resulting level-sensitive re-entry, then final acknowledgement.

Before the frame-only case the ROM keeps IRQ pending under SEI, then executes
CLI followed by NOP. This checks the 2A03 old-I polling boundary and eventual
acceptance without losing the level.

## NMI, BRK, and RTI priority

NMI is edge-latched and wins when NMI and IRQ are both eligible at a fetch
boundary. The Phase 5I bench raises an actual PPU NMI while frame IRQ is
already high, proves the NMI vector `$FFFA/$FFFB` is used first, proves no IRQ
entry occurs before the NMI handler signature, then observes the retained APU
IRQ through NMI RTI and its subsequent `$FFFE/$FFFF` entry.

BRK remains a software interrupt sharing `$FFFE/$FFFF`. Its padding-byte
semantics produce PC+2 and its pushed status has B=1/U=1; hardware IRQ and NMI
push B=0/U=1. The bench checks the stack addresses, pushed PC against the
CPU's recorded return address, pushed status bits, source-selected vector,
one RTI completion per IRQ/NMI/BRK entry, and the post-handler ROM signatures.

## DMC/OAM DMA and controllers

The existing arbiter remains authoritative:

- DMC waits until a CPU read or an OAM-owned slot can be halted; it does not
  steal a CPU write;
- accepted DMC reads use the normal CPU-space decode and runtime Mapper-0 PRG
  path, hold address/request until one acknowledgement, and stall the CPU for
  the established parity-dependent three/four-slot sequence;
- DMC has priority while OAM DMA is active; OAM state is held and resumes with
  all 256 reads and 256 writes intact; and
- APU time advances on every scheduled CPU-time slot during either DMA.

The system run completes 142 DMC fetches, four observed DMC/OAM collision
events, two OAM transfers, and a DMC fetch while executing inside the IRQ
handler. Directed model tests also cover a request during a CPU read, deferral
next to a CPU write, preservation of an already-created interrupt stack frame,
and exact OAM hold/resume. The retained CPU interrupt suite injects stalls
through every interrupt state, including vector and RTI states.

Controller reads remain accepted CPU transactions, never DMC transactions.
The ROM reads both `$4016` and direction-split `$4017`; the monitor counts each
read once and rejects controller shifts during DMC stall. The implementation
does not emulate the analog 2A03 DMC/controller extra-clock corruption quirk.
Likewise, DMC-over-OAM arbitration is the project's documented safe/exclusive
model rather than a claim of transistor-exact overlap timing.

## Debugger and runtime cartridge behavior

Debugger pause suppresses the scheduler, freezing CPU, APU, DMC DMA, OAM DMA,
frame sequencing, and pending IRQ state. The system bench pauses with an IRQ
and DMC request pending, authorizes exactly one CPU-time slot twice, performs a
25,110-slot frame step, pauses inside the IRQ handler, and resumes. It observes
256 paused fabric cycles, two single-slot steps, no repeated APU write, and no
duplicated DMA/controller transaction. The retained debugger tests separately
pass RUN, PAUSE, instruction step, frame step, resume, command CDC, NMI/DMA
stepping, Developer Mode, and the 132-frame playable mixed run.

The generated Game A and Game B images travel through the actual runtime
loader/storage/Mapper-0 activation path. Game A configures all five channels,
fetches DMC sample bytes from PRG, services the interrupt matrix, then reaches
replacement with DMC IRQ and OAM DMA active. Loader activation asserts the
functional NES reset, which synchronously clears CPU/APU/channel/frame/DMC and
both DMA engines. Game B then boots from its own reset vector, disables the
APU, inhibits frame IRQ, writes `$99` to RAM `$002F`, and remains free of stale
IRQ, request, DMA, or channel state.

The ROM generator emits inspectable legal NROM-128 iNES images, matching
one-byte-per-line PRG files for `$readmemh`, and a label/CRC reference file.
No third-party or commercial ROM content is present.

## Five-channel audio

Game A programs Pulse 1, Pulse 2, Triangle, Noise, and DMC concurrently. The
Phase 5I run observes 180,586 samples with all five channels active, 17,322
samples with every raw DAC code nonzero, and 620,039 total mixed-output
observations. It does not add an audio sample clock or resampler.

Mixer correctness remains checked independently: the Phase 5I Python test
compares a programmed all-channel state with `quantized_mix`; the retained
Phase 5H dedicated comparison checks 37,137 RTL rows; and the complete APU
oracle checks the Q0.20 mixed value and all raw/state fields on all 774,134
cycles. All report zero mismatches.

## Independent verification and directed coverage

`verification.nes_system.ApuIrqSources` models the CPU-visible source contract
without copying the RTL state machine: two independent level sources, their
ORed line, status composition, source-specific acknowledgements, and reset.
It composes with the existing instruction-level CPU reference and independent
DMC/OAM models. Twenty-six named Phase 5I Python tests cover all requested
areas: register decode, `$4015`, frame and DMC IRQ, both-source clear orders,
mask/pending/unmask, NMI priority and deferred IRQ, BRK, RTI, stack/vector,
DMC read/write/entry/OAM cases, controllers, pause/step, replacement, five
channels, mixer output, pending-IRQ reset, and generated-image legality.

`sim/nes_apu_cpu_phase5i_tb.sv` instantiates the real CPU, APU, PPU NMI path,
system bus, DMC/OAM engines, controllers, runtime loader, storage, and Mapper 0.
Its deterministic long run reports:

| Measure | Result |
| --- | ---: |
| Fabric cycles | 685,592 |
| Scheduled CPU slots | 206,577 |
| CPU instruction fetches | 68,364 |
| Hardware IRQ / NMI / BRK entries | 7 / 1 / 1 |
| RTI completions | 9 |
| DMC fetches / DMC-OAM collision events | 142 / 4 |
| OAM completions / controller reads | 2 / 2 |
| APU writes / `$4015` reads | 68 / 59 |
| Mixed-output observations | 620,039 |
| All-active / all-nonzero observations | 180,586 / 17,322 |
| Pause cycles / single slots / frame-step slots | 256 / 2 / 25,110 |
| Mismatches | 0 |

Every entry is checked at the interrupt stack and vector cycles, not inferred
only from the IRQ wire. RAM signatures additionally prove handler execution,
acknowledgement order, RTI return, and resumed foreground execution.

## Baseline and regression results

The clean `2dcbe3f` baseline used Python 3.14.4, pytest 8.3.5, Verilator
5.032, Quartus Prime Lite 23.1std.1 Build 993, and Platform Designer 23.1.
It passed 1,874 Python tests, strict RTL lint, every retained simulation,
the 300-frame playable run, 83-frame Developer Mode run, 132-frame debugger
run, and production compilation. Baseline fit/timing was 6,165 ALMs, 8,365
logic ALUTs, 1,110 route-through ALUTs, 6,342 registers, 270 M10Ks, two DSPs,
+0.575 ns worst setup, +0.077 ns worst hold, and zero TNS. Map/Fitter/
Assembler/Timing warnings were 100/150/0/146; all were nonfatal established
board, generated HPS/IP, legacy cartridge, and timing-advisory categories.

Final qualification passes 1,900 Python tests, Verilator lint, the new Phase
5I run, the 774,134-cycle complete APU comparison, the 37,137-row mixer run,
the retained 143,324-vector DMC comparison, systematic DMC/OAM runtime tests,
all CPU interrupt suites, PPU/NMI, controllers, Mapper 0, runtime loader/boot,
the Phase 4F-H library, VGA, 300-frame playable, 83-frame Developer Mode, and
132-frame debugger regressions. Existing tests and constraints were not
weakened.

## Production Quartus result

Full Analysis & Synthesis, Fitter, Assembler, Timing Analyzer, and SOF-to-RBF
conversion pass for `5CSEMA5F31C6`:

| Resource/timing item | Phase 5I |
| --- | ---: |
| ALMs | 6,151 / 32,070 (19%) |
| Logic ALUTs | 8,344 |
| Route-through ALUTs | 1,111 |
| Memory ALUTs | 590 |
| Total / dedicated registers | 6,323 / 6,097 |
| M10Ks | 270 / 397 (68%) |
| MLAB bits / block-memory bits | 18,880 / 2,199,552 |
| DSP blocks / PLLs | 2 / 1 |
| Worst setup slack | +1.013 ns |
| Worst hold slack | +0.077 ns |
| TNS | 0.000 ns in every reported domain/corner |

The worst setup path is in the 25.2 MHz VGA domain from `video.output_x[9]`
to `VGA_B[5]`. The slow-85C `CLOCK_50` critical path is from CPU decoded
addressing-mode state into the registered APU mixer TND segment and has
+1.366 ns slack. The global hold limit is an HPS DDR hard-memory-PHY LFIFO to
OCT output-enable path; the slow-85C `CLOCK_50` OAM-address-to-MLAB path has
+0.283 ns hold slack. The design is fully constrained for setup and hold.

Map/Fitter/Assembler/Timing warnings are 101/148/0/144 (393 total), with zero
errors. The profile remains generated HPS/DDR IP unmatched/empty timing
filters, generated-IP no-driver/truncation notices, incomplete unused board
I/O, PLL compensation, bidirectional-buffer, legacy Mapper-0 initialization,
and the tied VGA sync pin. There is no negative slack, unconstrained setup or
hold path, or Phase 5I functional warning.

## Remaining accuracy boundary and Phase 5J

Phase 5I proves system-level CPU/APU interaction in simulation and production
synthesis. Physical DE1-SoC validation remains unavailable. The CPU IRQ input
uses the project's explicit two-flop synchronization boundary; DMC DMA and its
controller/OAM collisions retain the safe timing approximation documented in
Phase 5F rather than asserting every silicon bus quirk.

Phase 5J may consume the verified Q0.20 mixer boundary to define a PCM sample
rate, filtering/resampling, and reference output. It must not change the IRQ,
register, DMA, controller, debugger, or runtime contracts proven here without
extending these tests. Phase 5J was not started in this change.
