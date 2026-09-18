# Phase 3A NTSC PPU timing foundation

## Objective and scope

Phase 3A adds a standalone, cycle-accurate NTSC NES PPU timing engine on top of
the verified Phase 2K repository. It establishes the coordinates, regions,
vblank state, frame parity, and odd-frame shortening that later PPU logic will
consume. It does not integrate the PPU with the CPU or make a complete PPU.

The Phase 2 CPU RTL is unchanged. The new core is also separate from the Phase
1 board image, so existing platform and CPU build targets retain their prior
top-level hierarchy.

## Architecture

`rtl/ppu/ppu_timing.sv` is a single-clock synchronous module. Its inputs are:

- `clk`: the common fabric clock;
- `reset`: synchronous active-high reset;
- `ppu_enable`: one enabled PPU timing tick on a fabric edge; and
- `rendering_enabled`: the future PPUMASK-derived odd-frame-skip control.

There is no generated, divided, or gated PPU clock. Reset has priority and
establishes scanline 0, dot 0, even-frame parity, and cleared vblank. Outside
reset, `dot`, `scanline`, `frame_odd`, and `vblank` change only on an edge for
which `ppu_enable` is high. They remain stable through any number of stalls.

`dot` and `scanline` describe the coordinate consumed on the next enabled
edge. Pulse-like outputs (`visible_pixel`, `frame_start`, `frame_end`,
`scanline_start`, `vblank_start`, and `vblank_end`) are combinational
qualifiers of that current coordinate, `ppu_enable`, and inactive reset. They
are therefore false during enable stalls. `pre_render` and `post_render` are
coordinate-region levels and `vblank` is stored timing state.

## NTSC timing convention

Normal frames contain 262 scanlines numbered 0 through 261. A normal scanline
contains 341 dots numbered 0 through 340.

| Region | Scanlines | Meaning |
|---|---:|---|
| Visible | 0-239 | 240 output rows |
| Post-render | 240 | idle separator after visible output |
| Vblank | 241-260 | vertical blanking interval |
| Pre-render | 261 | state preparation for the next frame |

Visible pixels are valid on scanlines 0 through 239 at dots 1 through 256.
The coordinate mapping is `pixel_x = dot - 1`, `pixel_y = scanline`, yielding
X 0-255 and Y 0-239. A complete frame therefore has exactly 61,440
`visible_pixel` events. Outside that geometric region, `pixel_x` and `pixel_y`
are driven to zero and `visible_pixel` is false.

The coordinate/event relationship is:

```text
scanline 0:    dot 0 | dots 1................256 | 257.........340
                       visible pixels x=0..255
scanline 240:  post-render
scanline 241:  dot 0 | dot 1: vblank set/start | ...
scanline 261:  dot 0 | dot 1: vblank clear/end | ... | frame end
next frame:    scanline 0, dot 0: frame start
```

`scanline_start` identifies enabled dot 0. `frame_start` identifies enabled
scanline 0, dot 0. `frame_end` identifies the enabled terminal coordinate:
normally scanline 261, dot 340, or scanline 261, dot 339 for a shortened odd
rendered frame.

## Vblank timing

The stored `vblank` level becomes asserted while entering scanline 241, dot 1
and becomes cleared while entering pre-render scanline 261, dot 1. Thus the
level already has its new value when either coordinate is presented:

- `vblank_start` is asserted once at scanline 241, dot 1 and `vblank` is high;
- `vblank_end` is asserted once at scanline 261, dot 1 and `vblank` is low.

These precise event outputs are intended for later PPU register/NMI logic.
Phase 3A does not implement PPUSTATUS read effects, NMI enable, or NMI
suppression races.

## Even/odd frames and skipped cycle

Reset starts an even frame (`frame_odd = 0`). Parity toggles only when the
current frame wraps to scanline 0, dot 0, exactly once per frame.

With `rendering_enabled = 0`, both parities execute scanline 261, dots 339 and
340. Every frame is therefore `341 * 262 = 89,342` enabled PPU ticks.

With `rendering_enabled = 1`, even frames remain 89,342 ticks. On an odd frame,
the enabled tick at scanline 261, dot 339 transitions directly to scanline 0,
dot 0 and toggles parity. Scanline 261, dot 340 is absent, producing an 89,341
tick odd frame. The skip decision is sampled from `rendering_enabled` at the
terminal enabled edge; PPUMASK itself is deferred.

## Independent reference and verification

`verification/ppu_timing.py` models a frame as a linear behavioral position
and derives scanline/dot coordinates from it. This is intentionally different
from the RTL's nested dot/scanline counter structure. The Python unit tests
prove frame geometry, coordinates, region transitions, vblank state/events,
parity, frame lengths, and the enabled-cycle equivalence of a 12-frame random
stall run.

`scripts/generate_ppu_timing_vectors.py` uses the independent model to create
an ignored build artifact consumed by `sim/ppu_timing_tb.sv`. The RTL testbench
checks every output on every fabric cycle and includes assertions for:

- dot and scanline ranges;
- exact state and event agreement with the Python model;
- stable dot, scanline, parity, and vblank through disabled edges;
- no event pulse during a stall;
- exact visible coordinates and invalid-region zeroing;
- legal normal wraps and explicit odd-rendered `261:339 -> 0:0` wraps;
- explicit `261:339 -> 261:340` progression on disabled-render odd frames;
- exact once-per-frame start/end and vblank event counts.

The deterministic RTL/reference workload uses seed `0x003A5EED` and covers:

| Scenario | Frames | Fabric cycles | Enabled ticks | Stalls | Visible events |
|---|---:|---:|---:|---:|---:|
| Rendering disabled | 2 | 178,687 | 178,684 | 0 | 122,880 |
| Rendering enabled, directed | 4 | 357,369 | 357,366 | 0 | 245,760 |
| Rendering enabled, randomized stalls | 6 | 800,395 | 536,049 | 264,343 | 368,640 |
| **RTL total** | **12** | **1,336,451** | **1,072,099** | **264,343** | **737,280** |

The additional Python randomized-stall test covers 12 rendered frames across
1,599,240 fabric cycles, including 527,142 stalls.

The completed regression contains 476 passing Python tests. The Phase 3A RTL
test and every retained Phase 1 and Phase 2A-2K simulation pass. Existing
exhaustive ALU (591,876 vectors) and address-generator (1,508,186 vectors)
coverage is unchanged. Verilator 5.032 reports clean PPU and project lint.

Post-change preservation builds also pass: standalone CPU synthesis remains
717 ALMs/1,097 ALUTs/191 registers, the unchanged Phase 1 board image completes
fitting and timing, and the unchanged Phase 2K diagnostic reproduces 3,244
ALMs/3,620 ALUTs/4,617 registers with +1.454 ns setup and +0.168 ns hold slack.
Phase 2K LED/HEX observation is still outstanding, so this is not a claim of
completed physical Phase 2K hardware validation.

The normal `scripts/test.sh` entry point automatically runs the Python tests,
all lint targets, generates the reference trace, and executes every RTL test.
The existing GitHub Actions workflow invokes that entry point, so Phase 3A is
covered without replacing or weakening prior CI checks.

## Standalone synthesis

`scripts/build_ppu_quartus.sh` compiles the standalone timing core for the
Cyclone V `5CSEMA5F31C6`. The proof uses the existing 50 MHz fabric-clock
period; non-clock standalone ports are virtual because this is not a board
image. All internal register-to-register paths remain timed. No PLL is used.

Quartus Prime Lite 23.1.1 analysis, synthesis, fitting, assembly, and
multi-corner timing analysis pass with:

- 66 ALMs out of 32,070;
- 73 combinational ALUTs;
- 20 registers;
- 0 block-memory bits and 0 RAM blocks;
- 0 DSP blocks;
- 0 PLLs;
- worst setup slack +16.230 ns, setup TNS 0;
- worst hold slack +0.172 ns, hold TNS 0; and
- worst minimum-pulse-width slack +9.070 ns.

The core is correspondingly small relative to the target device.
The sole PPU-project compiler warning is Quartus Lite's expected LogicLock
subscription notice; the design has no LogicLock assignment. Informational
messages identify the intentionally virtual standalone observation ports.

## Limitations

Phase 3A implements timing only. It has no background tile renderer, sprites,
OAM, CHR ROM/RAM, nametable RAM, palette RAM, PPUSCROLL, PPUADDR, PPUDATA,
complete `$2000-$2007` register interface, PPUSTATUS side effects, NMI behavior,
VGA, HDMI, framebuffer, cartridge mapper, APU, or full CPU/PPU integration.
It does not establish the final physical NES pixel frequency; it consumes the
Phase 1 clock-enable contract and remains in the common FPGA clock domain.

## Next recommended phase

Phase 3B should build the CPU-visible PPU register and vblank/NMI control layer
around these timing/event outputs while preserving the timing core as an
independently verified module.
