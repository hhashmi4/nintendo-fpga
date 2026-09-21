# Phase 3K — DE1-SoC VGA output

## What this phase does

The NES core produces logical picture information: a valid flag, an `(x,y)`
coordinate, a six-bit NES palette index, and three emphasis bits. A VGA
monitor instead needs a continuous pixel clock, red/green/blue voltages, and
horizontal/vertical synchronization even while the NES is not drawing.

Phase 3K therefore keeps video outside the PPU and implements this boundary:

```text
nes_core logical pixels
        -> triple framebuffer
        -> 2x integer scaler
        -> NES palette/emphasis lookup
        -> 640x480 VGA timing
        -> DE1-SoC ADV7123 VGA DAC
```

This boundary deliberately remains reusable. A future native-HDMI module can
read the same logical frame interface without modifying `nes_core`, the PPU,
or the VGA module. An external VGA-to-HDMI converter can already consume the
board VGA output with no RTL change.

## Board VGA hardware and pins

The source of truth is the official [Terasic DE1-SoC rev. F/G user
manual](https://community.altera.com/t5/s/jgyke29768/attachments/jgyke29768/fpga-device/73098/1/DE1-SoC_User_manual_revf.pdf),
available from Terasic's [DE1-SoC resources
page](https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=17&Language=English&No=870&PartNo=4).
The board contains an ADV7123 triple ten-bit DAC, but the DE1-SoC connects the
high eight converter bits for each channel. The FPGA interface is consequently
24-bit RGB: eight red, eight green, and eight blue pins. All are 3.3-V LVTTL.

| Signal | Width | Cyclone V pins, bit 0 first |
| --- | ---: | --- |
| `VGA_R` | 8 | A13, C13, E13, B12, C12, D12, E12, F13 |
| `VGA_G` | 8 | J9, J10, H12, G10, G11, G12, F11, E11 |
| `VGA_B` | 8 | B13, G13, H13, F14, H14, F15, G15, J14 |
| `VGA_HS` | 1 | B11 |
| `VGA_VS` | 1 | D11 |
| `VGA_CLK` | 1 | A11 |
| `VGA_BLANK_N` | 1 | F10 |
| `VGA_SYNC_N` | 1 | C10 |

HSYNC and VSYNC are active-low in this mode. `VGA_BLANK_N` is low outside the
active picture and `VGA_SYNC_N` is tied low as required by the board DAC path.
RGB is already eight bits per channel, so no additional board-bus
quantization is necessary. The physical VGA DAC is analog; this project does
not claim analog NTSC color synthesis.

## Clocking and real NES rate

The 50.000 MHz oscillator remains the only system/fabric clock. The existing
fractional accumulator emits NES master enables at `189/440` of 50 MHz, and a
master divider emits a PPU enable every four master ticks. `nes_core` advances
only on that PPU enable and retains its internal exact three-PPU-ticks per
CPU-slot scheduler.

| Quantity | Target | Generated average | Error |
| --- | ---: | ---: | ---: |
| NES master | 21.477272727 MHz | 21.477272727 MHz | 0 ppm |
| PPU | 5.369318182 MHz | 5.369318182 MHz | 0 ppm |
| CPU slot | 1.789772727 MHz | 1.789772727 MHz | 0 ppm |
| PPU:CPU | 3:1 | exactly 3:1 | exact |

The enables are data-plane clock enables, not generated clocks. This replaces
Phase 3J's deliberately accelerated 50 MHz logical PPU operation with the
appropriate NTSC average wall-clock rate.

VGA uses one Cyclone V PLL: 50 MHz multiplied by 63 and divided by 125 gives
25.200 MHz. That is 0.0993% above the historical 25.175 MHz nominal VGA pixel
clock. With 800 pixels by 525 lines it produces exactly 60.000 Hz relative to
the nominal 50 MHz board oscillator; it is not described as a 25.175 MHz or
59.94 Hz output. `VGA_CLK` is the inverse of the internal scan clock so the
ADV7123 receives a rising sampling edge half a pixel period after RGB changes.

There are two legitimate domains:

- `CLOCK_50`: NES, CPU, PPU, cartridge diagnostic, and framebuffer writes;
- 25.2 MHz PLL output: framebuffer reads, scaling, palette lookup, and VGA.

Reset is asserted asynchronously from active-low `KEY0` or loss of PLL lock,
then released through an independent two-flop reset synchronizer in each
domain. Phase 3K timing constraints derive the PLL clocks, declare the two
functional domains asynchronous, constrain VGA output delays, and explicitly
exclude only asynchronous controls, the VGA clock output itself, and
human-visible debug outputs.

## VGA timing

All timing values are named constants in `vga_timing.sv`.

| Region | Horizontal pixels | Vertical lines |
| --- | ---: | ---: |
| Active | 640 | 480 |
| Front porch | 16 | 10 |
| Active-low sync | 96 | 2 |
| Back porch | 48 | 33 |
| Total | 800 | 525 |

The active picture is 640x480 progressive. A complete frame is 420,000 pixel
clocks and contains 307,200 visible pixels. RGB and `VGA_BLANK_N` are forced
black/inactive outside the visible region. The independent timing test resets
the generator during active video, horizontal blanking, and vertical blanking,
then proves one complete frame contains exactly 307,200 active samples, 50,400
low-HSYNC samples, 1,600 low-VSYNC samples, and 525 lines.

## Framebuffer and clock-domain handoff

Each stored pixel is nine bits: six-bit NES color plus its three emphasis bits.
One 256x240 bank is 61,440 pixels or 552,960 logical bits. Three banks consume
1,658,880 logical framebuffer bits. Quartus infers each as a 61,440x9
dual-clock M10K memory, 68 M10Ks per bank and 204 M10Ks total. The third bank
is intentional: the NES is about 60.10 frames/s while VGA is 60.00 frames/s,
so simple ping-pong buffers can miss the next NES frame when a VGA release
lands just after NES frame start.

The NES writer starts only at a real PPU frame boundary. On every
`pixel_valid`, address `{pixel_y,pixel_x}` is exactly `pixel_y*256+pixel_x`.
Assertions enforce Y 0-239, address 0-61,439, monotonic address order, and a
complete final coordinate of `(255,239)`. This proves one write to each of the
61,440 locations with no out-of-range or accidental duplicate write.

A completed bank is published with a toggle and stable two-bit bank ID. The
bank ID receives two synchronizer stages; the request toggle receives three,
so bundled bank data settles before the request is consumed. VGA changes read
ownership only at `(799,524)`, after the complete scan. Its acknowledge toggle
and stable read-bank ID return through synchronizers. With three banks, one is
displayed, one may be queued, and one may be written; assertions prevent
illegal ownership overlap. A queued bank is never modified. If an abnormal
clock relationship leaves the one-entry completed-frame queue occupied for an
entire new NES capture, hardware latches the fault instead of presenting or
overwriting a partial frame.

The RAM has one registered-address read clock of latency. VGA coordinate,
active, region, mode, HSYNC, and VSYNC metadata are delayed by exactly the same
clock, then RGB and matching metadata enter a second output register stage.
This removes the common one-pixel BRAM alignment error and gives the DAC a
timed half-cycle output window before its sampling edge.

## Scaling, border, color, and emphasis

The scaler uses no interpolation:

```text
VGA x 0..63     -> black left border
VGA x 64..575   -> NES x = (VGA x - 64) >> 1
VGA x 576..639  -> black right border
VGA y 0..479    -> NES y = VGA y >> 1
```

Thus 256x240 becomes 512x480, centered with exactly 64 black pixels on each
side and no vertical border. Exhaustive Python verification checks all 307,200
visible coordinates: every NES coordinate appears exactly four times, twice
horizontally and twice vertically, with no third copy, skip, or boundary leak.

`nes_palette_rgb.sv` contains a deterministic 64-entry 24-bit palette based on
the NESdev [2C02G digital palette
file](https://www.nesdev.org/wiki/File%3A2C02G_wiki.pal). It is a recognizable
digital representation, not exact composite/NTSC analog reproduction. For
emphasis, red emphasis attenuates green and blue, green attenuates red and
blue, and blue attenuates red and green. Attenuation is deterministically 75%
with integer shifts; a channel is attenuated once even when multiple relevant
bits are active. All 512 color/emphasis combinations are reference-tested.

## Diagnostic cartridge and controls

The dedicated board top preserves the Phase 1 and Phase 2K tops. In normal
mode it instantiates a small ROM-only cartridge-shaped diagnostic. A real CPU
program at `$8000` clears OAM, creates two sprites in CPU RAM `$0200`, writes
all 32 palette bytes through PPU registers, fills all 1,024 nametable/attribute
bytes, performs `$4014` DMA, and enables rendering/NMI. The NMI handler at
`$9000` increments a RAM counter, moves sprite zero +8 NES pixels, and performs
another real DMA. The observed picture therefore follows the entire route:

```text
CPU RAM -> $4014 DMA -> PPU OAM -> sprite evaluation -> CHR fetch
        -> sprite renderer/mixer -> NES pixel stream -> framebuffer -> VGA
```

Controls:

- `KEY0`: active-low system/video reset;
- `SW0=0`: NES diagnostic scene; `SW0=1`: framebuffer-independent VGA bars;
- `SW1=1`: stop starting new frame captures; scanout continues the last frame.

The independent VGA pattern has black 64-pixel side borders and eight
64-pixel-wide vertical bars inside the centered 512-pixel region: white,
yellow, cyan, green, magenta, red, blue, and gray. Normal NES mode shows a
four-pattern colored tiled background, two sprites, and sprite-zero movement.

Debug outputs:

| Output | Meaning |
| --- | --- |
| LEDR0 | PLL locked |
| LEDR1 | system out of reset |
| LEDR2 | test-pattern mode |
| LEDR3 | capture freeze |
| LEDR4 | toggles per completed NES capture |
| LEDR5 | toggles per VGA frame |
| LEDR6 | toggles per completed OAM DMA |
| LEDR7 | toggles per PPU NMI event |
| LEDR8 | framebuffer range/sequence fault |
| LEDR9 | system or video reset active |
| HEX5..HEX2 | live CPU PC, hexadecimal |
| HEX1..HEX0 | low eight bits of captured-frame count |

No video function depends on an LED or HEX output.

## Verification evidence

The Python reference model independently defines timing, scaling, palette,
emphasis, pattern mode, NES rates, and three-bank handoff semantics.

- exhaustive scaler: all 307,200 visible positions, all 61,440 NES locations;
- RTL VGA timing: 420,000 clocks and three mid-frame/reset regions;
- static framebuffer/VGA: 307,200 active pixels, zero Python mismatches;
- independent bars: 307,200 active pixels, zero Python mismatches;
- CDC/ownership: two asynchronous clocks, queued third bank, swaps only at
  VGA frame end, displayed bank constant throughout active scan;
- reset during incomplete NES capture: partial frame discarded and display
  validity/counters deterministically cleared;
- full NES/VGA: 307,200 active pixels compared against the captured real NES
  frame, zero Python mismatches;
- integrated run: 2,520,005 50 MHz cycles, 270,614 PPU ticks, 90,204 CPU
  slots, three NMI events, four DMAs, three captures, and three displays;
- dynamic sprite: NES X 48->56 and corresponding VGA X 160->176, exactly +8
  and +16 respectively.

The full retained regression covers Phase 1, CPU Phase 2A-2K, PPU Phase
3A-3I, Phase 3J integration, exhaustive ALU/address tests, and Phase 3K. CI
runs Python, whole-project Verilator lint, every retained simulation, both
full-pixel Python trace comparisons, and the new timing/CDC/reset tests.
Quartus builds remain local because CI does not install licensed Intel tools.

## Synthesis, fit, and timing

The physical image targets `5CSEMA5F31C6`. Final results are recorded after
the reproducible `scripts/build_de1_soc_nes_vga_quartus.sh` flow:

| Resource | Result |
| --- | ---: |
| ALMs | 3,003 / 32,070 (9%) |
| logic ALUTs | 3,498 |
| routing-only ALUTs | 79 |
| memory ALUTs | 590 |
| registers | 1,180 |
| logical block-memory bits | 1,675,264 / 4,065,280 (41%) |
| MLAB bits | 18,880 |
| M10Ks | 206 / 397 (52%) |
| DSPs | 0 |
| PLLs | 1 |

The constrained clocks are `CLOCK_50` at 50.000 MHz, the PLL internal VCO at
630.000 MHz, and the PLL scan clock at 25.200 MHz. Worst multicorner
setup slack is +1.054 ns, worst hold slack is +0.163 ns, and worst minimum
pulse-width slack is +0.793 ns. Setup and hold TNS are zero. The TimeQuest
unconstrained-path summary reports zero unconstrained clocks, inputs, outputs,
input paths, and output paths.

## Build artifacts and Mac programming handoff

Build, fit, time, assemble, and convert without programming anything:

```bash
./scripts/build_de1_soc_nes_vga_quartus.sh
```

Final volatile-programming artifacts:

- `/home/humza/fpga/nintendo-fpga/build/quartus_de1_soc_nes_vga/output_files/de1_soc_nes_vga.sof`
- `/home/humza/fpga/nintendo-fpga/build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf`

SHA-256 values:

- SOF: `f532c8eda63abc4b3ec1f5efef4402a79777cbad67ca5a06d8df77eda3bfdb4b`
- RBF: `2e18c2351892efbd36c0992a363aac1481a237f2847524b9b92c9320a8bd3f2f`

On the Mac, copy the RBF from lab-node-01:

```bash
scp humza@lab-node-01:/home/humza/fpga/nintendo-fpga/build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf .
```

Use the already proven USB-Blaster II firmware and chain layout:

```bash
/opt/homebrew/bin/openFPGALoader -c usb-blasterII \
  --probe-firmware /Users/humzahashmi/fpga/firmware/blaster_6810.hex \
  --detect

/opt/homebrew/bin/openFPGALoader -c usb-blasterII \
  --probe-firmware /Users/humzahashmi/fpga/firmware/blaster_6810.hex \
  --index-chain 1 ./de1_soc_nes_vga.rbf
```

This command loads volatile Cyclone V SRAM only. It does not select or write
persistent flash.

Physical wiring is:

```text
MacBook --USB--> USB-Blaster --JTAG--> DE1-SoC
DE1-SoC VGA OUT --VGA cable--> powered native VGA monitor on VGA input
```

The VGA cable does not connect to the Mac. Power the board with its normal
supply.

## Physical PASS/FAIL and troubleshooting

Start with `SW0=1`. PASS is a stable, non-rolling 640x480 signal with two black
64-pixel borders and the eight centered vertical bars in the exact order
listed above. There must be no tearing, wrong-width bar, color instability, or
horizontal/vertical roll. Then set `SW0=0`. PASS is the stable centered tiled
NES scene with colored patterns and moving sprites. LEDR0 and LEDR1 should be
on; LEDR8 must remain off. `SW1` should visibly freeze the last complete NES
frame without disturbing sync.

- **NO SIGNAL:** confirm the RBF programmed successfully, LEDR0 is on, the
  monitor is powered/on VGA input, the cable is on DE1-SoC VGA OUT, and check
  VGA clock/pin assignments plus HSYNC/VSYNC.
- **Signal but black:** select `SW0=1`, then inspect `VGA_BLANK_N`, active
  video, RGB, PLL/reset LEDs, and framebuffer validity.
- **Rolling or unsynchronized:** inspect 800x525 totals, 25.2 MHz clock, and
  active-low sync polarity.
- **Correct bars but bad NES image:** VGA hardware is good; inspect NES frame
  capture, handoff fault LEDR8, palette conversion, scaling, CPU PC, NMI, and
  DMA heartbeats.

Automated work on lab-node-01 cannot observe the monitor and therefore cannot
claim physical VGA PASS.

## Remaining limitations

- The physical VGA image still requires user observation on the locally
  connected DE1-SoC and monitor.
- Phase 2K physical LED/HEX confirmation remains outstanding and is not called
  hardware verified.
- The board image uses a diagnostic PRG/CHR ROM, not a cartridge loader or
  mapper; `nes_core` keeps its production cartridge-facing PRG/CHR boundary.
- APU/audio, controllers, mapper support, cartridge loading, saves, PAL/Dendy
  modes, and native HDMI are not implemented.
- The palette and emphasis are deterministic digital approximations, not an
  analog NTSC decoder model.
- The current frame queue holds one completed frame; an extreme abnormal clock
  relationship that keeps it pending for an entire capture latches a fault and
  discards that newly completed frame instead of tearing.
