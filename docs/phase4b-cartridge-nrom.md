# Phase 4B iNES cartridge subsystem and Mapper 0/NROM

## Scope and baseline

Phase 4B replaces the Phase 3K board diagnostic-memory block with a real
cartridge subsystem behind the CPU and PPU cartridge interfaces established in
Phase 4A. The CPU, PPU, system bus, 513/514-cycle OAM DMA, NMI path, scheduler,
framebuffer, and VGA path are unchanged.

The starting commit was `8679473928fe1ac64d3bd06c95da0195e97a1d56` on
`phase4/system-bus-integration`. It matched its upstream exactly, and the
working tree was clean. Before Phase 4B changes:

- all 625 Python tests passed;
- every retained CPU, PPU, Phase 3J integration/NMI/DMA, Phase 3K VGA, and
  Phase 4A bus simulation passed;
- every Verilator lint target passed;
- the complete DE1-SoC flow passed synthesis, fitter, assembler, timing, and
  RBF conversion with 12 understood warnings;
- the image used 2,979 ALMs, 3,465 logic ALUTs, 590 memory ALUTs, 1,193
  registers, 206 M10Ks, and 1,675,264 block-memory bits;
- worst cross-corner setup and hold slack were +1.089 ns and +0.149 ns,
  respectively, with zero TNS and no unconstrained setup or hold paths.

This phase deliberately does not add advanced mappers, a runtime/physical
cartridge connector, battery saves, APU/audio, controllers, save states, or a
developer-mode graphical UI.

## iNES 1.0 input

An iNES file is a host-side container. The FPGA does not parse it. The first
16 bytes describe the following payload:

| Header byte | Phase 4B meaning |
|---:|---|
| 0-3 | Must be `4e 45 53 1a` (`NES` plus EOF marker) |
| 4 | PRG ROM count in 16 KiB banks; Mapper 0 accepts one or two |
| 5 | CHR ROM count in 8 KiB banks; Mapper 0 accepts zero or one |
| 6 bit 0 | vertical when set, horizontal when clear |
| 6 bit 2 | a 512-byte trainer follows the header when set |
| 6 bit 3 | four-screen nametables; rejected in Phase 4B |
| 6 bits 4-7 | low mapper-number nibble |
| 7 bits 4-7 | high mapper-number nibble |
| 8 | PRG RAM in 8 KiB units; legacy zero means one unit |
| 12-15 | reserved; required to be zero by the strict importer |

`verification/ines.py` validates the complete byte length, separates a trainer
before PRG extraction, computes the mapper number, and reports whether zero
CHR banks require CHR RAM. Trainer presence and bytes are parsed, but the
trainer is not copied into synthesized PRG RAM. NES 2.0, VS/PlayChoice,
four-screen, nonzero reserved bytes, unsupported PRG/CHR sizes, all nonzero
mappers, truncated images, and trailing bytes are rejected with deterministic
errors.

Only project-owned generated fixtures are used. No commercial ROM data is
stored in the repository.

## Build-time conversion

The conversion path is:

```text
input.nes
   -> strict iNES 1.0 validation
   -> PRG byte image (.prg.hex)
   -> CHR byte image (.chr.hex), or CHR-RAM metadata
   -> sorted JSON metadata plus SHA-256 digests
   -> Quartus-inferred initialized M10K ROMs
```

Run it from the repository root:

```bash
python3 scripts/convert_ines.py input.nes build/cartridge/my_cartridge
```

The JSON records the format, source and payload hashes, mapper number,
NROM-128/NROM-256 mode, PRG/CHR byte counts, CHR RAM/ROM status, PRG RAM size,
trainer presence, mirroring name, and RTL mirroring encoding. Conversion is
reproducible: identical input produces byte-identical memory and metadata
artifacts. When converting a CHR-RAM image, a stale CHR artifact at the same
prefix is removed so it cannot accidentally enter a later build.

`scripts/generate_phase4b_fixtures.py build/cartridge` generates the owned
boot, display, NROM-128 mapping, NROM-256 mapping, and CHR-RAM cartridges and
then sends every one through the same public converter. The normal simulation
and DE1-SoC build scripts run this generator before consuming its artifacts.

Quartus Prime 23.1 requires a literal filename in an inferred-ROM
`$readmemh`; it rejects a SystemVerilog string parameter in that position.
Consequently, the synthesizable branch names the generated display-fixture
artifacts literally, while Verilator uses `PRG_INIT_FILE` and `CHR_INIT_FILE`
parameters for every directed configuration. Selecting a different board ROM
currently requires changing the two literal build artifact paths and the four
metadata parameters in `de1_soc_nes_vga_top`; it does not require any CPU,
PPU, bus, or mapper logic change.

## Cartridge and mapper architecture

```text
Phase 4A CPU cartridge port ----+
                                v
                         nes_cartridge
                                |
                                v
                           nes_mapper0 ----> PRG ROM / optional PRG RAM
                                ^
                                |
existing PPU CHR port ----------+------------> CHR ROM or CHR RAM

cartridge mirroring metadata ----------------> existing PPU CIRAM mapper
```

`nes_cartridge` is the stable mapper-selection boundary. It accepts the
existing full CPU address/read/write/data interface and the existing 13-bit
PPU CHR address/read/write/data interface. It exposes cartridge metadata and
passive diagnostics. Mapper 0 is selected inside that shell; a future mapper
will replace or add only the implementation behind the same ports.

All cartridge logic remains in the 50 MHz fabric domain. PRG and CHR reads use
registered synchronous-memory inference. The established NES clock-enable
schedule presents an address at least one fabric clock before the CPU or PPU
consumes its data, so the inferred memory latency does not add a CPU or PPU
cycle. No cartridge-derived clock exists.

Reset suppresses CPU/PPU read data and access diagnostics. It does not clear
ROM. Optional PRG RAM and CHR RAM are storage arrays rather than reset state;
software must initialize bytes before depending on them. All control and
metadata outputs are deterministic.

## CPU mapping and PRG storage

Mapper 0 has no bank registers. Its PRG rule is purely an address transform:

| CPU address | NROM-128, 16 KiB PRG | NROM-256, 32 KiB PRG |
|---|---:|---:|
| `$8000-$BFFF` | `A[13:0]` | `A[14:0]` |
| `$C000-$FFFF` | `A[13:0]`, same 16 KiB image | `A[14:0]`, upper 16 KiB |

Thus `$8000` and `$C000`, `$BFFF` and `$FFFF`, and every corresponding pair
refer to the same physical NROM-128 byte. NROM-256 maps all 32 KiB directly.
Writes at `$8000-$FFFF` are observable for future mapper protocols but cannot
modify NROM.

The interrupt vectors are ordinary final PRG bytes:

| CPU bytes | Purpose |
|---|---|
| `$FFFA-$FFFB` | NMI vector, little endian |
| `$FFFC-$FFFD` | RESET vector, little endian |
| `$FFFE-$FFFF` | IRQ/BRK vector, little endian |

The owned mapping fixtures set distinct NMI, RESET, and IRQ targets, and both
the Python model and RTL test read them through Mapper 0. The integrated boot
fixture places `$8000` into `$FFFC/$FFFD`; the CPU performs its normal reset
sequence and constructs that PC from cartridge-returned bytes.

### PRG RAM

Mapper 0 exposes a configurable 8 KiB PRG RAM implementation at
`$6000-$7FFF`. When `PRG_RAM_ENABLE=1`, reads and writes use `A[12:0]`; the RTL
test covers both boundaries and stored data. When disabled, reads return zero
and writes have no effect. The DE1-SoC display fixture disables PRG RAM because
its program does not need it, so no unused M10Ks are spent. This parameterized
boundary preserves later battery-backed or mapper-controlled PRG RAM without
changing the Phase 4A bus.

## PPU mapping, CHR ROM, and CHR RAM

PPU pattern addresses `$0000-$1FFF` map one-to-one to 8 KiB CHR storage. A
CHR-ROM build reads the iNES CHR payload and ignores writes. A zero-CHR iNES
image selects an 8 KiB writable CHR RAM; PPU writes and later reads use all
13 address bits. Dedicated RTL testing covers `$0000`, `$0FFF`, `$1000`, and
`$1FFF`, exhaustive CHR ROM comparison, ignored CHR-ROM writes, and CHR-RAM
write/read at both ends.

The PPU still owns pattern-fetch timing and never contains cartridge graphics.
Background and sprite requests leave through its existing CHR interface,
cross Mapper 0, and return a cartridge byte. The integrated boot test observes
nonzero CHR bytes consumed after the cartridge program enables rendering.

## Nametable mirroring

The cartridge exports mirroring metadata; the existing PPU supplies the one
physical 2 KiB CIRAM. No nametable is duplicated. Let `p` be logical nametable
page 0-3 and `o` its 10-bit byte offset:

| Metadata | Physical CIRAM address |
|---|---|
| vertical | `{p[0], o}`: pages 0/2 and 1/3 pair |
| horizontal | `{p[1], o}`: pages 0/1 and 2/3 pair |

The independent Python model checks every nametable byte, including
`$3000-$3EFF` mirrors. Existing exhaustive PPU memory RTL regression proves
the same equations in hardware, and the board top now drives the PPU mode from
the cartridge rather than a hard-coded value.

## Owned cartridges and reset-vector boot

The boot fixture is NROM-128 with horizontal mirroring and CHR ROM. Its reset
program executes normal 2A03 instructions to initialize SP, write `$4B` and
`$5A` to CPU RAM, program palette/nametable bytes through PPU registers,
enable rendering, and enter a known loop. NMI and IRQ handlers increment
separate RAM bytes and return normally.

The display fixture is NROM-128 with vertical mirroring. It initializes a
palette, fills a nametable with a project-owned checkerboard tile, enables the
background, and loops. This is the cartridge embedded in the generated board
image for later physical VGA testing.

`nes_phase4b_boot_tb` does not force the CPU PC. It observes `$FFFC` and
`$FFFD` cartridge reads, then checks the resulting `$8000` instruction fetch,
the program's RAM signatures, its PPU-register traffic, and the PPU's CHR
reads. That provides an end-to-end path:

```text
cartridge vector -> Phase 4A bus -> CPU reset PC -> cartridge instructions
 -> PPU register writes -> PPU pattern fetch -> cartridge CHR byte
```

## Passive diagnostics

The cartridge boundary exports these behavior-independent observations:

- cartridge present and eight-bit mapper number;
- NROM-128/NROM-256 mode and CHR-RAM flag;
- horizontal/vertical mirroring encoding;
- current translated 15-bit PRG address and PRG data;
- current 13-bit CHR address and CHR data;
- PRG ROM read/write, PRG RAM read/write, and CHR read/write strobes.

The DE1-SoC integration retains the signals for a future developer renderer.
They do not drive cartridge, CPU, PPU, or bus state.

## Verification

The independent Python model implements PRG, CHR, PRG RAM, CHR RAM, vector,
and CIRAM translation without calling RTL-generation code. It exhaustively
checks all 32,768 CPU PRG addresses in both NROM modes, all 8,192 CHR
addresses, and complete horizontal and vertical nametable mappings.

`mapper0_phase4b_tb` compares 65,536 PRG results (both modes for every PRG
address), 16,384 CHR results, required boundaries, vector bytes, PRG RAM, CHR
RAM, and reset-safe outputs. `nes_phase4b_boot_tb` supplies the full-system
boot proof described above. Both generate FST waveforms under `build/sim`.

Run everything with:

```bash
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
scripts/build_de1_soc_nes_vga_quartus.sh
```

## Final qualification results

The completed Phase 4B qualification has the following sign-off targets; the
final report records the command output from the committed tree:

- 646 Python tests, including strict iNES import and exhaustive independent
  Mapper 0/mirroring tests;
- all Verilator lint targets with no emitted diagnostics;
- 65,536 RTL PRG comparisons, 16,384 RTL CHR comparisons, PRG/CHR RAM tests,
  and required address/vector boundaries;
- a real integrated CPU reset boot from cartridge `$FFFC/$FFFD`, followed by
  CPU RAM signatures, PPU register programming, and nonzero cartridge CHR
  consumption;
- every retained CPU, PPU, DMA/NMI, Phase 4A bus, framebuffer, and VGA
  regression;
- complete Quartus synthesis, fitter, assembler, timing, and RBF conversion.

The fitted Phase 4B board image uses 2,874 ALMs, 3,282 combinational logic
ALUTs, 590 memory ALUTs (3,872 logic-plus-memory ALUTs), 1,204 registers, 230
M10Ks, 18,880 MLAB bits, and 1,871,872 block-memory bits. It uses zero DSPs
and one PLL. Relative to Phase 4A, this is -105 ALMs, -183 logic ALUTs, +11
registers, +24 M10Ks, and +196,608 block-memory bits. The 16 KiB PRG image is
exactly 16 M10Ks and the 8 KiB CHR image is exactly eight M10Ks.

Timing is fully constrained with zero total negative slack: worst cross-corner
setup is +0.836 ns and worst cross-corner hold is +0.151 ns. The reports contain
no critical, latch, multiple-driver, unconstrained-path, or negative-slack
warning.

Known board-project warnings remain: an unused diagnostic reduction, the
existing PPU observation-port connectivity hierarchy, fixed-low `VGA_SYNC_N`,
unused board pins, Lite-edition LogicLock availability, automatic PLL
compensation, and two IRQ synchronizer SDC filters optimized away because IRQ
is tied low. Quartus also emits six new non-critical no-driver warnings for the
write-side fields of the two inferred ROM primitives. They were investigated:
the fitted report identifies both blocks as read-only `altsyncram` ROMs with
generated initialization MIFs, 16 PRG M10Ks, and eight CHR M10Ks; their unused
write data/address/enable fields are deterministically tied to zero by
Quartus.

## DE1-SoC artifact and physical test

The build creates the volatile-programming image at:

```text
build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf
```

It also retains the Quartus SOF under
`build/quartus_de1_soc_nes_vga/output_files`. Program the RBF using the
Phase 3K USB-Blaster/openFPGALoader procedure. With `SW0=1`, first confirm the
framebuffer-independent VGA bars. With `SW0=0`, the cartridge path should show
the display fixture's centered, 2x-scaled checkerboard background. `LEDR0` and
`LEDR1` should be on, `LEDR8` must remain off, HEX should settle in the
cartridge loop, and sync must remain stable. This repository run produces the
artifact but does not program or observe a physical board.

## Phase 4C recommendation

Implement the two NES controller serial ports behind the preserved Phase 4A
`$4016/$4017` boundary. Add the `$4016` shared latch/strobe behavior,
independent eight-button shift registers, deterministic post-eight-read bits,
DE1-SoC input synchronization, passive controller diagnostics, exhaustive
Python/RTL protocol tests, and an integrated cartridge program that reads both
ports. Keep physical pin/button mapping outside `nes_core` so a production PCB
or USB/input adapter can replace the DE1-SoC source without changing the CPU,
PPU, bus, DMA, or cartridge subsystem.
