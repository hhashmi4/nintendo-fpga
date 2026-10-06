# Phase 5B — NES APU Pulse 1

Phase 5B adds the first sound-producing NES channel. Pulse 1 accepts the real
`$4000-$4003` register fields, runs its duty sequencer, timer, envelope, length
counter and sweep unit in NES time, and exposes a raw digital amplitude from 0
through 15. This phase does not mix, resample or route audio to board hardware.

## Architecture

```text
complete CPU-time slots       Phase 5A frame events
          |                  quarter       half
          |                     |            |
          v                     v            v
  +------------------------------------------------+
  | nes_apu_pulse (CHANNEL_ONE=1)                  |
  |                                                |
  | $4000-$4003 -> duty/timer/envelope/length/sweep|
  |                  |                             |
  |                  +---- gating ----> raw 0..15 |
  +------------------------+-----------------------+
                           |
          active length ---+---> $4015 status bit 0
```

`rtl/apu/nes_apu_pulse.sv` is reusable for the later second pulse channel, but
the `CHANNEL_ONE` parameter makes the channel-one sweep-negate correction
explicit. `nes_apu` instantiates only Pulse 1 in this phase. Shared length and
duty constants live in `nes_apu_pkg`; there is no duplicate bus decoder or
frame sequencer.

All state remains in the 50 MHz fabric clock domain. `cpu_cycle_enable` is the
complete NES CPU-time slot from `nes_core`, while `timer_tick` selects every
other accepted CPU slot. Register events, quarter-frame events and half-frame
events are one-fabric-clock pulses consumed only when `cpu_cycle_enable` is
true.

## Registers

| Address | Bits | Pulse 1 behavior |
|---|---|---|
| `$4000` | `DDLC VVVV` | duty `DD`; envelope loop/length halt `L`; constant-volume select `C`; volume or envelope period `VVVV` |
| `$4001` | `EPPP NSSS` | sweep enable `E`; divider period `PPP`; negate `N`; shift `SSS`; write sets the sweep reload flag |
| `$4002` | `LLLL LLLL` | low eight bits of the 11-bit timer period |
| `$4003` | `IIIII HHH` | length index `IIIII`; high timer bits `HHH`; reset duty position to zero; request envelope restart |

A `$4003` write loads length only while Pulse 1 is enabled by `$4015`. It does
not reset the current timer divider. Reads of these write-only registers retain
the project's existing zero/open-bus simplification.

## Duty sequencer

The sequencer has eight explicit states. `$4003` selects position zero and each
timer expiration decrements the position modulo eight. Listed in chronological
order—position zero, then positions 7 down through 1—the output bits are:

| Duty | Nominal ratio | Eight output bits |
|---:|---:|---|
| 0 | 12.5% | `0 1 0 0 0 0 0 0` |
| 1 | 25% | `0 1 1 0 0 0 0 0` |
| 2 | 50% | `0 1 1 1 1 0 0 0` |
| 3 | 25% negated | `1 0 0 1 1 1 1 1` |

The implementation uses these exact patterns rather than a generic PWM duty
comparison. Directed tests cover all 32 duty/position combinations, and the
RTL waveform test checks exact four-bit output samples across a full sequence.

## Timer and frequency

The 11-bit period is assembled from `$4002` and `$4003`. On every other NES CPU
cycle, a nonzero divider decrements. At zero it reloads from the programmed
period and advances the duty sequencer. A duty step therefore lasts
`2 * (period + 1)` CPU cycles, and one complete waveform lasts:

```text
sequence CPU cycles = 16 * (period + 1)
pulse frequency      = NTSC CPU frequency / (16 * (period + 1))
```

The Python checks use 1,789,773 Hz for human-readable frequency estimates;
synthesizable RTL uses only integer counters. Periods below 8 are muted. Period
8 is the first valid boundary and has a 144-CPU-cycle waveform period.

## Length counter

`nes_apu_pkg` owns the single shared 32-entry table indexed by `$4003[7:3]`:

```text
10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14,
12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30
```

An enabled `$4003` write loads the selected value. Each Phase 5A half-frame
event decrements a nonzero counter unless `$4000[5]` halts it. Clearing Pulse 1
enable in `$4015` clears the counter on that accepted write edge. Setting enable
does not create length or activity; software must subsequently load it. `$4015`
status bit 0 is the real `length_counter != 0` state, not the enable bit.

## Envelope

`$4003` sets the envelope start flag. On the next Phase 5A quarter-frame event,
the envelope clears start, sets decay to 15 and reloads its divider from
`$4000[3:0]`. Later quarter events decrement the divider. Divider expiration
reloads it and decrements decay; decay stops at zero unless the loop flag
`$4000[5]` wraps it to 15. Constant-volume mode selects `$4000[3:0]` directly
without disabling the envelope state machine.

Rewriting `$4000` changes the fields but does not restart the envelope. A new
`$4003` write does restart it.

## Sweep

The sweep change amount is `period >> shift`. Pulse 1 calculates the target as:

```text
positive: target = period + change
negative: target = period - change - 1
```

The extra subtraction is the Pulse 1 one's-complement negate quirk. Pulse 2
will use `period - change` instead, which is why the channel identity is an
explicit module parameter rather than an accidental shared rule.

Each half-frame event clocks the sweep divider. When its old value is zero, an
enabled sweep with nonzero shift, a current period of at least 8 and an
in-range target updates the timer period. A `$4001` write requests a divider
reload on the next half-frame event. Shift zero never updates the timer.

The channel mutes when the current timer is below 8 or a positive target is
greater than `$7FF`. The target is calculated at 12-bit width so overflow is
observable rather than silently truncated. The target mute calculation remains
active even when sweep updates are disabled, matching the pulse-unit output
behavior.

## Output gating

The raw four-bit output is the constant volume or current envelope decay only
when all of these conditions hold:

- Pulse 1 enable in `$4015` is set;
- the length counter is nonzero;
- the current duty bit is one;
- the timer period is at least 8; and
- a positive sweep target does not overflow `$7FF`.

Otherwise it is zero. The signal is retained at the APU boundary for the future
mixer. It is not an analog sample, nonlinear mixed value or audio-codec stream.

## Frame timing, debugger and DMA

The channel consumes the existing Phase 5A `quarter_frame_tick` and
`half_frame_tick`; it creates no second frame sequencer. Half events clock both
length and sweep, while quarter events clock the envelope.

Debugger pause removes complete NES CPU-time slots, freezing timer, duty,
envelope, length and sweep state across arbitrarily many fabric clocks. A step
accepts exactly one slot, so held register levels cannot duplicate writes or
frame clocks. OAM DMA stalls the CPU core but does not remove CPU-time slots;
the Pulse 1 timer therefore continues on its normal alternating phase during
DMA.

Reset gives every field an explicit zero value, including the timer divider,
duty position, envelope state, length counter, sweep state and output-driving
state. Tests assert reset during an active tone, envelope decay and configured
sweep.

## Verification

The readable behavioral specification in `verification/apu.py` independently
models the registers, timing units, gating, reset and time-enable semantics.
`tests/python/test_apu_pulse1.py` adds 69 collected cases, including all four
duties, all eight positions, all 32 length indices, timer boundaries, exact
waveforms, envelope loop/stop/restart, sweep reload/overflow/shift-zero and the
Pulse 1 negate quirk, `$4015`, pause, single-step, DMA time and frequency math.
The complete Python suite contains 1,491 passing tests.

`scripts/generate_apu_pulse1_phase5b_vectors.py` uses fixed seed `0x005B2026`
to generate 220,195 cycles. `sim/nes_apu_pulse1_phase5b_tb.sv` compares all
architectural state and combinational outputs after every edge:

| Coverage counter | Value |
|---|---:|
| Compared cycles | 220,195 |
| Pause/stall cycles | 42,982 |
| Accepted writes | 9,454 |
| Quarter-frame events | 2,232 |
| Half-frame events | 1,052 |
| Pulse timer ticks | 88,413 |
| RTL/model mismatches | 0 |

The test emits `build/sim/nes_apu_pulse1_phase5b.fst`. The unchanged Phase 5A
top-level comparison also passes 142,214 cycles, covering `$4015` integration
through the actual `nes_apu` instance.

The full retained regression passes: CPU, PPU, system bus, Mapper 0,
controllers, OAM DMA, runtime loading 4F-A through 4F-H, VGA, Developer Mode,
the 300-frame playable run with 297 NMI handlers and 297 DMA transfers, and the
132-frame debugger run with 187 commands and acknowledgements. Strict
Verilator 5.032 lint passes.

## Quartus results

The production DE1-SoC synthesis, fit, assembly and all-corners timing flow
completed successfully and produced SOF and RBF artifacts.

| Resource/result | Phase 5A | Phase 5B | Delta |
|---|---:|---:|---:|
| ALMs | 5,533 | 5,576 | +43 |
| Combinational ALUTs for logic | 7,433 | 7,457 | +24 |
| Route-through ALUTs | 1,117 | 1,104 | -13 |
| Total registers | 5,838 | 5,852 | +14 |
| Dedicated logic registers | 5,612 | 5,626 | +14 |
| M10Ks | 270 | 270 | 0 |
| Block-memory bits | 2,199,552 | 2,199,552 | 0 |
| MLAB memory bits | 18,880 | 18,880 | 0 |
| Worst setup slack | +1.560 ns | +1.314 ns | -0.246 ns |
| Worst hold slack | +0.077 ns | +0.077 ns | 0.000 ns |
| Worst TNS | 0.000 ns | 0.000 ns | 0.000 ns |

The modest logic/register growth is consistent with one 11-bit timer, small
control counters and output gating; memory use is unchanged. Quartus reported
397 warnings and zero errors. The measured pre-change run reported 396, while
the committed Phase 5A report also records 397. The profile remains the
established HPS/generated-IP, clock-constraint, incomplete-board-pin and
constant-pin classes; no warning names `nes_apu`, `nes_apu_pulse` or either APU
source file. The design is fully constrained for setup and hold.

## References

Register, sweep and muting semantics follow the
[NESdev APU register map](https://www.nesdev.org/wiki/APU_registers) and
[NESdev sweep documentation](https://www.nesdev.org/wiki/APU_Sweep). Duty,
envelope and length behavior were cross-checked against the open-source
[Mesen2 square channel](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/APU/SquareChannel.h),
[envelope](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/APU/ApuEnvelope.h),
and
[length counter](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/APU/LengthCounter.h).

## Limitations and next phase

Phase 5B intentionally does not implement Pulse 2, Triangle, Noise, DMC, the
NES nonlinear mixer, resampling, I2S, HDMI audio, WAV output or the DE1-SoC
codec. The raw Pulse 1 amplitude is verified but is not yet audible.

The exact next phase is **Phase 5C — NES APU Pulse Channel 2**. It can reuse the
pulse architecture while selecting Pulse 2's distinct negate calculation. No
Phase 5C implementation is included here.
