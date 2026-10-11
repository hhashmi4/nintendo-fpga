# Phase 6A HDMI, USB-C, and production hardware architecture

Date: 2026-10-11
Repository baseline: `0f23345`
Branch: `phase6/hdmi-usbc-architecture`

## Scope and decision language

This phase is an architecture and feasibility study. It adds no HDMI or
DisplayPort transmitter RTL, no production schematic or layout, and no
functional change to the CPU, PPU, APU, cartridge loader, VGA path, or Phase 5M
diagnostics. The machine-readable companion is
`config/phase6a_architecture.json`.

Every material statement uses one of these gates:

| Gate | Meaning |
|---|---|
| **CONFIRMED** | Measured in this repository or stated by a cited manufacturer specification. |
| **PROPOSED** | The recommended direction for a later phase; not implemented in Phase 6A. |
| **UNVERIFIED** | Evidence, implementation, procurement, or qualification is still missing. |
| **REQUIRES PHYSICAL TESTING** | Simulation and remote builds cannot establish the result. |

The principal decisions are:

1. **PROPOSED:** use a 24-bit parallel RGB external HDMI transmitter, with the
   Analog Devices ADV7513 as the first qualification candidate. Do not release
   a schematic until samples, authorized-channel volume pricing, complete
   programming material, and lifecycle are confirmed.
2. **PROPOSED:** make 1280x720p60 the initial HDMI mode. Present the full
   256x240 image in a centered 960x720 4:3 box by default and offer a centered
   768x720 exact-3x pixel mode.
3. **PROPOSED:** preserve VGA through the shared logical framebuffer and
   compositor, while permitting VGA and HDMI to have different timing/scaler
   instances.
4. **PROPOSED:** reuse the Phase 5K signed-16, 48 kHz PCM stream, duplicate mono
   into left and right I2S channels, and let the HDMI transmitter form HDMI
   Audio Sample Packets, InfoFrames, and audio-clock regeneration data.
5. **PROPOSED:** use a dedicated sink-only USB-C power receptacle and an
   autonomous PD controller. Prefer a 9 V/3 A contract, support a controlled
   5 V/3 A fallback only when CC advertises it, and size rails against a final
   vendor power estimate.
6. **UNVERIFIED:** keep USB-C DisplayPort Alt Mode optional and physically
   separate from the power inlet. The present 5CSEMA5 SE device has no HSSI
   transceivers and cannot directly implement a supported DP PHY.
7. **PROPOSED, conditional:** retain the Cyclone V SoC for the first custom
   prototype to minimize migration risk. Procurement, thermal, and cost gates
   must pass; AMD Zynq-7000 and Intel Agilex 5 SoC remain explicit alternatives.

## Repository and baseline evidence

### Repository gate

The Phase 6A work began with a clean tree on
`phase6/hdmi-usbc-architecture`. The first ten commits included `0f23345`, and
`origin` had fetch and push URLs configured. No work continued until those
conditions were true.

Installed tools used for the baseline were:

| Tool | Version |
|---|---|
| Python | 3.14.4 |
| pytest, repository `.venv` | 8.3.5 |
| Verilator | 5.032, 2025-01-01 Debian revision |
| Quartus Prime Shell / Timing Analyzer | 23.1std.1 Build 993, Lite Edition |
| Git | 2.53.0 |
| GitHub CLI | 2.46.0 |
| Icarus Verilog | Not installed; not required by the project flow |

### Baseline verification

`PATH="$PWD/.venv/bin:$PATH" ./scripts/test.sh` passed without changing test
behavior. It collected and passed 1,967 Python tests, then passed synthesizable
Verilator lint and the complete Phase 1 through Phase 5M RTL regression. The
Phase 5K directed/long-run audio test and the Phase 5M MMIO/CDC test also passed
when invoked independently. The diagnostics model compared seven independent
metrics. The playable regression completed 300 frames; its debugger run
completed 132 frames and 187 commands. Existing pixel comparisons reported no
mismatches.

The production build was `./scripts/build_de1_soc_nes_vga_quartus.sh`, not the
small platform-diagnostic build. It regenerated and checked the HPS system,
including the loader at `0xff200000` and diagnostics at `0xff201000`, then
completed Analysis & Synthesis, Fitter, Assembler, and all-corner timing.

| Production metric | Baseline result |
|---|---:|
| Device | 5CSEMA5F31C6 |
| Logic utilization | 9,613 / 32,070 ALMs (30%) |
| Combinational ALUTs used for logic | 12,931 |
| Total registers | 15,011 |
| Dedicated logic registers | 14,785 |
| M10K blocks | 275 / 397 (69%) |
| Block-memory bits | 2,238,504 / 4,065,280 (55%) |
| DSP blocks | 7 / 87 (8%) |
| PLLs | 2 / 6 (33%) |
| Pins | 226 / 457 (49%) |
| Worst setup slack | +0.729 ns |
| Worst hold slack | +0.077 ns |
| Worst TNS, every reported clock/corner | 0.000 ns |

Warning totals were 105 for Analysis & Synthesis, 149 for Fitter, zero for
Assembler, and 144 for Timing Analyzer. No message was labeled a critical
warning. The retained warnings include the unavailable LogicLock feature in
Lite Edition, incomplete-I/O-assignment notices, PLL compensation notices, and
unmatched/ignored generated HPS constraint filters. Phase 6A does not suppress
or waive them; production pinout and constraints need a warning-by-warning
closure review once a package and schematic exist.

A separate minimal `de1_soc_top` sanity build also passed, but its 43-ALM result
is not the production NES utilization and is deliberately excluded from the
production comparison.

## Existing architecture inventory

### NES and logical pixels — CONFIRMED

`rtl/nes_core.sv` emits a stall-safe logical pixel in the 50 MHz fabric domain:

- `pixel_valid`, one clock for each accepted logical pixel;
- `pixel_x[7:0]` and `pixel_y[7:0]`, covering 256x240;
- `pixel_palette_address[13:0]`;
- `pixel_nes_color[5:0]`;
- `pixel_color_emphasis[2:0]`;
- `pixel_source[1:0]`;
- separate PPU `frame_start` and `frame_end` events.

The core uses clock enables, not locally divided clocks. From the 50 MHz fabric
clock, the exact-average enable generator produces a 21.477272727 MHz NES
master rate, a 5.369318182 MHz PPU rate, and a 1.789772727 MHz CPU/APU-slot
rate while preserving the 3:1 PPU-to-CPU relationship.

### Current video path — CONFIRMED

The DE1-SoC top writes color plus emphasis into three 256x240x9 frame banks.
The logical storage is 1,658,880 bits and fits as 204 M10Ks. Writes occur in
the 50 MHz domain; a held-bank/toggle handshake publishes a complete bank to
the VGA domain. A 25.2 MHz PLL (`50 * 63 / 125`) drives an 800x525 timing
generator, producing exactly 640x480 at 60 Hz in the repository convention.

Normal VGA displays each 256x240 source pixel as 2x2, resulting in a 512x480
image and 64-pixel left/right borders. Developer Mode instead uses that
512-pixel game region plus a 128-pixel side panel. The palette converter emits
RGB888. The external DE1-SoC ADV7123 samples the 24-bit RGB bus on the exported
VGA clock, with negative horizontal and vertical sync.

This existing integer-scaled VGA presentation is 16:15 as a square-pixel
raster, not 4:3. Phase 6A does not relabel it. A future 4:3 HDMI presentation
therefore needs intentional horizontal resampling rather than merely copying
the VGA pixels.

### Audio path — CONFIRMED

The APU nonlinear mixer produces unsigned Q0.20 at the CPU/APU clock-enable
cadence. `nes_audio_resampler` applies the Phase 5K fixed-point filter and an
exact `352/13125` scheduler per APU tick, emitting signed 32-bit samples plus a
one-clock `sample_valid`. `nes_audio_conditioner` applies DC blocking, 0.75
gain, rounding, and saturation and emits signed 16-bit mono PCM plus a
one-clock `pcm_valid`.

A 32-entry, 16-bit Gray-pointer asynchronous FIFO crosses from 50 MHz into a
12 MHz PLL domain. The WM8731 serializer produces a 48 kHz LRCLK and an
average 3.072 MHz BCLK with two 32-bit slots; each signed 16-bit mono sample is
placed identically in left and right. The current I2S pins terminate at the
DE1-SoC codec. They are not HDMI packets.

### HPS, loader, and diagnostics — CONFIRMED

The generated Cyclone V HPS subsystem supplies a measured 97.368421 MHz user
clock and the lightweight HPS-to-FPGA bridge. The HPS owns DDR3, microSD,
boot/menu/game-library software, UART and other board peripherals. The loader
is a versioned, exactly-once CDC/MMIO endpoint at `0xff200000` with a 64-byte
span.

The Phase 5M diagnostic plane is an independent 50 MHz fabric subsystem at
`0xff201000` with a 512-byte span. It has atomic snapshots, clock heartbeats,
sticky faults, and a 16-entry trace. Its existing video and audio counters are
real observations; offline status explicitly reports physical VGA, codec,
clock, and HPS behavior as not tested.

### Current physical commitments — CONFIRMED

The fitted DE1-SoC image uses 226 of 457 package I/O pins. Explicit board I/O
includes 24 VGA data pins plus sync/clock/control, four audio-stream pins and
two codec-I2C pins, switches, LEDs and displays. HPS-dedicated or muxed pins
serve 32-bit DDR3, microSD, QSPI, Ethernet, USB ULPI, SPI, UART and two I2C
buses. A production board can omit many DE1-SoC user-interface peripherals,
but that does not make an arbitrary count of free pins usable: bank voltage,
clock capability, HPS mux, DDR placement, and package escape must be checked
against the exact package pin file.

The fitted device reports zero HSSI RX/TX PCS/PMA resources. The selected
Cyclone V SE part therefore has no native serial-transceiver lane available
for DisplayPort.

## Shared video architecture

### Logical organization — PROPOSED

```text
                         50 MHz NES domain
  NES PPU -> logical pixel contract -> triple framebuffer/publish CDC
                                      |
                                      v
                         shared palette/compositor policy
                                      |
                 +--------------------+--------------------+
                 |                    |                    |
          VGA timing/scaler    HDMI timing/scaler    DP timing/scaler
          25.2 MHz today       74.25 MHz initial     optional / unproven
                 |                    |                    |
             ADV7123 DAC       external HDMI Tx       DP MAC + PHY +
                                                     Type-C Alt Mode
```

“Shared” means one PPU contract, framebuffer publication protocol, palette,
Developer Mode/game-library composition rules, and scaler policy. It does not
require VGA and HDMI to share a pixel clock or timing generator. Forking a
single timed raster would prevent simultaneous 640x480 VGA and 720p HDMI, so
each enabled sink gets a mode-specific read/timing instance. A build that only
needs one mode may share the final scan stream directly.

The game library and boot UI should render into the same logical compositor as
gameplay and Developer Mode. No UI should bypass the common scan contract.
Overlay state must latch at a frame boundary so a frame never mixes modes.

### Synthesizable contracts — PROPOSED

These declarations specify a future contract; they are documentation, not new
RTL in Phase 6A. All signals are active high unless their names say otherwise.

```systemverilog
typedef enum logic [1:0] {
    VIDEO_MODE_VGA_640X480   = 2'd0,
    VIDEO_MODE_CTA_720P60    = 2'd1,
    VIDEO_MODE_CTA_1080P60   = 2'd2
} video_mode_id_t;

typedef enum logic [1:0] {
    SCALE_FULL_4X3           = 2'd0,
    SCALE_INTEGER_CENTERED   = 2'd1,
    SCALE_DEVELOPER_LAYOUT   = 2'd2
} video_scale_mode_t;

typedef struct packed {
    video_mode_id_t mode_id;
    logic [15:0] h_active;
    logic [15:0] h_total;
    logic [15:0] v_active;
    logic [15:0] v_total;
    logic        hsync_positive;
    logic        vsync_positive;
    logic [31:0] pixel_clock_hz;
} video_timing_metadata_t;

interface nes_pixel_if(input logic clk, input logic reset);
    logic        valid;
    logic        frame_start;
    logic        frame_end;
    logic [7:0]  x;
    logic [7:0]  y;
    logic [5:0]  nes_color;
    logic [2:0]  emphasis;
    logic [1:0]  source;
    modport producer(output valid, frame_start, frame_end, x, y,
                     nes_color, emphasis, source,
                     input clk, reset);
    modport consumer(input valid, frame_start, frame_end, x, y,
                     nes_color, emphasis, source, clk, reset);
endinterface

interface video_scan_if(input logic pixel_clk, input logic reset);
    logic [23:0] rgb;
    logic        data_enable;
    logic        hsync;
    logic        vsync;
    logic        line_start;
    logic        line_end;
    logic        frame_start;
    logic        frame_end;
    logic [15:0] x;
    logic [15:0] y;
    video_timing_metadata_t timing;
    modport source(output rgb, data_enable, hsync, vsync,
                   line_start, line_end, frame_start, frame_end,
                   x, y, timing,
                   input pixel_clk, reset);
    modport sink(input rgb, data_enable, hsync, vsync,
                 line_start, line_end, frame_start, frame_end,
                 x, y, timing, pixel_clk, reset);
endinterface

interface video_scale_control_if(input logic clk, input logic reset);
    logic                    request;
    video_mode_id_t          requested_mode;
    video_scale_mode_t       requested_scale;
    logic                    commit_at_next_frame;
    logic                    accepted;
    logic                    active;
    logic                    error;
    video_mode_id_t          active_mode;
    video_scale_mode_t       active_scale;
    modport controller(output request, requested_mode, requested_scale,
                       commit_at_next_frame,
                       input accepted, active, error,
                       active_mode, active_scale, clk, reset);
    modport scaler(input request, requested_mode, requested_scale,
                   commit_at_next_frame, clk, reset,
                   output accepted, active, error,
                   active_mode, active_scale);
endinterface
```

Contract rules:

- `nes_pixel_if.valid` is not backpressured; the consumer must accept each
  valid pixel or flag an overflow. Coordinates and metadata are valid only
  with `valid`. Frame events are one source-clock pulse.
- The framebuffer publish handshake, not an unsynchronized bank number, crosses
  clock domains. A published bank remains immutable until the destination
  releases it.
- `video_scan_if.rgb` is RGB888. `data_enable` identifies active video;
  RGB outside it is black. Sync polarity is described by the metadata and is
  not encoded by signal names.
- `x/y` count the complete raster from zero, including blanking. `line_start`
  and `frame_start` coincide with `(0,0)` conventions; `frame_end` identifies
  the final pixel clock of the complete raster.
- Timing metadata is constant from reset release until an accepted frame-boundary
  mode commit. A sink must never infer pixel frequency solely from `mode_id`.
- Each pixel-clock domain gets asynchronous reset assertion and synchronous
  deassertion. PLL lock must be synchronized and qualified before leaving black.
- A scaler-control request either commits atomically on a future frame or sets
  `error`; it cannot tear a frame.

### VGA compatibility — CONFIRMED and PROPOSED

The current 25.2 MHz VGA path remains the behavioral baseline and is not
modified by Phase 6A. A future refactor must prove its normal-mode and
Developer Mode output pixel-identical to current captures before it can replace
the path. If both VGA and HDMI are fitted, independent timing instances read a
common published frame. If production omits VGA, retain a test header or
compile-time diagnostic sink only if pin and cost budgets allow it.

## HDMI requirements and mode selection

### Required behavior — PROPOSED

The HDMI source must provide RGB digital video, two-channel 48 kHz LPCM,
Developer Mode, the HPS game library/boot display, hot-plug detection, EDID
read/validation, a safe fallback mode, and diagnostics. It must keep the output
muted/black during reset, unstable clocks, configuration, or mode changes.

At connection, firmware should debounce HPD, read base EDID and any required
extensions through the transmitter DDC engine, verify block checksums, select a
supported policy mode, configure video/audio/InfoFrames, then unmute on a frame
boundary. A disconnect immediately mutes output and invalidates the cached
EDID. EDID timeout, invalid header/checksum, no mutually supported mode,
I2C NACK/timeout, and transmitter interrupt are distinct errors. The fallback
is 640x480p59.94 only after policy allows operation without valid EDID; an EDID
failure is never silently reported as success.

HPD confirms an electrical sink indication. It does **not** confirm that a
monitor decoded pixels, selected this input, displayed an image, or played
audio.

### Pixel clocks and bandwidth — CONFIRMED calculations

The following standard timing totals are architecture inputs. RGB payload is
active pixels x refresh x 24 bits. Parallel-bus rate includes blanking. Each
HDMI 1.x TMDS data lane transmits ten serial bits per pixel clock; the clock
pair runs at the pixel clock for 8-bit color.

| Mode | Total timing | Pixel clock | Active RGB payload | 24-bit bus incl. blanking | TMDS per data lane | Aggregate 3-lane TMDS |
|---|---:|---:|---:|---:|---:|---:|
| 640x480p59.94 | 800x525 | 25.175 MHz | 0.442 Gb/s | 0.604 Gb/s | 0.25175 Gb/s | 0.75525 Gb/s |
| 1280x720p60 | 1650x750 | 74.25 MHz | 1.327 Gb/s | 1.782 Gb/s | 0.7425 Gb/s | 2.2275 Gb/s |
| 1920x1080p60 | 2200x1125 | 148.5 MHz | 2.986 Gb/s | 3.564 Gb/s | 1.485 Gb/s | 4.455 Gb/s |

Audio and data-island capacity is carried in horizontal/vertical blanking; it
does not add another external TMDS lane. Board signal integrity must
nevertheless qualify the full per-lane rate.

### Presentation choices

| Mode | Full-frame 4:3 presentation | Integer-pixel option | Consequence |
|---|---|---|---|
| 640x480 | 640x480, 2.5x H and 2x V | 512x480, 2x | Excellent debug fallback; 4:3 consumes the whole active area, while integer mode has 64-pixel side borders. |
| 1280x720 | 960x720, 3.75x H and 3x V | 768x720, 3x | Exact vertical scale, generous side bars, and a standards-native HDTV mode. |
| 1920x1080 | 1440x1080, 5.625x H and 4.5x V | 1024x960, 4x | Highest clock/resource/routing demand and no exact full-height integer scale. |

The default 720p 4:3 scaler should use deterministic nearest-neighbor rational
mapping and preserve all 240 lines. The exact-3x option is intentionally
pixel-square and 16:15; it is not mislabeled 4:3. Any future overscan crop or
an alternative historical NTSC pixel-aspect policy must be separately named
and tested.

### Recommendation

**PROPOSED:** start with 720p60. It is a common TV/monitor mode, permits an
exact 3x vertical scale of all NES lines, makes a clean 960x720 4:3 container,
and remains far below the 165 MHz ceiling of the preferred external
transmitter. Compared with 640x480 it improves current TV compatibility and
UI space. Compared with 1080p it halves the pixel clock, parallel-bus activity,
and TMDS lane rate, leaving materially more timing, power, and PCB margin.

Keep 640x480p59.94 as a diagnostic/EDID fallback. Treat 1080p60 as a later
mode that needs separate synthesis, power, memory-bandwidth, EDID, and physical
qualification; it is not required for the first product.

## HDMI transmitter options

### Comparison

| Attribute | A. External HDMI transmitter IC | B. FPGA-native TMDS | C. Vendor HDMI IP plus FPGA PHY |
|---|---|---|---|
| Candidate | ADV7513BSWZ first; ADV7511 or a qualified LT8618SX-class device as reselection candidates | Project-owned TMDS encoder, packet engine and serializer | Intel HDMI FPGA IP on a supported transceiver family |
| Video interface | RGB888 + clock, DE, HSYNC, VSYNC | Internal RGB/timing | Vendor streaming video interface into IP |
| Audio interface | I2S or S/PDIF; IC makes HDMI packets | Project must build packetizer, InfoFrames, ACR, scheduling | IP-specific audio/auxiliary interface |
| Verified ceiling | ADV7513: 165 MHz, formats through 1080p | Current SE GPIO/LVDS cannot claim compliant ceiling; 720p already needs 742.5 Mb/s/lane | Family/IP dependent; supported transceiver devices reach HDMI 2.x rates |
| Clocking | One pixel clock plus I2S clocks; IC owns TMDS PLL/serialization | Pixel, 5x DDR or 10x serialization clocks; tight phase/jitter budget | Reference clocks, transceiver PLLs and IP clock tree |
| FPGA I/O | About 24 data + 4 video control/clock + I2S + I2C/status; approximately 35-40 single-ended pins | Four high-speed differential pairs plus DDC/HPD/CEC; fewer pins but unsuitable electrical risk on this device | Four suitable high-speed lanes or family-specific PHY I/O plus DDC/HPD |
| External parts | IC, 1.8/3.3 V filtering, TMDS termination/reference parts, connector, DDC pull-ups/5 V, ESD | Connector, ESD, DDC/HPD level protection and any mandated bias/coupling network | Connector, ESD, reference clock, DDC/HPD protection; possibly redrivers |
| I2C / EDID / HPD | IC has I2C configuration, DDC EDID engine, 5 V-tolerant HPD and interrupts | Entire control/DDC behavior belongs to project RTL/firmware | IP/reference design dependent; software/register integration remains |
| PCB difficulty | Moderate: parallel bus locally, four short controlled-impedance pairs from IC to connector | High: high-speed pairs originate at BGA and electrical compliance is project risk | High: transceiver escape, reference clocks, lane constraints and SI |
| Availability / price | ADV7513 vendor status is RND; public spot stock/pricing is inconsistent. Budget $13-$25, obtain quote | No transmitter IC; higher FPGA, engineering, test, and compliance cost | Higher FPGA and licensed-IP/tool cost; exact quote required |
| Licensing/compliance | HDMI adopter/product compliance obligations remain; HDCP keys/license only if protected content is used | Same HDMI obligations plus self-designed implementation risk | HDMI obligations plus vendor IP production license and tool license |
| RTL integration | Low/medium: timing, I2S, I2C control/status | Very high: TMDS, guards/preambles/data islands, audio, EDID/DDC, CDC and PHY | Medium/high: vendor IP integration, transceiver resets, clocks and software |
| Simulation | Behavioral IC model around video/I2S/I2C plus configuration traces | Full protocol/encoder/packet verification and serializer checks | Vendor simulation model and reference testbench, plus project wrappers |
| Physical proof | Sink matrix, EDID/HPD, audio, eye/compliance, ESD/EMI/thermal | All preceding tests plus validating the custom PHY itself | Reference-board bring-up, transceiver tuning, eye/compliance and sink matrix |

### External transmitter evidence and limits

**CONFIRMED:** Analog Devices marks the ADV7513 “recommended for new designs.”
Its public data sheet specifies a 20-165 MHz input/TMDS clock, D[23:0], DE,
HSYNC, VSYNC and pixel clock; I2S and S/PDIF; an on-chip EDID/HDCP
microcontroller; interrupt reporting; and 5 V-tolerant DDC/HPD. It accepts
1.8-3.3 V video/audio logic and requires 1.8 V analog/digital/PLL supplies plus
a 3.3 V supply. Typical transmitter power is stated as 256 mW at 1.8 V plus
1 mW at 3.3 V for a 1080p random pattern. The public package is a 64-lead
10x10 mm exposed-pad LQFP, which substantially reduces assembly risk versus a
BGA bridge.

**UNVERIFIED:** public distributor views during this study disagreed on stock,
and ADI does not publish a 1,000-unit price on the product page. Some detailed
programming/reference material is distributed under NDA. “Recommended for new
designs” is useful lifecycle evidence, not a supply commitment. Purchasing
must obtain samples, a written authorized-channel quote/lead time, a PCN/PDN
path, and all programming documents before schematic freeze.

The ADV7511 provides more clock margin and ARC but uses a 100-lead package and
adds functions this console does not require. The LT8618SX product brief claims
24-bit RGB, I2S/S/PDIF, HDMI 1.4 and up to 4K30, but document/support and
authorized-channel evidence are weaker. Neither is declared a drop-in
alternative.

### Why native TMDS is not selected

At 720p60 the FPGA would need 742.5 Mb/s on each TMDS data lane; at 1080p60 it
would need 1.485 Gb/s. A fabric serializer would also need correct audio/data
island scheduling and HDMI control periods. The current fitted SE device has
no HSSI transmitters. Although other Cyclone V variants advertise high-speed
LVDS or transceivers, a general-purpose LVDS output is not automatically a
compliant HDMI TMDS current-mode PHY. No manufacturer reference design or
electrical compliance evidence was found for this exact device/package.
Consequently this route is **UNVERIFIED** and rejected for production risk,
even if a hobby implementation could show a picture.

### Why vendor IP is not selected on the current FPGA

The Intel HDMI IP device-support table lists Arria V, Arria 10, Cyclone 10 GX,
Stratix V/10 and Agilex families, but not Cyclone V. Its production use also
requires the applicable IP/tool license. Changing to a supported transceiver
device solely for HDMI would create a larger power, package, tool, and board
migration than placing a low-power external transmitter beside the connector.
Vendor IP remains a valid option only if a later FPGA selection is already
driven by DisplayPort or other transceiver requirements.

### Selected architecture and configuration ownership

**PROPOSED:** FPGA logic generates RGB888, timing, and stereo I2S. The HPS
configures the transmitter over I2C, services its interrupt, reads EDID through
its DDC engine, selects the allowed mode, and mirrors qualified status into
Phase 5M. Hardware gates video/audio mute on reset, PLL lock, transmitter
configuration, and FIFO health so delayed software cannot emit uncontrolled
output.

The external IC owns TMDS serialization, electrical drive, control/data
periods, guard bands, InfoFrames, Audio Sample Packets, and audio-clock
regeneration fields. The FPGA does not duplicate these functions. The exact
register script, chip/revision identification registers, lock bits, interrupt
polarity, and reserved-register requirements are **UNVERIFIED** pending the
complete programming guide and bench prototype.

## HDMI audio architecture

### Reused interface — CONFIRMED

The reusable boundary is the Phase 5K conditioner output:

```systemverilog
interface pcm_sample_if(input logic clk, input logic reset);
    logic               valid;
    logic signed [15:0] sample;
    logic [31:0]        generated_count;
    modport source(output valid, sample, generated_count,
                   input clk, reset);
    modport sink(input valid, sample, generated_count, clk, reset);
endinterface
```

`valid` is exactly one 50 MHz clock pulse per 48 kHz sample. `sample` is signed
two's-complement mono and is stable during that pulse. There is no ready signal;
every independently enabled physical sink must accept it or count an overrun.
The APU, resampler coefficients, conditioner, and sample rate do not change.

### Proposed transport

```text
 Phase 5K conditioner: signed PCM16 + valid at 48 kHz in 50 MHz domain
                              |
                 +------------+-------------+
                 |                          |
       existing WM8731 FIFO         HDMI 32+ entry async FIFO
                 |                          |
       existing 12 MHz I2S         HDMI I2S clock domain
                                            |
                                  duplicate mono L/R
                                  LRCLK = 48 kHz
                                  BCLK = 3.072 MHz
                                  2 x 32-bit slots
                                            |
                                      ADV7513 I2S
                                            |
                           HDMI audio packets + ACR + InfoFrame
```

Each physical sink receives its own FIFO. Sharing one read pointer would let a
stalled or absent sink corrupt the other. A minimum 32-sample FIFO preserves
the existing approximately 667 microsecond depth; the implemented depth must
be re-evaluated against transmitter startup and hot-plug behavior. Gray-coded
pointers, two-flop synchronizers, full/empty flags, and sticky overrun/underrun
counters follow the existing Phase 5K CDC pattern.

I2S carries sample words and clocks into the transmitter. It is **not** the
HDMI wire protocol. The transmitter must be configured for two-channel LPCM,
48 kHz, the chosen word/slot alignment, the correct channel-status fields and
Audio InfoFrame. It then inserts Audio Sample Packets during data islands and
generates the HDMI N/CTS audio-clock-regeneration information relative to the
pixel/TMDS clock. Whether N/CTS is fully automatic for every selected mode,
and its precise register programming, is an ADV7513 prototype gate.

Startup fills the FIFO to a threshold while muted, aligns the first left/right
frame, then unmutes at a video frame boundary. On HPD loss, clock loss,
configuration change, or sustained underflow, output returns to zero/mute and
the diagnostic counters remain monotonic. HDMI audio follows the exact 48 kHz
PCM producer; video mode changes alter transmitter ACR, not the NES resampler.

## USB-C power architecture

### Preliminary load estimate

No final current rating is selected from intuition alone. The baseline design
has a fitted netlist but no board-specific activity file, enclosure thermal
model, or production power tree. The table is therefore a conservative
architecture estimate, not an Intel Power Analyzer result.

| Load | Typical estimate | Peak/design estimate | Basis and uncertainty |
|---|---:|---:|---|
| Cyclone V FPGA fabric + dual-core HPS | 4.0 W | 6.0 W | Dominant unknown; must be replaced by an Early Power Estimator/Power Analyzer result with final clocks and activity. |
| 32-bit DDR3/DDR3L including termination | 1.1 W | 1.5 W | Density, speed, refresh, ODT and VTT topology not yet selected. |
| ADV7513 and HDMI support | 0.3 W | 0.45 W | Data sheet states about 257 mW typical at 1080p; allowance adds I/O, ESD and HDMI 5 V. |
| QSPI and microSD | 0.25 W | 0.8 W | microSD write/inrush peak is media-dependent. |
| Controllers, debug, status LEDs and low-speed I/O | 0.4 W | 0.7 W | Connector implementation and LED population are open. |
| Oscillators, reset, monitoring and level translation | 0.2 W | 0.3 W | Architecture allowance. |
| Conversion and distribution loss | 0.9 W | 1.5 W | Approximately 85-90% aggregate efficiency until a rail-by-rail design exists. |
| **Subtotal before margin** | **7.2 W** | **11.3 W** | Rounded architecture estimate. |
| **Design peak with 25% margin** | — | **14.1 W** | Does not include bus-powered accessories or an optional DP bridge. |

This budget permits a carefully controlled 5 V/3 A input but leaves little
connector, cable, transient, or future-expansion margin. It does not justify
running from a default-current USB source.

### Input options

| Input | Available power | Advantages | Limitations | Decision |
|---|---:|---|---|---|
| USB-C 5 V default current | As little as legacy USB default current; source-dependent | Simplest connector and buck ratios | Cannot run the console load reliably; the sink must obey the advertised CC current | Support only a low-power fault/standby path, not normal operation |
| USB-C 5 V at advertised 1.5 A | 7.5 W | No PD messages | Below the peak budget and near the typical estimate | Do not enable normal high-load rails |
| USB-C 5 V at advertised 3 A | 15 W | Common Type-C supply; no elevated VBUS | High input current and small peak margin; cable/drop losses matter | Controlled fallback after CC detection |
| USB PD 9 V/3 A | 27 W | Lower input current, good regulator headroom, common fixed PDO | Needs PD controller and 9 V-capable protection/converters | **Preferred contract** |
| USB PD 12 V/2 A or 3 A | 24-36 W | Further reduces input current | 12 V fixed PDO is less universal than 9 V; no load presently needs it | Optional accepted PDO, not required |

USB Type-C defines default, 1.5 A, and 3.0 A advertisements at 5 V. The sink
must monitor CC and stay within the advertised level. A passive pair of Rd
resistors establishes a sink attachment but does not promise 3 A. Normal boot
must therefore wait for a sufficient CC advertisement or a valid PD contract.

### Proposed power chain

```text
 Dedicated USB-C power receptacle (sink only)
       |
       +-- CC1/CC2 ESD/short protection --> STUSB4500 PD sink controller
       |                                      | I2C, ATTACH, POWER_OK, ALERT
       |                                      v
       +-- VBUS TVS --> fuse/eFuse + reverse/OVP switch --> input LC filter
                                                         |
                                         9 V preferred / 5 V fallback bus
                                                         |
            +-------------------+------------------------+----------------+
            |                   |                        |                |
       >=6 A core buck     3.3 V system buck       1.8 V buck/LDO     DDR rail/VTT
       FPGA/HPS 1.1 V      I/O, SD, control        HDMI/FPGA I/O      DDR3/DDR3L
            |                   |                        |                |
            +----------- sequenced enables / power-good / reset --------+
                                      |
                             supervisor -> HPS/FPGA reset
```

**PROPOSED:** STUSB4500QTR is the first power-controller candidate. ST lists it
active/in volume production. It is a standalone sink controller with dead-
battery startup, three configurable sink PDOs, NVM policy, I2C status, attach
and power-good outputs, VBUS monitoring, external switch control, and up to
20 V/5 A negotiation. It can bring up a known fixed policy without boot
firmware. It is not a DisplayPort Alt Mode controller and must not be reused as
one.

The preliminary PDO policy is 5 V as mandatory safe entry, 9 V/3 A preferred,
and an optional 12 V entry only if the final converters and source-compatibility
study justify it. NVM programming, cable detach, hard-reset behavior, discharge
timing, and every PDO transition need bench validation.

Required hardware protections are:

- a mechanically anchored, rated receptacle with shield bonding strategy;
- low-capacitance IEC ESD protection at CC and any exposed signal pins;
- a VBUS TVS selected for the maximum accepted PDO without nuisance clamp;
- input fuse or resettable fuse plus an eFuse/load switch providing adjustable
  current limit, inrush/slew control, reverse blocking and overvoltage cutoff;
- PD-controlled discharge and a bleeder whose ratings cover fault transitions;
- an input common-mode/differential filter selected after conducted-EMI tests;
- independent buck current limit and thermal shutdown;
- rail power-good into a supervisor, with reset held until vendor sequencing
  and ramp constraints are satisfied;
- test points or ADC-divided monitors for VBUS, 3.3 V, 1.8 V, core and DDR
  rails, with divider tolerance and ADC accuracy included in thresholds.

The provisional regulator floors are at least 6 A for the 1.1 V core rail,
4 A for 3.3 V, 2 A for 1.8 V, and 2 A plus the required source/sink capability
for DDR/VTT. These are **not selections**: the final Intel estimator, transient
simulation, efficiency/thermal derating, and rail sequencing may raise or
split them.

Attach detection, overvoltage/current protection, safe discharge, power-path
interlock, rail sequencing and reset are hardware-owned. HPS firmware may read
the PD contract, log faults, expose telemetry, request only prequalified PDOs,
and implement graceful shutdown. Firmware must not be the sole protection
against an excessive VBUS or an invalid startup sequence.

## USB-C DisplayPort Alternate Mode feasibility

### What a source actually requires

USB-C is only the connector. A video source must contain all of the following:

1. a DisplayPort source MAC that generates main-link packets and audio;
2. a compliant DP PHY with one, two, or four AC-coupled high-speed lanes;
3. AUX-channel transactions for DPCD/EDID and link training;
4. HPD handling, including interrupt pulses;
5. a USB-C/PD port controller that discovers the partner and cable, sends the
   structured VDM sequence, enters the DisplayPort SVID/mode, and selects a
   valid pin assignment;
6. orientation and lane-assignment muxing, with SBU routing for AUX and, if
   loss requires it, a qualified redriver;
7. VCONN and a legal source/sink/dual-role VBUS policy for the video port;
8. a full 24-pin receptacle, controlled-impedance pairs, ESD, return paths and
   a cable/monitor compliance matrix.

VESA states that DP Alt Mode repurposes some or all four SuperSpeed pairs,
places AUX/HPD functions on other Type-C signaling, and supports reversible
orientation. A USB-C connector or passive HDMI-to-USB-C cable alone provides
none of the DP source protocol, AUX channel, link training, or Alt Mode
negotiation. A monitor also needs a USB-C input that explicitly accepts DP Alt
Mode; power-only and data-only USB-C inputs are not substitutes.

### Architecture comparison

| Approach | Feasibility | Approximate cost | Complexity and risk |
|---|---|---:|---|
| A. FPGA with supported DP PHY/IP | Feasible after changing to a transceiver-capable device. Intel lists DP IP support for Cyclone V at RBR/HBR, but the current SE part has no HSSI lanes. Cyclone V SX/ST or a newer transceiver device would be needed. | FPGA/package and licensed IP can add tens to hundreds of dollars; quote required | High: FPGA migration, licensed MAC, PHY/reference clocks, link training, PD/VDM controller, mux, SI and VESA compliance |
| B. External DP transmitter | Conceptually feasible if a production part accepts this RGB/audio format and exposes a DP source with public support | Likely $15-$40 plus PD/mux, but **UNVERIFIED** | Medium/high. No part with sufficiently strong public lifecycle, documentation, authorized supply and integration evidence was qualified in this study. |
| C. HDMI-to-DisplayPort active conversion | Technically possible only with an active source-direction bridge that terminates HDMI, creates DP, trains the link and carries audio | Two transmitter/bridge stages plus PD/mux; likely highest BOM | Very high: scarce direction-specific bridges, two clock/protocol domains, latency, licensing, SI and opaque firmware. A passive adapter cannot work. |

Intel's family-wide DP support statement does not make the current package
capable. The fitted report's zero HSSI resources and the SE-versus-SX family
split are the controlling facts. A future Cyclone V SX study would still need
to check exact package transceiver count and HPS/DDR pin compatibility.

A Type-C mux such as TI's active HD3SS460 can route up to four DP 1.2a lanes
and AUX for either orientation, but it is only an analog mux. It supplies no
DP source or CC/PD state machine. TI now marks the formerly attractive
TPS65987D Alt Mode controller not recommended for new designs, illustrating
why the exact port controller must be reselected near implementation rather
than frozen here.

### Recommendation

**UNVERIFIED / optional:** do not route or populate USB-C video in the first
production prototype. Use a dedicated HDMI connector for the required output
and a separate sink-only USB-C connector for power. If a product case exists
for USB-C video, qualify it first on a development board with the exact DP
source, Type-C controller, mux, firmware, cables, and representative monitors.
Only then decide whether it belongs on the main PCB or a daughtercard.

Keeping the video connector separate is deliberate. Combining “console draws
power” and “console sources DP video” on one Type-C port creates a nontrivial
power/data-role policy and monitor-power interaction. That combined-port
product behavior is an unresolved decision, not an assumed feature.

## Production FPGA / SoC selection

Resource names are not directly comparable across vendors. Current ALM and
M10K utilization proves headroom only on the fitted Cyclone V target; it does
not predict LUT/BRAM packing elsewhere.

| Candidate | Relevant resources and processors | HDMI / DP | Package, power, tools, indicative price | Migration |
|---|---|---|---|---|
| Intel 5CSEMA5F31C6N, current Cyclone V SE | 32,070 ALMs, 4.065 Mbit M10K, 87 DSP, 6 PLL; dual Cortex-A9 HPS and hard DDR3 controller. Current design uses 30% ALMs, 55% bits/69% M10Ks, 8% DSP and 33% PLL. | External HDMI is straightforward. No HSSI in this SE device; direct DP is unavailable. | 896-ball FBGA, 28 nm, largest board/escape burden here. Quartus Lite 23.1 works. Public single-unit evidence was about $298-$328 and inconsistent in stock; volume RFQ required. | Lowest: current RTL, Qsys/HPS software, constraints and verification are established. Custom DDR/power/pinout remain major work. |
| Intel Cyclone V SX/ST | Similar generation with HPS and transceivers, exact density/package to select | Could use external HDMI; family DP IP supports RBR/HBR on suitable transceivers | Mature family, large BGA, transceiver power and licensed DP IP. Price/availability unverified. | Medium: fabric/HPS concepts are close, but not pin/package drop-in; redo Qsys, clocks, transceivers, power, constraints and board. |
| Intel Agilex 5 SoC E-series | 50K-656K LE family, substantially more memory/DSP options, A55/A76 HPS variants, DDR4/5/LPDDR and optional 17/28 Gb/s transceivers | External HDMI works; current HDMI/DP support depends on exact device/IP revision and was listed as staged/preliminary for some variants | Smaller modern packages exist, but Pro tools, modern DDR, more rails and quotation-only silicon/IP raise NRE. Unit price unverified. | High: core RTL should port, but HPS, boot, DDR, MMIO, PLL/RAM IP, constraints and software platform all change. |
| AMD XC7Z020 Zynq-7000 | 85K logic cells, 53,200 LUTs, 4.9 Mbit BRAM, 220 DSP; dual Cortex-A9 and hard DDR3 controller | External HDMI preferred. This Z-7020 has no suitable native DP path in the proposed architecture. | 400/484-ball packages simplify escape. Public single-unit listing was about $131 but showed no stock; Vivado/license and lifecycle quote required. | High: synthesizable NES logic is reusable, but every Intel PLL/RAM/Qsys/Avalon/HPS/boot/constraint boundary becomes AMD clocking/BRAM/AXI/PS work. |
| AMD Zynq UltraScale+ MPSoC | Device-dependent larger PL, DDR4 PS and faster transceivers; AMD documents a hardened PS DisplayPort controller on applicable MPSoCs | Strongest native DP option; external HDMI still possible | Higher silicon/tool/power/DDR complexity and BGA burden. Pricing is quote-dependent and likely disproportionate to an NES. | Very high, including 64-bit PS software/platform migration; only justified if USB-C DP becomes mandatory. |

### Recommendation and portability boundary

**PROPOSED:** use the current 5CSEMA5F31C6N for the first custom-board
prototype because all NES RTL, HPS loader/library, diagnostic MMIO and remote
timing evidence already target it. This is conditional, not a production
lifetime commitment. Before PCB authorization, obtain a volume quote and
lifecycle statement, run the final Intel power estimator, verify the precise
DDR topology and power sequencing, and demonstrate that the 896-ball escape is
economically manufacturable.

In parallel, run a synthesis-only XC7Z020 port as the cost/supply fallback.
Its nominal BRAM exceeds current used bits, but RAM aspect ratios and packing
must be proven. Agilex 5 is the strategic Intel migration study, not the first
cost-down target. Zynq UltraScale+ enters only if native DP is a hard product
requirement.

Portable code consists of the NES CPU/PPU/APU, bus, mapper, loader protocol,
diagnostic semantics, logical pixel interface, scaler math and PCM interface.
Platform-specific work includes PLLs, memory primitives/packing, HPS/PS and
DDR subsystems, Avalon-versus-AXI bridges, boot software/device tree, pin/bank
assignments, reset/power sequencing, and any vendor display PHY/IP. No family
or package is drop-in compatible.

## Conceptual production PCB

### Block diagram — PROPOSED

```text
                    +---------------- configuration QSPI
                    |
 USB-C power -> protection/PD -> sequenced regulators/power-good
                    |                       |
                    |                       v
                    |             +---------------------+
                    +------------>| Cyclone V SoC FPGA  |<-- JTAG/UART/debug
                                  |  FPGA fabric + HPS  |
        DDR3/DDR3L <------------->| hard DDR controller |
                                  +-----+------+--------+
                                        |      |
                                  HPS SDIO      +-- NES controller latch/clock/data
                                        |
                                     microSD

  NES pixel -> framebuffer/scaler -> RGB888/timing -> ADV7513 -> HDMI ESD -> HDMI
  PCM16/valid -> async FIFO/I2S ----------------------^             |
  HPS I2C/status <------------------------------------+        DDC/HPD/5 V

  Optional, not routed until qualified:
  scan/audio -> DP source MAC/PHY -> lane/AUX orientation mux -> USB-C video
                                  ^
                            Alt Mode PD controller
```

Required support includes configuration flash, vendor-required DDR reference
parts and termination, at least one qualified oscillator plus PLL references,
reset supervisor, temperature-aware regulators, ESD at every external
connector, HDMI 5 V current limiting, microSD card detect/protection, original
NES controller connectors or qualified panel harnesses, JTAG and recovery
UART, manufacturing test pads, and decoupling per each component guide.

### Mechanical and stack-up estimate

The planning envelope is approximately 120x90 mm, growing toward 140x100 mm if
full-size original controller connectors must mount directly on the board.
Connector and enclosure CAD, not the FPGA, will settle the outline.

An eight-layer controlled-impedance board is the initial cost/risk estimate:

1. signals/components and short high-speed escape;
2. solid ground;
3. controlled high-speed signals;
4. power;
5. power;
6. controlled signals/DDR;
7. solid ground;
8. signals/components.

That ordering is illustrative, **not a finalized stack-up**. A fabricator must
solve dielectric thickness, copper, 50-ohm single-ended and 100-ohm
differential geometry, via stubs and impedance coupons. The 896-ball FPGA plus
32-bit DDR is the primary escape risk. Whether eight layers can use ordinary
through vias or requires laser microvias/via-in-pad depends on the exact fanout,
DDR placement, BGA pitch and fabricator rules. It must be demonstrated before
costing.

HDMI pairs need short, continuous-reference, 100-ohm differential routing with
intra-pair matching, minimal vias/stubs and transmitter-to-connector placement.
The parallel RGB bus needs clock/data timing analysis and local length control,
but must not be over-constrained as if it were TMDS. DDR length, topology,
byte-lane/DQS matching and reference planes follow the selected FPGA memory
guide and memory data sheet. USB-C DP, if ever fitted, requires independent
5.4 Gb/s-or-faster insertion-loss, crosstalk and mux/redriver analysis.

Use multiple ground planes, local high-frequency decoupling, bulk capacitance
at load steps, broad low-voltage core pours or planes, and remote sense where
the chosen regulator permits it. Place the HDMI transmitter by the connector,
the DDR immediately at its dedicated HPS banks, and switching regulators away
from video clocks, TMDS, AUX and audio references.

Thermal design begins with regulator and FPGA junction estimates at worst-case
ambient. Provide exposed copper/thermal vias under the HDMI transmitter and
power devices, a heat-spreader/heatsink keep-out over the SoC, airflow paths in
the enclosure, and temperature telemetry. Passive operation is a goal, not a
Phase 6A claim.

## Preliminary BOM and cost

Prices are approximate USD engineering-quantity allowances observed or bounded
on 2026-10-11. They are not quotes, do not claim present stock, exclude tariff
and freight, and can change materially at production volume. Parts marked
“candidate” require schematic review and authorized-channel confirmation.

| Manufacturer / candidate part | Purpose / important specification | Approx. unit cost | Sourcing confidence | Alternative | Integration risk |
|---|---|---:|---|---|---|
| Altera/Intel `5CSEMA5F31C6N` | 85K-LE-class Cyclone V SE SoC, dual A9, 4.065 Mbit RAM, 896 FBGA | $298-$330 | Low/medium: supported family, but public stock/price was poor | AMD `XC7Z020-1CLG484C`; Cyclone V SX after study | Very high: cost, BGA, DDR, power and lifecycle dominate |
| ISSI `IS43TR16256BL-125KBL` x2, candidate | 4 Gb x16 DDR3L devices for a 32-bit, 1 GiB HPS memory | $6-$12 each | Medium; exact speed/geometry must match HPS design | Micron-compatible 4 Gb x16 part after FPGA qualification | High: topology, training and layout |
| Analog Devices `ADV7513BSWZ` | 165 MHz RGB/I2S HDMI transmitter, LQFP-64 | $13-$25 | Medium for lifecycle, low for public stock/quote | `ADV7511`; qualified LT8618SX-class bridge | Medium: documentation, I2C script, compliance |
| STMicroelectronics `STUSB4500QTR` | Autonomous sink-only PD controller, up to 20 V/5 A, NVM/I2C | $2-$6; ST showed $1.22 at 500 | High for active status; quote still required | Current certified sink controller with dead-battery mode | Medium: NVM policy, external power path |
| Texas Instruments `TPS25947` family, candidate | eFuse with inrush/current/OVP/reverse-path protection; exact suffix TBD | $2-$4 | Medium | ST or ADI eFuse meeting final PDO/current | Medium: ratings depend on 9/12 V policy |
| Texas Instruments `TPS543820`, candidate | 4-18 V, high-current synchronous core buck | $4-$8 | Medium | Qualified 6-8 A FPGA point-of-load converter | High: transient, sequencing, layout, thermal |
| Texas Instruments `TPS62130` family x2, candidate | 3 A synchronous secondary rails | $3-$5 each | Medium | ADI/Monolithic Power equivalents | Medium: exact rails/current pending power analysis |
| Texas Instruments `TPS51200`, candidate | DDR VTT termination regulator | $1-$3 | High | FPGA reference-design qualified VTT regulator | Medium: only after DDR topology is fixed |
| Winbond `W25Q128JVSIQ`, candidate | 128 Mbit QSPI boot/configuration storage | $2-$5 | High | Micron/Infineon pin-compatible device after boot test | Medium: HPS boot support and image size |
| Abracon `ASV-50.000MHZ-EJ-T`, candidate | 50 MHz low-jitter system oscillator | $1-$2 | High | Epson `SG-210STF` qualified frequency variant | Medium: jitter, voltage and temperature grade |
| Texas Instruments `TPS3808G01`, candidate | Programmable reset supervisor | $1-$3 | High | Supervisor matching final rails/delay | Low/medium |
| TI `TPD12S016` or discrete qualified arrays | HDMI ESD, DDC level shifting and 5 V support | $2-$5 | Medium; verify lifecycle and capacitance | Semtech low-capacitance arrays + separate switch | Medium: eye, IEC ESD, connector leakage |
| TI `TPD4S311`, candidate | USB-C CC/SBU short-to-VBUS and ESD protection | $1-$3 | Medium/high | ST USB-C port protection matching PD controller | Medium: coordinate with controller protection |
| Amphenol `10029449-111RLF`, candidate | Full-size HDMI Type A receptacle | $1-$3 | Medium/high | Molex/TE equivalent with same mechanical envelope | Low/medium: shell/retention/ESD placement |
| GCT `USB4105-GF-A`, candidate | USB-C receptacle for dedicated power input | $1-$3 | High | Amphenol/TE power-capable receptacle | Medium: shell strength and 5 A contact qualification |
| Molex `104031-0811`, candidate | Push-push microSD socket | $1-$3 | High | Amphenol/TE microSD socket | Medium: ESD and card-detect mechanics |
| Custom/qualified NES 7-pin connector x2 | Original controller compatibility | $5-$15 each | Low: long-term source not yet qualified | Panel connector plus internal harness | High: mechanical supply and mating durability |
| Passives, inductors, load switches, test/debug and misc. | Decoupling, feedback, filtering, HDMI 5 V, JTAG/UART, protection support | $25-$50 total | Medium | Selected with final schematic | Medium/high due to rail count and SI |

The resulting engineering-quantity component allowance is roughly $380-$510,
dominated by the publicly visible Cyclone V price. That is not a production
cost target. It excludes bare PCB fabrication, stencil, assembly, BGA X-ray,
AOI, programming, functional/compliance test fixtures, yield/rework, freight,
power adapter, controller connectors/harness labor, heatsink, fasteners and the
3D-printed or molded enclosure. A production RFQ may lower silicon pricing or
may invalidate the current FPGA choice entirely.

The optional USB-C DP function has no BOM value because no transmitter and Alt
Mode controller have passed the evidence gate. Assigning it a price now would
be false precision.

## Phase 5M diagnostic integration plan

The current 512-byte/version-1 register map remains unchanged in Phase 6A. A
future extension must either use reserved space with a capability/version bump
or define a second slave; old software must continue to reject unsupported
versions safely.

| Future status | Actual observation source | What it proves | What it does not prove |
|---|---|---|---|
| HDMI transmitter identity/revision | Successful I2C read of documented ID/revision, mirrored by firmware | A responding device at the expected address | Correct routing or displayed video |
| HDMI configuration status | Firmware state plus selected critical-register readback | Expected writes/readbacks completed | Analog link compliance or sink decode |
| HDMI hot plug | Debounced HPD pin/register | Sink asserts HPD electrically | Monitor is on the right input or shows an image |
| EDID status | DDC completion, header/extension checksums, parsed capability/mode | Specific bytes were read and accepted | Sink will render every advertised mode correctly |
| Video clock lock | Existing pixel PLL lock; transmitter lock only if documented status exists | Named PLL/status is asserted and clock heartbeat advances | Correct pixel contents or TMDS eye |
| HDMI audio sample count | PCM FIFO writes and I2S frame-accepted events | Samples reached the transmitter boundary | Sink decoded or played audio |
| Audio FIFO underruns/overruns | Hardware sticky counters | Transport starvation or backpressure occurred | Audible severity without correlation |
| USB-C attach/current state | PD controller ATTACH/CC status over pin/I2C | Cable/source attach and advertised current | Stable supply under full transient load |
| PD contract | Controller contract/PDO registers plus measured VBUS window | Negotiated PDO and plausible VBUS | Connector/cable temperature or full-load margin |
| USB-C Alt Mode | Future controller VDM/mode state | DP SVID/mode was entered | DP link trained or monitor displayed video |
| DP link status | Future DP MAC lane rate/count, training state and AUX errors | Link-training state and protocol errors | Image quality without sink/visual tests |
| Power-good rails | Regulator/eFuse PGOOD pins synchronized to fabric | Digital thresholds are presently satisfied | Exact voltage, ripple or transient margin |
| Rail voltage | External ADC plus calibrated dividers | Sampled rail lies in a defined window | High-frequency ripple beyond ADC bandwidth |
| Fault codes | Hardware-latched first/last faults and trace events | A defined internal condition occurred | Root cause unless underlying telemetry agrees |

New sticky faults should include transmitter absent/wrong ID, I2C timeout/NACK,
EDID timeout/invalid checksum/no supported mode, HPD drop while active, video
PLL loss, HDMI FIFO overrun/underrun, insufficient Type-C current, PD failure or
unexpected PDO, input/eFuse fault, rail PGOOD loss/ADC out of range, Alt Mode
entry failure, AUX timeout and DP link-training failure. Counters crossing from
pixel, I2S, PD interrupt, and monitor-ADC domains need the same atomic snapshot
and finite-bounded CDC discipline as Phase 5M.

## Verification plan for later phases

### Python reference verification

- Exhaust every source x/y mapping for 640x480, 720p and 1080p policies;
- prove active/blank/sync totals, polarities, frame rate, aspect box, black bars,
  full 256x240 coverage and no out-of-range framebuffer address;
- generate pixel-exact gameplay, boot menu, game library and all Developer Mode
  reference frames for 4:3 and integer modes;
- parse real and adversarial base/extension EDID blocks with checksum, timeout,
  duplicate and unsupported-mode cases;
- model HPD debounce/mode selection and configuration recovery;
- model PCM duplication, FIFO accounting, 48 kHz long-run count and I2S bits;
- model Type-C advertised-current policy and PD PDO selection/fallback;
- define expected diagnostic counters and every injected fault.

### RTL simulation

- Assert every `nes_pixel_if`, framebuffer publish and `video_scan_if` contract;
- compare complete output frames and timings under arbitrary clock phase/reset;
- stress frame-bank publication, mode commits, PLL loss, reset and hot plug;
- use a behavioral transmitter model for I2C register semantics, EDID memory,
  HPD/INT, video timing acceptance and I2S consumption;
- compare I2S slots/sample order and run enough time to establish exact average
  sample-rate stability; inject FIFO underflow/overflow and metastability-safe
  pointer delays;
- test missing transmitter, I2C NACK/timeout, corrupt EDID, disconnect/reconnect
  and interrupted configuration;
- model PD controller pins/registers and inject insufficient current, rejected
  PDO, VBUS transition timeout and power-good loss;
- if DP proceeds, use vendor models for AUX/DPCD, lane training, orientation,
  pin assignments and recovery at every supported lane count/rate.

An external-transmitter behavioral model validates the digital contract. It
does not model the HDMI analog eye, sink equalizer, cable, emissions or ESD.

### FPGA synthesis and timing

- compile VGA-only, HDMI-only and simultaneous VGA+HDMI configurations;
- constrain generated pixel/I2S clocks, parallel RGB output delay, I2C and every
  CDC; run all device corners and a CDC review;
- report mode-by-mode ALMs/ALUTs/registers/M10Ks/DSPs/PLLs/pins, setup, hold,
  TNS and every warning;
- validate exact pin bank voltages, clock-capable pins, simultaneous switching,
  package escape and power estimates before schematic freeze;
- for any new FPGA, synthesize the whole project rather than translating
  resource percentages on paper;
- for DP, compile licensed IP on the exact device/speed/package and close the
  transceiver reference-clock/reset constraints.

### PCB electrical and layout verification

- ERC for every supply pin, power-input state, sequencing enable, discharge,
  reset, pull-up, strap, DDC/HPD/CEC and unpowered-backfeed path;
- DRC against the chosen fabricator's BGA, microvia, annular-ring, impedance,
  creepage and assembly rules;
- pre-layout power-tree/load-step simulation and DDR/parallel-video timing;
- pre- and post-layout HDMI/DDR SI with vendor IBIS models, stack-up insertion
  loss, return paths, crosstalk, via stubs and connector models;
- optional DP loss/eye/AUX/mux analysis at the selected link rate;
- power-distribution impedance/ripple analysis and a worst-case thermal model;
- independent schematic/layout review against FPGA, DDR, ADV7513, USB-C and PD
  reference designs.

### Physical verification — REQUIRES PHYSICAL TESTING

- power-only startup with electronic loads, every advertised current and PDO,
  wrong/weak cables, hot plug, brownout, short, OVP/OCP and thermal fault;
- measure every rail's ramp, sequencing, ripple, load transient, efficiency,
  inrush and shutdown discharge at temperature;
- HDMI transmitter ID/configuration, HPD, EDID and reconnect across a matrix of
  TVs, monitors, receivers, capture devices and cable lengths;
- confirm 4:3 geometry, integer mode, Developer Mode and game-library display;
- confirm 48 kHz LPCM enumeration, channel duplication, long-run A/V behavior,
  silence/mute and audible underrun recovery;
- HDMI eye/compliance pre-test, DDC/HPD levels, ESD, conducted/radiated EMI and
  enclosure thermal soak;
- if enabled, Type-C orientation, every DP pin assignment/lane count, AUX/HPD,
  link training, cable types, monitors and DP compliance;
- original controller connector electrical/mechanical endurance, microSD hot
  insertion/removal policy, JTAG recovery and manufacturing test coverage.

Remote simulation and synthesis cannot prove that a display shows an image,
that a speaker plays clean audio, that USB-C negotiates with real chargers,
that a TMDS/DP eye passes, that DDR trains on a custom board, or that the
enclosure is electrically, thermally or mechanically safe.

## Risks, unresolved decisions, and gates

| Risk / decision | Present state | Gate before commitment |
|---|---|---|
| ADV7513 supply and complete docs | Vendor RND status confirmed; public supply evidence inconsistent | Authorized quote, samples, programming material, reference schematic and prototype |
| HDMI legal/compliance | Obligations exist; exact company/product plan absent | HDMI adopter/trademark/compliance review; decide explicitly that HDCP is unnecessary for original unprotected content |
| 720p PLL and parallel timing | Numerically feasible; not implemented | New PLL/scaler synthesis and external-transmitter timing closure |
| 4:3 resampling policy | Full-frame 960x720 proposed | Approve pixel mapping and compare on representative displays |
| FPGA lifetime and cost | Existing design fits; engineering price is high | Volume RFQ/lifecycle and costed alternative port |
| Power and cooling | 14.1 W design estimate only | Final activity-based power analysis, rail transient/thermal design and measurements |
| DDR device/topology | Conceptual two-x16 DDR3L | Vendor memory-interface validation and PCB timing/SI |
| Eight-layer stack-up | Plausible concept | Fabricator escape study and impedance/DDR review |
| Original controller connectors | Function defined; supply/mechanics weak | Qualified source or panel-harness design and endurance test |
| USB-C combined power/video port | Separate ports recommended | Product decision plus legal Type-C role/PD architecture if combined |
| USB-C DP | No qualified transmitter/controller; current FPGA lacks PHY | Business case, exact parts/dev kit, licensed IP, prototype and compliance plan |
| Physical validation | DE1-SoC unavailable | Hardware access; do not convert `NOT TESTED` into inferred PASS |

## Recommended next phases

These are proposals, not Phase 6A implementation:

1. **Phase 6B candidate qualification:** obtain ADV7513 documentation/samples,
   build a small transmitter prototype or supported evaluation setup, and
   verify 720p60 RGB + 48 kHz I2S + HPD/EDID on physical sinks.
2. **Shared-video refactor:** introduce the documented interfaces while proving
   existing VGA output pixel-identical, then add a standalone 720p timing/scaler
   with Python/RTL comparison. This should remain separate from transmitter RTL.
3. **HDMI integration:** add transmitter configuration/EDID firmware, HDMI
   audio FIFO/I2S, diagnostics and full regression after the IC gate passes.
4. **Power proof:** complete vendor power estimates, PD/eFuse/regulator
   prototype, sequencing and fault tests before a production schematic.
5. **FPGA/PCB gate:** get Cyclone V and Zynq quotations, run the alternative
   synthesis study, select exact memory/package, and complete preliminary
   escape/SI/thermal reviews.
6. **Optional DP discovery:** only after HDMI is physically stable, prototype a
   complete DP source + Alt Mode controller + mux path and decide whether the
   feature warrants its cost and migration risk.
7. **Production schematic/layout:** begin only after the preceding component,
   power, FPGA and compliance gates close.

## Evidence register

Manufacturer and standards-owner sources used for specifications:

- [Analog Devices ADV7513 product page and lifecycle](https://www.analog.com/en/products/adv7513.html)
- [Analog Devices ADV7513 data sheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ADV7513.pdf)
- [Analog Devices AN-1270 FPGA/ADV751x video-generator configuration](https://www.analog.com/en/resources/app-notes/an-1270.html)
- [Analog Devices ADV7511 product page](https://www.analog.com/en/products/adv7511.html)
- [Altera Cyclone V family overview](https://www.altera.com/products/fpga/cyclone/v)
- [Altera Cyclone V device overview](https://docs.altera.com/r/docs/683694/current/cyclone-v-device-overview)
- [Intel HDMI FPGA IP device-support/licensing guide](https://cdrdv2-public.intel.com/772809/ug_hdmi-683798-772809.pdf)
- [Altera DisplayPort IP Cyclone V hardware-design example](https://docs.altera.com/r/docs/683273/25.1/displayport-ip-user-guide/displayport-ip-hardware-design-examples-for-arria-v-cyclone-v-and-stratix-v-devices)
- [Intel Agilex 5 FPGA and SoC overview](https://www.intel.com/content/www/us/en/products/details/fpga/agilex/5.html)
- [AMD Zynq-7000 product and resource table](https://www.amd.com/en/products/adaptive-socs-and-fpgas/soc/zynq-7000.html)
- [AMD Zynq-7000 selection guide](https://www.amd.com/content/dam/xilinx/support/documents/selection-guides/zynq-7000-product-selection-guide.pdf)
- [AMD Zynq UltraScale+ hardened DisplayPort interface](https://docs.amd.com/r/en-US/ug1449-multimedia/DisplayPort-Interface)
- [STMicroelectronics STUSB4500 product status](https://www.st.com/en/interfaces-and-transceivers/stusb4500.html)
- [STMicroelectronics STUSB4500 data sheet](https://www.st.com/resource/en/datasheet/stusb4500.pdf)
- [USB-IF USB Type-C specification, revision 2.0](https://www.usb.org/sites/default/files/USB%20Type-C%20Spec%20R2.0%20-%20August%202019.pdf)
- [VESA DisplayPort Alt Mode announcement and signal overview](https://vesa.org/featured-articles/vesa-brings-displayport-to-new-usb-type-c-connector/)
- [VESA DisplayPort Alt Mode technical overview](https://www.vesa.org/wp-content/uploads/2014/09/DP-Alt-Mode-Overview-for-VESA-v1.pdf)
- [TI HD3SS460 active product page and DP 1.2a mux specification](https://www.ti.com/product/HD3SS460)
- [TI TPS65987D lifecycle and Alt Mode capability](https://www.ti.com/product/TPS65987D)
- [Lontium LT8618SX product brief](https://www.lontiumsemi.com/UploadFiles/2021-03/LT8618SX%20Product%20Brief.pdf)

Public price observations were cross-checks, not stock guarantees:

- [DigiKey XC7Z020 listings](https://www.digikey.com/en/products/filter/embedded-system-on-chip-soc/777?s=N4IgjCBcoLQdIDGUBmBDANgZwKYBoQB7KAbXACZyQBdAXwJioWUgBcAnAV3yNJAE4ateiCZkAGgGEA7AC0ADOXlCgA)
- [ST direct STUSB4500 ordering page](https://estore.st.com/en/products/interfaces-and-transceivers/usb/usb-type-c-and-power-delivery-controllers/stusb4500.html)

When an official source and a distributor view differ, the official electrical
and lifecycle specification controls while procurement remains **UNVERIFIED**.

## Phase boundary

Phase 6A ends with this document and its machine-readable decision record. No
HDMI transmitter RTL, DisplayPort transmitter RTL, new scaler/timing RTL,
production schematic, PCB layout, or CPU/PPU/APU/loader functional change is
part of this phase.
