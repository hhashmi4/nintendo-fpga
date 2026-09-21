# Phase 4D-B playable Mapper 0 ROM validation

## Status

The project-owned playable NROM image is qualified in simulation through the
real CPU, PPU, controller, cartridge, OAM DMA, framebuffer, palette, scaler,
and VGA paths. The final Quartus image passes synthesis, fitting, assembly,
and timing. Physical programming and visual/input validation remain pending:
the build host had no accessible USB-Blaster or JTAG chain on 2026-09-21.

The evidence boundary is therefore:

- **SIMULATION PASS**
- **PHYSICAL HARDWARE NOT YET VALIDATED**

No audio, additional mapper, loader, menu, developer overlay, USB-controller,
physical-cartridge, or save-state feature was added.

## Repository and baseline

Work began from clean commit
`1f15ab1402d145d8c808095c8645bd5b266eb9db` (`Extract Phase 4D-A OAM DMA
bus master`) on `phase4/oam-dma-bus-master`. Development is on
`phase4/playable-rom-validation`; it is not merged to `main`.

Before any source change, the repository-local virtual environment ran the
complete `scripts/test.sh` suite. All 1,168 Python tests, Verilator lint, and
all retained CPU, PPU, NMI, DMA, VGA, Phase 4A bus, Phase 4B cartridge, Phase
4C controller, and Phase 4D-A tests passed. The standalone Phase 4D-A test
transferred six complete pages (1,536 reads and 1,536 writes), the integrated
DMA test completed three transfers, and the DMA/NMI test observed four NMI
pulses and four handler entries. Phase 4A checked 131,072 direction/address
vectors, Phase 4B checked 65,536 PRG and 16,384 CHR reads, Phase 4C performed
7,251 protocol checks, and both full VGA comparisons covered 307,200 pixels
without mismatch.

The fresh baseline board build reported:

| Metric | Phase 4D-A baseline |
| --- | ---: |
| ALMs | 2,906 |
| logic ALUTs | 3,329 |
| memory ALUTs | 590 |
| registers | 1,229 |
| M10Ks | 230 |
| block-memory bits | 1,871,872 |
| MLAB bits | 18,880 |
| DSPs | 0 |
| PLLs | 1 |
| worst setup slack | +1.084 ns |
| worst hold slack | +0.118 ns |
| setup / hold TNS | 0.000 / 0.000 ns |
| unconstrained setup / hold paths | 0 / 0 |

## Playable ROM and license

`roms/phase4db_playable_nrom128.nes` is a small game written specifically for
this project and licensed under the MIT license in `roms/LICENSE`. Its Python
source generator, tiles, and resulting binary contain no commercial Nintendo
program or graphic data.

| Property | Value |
| --- | --- |
| name | Nintendo FPGA Phase 4D-B playable demo |
| format | iNES 1.0 |
| source/license | this repository / MIT |
| image SHA-256 | `307007ec66a59b6893b9c6530db563b9c1950d5372492eeaf98a7e299b0667a9` |
| mapper / board | 0 / NROM-128 |
| PRG ROM | 16,384 bytes, SHA-256 `293a0e0b50316e82c1af16d84325a4c8457d5cad3a44ae35083f3f831da28138` |
| CHR ROM | 8,192 bytes, SHA-256 `5b644c74a388365f4011df8875f6670f2b34da140bc6d2d8d79f00fdb0edfe88` |
| CHR RAM | no |
| mirroring | horizontal (`mirroring_mode=1`) |
| NMI / reset / IRQ-BRK vectors | `$9000` / `$8000` / `$9100` |

The title state shows a tiled background. Start reveals the player. The D-pad
moves it by two pixels per poll with hard screen bounds; A and Select choose
visible palettes, and B chooses a visibly different sprite tile. Audio is not
required. The NMI handler updates the OAM source page and triggers page-$02
OAM DMA once per gameplay frame.

## Reproducible import and board build

The complete source path is:

```text
Python game/CHR source
  -> project-owned .nes
  -> strict iNES parser and validation
  -> PRG/CHR extraction plus derived JSON metadata
  -> readmemh initialization files
  -> Mapper 0 cartridge
  -> Quartus SOF and RBF
```

Build the selected image with one command:

```bash
source .venv/bin/activate
./scripts/build_de1_soc_nes_vga_quartus.sh
```

The build script regenerates a temporary ROM and byte-compares it with the
committed image before calling `scripts/prepare_phase4db_cartridge.py`. The
preparer uses the existing Phase 4B importer. It deterministically rejects a
nonzero mapper, a PRG size other than 16 KiB, a CHR size other than 8 KiB, CHR
RAM, non-horizontal mirroring, a malformed/truncated iNES image, or any vector
outside `$8000-$FFFF`. Generated PRG/CHR files are never hand edited.

## Simulation evidence

`nes_phase4db_playable_tb` records reset reads `$FFFC=00` and `$FFFD=80`, the
initial PC `$8000`, the first sixteen PRG bus reads, the RAM initialization
marker, PPUCTRL/PPUMASK initialization, first nametable and palette writes,
first controller poll, VBlank/NMI handler entries, and DMA starts. The boot
checks also require CIRAM tile 0 to equal `$01`, palette entry 0 to equal
`$0F`, `PPUCTRL=$80`, and `PPUMASK=$1E` before accepting gameplay.

The final sustained run completed:

| Counter | Result |
| --- | ---: |
| fabric / PPU cycles | 26,713,111 / 26,713,111 |
| CPU slots / running CPU cycles | 8,904,370 / 8,751,816 |
| complete PPU frames | 300 |
| VBlank NMI events / handler entries | 297 / 297 |
| OAM DMA starts / completions | 297 / 297 |
| DMA source reads / OAM writes | 76,032 / 76,032 |
| post-DMA CPU resumes | 297 |
| controller polls / `$4016` reads | 297 / 2,376 |
| PRG reads | 7,281,979 |
| PPU-register writes | 1,363 |
| final PC / SP | `$80A5` / `$FF` |

Every DMA was page `$02`, performed exactly 256 ordered source reads and 256
`$2004` writes, transferred indices `$00` through `$FF`, stalled for 513 or
514 CPU slots, updated primary OAM, and was followed by a CPU resume. Bus-owner
assertions allowed only CPU ownership when idle and DMA ownership when active.
The PC remained in valid PRG space, SP stayed at or above `$E0` after boot,
the IRQ/BRK error counter stayed zero, and no unexplained BRK loop occurred.

Each A, B, Select, Start, Up, Down, Left, and Right sequence passes through the
input synchronizer, NES serial controller, `$4016`, CPU program, RAM game
state, OAM DMA, and rendered pixels. No testbench forces game state or output.
Left/up boundary holds prove that positions stop at X=`$08`, Y=`$10` rather
than wrapping.

```text
DE1-SoC switch -> two-flop synchronizer -> NES controller shift register
  -> $4016 CPU reads -> game state -> page-$02 OAM -> rendered frame
```

### Deterministic frames

All artifacts contain the actual FPGA PPU's 61,440 9-bit color/emphasis
outputs. `scripts/verify_phase4db_frames.py` checks the ASCII artifacts and
emits 256x240 binary PPMs under `build/sim`.

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

The started-frame player begins at rendered minimum `(121,101)`. Right moves
the minimum X to 123, and Up moves the minimum Y to 99. Returning Left or Down
reproduces the prior frame hash. These frames verify background/sprite
composition, sprite palette and tile changes, horizontal nametable mapping,
and stable sequential rendering. The demo does not exercise scrolling or
sprite-behind-background priority; those remain covered by retained focused
PPU regressions.

### VGA path

`nes_vga_phase4db_tb` drives the same sparse real-rate enable generator and
synchronous Mapper 0 cartridge used by the board top:

```text
.nes PRG/CHR -> Mapper 0 -> CPU/PPU -> NES pixels -> triple framebuffer
  -> palette/scaler -> 640x480 VGA
```

It captured nine NES frames and displayed nine VGA frames while observing
seven NMIs and seven DMA completions. The Python video model compared all
307,200 active 640x480 pixels with zero mismatches. The 256x240 picture is
centered and doubled to 512x480 with 64 black pixels on each side; a two-pixel
game move became four VGA pixels. Existing timing tests continue to prove
800x525 totals, HSYNC, VSYNC, blanking, palette conversion, and safe complete-
frame handoff. The PPU remains VGA-independent.

## Compatibility issue and fix

The playable test exposed one real integration bug. With real-rate sparse PPU
enables and synchronous cartridge CHR ROM, the PPU renderer address mux chose
the sprite address only while the one-cycle request pulse was high. During
intervening 50 MHz fabric clocks it reverted to the background address, so the
M10K output delivered the sprite byte one PPU tick too late. Full-rate PPU
tests kept the request asserted on consecutive fabric clocks, and the older
VGA integration used a combinational diagnostic CHR memory, so neither could
reproduce it.

The minimal RTL correction keeps the sprite address selected for the complete
dots-257-through-320 sprite-fetch window; request/grant/capture behavior is
unchanged. The Phase 3H regression now uses a registered synchronous CHR model
while retaining randomized enable stalls and its exact 61,440-pixel reference.
The playable cartridge-to-VGA regression independently proves the fix at the
real enable rate. No CPU, DMA, NMI, controller, mapper, framebuffer, or VGA
architecture was rewritten.

## Final regression and Quartus

The final complete suite passed 1,170 Python tests, strict Verilator lint, and
every retained and new RTL simulation. The new playable checks are part of
`scripts/test.sh`, not an out-of-band manual test.

The final full DE1-SoC build completed analysis/synthesis, fitting, assembly,
multi-corner timing analysis, and raw-binary generation with zero errors.

| Resource | Phase 4D-A baseline | Phase 4D-B final | Change |
| --- | ---: | ---: | ---: |
| ALMs | 2,906 | 2,879 | -27 |
| Logic ALUTs | 3,329 | 3,297 | -32 |
| Memory ALUTs | 590 | 590 | 0 |
| Registers | 1,229 | 1,239 | +10 |
| M10Ks | 230 | 230 | 0 |
| Block-memory bits | 1,871,872 | 1,871,872 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| DSPs | 0 | 0 | 0 |
| PLLs | 1 | 1 | 0 |

There is no significant resource increase. The small ALM/ALUT reduction and
ten-register increase are consistent with the changed ROM contents, added
passive observation connections, and a fresh fit; block memory and specialist
resource use are unchanged.

| Timing metric | Phase 4D-A baseline | Phase 4D-B final |
| --- | ---: | ---: |
| Worst setup slack | +1.084 ns | +0.525 ns |
| Worst hold slack | +0.118 ns | +0.145 ns |
| Setup TNS | 0.000 ns | 0.000 ns |
| Hold TNS | 0.000 ns | 0.000 ns |
| Unconstrained setup paths | 0 | 0 |
| Unconstrained hold paths | 0 | 0 |

The setup margin decreased by 0.559 ns but remains positive at every analyzed
corner; hold margin improved by 0.027 ns. The worst setup path is in the
50 MHz `CLOCK_50` domain at the slow 1100 mV, 85 C corner, from duplicated CPU
addressing-mode logic to PPU sprite-pattern storage. It has 19 logic levels,
18.904 ns data delay, -0.401 ns clock skew, a 20.000 ns relationship, and
+0.525 ns slack. No timing exception or unconstrained path hides this result.

Final programming artifacts:

| File | Size | SHA-256 |
| --- | ---: | --- |
| `build/quartus_de1_soc_nes_vga/output_files/de1_soc_nes_vga.sof` | 6,690,502 bytes | `30a6709deed10a406ddf5db7896d0682bc14c165d7a883c90ec49921cc8b5de9` |
| `build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf` | 7,007,204 bytes | `0310918f286eb867fff9e4fcb0384234c80959b335c5f5ef8fa4178f14c21bed` |

## Warnings

The final flow emitted the same 17 understood warnings as the baseline. No
latch, multiple-driver, RAM-initialization failure, CDC failure, or timing
warning was introduced. The messages cover read-only ROM
write inputs tied to zero, an intentionally consumed-but-not-displayed passive
status reduction, constant `VGA_SYNC_N`, incomplete noncritical board I/O
defaults, the Lite-edition LogicLock notice, default PLL compensation, and
two unmatched IRQ synchronizer exceptions because the board IRQ input is tied
inactive. The final report contains no new warning requiring investigation.

## USB-Blaster, programming, and physical validation

On 2026-09-21 this build host reported:

```text
lsusb: unable to initialize libusb: -99
jtagconfig: No JTAG hardware available
quartus_pgm -l: unable to connect before a 20-second timeout
```

No target identity could be established, so the FPGA was not programmed.
Consequently there is no claimed physical VGA image, controller response,
DMA observation, or sustained hardware runtime.

On the established Mac programming host, connect board power, USB-Blaster II,
VGA cable, and monitor, then run:

```bash
/opt/homebrew/bin/openFPGALoader -c usb-blasterII \
  --probe-firmware /Users/humzahashmi/fpga/firmware/blaster_6810.hex \
  --detect

/opt/homebrew/bin/openFPGALoader -c usb-blasterII \
  --probe-firmware /Users/humzahashmi/fpga/firmware/blaster_6810.hex \
  --index-chain 1 ./de1_soc_nes_vga.rbf
```

Proceed with the second command only if detection shows the previously proven
Cyclone V SoC (`5CSE*A5/5CST*5/5CSX*5`, IDCODE `0x02d120dd`) at chain index 1.
This loads volatile SRAM, not persistent flash.

Alternatively, on a host where Quartus detects cable 1 and confirms the FPGA
as the second JTAG-chain device, program the requested SOF directly:

```bash
jtagconfig
quartus_pgm -m JTAG -c 1 \
  -o "p;/home/humza/fpga/nintendo-fpga/build/quartus_de1_soc_nes_vga/output_files/de1_soc_nes_vga.sof@2"
```

Do not run that command unless `jtagconfig` identifies both the cable and the
Cyclone V at that exact position.

Physical checklist:

1. Set `SW0=0`, `SW1=0`, release reset with `KEY0`, and confirm LEDR0/LEDR1
   indicate PLL lock and released reset; LEDR8 must remain off.
2. Confirm a stable centered 512x480 game image, plausible colors, black side
   borders, no sync loss, tearing, or progressive corruption.
3. Press Start (`SW5`) and confirm the player appears. Verify A=`SW2`, B=`SW3`,
   Select=`SW4`, Up=`SW6`, Down=`SW7`, Left=`SW8`, and Right=`SW9` against the
   documented visible actions.
4. Confirm motion stays bounded and sprites remain stable while LEDR6 (DMA)
   and LEDR7 (NMI) continue to toggle. This is behavioral corroboration;
   exact internal counts come from simulation.
5. Measure an actual continuous run interval and record it. Throughout it,
   confirm video lock, input response, sprite updates, and absence of freezes
   or frame corruption.

If output differs, first isolate programming artifact/chain, ROM initialization,
reset, switch polarity/synchronization, VGA pins/timing, and Quartus timing
before changing NES architecture.

## Passive observations and Phase 4E recommendation

The board integration retains observational signals for CPU PC/A/X/Y/SP/P,
bus address/read-data/write-data/read/write/valid; PPU dot/scanline/frame
parity and captured-frame count, control/mask/status/NMI/pixels; cartridge
mapper/mirroring and PRG/CHR addresses/data/access; controller live/latched
state, serial index/data, strobe, and reads; and DMA active/page/source/index,
elapsed cycles, source data, bus owner, and completion. None feeds functional
control.

Phase 4E should consume these existing signals in a read-only snapshot layer,
cross the snapshot deliberately into the video domain, and composite a
switch-selectable developer side panel *after* the NES pixel stream. Keep the
PPU, cartridge, controller, and DMA independent of VGA/HDMI. Include PC and
registers, PPU scanline/dot/frame/status, mapper and live PRG/CHR transactions,
controller shift/index/read state, and DMA owner/progress/count/completion.
Use the Phase 4D-B title/Start/movement hashes as the normal-mode invariant and
add overlay-specific VGA hashes without altering the underlying NES frame.

## Files added or modified

- playable source/image/license: `roms/`,
  `scripts/generate_phase4db_playable_rom.py`, and
  `scripts/generate_phase4b_fixtures.py`;
- strict import and metadata: `scripts/prepare_phase4db_cartridge.py`,
  `verification/ines.py`, and `tests/python/test_phase4db_rom.py`;
- integration regressions and frame verification:
  `sim/nes_phase4db_playable_tb.sv`, `sim/nes_vga_phase4db_tb.sv`,
  `scripts/verify_phase4db_frames.py`, `sim/ppu_phase3h_tb.sv`,
  `scripts/sim.sh`, and `scripts/test.sh`;
- minimal compatibility fix: `rtl/ppu/ppu_background_core.sv`;
- selected board ROM and passive observations: `rtl/cartridge/nes_mapper0.sv`
  and `rtl/de1_soc_nes_vga_top.sv`;
- reproducible Quartus flow and documentation:
  `scripts/build_de1_soc_nes_vga_quartus.sh`, `README.md`, and this file.

Generated Quartus products, traces, extracted PRG/CHR files, JSON metadata,
frame hex, and PPM images remain under ignored `build/` paths.
