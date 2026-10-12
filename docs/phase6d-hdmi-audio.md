# Phase 6D — HDMI audio integration and verification

## Scope and qualification boundary

Phase 6D implements a simulation-first PCM broadcast, independent HDMI FIFO,
stereo I2S transport, shared-I2C audio configuration/readback, recovery and
diagnostics. No NES CPU, PPU, APU, mixer, cartridge or controller behavior is
changed. Phase 6E, USB-C DisplayPort, FPGA TMDS and production PCB work are not
started. The DE1-SoC and an external transmitter are unavailable.

`phase6d_hdmi_audio_top` is a logical integration target, not a new physical
DE1-SoC pinout. Its default `ALLOW_UNQUALIFIED_AUDIO=0` prevents transmitter
audio configuration. The standalone Quartus project explicitly sets it to 1
for logical synthesis; every transmitter signal remains a virtual pin. The
production `de1_soc_nes_vga_top` keeps its WM8731/VGA wiring and reports HDMI
audio unavailable. It does not emit physical HDMI audio.

ADV7513 programming details are available, so a documented candidate profile
can be simulated. **Physical transmitter/carrier configuration remains
qualification-blocked.** Register readback is evidence about register state,
not proof of HDMI packets, TV audio, compliance or analog pop-free operation.

## Official references and hardware audit

- [ADV7513 data sheet, Rev. B](https://www.analog.com/media/en/technical-documentation/data-sheets/adv7513.pdf), audio AC timing and pin table.
- [ADV7513 Hardware User's Guide](https://www.analog.com/media/en/technical-documentation/user-guides/ADV7513_Hardware_User_Guide.pdf), audio input and clocking.
- [ADV7513 Programming Guide, Rev. B](https://www.analog.com/media/en/technical-documentation/user-guides/ADV7513_Programming_Guide.pdf), audio configuration, channel status, InfoFrames and ACR; notably the audio sections and N-value table.

The candidate supports LPCM I2S and S/PDIF. This phase selects normal I2S,
16-bit words, two channels on I2S0, 32-bit channel slots, LRCLK low for left,
and rising-SCLK capture. Audio-data and LRCLK setup/hold are each 2 ns. The
applicable SCLK duty range is 40–60% for the selected N/2-even case. External
MCLK is not required in the selected internal-clock mode. No MCLK ratio is
invented. Candidate LQFP-64 pins are I2S0=5, SCLK=9, LRCLK=10, optional MCLK=4;
these are IC pin numbers, **not FPGA package assignments**.

The external transmitter performs HDMI packetization and automatic CTS
generation. The documented 48 kHz N value, 6144, is configured through I2C;
there is no FPGA audio-packet or N/CTS generation engine. Phase 6C's documented
power/address-latch delay, PD behavior, HPD filtering, video configuration and
EDID validation are retained. Reset/reconnect reruns video qualification before
the audio stage. Physical sequencing and sink behavior still require testing.

## Architecture and actual interfaces

```text
APU Q0.20 mixer / APU tick (50 MHz fabric domain)
  -> existing Phase 5K resampler and conditioner
  -> pcm_output_sample / pcm_output_valid
       +-> existing codec FIFO -> existing WM8731 I2S
       +-> hdmi_audio_transport FIFO -> hdmi_i2s_tx -> external transmitter

Phase 6B video -> Phase 6C RGB/HPD/EDID controller
                    -> shared I2C ownership -> audio profile + readback
                    -> prime / enable / mute / recovery
```

| Module | Actual Phase 6D interface/responsibility |
|---|---|
| `nes_audio_output` | Adds signed `[15:0] pcm_output_sample`, `pcm_output_valid`, `pcm_output_reset`, `hdmi_audio_clk`; optional `ENABLE_HDMI_CLOCK` defaults off |
| `hdmi_audio_transport` | `source_clk/source_reset`, `pcm_sample/pcm_valid`, `accept_samples/fifo_flush/sample_ready`; `audio_clk/audio_reset`, `stream_enable/mute`; I2S and counters |
| `hdmi_i2s_tx` | FIFO empty/data/read-enable, sample/underrun/frame events, BCLK/LRCLK/data |
| `hdmi_audio_controller` | Video/HPD/clock/prime qualification, mute/clear, FIFO faults, ordered configuration and recovery |
| `adv7513_audio_config_engine` | Independent audio read-modify-write and readback stages over the existing register-command protocol |
| `hdmi_audio_edid` | Streaming CTA Basic Audio or explicit stereo/48 kHz/16-bit LPCM SAD recognition |
| `phase6d_hdmi_audio_top` | Instantiates actual Phase 5K PCM/codec/PLL, HDMI branch and Phase 6B/6C video/control; accepts `APU_MIXED_AUDIO`, `APU_TICK`, `SOURCE_RESET`, codec and HDMI bus inputs |

The PCM sample is stable with a one-fabric-cycle valid pulse. It is signed
two's-complement mono at exactly 48,000 samples/s relative to nominal CLOCK_50
and the existing APU tick schedule. Phase 5K uses 352/13125 samples per nominal
19,687,500/11 Hz APU tick stream. No second resampler, mixer change or gain
change is introduced. The original 961-tap FIR and conditioner remain intact.

The producer is real-time and cannot be backpressured. `sample_ready` describes
HDMI acceptance; it is not fed back into the APU or WM8731 branch. Each valid
sample accepted while full is explicitly counted as an overrun. Outside an
accepting state samples are intentionally discarded; reconnect starts a fresh
epoch rather than replaying the intervening audio. No timestamp is needed:
the FIFO preserves order, and consumed-sample/fault counters expose progress.

## Clocking, CDC and audio/video coordination

The existing audio PLL retains its exact 12 MHz codec output. With
`ENABLE_HDMI_CLOCK=1`, a second output of **that same PLL** supplies 50 MHz to
HDMI serialization. Quartus realizes a common 600 MHz VCO with /50 and /12
outputs. There is no additional audio PLL. The standalone target has two PLLs
total: video plus audio; production also retains its previous two PLLs.

The HDMI serializer schedules BCLK half-edges at 768/6250 of 50 MHz. Each half
period is 8 or 9 clocks (160 or 180 ns), yielding 3.072 MHz average BCLK and
48 kHz LRCLK. Adjacent high/low times give 47.06–52.94% duty. A frame is 1041
or 1042 fabric clocks; fractional scheduling has no accumulated rate error.
The existing 12 MHz WM8731 serializer is deliberately not reused for HDMI:
its 1/2-clock half-edge quantization would not meet the ADV7513 duty limit.
Oscillator tolerance and physical jitter are not measured by this simulation.

PCM crosses fabric 50 MHz to PLL-output 50 MHz through the reused Phase 5K
`audio_async_fifo`, depth 32, with registered Gray pointers and two-flop
synchronizers. Although nominal frequencies agree, phase is not assumed.
Full/empty detection, wraparound, occupancy and reset are retained. Prefill is
four samples, about 83.3 us. Stream/mute/flush controls are synchronized;
consumed and underrun counters are registered Gray codes before crossing back.
FIFO occupancy is a synchronized source-side estimate, not an instantaneous
cross-domain measurement. PCM words never pass through direct bus sampling.

FIFO flush clears the write side immediately and the read side after its
two-stage flush synchronizer. It also disables consumption; reconfiguration
and four fresh samples precede unmute. BCLK continues across link flush and
user mute while the clock domain is operational. A source/codec reset or PLL
loss resets the serializer; release uses the existing reset synchronizer.
The broadcast still depends on successful WM8731 initialization, inherited
from Phase 5K. The controller's clock-ready input is PLL lock qualified by
`!pcm_output_reset`; its diagnostic therefore means **operational audio clock
domain**, not an independent frequency or raw PLL measurement.

At exactly 60 Hz, 48,000/60=800 is a consistency check, never a frame-triggered
restart. Audio has no video-frame reset or sample-drop/duplicate correction.
Importantly, the existing Cyclone V video PLL requests 74.25 MHz but Quartus
fits 50 MHz x49/33 = 74.242424 MHz (about -102.03 ppm). Thus fitted video is
approximately 59.993878 Hz and about 800.081633 audio samples/frame. The tests
exercise nominal and fitted video clocks separately; neither alters audio.
This existing video approximation is disclosed, not silently treated as exact
60 Hz or changed in Phase 6D.

## Stereo/I2S contract

Both channels carry the same unchanged 16-bit sample. For each 32-bit slot,
captured position 0 is the I2S delay, positions 1–16 are bits 15–0 MSB-first,
and positions 17–31 are zero padding. LRCLK is low for positions 0–31 and high
for 32–63. Data and LRCLK change only at falling BCLK; the candidate captures
at rising BCLK. Reset drives clocks/data low, followed by deterministic silent
framing. `SLOT_WIDTH=32` is the supported clock/profile setting, enforced at
elaboration; alternative slot rates are not advertised.

Signedness is preserved in the 16-bit payload: +32767=`7fff`, -32768=`8000`,
-1=`ffff`. Mathematical 32-bit sign extension would produce `00007fff`,
`ffff8000`, `ffffffff`; that does **not** mean sending sign-filled I2S padding.
There is no numerical 32-bit sample conversion in the transport. Tests cover
these boundaries, zeros, positive/negative values, equality, order and padding.

## Audio configuration and sink policy

Audio gets bus ownership only after Phase 6C video/EDID is running. The first
CTA extension must advertise Basic Audio or a qualifying LPCM SAD. Its result
is used only with the existing validated EDID/video mode. Video-only and
unsupported sinks remain silent without an invented I2C failure.

The profile uses main-map 7-bit address `0x39`. Every write is masked RMW; a
separate verification pass checks final fields, not merely ACKs. Transient
packet-disable/update-lock values are excluded from final-state verification.

| Order | Register | Mask/value | Purpose |
|---:|---|---|---|
| 0 | `44` | `68/00` | Disable audio-related packets during update |
| 1–3 | `01,02,03` | `0f/00, ff/18, ff/00` | N=6144 |
| 4 | `0a` | `fc/00` | Automatic CTS, I2S source |
| 5 | `0b` | `e0/00` | Rising capture, internal MCLK mode, S/PDIF off |
| 6 | `0c` | `ff/c4` | Normal I2S, I2S0 enabled |
| 7 | `0e` | `3f/01` | Channel mapping |
| 8–10 | `12,14,15` | `ff/00, 0f/02, f0/20` | Channel status, 16-bit word, 48 kHz; preserve video Input ID |
| 11 | `4a` | `20/20` | Hold audio InfoFrame update |
| 12–16 | `73..77` | `ff/01, ff/00, ff/00, ff/00, ff/00` | Stereo Audio InfoFrame |
| 17 | `44` | `68/68` | Enable ACR, samples and audio InfoFrame |
| 18 | `4a` | `20/00` | Release audio InfoFrame update |

States are RESET, WAIT_VIDEO, WAIT_CLOCK, CONFIGURE, VERIFY_CONFIG,
PRIME_AUDIO, ENABLE_AUDIO, RUNNING, MUTED, FAULT and RECOVERY. Default clock
wait is 1 s, prime timeout 100 ms, recovery delay 100 ms, with three controller
configuration-recovery attempts and two per-command retries. An in-flight bus
transaction drains before ownership is reused. A failed readback never marks
the transmitter configured. Audio RMW preserves unrelated video fields.

## Mute, HPD and recovery

Startup, disconnected, unconfigured, reset and fault conditions are muted.
User mute continues consuming the queue but emits zero samples. It does not
accumulate stale audio. Changes take effect at a complete stereo frame
boundary, after control synchronization, so a current frame can finish.
Runtime mute uses PCM zeros, not a claimed hardware AVMUTE transaction.
The transmitter may send zero-valued packets while the controller primes.

Phase 6C retains symmetric 5 ms HPD debounce. A stable disconnect disables
audio, latches link loss and flushes the queue. Reconnect repeats video/EDID,
audio configuration/readback and prefill. PLL/source/codec reset discards the
current audio epoch. Underrun emits zeros and requests recovery; overrun is
counted and also requests recovery. Persistent configuration failures reach
FAULT/RECOVERY_FAILED; explicit fault clear or a new link session permits a
new attempt. No audio action gates VGA, CPU, APU or the WM8731 consumer.

## Phase 5M diagnostic extension

MMIO remains at `0xff201000`, span 512 bytes, append-only version **1.2**,
build `0x0006000d`. Existing offsets and commands are unchanged. Capability
bit 7 describes the schema; availability bit 13 is asserted only by wrappers
that actually connect HDMI audio (`HDMI_AUDIO_AVAILABLE`, default false).
Production ties the new inputs to unavailable/muted values. The atomic
snapshot bank grows from 86 to 93 words using the existing mailbox CDC.

| Offset | Register / meaning |
|---|---|
| `110` | HDMI_AUDIO_STATUS: enabled[0], configured[1], muted[2], operational clock locked[3], sticky fault[4], state[8:5] |
| `114` | HDMI_AUDIO_SAMPLE_COUNT: FIFO words consumed, including user-muted words |
| `118` | HDMI_AUDIO_FIFO_OCCUPANCY |
| `11c` | HDMI_AUDIO_FIFO_UNDERRUNS |
| `120` | HDMI_AUDIO_FIFO_OVERRUNS |
| `124` | HDMI_AUDIO_RECONNECT_COUNT |
| `128` | HDMI_AUDIO_LAST_ERROR |

CONTROL bit 6 requests an explicit one-fabric-cycle HDMI audio fault clear.
The Python client exposes `clear_hdmi_audio_fault()` and decoded status.
Counters saturate (sample/under/over), survive link FIFO flush, and reset with
their respective source/audio reset epoch. Reconnect count is controller-reset
scoped. Sticky last error survives successful recovery; a new detected error
replaces it and explicit clear clears it. Clearing does not erase counters.

| Value | Stable HDMI-audio-local error |
|---:|---|
| 0 | NONE |
| 1 | HDMI_AUDIO_CLOCK_UNLOCKED (qualified domain unavailable) |
| 2 | HDMI_AUDIO_CONFIG_NACK |
| 3 | HDMI_AUDIO_CONFIG_TIMEOUT |
| 4 | HDMI_AUDIO_CONFIG_VERIFY_FAILED |
| 5 | HDMI_AUDIO_FIFO_UNDERRUN |
| 6 | HDMI_AUDIO_FIFO_OVERRUN |
| 7 | HDMI_AUDIO_LINK_LOST |
| 8 | HDMI_AUDIO_RECOVERY_FAILED |

These are observable digital events, not physical sound/voltage measurements.
The diagnostic report explicitly leaves physical HDMI audio NOT TESTED.

## Verification and reproducibility

Baseline started at `91a6bec` on `phase6/hdmi-audio`: 2,013 Python tests,
complete lint/RTL/system regression and the foundation Quartus build passed
before implementation. Production comparison uses the retained Phase 6C
production reports (not a newly rerun pre-edit full production build).
The continuation preserved the existing uncommitted Phase 6D work.

Tools: Python 3.14.4, pytest 8.3.5, Verilator 5.032, Quartus Prime Lite
23.1std.1 build 993. Platform Designer is the bundled 23.1 `qsys-script` /
`qsys-generate`, located by `generate_hps_loader_system.sh` outside PATH.

```sh
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
PATH="$PWD/.venv/bin:$PATH" bash scripts/test_hdmi_audio.sh
scripts/lint.sh
PATH="$PWD/.venv/bin:$PATH" scripts/build_de1_soc_nes_vga_quartus.sh
bash scripts/build_phase6d_hdmi_audio_quartus.sh
```

The independent Python model uses sample queues, mathematical I2S frames,
rational edge deadlines, capability parsing and link policy, not RTL pointer
encodings or state transitions. Random PCM and complete expected I2S frames
are generated independently into ignored `build/sim` artifacts.

| Verification | Result |
|---|---|
| Complete Python suite | 2,036 passed (2,013 baseline + 23 additions) |
| Complete Verilator lint | Passed; existing warning policy retained |
| Complete `scripts/test.sh` | Passed, including all CPU/PPU/APU/DMA/controller/mapper/loading/microSD/VGA/Developer Mode/debugger/5J/5K/5M/6B/6C suites |
| Directed HDMI transport | Silence, signed extrema, L/R equality, delay/padding, sample-valid, full/empty, overflow/underrun, reset/mute/flush; intentional faults accounted |
| Shared actual I2C | Audio-capable versus video-only EDID, RMW/readback, preserved video fields and packet masks |
| Audio EDID RTL | 14 basic/SAD/non-CTA/unsupported/truncated/empty/malformed capability cases |
| Seeded serializer | Seed `0x6d480001`, 270,817 clocks, 256 samples, zero mismatches |
| Seeded CDC | Same seed, 271,072 source clocks, 256 samples, four reset epochs, randomized producer phase/stalls/mute, FIFO high-water 32, zero mismatches |
| Seeded control | Same seed, 16 HPD/configuration/mute/recovery trials, 11,389 clocks; NACK/timeout/readback/overflow faults, recovery exhaustion and explicit clear; zero mismatches |
| Diagnostic extension | Snapshot values, state/flags, software decode and explicit-clear pulse checked |

Each long-run test covers 10,000,019 source clocks, about 200 ms: 9,600
generated samples, 9,596 consumed/decoded stereo frames, FIFO high-water four,
zero underruns/overruns and zero sequence mismatches. Four samples remain in
the primed pipeline; this is not unexplained loss. Actual 720p raster counters
and sync/active timing run concurrently with actual VGA timing. Nominal video
completes 12 frames and VGA 12; fitted video completes 11 plus a partial frame
in the same 200 ms, with identical audio accounting. The 800/frame check is
applied only to the independent nominal exact-60-Hz timeline. Audio is never
restarted by either raster.

### CPU-driven melody provenance

The retained Phase 5J melody executes 5,369,318 CPU cycles / 2,076,421
instructions, performs 79 APU writes and records 22,701 mixed-audio events.
All nine Phase 5J WAV scenarios still pass; melody is 144,000 samples / 3 s.
HDMI verification uses explicitly **staged deterministic capture/replay**,
not a claim of a monolithic CPU-to-HDMI simulation:

1. Validate every captured mixer event against the independent APU mixer.
2. Expand 20,000 APU ticks beginning at capture cycle 282180.
3. Independently calculate 536 expected samples with the Phase 5K causal Q18
   FIR and conditioner, including a fresh source-reset history.
4. Drive the actual `nes_audio_output` RTL, including codec I2C startup, FIR,
   conditioner and both consumer branches. Compare every observed PCM output
   and pin-decoded HDMI/WM8731 frame.

The integration check reaches 19,277 replay ticks, 516 checked PCM outputs and
512 decoded frames on each consumer, zero mismatches. It then restarts the
actual codec during playback, verifies both branches reset and resume fresh
zero-valued silence for 60,000 fabric clocks, and checks source-reset flushing
and counter reset. A separate 512-sample
Phase 5J WAV replay checks transport only; it is not substituted for the real
Phase 5K pipeline. Capture SHA-256:
`9792743e9f423cf56211ffd762c8bdc82a38dfcef4fbe2825932b91a8502548a`.
Generation records input offset, source hash, instruction/write counts and
model identity in `build/sim/phase6d_phase5k_pcm.json`.

Retained playable coverage includes 300 NES frames / 26,713,128 cycles,
production-top VGA playback 83 frames / 68,880,005 cycles, and debugger mixed
playback 132 frames / 187 acknowledged commands. No existing tests are removed
or weakened. Feature pushes remain FAST and PRs FULL; no extra hosted workflow
was added. WAVs, large traces, generated vectors and build artifacts are not
committed.

## Quartus and timing results

Production synthesis, fit, assembly, SOF/RBF generation and all-corners timing
passed. The production constraints are unchanged. The logical SDC keeps
the Phase 6C RGB capture budget, adds finite first-stage codec-CDC bounds and
specific asynchronous reset-source exceptions, and times downstream logic.
No blanket source/HDMI clock-group exception is added. All-path hold and
multi-corner optimization are enabled in the logical project.

HDMI audio I/O uses conservative single-cycle logical budgets. Fractional
clock-enable BCLK is not falsely modeled as an integer-divide generated clock.
RTL checks falling-edge launch, 160/180 ns half-periods and rising-edge data;
these do not replace package/carrier source-synchronous timing qualification.

| Production resource/timing | Phase 6C retained report | Phase 6D | Delta |
|---|---:|---:|---:|
| ALMs | 9,629 | 9,632 | +3 |
| Combinational ALUTs | 12,961 | 12,965 | +4 |
| Total / dedicated registers | 14,972 / 14,746 | 14,997 / 14,771 | +25 / +25 |
| M10Ks / memory bits | 275 / 2,238,504 | 275 / 2,238,504 | 0 |
| DSPs / PLLs | 7 / 2 | 7 / 2 | 0 |
| Worst setup slack | +1.382 ns | +1.549 ns | +0.167 ns |
| Worst hold slack | +0.077 ns | +0.065 ns | -0.012 ns |
| Setup/hold TNS | 0 / 0 ns | 0 / 0 ns | 0 |
| Unconstrained setup/hold paths | 0 / 0 | 0 / 0 | 0 |

Production recovery/removal/pulse-width minima are +3.375/+0.266/+0.608 ns.
The critical setup path is `video|green[0]` to `VGA_G[0]`; the critical hold
family is generated HPS DDR LFIFO-to-OCT-output-enable logic (slow-corner
report +0.143 ns; all-corner minimum +0.065 ns). Production compilation reports
402 warnings, in the retained generated-HPS/IP, constant/pruned nodes,
incomplete-I/O, generated-SDC-filter, Lite LogicLock and PLL-compensation
categories. There are no timing violations, latches or multiple-driver
warnings. The generated HPS DDR uncertainty advisories are not waived by new
constraints. No production HDMI pins are assigned.

| Logical interface resource/timing | Phase 6C | Phase 6D |
|---|---:|---:|
| ALMs / combinational ALUTs | 1,958 / 2,452 | 3,378 / 4,931 |
| Registers | 2,975 | 4,436 |
| M10Ks / memory bits | 204 / 1,658,880 | 210 / 1,698,344 |
| DSPs / PLLs | 3 / 1 | 8 / 2 |
| Worst setup / hold slack | +0.988 / +0.123 ns | +0.999 / +0.121 ns |
| Setup/hold TNS | 0 / 0 ns | 0 / 0 ns |
| Unconstrained setup/hold paths | 0 / 0 | 0 / 0 |

The logical target now includes the complete Phase 5K PCM/codec source, so its
extra PLL versus the video-only Phase 6C target is the reused audio PLL, not a
new HDMI-specific PLL. The final all-corner pulse-width minimum is +0.612 ns.
The critical setup path is `shared_video|...|output_active` to `HDMI_RGB[13]`.
The detailed slow-corner hold path is between framebuffer write-address
register duplicates (+0.219 ns); the all-corner minimum is +0.121 ns.

Logical compilation reports 25 warnings: timing-driven synthesis's initial
netlist notice, two inferred dual-clock RAM read-during-write notices,
constant high bits of diagnostic outputs, Lite LogicLock and automatic PLL
compensation. FIFO protocol prevents a consumed read and accepted write from
colliding at the same storage address: empty reads and full writes are not
accepted. Reset/flush also gates consumption. There are no ignored final SDC
filters, timing violations, latches or multiple drivers. Source/HDMI interfaces
remain **logically constrained virtual I/O**, not physically timed carrier I/O.

## Limitations and physical test plan

The profile, pins, clocks and packet behavior have no physical qualification.
Only the first CTA extension is considered, inherited from Phase 6C. There is
no compressed audio, multichannel mapping, sample-rate negotiation, sink-latency
compensation, adaptive resampling, hardware AVMUTE or HDMI compliance claim.
The HDMI branch inherits the codec-startup dependency. The long-run test is
200 ms per clock case, not an hours-long drift/thermal test. Oscillator ppm,
phase noise, metastability MTBF on a board, audible latency and pops remain
unmeasured. A qualification gate being open in a logical build is not approval
to connect an unreviewed carrier.

Before enabling hardware:

1. Qualify silicon revision, supplies/PD/straps, voltage translation, pull-ups,
   connector and actual carrier pin mapping; retain the documented startup delay.
2. Capture I2C RMW and readback on silicon; independently inspect input word/
   slot detection, N/CTS behavior, audio channel status and Audio InfoFrames.
3. Measure SCLK frequency/duty/jitter, LRCLK polarity/rate, I2S delay and 2 ns
   setup/hold at the transmitter pins. Replace logical I/O budgets with actual
   package and carrier delays; measure both PLL outputs and video ppm.
4. Play signed boundary patterns and the original melody through multiple TVs,
   monitors and capture devices; compare decoded PCM and channel mapping.
5. Exercise boot-disconnected, HPD bounce, unplug/replug, transmitter power/reset,
   codec reset, PLL loss, bus NACK/timeout and FIFO faults. Prove fresh prefill,
   silence, recovery, preserved VGA/WM8731 and bounded occupancy over hours.
6. Measure A/V latency, mute transitions, analog pops/noise and compliance with
   suitable instruments. Do not infer these outcomes from the simulation pass.
