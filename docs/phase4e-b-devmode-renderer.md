# Phase 4E-B graphical Developer Mode renderer

## Scope and result

Phase 4E-B adds the first graphical Developer Mode page. It is a read-only,
full-screen 640x480 diagnostic display generated directly from VGA coordinates
and the coherent Phase 4E-A video-domain snapshot. It does not add a debug
framebuffer, side panel, pages, pause, stepping, breakpoints, memory editing or
viewers, save states, audio, storage, a boot menu, HDMI, or another mapper.

The complete path is:

```text
NES core and peripherals
  -> passive Phase 4E-A observations
  -> coherent 711-bit source snapshot
  -> toggle/acknowledge bundled-data CDC
  -> VGA-frame-stable destination bank
  -> Phase 4E-B text/glyph renderer
  -> explicit normal/developer RGB mux
  -> existing VGA timing and DAC outputs
```

The renderer has no signal that can control CPU, PPU, DMA, cartridge,
controller, NMI, system bus, or framebuffer behavior. It never reads a live NES
signal. Its only state input is `debug_destination_snapshot`, the renderer bank
that Phase 4E-A commits at VGA frame start.

Development began from clean, upstream-synchronized commit
`5fd7a2f3a1fb8c3d97dbbfc53050b75a026306cc` on
`phase4/devmode-snapshot`. Work is isolated on `phase4/devmode-renderer` and is
not merged to `main`. Phase 4E-B has not been programmed on physical hardware;
no physical-validation claim is made.

## Baseline

Before changes, the retained Phase 4E-A suite passed 1,174 Python tests, full
Verilator lint, every retained CPU/ALU/addressing, PPU, NMI/DMA, VGA, Phase
4A-4D-B, Phase 4E-A, playable-ROM, deterministic-frame, and long-run test. The
300-frame run produced 300 snapshots and destination updates, 297 NMIs, 297 DMA
completions, and 297 controller polls. All three VGA references compared
307,200 active pixels with zero mismatch.

The untouched Phase 4E-A board flow completed synthesis, fitting, assembly,
timing, and RBF conversion with 17 warnings and no error:

| Metric | Phase 4E-A baseline |
| --- | ---: |
| ALMs | 3,388 |
| logic ALUTs | 3,971 |
| memory ALUTs | 590 |
| registers | 3,801 |
| M10Ks | 230 |
| MLAB bits | 18,880 |
| block-memory bits | 1,871,872 |
| worst setup slack | +1.134 ns |
| worst hold slack | +0.149 ns |
| setup / hold TNS | 0.000 / 0.000 ns |
| unconstrained setup / hold paths | 0 / 0 |

The baseline SOF was 6,690,502 bytes with SHA-256
`e969af4e830d88f9a299352afb33ebb9c38ec78ccc140e16fab7a85b8ce96f64`.
The baseline RBF was 7,007,204 bytes and remained bit-identical to the prior
Phase 4E-A artifact, SHA-256
`d1cecd47403ba7c412a2cca2a2243b9d07181436b6be645d9f161153d198bcbd`.

## Font architecture and character set

`debug_font_pkg` implements a deterministic 6x8 cell font as combinational
ROM-style logic. Five columns carry visible strokes, the sixth is blank, and
row seven is blank. The display doubles rows but not columns, making each text
cell 8x16 pixels: six glyph columns, two horizontal spacing pixels, and each
font row repeated twice. This gives a 78-column by 29-row useful grid inside an
eight-pixel screen inset.

The supported set is space, `A-Z`, `0-9`, period, dash, slash, colon, equals,
and square brackets. Unsupported characters render blank. The package also
provides shared nibble-to-uppercase-hex and bit-to-character helpers. The font
uses no M10K or MLAB storage.

The Python model separately declares the complete glyph set as five-character
binary rows. It generates 352 reference rows: 44 characters times eight rows.
RTL checks every row, including all digits, all letters, and punctuation.

## Text engine and formatting

`nes_debug_renderer` converts `scan_x` and `scan_y` into a cell coordinate,
glyph coordinate, character, style color, and final pixel. Fixed labels are
selected through a reusable word helper. Dynamic fields use reusable owner,
controller-button, single-bit, and hexadecimal character helpers. Values are
displayed in deterministic uppercase hexadecimal:

- two digits for 8-bit values;
- four digits for 16-bit values;
- eight digits for 32-bit counters;
- three digits for 9- or 10-bit timing/count values.

The PPU scanline and dot are hexadecimal on this first compact page. This is
intentional and documented by their fixed three-digit width. No decimal
divider or large formatting datapath is required.

The palette is a dark navy background, a darker blue header band, cyan project
headings, yellow section headings, light text, green valid/idle/run states,
red invalid/stale/active/stalled states, and muted blue borders.

## Screen layout

The page title is project-owned and does not use Nintendo branding:

```text
FPGA CONSOLE - DEVELOPER MODE
SNAP=0000012C      VALID

CPU                       PPU                       CART
PC=80A5                   SL=08E                    PRESENT=1
A=03  X=10                DOT=0DD                   MAP=00
Y=20  SP=FF               CTRL=80                   NROM=128
P=24  OP=A9               MASK=1E                   PRG=40A5:4C
ADR=2002                  STAT=A0                   CHR=12F0:03
RD=EA  WR=55              VB=1 NMI=1                MIR=H
BUS=CPU                   Z=1 OV=0                  CHR=ROM
RW=R                      PIX=23 /12
RUN                       PAR=1

CONTROLLER                DMA                       SYSTEM
P1=A--TU--R               IDLE                      SNAP=0000012C
P2=-B----L-               PG=02                     FRAME=0000012C
STB=0                     ADR=02C1                  NMI=00000129
I1=3 I2=7                 IDX=C1                    DMA=00000129
SHIFT1=A5                 SLOT=201                  POLL=00000129
SHIFT2=5A                 RD=100 WR=100             CPU=0087DE98
                           OWN=CPU                   PPU=0197A4A8

READ ONLY - FPGA CONSOLE
```

The controller compact order is `A B Select sTart Up Down Left Right`.
Pressed buttons show `A`, `B`, `S`, `T`, `U`, `D`, `L`, or `R`; released
buttons show dash.

### CPU block

The CPU block displays PC, A, X, Y, SP, processor status, opcode, current
address, read data, write data, read/write/idle qualifier, stall/run state, and
bus owner. All values come from `snapshot.cpu`.

### PPU block

The PPU block displays scanline, dot, PPUCTRL, PPUMASK, PPUSTATUS, VBlank, NMI
level, sprite-zero hit, sprite overflow, pixel color, low palette-address byte,
and frame parity. All values come from `snapshot.ppu`.

### Cartridge block

The cartridge block displays presence, mapper, NROM-128/256 mode, PRG
address/data, CHR address/data, horizontal/vertical mirroring, and CHR ROM/RAM.
All values come from `snapshot.cartridge`.

### Controller block

The controller block displays both eight-button live vectors, strobe, read
indices, and both latched shift registers. All values come from
`snapshot.controller`.

### DMA block

The DMA block displays active/idle, source page and address, byte index,
elapsed slots, read/write counts, and bus owner. All values come from
`snapshot.dma`.

### System block

The system block displays snapshot ID, source-frame number, NMI count, DMA
completion count, controller-poll count, CPU-slot count, and PPU-cycle count.
All values come from `snapshot.system`.

## Snapshot health and update behavior

Before Phase 4E-A has delivered a snapshot, the page shows `INVALID`. A valid
snapshot shows `VALID`. The video-domain stale detector resets on every
`destination_update` and counts VGA frame starts without a new snapshot. Four
consecutive missed updates assert `STALE`. The four-frame interval tolerates a
single cadence beat between the approximately 60 Hz NES and VGA frames while
still detecting a stopped transfer quickly. Stale state is diagnostic only.

Phase 4E-A remains responsible for atomic update semantics: the 711-bit
renderer bank changes only at VGA frame start, and is then stable for the
complete displayed frame. The renderer is combinational from that stable bank
and coordinates, so one screen can never mix two source snapshots. The
existing asynchronous-clock test proves exactly one destination commit per
source capture, no commit without capture, and no group tearing. Phase 4E-B
tests coherent snapshot ID and field rendering from that bank.

## Video compositor and hard normal bypass

The existing `nes_vga_video` instance still owns the sole VGA timing generator,
framebuffer scaling, test-pattern selection, HSYNC, VSYNC, and blanking.
Its normal RGB outputs now have explicit internal names. A final three-channel
mux selects either those normal values or the Developer Mode page. Developer
Mode never modifies timing signals.

With `developer_mode_enable == 0`, the mux assignments are exactly:

```text
VGA_R/G/B = normal_vga_red/green/blue
```

No renderer pixel participates in that selected path. The testbench replaces
normal NES RGB with unrelated constant values and proves both directions: the
normal selection is an exact RGB bypass, and the Developer Mode page is
unchanged when normal NES pixels change.

## Developer Mode enable and board controls

No physical control was available without breaking Phase 4D-B:

- SW0 remains the color-bar/test-pattern selector;
- SW1 remains framebuffer capture freeze;
- SW2-SW9 remain Controller 1 A, B, Select, Start, Up, Down, Left, Right;
- KEY0 remains active-low reset.

The board top therefore exposes `DEVELOPER_MODE_DEFAULT` as a clean parameter
for simulation and future integration, with a default of zero. The normal
hardware SOF/RBF is hard-disabled for Developer Mode. A retained internal RGB
observation register prevents Quartus from pruning the implemented renderer,
so the build measures its genuine cost even though the physical mode select is
off. No switch or key was repurposed.

## Verification

### Python

`verification/debug_renderer.py` models the font, screen text, formatting,
colors, and direct-pixel composition at a higher level than the RTL selection
tree. Python tests cover the complete character set and row dimensions,
representative glyph shapes and punctuation, exhaustive hexadecimal nibbles,
8/16/32-bit formatting, controller compaction, layout strings, and the full
frame size.

### Focused RTL

`nes_debug_renderer_tb` produces `build/sim/nes_debug_renderer.fst` and checks:

- reset and stale reset;
- `INVALID`, `VALID`, and `STALE` selection;
- the intentionally short two-frame stale threshold used by the test;
- update clearing stale state;
- exhaustive nibble-to-character mapping;
- all 352 software-generated glyph rows;
- representative CPU, PPU, cartridge, controller, DMA, and counter values;
- exact normal RGB bypass;
- renderer independence from normal NES pixels;
- one full 640x480 active frame.

The simulated frame trace contains 307,200 pixels. The Python renderer compared
all 307,200 pixels and found zero mismatch. Active RGB SHA-256 is
`6ae63030601d8faec39ddacae77db7d72914017e5c9f75115da8a67f5dfebcee`.
The human-viewable `build/sim/phase4eb_developer_mode.ppm` is 921,615 bytes,
SHA-256 `0bcfdefacce4a03a53255ee5d0c9166a4f45ccf5e1fd0c524b4862b159174489`.

### Normal and playable invariants

The retained playable-ROM run continues for 300 frames with 300 snapshot
captures/updates, 297 NMIs, 297 completed DMAs, 297 controller polls, 7,281,984
PRG reads, and 11,983,656 CHR reads. Normal-mode deterministic hashes remain:

| Frame | SHA-256 |
| --- | --- |
| title | `e7707b93cddfbdfa148dffb38523d03013d2ff9a717981a416cb00078db05ae2` |
| post-Start | `a49d66d2e3a6662c3b8113f701f70a4dc44e932e05d18100c270de626f951e52` |
| A | `ffe9da19bfc93c2c717dd5dfb046ebe8cb7330503556e4a12deb6d24d54f8939` |
| B | `35bba0c5f1de0b9159cccd77e4f7a045cd4e103950fad1c35bc17101a27b14ba` |
| Select | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Right | `71d5e3a9e3268eddd86d5653fbb00ce16056fd73fbc6c1cf82b536cc2aacdb41` |
| Left | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Up | `83aaf2a6db7ad77d207c9cbad8293e4d2aa9f7e1b9379383aa989d2cd284d159` |
| Down | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |

The normal framebuffer-to-VGA comparisons continue to check all 307,200
active pixels with zero mismatch. This confirms the disabled compositor makes
no functional change to normal gameplay or VGA timing.

## Quartus resources and timing

The final DE1-SoC flow completed synthesis, fitting, assembly, full timing, and
RBF generation with no error:

| Metric | Phase 4E-A | Phase 4E-B | Increment |
| --- | ---: | ---: | ---: |
| ALMs | 3,388 | 4,455 | +1,067 |
| logic ALUTs | 3,971 | 5,838 | +1,867 |
| memory ALUTs | 590 | 590 | 0 |
| registers | 3,801 | 3,908 | +107 |
| M10Ks | 230 | 230 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| block-memory bits | 1,871,872 | 1,871,872 | 0 |
| DSPs / PLLs | 0 / 1 | 0 / 1 | 0 / 0 |

There is no 640x480 debug framebuffer. The increment is direct combinational
text/glyph logic and a small number of video-domain registers.

Worst setup slack is +0.536 ns, worst hold slack is +0.151 ns across all
reported corners, setup and hold TNS are both zero, and there are zero
unconstrained setup/hold paths. The pixel-clock setup slack is +1.174 ns. The
worst setup path has 18 logic levels and 18.942 ns data delay from CPU
`debug_addressing_mode[1]` through the existing system/PPU memory path to PPU
sprite `pattern_low[4][4]`; it is not in the debug renderer.

Quartus reports the same 17-warning total and categories as baseline: the
intentional constant VGA sync pin, incomplete-I/O summary, PLL compensation,
subscription-only LogicLock notice, and two stale unmatched IRQ synchronizer
filters in the existing SDC. No new renderer warning category appears.

The final SOF is 6,690,502 bytes, SHA-256
`369e88a1314530b92a3a51c9d72e7a561c7401f416f0778d40866049c8d5e508`.
The final RBF is 7,007,204 bytes, SHA-256
`ce155fca7ec4a1a6bed180f76c8ee00f888f7a949177c9717b6bf89bf2959344`.
Neither artifact has been programmed on hardware in this phase.

## Exact Phase 4E-C recommendation

Phase 4E-C should keep this renderer and snapshot contract, but replace the
full-screen page selection with a 512+128 compositor:

1. Keep the existing 640x480 timing generator and normal hard bypass.
2. In Developer Mode only, place the current 256x240 NES framebuffer at exact
   2x scale in pixels `x=0..511`, `y=0..479`.
3. Restrict a compact renderer to `x=512..639`, giving a 16-column by 30-row
   panel with the existing 8x16 cell geometry.
4. Define the first side page as snapshot health/ID, CPU PC/A/X/Y/SP/P/opcode,
   PPU scanline/dot/status, compact pad bits, DMA active/index, and frame/NMI/DMA
   counters. Defer multiple pages and all control features.
5. Continue reading only the Phase 4E-A frame-stable destination bank. Do not
   add live NES taps or feedback paths.
6. If pipelining is needed, delay both left-game and right-panel RGB by the same
   number of pixel clocks while leaving the disabled normal path as the current
   direct bypass.
7. Add an explicit safe physical mode source (for example a separately
   specified GPIO or virtual/JTAG control) before claiming board-selectable
   Developer Mode. Do not reuse SW0, SW1, SW2-SW9, or KEY0.
8. Preserve the nine normal-mode hashes and add a pixel-perfect 512+128
   Developer Mode reference frame before hardware programming.
