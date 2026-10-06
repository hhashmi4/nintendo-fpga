# Phase 5D — NES APU Triangle Channel

Phase 5D adds the NES triangle channel alongside the two existing pulse
channels. It implements the three triangle registers, every-CPU-cycle timer,
32-step digital waveform, linear counter, shared-table length counter, and
`$4015` enable/status behavior. `nes_apu` exposes independent raw four-bit
`pulse1_output`, `pulse2_output`, and `triangle_output` signals; this phase
does not mix, resample, or route them to audio hardware.

## Architecture

```text
                              nes_apu
                                 |
          shared register events, frame ticks, and CPU time
                  +--------------+--------------+
                  |              |              |
                  v              v              v
           nes_apu_pulse  nes_apu_pulse  nes_apu_triangle
             Pulse 1        Pulse 2         Triangle
            $4000-$4003     $4004-$4007     $4008/$400A/$400B
                  |              |              |
                  v              v              v
              raw 0..15      raw 0..15      raw 0..15
```

`rtl/apu/nes_apu_triangle.sv` owns all triangle-specific register and channel
state. It consumes the existing top-level accepted write event, CPU-time
enable, and Phase 5A quarter/half-frame ticks. It does not add a bus decoder or
frame sequencer. The common `nes_apu_pkg` length table is shared with both
pulse instances; the package now also defines the exact triangle sequence.

All state remains in the 50 MHz fabric clock domain. `cpu_cycle_enable` marks
an accepted NES CPU/APU time slot. Debugger pause removes this enable, while
OAM DMA continues to supply it even though CPU instruction execution is
stalled.

## Register map

| Address | Bits | Triangle behavior |
|---|---|---|
| `$4008` | `CRRR RRRR` | control/length-halt flag `C`; seven-bit linear reload value `R` |
| `$4009` | — | reserved; writes have no effect |
| `$400A` | `LLLL LLLL` | low eight bits of the 11-bit timer period |
| `$400B` | `IIIII HHH` | length-table index `I`; timer period high bits `H`; set linear reload flag |

An enabled `$400B` write loads the length counter through the same 32-entry NES
table used by the pulse channels and sets the linear reload flag. If `$4015`
triangle enable is clear, the length load is suppressed. The write updates
only the timer period high bits: it does not restart the timer divider or reset
the waveform position.

The existing top-level decoder routes `$4000-$4003` only to Pulse 1,
`$4004-$4007` only to Pulse 2, and `$4008-$400B` only to Triangle. The triangle
module explicitly ignores local register 1 (`$4009`). `$4017` remains the one
shared frame-counter control register.

## Timer and 32-step sequencer

The triangle timer is an 11-bit down-counter and clocks on every accepted CPU
cycle, twice the pulse-timer rate. At zero it reloads from the programmed
period. If both length and linear counters are nonzero on that edge, it also
advances the five-bit waveform position; otherwise only the timer reload
occurs. Nonzero timer values decrement normally.

The hardware sequence is a lookup table, not a mathematical oscillator:

```text
position  0..15: 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
position 16..31:  0,  1,  2,  3,  4,  5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
```

All 32 positions and both wrap boundaries are checked explicitly. For CPU
frequency 1,789,773 Hz, the ideal sequence frequency is:

```text
sequence CPU cycles = 32 * (timer period + 1)
triangle frequency  = 1,789,773 Hz / sequence CPU cycles
```

Python sanity checks cover periods 0, 1, 2, 15, `$100`, and `$7FF`, including
observed advance spacing. Floating-point frequency calculations exist only in
the reference tests; RTL timing is entirely integer based.

Periods 0 and 1 are not given the pulse channel's period-below-8 mute rule.
They advance the digital sequencer at their real, ultrasonic rates. Any later
band-limiting or output filtering belongs to the mixer/audio-output work, not
the channel model.

## Linear counter and control flag

`$4008[6:0]` supplies the reload value and `$400B` sets the reload flag. Each
existing `quarter_frame_tick` performs exactly one update using the flag state
from before the edge:

```text
if reload flag is set:
    linear counter = reload value
else if linear counter is nonzero:
    linear counter = linear counter - 1

if control flag is clear:
    reload flag = 0
```

With control zero, the first quarter-frame event after `$400B` reloads the
counter and clears the flag; later events count toward zero. With control one,
the reload flag remains set, so every quarter-frame event reloads the counter.
The same control bit is also the length-counter halt bit. Directed tests cover
reload, decrement, flag clearing/persistence, zero reload values, and
coincident quarter/half-frame events.

## Length counter and `$4015`

The triangle uses the common NES length table. An enabled `$400B` write loads
the indexed value. A `half_frame_tick` decrements a nonzero length exactly once
when the `$4008` control flag is clear; control one holds it.

`$4015[2]` is the triangle enable bit. Clearing it immediately clears the
triangle length counter and therefore its active status. Setting it alone does
not create a length value; a later `$400B` write may load one. `$4015` read bit
2 reports `triangle length_counter != 0`, not the enable latch. Bits 0 and 1
continue to report the actual Pulse 1/Pulse 2 length state, and the
unimplemented Noise/DMC activity bits remain inactive. All eight meaningful
Pulse 1/Pulse 2/Triangle status combinations are checked.

## Held DAC output

The triangle raw output is always the current four-bit sequence-table value.
When either length or linear counter is zero, timer reload/decrement behavior
continues but the waveform position stops advancing. The DAC therefore holds
its last code rather than being forced to zero. The same held-state rule
applies after `$4015` disables and clears length. This deliberately differs
from pulse output gating and models the digital channel state before any later
analog mixer or high-pass filtering.

The implementation follows the documented NES APU behavior summarized by the
[NESdev triangle reference](https://www.nesdev.org/wiki/APU_Triangle), the
[NESdev length-counter reference](https://www.nesdev.org/wiki/APU_Length_Counter),
and the independently implemented
[Mesen 2 triangle channel](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/APU/TriangleChannel.h).

## Multi-channel, debugger, DMA, and reset behavior

The deterministic integration scenario programs all three channels with
different timer and counter state and observes independent nonzero raw outputs.
Register-isolation tests mutate every register bank in turn, including `$4009`,
and prove the other two channels are unchanged. Both pulse models and retained
Phase 5B/5C RTL comparisons are unchanged.

During debugger pause, thousands of hostile fabric cycles leave the triangle
timer, position, linear state, length, and register state frozen. A debugger
step accepts one APU edge and cannot duplicate a held register write or frame
event. During DMA-like accepted CPU slots, Triangle and both pulse timers
continue while CPU instruction execution would be stalled. Reset from active
waveform, nonzero counters, a set reload flag, and an arbitrary position
returns every field deterministically to zero; waveform position zero maps to
raw code 15.

## Independent model and verification

`verification/apu.py` contains a behavioral `TriangleModel` alongside the
existing pulse models. It describes register state, timer, sequencer, linear
reload rules, length behavior, raw output holding, reset, accepted-time pause,
and top-level `$4015` integration independently of RTL structure.

`tests/python/test_apu_triangle.py` contributes 108 collected cases covering
register decode/isolation, all 32 waveform positions, timer bytes/reload/
advance boundaries, linear reload/decrement/control rules, all 32 length-table
entries, halt and enable behavior, all eight three-channel status combinations,
held DAC codes, low periods, simultaneous operation, frame-event sharing,
pause, one-step writes, DMA-like time, reset, and frequency calculations. The
complete Python suite contains 1,635 passing tests.

`scripts/generate_apu_triangle_phase5d_vectors.py` uses fixed seed
`0x005D2026`. `sim/nes_apu_triangle_phase5d_tb.sv` instantiates the real
top-level `nes_apu`, compares the complete triangle and APU integration state
plus all three outputs after every edge, proves all 32 waveform positions were
seen, and writes `build/sim/nes_apu_triangle_phase5d.fst`.

| Phase 5D coverage counter | Value |
|---|---:|
| Compared cycles | 314,560 |
| Pause/stall cycles | 58,023 |
| Reset cycles | 12 |
| Pulse 1 writes | 2,004 |
| Pulse 2 writes | 2,005 |
| Triangle-bank writes | 2,200 |
| `$4015` reads | 1,063 |
| Quarter-frame events | 976 |
| Half-frame events | 976 |
| Waveform positions observed | 32 of 32 |
| RTL/model mismatches | 0 |

The retained Phase 5A comparison passes 142,214 cycles, Phase 5B passes
220,195 cycles, and Phase 5C passes 272,426 cycles, all with zero mismatches
and their prior stall counts of 17,531, 42,982, and 51,438. The complete
regression passes CPU, PPU, system bus, Mapper 0, controllers, OAM DMA,
playable ROM, VGA, Developer Mode, debugger, the complete Phase 4F runtime-
loading stack, and the game library. The sustained playable run completes 300
frames with 297 NMI handlers and 297 DMA transfers; the debugger run completes
132 frames and 187 command/acknowledgement pairs. Strict Verilator 5.032 lint
passes.

## Quartus results

The production DE1-SoC synthesis, fit, assembly, and all-corners timing flow
completed successfully and produced SOF and RBF artifacts.

| Resource/result | Phase 5C baseline | Phase 5D | Delta |
|---|---:|---:|---:|
| ALMs | 5,599 | 5,603 | +4 |
| Combinational ALUTs for logic | 7,483 | 7,499 | +16 |
| Route-through ALUTs | 1,144 | 1,036 | -108 |
| Total registers | 5,880 | 5,885 | +5 |
| Dedicated logic registers | 5,654 | 5,659 | +5 |
| M10Ks | 270 | 270 | 0 |
| Block-memory bits | 2,199,552 | 2,199,552 | 0 |
| MLAB memory bits | 18,880 | 18,880 | 0 |
| Worst setup slack | +1.385 ns | +1.303 ns | -0.082 ns |
| Worst hold slack | +0.077 ns | +0.077 ns | 0.000 ns |
| Worst TNS | 0.000 ns | 0.000 ns | 0.000 ns |

The resource change is small and no M10K or memory-bit allocation changed.
Quartus reports the identical 397-warning profile and zero errors before and
after the change: map 101, fit 150, assembly 0, and timing 146. The profile is
the established generated HPS/IP, board-pin, constraint, constant-pin, and
clock-advisory output; no warning identifies the triangle or another APU
source as faulty.

## Limitations and exact next phase

Phase 5D intentionally does not implement Noise, DMC, the nonlinear NES mixer,
sample-rate conversion, WAV output, I2S, HDMI audio, or the DE1-SoC audio
codec. The three raw channel outputs are not yet audible.

The exact next phase is **Phase 5E — NES APU Noise Channel**. No Phase 5E
implementation is included here.
