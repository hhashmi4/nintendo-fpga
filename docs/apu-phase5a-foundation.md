# Phase 5A — NES APU foundation

Phase 5A establishes the timing, register, status, frame-sequencer, IRQ, and
verification architecture for the NTSC Ricoh 2A03 APU. It does not synthesize
audible channels, mix samples, drive the DE1-SoC codec, or implement DMC DMA.
Those remain separate Phase 5 subphases.

## Architectural boundary

```text
NES CPU bus ($4000-$4017)       complete NES CPU-time slots
             |                              |
             v                              v
        +------------------------------------------------+
        | nes_apu                                        |
        |                                                |
        | register events  $4015 state/status            |
        | $4017 delayed control  NTSC frame sequencer    |
        | quarter/half ticks      frame IRQ latch         |
        +------+--------------------+--------------------+
               |                    |
               v                    v
       future channel blocks   APU IRQ boundary
       P1/P2/T/N/DMC           (CPU connection in 5I)
               |
               v
       future nonlinear mixer -> sample stream -> codec
```

`rtl/apu/nes_apu_pkg.sv` owns register addresses, status-bit positions, frame
mode type, and exact NTSC sequence positions. `rtl/apu/nes_apu.sv` owns the
Phase 5A state. It exposes one-shot channel-register write events, channel
enable state, placeholder channel-active and DMC-IRQ inputs, frame ticks, and
the APU IRQ output. Future channel modules can consume those interfaces without
redefining CPU bus timing.

The production `de1_soc_nes_vga_top` instantiates this shell on the APU bus
already decoded by `nes_core`. `$4014` remains exclusively OAM DMA, `$4016`
remains Controller 1, `$4017` reads remain Controller 2, and `$4017` writes
reach the APU frame counter. No address ownership changed.

## Clock and execution contract

The design retains one 50 MHz FPGA clock and uses enables, never generated APU
clocks. `nes_timing_gen` creates the existing NTSC rational-rate enable stream;
`nes_core` advances a three-phase PPU/CPU scheduler only while the debugger
authorizes execution. The APU receives `nes_core.cpu_cycle_slot`, the complete
NES CPU-time slot stream.

This choice has three important consequences:

- A debugger pause stops the scheduler, so all APU state and event outputs
  stop. Instruction and frame steps advance exactly the CPU slots authorized
  by the debugger.
- OAM DMA suppresses `cpu_enable` but does not suppress `cpu_cycle_slot`.
  Therefore APU time continues through all 513 or 514 DMA slots.
- APU writes are still the bus router's accepted `apu_cpu_write` strobes.
  They occur only when the CPU owns an enabled valid bus cycle. A pause, DMA
  stall, or fabric-clock gap cannot repeat a write.

The APU's `cpu_cycle_odd` state toggles on every complete CPU-time slot,
including DMA. Reset defines the first accepted slot as even for deterministic
project behavior and for the `$4017` delay rule below.

## Register contract

### `$4000-$4013`

An accepted write emits exactly one `channel_write` pulse with the low
five-bit register index and eight-bit data. Phase 5A deliberately stores no
fake pulse, triangle, noise, or DMC register behavior. Future channel blocks
will consume this event.

Reads from write-only APU registers return zero under the project's current
open-bus simplification. Phase 5A does not broaden scope into a CPU data-bus
latch model.

### `$4015` write

Bits 0 through 4 are retained as the Pulse 1, Pulse 2, Triangle, Noise, and
DMC enable mask. An enable bit is not an active-status bit: future channels
will clear or retain their owned length/sample state according to these
enables. Every accepted `$4015` write also produces `dmc_irq_clear`, but Phase
5A has no DMC IRQ latch to mutate.

### `$4015` read

The returned value is:

| Bit | Phase 5A source |
|---:|---|
| 0–4 | future channel-active inputs, tied low in production today |
| 5 | zero under the current open-bus simplification |
| 6 | frame IRQ flag |
| 7 | future DMC IRQ input, tied low in production today |

An accepted status read clears the frame IRQ flag but not the externally owned
DMC IRQ flag. If a terminal frame IRQ is set on the same accepted CPU cycle,
the read reports bit 6 and the set wins over the read-clear. This policy is
explicitly modelled and tested.

### `$4017` write

Bit 7 selects 4-step or 5-step mode. Bit 6 inhibits frame IRQ. IRQ inhibit
takes effect on the write cycle and setting it immediately clears a latched
frame IRQ. The mode and sequence reset take effect later:

- a write on the project's even/APU CPU parity applies after three later CPU
  cycles;
- a write on odd/between-APU parity applies after four later CPU cycles;
- applying 5-step mode normally emits simultaneous one-cycle quarter- and
  half-frame ticks;
- a newer `$4017` write supersedes an older pending value.

Natural frame counting continues during the delay. This avoids hiding the
well-known parity quirk behind an approximate millisecond timer.

The frame units cannot be clocked on adjacent CPU cycles. A natural frame
event therefore blocks a delayed 5-step application tick on the immediately
following slot; the mode change and sequence reset still occur. This collision
case is represented by explicit state, freezes with debugger pause, and is
covered by both the directed model tests and RTL comparison.

## NTSC frame sequencer

All positions are integer 2A03 CPU-cycle counts. `frame_sequence_cycle` starts
at zero and an event at position *N* is observed on the slot that advances to
*N*.

| Mode | CPU cycle | Quarter | Half | Frame IRQ action |
|---|---:|:---:|:---:|---|
| 4-step | 7,457 | yes | no | — |
| 4-step | 14,913 | yes | yes | — |
| 4-step | 22,371 | yes | no | — |
| 4-step | 29,828 | no | no | set if allowed |
| 4-step | 29,829 | yes | yes | set if allowed |
| 4-step | 29,830 | no | no | set if allowed, then wrap |
| 5-step | 7,457 | yes | no | — |
| 5-step | 14,913 | yes | yes | — |
| 5-step | 22,371 | yes | no | — |
| 5-step | 29,829 | no | no | — |
| 5-step | 37,281 | yes | yes | — |
| 5-step | 37,282 | no | no | wrap |

The no-event entries are retained because they define exact terminal behavior,
not because they create broad event levels. `quarter_frame_tick` and
`half_frame_tick` are single fabric-cycle pulses aligned to an enabled NES CPU
slot. A half-frame tick always also has a quarter-frame tick.

The sequence and delayed-reset behavior follow the cycle table used by
[Mesen2's APU frame counter](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/APU/ApuFrameCounter.h).
The status and control side effects follow the
[NESdev APU status documentation](https://www.nesdev.org/wiki/APU_Status) and
[NESdev APU register map](https://www.nesdev.org/wiki/APU_registers).

## IRQ ownership

The 4-step terminal window sets `frame_irq_flag` when IRQ inhibit is clear.
Five-step mode never sets it. The APU module's `irq` output currently reflects
only frame IRQ. The DMC status input is intentionally not ORed into `irq` yet;
the future DMC phase will own that latch and its clear rules.

The production top keeps `nes_core.irq` tied inactive during 5A. Connecting
`apu_irq`, qualifying CPU-visible IRQ entry, and combining the future DMC IRQ
are reserved for Phase 5I full system integration. The correct module boundary
exists and is independently verified now, without silently changing playable
software behavior in a foundation phase.

## Reset behavior

Synchronous reset deterministically selects 4-step mode, clears IRQ inhibit
and the frame IRQ flag, clears all five channel enables, sets sequence count
and CPU parity to zero, and cancels any pending `$4017` update. Bus events,
frame ticks, read data, and IRQ are masked while reset is asserted. Reset is
tested after nonzero channel, sequence, parity, and pending-control state.

## Future Phase 5 plan

- **5B:** Pulse 1 foundation, timer/duty, and the required length/envelope/
  sweep interactions.
- **5C:** Pulse 2 using the shared pulse architecture.
- **5D:** Triangle timer, sequencer, length, and linear counter.
- **5E:** Noise timer/LFSR, length, and envelope.
- **5F:** DMC output unit, sample memory request, bus arbitration/CPU stalls,
  and DMC IRQ. The current DMC status/clear boundary does not assume an
  arbitration implementation.
- **5G:** shared behavior completion and cross-channel/IRQ edge qualification.
- **5H:** hardware-faithful nonlinear NES mixer.
- **5I:** full CPU/APU/system IRQ and DMC-bus integration.
- **5J:** deterministic sample generation and WAV/reference validation.
- **5K:** DE1-SoC codec and physical audio-output integration.
- **5L:** physical game-audio validation.

No later-phase behavior is emulated or stubbed with fake sound in 5A.

## Verification architecture

`verification/apu.py` is an independent executable specification. It computes
accepted bus actions, event timing, delayed frame-control application, IRQ
priority, status data, and post-edge state without importing RTL-generated
tables. `tests/python/test_apu.py` provides directed schedule, reset, status,
parity-delay, pause, and 100,000-cycle invariant tests.

`scripts/generate_apu_phase5a_vectors.py` creates 142,214 deterministic cycles
from that model. The self-checking `sim/nes_apu_phase5a_tb.sv` compares every
pre-edge output and post-edge architectural state against the oracle. Coverage
includes:

- every `$4000-$4013` write address;
- `$4015` enable, active-status, frame IRQ, DMC placeholder, and read-clear;
- exact complete 4-step and 5-step sequences;
- even and odd `$4017` delays and immediate 5-step clocks;
- natural-tick/delayed-5-step collision suppression;
- 17,531 enable-off/pause cycles;
- deterministic reset at arbitrary state;
- fixed-seed randomized reset, bus direction/address/data, channel status,
  DMC status, clock-enable, and control traffic.

The existing playable debugger test additionally observes the production APU
instance. It holds all APU architectural state stable across ten VGA frames of
NES pause, checks deterministic advancement for instruction and frame steps,
and proves sequence progression during OAM DMA. Existing exhaustive Phase 4A
decode tests retain the `$4014/$4016/$4017` ownership proof.

## Pre-change baseline

The clean `f7ab5ee` baseline passed all 1,412 Python tests, complete Verilator
lint and simulation regression, 300-frame playable run, and 132-frame/
187-command debugger run. The production DE1-SoC build completed with 5,559
ALMs, 7,378 combinational ALUTs, 5,845 total registers, 270 M10Ks, 2,199,552
block-memory bits, +1.312 ns worst setup slack, and +0.077 ns worst hold slack.
It reported 396 established HPS/clock/generated-IP warnings and no errors or
timing violations.

## Post-change qualification

The completed Phase 5A tree passes all 1,422 Python tests, complete Verilator
lint, and the full retained RTL regression. The APU-specific RTL comparison
checks 142,214 Python-reference cycles, including 17,531 disabled CPU-time
slots. The retained integration results include the 300-frame playable run
(297 NMI handlers and 297 DMA transfers), the 83-frame production-top
video/Developer Mode run, and the 132-frame/187-command playable debugger run.

The production DE1-SoC synthesis, fit, assembly, and all-corners timing flow
completed successfully with:

| Resource/result | Post-change result |
|---|---:|
| ALMs | 5,533 / 32,070 (17%) |
| Combinational ALUTs for logic | 7,433 |
| Route-through ALUTs | 1,117 |
| Total registers | 5,838 |
| Dedicated logic registers | 5,612 |
| M10Ks | 270 / 397 (68%) |
| Block-memory bits | 2,199,552 / 4,065,280 (54%) |
| MLAB memory bits | 18,880 |
| Worst setup slack | +1.560 ns |
| Worst hold slack | +0.077 ns |
| Worst timing TNS | 0.000 ns |

The build is fully constrained and produced both SOF and RBF programming
artifacts. Quartus reported 397 warnings and no errors: one more aggregate
warning than the baseline, still within the existing HPS/generated-IP,
clock-constraint, incomplete-board-pin, and constant-pin classes. No warning
names the APU hierarchy or either new APU source file.
