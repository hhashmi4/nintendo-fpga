# Phase 5K — real-time APU audio and DE1-SoC codec

Phase 5K adds a synthesizable 48 kHz audio path from the existing nonlinear
Q0.20 NES mixer to the DE1-SoC WM8731 and the board's analogue LINE OUT jack.
It does not change APU channel timing or mixing. It also does not perform the
physical listening, oscilloscope, noise-floor, or pop validation reserved for
Phase 5L.

## Authoritative hardware sources

The pinout and codec programming were checked against these official files,
not inferred from signal names:

- Terasic **DE1-SoC User Manual**, 28 January 2019, sections 3.6.4, 3.6.5,
  and 5.2, from the official rev. F/G System CD. Tables 3-12 and 3-13 define
  the audio and FPGA-side I2C package pins and 3.3 V I/O. Section 5.2 confirms
  that 16-bit I2S and 48 kHz playback through LINE OUT are supported.
- Terasic System CD
  `Demonstrations/FPGA/DE1_SoC_Audio/DE1_SoC_Audio.qsf`, used as a second
  check on the rev. F/G package assignments.
- Wolfson **WM8731/WM8731L Production Data**, revision 4.8, April 2009, from
  `Datasheet/Audio CODEC/WM8731.pdf` on the System CD. This is the authority
  for the two-wire transaction, register fields, clock ratios, USB-mode
  sample table, I2S alignment, reset, and power sequence.

Terasic distributes those files through the [DE1-SoC resources page](https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=205&Language=English&No=836&PartNo=4)
and the [official System CD index](https://download.terasic.com/downloads/cd-rom/de1-soc/).

| Board net | Cyclone V pin | Direction in 5K | Use |
|---|---:|---|---|
| `AUD_XCK` | G7 | output | 12.000 MHz codec MCLK |
| `AUD_BCLK` | H7 | output | 3.072 MHz average bit clock |
| `AUD_DACLRCK` | H8 | output | exact 48 kHz DAC left/right clock |
| `AUD_DACDAT` | J7 | output | signed 16-bit I2S, mono duplicated |
| `AUD_ADCLRCK` | K8 | unused | ADC is powered down in playback-only mode |
| `AUD_ADCDAT` | K7 | unused | ADC is powered down in playback-only mode |
| `FPGA_I2C_SCLK` | J12 | open-drain | 100 kHz codec control clock |
| `FPGA_I2C_SDAT` | K12 | open-drain | codec control data |

All assigned audio pins use `3.3-V LVTTL`. The board mux gives the FPGA this
control bus by default. HPS software must not assert `HPS_I2C_CONTROL` while
the FPGA owns it. The WM8731 has power-on reset and a software reset register;
there is no separate codec-reset FPGA pin on this board. Power rails and the
analogue path from the codec to the 3.5 mm LINE OUT jack are board hardware.
The codec documents right-justified, left-justified, I2S, and DSP-mode serial
formats with 16/20/24/32-bit word selections and 8-96 kHz sample rates; those
formats are not interchangeable. Phase 5K deliberately selects slave-mode,
16-bit I2S and the documented 12 MHz/250fs USB-mode 48 kHz configuration.

## Data path

```text
NES APU channels -> existing Q0.20 nonlinear mixer
                 -> exact 48 kHz scheduler + 961-tap Q18 FIR
                 -> Q30 10 Hz DC blocker + fixed gain + saturation
                 -> signed 16-bit PCM
                 -> 32-entry asynchronous FIFO
                 -> duplicated-left/right 16-bit I2S
                 -> WM8731 DAC -> DE1-SoC LINE OUT
```

The APU continues to run from the established nominal NTSC CPU/APU enable
stream, `19,687,500/11 Hz`. Debugger pause holds APU state, so the audio path
continues sampling its held mixer value and naturally decays to zero through
the DC blocker. A runtime game reset flushes filter, DC, FIFO, and serializer
state deterministically without modifying CPU, PPU, DMA, cartridge, VGA,
Developer Mode, or debugger architecture.

## Sample scheduling and anti-alias filtering

The source-domain scheduler adds 352 modulo 13,125 at every APU tick:

```text
(19,687,500 / 11) * (352 / 13,125) = 48,000 samples/s
```

The reduced ratio is exact, produces only 37- or 38-input-tick gaps, returns
to phase zero every 13,125 APU ticks, and has no frame-derived timing or
long-term drift.

A symmetric 961-tap Blackman-windowed sinc FIR is stored as one 481-entry
half-coefficient Q18 ROM. Two replicated circular 961x20 source-history RAMs
supply a symmetric sample pair to one pre-adder and one pipelined,
time-multiplexed MAC per 50 MHz cycle. The 483-cycle calculation fits well
inside the minimum 1,033-fabric-cycle output interval and reads the old half
of each snapshot before live input can overwrite it. The history uses
constant-first-sample extension, so constant unsigned mixer silence does not
create a startup transient. Coefficients are generated and checked by
`scripts/generate_audio_phase5k_coefficients.py`.

The 19 kHz cutoff is intentionally more conservative than Phase 5J's offline
3,073-tap, Q30, 22 kHz filter. A 961-tap implementation consumes one reusable
MAC instead of an impractical parallel 3,073-tap datapath. It has exact unity
DC gain, -0.002 dB at 10 kHz, -0.330 dB at 16 kHz, -6.021 dB at 19 kHz,
-28.598 dB at 22 kHz, and -72.751 dB at the 24 kHz output Nyquist frequency.
Relative to the Phase 5J reference it is -0.002 dB at 10 kHz, -0.330 dB at
16 kHz, and -6.020 dB at 19 kHz. Phase 5J can use future samples and rational
interpolation offline; Phase 5K is causal, includes the source sample that
triggers each output, and accepts the FIR's fixed 480-input-tick group delay.

The Q18 coefficients have maximum/RMS absolute error `4.431e-5`/`1.781e-6`
against the normalized floating-point 5K design; their worst magnitude error
over 0-24 kHz is `1.114e-4`. Against the deliberately wider Phase 5J filter,
the maximum absolute magnitude difference is `2.391e-4` through 10 kHz and
`0.03727` through 16 kHz, then grows to `0.8484` in the intentional transition-
band difference near 20.97 kHz. Consequently the two pipelines are exact at
DC and closely matched in the audio passband, but their time-domain PCM is not
claimed sample-identical: 5K has a causal group delay, a lower cutoff, no
future-sample interpolation, and Q18 rather than Q30 coefficients.

## DC removal and PCM policy

The conditioner implements

```text
y[n] = x[n] - x[n-1] + round(Q30(0.9986918597) * y[n-1])
```

with coefficient `1,072,337,219`, a 10 Hz corner at 48 kHz, an 80-bit feedback
product, and signed 48-bit output state. Its first accepted sample establishes
the unsigned DC level and returns zero. Therefore a constant mixer value is
digital zero immediately and remains zero. Reset clears all state.

The Phase 5J 0.75 gain is retained. Because the mixer is Q0.20, PCM conversion
is `round_away_from_zero(y * 3 / 128)`, which maps a full-scale mixer delta to
24,576. Results saturate to `[-32768, 32767]`; saturation increments a bounded
diagnostic counter. There is no automatic normalization. PCM is signed
two's-complement, and the same sample is sent to both codec channels.

## Clock tree and CDC

An integer-ratio Cyclone V PLL derives 12.000 MHz (`50 MHz * 6/25`) for
`AUD_XCK`. This differs from Terasic's illustrative 18.432 MHz configuration:
the exact 12 MHz option avoids device-specific fractional-PLL quantization and
is explicitly supported by the WM8731 USB-mode table.

The serializer remains entirely in the 12 MHz clock domain. A 64/125 phase
accumulator supplies BCLK **half-edge enables**; it does not create an
uncontrolled internal fabric clock. Half-periods are one or two MCLK cycles,
128 half-edges occupy exactly 250 MCLK cycles, BCLK averages 3.072 MHz, and
LRCK is exactly 48 kHz. The codec is configured as a slave. SDC discovers both
PLL clocks, makes the unrelated 50 MHz, pixel, HPS, and audio clock groups
asynchronous, and applies board-output timing relative to the audio PLL.

PCM crosses from 50 MHz to 12 MHz through a 32-entry asynchronous FIFO.
Binary pointers have an extra wrap bit, cross only after Gray encoding, and
pass through two forced synchronizer stages. Full/empty comparisons occur in
their owning domains. The PLL-lock indication is also synchronized before it
controls the 50 MHz pipeline. The serializer waits for four entries before
starting and latches that startup threshold; ordinary occupancy ripple cannot
pause an established stream. Overflow and underflow pulses feed saturating
diagnostics. Source reset resets both FIFO domains through domain-local reset
synchronization.

## WM8731 configuration

The controller uses the codec's verified seven-bit address `0x1a`, hence the
on-wire write byte `0x34`. Each register write is a fresh START, address byte,
two packed register/data bytes, three checked ACK bits, and STOP. SCL and SDA
are open-drain. Clock stretching, a stuck bus, NACK, and timeouts are handled;
the complete sequence retries twice from register zero before failing.

| Order | Register/value | Purpose |
|---:|---:|---|
| 0 | R15 `0x000` | software reset |
| 1 | R9 `0x000` | keep digital interface inactive |
| 2 | R5 `0x008` | DAC soft mute |
| 3 | R6 `0x007` | power down line/mic/ADC; retain DAC/output/clock |
| 4 | R2 `0x1f0` | -9 dB, zero-cross, apply to both output channels |
| 5 | R4 `0x012` | select DAC, mute microphone path |
| 6 | R7 `0x002` | slave, 16-bit I2S, normal polarity |
| 7 | R8 `0x001` | USB mode, 250fs, exact 48/48 kHz |
| 8 | R9 `0x001` | activate digital interface |
| 9 | R5 `0x000` | release DAC soft mute |

`codec_init_busy`, `codec_init_done`, and `codec_init_error` distinguish all
terminal states. Fault codes are `01` PLL timeout, `02` NACK, `03` SCL/clock
stretch timeout, and `04` bus stuck. Pipeline and FIFO reset remain asserted
until PLL lock and successful completion. PCM clocks and zero data start only
after configuration; the FIFO then prefills before nonzero playback. This is
a deterministic digital mute policy, not a claim of physically pop-free
analogue behaviour.

## I2S framing

Each LRCK frame has two 32-bit slots. LRCK low is left and high is right.
Both contain the same latched signed sample: one zero delay bit, 16 MSB-first
sample bits, then fifteen zero padding bits. Data and LRCK change on falling
BCLK edges and are sampled by the codec on rising edges. This implements the
WM8731 definition that I2S MSB appears on the second rising BCLK edge after an
LRCK transition; it is deliberately not left-justified timing.

## Diagnostics and bring-up tone

The production wrapper exposes and preserves bounded state for future HPS or
Developer Mode mapping:

- PLL lock and codec busy/done/error/mute;
- I2C ACK, NACK, timeout, and initialization-retry counters;
- generated/transmitted sample counts and measured one-second source rate;
- FIFO occupancy, overruns, and underruns;
- saturation count and last fault code.

Fault codes `10`, `11`, and `12` denote FIFO underrun, FIFO overflow, and FIR
deadline overrun. Counters saturate rather than wrap where loss of fault
history would be harmful. There is no per-cycle log or trace RAM.

SW0 retains its existing video-pattern meaning and additionally selects a
separate ROM-independent audio diagnostic source: an exact 1 kHz, +/-8192
square wave at 48 kHz. This selection is after the APU/FIR and does not modify
any APU channel or invent stereo panning.

## Verification

The independent Python model describes the mathematical scheduler, generated
filter, DC recurrence, quantization, bounded FIFO, I2S words and clocks,
two-wire bytes, initialization order, and diagnostic tone. It is transaction-
and-equation based rather than an RTL state-machine transcription.

Directed RTL checks cover exact cadence and phase return, FIR causal-impulse/
constant behaviour and deadline, signed gain/rounding/saturation, FIFO ordering/full/
empty/overrun/underrun/reset, exact 250-MCLK stereo I2S frames, word alignment,
codec writes/ACK/NACK/timeout/retry/PLL loss/stuck bus, mute/reset, source
stall, and the diagnostic tone. The extended run produces 352 samples from
13,125 source ticks with zero schedule mismatch, duplication, or loss.
The production-top playable/Developer Mode run generated 65,978 samples and
transmitted 65,974 after the four-entry startup prefill, with codec init done
and no FIFO fault. The debugger integration also verifies that generation and
transmission advance by more than 1,000 samples while NES execution is paused.

The final Phase 5K verification result is:

- `22` focused Python reference tests pass;
- `scripts/lint.sh` passes under Verilator 5.032;
- `sim/nes_audio_phase5k_tb.sv` passes its directed and extended run;
- the complete `scripts/test.sh` regression passes with `1,942`
  Python tests, including all retained CPU/PPU/DMA/controller/runtime/playable/
  VGA/Developer Mode/debugger and Phase 5A-5J checks;
- production Quartus synthesis, fitting, assembly, and all-corners timing pass.

## Quartus result

| Metric | Phase 5J baseline | Phase 5K |
|---|---:|---:|
| ALMs | 6,151 | 7,031 |
| combinational ALUTs | 8,934 | 10,487 |
| registers | 6,323 | 7,092 |
| M10Ks | 270 | 275 |
| MLAB bits | 18,880 | 18,880 |
| block-memory bits | 2,199,552 | 2,238,504 |
| DSP blocks | 2 | 7 |
| PLLs | 1 | 2 |
| worst setup slack | +1.013 ns | +0.863 ns |
| worst hold slack | +0.077 ns | +0.077 ns |
| setup/hold TNS | 0 / 0 ns | 0 / 0 ns |

The expected growth is the second PLL, replicated history RAMs, the FIFO,
coefficient ROM/mux, one time-shared filter MAC, DC arithmetic, serializer,
and bounded diagnostics. Analysis and synthesis reported 101 warnings,
fitting 149, and
timing analysis 144. The profile remains the established generated-HPS SDC,
unused-HPS-interface, PLL-compensation, and board-I/O advisory set, plus the
expected dual-clock-RAM read-during-write advisory for the audio FIFO. FIFO
full/empty ownership prevents the two ports from accessing the same live entry,
so the device's undefined same-address collision behavior is not exercised.
Timing reports zero unconstrained clocks, inputs, or outputs. The worst setup path is
the pre-existing `CLOCK_50` CPU/APU path from `cpu.debug_pc[0]` to
`mixer.tnd_segment_q[2]` (16 logic levels), not the new audio conditioner or
audio clock domain. The worst audio-clock setup slack is +58.754 ns.

## Phase 5L physical procedure and known limitations

Phase 5K stops before physical validation. For Phase 5L, build/program the
production image, connect amplified speakers or a headset to LINE OUT, leave
HPS codec-bus ownership deasserted, select SW0 for the known 1 kHz tone, and
verify MCLK/BCLK/LRCK/data alignment and analogue level before trying a game.
Then check startup/reset/retry behaviour, audible pops, channel equality,
noise floor, clipping diagnostics, and long-run FIFO counters.

Known limits are deliberate: there is no ADC/loopback capture, dynamic volume,
stereo panning, HDMI audio, physical pop/noise claim, or HPS register map yet.
The causal 961-tap filter rolls off earlier and rejects Nyquist less deeply
than Phase 5J's offline 3,073-tap reference. Those tradeoffs and all physical
measurements belong to Phase 5L or a separately scoped later phase.
