# Phase 6B — shared digital video pipeline

Phase 6B implements a sink-neutral 1280x720p60 scanout path for the NES video
source. It accepts the same 256x240 indexed-pixel stream used by VGA, retains
the existing palette and emphasis behavior, and presents registered RGB888,
positive horizontal and vertical sync, active-video/data-enable, pixel clock,
line boundaries, and frame boundaries for a future external HDMI transmitter.
It does not implement TMDS, HDMI packets or audio, USB-C DisplayPort, or a PCB
interface. No physical HDMI operation is claimed.

The production DE1-SoC top remains the proven VGA design. The new path is a
reusable selectable scanout block plus a standalone Cyclone V qualification
top; it is deliberately not connected to unassigned board pins. This preserves
VGA, Developer Mode, debugger, loading, CPU, PPU, APU, DMA, controller, HPS,
and codec behavior while making the digital pipeline independently verifiable
and synthesizable.

## Entry gate and baseline

Implementation began only after the following repository gate passed:

- branch `phase6/shared-video-pipeline`;
- clean working tree;
- starting commit `4896badfb7836e034a3af1bf6823d9ce408542b8`;
- existing Phase 6A architecture document present and reviewed.

The unmodified baseline passed 1,967 Python tests, complete Verilator lint and
RTL simulation, and the production Quartus fit/assembly/all-corner timing
flow. The baseline production image used 9,613 ALMs, 12,931 logic ALUTs,
15,011 total registers, 275 M10Ks, 2,238,504 block-memory bits, 7 DSPs, and
2 PLLs. Its worst setup and hold slack were +0.729 ns and +0.077 ns, with zero
TNS. The retained playable path ran 300 frames/26,713,128 fabric cycles, and
the complete 640x480 VGA and Developer Mode comparisons each checked 307,200
pixels without mismatch.

## Existing architecture and preserved boundaries

The PPU produces a raster-ordered visible-pixel stream containing an 8-bit
coordinate, 6-bit NES palette index, and 3 emphasis bits. `nes_framebuffer`
stores three complete 256x240x9 indexed frames. Its source side runs in the NES
rendering/fabric domain; its read side runs in the selected video pixel domain.
The current production `nes_vga_video` reads that store at 25.2 MHz and uses
640x480 timing. Normal mode is an exact 2x presentation; Developer Mode retains
the established 512x480 game plus 128x480 panel composition.

The framebuffer already provides the key sink-neutral boundary: a scanout
supplies a 16-bit linear address, receives one registered 9-bit indexed pixel,
and requests ownership changes only at its own frame end. Phase 6B reuses that
contract and the existing NES RGB palette rather than altering the PPU or
creating a second production video path.

## Framebuffer memory calculation

One NES frame contains:

```text
256 * 240 = 61,440 pixels
```

The alternatives calculated before implementation are:

| Representation | One buffer | Two buffers | Three buffers |
|---|---:|---:|---:|
| 6-bit palette index only | 368,640 bits / 45 KiB | 737,280 bits / 90 KiB | 1,105,920 bits / 135 KiB |
| 9-bit index plus emphasis | 552,960 bits / 67.5 KiB | 1,105,920 bits / 135 KiB | 1,658,880 bits / 202.5 KiB |
| RGB888 | 1,474,560 bits / 180 KiB | 2,949,120 bits / 360 KiB | 4,423,680 bits / 540 KiB |

The 5CSEMA5F31C6 has 4,065,280 block-memory bits and 397 M10K blocks. RGB888
triple buffering does not fit even in an otherwise empty device. RGB888 double
buffering would consume about 73% of raw block bits and leaves insufficient
headroom for the cartridge, audio, debugger, and other production memories.
Two indexed banks fit, but a producer can finish while one bank is displayed
and the other is awaiting a consumer boundary; it then has no safe place to
begin the next frame.

The selected architecture is therefore the existing three-bank 9-bit indexed
store, with palette expansion to RGB888 after the synchronous read port. It
uses 1,658,880 logical bits. The standalone fitted implementation occupies
204 M10Ks because 61,440x9 is not an exact M10K packing shape. Three banks let
the writer continue into a free bank while one complete frame waits and a
third is scanned. This is the smallest option that retains color emphasis and
avoids the systematic phase-dependent frame loss possible with two banks.

Instantiating an additional independent three-bank store alongside the
unchanged production VGA store would require about 3,897,384 logical memory
bits in the current image and roughly 479 M10Ks, beyond the device's 397-block
limit. Consequently, Phase 6B supplies one reusable, selectable framebuffer
and scanout pipeline rather than duplicating it in the production top. A later
dual-output design must arbitrate reads from shared banks, add a bounded line
prefetch/cache, or move the frame store to external memory. It must not simply
duplicate the present triple store.

## 720p60 timing and clock

`video_720p_timing` implements the standard 1280x720 progressive 60 Hz raster:

| Parameter | Active | Front porch | Sync | Back porch | Total |
|---|---:|---:|---:|---:|---:|
| Horizontal pixels | 1280 | 110 | 40 | 220 | 1650 |
| Vertical lines | 720 | 5 | 5 | 20 | 750 |

Both syncs are positive. A dedicated Cyclone V `altpll` transforms 50.000 MHz
to 74.250 MHz with a 297/200 ratio. The resulting 1,237,500 pixel periods per
frame produce exactly 60.000 frames per second. Quartus reports a 13.469 ns
generated-clock period. The timing block exposes active-video, coordinates,
line start/end, and frame start/end in addition to syncs.

`nes_720p_video` registers RGB, sync, data enable, coordinates, and boundary
strobes into one aligned output contract. Pixels are black outside active
video and outside the presentation canvas. Test-pattern and Developer Mode
controls pass through two-flop level synchronizers and are sampled only at an
output frame boundary, so a control transition cannot split a frame.

## Pixel mapping

Normal mode centers a 960x720 4:3 canvas in 1280x720, leaving deterministic
160-pixel black pillars at both sides. Vertical mapping is exact 3x:

```text
source_y = floor(output_y / 3)
```

Horizontal mapping covers all 256 NES pixels with deterministic nearest-
neighbor sampling:

```text
source_x = floor((output_x - 160) * 256 / 960)
         = floor((output_x - 160) * 4 / 15)
```

Each source pixel therefore produces either 3x3 or 4x3 output pixels, for 9 or
12 output samples, and no source pixel is omitted. Hardware uses exact bounded
reciprocal multiplies rather than general division. Exhaustive comparison
proves those products equal the mathematical floors at every legal coordinate.

Developer Mode preserves the existing logical composition inside the same
960x720 canvas. The game occupies x=160..927 and is exact 3x in both axes.
The established logical panel coordinates x=512..639, y=0..479 are mapped into
x=928..1119 by a deterministic 3:2 nearest-neighbor scale. The renderer
request remains in the original 640x480 logical coordinate system, so the
debugger's contents and page semantics do not change. This is a reusable
contract; production VGA continues using its current compositor.

## Frame ownership and clock-domain crossing

Only complete banks cross between the unrelated producer and pixel clocks.
The ownership protocol is:

1. On source frame start, the writer selects a bank that is neither displayed
   nor pending and accepts raster-ordered pixels.
2. The bank is unpublished until pixel 255,239 is written. Range and sequence
   errors become sticky status; a partial frame is never made displayable.
3. Completion publishes a bank identifier held stable with a request toggle.
   The toggle and held identifier use explicit synchronizer chains.
4. The reader changes banks only at its raw 1650x750 frame end, then returns an
   acknowledge toggle. It never scans the bank being written.
5. If a second frame completes before acknowledgement, the third bank retains
   it. The writer publishes it after the first acknowledgement. If all roles
   are occupied, a source frame is skipped rather than overwriting visible or
   complete data.

This protocol prevents partial-frame display and tearing. It preserves frame
order and avoids drops whenever the three ownership roles can absorb the
clock phase difference. It does not synthesize frames: if the source is slower,
the current complete frame repeats; if it persistently outruns the output and
all banks are owned, whole source frames may be skipped. Those are explicit,
safe rate-mismatch outcomes rather than unsafe multi-bit CDC.

The implementation also corrects an existing corner case in
`nes_framebuffer`: the first accepted pixel of an immediately adjacent frame
now advances the expected address from the selected start-of-frame address,
not from stale state. The new asynchronous back-to-back test exposed this
case.

## Digital interface

`nes_digital_video_pipeline` exposes the future transmitter-side signals:

| Signal | Meaning |
|---|---|
| `video_pixel_clock` | 74.25 MHz scanout clock supplied to the module |
| `rgb[23:0]` | registered RGB888, black during blanking |
| `hsync`, `vsync` | registered positive-polarity syncs |
| `active_video` | registered data enable |
| `frame_start`, `frame_end` | one-pixel aligned frame boundary strobes |
| `line_start`, `line_end` | one-pixel aligned line boundary strobes |
| `scan_x`, `scan_y` | aligned output-raster coordinates |
| `source_nes_x`, `source_nes_y` | aligned source-pixel coordinates |

It also exposes capture/pending/display bank status, sticky write faults,
16-bit capture/display counters, panel request/coordinates, and swap strobes.
The interface contains no serializer, packetizer, DDC/EDID, hot-plug, HDCP,
electrical level shifting, or transmitter configuration logic.

## Diagnostic extension

Phase 5M's MMIO aperture, register addresses, version, snapshot semantics, and
existing bits are unchanged. `VIDEO_STATUS` bits 4:0 retain their Phase 5M
meaning. Formerly reserved bits now report:

| Bit | Meaning |
|---:|---|
| 5 | framebuffer capture active |
| 6 | completed frame pending handoff |
| 7 | display bank contains a complete frame |
| 8 | sticky write-coordinate range error |
| 9 | sticky raster-sequence error |

Capture and fault levels already live in the 50 MHz diagnostic domain.
Display-valid crosses from the pixel domain through a forced two-flop
synchronizer and has an explicit first-stage false path. No unsynchronized
multi-bit value was added to diagnostics.

## Independent models and verification

`verification/shared_video.py` independently models all timing samples,
normal and Developer Mode coordinate mapping, every storage alternative,
three-bank ownership, and randomized asynchronous frame sequencing. It uses
direct mathematical division and a transaction-level ownership model instead
of copying the RTL reciprocal products or signal-level state machine.

The Phase 6B Python addition contains 19 collected tests. It exhaustively
counts a full 1,237,500-period timing frame, exhaustively covers the 960x720
normal canvas, checks all 61,440 source pixels and 230,400 pillar pixels,
checks Developer Mode bounds/coverage, samples 20,000 randomized coordinates,
verifies memory arithmetic, and runs 80 randomized frame-sequencing cases over
four producer/consumer rate relationships.

Four self-checking RTL benches add:

- exhaustive timing for all 1,237,500 pixel periods, including 921,600 active,
  30,000 HSYNC, 8,250 VSYNC, 750 line starts/ends, and one frame start/end;
- exhaustive normal and Developer Mode scaling, borders, bounds, source
  coverage, address checksums, and randomized inactive coordinates;
- two complete uniform indexed frames under asynchronous 50 MHz and
  approximately 74.25 MHz clocks, verifying atomic frame swaps, all normal
  game pixels, both pillars, frame-latched Developer Mode, and panel mapping;
- freeze, malformed raster sequence, out-of-range writes, sticky errors, and
  reset recovery in the framebuffer fault bench.

The RTL artifact contains:

```text
TIMING 1237500 921600 30000 8250 750 750 1 1
SCALER 691200 230400 21233249280 552960 138240 21254215680
PIPELINE 2 2 1935360 691200 138240
```

`scripts/verify_shared_video.py` recomputes these quantities from the Python
model and requires exact agreement. The pipeline comparison covers two atomic
swaps, 1,935,360 observed output periods, 691,200 normal game pixels, and
138,240 Developer Mode panel pixels. Verilator assertions additionally guard
coordinates, range, bank aliasing, and publication rules. Phase 5M's directed
test verifies all five added status bits after the required synchronization.

The final complete `scripts/test.sh` run passes 1,986 Python tests, all 78
self-checking RTL simulations, complete Verilator lint, all Phase 1 through 6B
RTL/model comparisons, playable game,
VGA, Developer Mode, debugger, loader, CPU, PPU, APU, DMA, controller, audio,
and diagnostic regressions. No existing assertion or constraint was disabled
in normal verification; only the dedicated malformed-input fault bench turns
off simulation assertions while deliberately driving invalid traffic, then
checks the synthesized sticky-fault behavior.

## Quartus results

`phase6b_video` is a standalone synthesis, fit, assembly, and all-corners
timing target for the complete clocked pipeline. Its synthetic source keeps
all three memories, CDC, scaler, palette, registered RGB path, and real
74.25 MHz PLL live. It is not a board pinout.

On Quartus Prime Lite 23.1std.1 Build 993 for 5CSEMA5F31C6, the fitted target
uses:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| ALMs | 267 | 32,070 | <1% |
| logic ALUTs | 391 | — | — |
| route-through ALUTs | 3 | — | — |
| total registers | 183 | — | — |
| dedicated logic registers | 166 | — | — |
| M10K blocks | 204 | 397 | 51% |
| block-memory bits | 1,658,880 | 4,065,280 | 41% |
| DSP blocks | 3 | 87 | 3% |
| PLLs | 1 | 6 | 17% |

All setup, hold, and minimum-pulse TNS values are 0.000 ns. The all-corner
slacks are:

| Corner/check | Pixel clock | 50 MHz clock |
|---|---:|---:|
| slow 85 C setup | +0.394 ns | +10.677 ns |
| slow 85 C hold | +0.412 ns | +0.219 ns |
| slow 0 C setup | +0.734 ns | +11.193 ns |
| slow 0 C hold | +0.400 ns | +0.208 ns |
| fast 85 C setup | +4.172 ns | +13.397 ns |
| fast 85 C hold | +0.217 ns | +0.128 ns |
| fast 0 C setup | +4.560 ns | +14.269 ns |
| fast 0 C hold | +0.210 ns | +0.118 ns |

Worst minimum-pulse slack is +0.612 ns. The worst setup path is from registered
`rgb[15]` to the qualification harness's `VIDEO_G[7]` output under its 3 ns
virtual transmitter delay: +0.394 ns, 6.514 ns data delay, zero logic levels.
The first internal framebuffer-RAM-to-RGB path is +1.385 ns. Timing Analyzer
recognizes eleven synchronizer chains with a two-register minimum and reports a
worst-case MTBF of at least 10^9 years.

Analysis/synthesis, fitter, assembler, and timing emit 0/4/0/0 warnings. The
four fitter messages are the Lite-only LogicLock notice, incomplete I/O
assignment notice, a critical unassigned-pin warning for 34 of the standalone
harness's 36 pins, and PLL compensation selection. The unassigned outputs are
intentional because Phase 6B defines no PCB/transmitter pinout; the 50 MHz
clock and reset are the only placed pins. These warnings do not occur because
of unconstrained timing paths or failed timing.

The production `de1_soc_nes_vga` target also completes synthesis, fitting,
assembly, RBF generation, and all-corners timing after the new reusable sources
and diagnostic status extension are added. It uses 9,586/32,070 ALMs (30%),
12,947 logic ALUTs, 590 memory ALUTs/18,880 MLAB bits, 14,981 total registers
(14,755 dedicated), 275/397 M10Ks and 2,238,504/4,065,280 block-memory bits,
7/87 DSPs, and 2/6 PLLs. Thus the existing VGA/audio production memory and PLL
footprint is preserved; the standalone 720p memory and PLL are not silently
duplicated into that image.

Production worst all-corner setup is +1.099 ns on the 50 MHz path from CPU
`operand_low[0]` to APU mixer `tnd_segment_q[4]` (18.558 ns data delay,
16 logic levels). Worst hold is +0.077 ns in the generated HPS DDR AFI domain
at fast 0 C. Every setup, hold, recovery, removal, and minimum-pulse TNS is
0.000 ns. The production warning counts are 106 analysis/synthesis, 149 fitter,
0 assembler, and 144 timing. They remain the known Platform Designer HPS/DDR,
pin-model, PLL-compensation, and clock-uncertainty classes; no Phase 6B
constraint produces an empty collection, ignored path, or timing exception.

Build the standalone proof with:

```bash
./scripts/build_phase6b_video_quartus.sh
```

The script fails on a missing artifact, unsuccessful stage, negative/missing
slack, timing-failure marker, latch/multiple-driver warning, or a PLL count
other than one. `scripts/report_phase6b_timing.tcl` emits the detailed top
twenty setup paths used for critical-path review.

## Remaining limitations

- There is no HDMI transmitter, TMDS electrical signaling, audio packetization,
  EDID/DDC/HPD handling, HDCP, USB-C DisplayPort, or production PCB design.
- The standalone top has no production video-pin assignments and is not an
  FPGA board image intended to drive an electrical interface.
- No monitor, external transmitter, cable, signal-integrity behavior, or
  physical HDMI output has been tested.
- Production remains VGA-only. Concurrent VGA and digital output needs a
  shared-read/prefetch design because duplicating the triple buffer does not
  fit the current M10K budget.
- Nearest-neighbor 15:4 horizontal expansion is deterministic and pixel
  accurate but intentionally nonuniform; no interpolation or CRT filtering is
  included.
- Whole frames can be skipped under a sustained producer/consumer rate
  mismatch once every safe bank role is occupied; partial frames are never
  displayed.

Phase 6B stops at this digital pixel/clock/control boundary.
