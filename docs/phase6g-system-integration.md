# Phase 6G — Complete system integration and reliability

## Scope and entry gates

This phase consolidates the existing NES architecture. It adds no physical
interface, controller transport, mapper, processor instruction, or future-phase
hardware. The DE1-SoC is unavailable. All results below are software simulation
or Quartus results; physical VGA, LINE OUT, HPS/microSD, HDMI, and USB-C operation
remain **NOT TESTED**.

Before any source change, the working tree was clean on
`phase6/interface-integration` at
`8463e29fcbbba4dc0f93ec50146f8c4e217e4b90`. The Phase 3–6 documentation,
RTL, Python references/tests, host loader/library, diagnostics, build scripts,
and CI workflows were reviewed. A read/hash inventory covered 290 tracked
files (2,782,368 bytes). Baseline `scripts/test.sh` passed all **2,218 Python
tests**, complete lint, complete retained RTL regression and debugger tests.
The production Quartus synthesis, fitting, assembly, all-corners timing,
and RBF generation also passed before implementation began.

The baseline logs and reports are archived in ignored
`build/phase6g/baseline/`. Final qualification logs are
`build/phase6g/full-regression.log`, `lint-final.log`,
`quartus-production.log` and `quartus-hdmi-final.log`. Quartus reports and
critical slow-setup / slow-hold / fast-hold paths remain under the respective
`build/quartus_*/` directories. Generated logs and images are not committed.

## Integration boundary

The physical production target remains `de1_soc_nes_vga_top`: CPU, PPU, APU,
OAM/DMC DMA, both NES controller registers, Mapper 0, HPS loader, VGA,
WM8731 LINE OUT, Developer Mode and diagnostics. The existing Phase 6D target
remains a **separate logical HDMI qualification target** with virtual pins.
Its unqualified-audio opt-in is unchanged; production reports HDMI unavailable.

The new system bench connects actual production PPU/PCM streams to existing
720p/HDMI modules and an external transmitter/EDID behavioral model. Its second
framebuffer is a simulation instrument, not a new board image: duplicating the
204-M10K framebuffer in production would exceed this device's memory budget.
There is no claimed simultaneous physical VGA/HDMI implementation.

The Phase 6E power supervisor is exercised as a disconnected observer. Its
permit, reset and disable outputs do not control the production board. The
production diagnostic capability remains unavailable and its power registers
remain zero. Phase 6F's decision to defer USB-C video is preserved. USB HID,
Bluetooth, DP Alt Mode, physical PD control, advanced mappers and Phases 6H–9
are outside this change.

## Interface, clock and reset audit

| Boundary | Clock / transfer | Startup and recovery contract | Evidence or correction |
|---|---|---|---|
| CPU / PPU / APU / OAM and DMC DMA | One 50 MHz fabric clock; rational CPU/PPU enables; 3:1 PPU scheduling | Whole-NES functional reset, coherent debugger suspension; DMA owns accepted bus slots | Retained CPU/PPU/APU/DMA tests plus real ROM, DMC, OAM and controller execution |
| Mapper 0 / cartridge storage | Fabric synchronous PRG/CHR access | BEGIN holds NES before writes; COMMIT requires complete sequential image; ACTIVATE selects metadata before restart | Software MMIO plans replayed through production top; NROM128/CHR-ROM and NROM256/CHR-RAM |
| HPS / runtime loader | HPS user clock to 50 MHz; bundled-data request/acknowledge mailbox | Common bridge reset assertion, local synchronous release, exactly-once commands | Unrelated 71.428571 MHz test initiator; hardware HPS clock remains 97.368421 MHz; interrupted-transfer reset and reload |
| Controller inputs / $4016 / $4017 | Two-flop input synchronization, fabric serial ports | Strobe/latch and eight serial bits; $4017 writes remain APU frame-counter writes | Production switch path for Player 1; logical Player 2 test input; exhaustive retained protocol cases |
| PPU / VGA framebuffer | 50 MHz to 25.2 MHz; triple banks, stable bank plus toggle/ack | Display swaps at frame end; only complete frames publish | Completeness guard; reset both ownership endpoints on cartridge/HPS restart |
| PPU / logical 720p framebuffer | Fabric to nominal 74.25 MHz or fitted 74.242424 MHz | Same ownership protocol; either endpoint reset invalidates content | Coordinated content resets; raster remains running during source reset |
| Developer snapshot and command mailboxes | Fabric / VGA pixel clock; coherent held data and handshakes | Snapshot contents and command epochs belong to the current cartridge | Destination content reset and both debugger command endpoints now follow functional restart |
| PCM producer / WM8731 | 50 MHz resampler; async FIFO to 12 MHz codec domain | Codec initialized, clock locked, consumer reset released, four samples prefetched | Producer reset-release barrier; registered source Gray counters; repeated short resets |
| PCM / HDMI audio | Independent FIFO to PLL 50 MHz; shared PCM broadcast | EDID/configuration/clock qualification, FIFO prime, mute/flush on disconnect | Real PCM pin decoding, independent FIFO/recovery tests, no feedback into codec branch |
| HDMI control / pixel domain | 50 MHz I2C and HPD supervisor; two-flop enable and frame-toggle return | Initial/reconnected RGB starts at raster origin; loss of enable suppresses DE | Frame-aligned enable fix; 32 reconnect phases and full 720p timing/pixels |
| Diagnostic MMIO | Fabric snapshots to HPS mailbox; physical-reset lifetime | Remains live through cartridge reset; sticky faults and existing register meanings | Counter decreases rebase; do not synthesize a new underrun/overrun event |
| Logical USB-C power | Existing normalized packet / isolated observer | No DE1-SoC power actuator or assumed hardware | Synthetic fault packets while game/audio continue; production availability/provenance remain zero |

Reset assertion is asynchronous only at existing reset synchronizers; release
is synchronous in each destination. Framebuffer and snapshot content are
invalidated without stopping VGA timing during game replacement. Physical
KEY0 or loss of the production video PLL still resets the whole system as
before. Diagnostic state survives functional resets, but KEY0 clears its
lifetime counters. Audio PLL loss restarts codec initialization; a terminal
codec NACK requires the existing reset/retry interface (production exposes
KEY0, not a new MMIO retry register).

CDC review covers structural protocols and reset epochs. RTL simulation does
not model analog metastability. Existing clock groups, timing constraints,
and synchronizer attributes remain in place. The logical HDMI SDC adds only
the new codec-domain reset assertion into the producer reset synchronizer;
its fabric-domain release chain remains timed. No data path or existing
failing path was exempted to obtain timing closure.

## Reproduced defects and fixes

1. **A terminal coordinate could publish an incomplete framebuffer.** Sending
   `(0,0)` followed by `(255,239)` set a sequence error but still incremented
   the published-frame count on the original RTL. A per-capture corruption
   flag now requires all 61,440 coordinates in order. An interrupted capture
   restarts at a new frame origin, with the prior error sticky. Valid queued
   frames, freeze behavior and third-bank ownership are preserved.
2. **Cartridge reset left the VGA reader and debug destination in an old
   mailbox epoch.** The writer/producer reset while the reader retained its
   bank, acknowledgement or snapshot. A pixel-domain content reset now clears
   those endpoints on functional restart; the command mailbox clears both
   endpoints. The logical digital pipeline also coordinates unilateral resets.
3. **HDMI reconnect enabled RGB partway through a raster.** Original RTL failed
   the directed first-reconnect test. The adapter waits for frame origin,
   preserves its first pixel, and continues to suppress output promptly on
   disconnect. HS/VS and the forwarded clock retain their existing behavior.
4. **A short functional reset could outpace the codec reset domain.** The
   producer now waits until the consumer reset has released before clearing
   its own reset, restarting the converter, FIFO write pointer and prefill.
   Returning diagnostic synchronizers are cleared with that stream epoch.
   Codec sample/underrun Gray values are registered at their source, avoiding
   combinational conversion glitches during binary carries.
5. **Resetting an audio counter generated a false diagnostic fault/trace.**
   Original RTL failed deterministic counter row 17. Saturating counters now
   generate new events only when they increase; decreases establish a new
   baseline. Actual increases, sticky history and explicit clear semantics
   remain unchanged. There are **no MMIO extensions**: version **1.3**,
   addresses, masks and software-generated definitions are preserved.
6. **Quartus created implicit nets for debugger enum constants in diagnostic
   port expressions.** This warning already existed at the baseline. Moving
   the package-qualified comparisons into explicit intermediate signals
   removes all three project-owned implicit nets and preserves the intended
   pause/step diagnostic conditions. The production build now rejects any
   implicit-net warning originating in project RTL; the generated HPS DDR
   IP's separate `pll_dr_clk` warning remains vendor-owned.
7. **The returned framebuffer bank and acknowledgement had equal CDC depth.**
   A one-cycle delay in sampling the two-bit bank could release the pending
   reservation while the bank still appeared stale. The acknowledgement now
   has three stages behind the two-stage bank bus, matching the forward
   bundled-data guard. A directed 61,454-cycle test delays the bank return,
   verifies the pending reservation persists, and proves the next capture
   selects the third bank rather than the displayed bank. This is a digital
   sampling-skew test, not an analog metastability simulation.

The original failing framebuffer, ownership-skew, HDMI-enable, audio-reset
and diagnostic-counter logs are retained as local reproduction evidence under
`build/phase6g/`. These are intentional tests of the starting RTL, separate
from the passing final regression.

## Verification design

`verification/system_integration.py` supplies independent architectural models
for ordered frame admission, resettable saturating event counters, frame-origin
link admission and rational audio/video cadence. Thirty-three Python tests
include directed failures, three randomized damage seeds, three 10,000-step
counter-reset sequences, hotplug phases and exact fractional-rate checks.

`generate_phase6g_vectors.py` produces deterministic RTL expectations (seed
`0x60072026`). The fault framebuffer bench uses explicit fatal comparisons
without enabling the DUT's normal-input assertions, because those assertions
intentionally prohibit malformed coordinates. This matches the retained
Phase 6B fault-test convention; other new benches enable assertions, and no
retained assertion or test is removed.

`generate_phase6g_system.py` creates original project-owned Mapper-0 ROMs.
Game A retains the known checkerboard and adds all five APU channels, looping
DMC fetches, OAM DMA and eight-bit polling of both controller ports. Game B
proves the two PRG halves and CHR-RAM through actual CPU/PPU accesses. The real
software parser, load plan and MMIO transport generate the command streams.
The test substitutes only unavailable external HPS bus activity, Player 2's
logical input, and external codec/transmitter responses. Production RTL,
its loader/CDC, CPU, PPU, APU, DMA and audio paths execute normally.

Pixel expectations come from independent Python palette/scaling models for
all **307,200 VGA** and **921,600 HDMI** active pixels, including borders.
The HDMI check covers all 1,237,500 raster clocks, DE and positive HS/VS.
I2S receivers decode pin data with the one-bit delay, 16-bit MSB-first words,
32-bit slots, zero padding and duplicated stereo; expected words come from
queues of the broadcast PCM, never from serializer/FIFO data internals.
The retained CPU-capture/Python FIR test separately verifies PCM arithmetic.

Audio follows NES time, not output frame boundaries. At nominal 720p60 there
are exactly 800 samples per video frame; the fitted clock yields exactly
39,204/49 samples per frame. No frame event resets or retimes the audio
producer. Retained nominal/fitted long runs test cumulative sample count,
FIFO bounds, frame cadence and WM8731 independence. Display buffering can
add frame latency; this architecture has no timestamped lip-sync controller
and makes no physical display/audio latency guarantee.

Full verification remains the PR/release gate. Feature pushes retain the
existing FAST Python/full-lint/focused-smoke policy. New complete-system tests
run in FULL, use deterministic bounded workloads, and avoid large wave dumps.

```sh
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
PATH="$PWD/.venv/bin:$PATH" scripts/test_system_integration.sh
PATH="$PWD/.venv/bin:$PATH" scripts/build_de1_soc_nes_vga_quartus.sh
PATH="$PWD/.venv/bin:$PATH" bash scripts/build_phase6d_hdmi_audio_quartus.sh
```

## Qualification results

| Verification | Deterministic coverage | Result |
|---|---|---|
| Python | 2,251 tests, including 33 new architectural-model tests | Pass |
| Full Verilator lint | All retained production/logical targets | Pass, zero warnings/errors |
| Frame corruption/recovery | 250,332 producer vector cycles, four reset epochs, 61,440 recovered pixels | Zero mismatches |
| Ownership return skew | 61,454 producer cycles, one-cycle bank/ack sampling skew | Reservation preserved; original RTL fails |
| HDMI frame admission | 1,077 pixel clocks, 32 reconnect phases | Zero mismatches |
| Diagnostic counter epochs | 10,000 deterministic observations with counter resets | Zero false-event mismatches |
| Unilateral content reset | Six source/pixel reset epochs, recovered full Developer Mode frames | Zero mismatches |
| Codec/HDMI PCM reference | 19,277 CPU-capture input ticks, 516 produced PCM samples, 512 decoded words per output | Zero mismatches |
| Audio recovery | 1,762,216 fabric cycles; 32 one-to-four-cycle resets, source starvation, PLL loss and codec reinitialization | Recovery, silence and registered Gray transitions verified |
| Retained A/V cadence | Two 10,000,019-cycle runs, nominal and fitted video clocks; 9,600 produced / 9,596 transmitted samples each | No under/overruns; FIFO high-water four |
| Retained playable core | 26,713,128 cycles, 300 frames, 297 NMI handlers / DMAs / controller polls | Pass; original frame hashes preserved |
| Retained production VGA / Developer Mode | 69,720,005 fabric cycles, 84 frames, 82 coherent snapshots, 307,200 combined-frame pixels | Zero mismatches |
| Retained debugger | 132 frames, 187 commands / acknowledgements, 71 instruction steps, 41 frame steps | No lost commands; 129 NMI/DMA/controller-poll sequences |
| Complete production + logical HDMI system | 35,588,469 fabric cycles, 52 PPU frames, 13 reset epochs, 155,949 HPS commands | Zero mismatches |

The complete system run observed nine OAM DMAs, 2,674 DMC acknowledgements,
32,650 Player 1 reads, 32,648 Player 2 reads, 31,012 PCM samples (30,971
nonzero), 30,969 decoded WM8731 words and 13,260 decoded HDMI words. HDMI is
intentionally disconnected/requalified during part of the run; its lower
word count is not a PCM rate mismatch. Normal streaming had no FIFO under/
overruns. Separate fault tests intentionally cause and verify those faults.

Every retained test remains enabled. `scripts/test.sh` completed successfully
on the final RTL, including the complete Phase 6G suite. Final lint and RTL
compilation reported zero Verilator warnings/errors. Python took 93.74 s;
the final complete-system simulation took 442.46 s on this host while Quartus
was also running. The existing CI timeout remains 75 minutes; FULL adds the
bounded Phase 6G suite, while FAST keeps the established smoke selection.
Counts above are per test/clock domain and are not summed as one elapsed run.

Quartus Prime Lite **23.1std.1 Build 993** completed analysis/synthesis,
fitting, assembly, all-corners STA and production RBF conversion. Both targets
are fully constrained for setup/hold and have zero TNS at every reported
corner. Verilator is the existing pinned **5.032**.

| Measurement | Baseline production | Final production VGA/WM8731/HPS | Final logical HDMI A/V |
|---|---:|---:|---:|
| ALMs | 9,572 | 9,574 | 3,297 |
| Logic ALUTs | 12,946 | 12,974 | 4,819 |
| Routing ALUTs | 3,728 | 3,795 | 513 |
| Memory ALUTs | 590 | 590 | 0 |
| Registers | 15,027 | 15,046 | 4,430 |
| M10Ks | 275 | 275 | 210 |
| DSPs | 7 | 7 | 8 |
| PLLs | 2 | 2 | 2 |
| Worst setup slack | +1.364 ns | **+1.048 ns** | **+0.747 ns** |
| Worst hold slack | +0.077 ns | **+0.077 ns** | **+0.123 ns** |
| TNS | 0.000 ns | **0.000 ns** | **0.000 ns** |
| Synthesis / fitter / assembler / STA warnings | 108 / 149 / 0 / 144 | 105 / 149 / 0 / 144 | 22 / 3 / 0 / 0 |
| Total warnings (one count per compile stage) | 401 | **398** | **25** |

Final production recovery/removal/minimum-pulse-width minima are
**+3.375 / +0.460 / +0.608 ns**; logical HDMI minima are
**+9.784 / +0.740 / +0.612 ns**. No constraint was relaxed. The production
target costs two more ALMs than the measured baseline, with unchanged block
memory, DSP and PLL counts.

Critical production setup is `nes_vga_video:video|output_active` to
`VGA_B[2]`, slow 1100 mV / 85 C. Critical hold is the HPS DDR hard-PHY
`dq_ddio[2].ubidir_dq_dqs` path from `lfifo~LFIFO_OUT_OCT_LFIFO_DFF` to
`os_oct_ddio_oe~DFF`, fast 1100 mV / 0 C, on `afi_clk_write_clk`.
The baseline critical setup path was `developer_mode_enable~DUPLICATE` to
`VGA_G[1]`.

Logical HDMI critical setup is
`shared_video|pixel_reset_synchronizer|sync_ff[1]` to `HDMI_RGB[7]`, slow
1100 mV / 85 C, using the retained virtual `HDMI_TX_CAPTURE` clock. Critical
hold is the `shared_video|pipeline|framebuffer|expected_write_address[2]`
feedback path, fast 1100 mV / 0 C on `CLOCK_50`. These are logical carrier
timing assumptions, not physical HDMI measurements.

The three project-owned implicit-net warnings are gone. Remaining production
warnings include generated HPS DDR IP implicit/undriven/truncation/connectivity
messages, optimized/constant pins, the existing dual-clock RAM read-during-
write advisory, PLL compensation and I/O-assignment advisories, and generated
DDR SDC filters/exceptions (86 code 332049 and 58 code 332174 in STA).
The FIFO/ownership tests verify that active readers do not consume a bank or
entry being overwritten; they do not qualify analog memory collision behavior.
Logical HDMI warnings are the existing unused/constant/virtual-pin and fitter
advisories. No warning was hidden to obtain closure; no latches, multiple
drivers, negative slack or unconstrained setup/hold paths were accepted.

## Physical DE1-SoC bring-up plan (not executed)

1. **Identify and record the image.** Use the production SOF/RBF from this
   revision and its matching HPS Platform Designer handoff. Record board
   revision, clocks, monitor, cables, power supply, image hash and diagnostic
   version/build ID. Start with SW0/SW1 low and the project-owned legacy ROM.
2. **Reset and VGA.** Confirm stable 640x480 sync and checkerboard/game output;
   exercise KEY0 repeatedly, then SW0 test pattern and SW1 capture freeze.
   Confirm frame swaps occur without tearing and reset replaces stale content
   with black until a complete frame arrives. Exercise Developer Mode using
   the established build/virtual controls; do not invent a switch assignment.
3. **Codec and LINE OUT.** Check codec initialization/ACK/error counters and
   the 12 MHz master clock. Use LINE OUT into an appropriate line input.
   SW0 selects the existing diagnostic tone. Verify both channels, mute during
   reset, restoration after repeated resets, no sustained FIFO faults, and
   then the owned APU melody/game. Record analog noise, clicks and levels as
   new hardware observations, not prevalidated properties.
4. **HPS bridge and microSD.** Boot the matching HPS Linux image and mount the
   microSD game-library directory. First run header discovery and dry-run
   validation with owned NROM128/256, CHR-ROM/RAM, malformed, truncated and
   unsupported images. Check permissions and the existing MMIO IDs before
   using loader base `0xff200000` (64 bytes) or diagnostics base `0xff201000`
   (512 bytes). Use the existing CLI/transport rather than raw ad hoc writes.
5. **Replacement and recovery.** Load a valid game, replace it with another,
   repeat activation, interrupt a transfer, submit an incomplete image and
   verify NES hold plus live VGA timing and silent audio. A fresh valid BEGIN,
   complete load, COMMIT and ACTIVATE must recover. Runtime storage is a
   single staging store: there is no promised rollback to the overwritten
   image. HPS bridge reset or KEY0 returns to the legacy image.
6. **Diagnostics.** Capture coherent snapshots before/after each experiment;
   check sample/frame/loader/DMA progress, sticky fault causes and trace data.
   Verify functional resets do not fabricate audio faults, explicit clearing
   works, and KEY0 resets lifetime state. Production HDMI/USB-C capabilities
   and unavailable registers must remain unavailable/zero.
7. **Controllers and future USB boundary.** Verify Player 1 switch mapping and
   serial order. Player 2's production input remains zero until an external
   provider exists; its $4017 logical behavior is tested in simulation. A
   future USB implementation must deliver synchronized abstract button vectors
   to the existing two ports and be qualified separately for enumeration,
   disconnect/reconnect, latency and simultaneous inputs. No USB HID or
   Bluetooth driver is part of this phase.

Physical HDMI needs a qualified external transmitter/carrier and separate
pin, electrical, I2C, EDID, video, audio and sink testing. Physical USB-C power
needs its own qualified hardware. Neither is connected or claimed here.
