# Phase 5J — deterministic NES APU PCM/WAV pipeline

Phase 5J turns the existing unsigned Q0.20 mixer output into deterministic,
playable mono PCM without adding a physical audio interface. Legal generated
NROM-128 programs execute on the real RTL CPU, write the real APU, and reach
the established nonlinear mixer. A bounded event capture preserves that RTL
output; an offline fixed-point converter anti-aliases it, removes DC, samples
it at exactly 48 kHz, and writes signed 16-bit RIFF/WAVE files.

This phase adds no production RTL and no independent audio clock. It does not
implement I2S, HDMI audio, the DE1-SoC codec, or any Phase 5K/5L hardware.

## End-to-end architecture

```text
generated original .nes / PRG image
              |
              v
real cpu_core + nes_core bus and DMC DMA
              |
              v
real nes_apu channels and one-cycle nonlinear mixer
              |
              v
Q0.20 event/RLE capture at NES CPU-time boundaries
              |
              v
3073-tap fixed Q30 anti-alias FIR + rational interpolation
              |
              v
10 Hz fixed-point DC blocker + fixed 0.75 gain
              |
              v
48,000 Hz mono signed-16 PCM -> deterministic RIFF/WAVE
```

`sim/nes_apu_audio_phase5j_tb.sv` instantiates `nes_core`, `nes_apu`, the
controller, and the static Mapper-0 cartridge. It does not drive channel codes
from Python or feed a fabricated waveform to the mixer. The testbench checks
that each APU access is an accepted CPU transaction, records the executing ROM
PC for every write, and asserts every acknowledged DMC byte against the byte
read from the instantiated cartridge PRG array.

## NES time and mixer alignment

The repository's NTSC timing is authoritative:

```text
master rate = 945,000,000 / 44 Hz
CPU rate    = master / 12 = 19,687,500 / 11 Hz
            = 1,789,772.727... Hz
```

The 50 MHz FPGA fabric clock is only the implementation clock. `nes_core`
produces scheduled CPU-time slots from the PPU/master timing model, and the APU
advances on every such slot, including DMA-owned slots. Phase 5J never treats
50 MHz as an audio or CPU rate.

The Phase 5H mixer registers its lookup selections on a fabric rising edge.
Raw channel state changes on an enabled APU/CPU slot at that same edge; the
corresponding `mixed_audio` value is therefore visible one fabric edge later.
The capture monitor remembers the slot edge and samples the raw tuple plus
Q0.20 mix after the following edge. It labels that observation with the
original NES CPU cycle. This explicitly consumes the one-fabric-cycle mixer
latency without shifting audio by one NES CPU cycle.

At 48 kHz, the exact output/input rate ratio is:

```text
48,000 / (19,687,500 / 11) = 352 / 13,125
```

For output sample `n`, the converter evaluates input position
`n * 19,687,500 / (11 * 48,000)` with integer division and remainder. The
sample count is nearest-integer `N * 352 / 13,125` for `N` captured CPU
cycles. There is no floating phase accumulator and therefore no accumulated
timing drift. Captures of 178,977, 1,073,864, and 5,369,318 CPU cycles produce
exactly 4,800, 28,800, and 144,000 samples respectively.

## Bounded capture format

The ASCII `NESAPU_CAPTURE_V1` format is deliberately simple, strict, and RLE
by change event. It is small enough for CI inspection but retains all data
needed to reconstruct every held CPU-cycle value:

```text
NESAPU_CAPTURE_V1
scenario=pulse1
cpu_rate_num=19687500
cpu_rate_den=11
cpu_cycles=178977
mixer_q_bits=20
mixer_latency_fabric_cycles=1
pause_policy=omit
BEGIN
W 27 0x800f 0x4017 0x40
S 62
A 0 258384 0 0 15 0 0 0
...
I 59679
END 178977 89 6 0
```

Records have the following meanings:

- `S absolute_cpu_slot` identifies the first audio cycle;
- `A relative_audio_cycle mix p1 p2 triangle noise dmc flags` changes the
  held raw/mixed tuple; flags are reserved and zero in version 1;
- `W absolute_cpu_slot pc address data` proves a CPU-executed APU write;
- `F absolute_cpu_slot address data` proves a DMC cartridge-bus fetch;
- `P relative_audio_cycle fabric_cycles` records a debugger pause;
- `R relative_audio_cycle asserted` records functional reset assertion or
  release;
- `I count` records executed CPU instruction fetches; and
- `END cycles events writes fetches` closes and cross-checks the capture.

The parser requires the exact timing/Q-format/latency policy, increasing event
cycles, an event at cycle zero, consistent record counts, a CPU instruction
record, and mixer-range limits. Conversion independently recomputes every
event's Q0.20 value with `verification.apu_mixer.quantized_mix`. Captures are
limited to 20,000,000 emulated cycles and 256 MiB; normal Phase 5J captures
are much smaller. The 3-second melody capture is 661 KiB and its WAV is
282 KiB. Generated captures, ROMs, metrics, and WAVs stay under ignored
`build/` paths rather than becoming repository binaries.

## Anti-alias filtering and rational conversion

`verification/apu_audio_fir.py` contains a committed symmetric 3,073-tap
Blackman-windowed sinc low-pass filter generated by
`scripts/generate_apu_audio_fir.py`. `--check` regenerates and compares it in
both FAST and FULL verification.

| Filter property | Policy/result |
| --- | --- |
| Input rate | `19,687,500 / 11` Hz |
| Type | odd symmetric Blackman-windowed sinc FIR |
| Taps | 3,073 |
| Ideal cutoff | 22,000 Hz |
| Coefficients | signed Q30, exact quantized sum `2^30` |
| Half-vector SHA-256 | `af72530012b6f266f15885eb520d5f0ad4cab5336af59fb04b997a0f89bfbb8b` |
| DC / 20 kHz magnitude | 1.0 / 0.9999662 |
| 22 kHz magnitude | 0.4999998 |
| 24 kHz magnitude | 0.00003339 (about -89.5 dB) |
| Linear-phase group delay | 1,536 CPU cycles, about 0.858 ms |
| Normalization | unity DC gain before DC removal |
| Edge policy | constant first/last input extension |

The offline implementation centers the symmetric FIR at each requested input
cycle, so the exported timeline is zero-phase rather than delayed by 1,536
cycles. Its look-ahead is why this exact implementation is an offline
validation/export path, not a proposed real-time FPGA filter. The group delay
above is the equivalent causal latency. Between adjacent integer-cycle FIR
values the rational resampler performs deterministic integer linear
interpolation. RLE coefficient prefix sums avoid expanding the capture to one
text row per CPU cycle.

Merely taking every 37th CPU sample would have neither an exact 48 kHz rate
nor rejection above the 24 kHz output Nyquist limit. The fixed FIR plus exact
`352/13125` rational schedule supplies both.

## DC removal and PCM policy

The mixer is intentionally unipolar. Moreover, the NES triangle DAC retains
its sequencer code when gated; after reset the established raw code is 15.
Changing the Phase 5H mixer to hide either behavior would break its verified
contract. Phase 5J instead applies this signed fixed-point first-order high
pass after resampling:

```text
y[n] = x[n] - x[n-1] + R * y[n-1]
R    = 1,072,337,219 / 2^30 = 0.99869186...
```

This is the reproducible 10 Hz DC-blocking policy at 48 kHz. Frequencies near
and below 10 Hz are intentionally attenuated; ordinary APU musical content is
well above it. Constant left-edge extension initializes `x[-1]` to the first
filtered value and `y[-1]` to zero. Thus an unsigned constant resting code
becomes exact centered PCM silence without an artificial start click. The
silence scenario produces 4,800 samples whose peak and RMS are both zero.

High-pass output is multiplied by a fixed gain of `3/4`, then mapped from the
Q0.20 scale to signed 16-bit PCM. Division uses round-to-nearest with exact
halves away from zero, followed by explicit `[-32768, 32767]` saturation.
There is no automatic or scenario-dependent normalization. All qualified
scenarios have zero clipped samples. WAV encoding is written directly as a
canonical little-endian PCM RIFF file: one channel, 48,000 Hz, 16 bits, two
bytes per frame.

## Original generated test ROMs

`scripts/generate_apu_audio_phase5j_roms.py` emits NROM-128 `.nes` images and
matching one-byte-per-line PRG files for these original programs:

| Scenario | CPU action |
| --- | --- |
| `pulse1` | 50% Pulse 1, timer 253 |
| `pulse2` | 50% Pulse 2, timer 169 |
| `triangle` | Triangle, timer 126 |
| `noise` | long-mode noise, period index 4 |
| `dmc` | fastest-rate loop over an original 17-byte sample |
| `combined` | all five channels concurrently |
| `silence` | channels disabled |
| `silence_transition` | silence, Pulse 1, silence, then injected reset |
| `melody` | 12 original CPU-timed notes with Pulse 1/2 and Triangle |

The DMC bytes are
`55 aa 0f f0 33 cc 69 96 87 78 1e e1 4b b4 25 da 5a` at `$E000-$E010`.
They are not synthesized by the WAV converter. In both DMC-bearing short
captures, the testbench observes the sequence through real DMC DMA and the
cartridge bus, including repeated loop refills. The verifier requires the
first 17 acknowledged addresses and values to match the generated ROM exactly.

The melody begins and ends with silence. CPU delay loops time each note, and
the CPU performs 79 APU writes while executing 2,076,421 instructions during
the 3-second capture. Its timer sequence is original to this test and is not
derived from commercial game code or music.

## Measured qualification results

The following files were generated locally from the qualified real RTL run.
Peak and RMS are signed-16 sample units. Hashes cover the complete capture and
complete WAV bytes; artifacts themselves remain ignored build output.

| Scenario | Duration / samples | Instructions / writes / fetches | Events | Peak / RMS | Frequency | Capture SHA-256 | WAV SHA-256 |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Pulse 1 | 0.100 s / 4,800 | 59,679 / 6 / 0 | 89 | 3,706 / 1,901.90 | 440.389 Hz | `aa30312ec38e81a0c19365bba49e61e52fb01f47041a0b1a9b91b19b745ffbca` | `6268d16b5f6485afda9ea1726041e92f5c16073f1dd88db70c656ea67e2b308e` |
| Pulse 2 | 0.100 s / 4,800 | 59,679 / 6 / 0 | 133 | 3,957 / 1,896.12 | 657.940 Hz | `4516a970d433b54b85feb78bfda2a1bc24ba6684075ee05bd0a52c28994578e3` | `cb3788cded4cfcd3ac65c115b0ff87dc15a0180f27ba0562cbd15a44e0041fbf` |
| Triangle | 0.100 s / 4,800 | 59,679 / 6 / 0 | 1,268 | 5,883 / 1,991.65 | 440.627 Hz | `668d837fa63a72b95f7e581ed760d7bedc49f76e1c1906a9697e83904b03b19d` | `466f2e63eba661b1515c072594b6e03e9b9b44a476905fcb1e9b65d5edcb8e58` |
| Noise | 0.100 s / 4,800 | 59,679 / 6 / 0 | 1,296 | 3,455 / 1,510.95 | n/a | `924b11aba65a7a387f4bec6858f433405f577f99739794793a13292989ed78bf` | `ae098ec900ee8e804368eee7d05f150d5aeb01cf631c6c9011983bbf95523046` |
| DMC | 0.100 s / 4,800 | 59,268 / 7 / 414 | 3,302 | 648 / 225.63 | n/a | `91ab9c6e1cb17c667bd23d408d319f83c07e886cdab25e59e4da61184ea81912` | `fff040c8765218b9658b2a017c26e2b1c42d63ffcaa3efa06aead9fc01d0e62e` |
| Combined | 0.100 s / 4,800 | 59,294 / 20 / 414 | 5,995 | 6,619 / 2,250.42 | n/a | `8e7fffbe77106ec53abe035e9297f95d09ed15fd8ddab5ef198011c6703fb5d0` | `b14a2af683a281e30ec13f26cd77669739e330dc96e797a8c7b26d0c608faf6a` |
| Silence | 0.100 s / 4,800 | 59,671 / 2 / 0 | 1 | 0 / 0.00 | n/a | `3d65931fbaea81580086dd61556dadcdf0404aa76b0b50c1fffe3e93bc4302b5` | `639dad0ac2923f5fe9e9ccfb99aa9b3084048e2e53317d1903e6e899a4f6296a` |
| Silence/tone/reset | 0.600 s / 28,800 | 426,284 / 9 / 0 | 163 | 3,983 / 1,055.71 | n/a | `01b56a724bdc5fd9a5cfa8db15138bfc5a27927c0b469b74d8b01bd532fbcc54` | `637a10a192afc2473c7755cdc76e2f04a109221a6930eb8a341cb6c6ae33c2c3` |
| Melody | 3.000 s / 144,000 | 2,076,421 / 79 / 0 | 22,701 | 6,574 / 2,719.18 | changing | `9792743e9f423cf56211ffd762c8bdc82a38dfcef4fbe2825932b91a8502548a` | `2c18bc7d694a7f03224f4f5ac10af5434d61fac1d8e5ed60cdda234574ff5be9` |

For timer `t`, expected pulse frequency is `CPU/(16*(t+1))`; expected
Triangle frequency is `CPU/(32*(t+1))`. Pulse 1 expected 440.396832 Hz and
measured 440.389284 Hz (0.0017% error). Pulse 2 expected 658.004679 Hz and
measured 657.940214 Hz (0.0098%). Triangle expected 440.396832 Hz and measured
440.626542 Hz (0.0522%). Measurement uses median interpolated positive PCM
zero-crossing periods and is independent of the programmed-timer calculation.
All are inside the fixed 0.25% acceptance tolerance.

Individual scenarios prove variation from Pulse 1, Pulse 2, Triangle, Noise,
and DMC; the combined run proves that all five raw values vary in one real
mixed stream. Every one of the 34,948 captured Q0.20 change events across the
nine scenarios exactly equals the independent Phase 5H quantized mixer model.
There are zero unexpected mixer mismatches.

## Pause, reset, and determinism

Debugger pause deauthorizes the scheduler. The combined capture pauses at
audio cycle 80,000 for 96 fabric clocks and asserts that CPU slots, all raw
channels, and `mixed_audio` remain fixed. Paused wall time is omitted from the
WAV: it neither advances emulated time nor inserts repeated audio. This makes
WAV duration describe NES time rather than simulator wall time.

The transition capture asserts functional reset after its tone has returned
to silence. During reset the testbench checks zero pipelined mix, zero pulse/
noise/DMC codes, reset Triangle position/code 15, and deasserted IRQ. Reset
fabric clocks likewise do not create NES-time samples. CPU restart and new APU
writes after release are recorded at the same deterministic audio-cycle
boundary.

The complete combined simulation, including its pause, is run twice. The two
capture files compare byte-for-byte. Independent conversions produce equal
PCM tuples and byte-identical WAV files:

```text
capture SHA-256  8e7fffbe77106ec53abe035e9297f95d09ed15fd8ddab5ef198011c6703fb5d0
WAV SHA-256      b14a2af683a281e30ec13f26cd77669739e330dc96e797a8c7b26d0c608faf6a
```

Fixed ROM contents, fixed RTL initialization, committed integer FIR
coefficients, rational phase arithmetic, fixed-point high pass/gain, explicit
rounding, and manual RIFF encoding remove seed, host-time, and codec-library
variation.

## Verification and production result

The pre-change `a2874b7` baseline used Python 3.14.4, Verilator 5.032, and
Quartus Prime Lite 23.1std.1 Build 993. It passed 1,900 Python tests, full RTL
lint and regression, the 774,134-cycle complete-APU and 37,137-row mixer
comparisons with zero mismatches, the 685,592-fabric-cycle CPU/APU run, the
300-frame playable ROM, 83-frame Developer Mode, 132-frame debugger, runtime
boot/library, controller, DMA, CPU/PPU, and VGA suites.

Phase 5J adds 20 Python tests for exact sample timing, FIR properties,
analytic tone/silence conversion, deterministic RIFF bytes, strict malformed
capture handling, mixer mismatch rejection, and every generated legal ROM.
The FULL RTL path adds all nine captures above, exact mixer/event checks, DMC
ROM fetch checks, pause/reset checks, and repeated-capture determinism. On the
qualification host the complete Phase 5J audio command takes about two minutes;
the Verilated simulation uses about 41 MiB while the listenable 3-second run
accounts for roughly 56 seconds. FAST feature-push CI retains Python/filter/
format checks; FULL pull-request CI runs the real RTL captures. No WAV binary
is uploaded or committed by default.

No production RTL or timing constraint changes in Phase 5J. Production
Analysis & Synthesis, Fitter, Assembler, Timing Analyzer, and conversion pass
with the Phase 5I hardware image unchanged:

| Resource/timing item | Phase 5J qualification |
| --- | ---: |
| ALMs | 6,151 / 32,070 (19%) |
| Logic / route-through / memory ALUTs | 8,344 / 1,111 / 590 |
| Total / dedicated registers | 6,323 / 6,097 |
| M10Ks | 270 / 397 (68%) |
| MLAB / block-memory bits | 18,880 / 2,199,552 |
| DSP blocks / PLLs | 2 / 1 |
| Worst setup slack | +1.013 ns |
| Worst hold slack | +0.077 ns |
| TNS | 0.000 ns in every reported domain/corner |

The worst setup path is the 25.2 MHz VGA-domain `video.output_x[9]` to
`VGA_B[5]` path. The slow-85C `CLOCK_50` critical path is CPU decoded
addressing-mode state to the registered mixer TND segment with +1.366 ns
slack. Global worst hold is an HPS DDR hard-memory-PHY LFIFO to OCT path; the
slow-85C `CLOCK_50` OAM-address-to-MLAB hold path is +0.283 ns. Map/Fitter/
Assembler/Timing warning counts are 100/148/0/144, all in established
generated HPS/IP, unused/incomplete board I/O, PLL, bidirectional-buffer,
legacy ROM initialization, VGA sync, or timing-advisory categories. There are
no timing failures and constraints were not relaxed.

## Generate, export, and listen

From the repository root, generate only the 3-second original demonstration:

```bash
scripts/run_apu_audio_phase5j.sh --demo
```

The playable file is `build/audio/phase5j_melody.wav`. Any standard PCM WAV
player can open it. Run every scenario and the repeated determinism check with:

```bash
scripts/run_apu_audio_phase5j.sh --full
```

Convert any existing valid RTL capture independently with:

```bash
python3 scripts/export_apu_wav.py \
  build/audio/phase5j_pulse1.apucap \
  build/audio/pulse1.wav \
  --measure-frequency \
  --metrics-json build/audio/pulse1.json
```

The exporter reports duration, sample count/rate, peak, RMS, clipping count,
instruction/write/fetch evidence, optional frequency, and complete capture/
WAV hashes. It exits nonzero on malformed, inconsistent, oversized, or
mixer-invalid input.

## Known limits and Phase 5K boundary

- Conversion is fixed to mono 48 kHz signed-16 PCM and a fixed 0.75 gain.
- The centered symmetric FIR is an offline exporter; it uses future samples
  and is not a real-time FPGA implementation.
- The 10 Hz high pass intentionally removes DC and attenuates sub-10-Hz
  content. It does not model every component of a particular console's analog
  output filter.
- Frequency, peak, RMS, and clipping measurements prove numerical behavior,
  not subjective sound quality.
- Captures are bounded to about 11.17 seconds by the 20,000,000-cycle safety
  limit; the limit can be revisited if longer local exports become useful.
- No physical DE1-SoC behavior is claimed or required.

Phase 5K remains future real-time audio-output work. Phase 5J deliberately
stops at deterministic offline PCM/WAV validation and adds no 5K/5L hardware.
