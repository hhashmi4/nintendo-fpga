# Phase 4F-G — End-to-end runtime `.nes` boot validation

Phase 4F-G closes the simulation gap between the Linux loader and the NES
system. A deterministic, project-owned `.nes` file now passes through the real
Phase 4F-E parser and load-plan builder, production Phase 4F-F MMIO transport
semantics, the RTL MMIO register bank and asynchronous CDC, and the existing
Phase 4F-A through 4F-D runtime cartridge before the real CPU and PPU consume
it. No payload is initialized directly in the testbench.

This is an integration and simulation result. It does **not** claim that Linux
on a physical DE1-SoC has communicated with the FPGA. Physical HPS/FPGA and
board validation remains Phase 4F-I. This phase adds no game library, microSD
workflow, APU, or audio work.

## Baseline

Development started from clean commit `ef4273c` on
`phase4/runtime-boot-e2e`; that commit is current `main` with Phase 4F-F merged.
The host used Python 3.14.4, Verilator 5.032, and Quartus Prime Lite
23.1std.1 build 993. Platform Designer was available through the Quartus
installation's `qsys-generate`.

Before changes, the repository passed 1,372 Python tests, complete Verilator
lint, every platform/CPU/PPU/bus/Mapper/controller/DMA/playable/video/debugger
and Phase 4F-A through 4F-F simulation, Platform Designer generation, and the
production Quartus build. The baseline fit used 5,559 ALMs, 7,378 logic ALUTs,
1,059 route-through ALUTs, 590 memory ALUTs, 5,619 dedicated logic registers,
270 M10Ks, 18,880 MLAB bits, and 2,199,552 block-memory bits. Worst reported
setup slack was +1.312 ns and worst hold slack was +0.077 ns; all TNS values
were zero.

## What existing tests did not prove

Phase 4F-D connected the runtime cartridge to the NES core, but generated
loader commands inside its SystemVerilog testbench. Phase 4F-F connected the
production MMIO register bank and CDC to a loader, but used modeled activation
status and stopped before the runtime cartridge and NES core. Software tests
used the real parser, plan, and MMIO transport against a faithful Python device
model. None began with one `.nes` and traversed all three boundaries in one
proof.

The new test composes the unchanged production modules in the same order as
the board top:

```text
generated original .nes
  -> load_runtime_image (strict iNES parser)
  -> LoadPlan / execute_load_plan
  -> MmioRuntimeLoaderTransport
  -> software-visible MMIO trace
  -> nes_runtime_loader_mmio
  -> nes_runtime_loader_cdc (asynchronous clocks)
  -> deterministic ready/valid backpressure
  -> nes_cartridge_runtime_mux / runtime loader and storage
  -> validation and atomic activation/reset
  -> nes_core CPU, PPU, DMA, controller, and Mapper 0
```

The board top itself ties simulation-only HPS MMIO inputs inactive, so the
harness instantiates the same MMIO, CDC, cartridge mux, timing generator,
controller, and NES core modules directly. It does not replace any production
protocol or cartridge logic.

## Original generated cartridges

`scripts/generate_phase4fg_runtime_boot.py` builds both legal images at test
time. No third-party ROM content or committed binary fixture is involved.

Game A is horizontal-mirroring NROM-128 with 16 KiB PRG and 8 KiB CHR-ROM.
Its reset program naturally vectors to `$8000` through 16 KiB Mapper-0
mirroring and writes the unique CPU RAM signature `42 4f 47`. It initializes a
palette and nametable, renders an alternating original tile from CHR-ROM,
performs one 256-byte OAM DMA, enables NMI and increments `$0010` from its NMI
handler, and continuously polls controller A into `$0011`.

Game B is vertical-mirroring NROM-256 with 32 KiB PRG and zero CHR payload.
Its reset vector is in the physical upper bank and naturally selects `$C000`.
It writes signature `47 42 32`, reads `$3c` through `$8000` from the lower PRG
half and `$c7` through `$C200` from the independent upper half, then writes and
reads `$a6` through the CPU-to-PPU CHR-RAM path. The zero-length CHR transfer is
the parser, manifest, validation, activation, and runtime storage contract for
CHR-RAM; an 8 KiB fake payload is never created.

## Software-to-RTL trace contract

The generator loads each just-written file back through `load_runtime_image`,
constructs a real `LoadPlan`, and runs `execute_load_plan` over the production
`MmioRuntimeLoaderTransport`. A recording `RawMmio` wrapper observes writes
while `SimulatedRuntimeLoaderMmio` supplies the status and completion responses
needed by the production polling code.

The resulting version-1 trace contains only software-visible operations:

```text
R <byte-offset> <mask> <expected>
W <byte-offset> <value>
S <status-mask> <expected>
```

`R` checks an MMIO read, `W` performs a 32-bit MMIO write, and `S` polls the
real RTL `STATUS` register. A `COMMAND` write is replayed exactly once and the
harness performs the same bounded `COMPLETED_COUNT`/pending wait as production
software. The trace starts by checking magic, version, and capabilities, so a
software/RTL register-contract drift fails before transfer. Offsets, manifest
packing, commands, status bits, and error codes come from the generated 4F-F
definitions, not parallel Phase 4F-G constants.

The three traces are generated as one continuous modeled session so the
second-image status correctly retains `runtime_active` while the NES is held.
Trace files are build artifacts under `build/runtime_e2e`, not source files.

## RTL timing and transfer proof

The MMIO clock is 71.4 MHz (`#7`) and the cartridge/NES clock is 50 MHz
(`#10`), with no shared phase assumption. Every CDC-delivered command is held
behind one deterministic destination ready/valid stall. The test observes
57,609 stalled command cycles and checks the accepted payload counts at each
commit:

| Session | PRG accepted | CHR accepted | Result |
|---|---:|---:|---|
| Game A | 16,384 | 8,192 | valid and activated |
| failed replacement | 257 | 0 | `PRG_INCOMPLETE`, never activated |
| Game B | 32,768 | 0 | valid and activated |

There are exactly three `BEGIN`s, three `COMMIT`s, and two `ACTIVATE`s. The
accepted-command total is 57,609. `image_valid` is checked only after the exact
declared transfer count, and a fresh `BEGIN` clears stale validity/error state.
The MMIO completion handshake and CDC assertions reject loss, duplication,
tearing, or early completion.

## CPU, PPU, and system proof

For Game A, the harness observes reads of CPU `$FFFC/$FFFD` returning
`$00/$80`, followed by execution of runtime PRG and the `42 4f 47` RAM
signature. This cannot come from the build-time cartridge. It also observes:

- one complete 256-read/256-write OAM DMA and legal 513/514-cycle stall;
- VBlank/NMI entry and execution of the runtime-loaded counter handler;
- simulated controller A reaching the generated program through the real
  controller and system bus;
- thousands of PPU CHR reads, including both `$55` and `$aa` rows unique to
  the runtime CHR payload;
- a complete ordered 256×240 digital frame.

`scripts/verify_phase4fg_frame.py` compares all 61,440 9-bit NES pixels against
the deterministic reference SHA-256
`54648910b2b993d95d58980fefa422b4f8f88cdcb8ef695be437bdf0f9b12f0d`.
The result is zero mismatches. The script also emits a diagnostic PPM; no
screenshot, image recognition, or OCR is used.

For Game B, `$FFFC/$FFFD` return `$00/$c0`. Its different RAM signature, both
PRG-half sentinels, and `$a6` CHR-RAM readback prove direct NROM-256 mapping,
runtime CPU execution, and writable runtime graphics storage.

## Replacement and failure semantics

The entire sequence runs in one Verilator process without resetting the MMIO,
CDC, cartridge, or FPGA fabric:

1. load, validate, activate, and execute Game A;
2. issue a new `BEGIN`, send only 257 Game B bytes, and `COMMIT`;
3. observe `PRG_INCOMPLETE`, no `ACTIVATE`, and no execution of partial data;
4. recover with a fresh valid `BEGIN`;
5. load, validate, activate, reset, and execute Game B.

This matches the existing single-buffer architecture. Once replacement
`BEGIN` is accepted, the NES remains held. A failed replacement does not roll
back or resume Game A; another complete valid load and activation is required.
The old active metadata remains observable while held, but its storage may
already be partially overwritten and is never released unsafely.

Python negative tests reject wrong magic, Mapper 1, unsupported PRG and CHR
bank counts, trainer images, NES 2.0, and truncated payloads before the MMIO
transport is constructed or written; every observed MMIO write count is zero.
An injected raw-MMIO failure propagates as a named `RuntimeLoadError`, stops the
load, and proves that no `ACTIVATE` command was emitted.

## Reproduction

The focused software and RTL checks are included in the normal suite. Their
essential commands are:

```bash
python3 scripts/generate_phase4fg_runtime_boot.py build/runtime_e2e
python3 -m pytest tests/python/test_runtime_boot_e2e.py -q
./scripts/sim.sh
python3 scripts/verify_phase4fg_frame.py \
  build/sim/phase4fg_game_a.hex build/sim/phase4fg_game_a.ppm
```

## Final verification

The post-change run passed all 1,381 Python tests, complete Verilator lint,
every platform/CPU/PPU/bus/Mapper/controller/DMA/playable/video/Developer
Mode/debugger and Phase 4F-A through 4F-G simulation, and Platform Designer
generation. The playable-ROM regression completed 300 frames; the dedicated
debugger mixed-command run completed 132 frames and 187 commands.

The production Quartus build completed with no errors and no timing
violations. Since Phase 4F-G changes verification infrastructure rather than
production RTL, its fit matches the baseline: 5,559 ALMs, 7,378 logic ALUTs,
1,059 route-through ALUTs, 590 memory ALUTs, 5,619 dedicated logic registers
(5,845 total registers), 270 M10Ks, 18,880 MLAB bits, 2,199,552 block-memory
bits, zero DSPs, and one PLL. Worst setup slack is +1.312 ns, worst hold slack
is +0.077 ns, and all reported TNS values are zero.

The warning profile remains the established board-build profile: HPS/DDR and
Platform Designer requested-versus-achieved clock notices, an existing
dependency-loop notice, unused IRQ-mapper reset/clock inputs, incomplete
board-I/O and generated-SDC filter warnings, HPS pin notices, and the fixed
`VGA_SYNC_N` output. No latch or multiple-driver warnings were introduced.

No production RTL architecture was redesigned; the phase adds generated
fixtures, software negative/failure coverage, a cross-layer RTL harness,
frame verification, and documentation.
