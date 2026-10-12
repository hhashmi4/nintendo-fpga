# Phase 6C — HDMI transmitter interface, control, and verification

## Scope and completion status

Phase 6C connects the Phase 6B 720p RGB888 stream to a logical external-HDMI-
transmitter boundary. It implements pixel/sync alignment, transmitter control,
open-drain I2C, HPD filtering, buffered EDID validation, fail-closed startup and
recovery, and a versioned diagnostic extension. It does not implement TMDS in
the FPGA.

The RTL and its independent models are simulation-qualified. The ADV7513 is a
qualification candidate, not an approved production component. The stock
DE1-SoC has no ADV7513, HDMI connector, or routed RGB/DDC/HPD interface, and the
board is unavailable. No physical HDMI claim is made.

Phase 6D audio, USB-C DisplayPort, schematic capture, production PCB design,
and NES CPU/PPU/APU/game-loading changes are outside this phase.

## Official source set

The implementation was checked against these manufacturer sources:

- [ADV7513 Rev. B data sheet](https://www.analog.com/media/en/technical-documentation/data-sheets/adv7513.pdf)
- [ADV7513 Hardware User's Guide, Rev. 0](https://www.analog.com/media/en/technical-documentation/user-guides/ADV7513_Hardware_User_Guide.pdf)
- [ADV7513 Programming Guide, Rev. B](https://www.analog.com/media/en/technical-documentation/user-guides/ADV7513_Programming_Guide.pdf)
- [ADV7513 product page](https://www.analog.com/en/products/adv7513.html)
- [ADI ADV7513 design-support and evaluation-board files](https://ez.analog.com/video/a/documents/c/adv7513-faq/DO8985/adv7513-design-support-files)

The data sheet is the electrical and pin-level authority. The hardware guide
defines supplies, strapping, layout and application behavior. The programming
guide is the authority for register maps and programming tasks. Evaluation-
board material is a physical-design reference only; it is not copied as a new
board design here.

## Qualification boundary

### Confirmed from manufacturer documentation

- ADV7513 accepts 24-bit RGB/YCbCr video, separate `CLK`, `HSYNC`, `VSYNC`,
  and `DE`, with 1.8 V through 3.3 V video logic levels.
- Its input-video clock limit is 165 MHz and it supports formats through
  1080p; 74.25 MHz 720p is within the published range.
- Input video setup and hold requirements are 1.8 ns and 1.3 ns. I2C supports
  up to 400 kHz and requires open-drain wiring with external pull-ups.
- `SDA`, `SCL`, and `HPD` tolerate 5 V; that does not make the FPGA pins or an
  unqualified carrier 5-V tolerant.
- The required rails are 1.8 V `DVDD`, `AVDD`, `PVDD`, and `BGVDD`, plus 3.3 V
  `DVDD_3V`. Their sequencing, filtering, decoupling, thermal and layout rules
  remain carrier responsibilities.
- Pulling `PD/AD` low during address sampling selects 8-bit main-map address
  `0x72` (7-bit `0x39`) and makes the power-down input active high. Software
  must wait 200 ms after supplies become valid before the first I2C access.
- The default EDID-memory address is 8-bit `0x7e` (7-bit `0x3f`). The internal
  DDC master reads 256 bytes after HPD/power-up; main register `0x96[2]`
  indicates completion and the host reads the buffered EDID map.
- `0x42[6]` reports HPD, although this implementation uses the directly routed
  HPD input for deterministic disconnect response.
- The programming guide documents the mandatory fixed writes, input-format,
  VIC, HDMI/DVI, packet-update, power, and InfoFrame fields used below.

### Proposed design choices

- Strap for main address `0x72`, use the default EDID map at `0x7e`, and run
  the FPGA master at 100 kHz.
- Use RGB 4:4:4 Input ID 0: `rgb[23:16] = R`, `rgb[15:8] = G`, and
  `rgb[7:0] = B` with separate positive syncs and DE.
- Launch Phase 6B outputs on the pixel-clock rising edge and forward an
  inverted pixel clock. The candidate captures on the forwarded rising edge,
  half a 74.25 MHz period after launch.
- Budget the external source-synchronous path for the 1.8 ns setup and 1.3 ns
  hold requirements plus a provisional 1 ns carrier-skew allowance.
- Require 5 ms of continuous HPD level before either connect or disconnect is
  accepted. HPD is presence intent, never proof of a displayed image.
- Advertise and accept only CTA VIC 4 / exact 720p60 in this phase.

### Unverified and requiring physical testing

- ADV7513 lot/revision behavior, component availability, production lifetime,
  power integrity, thermal behavior, I/O voltage compatibility and reset
  behavior on a real carrier.
- RGB clock/data package and board skew, signal integrity, emissions, TMDS
  routing, connector/ESD behavior, DDC pull-ups and level compatibility.
- The complete 24-entry profile against physical silicon and diverse sinks,
  including AVI InfoFrame interpretation and power-down/reconnect behavior.
- EDID/HPD interoperability, cable faults, clock stretching and stuck-bus
  recovery with real TVs, monitors, adapters and capture devices.
- HDMI compliance, HDCP, CEC and audio. HDCP is explicitly disabled; CEC and
  audio are not configured.

## Digital RGB interface and 720p timing

`hdmi_rgb_output.sv` presents:

| Signal | Meaning |
|---|---|
| `tx_pixel_clock` | Inverted 74.25 MHz forwarded clock |
| `tx_rgb[23:0]` | RGB888, black outside enabled active video |
| `tx_hsync`, `tx_vsync` | Positive syncs from the registered Phase 6B stream |
| `tx_data_enable` | Active-high pixel qualification |
| `tx_frame_start` | One pixel at active coordinate `(0,0)`, for local logic |
| `frame_toggle` | One control-domain CDC event per enabled frame |

The adapter does not infer alignment from a shared clock. Phase 6B already
registers RGB, sync and DE together. The adapter preserves those values and
places the transmitter capture edge half a cycle later. Its enable crosses
through a two-flop pixel-domain synchronizer. Disable forces DE low and RGB
black; sync continues so the timing generator is never disturbed.

The sole implemented mode is:

| Quantity | Horizontal | Vertical |
|---|---:|---:|
| Active | 1280 | 720 |
| Front porch | 110 | 5 |
| Positive sync | 40 | 5 |
| Back porch | 220 | 20 |
| Total | 1650 | 750 |

At 74.25 MHz this is 1,237,500 pixels/frame, 45 kHz line rate, and exactly
60 frames/s nominal. Phase 6B's centered 960x720 4:3 canvas and 160-pixel black
pillars remain unchanged. No 480p or 1080p mode is advertised.

## I2C transport

`i2c_register_master.sv` is transmitter-neutral and accepts one-byte register
read or write commands. It implements START, STOP, seven-bit addressing,
register address, ACK/NACK, write data, repeated START, one-byte read and the
master's final NACK. `SCL` and `SDA` outputs are low-enable signals only; no RTL
signal can drive either wire high. A carrier wrapper must instantiate true
open-drain I/O buffers and pull-ups.

Both input wires pass through two-stage synchronizers before the FSM observes
slave ACK/data or clock stretching. Released-SCL phases pause while the sampled
line is low. The default stretch limit is 50,000 control cycles (1 ms). A busy
SDA at command start generates as many as nine SCL recovery pulses followed by
a STOP. An unreleased line returns a typed timeout rather than hanging.

## ADV7513 configuration

The register table is isolated in `adv7513_720p_profile.sv`; the reusable
transport has no part-specific values. Every update is read/modify/write so
reserved bits are preserved. A separate pass reads the final values back. A
transaction receives the initial attempt plus at most two retries.

The video-only qualification profile is:

| Order | Register | Mask | Value | Purpose |
|---:|---:|---:|---:|---|
| 0 | `41` | `40` | `00` | Clear main software power-down |
| 1–8 | `98,9a,9c,9d,a2,a3,e0,f9` | documented | `03,e0,30,01,a4,a4,d0,00` | Required fixed settings |
| 9 | `0b` | `80` | `00` | Disable S/PDIF |
| 10 | `0c` | `3c` | `00` | Disable I2S channels |
| 11 | `15` | `0f` | `00` | Input ID 0, RGB 4:4:4 |
| 12 | `16` | `c1` | `00` | RGB/full-range/no input style 2 |
| 13 | `17` | `62` | `02` | Positive separate syncs and aspect field |
| 14 | `18` | `80` | `00` | Disable color-space conversion |
| 15 | `3b` | `7e` | `40` | Manual pixel repetition, x1 |
| 16 | `3c` | `3f` | `04` | Manual CTA VIC 4 |
| 17 | `af` | `82` | `02` | HDMI mode, HDCP disabled |
| 18 | `4a` | `c0` | `c0` | Begin atomic AVI packet update |
| 19–21 | `55,56,57` | `7f,ff,0f` | `11,a9,00` | RGB/BT.709/16:9 raster, centered 4:3 active image |
| 22 | `44` | `10` | `10` | Enable AVI InfoFrame |
| 23 | `4a` | `c0` | `80` | Commit atomic AVI packet update |

Entry 18 is intentionally excluded from final readback because entry 23
changes the same packet-update field. The other masked fields are verified.
The configuration is backed by official documentation, but remains a
non-production qualification profile until physical readback and sink testing
pass. It contains no Phase 6D audio configuration.

The selected active-high `HDMI_PD` behavior is tied to the `0x72` strap. It is
held low while the address is sampled, can assert while waiting for HPD, and is
deasserted for configure/verify/EDID. A terminal fault asserts it and also
gates FPGA video. A future carrier must guarantee the low strap during the
documented 200 ms address-decision interval.

## HPD, EDID, startup and recovery

`hdmi_hpd_filter.sv` synchronizes HPD and reports four observable states:
unplugged, connect-debounce, stable-connected and disconnect-debounce. Bounce
does not change the stable output. A qualified disconnect removes video before
recovery begins.

`adv7513_edid_reader.sv` polls `0x96[2]`, then reads the internally buffered
base block and the first extension through the EDID map. The FPGA does not
drive the HDMI connector DDC wires directly. `edid_720p_validator.sv` requires
the eight-byte EDID header, a zero base checksum, and—when declared—the first
extension with a zero checksum and CTA tag. It recognizes exact 720p timing in
a base-block detailed timing descriptor or CTA short video descriptor VIC 4.
Absent, short, malformed, checksum-failing, and unsupported EDIDs fail closed.
Only the first extension is consumed in Phase 6C.

The controller uses the requested deterministic state sequence:

`RESET → WAIT_CLOCK → WAIT_HPD → CONFIGURE → VERIFY_CONFIG →`
`CHECK_DISPLAY_CAPABILITY → ENABLE_VIDEO → RUNNING`

The default time policy is 200 ms before the first I2C access, 1 s to acquire
pixel lock, 5 s for HPD, 1 ms per EDID-ready poll, a bounded 256 polls, 100 ms
between recovery attempts, and at most three controller recovery attempts.
Clock loss, disconnect, transport failure, bad readback, or unusable EDID gates
video. Recovery restarts from clock qualification; a terminal failure waits
for a new qualified connection. A disconnect blocks new I2C commands
immediately, lets an in-flight transaction reach STOP, and clears each
sub-engine before the next qualification attempt.

## Diagnostics and stable fault codes

The existing 512-byte Phase 5M aperture is unchanged. Interface version 1.1
appends these registers:

| Offset | Name | Meaning |
|---:|---|---|
| `0x0f8` | `HDMI_STATUS` | bits 0 present, 1 configured, 2 fault, 4:3 HPD state, 5 EDID valid, 6 mode supported, 7 clock locked, 8 enabled, 12:9 startup state |
| `0x0fc` | `HDMI_VIDEO_FRAMES` | synchronized enabled-frame events |
| `0x100` | `HDMI_I2C_NACKS` | completed transactions reporting NACK |
| `0x104` | `HDMI_I2C_TIMEOUTS` | completed transport timeouts |
| `0x108` | `HDMI_RECOVERIES` | bus and startup recovery actions |
| `0x10c` | `HDMI_LAST_ERROR` | HDMI-local stable error code |

The capability and availability masks add `HDMI_TX` bits without moving old
fields or changing the loader aperture. Values enter the existing bundled
snapshot mailbox atomically. The Phase 6C controller has already synchronized
its pixel-domain inputs before diagnostic capture. The production DE1-SoC top
ties this bank to the truthful disconnected/zero state because no transmitter
is physically present.

`HDMI_LAST_ERROR` uses a separate namespace so the earlier ten sticky system
fault bits remain stable:

| Code | Name |
|---:|---|
| 1 | `HDMI_TX_NOT_DETECTED` |
| 2 | `HDMI_TX_I2C_NACK` |
| 3 | `HDMI_TX_I2C_TIMEOUT` |
| 4 | `HDMI_HPD_TIMEOUT` |
| 5 | `HDMI_EDID_INVALID` |
| 6 | `HDMI_MODE_UNSUPPORTED` |
| 7 | `HDMI_PIXEL_CLOCK_UNLOCKED` |
| 8 | `HDMI_CONFIG_VERIFY_FAILED` |
| 9 | `HDMI_RECOVERY_FAILED` |

Only observable digital conditions produce these codes. No link quality,
display success, voltage, current, temperature or signal-integrity measurement
is inferred.

## Verification

`verification/hdmi_transmitter.py` independently models protocol events,
masked profile application, HPD candidate duration, EDID structure/timings,
startup recovery, RGB qualification and raster measurements. It works at
transaction and structure level rather than translating RTL state-by-state.

The retained and new tests cover:

- exact 720p pixel/line/frame, HSYNC, VSYNC and DE boundaries;
- ten complete transmitter frames, normal and Developer layouts, exact black
  pillars, RGB/sync tuple alignment, frame toggles and safe disable;
- I2C START/STOP, all ACKs, address NACK, repeated START/read/master NACK,
  stretching timeout, open-drain behavior and stuck-bus recovery;
- 24-entry ordered configuration, reserved-bit preservation, distinct
  readback, mismatch, NACK/timeout retries and transmitter-not-detected mapping;
- HPD connect, disconnect, bounce, reconnect and reset while running;
- valid CTA EDID, invalid header/base/extension checksum, base DTD, unsupported
  mode and unavailable transport;
- complete startup, missing pixel clock, configuration/EDID faults, recovery
  limit and fail-closed behavior;
- diagnostic MMIO/CDC snapshots and software decoding;
- complete retained CPU, PPU, APU, audio, DMA, controller, cartridge, loader,
  microSD, VGA, Developer Mode, debugger, playable-ROM and Phase 6B suites.

The final full run passed **2,013 Python tests**, complete Verilator lint, and
every retained RTL/system simulation. The 300-frame playable run observed 297
NMI, DMA, and controller events; the retained Developer Mode VGA run completed
83 exact frames; and the debugger long run completed 132 frames and 187
commands. No existing test was weakened.

The compact RTL artifacts are checked against independent Python calculations:
ten exact 1,237,500-pixel frames, 921,600 active pixels/frame, 30,000 HSYNC
pixels/frame, 8,250 VSYNC pixels/frame, 230,400 pillar pixels/frame, 24 profile
writes, 256 EDID bytes, three synchronized frame events and three bounded NACK
attempts. The Phase 4D-B 300-frame playable regression remains the longer
whole-system VGA stability test.

## Quartus qualification

The standalone `phase6c_hdmi` project fits the complete shared-video pipeline
and logical transmitter control into `5CSEMA5F31C6`. All HDMI boundary signals
are virtual. Only the real 50 MHz clock and reset pins are assigned, so the SOF
is a synthesis/timing artifact rather than a usable HDMI board image.

| Resource/timing | Phase 6B | Phase 6C logical interface |
|---|---:|---:|
| ALMs | 267 | 1,958 |
| Combinational ALUTs | 391 | 2,452 |
| Registers | 183 | 2,975 |
| M10Ks / bits | 204 / 1,658,880 | 204 / 1,658,880 |
| DSP blocks | 3 | 3 |
| PLLs | 1 | 1 |
| Worst setup slack | +0.394 ns | +0.988 ns |
| Worst hold slack, all corners | +0.118 ns | +0.123 ns |
| Setup/hold TNS | 0 / 0 ns | 0 / 0 ns |
| Unconstrained setup/hold paths | 0 / 0 | 0 / 0 |

The Phase 6C critical setup path is the source-synchronous Phase 6B
`output_active` register to `HDMI_RGB[16]` virtual output path; the
forwarded-clock constraint includes its output route. At the slow 85 C corner,
the critical hold path is a retained Phase 6B framebuffer address register in
the 50 MHz domain (+0.224 ns). The all-corners hold minimum is the same 50 MHz
domain at the fast 0 C corner (+0.123 ns); the HDMI capture interface itself
has +4.655 ns hold slack there.

Expected warnings are the Lite-edition LogicLock notice, automatic PLL
compensation notice, the timing-driven-synthesis initialization notice for the
virtual-boundary project, and constant high bits of the eight-bit error output
(defined codes currently require only four bits). There are no latch,
multiple-driver, unconstrained-path or timing-failure warnings.

The production `de1_soc_nes_vga` build remains the hardware image and retains
its existing VGA pinout. It has no invented HDMI locations. Its final results
against the pre-change baseline are:

| Production resource/timing | Baseline | Phase 6C tree | Delta |
|---|---:|---:|---:|
| ALMs | 9,586 | 9,629 | +43 |
| Combinational ALUTs | 12,947 | 12,961 | +14 |
| Total / dedicated registers | 14,981 / 14,755 | 14,972 / 14,746 | -9 / -9 |
| M10Ks / bits | 275 / 2,238,504 | 275 / 2,238,504 | 0 |
| DSP blocks / PLLs / pins | 7 / 2 / 226 | 7 / 2 / 226 | 0 |
| Worst setup slack | +1.099 ns | +1.382 ns | +0.283 ns |
| Worst hold slack | +0.077 ns | +0.077 ns | 0 ns |
| Setup/hold TNS | 0 / 0 ns | 0 / 0 ns | 0 |
| Unconstrained setup/hold paths | 0 / 0 | 0 / 0 | 0 |

The final production critical slow-corner setup path runs from CPU operand
logic to the APU TND mixer in the 50 MHz domain. Its slow-corner critical hold
path and the all-corners hold minimum are in the generated HPS DDR interface;
the latter occurs at the fast 0 C corner. Production warnings remain the
existing HPS/generated-IP, incomplete-I/O, generated-SDC filter, Lite-edition
LogicLock, and PLL-compensation categories; no new HDMI pin assignment or
physical-interface warning was introduced.

## Required physical test plan

Before production approval:

1. Review the selected transmitter revision and all power, strap, pull-up,
   level, connector, ESD, thermal and layout requirements against the latest
   controlled manufacturer documents.
2. Measure rail sequencing and prove at least 200 ms between valid supplies and
   first I2C access. Confirm `0x72`, PD polarity and silicon identification.
3. Read every profile field back on hardware, capture ACK/NACK/timeout behavior,
   and verify safe power-down on each injected failure.
4. Measure 74.25 MHz clock, RGB/sync/DE setup/hold at transmitter pins and
   replace the provisional 1 ns PCB budget with extracted carrier delays.
5. Exercise HPD bounce, live unplug/replug, broken DDC, held-low SDA/SCL, slow
   clock stretching, invalid EDID and EDIDs with multiple extensions.
6. Test multiple TVs, monitors, capture devices, cable lengths and power cycles;
   verify InfoFrames, 4:3 presentation, color/range and exact 720p timing with a
   protocol analyzer and oscilloscope.
7. Perform TMDS signal-integrity, EMI/EMC, ESD and applicable HDMI compliance
   work. Do not infer those results from FPGA timing closure.

## Phase 6D interface boundary

Phase 6D may add I2S data, bit clock, word select, audio-clock policy, audio
InfoFrame/channel-status programming and audio-specific diagnostics. It must
reuse the table/transport arbitration architecture, preserve the Phase 6C
video startup and safe-disable behavior, and add official register values only
after documentation review. No audio register, pin or packet behavior is
implemented by Phase 6C.
