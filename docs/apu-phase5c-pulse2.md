# Phase 5C — NES APU Pulse 2

Phase 5C adds the second NES pulse channel without duplicating the proven
Pulse 1 datapath. Pulse 2 accepts `$4004-$4007`, has independent channel state,
owns `$4015` enable/status bit 1, and exposes an independent raw amplitude from
0 through 15. Both pulse channels can run simultaneously. This phase does not
mix, resample, or route audio to board hardware.

## Architecture and shared RTL

```text
                         nes_apu
                            |
        shared register events, frame ticks, and CPU time
                 +----------+----------+
                 |                     |
                 v                     v
       nes_apu_pulse              nes_apu_pulse
       CHANNEL_ONE=1              CHANNEL_ONE=0
       $4000-$4003                $4004-$4007
       Pulse 1 state              Pulse 2 state
                 |                     |
                 v                     v
          pulse1_output 0..15    pulse2_output 0..15
```

`rtl/apu/nes_apu_pulse.sv` remains the single pulse implementation. `nes_apu`
instantiates it twice and selects the channel-specific sweep rule with the
existing `CHANNEL_ONE` parameter. The instances receive the same Phase 5A
quarter- and half-frame pulses and the same alternating pulse-timer clock
enable, but every register and counter inside them is independent. No second
bus decoder, frame sequencer, duty table, or length table was added.

All state stays in the 50 MHz fabric domain. `cpu_cycle_enable` represents a
complete NES CPU-time slot, including OAM-DMA slots, and the pulse timer enable
selects every other accepted slot. Removing that enable for debugger pause
freezes both channels. One debugger step accepts one write/event edge and does
not repeat a held bus level.

## Pulse 2 registers

| Address | Bits | Pulse 2 behavior |
|---|---|---|
| `$4004` | `DDLC VVVV` | duty `DD`; envelope loop/length halt `L`; constant-volume select `C`; volume or envelope period `VVVV` |
| `$4005` | `EPPP NSSS` | sweep enable `E`; divider period `PPP`; negate `N`; shift `SSS`; request sweep reload |
| `$4006` | `LLLL LLLL` | low eight bits of the 11-bit timer period |
| `$4007` | `IIIII HHH` | length index `IIIII`; high timer bits `HHH`; restart duty position and envelope |

The Phase 5A decoder already emits one accepted channel-write event with a
five-bit register index. Pulse 1 accepts indices 0–3 and Pulse 2 accepts 4–7;
each instance receives only the low two register bits. An enabled `$4007`
write loads the shared NES length-table value, resets the Pulse 2 duty position
to zero, and requests envelope restart. As with Pulse 1, it does not reload the
current timer divider.

## Shared behavior and channel-specific sweep

Pulse 2 reuses all four exact eight-step duty sequences, the every-other-CPU-
cycle timer, envelope, 32-entry length table, sweep divider/reload logic, and
output gates proven for Pulse 1. The timer period, timer divider, sequencer
position, envelope state, length counter, and sweep state are separate for
each instance.

The one functional channel difference is negative sweep targeting. For change
amount `period >> shift`:

```text
positive, either channel: target = period + change
Pulse 1 negative:         target = period - change - 1
Pulse 2 negative:         target = period - change
```

Pulse 1 models the 2A03 one's-complement adder behavior and therefore performs
the extra subtraction. Pulse 2 uses the two's-complement result. The parameter
is explicit in RTL and the Python model, and the named differential regression
starts both channels at period `$100` with shift 1. One half-frame sweep event
produces Pulse 1 `$07F` and Pulse 2 `$080`: exactly one count apart.

Positive sweep, negative sweep, divider reload, shift-zero suppression,
period-below-8 mute, and positive-target overflow mute are all checked for
Pulse 2. The raw output equals the selected constant volume or envelope decay
only when the channel is enabled, length is nonzero, the duty bit is one, the
current period is at least 8, and the sweep target does not overflow `$7FF`.
Otherwise it is zero.

## `$4015` integration

`$4015[0]` enables Pulse 1 and `$4015[1]` enables Pulse 2. A write affects both
instances on the accepted CPU edge. Clearing either bit immediately clears
only that channel's length counter; setting a bit does not invent length.

On reads, bits 0 and 1 report the real `length_counter != 0` state of Pulse 1
and Pulse 2. External placeholder activity remains only on bits 4:2 for the
future DMC, Noise, and Triangle channels. Directed and RTL/model tests cover
both disabled, either channel enabled/active alone, and both enabled/active.

## Simultaneous operation and timing

The deterministic dual-waveform scenario programs Pulse 1 for duty 12.5%,
constant volume 15, timer 8 and Pulse 2 for duty 50%, constant volume 8, timer
10. Exact `(pulse1_output, pulse2_output)` samples are compared while the two
duty phases advance at different rates. The trace observes `(15,0)`, `(0,8)`,
and `(15,8)`, proving neither output is derived from the other.

For either channel:

```text
sequence CPU cycles = 16 * (timer period + 1)
pulse frequency      = 1,789,773 Hz / sequence CPU cycles
```

Thus the example timers have 144- and 176-CPU-cycle waveform periods, or
approximately 12.43 kHz and 10.17 kHz. Floating-point frequency calculations
exist only in Python tests; synthesizable RTL uses integer counters.

Both envelopes consume the same quarter-frame pulse but update private decay,
divider, loop, and restart state. Both length and sweep units consume the same
half-frame pulse but update private state. `$4017` therefore controls one shared
frame sequencer without merging the channels.

During debugger pause, 8,192 hostile held-write fabric cycles leave every APU
and pulse field unchanged. Directed single-step tests accept `$4003` and
`$4007` exactly once and prove subsequent paused levels cannot repeat them.
During 2,048 DMA-like accepted CPU slots with no CPU register strobes, both
timers continue at their independent rates. Reset from different active timer,
envelope, length, and sweep states clears both instances deterministically.

## Verification and waveforms

`verification/apu.py` now owns a reusable independent `PulseModel` with
`Pulse1Model` and `Pulse2Model` wrappers selecting only the documented negate
rule. The top-level model routes each register bank independently and clocks
both models from the shared frame events and CPU-time stream.

`tests/python/test_apu_pulse2.py` contributes 36 collected cases. They cover
all four registers, all four duties and eight positions, timer advancement,
constant and decaying/looping/restarting envelopes, length load/decrement/halt,
positive and negative sweep, mute rules, all `$4015` combinations, register
isolation, simultaneous waveforms, private envelope/length/sweep state, the
named negate differential, pause, step, DMA, reset, and frequency math. The
complete Python suite contains 1,527 passing tests.

`scripts/generate_apu_pulse2_phase5c_vectors.py` uses fixed seed `0x005C2026`.
`sim/nes_apu_pulse2_phase5c_tb.sv` instantiates the real `nes_apu`, compares
both complete pulse states and all APU integration signals after every edge,
and records `build/sim/nes_apu_pulse2_phase5c.fst`.

| Phase 5C coverage counter | Value |
|---|---:|
| Compared cycles | 272,426 |
| Pause/stall cycles | 51,438 |
| Reset cycles | 13 |
| Pulse 1 writes | 1,617 |
| Pulse 2 writes | 1,686 |
| `$4015` reads | 785 |
| Quarter-frame events | 869 |
| Half-frame events | 869 |
| RTL/model mismatches | 0 |

The unchanged Phase 5A top-level comparison passes 142,214 cycles and the
unchanged shared-module Phase 5B Pulse 1 comparison passes 220,195 cycles, both
with zero mismatches. This explicitly guards the prior Pulse 1 behavior while
the Phase 5C top-level test proves dual-channel integration.

The complete retained regression passes CPU, PPU, system bus, Mapper 0,
controllers, OAM DMA, playable ROM, VGA, Developer Mode, debugger, runtime
loading Phase 4F, Phase 4F-G end-to-end boot, and the Phase 4F-H game library.
The sustained playable run completes 300 frames with 297 NMI handlers and 297
DMA transfers; the debugger run completes 132 frames and 187 command/
acknowledgement pairs. Strict Verilator 5.032 lint passes.

## Quartus results

The production DE1-SoC synthesis, fit, assembly, and all-corners timing flow
completed successfully and produced SOF and RBF artifacts.

| Resource/result | Phase 5B | Phase 5C | Delta |
|---|---:|---:|---:|
| ALMs | 5,576 | 5,599 | +23 |
| Combinational ALUTs for logic | 7,457 | 7,483 | +26 |
| Route-through ALUTs | 1,104 | 1,144 | +40 |
| Total registers | 5,852 | 5,880 | +28 |
| Dedicated logic registers | 5,626 | 5,654 | +28 |
| M10Ks | 270 | 270 | 0 |
| Block-memory bits | 2,199,552 | 2,199,552 | 0 |
| MLAB memory bits | 18,880 | 18,880 | 0 |
| Worst setup slack | +1.314 ns | +1.385 ns | +0.071 ns |
| Worst hold slack | +0.077 ns | +0.077 ns | 0.000 ns |
| Worst TNS | 0.000 ns | 0.000 ns | 0.000 ns |

The small logic/register increase is consistent with the second independent
length/status and pulse-control state; block-memory allocation is unchanged.
Quartus reports 397 stage warnings and zero errors: map 101, fit 150, assembly
0, and timing 146. This is one additional map-stage warning relative to the
measured 396-warning pre-change baseline. The report lists the new raw output
in the same expected dangling-until-mixer connectivity class as Pulse 1; the
remaining profile is unchanged generated HPS/IP, board-pin, constraint,
constant-pin, and clock-advisory output. No warning names either pulse instance
or an APU source as faulty.

## Limitations and next phase

Phase 5C intentionally does not implement Triangle, Noise, DMC, the nonlinear
NES mixer, sample-rate conversion, WAV output, I2S, HDMI audio, or the DE1-SoC
audio codec. `pulse1_output` and `pulse2_output` remain separate raw digital
amplitudes and are not yet audible.

The exact next phase is **Phase 5D — NES APU Triangle Channel**. No Phase 5D
implementation is included here.
