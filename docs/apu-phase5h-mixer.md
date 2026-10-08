# Phase 5H — NES APU nonlinear mixer

Phase 5H converts the five verified raw APU codes into one deterministic
digital signal. It changes no oscillator, envelope, counter, IRQ, register,
DMA, controller, or scheduler behavior. The raw Pulse 1, Pulse 2, Triangle,
Noise, and DMC outputs remain independently visible.

This phase ends at a normalized digital mixer boundary. It does not consume
the APU IRQ, choose a PCM sample rate, resample, write WAV files, serialize
I2S, drive HDMI audio, or configure the DE1-SoC codec.

## Mixer model

The high-precision reference implements the commonly documented NES mixer
relationship:

```text
pulse = 95.88 / (8128 / (P1 + P2) + 100)

tnd = 159.79 / (
          1 / (Triangle / 8227 + Noise / 12241 + DMC / 22638)
          + 100
      )

mixed = pulse + tnd
```

A zero numerator defines the corresponding contribution as exactly zero, so
there is no division-by-zero ambiguity. The model is documented by the
[NESdev APU Mixer reference](https://www.nesdev.org/wiki/APU_Mixer). Mesen's
[`NesSoundMixer.cpp`](https://github.com/SourMesen/Mesen2/blob/master/Core/NES/NesSoundMixer.cpp)
uses the equivalent pulse equation and rewrites the TND conductance in DMC
units with Triangle coefficient `2.7516713261` and Noise coefficient
`1.8493587125`. The Phase 5H independent model keeps the original rational
denominators and uses Python `Fraction`; floating-point arithmetic is never
used to produce an RTL constant.

The exact maximum at `(15, 15, 15, 15, 127)` is
`0.9999993508269456`. The formula is monotonic in each non-negative channel,
and the pulse term depends only on `P1 + P2`.

## Digital representation

`mixed_audio[19:0]` is unsigned unipolar Q0.20:

```text
normalized amplitude = mixed_audio / 2^20
silence              = 20'h00000
full-scale code       = 20'hfffff
```

No DC centering is introduced. Centering and conversion to a signed PCM or
physical DAC representation belong at the later sample/output boundary, where
the destination format is known.

Twenty fractional bits give an LSB of `2^-20` (about -120.4 dBFS) while
keeping adders, coefficients, and the future sample-conversion interface
compact. Sixteen bits would discard four useful fractional bits before Phase
5J; 24 bits would enlarge the lookup data and datapath by 20% without a useful
accuracy benefit relative to the empirical analog approximation. The exact
model is already just below 1.0, so Q0.20 uses the available unsigned range
efficiently and needs no integer bit.

All table entries and interpolation results use round-to-nearest with an exact
half rounded upward. Pulse and TND contributions are computed separately in
Q0.20 and added in 21 bits. The one legal all-maximum input whose separately
rounded terms sum to `0x100000` is explicitly saturated to `0xfffff`; every
other equivalence class is below full scale.

## Synthesizable architecture

`rtl/apu/nes_apu_mixer.sv` is a pure datapath module with no bus behavior or
channel state. A synchronous lookup stage gives it exactly one fabric-clock
cycle of latency. Reset clears that stage to zero, so the first reset edge
produces unambiguous digital silence. The pipeline has no enable and therefore
continues to track the raw inputs even when CPU/APU state is paused; after its
one-cycle fill it has no independent time evolution.

The pulse path exploits the complete 0..30 sum domain. A generated 31-entry
LUT stores the correctly rounded exact pulse contribution. This makes Pulse 1
and Pulse 2 symmetric by construction.

The TND path first forms a DMC-unit drive in Q12:

```text
drive_q12 = DMC * 4096 + Triangle * 11271 + Noise * 7575

11271 = round((22638 / 8227)  * 4096)
 7575 = round((22638 / 12241) * 4096)
```

The nonlinear transfer is then evaluated by piecewise-linear interpolation
over half-DMC-unit segments. Segment index `i` represents drive `i/2`; the
generated LUT stores a 20-bit base and 12-bit delta for indices 0..392. The
11 low drive bits select the fraction within the segment. Legal maximum input
produces index 392 and fraction 66, so the lookup is proven large enough. The
pulse entry, packed TND entry, and fraction are registered together; the
following combinational stage performs one 12-by-11-bit multiply, adds the
rounding bias, shifts, combines both contributions, and saturates. There is no
general divider and no floating-point or `real` RTL.

This 393-entry transfer needs roughly 12.6 kbit of coefficient data plus the
small pulse table. It avoids the 32,768-entry full TND ROM while retaining
sub-four-LSB agreement with the exact equation. The constants are generated
offline by `scripts/generate_apu_mixer_luts.py`; `--check` proves that the
committed `nes_apu_mixer_lut_pkg.sv` is reproducible without network access.

`nes_apu` instantiates the mixer directly from the five established raw
outputs and adds only the `mixed_audio` output port. `mixed_audio` represents
the raw channel tuple sampled on the preceding rising edge. The production
board top captures this future pipeline boundary in a preserved observation
register so Quartus cannot optimize the mixer away before a physical audio
output exists. That observation register is not part of the mixer interface
and does not add latency to `nes_apu.mixed_audio`.

## Independent reference and error budget

`verification/apu_mixer.py` deliberately separates:

- `reference_pulse_mix`, `reference_tnd_mix`, and `reference_mix`, which use
  exact rational arithmetic and the documented equations; and
- `quantized_pulse_mix`, `quantized_tnd_mix`, and `quantized_mix`, which mirror
  the RTL's Q12 weights, generated nodes, interpolation, rounding, and
  saturation.

The acceptance limits were fixed before RTL qualification:

| Metric | Acceptance limit |
| --- | ---: |
| Maximum absolute error | 4.0 Q0.20 LSB |
| Mean absolute error | 1.0 Q0.20 LSB |
| RMS error | 1.1 Q0.20 LSB |
| Maximum relative error for reference >= `1e-4` | 0.02% |

Exhaustive analysis produced:

| Metric | Result |
| --- | ---: |
| Pulse-sum/TND equivalence classes | 1,015,808 |
| Represented legal five-channel combinations | 8,388,608 |
| Maximum absolute error | 3.760161616 Q0.20 LSB |
| Mean absolute error, pulse-pair weighted | 0.895632511 Q0.20 LSB |
| RMS error, pulse-pair weighted | 1.089153087 Q0.20 LSB |
| Maximum relative error above `1e-4` | 0.013657877% |
| Saturated equivalence classes | 1 |

The maximum absolute error occurs at pulse sum 9, Triangle 15, Noise 2, DMC
1. Any legal Pulse 1/Pulse 2 pair summing to 9 has that same result. The
maximum relative error under the stated floor occurs at pulse sum 0, Triangle
0, Noise 1, DMC 0. Excluding quieter values avoids a misleading relative
ratio as the correct output approaches zero; absolute error remains bounded
there.

## Verification completeness

The Python suite checks directed silence, every single-channel minimum and
maximum, pair and all-channel combinations, exact LUT boundaries,
deterministic rounding, saturation, type/range rejection, and generated-file
freshness. It exhaustively checks:

- all 256 Pulse 1/Pulse 2 pairs for LUT agreement and symmetry;
- all 32,768 Triangle/Noise/DMC combinations;
- monotonic DMC sweeps at every Triangle/Noise point;
- monotonic Triangle steps at every Noise/DMC point;
- monotonic Noise steps at every Triangle/DMC point; and
- all 1,015,808 separable pulse-sum/TND classes against the exact model.

The complete nominal five-channel domain has 8,388,608 combinations. Brute
forcing each through RTL is unnecessary because the implementation and the
documented equation are separable into a pulse term selected only by the
31 pulse sums and a TND term selected only by the 32,768 TND triples. Testing
all 256 pulse pairs and every TND triple proves both nonlinear mappings;
testing their 1,015,808 Cartesian-product classes in Python proves every
possible adder/error combination. The dedicated RTL run adds 17 directed and
4,096 fixed-seed combined cases to exercise addition and the full-scale
saturation boundary. It compares 37,137 rows with zero mismatches.

The retained complete-APU oracle now packs `mixed_audio` beside all five raw
outputs in both pre-edge and post-edge events and models the documented
one-edge pipeline exactly. Its original 759,254 Phase 5G
cycles and 377-bit state comparison remain intact, with 14,880 Phase 5H cycles
appended for long silence, all-channel activity, and sequential channel
disable/stop transitions. The resulting 774,134-cycle run also covers
debugger-style pause, reset, DMC acknowledgement, frame events, dense writes,
and randomized activity, with zero mixed or raw/state mismatches. Whenever all
five raw outputs are zero, the testbench separately asserts exact zero mix.

Waveforms are written to:

- `build/sim/nes_apu_mixer_phase5h.fst`
- `build/sim/nes_apu_complete_phase5g.fst`

## Baseline and qualification

The clean `d42e2b3` baseline used Python 3.14.4, Verilator 5.032, and Quartus
Prime Lite 23.1std.1 Build 993. It passed 1,845 Python tests, complete lint,
all retained simulations, the 759,254-cycle Phase 5G comparison, the 300-frame
playable run, the 83-frame production VGA/Developer Mode run, and the
132-frame/187-command debugger run.

The baseline production fit used 5,703 ALMs, 7,649 logic ALUTs, 1,082
route-through ALUTs, 5,990 total registers, 5,764 dedicated logic registers,
270 M10Ks, 18,880 MLAB bits, 2,199,552 block-memory bits, and zero DSP blocks.
Worst setup slack was +1.457 ns, worst hold slack +0.077 ns, and every timing
TNS was 0.000 ns. Map/Fitter/Assembler/Timing warnings were 100/150/0/146.

The first qualified zero-latency implementation was functionally exact to the
quantized model, but its retained production path missed `CLOCK_50` setup by
0.118 ns with -0.162 ns TNS. It was rejected. Registering the matched pulse
entry, TND entry, and interpolation fraction improved the final worst setup
slack to +0.575 ns; worst hold is +0.077 ns and all-corners TNS is 0.000 ns.
This is why the final interface has one cycle of explicitly verified latency.

The final production fit used 6,165 ALMs, 8,365 logic ALUTs, 1,110
route-through ALUTs, 6,342 total registers, 6,116 dedicated logic registers,
270 M10Ks, 18,880 MLAB bits, 2,199,552 block-memory bits, and two DSP blocks.
Relative to 5G this is +462 ALMs, +716 logic ALUTs, +28 route-through ALUTs,
+352 registers, no block-memory increase, and +2 DSPs. Quartus attributes 314
combinational ALUTs, 62 dedicated registers, and both DSPs directly to the
mixer hierarchy; the remaining total-fit delta includes packing and routing
effects. Overall device use remains 19% of ALMs, 68% of M10Ks, and 2% of DSPs.
Map/Fitter/Assembler/Timing warnings are 101/150/0/146 (397 total), with no
errors or timing violations.

Final qualification passes 1,874 Python tests, complete Verilator lint, the
37,137-row dedicated mixer run, the 774,134-cycle complete-APU comparison,
all retained DMC/DMA, CPU, PPU, bus, cartridge, controller, runtime, playable,
VGA, Developer Mode, and debugger simulations, and the production Quartus
build above.

## Scope boundary

Phase 5H ends with a deterministic unsigned Q0.20 mixed value plus the five
unchanged raw channel outputs. CPU IRQ consumption remains Phase 5I. PCM
sample generation/resampling, WAV reference output, I2S/HDMI transport, and
DE1-SoC codec integration remain later work.
