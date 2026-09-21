# Phase 4E-C game and Developer side-panel composition

## Scope and result

Phase 4E-C composes the playable NES and the observation-only Developer Mode
on one 640x480 VGA frame. In Developer Mode, the complete 256x240 game image
is enlarged by an exact integer factor of two into `x=0..511`, while a compact
read-only diagnostic panel occupies `x=512..639`. Normal Mode remains the
existing centered NES presentation through a literal RGB bypass.

The data paths are deliberately separate:

```text
NES PPU -> triple framebuffer -> exact-2x scaler -> game RGB -----+
                                                                  |
Phase 4E-A frame-stable snapshot -> compact panel renderer -------+-> RGB mux -> VGA

existing VGA timing -----------------------------------------------> sync/blank/clock
```

The panel consumes only the Phase 4E-A 711-bit video-domain snapshot,
snapshot-valid/update status, and VGA coordinates. It has no live core or NES
pixel input, and no output feeds CPU, PPU, cartridge, controller, DMA, NMI,
bus, or framebuffer control. This phase adds no pause, step, breakpoint,
editor, memory/graphics viewer, audio, storage, boot menu, or mapper.

Development began from clean, upstream-synchronized Phase 4E-B commit
`1045b99fd865a3d89e60cc38657162286c5ac39c` and is isolated on
`phase4/devmode-side-panel`. It is not merged to `main`.

## Baseline

The unmodified Phase 4E-B baseline passed 1,179 Python tests, complete
Verilator lint, every retained CPU, ALU/addressing, PPU, DMA/NMI, VGA, Phase
4A-4E-B, playable-ROM, normal-frame-hash, and 300-frame long-run test. The
long run recorded 300 frames/snapshots, 297 NMIs, 297 DMA completions, and 297
controller polls.

The baseline DE1-SoC flow completed synthesis, fitting, assembly, timing, and
RBF generation with 17 warnings and no errors:

| Metric | Phase 4E-B baseline |
| --- | ---: |
| ALMs | 4,455 |
| logic ALUTs | 5,838 |
| memory ALUTs | 590 |
| registers | 3,908 |
| M10Ks | 230 |
| MLAB bits | 18,880 |
| block-memory bits | 1,871,872 |
| DSPs / PLLs | 0 / 1 |
| worst setup slack | +0.536 ns |
| pixel-clock setup slack | +1.174 ns |
| worst hold slack | +0.151 ns |
| setup / hold TNS | 0.000 / 0.000 ns |
| unconstrained setup / hold paths | 0 / 0 |

The fresh baseline SOF was 6,690,502 bytes, SHA-256
`974fb5d56eed11e0f01d15916bb2e3a98832452fe88953895761d80024c78fe3`.
The baseline RBF was 7,007,204 bytes, SHA-256
`ce155fca7ec4a1a6bed180f76c8ee00f888f7a949177c9717b6bf89bf2959344`.

## Game-region scaling and panel geometry

`vga_nes_scaler` now has an explicit `developer_layout` input. Its normal
mapping is unchanged: the 512-pixel-wide exact-2x image is centered at
`x=64..575`. Developer layout changes only the horizontal origin to zero.
Both layouts calculate:

```text
nes_x = (vga_x - left_edge) >> 1
nes_y = vga_y >> 1
framebuffer_address = nes_y * 256 + nes_x
```

Thus every NES pixel appears at `(2x,2y)`, `(2x+1,2y)`, `(2x,2y+1)`, and
`(2x+1,2y+1)`. No pixel is cropped or stretched. The panel renderer accepts
only coordinates `x=512..639`, `y=0..479`. The final compositor uses
`scan_x < 512` for game selection, so pixel 511 is always game and pixel 512
is always panel.

The panel reuses the Phase 4E-B ROM-style 6x8 font, displayed in 8x16 cells.
Its 128x480 area therefore contains exactly 16 columns by 30 rows. It uses no
framebuffer and no block memory; glyph, character, color, and value selection
are generated directly from coordinates and the stable snapshot. The panel
receives the normal video pipeline's one-stage-earlier render coordinates and
registers RGB on the same edge that registers game RGB. This gives the text
selection tree a full pixel period without shifting the game/panel boundary.

## Compact text layout

The first live-overview page intentionally selects the fields most useful
during gameplay:

```text
 DEV MODE
 VALID / STALE / INVALID
 CPU
 PC xxxx
 A xx X xx Y xx
 SPxx Pxx OPxx
 RUN/STALL  CPU/DMA/NONE

 PPU
 SLxxx DTxxx
 Cxx Mxx Sxx
 Nn Vn Zn

 CART
 MAPxx N128/256
 PRGxxxx
 CHRxxxx MIR H/V

 PAD1
 ABSTUDLR

 DMA
 ACTIVE/IDLE
 PGxx IDXxx
 CNTxxxxxxxx

 SYSTEM
 FRxxxxxxxx
 IDxxxxxxxx
 NMIxxxxxxxx
 DMAxxxxxxxx
```

Lowercase `x` denotes hexadecimal digits and `n` a binary status digit. The
controller order is A, B, Select, sTart, Up, Down, Left, Right; a released
button is a dash. CPU exposes PC, A/X/Y, SP, status, opcode, run/stall, and bus
owner. PPU exposes scanline, dot, PPUCTRL, PPUMASK, PPUSTATUS, NMI, VBlank, and
sprite-zero hit. Cartridge exposes mapper, NROM mode, PRG/CHR addresses, and
mirroring. DMA exposes active/idle, page, index, and completion count. System
exposes source frame, snapshot ID, NMI count, and DMA count.

The PPU scanline/dot fields remain three-digit uppercase hexadecimal, matching
Phase 4E-B and avoiding a divider. Colors and stale behavior are also reused:
dark background, cyan header, yellow section labels, light values, green good
state, red fault/stale state, and a four-VGA-frame stale threshold.

## Compositor, mode priority, and board controls

`nes_developer_compositor` is the single final RGB selector:

```text
Developer Mode off: existing normal NES RGB (literal bypass)
Developer Mode on, blanking: black RGB
Developer Mode on, x < 512: left-aligned game/test-pattern RGB
Developer Mode on, x >= 512: panel RGB
```

HSYNC, VSYNC, blanking, and VGA clock continue directly from the one existing
timing generator and never pass through the compositor.

The effective behavior priority is:

1. KEY0 low asynchronously requests reset; synchronized resets blank/restart
   the affected state.
2. VGA blanking suppresses active RGB.
3. `developer_mode_enable` chooses the normal full-width layout or 512+128
   composition.
4. Within the selected game region, SW0 chooses the established color bars in
   place of framebuffer pixels. It does not replace or obscure the panel.
5. SW1 suppresses framebuffer capture only.

No physical assignment changed:

- SW0: color-bar/test-pattern selector;
- SW1: framebuffer capture freeze;
- SW2-SW9: Controller 1 A, B, Select, Start, Up, Down, Left, Right;
- KEY0: active-low reset.

The board build keeps `DEVELOPER_MODE_DEFAULT=0`. A retained video-domain
mode register provides a clean simulation/integration selection point without
repurposing a switch. A future physical revision should drive that point from
a separately specified, synchronized, debounced input or a virtual/JTAG
control. SW0-SW9 and KEY0 must not be stolen.

SW1 preserves its original semantics in Developer Mode: the last completed
game framebuffer remains displayed, while NES execution, Phase 4E-A snapshot
capture/CDC, and the panel continue. This makes a frozen game image useful
without making debug data stale.

## Verification architecture

The Python reference extends the Phase 4E-B font/layout model with a compact
panel and a complete combined-frame renderer. It independently performs exact
2x sampling for the left 512 pixels and panel rendering for the right 128.
Python tests exhaustively prove all 512x480 left-region coordinates and that
each of the 61,440 NES source addresses occurs exactly four times.

`nes_developer_side_panel_tb` is the focused RTL test. It checks reset,
invalid/valid/stale behavior, exact normal bypass, panel independence from game
RGB, game independence from snapshot changes, and both `y=0` and `y=479` at
`x=0,1,510,511,512,513,638,639`. It emits an FST and a complete synthetic
640x480 trace for an all-pixel software comparison.

`nes_vga_phase4ec_tb` instantiates the actual board top with the project-owned
playable ROM and Developer Mode enabled through the parameter. It shadows real
framebuffer writes, captures an actual completed game bank and a coherent
Phase 4E-A snapshot, then compares the resulting 512+128 frame independently.
It also proves SW0 affects only the game region, SW1 freezes only game capture,
Controller 1 Right changes both gameplay and a later panel snapshot, CPU state
changes between snapshots, IDs/fields stay constant for each displayed frame,
and composition remains live for 60 further snapshots.

## Normal-mode invariants and VGA timing

Normal Mode never selects panel RGB and still passes every established VGA
pixel/reference check. The retained playable-ROM regression checks all nine
Phase 4D-B hashes (title, post-Start, A, B, Select, Right, Left, Up, and Down),
plus 300 sustained gameplay frames. The existing timing test still proves 640
active pixels, 480 active lines, horizontal/vertical sync, blanking, and pixel
cadence. Developer Mode changes only active RGB content.

## Final measured results

The final retained regression passes 1,182 Python tests, full Verilator lint,
all CPU/ALU/addressing, PPU, DMA/NMI, VGA, Phase 4A through Phase 4E-B, both
Phase 4E-C tests, the playable-ROM integration, normal hashes, and the
300-frame long run. That long run reports 300 frames, 300 source snapshots,
300 destination updates, 297 NMIs, 297 DMA completions, and 297 controller
polls. The Developer Mode integration reaches 73 frames and 71 snapshot-bank
updates, then continues through 70 NMIs, 70 DMAs, and 70 controller polls; 66
successive snapshots change CPU state, and Right moves the real-ROM sprite
from x=121 to x=123.

Both complete Developer Mode frames compare all 307,200 active pixels with
zero mismatches. The synthetic combined-frame RGB hash is
`0d6f92b603db34913a94e565344204c6110e42d1ca098b7ffb2a97610cbdb62a`;
its 921,615-byte PPM hash is
`468d74b5b47a0e27050cf93dc7ab86c236886d3eae920ed4a1820ff4781722a0`.
The real playable-ROM combined-frame RGB hash is
`113e019fce63860e7b6058f5104cb43c7fb6710f6a0d0ed96aa242d21e0da5e0`;
its 921,615-byte PPM hash is
`25423b60927d405c34a2151d6a9ffa5ffe7b16bde857549a02baa1f1aa391473`.
The focused Phase 4E-C FST is 223,977 bytes with SHA-256
`328db926e527752385e81594b6744f36512c7af12b07200d5108bd7ca683d846`.

Every retained normal-mode RGB hash is unchanged:

| Fixture | SHA-256 |
| --- | --- |
| title | `e7707b93cddfbdfa148dffb38523d03013d2ff9a717981a416cb00078db05ae2` |
| post-Start | `a49d66d2e3a6662c3b8113f701f70a4dc44e932e05d18100c270de626f951e52` |
| A | `ffe9da19bfc93c2c717dd5dfb046ebe8cb7330503556e4a12deb6d24d54f8939` |
| B | `35bba0c5f1de0b9159cccd77e4f7a045cd4e103950fad1c35bc17101a27b14ba` |
| Select / Left / Down | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Right | `71d5e3a9e3268eddd86d5653fbb00ce16056fd73fbc6c1cf82b536cc2aacdb41` |
| Up | `83aaf2a6db7ad77d207c9cbad8293e4d2aa9f7e1b9379383aa989d2cd284d159` |

The compact side panel replaces the Phase 4E-B full-screen layout instead of
duplicating it. The final fitted comparison is:

| Metric | Phase 4E-B | Phase 4E-C | Change |
| --- | ---: | ---: | ---: |
| ALMs | 4,455 | 3,789 | -666 |
| logic ALUTs | 5,838 | 4,743 | -1,095 |
| memory ALUTs | 590 | 590 | 0 |
| registers | 3,908 | 3,907 | -1 |
| M10Ks | 230 | 230 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| block-memory bits | 1,871,872 | 1,871,872 | 0 |
| DSPs / PLLs | 0 / 1 | 0 / 1 | 0 / 0 |

An initial implementation exposed the unregistered glyph-selection tree all
the way to the VGA pins and failed timing. Registering panel RGB at the same
pipeline boundary as game RGB removed that path without changing any frame
pixel. The final full Quartus flow passes with +0.942 ns worst setup slack,
+0.146 ns worst hold slack, zero setup/hold TNS, and no unconstrained setup or
hold path. Pixel-clock and final VGA-output setup slack are both +1.168 ns;
the final output path has one logic level and 6.619 ns data delay. The overall
critical setup path has 17 logic levels and 18.391 ns data delay, from CPU
`debug_addressing_mode[1]` to snapshot DMA source-data bit 7. It passes and is
not the panel/compositor output path.

Quartus completes with 17 warnings and no errors. The audited categories are
the existing unused-status aggregation, tied-off inferred ROM write ports,
connectivity summary, intentional constant `VGA_SYNC_N`, subscription-only
LogicLock notice, incomplete-I/O summary, PLL compensation notice, and two
stale unmatched IRQ synchronizer filters repeated by fitter/timing. There is
no new panel/compositor warning category.

The final SOF is 6,690,502 bytes with SHA-256
`b884d4a02643adf838521655c26dd3ca46f8dc2ba798084bc5951296e0b96a64`.
The final RBF is 7,007,204 bytes with SHA-256
`409f86e2eb0cde268c3e17b8da56ed1f68aee469929940588c805280ffae6505`.

No Phase 4E-C artifact has been programmed on physical hardware; no physical
validation claim is made. Once a safe mode input exists, hardware validation
should confirm stable VGA, an uncropped 512x480 playable game at left, the
128x480 live panel at right, controller response, updating values, SW0 bars,
SW1 game-only freeze, and no gameplay corruption.

## Exact Phase 4E-D recommendation

Keep the compositor, geometry, font, and Phase 4E-A snapshot contract intact.
Add one small page-select register in the video domain, driven only by a new
safe synchronized/debounced board input or virtual/JTAG control. Select among
compact character/layout generators before the shared glyph/color stage; do
not instantiate another font or framebuffer. Recommended pages are:

1. live overview: the present Phase 4E-C page;
2. CPU/bus: complete CPU registers, address/read/write/valid, opcode, owner,
   stalls, and selected system counters;
3. PPU/cartridge: timing/register/pixel state plus PRG/CHR/mirroring detail;
4. DMA/controllers/system: DMA phase/counts, both controller ports and shift
   state, snapshot health, and performance counters.

Commit page selection only at VGA frame start so a displayed frame cannot mix
layouts. Pages must continue to consume only the stable snapshot bank, remain
read-only, leave sync/blanking and the `x=511/512` boundary unchanged, preserve
the literal normal bypass, and gain independent all-pixel reference fixtures.
