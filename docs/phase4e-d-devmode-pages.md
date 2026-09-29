# Phase 4E-D multiple Developer Mode pages

## Scope and result

Phase 4E-D adds five selectable pages to the existing 128x480 Developer Mode
side panel. The 512x480 exact-2x playable game region, Phase 4E-A 711-bit
snapshot and CDC, Phase 4E-B font/text infrastructure, Phase 4E-C compositor,
VGA timing, and literal normal-mode bypass are unchanged.

The resulting observation-only path is:

```text
NES core -> coherent source snapshot -> safe CDC -> frame-stable snapshot --+
                                                                          |
virtual page request -> frame-start page latch -> page-aware text layout --+-> shared glyph/color renderer
NES framebuffer -> exact-2x scaler ------------------------------------------> x=0..511
panel RGB -------------------------------------------------------------------> x=512..639
```

No debug signal controls CPU, PPU, DMA, cartridge, controller, NMI, system
bus, or framebuffer behavior. No pause, step, breakpoint, editor, graphics
viewer, audio, storage, boot menu, or mapper was added.

Work began from clean, upstream-synchronized Phase 4E-C commit
`b66100dff579e4446eaa584893417a90c227ae8b` and is isolated on
`phase4/devmode-pages`. It is not merged to `main`.

## Baseline

The unmodified Phase 4E-C baseline passed 1,182 Python tests, complete
Verilator lint, all retained CPU, ALU/addressing, PPU, DMA/NMI, VGA, Phase 4A
through Phase 4E-C, playable-ROM, combined-frame, normal-frame-hash, and
300-frame tests. The long run recorded 300 frames/snapshots, 297 NMIs, 297
DMA completions, and 297 controller polls.

The fresh baseline Quartus flow completed synthesis, fitting, assembly,
timing, and RBF generation with 17 warnings and no errors:

| Metric | Phase 4E-C baseline |
| --- | ---: |
| ALMs | 3,789 |
| logic ALUTs | 4,743 |
| route-through ALUTs | 826 |
| memory ALUTs | 590 |
| registers | 3,907 |
| M10Ks | 230 |
| MLAB bits | 18,880 |
| block-memory bits | 1,871,872 |
| DSPs / PLLs | 0 / 1 |
| worst setup slack | +0.942 ns |
| pixel/compositor setup slack | +1.168 ns |
| worst hold slack | +0.146 ns |
| setup / hold TNS | 0.000 / 0.000 ns |
| unconstrained setup / hold paths | 0 / 0 |

The baseline SOF was 6,690,502 bytes, SHA-256
`ed8719a12bb3a5a76c8ba7e1e03fb10a9a1ec2ba5492f800bc99004dea6ae30c`.
The baseline RBF was 7,007,204 bytes, SHA-256
`409f86e2eb0cde268c3e17b8da56ed1f68aee469929940588c805280ffae6505`.

## Page selection and frame-boundary latching

`nes_debug_page_select` is a small pixel-clock-domain state machine. Reset
selects Page 0. A one-cycle `page_next_request` advances
`0 -> 1 -> 2 -> 3 -> 4 -> 0`; `page_select_valid` supplies a direct
three-bit page request and has priority if both controls arrive together.
Out-of-range direct values sanitize to Page 0.

A request received during a VGA frame updates only `pending_page`. The
renderer-visible `active_page` changes at the next `frame_start`, so all
307,200 active pixels in a displayed frame use one page. A request coincident
with frame start commits on that boundary. Multiple queued next requests
advance from the pending value. Reset clears the pending flag and restores
Page 0 deterministically.

The current controls are retained internal registers intended for simulation,
future virtual input, or JTAG access:

- `developer_page_next_request`;
- `developer_page_select_valid`;
- `developer_page_request[2:0]`;
- observed `developer_page_active[2:0]` and request-pending status.

They have no physical board pin mapping. SW0 remains the color-bar selector,
SW1 remains framebuffer freeze, SW2-SW9 remain Controller 1, and KEY0 remains
active-low reset. The production image also retains
`DEVELOPER_MODE_DEFAULT=0`, so Developer Mode is hard-disabled unless an
integration build explicitly enables it. A future physical input must use a
separately specified GPIO, JTAG virtual input, or equivalent synchronized and
debounced source; existing controls must not be stolen.

## Shared renderer and layouts

One page-aware `nes_debug_panel_renderer` selects the character at the current
16-column by 30-row cell. All pages share the Phase 4E-B 6x8 ROM font, 8x16
cells, hexadecimal/status helpers, colors, snapshot unpacking, glyph stage,
and four-frame stale threshold. There are no page-specific snapshot banks,
live core taps, duplicate CDC paths, framebuffers, or separate renderer
modules. Every page shows one common `VALID`, `INVALID`, or `STALE` health
line and a title/index.

### Page 0: Overview — `OVERVIEW 1/5`

The at-a-glance page retains the Phase 4E-C summary: CPU PC, A/X/Y, SP,
status, opcode, run/stall and owner; PPU scanline/dot and key registers/status;
mapper/NROM/PRG/CHR/mirroring; compact PAD1 state; DMA activity/page/index and
count; source frame, snapshot ID, NMI count, and DMA count.

### Page 1: CPU/Bus — `CPU/BUS 2/5`

This page expands PC, A, X, Y, SP, status, opcode, current address, read data,
write data, read/write state, valid, run/stall, and bus owner. It also displays
the passively inferred CPU bus target and CPU/DMA ownership/access flags.

### Page 2: PPU/Cartridge — `PPU/CART 3/5`

The PPU portion shows scanline, dot, source frame/parity, PPUCTRL, PPUMASK,
PPUSTATUS, VBlank, NMI enable/pending/event, sprite-zero hit, sprite overflow,
pixel/palette information, coordinates, and validity. Cartridge rows show
presence, mapper, NROM-128/256, PRG address/data/access, CHR address/data/access,
mirroring, and CHR RAM/ROM state.

### Page 3: DMA/Controllers — `DMA/PAD 4/5`

DMA rows show active/idle, source page/address/data, OAM data, byte index,
phase, initiating parity, elapsed slots, read/write counts, completion event
and count, CPU stall, and owner. Controller rows show both live vectors,
latched shifts, serial indices, strobe, serial/read/latch events, and poll
count.

### Page 4: System/Performance — `SYSTEM 5/5`

The system page shows source frame, snapshot ID, NMI count, DMA completion
count, controller poll count, CPU-slot count, PPU-cycle count, PRG read count,
CHR read count, missed snapshot count, and common snapshot health.

## Compositor, game region, and normal mode

Only panel character selection depends on `active_page`. Developer Mode still
selects exact-2x NES pixels for `x=0..511` and panel pixels for `x=512..639`.
Directed checks cover x=0, 1, 510, 511, 512, 513, 638, and 639 at y=0 and
y=479. Changing a snapshot changes only the panel; changing game RGB changes
only the game region. Page changes cannot reach the game-pixel input or any
NES state.

With Developer Mode disabled, the final compositor still returns the existing
normal NES RGB directly. Page state cannot alter RGB, HSYNC, VSYNC, blanking,
pixel cadence, or the normal scaler. SW0 test pattern and SW1 game-framebuffer
freeze retain their Phase 4E-C priority and behavior; the panel can continue
to update while SW1 freezes the game image.

## Verification

The Python model supports all five pages from the same deterministic snapshot
fixture. `nes_debug_pages_tb` verifies reset, queued mid-frame requests,
boundary-only commit, direct-selection priority/sanitization, complete wrap,
one-page-per-frame behavior, health state, fixed geometry, and game-region
invariance. It writes an FST and five complete RGB traces. The independent
software renderer compares every one of the 307,200 active pixels on every
page: 1,536,000 compared pixels with zero mismatches.

| Page | RGB SHA-256 | PPM SHA-256 |
| --- | --- | --- |
| Overview | `a95bb32db832226873fbdcf9e88aad30cecb4d8002688b3c9a14080b0308beb0` | `053629a51a957510e159b403450804da78fc1399ca029c4fcb709253648e354d` |
| CPU/Bus | `9674c6bfc59c773451d5041aeb89028ac4eeaef6ea8509c73ea5656044cd23f0` | `2e031e9d8b9a8fc2aa6fa447b3bc74e8fa83730ceaa6b9c5bada3d47de587758` |
| PPU/Cartridge | `ed18e8216a6592cca856dd5f1b8bac84849d68ccc44a622cf254013698bb43ea` | `f29b8546ee58c6e548e1e1553ba045cb5d24b91870c90978d20234d0fdfe07c8` |
| DMA/Controllers | `851286645ac08ed59cfce6018c31a90f1d9dc6b08a8c5334c690f9521b1001e0` | `595706e1901b3ec07c15e0cb1d46b9ab15ba5e3cbff273ba9079d111954ac78d` |
| System/Performance | `de86566d6b24b50d6c538900c84490b4ea46c593ad851a25d97c731d102fa4c9` | `a6857edf39ef2cbd1a2f7906b64fc0d4d498f219e994b7314b84318c5f11a3f1` |

Each viewable PPM is 921,615 bytes under `build/sim/phase4ed_pages`. The
1,026,971-byte FST has SHA-256
`cc628d59296054fbc9954d14b183e78e59da17b688fe8d48915470eef069ce35`.

The real-ROM top-level integration deliberately issues ten mid-frame page-next
requests, traverses all pages twice, verifies pending/commit behavior, and
returns to Page 0. Gameplay and Right input move the real sprite from x=121 to
x=123. The sustained run records 83 source frames, 81 destination snapshot
updates, 80 NMIs, 80 DMA completions, 80 controller polls, 75 CPU-state
changes, ten page changes, and a 307,200-pixel real combined-frame comparison
with zero mismatches. Its RGB hash is
`29e2c9c42dc2f2d5f60b1ad8c8304f185b6cf97c7832677afee13d4582a2647e`;
the 921,615-byte PPM hash is
`f4e2799cc4a530d659d1b7afa7801b90088a75df8f82d2764bc3a34f2a97ce34`.

The retained 300-frame run reports 300 frames, 300 source captures, 300
destination updates, 297 NMIs, 297 DMA completions, and 297 controller polls.
All normal-mode RGB hashes remain exact:

| Fixture | SHA-256 |
| --- | --- |
| title | `e7707b93cddfbdfa148dffb38523d03013d2ff9a717981a416cb00078db05ae2` |
| post-Start | `a49d66d2e3a6662c3b8113f701f70a4dc44e932e05d18100c270de626f951e52` |
| A | `ffe9da19bfc93c2c717dd5dfb046ebe8cb7330503556e4a12deb6d24d54f8939` |
| B | `35bba0c5f1de0b9159cccd77e4f7a045cd4e103950fad1c35bc17101a27b14ba` |
| Select / Left / Down | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Right | `71d5e3a9e3268eddd86d5653fbb00ce16056fd73fbc6c1cf82b536cc2aacdb41` |
| Up | `83aaf2a6db7ad77d207c9cbad8293e4d2aa9f7e1b9379383aa989d2cd284d159` |

The final regression passes 1,184 Python tests, complete Verilator lint, all
retained CPU/ALU/addressing, PPU, DMA/NMI, VGA, Phase 4A through Phase 4E-C,
new Phase 4E-D selector/page/pixel tests, normal hashes, combined real-ROM
integration, page cycling, and the 300-frame run. Generated FST waveforms were
checked for nonzero size.

## Resources, timing, warnings, and artifacts

The five layouts share the renderer but expose substantially more snapshot
fields through a larger combinational character selector. The page selector
itself is only a few registers; no RAM or DSP was added. Final fitted results
are:

| Metric | Phase 4E-C | Phase 4E-D | Change |
| --- | ---: | ---: | ---: |
| ALMs | 3,789 | 4,702 | +913 |
| logic ALUTs | 4,743 | 6,167 | +1,424 |
| route-through ALUTs | 826 | 602 | -224 |
| memory ALUTs | 590 | 590 | 0 |
| registers | 3,907 | 3,944 | +37 |
| M10Ks | 230 | 230 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| block-memory bits | 1,871,872 | 1,871,872 | 0 |
| DSPs / PLLs | 0 / 1 | 0 / 1 | 0 / 0 |

The first automatic-effort fit placed the expanded design poorly and reported
-0.408 ns setup slack on an existing CLOCK_50-domain CPU/PPU path; the actual
renderer pixel path still passed. Setting the production project to Quartus
Standard Fit enabled timing-driven placement. The clean final full flow has
+0.073 ns worst setup slack, +0.151 ns worst hold slack, zero setup/hold TNS,
and no unconstrained setup or hold paths. The pixel/compositor clock domain
has +1.147 ns setup slack. The overall critical path has 19.376 ns data delay
from CPU `debug_addressing_mode[2]~DUPLICATE` to sprite-renderer
`pattern_high[1][0]`; it is not the panel/compositor pixel path.

Quartus completes synthesis, fitter, assembler, timing, and RBF conversion
with zero errors and 17 warnings. The audited warnings are the existing
unused-status aggregation, tied-off inferred-ROM write ports, connectivity
summary, intentional constant VGA_SYNC_N, subscription-only LogicLock notice,
incomplete-I/O summary, PLL compensation notice, and two obsolete unmatched
IRQ synchronizer filters repeated by fitter/timing. No page-specific warning
category appears.

The final SOF is 6,690,502 bytes, SHA-256
`82fa878a8e150f135275f2c1e0ec09411a7ccb1907b64fdb6c4286ce0ef10501`.
The final RBF is 7,007,204 bytes, SHA-256
`61997f585c53848c32e0cd56f18600b24cf3679c27e905ddd9935928d5041946`.

Neither artifact was programmed onto physical hardware, so Phase 4E-D makes
no hardware-validation claim.

## Exact Phase 4E-E recommendation

Retain the snapshot, CDC, page latch, renderer, compositor, and board-control
mappings. Add a dedicated synchronized command/status block reached through
JTAG virtual input or a separately assigned GPIO interface. It should debounce
or edge-detect run/pause, instruction-step, and frame-step commands, cross them
into the 50 MHz NES domain with request/acknowledge handshakes, and expose the
acknowledged debugger state back through the coherent snapshot.

Pause must be accepted only at a documented architectural boundary. For CPU
pause, finish the current instruction and define DMA priority explicitly;
the safest first policy is to let an active OAM DMA finish atomically before
acknowledging pause. Frame pause should stop only at the established PPU frame
boundary. Instruction and frame steps should consume one queued token and
return to paused state with an acknowledgment/counter, preventing repeated or
lost commands. Page navigation remains a video-domain diagnostic control and
must never double as execution control. Add assertions for no partial
instruction, no truncated DMA, exactly one action per step token, stable VGA
while paused, and unchanged run-mode frame hashes.
