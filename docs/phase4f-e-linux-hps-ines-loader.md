# Phase 4F-E — Linux/HPS iNES loader software

Phase 4F-E provides the production-side software boundary between a `.nes`
file and the logical loader endpoint completed in Phases 4F-A through 4F-D. It
strictly parses classic iNES, validates the subset implemented by the runtime
Mapper-0 cartridge, creates the exact manifest, streams sequential PRG/CHR
commands, waits for staged validation, and explicitly activates the image.

This phase deliberately does not implement the Cyclone V HPS/FPGA bridge,
clock-domain crossing, Platform Designer component, register map, AXI access,
or `/dev/mem` access. A deterministic mock implements the logical contract for
software testing. Phase 4F-F can implement the same transport interface using
real hardware status and command registers once that physical contract exists.

## Baseline

Development started at merge commit `3386b44` on
`phase4/hps-ines-loader`, exactly matching current `main`, with a clean tree.
The environment was Python 3.14.4, Verilator 5.032, and Quartus Prime Lite
23.1std.1 build 993.

The pre-change regression passed 1,320 Python tests, warning-free full RTL
lint, and every CPU, PPU, bus, Mapper-0, controller, DMA, playable-ROM, VGA,
Developer Mode, debugger, and Phase 4F-A/B/C/D simulation. The 300-frame
playable run completed 297 NMI handlers and DMA transfers; the 132-frame mixed
debugger run completed 187 acknowledged commands.

The pre-change standalone runtime-cartridge compile used 372 ALMs, 343 logic
ALUTs, 162 registers, 40 M10Ks, and 327,680 block-memory bits. It was fully
constrained at 50 MHz with +13.182 ns worst setup slack and +0.168 ns worst
hold slack. Analysis/synthesis had zero warnings; the full compile's one
warning was Quartus Lite's standard unavailable LogicLock feature notice.

## Software architecture

The implementation is dependency-free apart from the Python standard library:

```text
classic iNES bytes
        |
        v
INESHeader + ParsedINES       structural parsing and exact boundaries
        |
        v
RuntimeImage                  supported Mapper-0 configuration only
        |
        v
Manifest + streaming LoadPlan centralized FPGA encodings and byte order
        |
        v
RuntimeLoaderTransport        physical-transport-neutral interface
        |
        v
MockRuntimeLoaderTransport    deterministic Phase 4F-E test endpoint
```

The production package is `software/nes_loader`. It does not import the older
`verification/ines.py`; that module remains the independent build-time
cartridge utility. The new parser reuses its proven classic-iNES interpretation
while keeping verification code out of the Linux/HPS runtime boundary.

- `ines.py` separates raw header/container parsing from supported-image
  validation. Once a `RuntimeImage` exists, no downstream component reads raw
  iNES flag bits.
- `protocol.py` centralizes command, target, state, error, manifest, size, and
  mirroring values. Unit tests compare the size and mirroring encodings against
  `rtl/loader/nes_runtime_loader_pkg.sv`.
- `loader.py` stores PRG/CHR as bytes and lazily yields byte commands, avoiding
  a second materialized list of tens of thousands of write objects.
- `transport.py` defines the interface a Phase 4F-F adapter must implement and
  provides the mock used now.
- `cli.py` implements inspection and dry-run loading. The repository entry
  point is `scripts/nes_loader.py`.

## Supported iNES contract

A structurally valid input begins with `4e 45 53 1a`, contains a complete
16-byte header, and has exactly the trainer plus PRG plus CHR length declared
by that header. Truncated data and all trailing data are rejected; this phase
does not guess where payloads end.

The mapper number is `(flags7 & 0xf0) | (flags6 >> 4)`. Both nibbles are
tested. The accepted runtime subset is:

| iNES property | Accepted value | Runtime meaning |
|---|---|---|
| format | classic iNES 1.0 | NES 2.0 is detected and rejected |
| mapper | `0` | Mapper 0 / NROM |
| PRG banks | one or two 16 KiB banks | physical 16,384 or 32,768-byte payload |
| CHR banks | one 8 KiB bank | CHR-ROM with an 8,192-byte payload |
| CHR banks | zero | CHR-RAM with no transferred CHR payload |
| mirroring | horizontal or vertical | FPGA encodings `1` or `0`, respectively |
| trainer | absent | trainer-bearing images are rejected after correct parsing |
| four-screen | absent | no silent horizontal/vertical reinterpretation |
| battery flag | clear | persistent PRG RAM is not implemented |
| VS/PlayChoice | absent | unsupported console variants are rejected |
| bytes 12-15 | zero | strict classic-iNES reserved-byte policy |

Classic iNES byte 8 is parsed using its conventional 8 KiB unit and legacy
zero-means-one-unit interpretation, matching the existing importer. It is not
placed in the runtime manifest: the current runtime Mapper 0 has no PRG-RAM
storage. The battery flag is rejected explicitly rather than pretending save
support exists.

NROM-128 is never duplicated by software. Exactly its physical 16 KiB PRG is
sent; `nes_runtime_mapper0` performs CPU `$8000-$BFFF` / `$C000-$FFFF`
mirroring. CHR-RAM similarly has no invented 8 KiB ROM transfer.

## Manifest mapping

The validated software model maps directly to the Phase 4F-C fields:

| Runtime image | Manifest field |
|---|---|
| Mapper 0 | `mapper = 0` |
| NROM-128 | `prg_bytes = 0x4000` |
| NROM-256 | `prg_bytes = 0x8000` |
| CHR-ROM | `chr_bytes = 0x2000`, `chr_is_ram = 0` |
| CHR-RAM | `chr_bytes = 0`, `chr_is_ram = 1` |
| vertical mirroring | `mirroring = 0` |
| horizontal mirroring | `mirroring = 1` |

The manifest is supplied only with `BEGIN`. The FPGA samples it on command
acceptance, so later software-side object changes cannot alter a session.

## Command and status contract

The loader emits this deterministic lifecycle:

```text
BEGIN(manifest; target NONE, address 0, data 0)
PRG WRITE(0), WRITE(1), ... WRITE(prg_bytes - 1)
CHR WRITE(0), WRITE(1), ... WRITE(8191)       [CHR-ROM only]
COMMIT
wait for image_valid or loader error
ACTIVATE(target NONE, address 0, data 0)
wait for runtime_active and reset-window completion
```

PRG and CHR coverage are independent in RTL and could interleave, but this
plan sends the complete PRG stream followed by the complete CHR stream. Every
address is emitted once, in order. Each command is held at the transport
boundary until accepted; the transport may report temporary backpressure.

`COMMIT` requests the Phase 4F-C completeness checks. `image_valid` means that
the staged store and manifest are complete, not that the cartridge is active.
Only after observing it does software issue canonical `ACTIVATE`. Phase 4F-D
then atomically latches active metadata and runtime selection, starts its
whole-NES reset window, and asserts `runtime_active`. The software's active
wait also requires `activation_in_progress = 0` and `nes_hold_reset = 0`, so
success means runtime execution has been released rather than merely selected.

The endpoint's first error is preserved. A fresh valid `BEGIN` is the defined
recovery from `ERROR` or replacement path from `READY`; reset also returns the
endpoint to `IDLE`. This loader stops immediately on a command/transport
failure or reported FPGA error. It never sends `ACTIVATE` after failed
validation.

## Backpressure and timeouts

`RuntimeLoaderTransport.send()` owns ready/acceptance waiting and receives a
bounded command timeout. Separate bounded waits cover image validation and
activation/reset release. Errors name the failed stage and preserve the
underlying transport or FPGA error code.

The mock represents latency as deterministic poll counts without wall-clock
sleeps. Tests can delay selected command acceptances, delay validation, delay
activation, inject a transport failure at an exact command index, or inject an
FPGA validation error. This verifies temporary stalls and timeout behavior
without claiming to model an unimplemented bridge.

The mock also enforces `BEGIN` first, a valid manifest, target-specific exact
sequential addresses, declared/physical bounds, no CHR writes for CHR-RAM,
complete counts before `COMMIT`, staged validity before `ACTIVATE`, and active
reset release. Every accepted logical command is recorded for exact sequence
inspection.

## CLI

Inspect any input without dumping payload data:

```bash
python3 scripts/nes_loader.py inspect game.nes
```

Exercise the complete software workflow against the mock:

```bash
python3 scripts/nes_loader.py load game.nes --dry-run
```

`load` without `--dry-run` fails with an explicit message that Phase 4F-E has
no physical transport. It does not open `/dev/mem`, invent MMIO addresses, or
pretend that mock acceptance reached an FPGA.

Command, validation, and activation timeouts can be set independently with
`--command-timeout`, `--validation-timeout`, and `--activation-timeout`.

## Original generated fixtures and verification

`verification/runtime_loader_fixtures.py` creates deterministic synthetic
PRG/CHR patterns. `scripts/generate_runtime_loader_fixtures.py OUTPUT_DIR`
emits four legal images: NROM-128 CHR-ROM horizontal, NROM-128 CHR-ROM
vertical, NROM-256 CHR-ROM horizontal, and NROM-128 CHR-RAM vertical. The
binary outputs are generated under `build` and are not committed. No
commercial or downloaded ROM content is used.

Forty focused tests cover those four images, reproducible generation, wrong
and truncated magic/header data, both mapper nibbles, unsupported PRG/CHR bank
counts, exact truncation/trailing-byte handling, trainer boundaries, battery,
four-screen, VS/PlayChoice, NES 2.0, reserved fields, manifest/RTL encoding
agreement, lazy plan boundaries, inspect/dry-run CLI output, exact recorded
commands and payloads, CHR-RAM zero-write behavior, deterministic
backpressure, command/validation/activation timeouts, mid-PRG transport
failure, FPGA validation failure, ordering errors, incomplete commits, fresh
`BEGIN` recovery, and activation-before-valid rejection.

The final repository regression passed 1,360 Python tests, warning-free full
Verilator lint, and every CPU, PPU, bus, Mapper-0, controller, DMA,
playable-ROM, VGA, Developer Mode, debugger, and Phase 4F-A/B/C/D simulation.
The post-change standalone runtime-cartridge Quartus compile also reproduced
the baseline resource, timing, and warning profile.

Phase 4F-E changes no RTL or Quartus project. Consequently the standalone
runtime-cartridge resource, timing, and warning profile remains the measured
Phase 4F-D baseline above.

## Deliberate exclusions

This phase does not implement Phase 4F-F HPS/FPGA bridge or CDC logic, an AXI
or lightweight-HPS register map, physical FPGA communication, microSD library
selection, additional mappers, NES 2.0, trainers, four-screen mirroring,
battery saves, end-to-end runtime game boot on the board, or physical DE1-SoC
validation.
