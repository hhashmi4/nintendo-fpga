# Phase 5E — NES APU Noise Channel

Phase 5E adds the NTSC NES Noise channel beside Pulse 1, Pulse 2, and
Triangle. It implements the channel through the existing APU register-write,
frame-sequencer, CPU-time, pause, and DMA boundaries. The four raw channel
codes remain independent; this phase does not add a mixer or audio output.

```text
complete CPU/APU slots                 shared frame events
          |                         quarter           half
          v                            |                |
    every-other-slot timer             v                v
          |                    +------------+     +----------+
          v                    | envelope   |     | length   |
    NTSC period divider        +------------+     +----------+
          |                           |                 |
          v                           +--------+--------+
    15-bit LFSR                                |
          |                                    v
          +---------------------------> output gate ---> 0..15
```

The implementation is in `rtl/apu/nes_apu_noise.sv`. `nes_apu.sv` supplies
the already-qualified register write, existing quarter/half events, stored
`$4015` enable, and the same every-other-CPU-slot timer tick used by the pulse
channels. There is no second bus decoder or frame sequencer.

## Register map

| Address | Bits | Behavior |
|---|---|---|
| `$400C` | 5 | envelope loop and length-counter halt |
| `$400C` | 4 | constant-volume select |
| `$400C` | 3:0 | envelope divider period or constant volume |
| `$400D` | all | unused; accepted and ignored without side effects |
| `$400E` | 7 | LFSR mode: 0 long/normal, 1 short |
| `$400E` | 3:0 | NTSC Noise period-table index |
| `$400F` | 7:3 | shared length-table index |
| `$400F` | — | sets the envelope start flag |

Bits 6:4 of `$400E` and bits 2:0 of `$400F` do not alter channel state.
`$400F` loads length only while `$4015` bit 3 is enabled, but its envelope
restart behavior is independent of enable. A `$400F` write does not reset the
timer or LFSR phase.

Register ownership is now:

| Range | Owner |
|---|---|
| `$4000-$4003` | Pulse 1 |
| `$4004-$4007` | Pulse 2 |
| `$4008`, `$400A`, `$400B` | Triangle (`$4009` unused) |
| `$400C`, `$400E`, `$400F` | Noise (`$400D` unused) |
| `$4015` | channel enables/status |
| `$4017` | shared frame counter |

## Envelope and length counter

The Noise envelope follows the pulse envelope algorithm but owns independent
state. `$400F` sets `envelope_start`. The next quarter-frame event sets decay
to 15, loads the divider from `$400C[3:0]`, and clears start. Later
quarter-frame events decrement the divider; expiration reloads the divider and
decrements decay. If decay is already zero and `$400C[5]` is set, it wraps to
15. Constant-volume mode selects `$400C[3:0]` without stopping the envelope
state machine.

Noise uses the package's existing 32-entry NES length table. An enabled
`$400F` write selects it with bits 7:3. A half-frame event decrements a nonzero
length unless `$400C[5]` halts it. Clearing `$4015` bit 3 clears length on that
accepted edge. Setting the enable bit later does not invent a new length; a
subsequent `$400F` write is required.

## NTSC timer

The centralized `APU_NOISE_PERIOD_TABLE` contains periods in CPU cycles:

| Index | CPU cycles | Index | CPU cycles |
|---:|---:|---:|---:|
| 0 | 4 | 8 | 202 |
| 1 | 8 | 9 | 254 |
| 2 | 16 | 10 | 380 |
| 3 | 32 | 11 | 508 |
| 4 | 64 | 12 | 762 |
| 5 | 96 | 13 | 1016 |
| 6 | 128 | 14 | 2034 |
| 7 | 160 | 15 | 4068 |

These are the NTSC values, not PAL values. The divider receives one tick on
every other complete CPU/APU time slot. It reloads with `period / 2 - 1`, so
successive LFSR shifts are separated by exactly the table's CPU-cycle count.
Changing `$400E` does not disturb the in-flight countdown; the new selection
is used at the next reload. The timer and LFSR continue while length is zero or
the channel is disabled, matching the free-running hardware unit.

At the project's nominal 1,789,773 Hz NTSC CPU rate, representative LFSR shift
rates are approximately 447,443 Hz (index 0), 18,643 Hz (index 5), 8,860 Hz
(index 8), 2,349 Hz (index 12), and 440 Hz (index 15). These calculations are
documentation/model helpers only; RTL timing uses integer counters.

## 15-bit LFSR

The deterministic reset state is `15'h0001`. A timer expiration shifts right,
places feedback in bit 14, and uses bit 0 as one feedback input:

- normal/long mode: `feedback = bit 0 XOR bit 1`;
- short mode: `feedback = bit 0 XOR bit 6`.

Starting at one avoids the all-zero lock state. Simulation asserts the LFSR is
nonzero, and the Python suite traverses the complete 32,767-shift long-mode
sequence plus thousands of short-mode shifts.

The first normal-mode states after shifts are:

```text
4000 2000 1000 0800 0400 0200 0100 0080
0040 0020 0010 0008 0004 0002 4001 6000
```

The first short-mode states share the first nine values and then diverge:

```text
4000 2000 1000 0800 0400 0200 0100 0080
0040 4020 2010 1008 0804 0402 0201 4100
```

Hard-coded directed sequences establish the independent reference, while the
RTL test compares every subsequent state against the Python model across both
modes, multiple periods, live mode changes, pauses, and resets.

## Raw output and `$4015`

The raw Noise code is zero if length is zero, `$4015` bit 3 is clear, or LFSR
bit 0 is one. Otherwise it is the four-bit constant volume or current envelope
decay value. The exported range is therefore 0 through 15.

`$4015` status sources are now internal active-length state for bit 0 Pulse 1,
bit 1 Pulse 2, bit 2 Triangle, and bit 3 Noise. Bit 4 remains the explicit
future DMC placeholder. Tests cover all 16 implemented-channel combinations,
including immediate disable and non-loading re-enable behavior.

## Pause, step, DMA, reset, and multi-channel behavior

All Noise sequential state is inside the existing `cpu_cycle_enable` boundary.
Debugger pause therefore freezes the timer, LFSR, envelope, and length even if
a bus strobe is held for thousands of fabric clocks. One resumed step produces
one timer action and accepts a held write once. OAM DMA continues supplying
complete CPU/APU slots, so Noise and the other three channels advance while
normal instruction execution is stalled.

Reset clears register, envelope, timer-counter, and length state; selects
normal mode and period index zero; and restores the LFSR to one. The post-reset
raw output and active status are zero. A four-channel integration scenario
runs different Pulse 1, Pulse 2, Triangle, and Noise settings concurrently and
compares every raw output/state transition without adding a mixer.

## Verification

`verification/apu.py` contains an independent `NoiseModel` and the centralized
NTSC table. `tests/python/test_apu_noise.py` contributes 106 directed cases,
including all 16 periods, all 32 shared length values, fixed LFSR sequences,
the exact deterministic raw waveform, register isolation, all status masks,
pause/step, DMA, reset, and simultaneous four-channel operation.

The dedicated top-level test is generated with seed `0x005E2026` and passes:

| Phase 5E comparison counter | Value |
|---|---:|
| Compared cycles | 371,608 |
| Paused/stalled cycles | 66,769 |
| Reset cycles | 13 |
| Pulse 1 writes | 2,151 |
| Pulse 2 writes | 2,202 |
| Triangle writes | 2,118 |
| Noise-bank writes | 2,180 |
| `$4015` reads | 1,068 |
| Quarter-frame events | 1,111 |
| Half-frame events | 1,110 |
| LFSR shifts | 6,930 |
| RTL/model mismatches | 0 |

The FST waveform is `build/sim/nes_apu_noise_phase5e.fst`. The retained Phase
5A, 5B, 5C, and 5D comparisons continue to pass 142,214, 220,195, 272,426,
and 314,560 cycles respectively with zero mismatches.

Reference behavior was cross-checked against the
[NESdev Noise channel description](https://www.nesdev.org/wiki/APU_Noise),
[NESdev envelope description](https://www.nesdev.org/wiki/APU_Envelope), and
[Mesen 2 Noise channel implementation](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/APU/NoiseChannel.h).

## Quartus results

The production DE1-SoC synthesis, fit, assembly, and all-corners timing flow
completed successfully and produced SOF and RBF artifacts.

| Resource/result | Phase 5D measured baseline | Phase 5E | Delta |
|---|---:|---:|---:|
| ALMs | 5,603 | 5,612 | +9 |
| Combinational ALUTs for logic | 7,499 | 7,542 | +43 |
| Route-through ALUTs | 1,036 | 1,087 | +51 |
| Total registers | 5,885 | 5,885 | 0 |
| Dedicated logic registers | 5,659 | 5,659 | 0 |
| M10Ks | 270 | 270 | 0 |
| Block-memory bits | 2,199,552 | 2,199,552 | 0 |
| MLAB memory bits | 18,880 | 18,880 | 0 |
| Worst setup slack | +1.303 ns | +1.219 ns | -0.084 ns |
| Worst hold slack | +0.077 ns | +0.077 ns | 0.000 ns |
| Worst TNS | 0.000 ns | 0.000 ns | 0.000 ns |

The raw channel outputs deliberately remain unconsumed by an audio mixer, so
Quartus can remove waveform-only production logic that feeds dangling debug
signals. The real `$4015` status/length path remains live. No M10K, MLAB, or
memory-bit allocation changed, and the modest ALM/ALUT movement is consistent
with the new active channel state and decode.

The measured Phase 5E warning profile is 397 total: map 101, fit 150, assembly
0, and timing 146, with zero errors. It is the established generated HPS/IP,
board-pin, connectivity, constraint, constant-pin, and clock-advisory profile;
no warning identifies Noise logic as faulty. All reported setup/hold TNS is
zero and every reported slack is non-negative.

## Limitations and exact next phase

Phase 5E intentionally does not implement DMC, nonlinear NES mixing,
sample-rate conversion, WAV generation, 44.1/48 kHz output, I2S, HDMI audio,
or the DE1-SoC codec. The four raw channel outputs are not yet audible.

The exact next phase is **Phase 5F — NES APU DMC**. No Phase 5F implementation
is included here.
