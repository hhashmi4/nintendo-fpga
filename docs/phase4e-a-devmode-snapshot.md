# Phase 4E-A Developer Mode snapshot foundation

## Scope and status

Phase 4E-A adds the read-only state path needed by a future graphical Developer
Mode. It does not add a panel, overlay, pause, stepping, breakpoints, editors,
memory viewers, save states, audio, loading, a boot menu, HDMI, or another
mapper. The snapshot logic has no output connected to CPU, PPU, DMA,
cartridge, controller, system-bus, framebuffer, or NES-pixel control.

The data flow is:

```text
NES core and peripherals
  -> passive observation wires in the 50 MHz system domain
  -> grouped coherent source snapshot at NES frame start
  -> stable bundled data plus request/acknowledge toggles
  -> pending copy in the 25.2 MHz VGA domain
  -> renderer-facing copy committed at VGA frame start
  -> future Phase 4E-B renderer
```

The previously validated Phase 4D-B playable image is the functional baseline.
Phase 4E-A has not been programmed onto physical hardware, so this document
does not claim physical validation of the new snapshot layer.

## Repository and baseline

Work began with a clean, upstream-synchronized
`phase4/playable-rom-validation` branch at commit
`7c56f362f4e195871d6f9056dfd6ee5f724b1c21` (`Validate playable NROM
through the NES VGA path`). Development is isolated on
`phase4/devmode-snapshot` and is not merged to `main`.

The host's system Python lacked pytest, so the documented repository-local
`.venv` was placed first on `PATH`; no source change or dependency download was
needed. The clean baseline then passed 1,170 Python tests, full Verilator lint,
all retained CPU/ALU/addressing, PPU, NMI/DMA, VGA, Phase 4A bus, Phase 4B
cartridge, Phase 4C controller, Phase 4D-A DMA, and Phase 4D-B playable tests.
The 300-frame playable run reported 297 NMIs, 297 completed DMAs, and 297
controller polls. The cartridge-to-VGA comparison checked all 307,200 active
pixels with zero mismatch.

The fresh Phase 4D-B baseline board build completed synthesis, fitting,
assembly, timing, and RBF generation with these results:

| Metric | Phase 4D-B baseline |
| --- | ---: |
| ALMs | 2,879 |
| logic ALUTs | 3,297 |
| memory ALUTs | 590 |
| registers | 1,239 |
| M10Ks | 230 |
| block-memory bits | 1,871,872 |
| MLAB bits | 18,880 |
| DSPs / PLLs | 0 / 1 |
| worst setup slack | +0.525 ns |
| worst hold slack | +0.145 ns |
| setup / hold TNS | 0.000 / 0.000 ns |
| unconstrained setup / hold paths | 0 / 0 |

## Snapshot data structure

`nes_debug_snapshot_pkg` defines six packed groups and one aggregate packed
type. The aggregate is 711 bits. Declaration order is also the serialized
packing order used by the independent Python model: CPU first at the most
significant end, followed by PPU, cartridge, controller, DMA, and system.

### CPU group: 102 bits

| Field | Bits | Meaning |
| --- | ---: | --- |
| `pc` | 16 | current architectural program counter |
| `a`, `x`, `y`, `sp`, `status` | 8 each | architectural registers |
| `opcode` | 8 | CPU core's existing debug instruction register |
| `address` | 16 | current CPU-side bus address |
| `read_data`, `write_data` | 8 each | current CPU bus data |
| `read`, `write`, `bus_valid` | 1 each | current transaction qualifiers |
| `stalled` | 1 | DMA-owned CPU stall |
| `bus_owner` | 2 | encoded internal bus owner |

The opcode connection only exposes an existing `cpu_core` debug signal; CPU
execution is unchanged.

### PPU group: 92 bits

| Field | Bits | Meaning |
| --- | ---: | --- |
| `scanline`, `dot` | 9 each | PPU timing position at capture |
| `frame_odd` | 1 | PPU frame parity |
| `ctrl`, `mask`, `status` | 8 each | PPUCTRL, PPUMASK, and status flags |
| `pixel_x`, `pixel_y` | 8 each | current visible-pixel coordinates |
| `palette_address` | 14 | current PPU palette/memory output address |
| `pixel_color` | 6 | NES palette color |
| `pixel_emphasis` | 3 | emphasis metadata |
| `pixel_source` | 2 | universal/background/sprite selection |
| `pixel_valid` | 1 | current pixel qualifier |
| `nmi_enabled`, `nmi_level` | 1 each | PPUCTRL enable and current NMI condition |
| `nmi_event`, `nmi_suppressed` | 1 each | sticky events since the prior snapshot |
| `vblank`, `sprite_zero_hit`, `sprite_overflow` | 1 each | status flags |

`status[7:5]` mirrors VBlank, sprite-zero hit, and sprite overflow; the lower
five debug-only status bits are zero. `source_frame_number` in the system group
provides the full frame indication.

### Cartridge group: 61 bits

| Field | Bits | Meaning |
| --- | ---: | --- |
| `present` | 1 | cartridge present |
| `mapper_number` | 8 | selected mapper, currently zero |
| `nrom_256` | 1 | 32 KiB rather than mirrored 16 KiB PRG |
| `prg_address`, `prg_data` | 15 / 8 | mapped PRG observation |
| `prg_read`, `prg_write` | 1 each | PRG access strobes |
| `chr_address`, `chr_data` | 13 / 8 | mapped CHR observation |
| `chr_read`, `chr_write` | 1 each | CHR access strobes |
| `chr_is_ram` | 1 | CHR RAM/ROM selection |
| `mirroring` | 2 | cartridge nametable mirroring mode |

### Controller group: 46 bits

| Field | Bits | Meaning |
| --- | ---: | --- |
| `live1`, `live2` | 8 each | synchronized live button vectors |
| `shift1`, `shift2` | 8 each | latched serial shift registers |
| `index1`, `index2` | 4 each | saturating serial read indices |
| `strobe` | 1 | current `$4016` strobe state |
| `serial1`, `serial2` | 1 each | current controller data pins |
| `read_4016`, `read_4017` | 1 each | sticky read events since prior snapshot |
| `latch_event` | 1 | sticky high-to-low poll/latch event |

### DMA group: 90 bits

| Field | Bits | Meaning |
| --- | ---: | --- |
| `active` | 1 | DMA owns or is acquiring the bus |
| `source_page` | 8 | `$4014` page |
| `source_address` | 16 | current source address |
| `source_data` | 8 | current source read data |
| `byte_index` | 8 | byte number `$00-$FF` |
| `oam_data` | 8 | data presented to OAM |
| `phase` | 3 | DMA sequencer phase |
| `started_odd` | 1 | initiating CPU-slot parity |
| `elapsed_slots` | 10 | elapsed DMA CPU slots |
| `read_count`, `write_count` | 9 each | current transfer counts |
| `cpu_stall` | 1 | CPU stall state |
| `bus_owner` | 2 | current internal bus owner |
| `start_event`, `read_event`, `write_event` | 1 each | live event pulses at capture |
| `complete_event` | 1 | sticky completion since prior snapshot |
| `dummy_cycle`, `alignment_cycle` | 1 each | current startup phase qualifiers |

### System group: 320 bits

All ten fields are unsigned wrapping 32-bit counters:

- `snapshot_id`: increments on every accepted automatic or manual capture;
- `source_frame_number`: increments on each NES `ppu_frame_start`;
- `nmi_count`: PPU NMI events;
- `dma_count`: DMA completions;
- `controller_poll_count`: controller latch/poll events;
- `cpu_slot_count`: scheduled CPU slots, including DMA-owned slots;
- `ppu_cycle_count`: enabled PPU cycles;
- `prg_read_count` and `chr_read_count`: observed cartridge reads;
- `missed_capture_count`: requested captures rejected while the prior source
  bank is awaiting acknowledgement.

No RAM is inferred for the snapshot. The counters and banks are ordinary
registers, avoiding M10K consumption for a small, low-bandwidth debug path.

## Capture semantics

The automatic source event is the existing `ppu_frame_start`, at scanline 0,
dot 0. It occurs once per complete NES frame in the 50 MHz fabric domain, where
the NES itself advances through clock enables. On an accepted capture, all 711
bits are copied into one source register bank on the same edge, `snapshot_id`
increments, and the request toggle changes. The source bank cannot change
again until the destination acknowledgement returns.

NMI, NMI-suppression, controller-read/latch, and DMA-completion pulses can
occur far from frame start, so sticky interval flags preserve them through the
next accepted capture. Counters include an event coincident with the capture
edge. The source snapshot remains stable between accepted captures.

The module also has a `manual_capture` input. It uses the identical coherence
and CDC path and increments `snapshot_id`, but does not increment
`source_frame_number`. The production top ties it low in this phase; no button
or switch is assigned.

## Clock-domain crossing

The domains are physically different: the source is `CLOCK_50`; the
destination is the PLL-derived approximately 25.2 MHz `pixel_clk`. Clock
enables do not make the VGA logic part of the system clock domain.

The multi-bit payload is not synchronized bit by bit. Instead:

1. the source captures and holds the entire packed bank;
2. a request toggle crosses through a three-stage destination synchronizer;
3. after detecting the synchronized toggle, the destination samples the
   already-stable bundled bus into a pending bank and mirrors the toggle as
   acknowledgement;
4. acknowledgement crosses through a two-stage source synchronizer;
5. only then may the source accept and overwrite the bank;
6. the pending bank is committed to the renderer-facing bank only on
   `vga_frame_start`.

The control synchronizers carry forced-asynchronous Quartus identification
attributes. The board SDC already declares the system and PLL video clocks
as asynchronous; coherence therefore comes from the deliberately stable
bundled-data protocol, not from false per-bit timing assumptions. There is no
CDC deadlock at normal frame cadence: an NES frame is vastly longer than the
five synchronizer stages and acknowledgement round trip.

This two-bank destination arrangement is intentional. Receipt may occur at
any pixel, but the future renderer's visible bank changes only at a VGA frame
boundary and remains constant for the complete display frame.

## Developer Mode enable and board controls

All ten slide switches are already assigned by the playable board image:

- `SW0`: VGA color-bar/test-pattern selector;
- `SW1`: stop starting new framebuffer captures while scanout keeps the last
  completed frame;
- `SW2-SW9`: Controller 1 A, B, Select, Start, Up, Down, Left, Right.

Consequently Phase 4E-A does not silently steal a controller switch. The top
contains an internal `developer_mode_enable` reserved for the renderer and
ties it low. Phase 4E-B must choose an explicit non-conflicting control before
making Developer Mode user-selectable.

`KEY0` remains the only reset button. It is active low: pressing KEY0 asserts
the PLL reset and the common asynchronous reset request; releasing it permits
synchronized reset deassertion in both clock domains.

## Verification

### Independent Python model

`verification/debug_snapshot.py` independently declares every group/field
width, packs and unpacks the 711-bit representation, rejects out-of-range
values, and models 32-bit counter and capture-ID behavior. Four pytest cases
check the six group totals, complete round-trip packing, field boundaries,
300-frame sequence/counter cadence, and rejected-capture accounting.

### Focused RTL test

`nes_debug_snapshot_tb` uses unrelated 10 ns and 14 ns clocks and writes
`build/sim/nes_debug_snapshot.fst`. It verifies:

- no destination update before a source capture;
- one destination update per accepted source snapshot;
- full CPU, PPU, cartridge, controller, and DMA group equality;
- sticky event and counter inclusion on the capture edge;
- no tearing after every live observation changes immediately after capture;
- source stability while a transfer is busy;
- renderer-bank stability after receipt and before the next VGA frame;
- monotonic snapshot IDs and distinct frame/manual-capture semantics;
- reset clearing of the handshake, validity, payload, stickies, counters, and
  sequence, followed by a successful fresh transfer.

The test passes with four accepted captures and four destination updates.

### Playable-ROM integration and long run

The Phase 4D-B playable test instantiates the real snapshot layer with an
asynchronous debug clock. Over 300 frames it reported:

| Counter | Result |
| --- | ---: |
| source captures / destination updates | 300 / 300 |
| missed captures | 0 |
| NMI events / snapshot NMI count | 297 / 297 |
| DMA completions / snapshot DMA count | 297 / 297 |
| controller polls / snapshot poll count | 297 / 297 |
| DMA reads / writes | 76,032 / 76,032 |
| `$4016` reads | 2,376 |
| final snapshot PRG reads | 7,281,979 |
| final snapshot CHR reads | 11,983,656 |
| final CPU PC / SP | `$80A5` / `$FF` |

Assertions require IDs 1 through 300 without duplication, scanline/dot 0/0
for every automatic source capture, coherent status flags, valid Mapper 0
metadata, matching CPU/DMA bus ownership and stall state, changing CPU values,
observed controller input `$50`, controller and cartridge activity, and a DMA
completion. Gameplay continued throughout; there was no snapshot or CDC
deadlock and no functional feedback into the NES.

### Normal-mode frame invariants

The snapshot-enabled run reproduced every Phase 4D-B FPGA PPU hash exactly:

| Milestone | SHA-256 |
| --- | --- |
| title | `e7707b93cddfbdfa148dffb38523d03013d2ff9a717981a416cb00078db05ae2` |
| after Start | `a49d66d2e3a6662c3b8113f701f70a4dc44e932e05d18100c270de626f951e52` |
| A | `ffe9da19bfc93c2c717dd5dfb046ebe8cb7330503556e4a12deb6d24d54f8939` |
| B | `35bba0c5f1de0b9159cccd77e4f7a045cd4e103950fad1c35bc17101a27b14ba` |
| Select | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Right | `71d5e3a9e3268eddd86d5653fbb00ce16056fd73fbc6c1cf82b536cc2aacdb41` |
| Left | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Up | `83aaf2a6db7ad77d207c9cbad8293e4d2aa9f7e1b9379383aa989d2cd284d159` |
| Down | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |

Developer Mode is tied disabled and no output mux or overlay exists, so the
normal VGA pixel path remains the Phase 4D-B path by construction as well as
by hash evidence.

### Complete retained regression

The final canonical `scripts/test.sh` run passed all 1,174 Python tests, full
project Verilator lint, and every retained and new RTL simulation. This
includes CPU/ALU/addressing and Phase 2D-2K, every PPU stage, Phase 3J system
and scheduled NMI, Phase 3K timing/framebuffer/CDC/VGA, Phase 4A exhaustive
bus decode, Phase 4B Mapper 0 and boot, Phase 4C standalone/integrated
controllers, Phase 4D-A standalone/arbiter/integrated DMA and DMA/NMI, Phase
4D-B playable/VGA, and Phase 4E-A snapshot tests. Both final 640x480 VGA
reference comparisons covered 307,200 active pixels with zero mismatch.

## Quartus resources, timing, artifacts, and warnings

Final Phase 4E-A implementation results are recorded here after the complete
build and compared with the fresh Phase 4D-B baseline above.

| Resource | Phase 4D-B baseline | Phase 4E-A | Change |
| --- | ---: | ---: | ---: |
| ALMs | 2,879 | 3,388 | +509 |
| logic ALUTs | 3,297 | 3,971 | +674 |
| memory ALUTs | 590 | 590 | 0 |
| registers | 1,239 | 3,801 | +2,562 |
| M10Ks | 230 | 230 | 0 |
| block-memory bits | 1,871,872 | 1,871,872 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| DSPs / PLLs | 0 / 1 | 0 / 1 | 0 / 0 |

The complete design occupies 11% of device ALMs. The additional registers are
expected: three coherent 711-bit banks account for 2,133 bits, and the ten
32-bit system counters account for another 320. Handshake, sticky-event, and
valid state plus packing logic make up the remainder. Despite retaining the
complete future interface, the layer adds no block or distributed RAM. Logic
ALUT use increased by 674, primarily for counters and capture muxing. This is
an explicit register-for-coherence tradeoff; direct high-fanout live taps or
per-bit CDC synchronizers were rejected.

| Timing metric | Phase 4D-B baseline | Phase 4E-A | Change |
| --- | ---: | ---: | ---: |
| worst setup slack | +0.525 ns | +1.134 ns | +0.609 ns |
| worst hold slack | +0.145 ns | +0.149 ns | +0.004 ns |
| setup TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| hold TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| unconstrained setup / hold paths | 0 / 0 | 0 / 0 | 0 / 0 |

The snapshot did not create a failing path, and the worst path is not in the
debug layer. It is in the 50 MHz NES logic at the slow 1100 mV, 85 C corner,
from duplicated CPU execution-state logic to PPU `$2007` read-buffer state. It
has 17 logic levels, 18.251 ns data delay, -0.445 ns clock skew, a 20.000 ns
relationship, and +1.134 ns slack. The worst hold result across all corners is
+0.149 ns at fast 1100 mV, 0 C. Timing is fully constrained; all setup/hold
TNS values and unconstrained-path counts are zero. TimeQuest recognized 21
synchronizer chains with no uncalculated MTBF entries.

The full flow completed with zero errors and 17 warnings, the same total as
the fresh baseline. They remain the understood categories from Phase 4D-B:
constant/read-only ROM write inputs, the intentionally consumed passive
status network and constant `VGA_SYNC_N`, incomplete noncritical board I/O
assignments, the Lite-edition LogicLock notice, default PLL compensation, and
two unmatched IRQ synchronizer exceptions because board IRQ is tied inactive.
There is no inferred-latch, multiple-driver, RAM-initialization, CDC, or timing
failure. The only snapshot-specific CDC result is the additional recognized
toggle synchronizer chains.

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `build/quartus_de1_soc_nes_vga/output_files/de1_soc_nes_vga.sof` | 6,690,502 bytes | `8d68116a1a48c4036e3d29c767ebda5c9fca03058011235eeeaab6fd3c678263` |
| `build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf` | 7,007,204 bytes | `d1cecd47403ba7c412a2cca2a2243b9d07181436b6be645d9f161153d198bcbd` |

No Phase 4E-A FPGA programming was performed. SOF/RBF generation is a build
result, not physical-hardware validation.

## Files

Created:

- `rtl/debug/nes_debug_snapshot_pkg.sv`;
- `rtl/debug/nes_debug_snapshot.sv`;
- `sim/nes_debug_snapshot_tb.sv`;
- `verification/debug_snapshot.py`;
- `tests/python/test_debug_snapshot.py`;
- this document.

Modified:

- `rtl/nes_core.sv` to expose its existing passive opcode observation;
- `rtl/de1_soc_nes_vga_top.sv` to assemble and transfer observations;
- `sim/nes_phase4db_playable_tb.sv` for real-ROM snapshot integration;
- `sim/nes_vga_phase4db_tb.sv` for the added passive core port;
- `scripts/sim.sh`, `scripts/lint.sh`, and
  `scripts/test.sh`, plus `quartus/de1_soc_nes_vga.qsf`, to retain the new
  checks/build inputs;
- `README.md`.

Generated waveforms, extracted cartridge files, frames, reports, SOF, and RBF
remain under ignored `build/` paths.

## Exact Phase 4E-B recommendation

Keep `nes_debug_snapshot` and the NES core unchanged. Add a dedicated
pixel-domain `developer_debug_renderer` that consumes only
`debug_destination_snapshot`, `debug_destination_valid`, and the chosen
Developer Mode enable. Compose its output after the existing framebuffer
pixel/palette/scaler path, never by feeding state or control back into the NES.

Use the stable snapshot for a compact first panel containing snapshot/frame
IDs; CPU PC/A/X/Y/SP/P/opcode and bus transaction; PPU scanline/dot/parity,
CTRL/MASK/STATUS and NMI flags; mapper/mirroring plus PRG/CHR observations;
both controller live/shift/index states; DMA phase/page/index/data/counts/owner;
and system counters. Render an explicit `STALE` indication when
`destination_valid` is false or `snapshot_id` stops advancing.

Because SW0 is color bars, SW1 is framebuffer freeze, and SW2-SW9 are the
controller, do not repurpose any of them silently. Prefer an explicitly
documented alternate input or revise the board UI as a deliberate user-facing
mapping change. Preserve a hard normal-mode bypass whose RGB/HSYNC/VSYNC/
blanking outputs are bit-for-bit the current path; retain the nine hashes and
add panel-enabled VGA reference hashes. Phase 4E-B should still be read-only:
pause, stepping, breakpoints, and editors remain later phases.
