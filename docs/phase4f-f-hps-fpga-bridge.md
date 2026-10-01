# Phase 4F-F — Cyclone V HPS ↔ FPGA runtime-loader bridge

Phase 4F-F connects the Phase 4F-E Linux loader to the Phase 4F-A through
4F-D FPGA runtime cartridge through a synthesizable Cyclone V HPS bridge. The
production DE1-SoC image now contains the HPS hard subsystem, its lightweight
HPS-to-FPGA AXI master, an Avalon-MM adapter, a versioned loader register bank,
an asynchronous command/status mailbox, and the existing loader/storage/
validation/activation path.

This phase was developed without physical access to a DE1-SoC. The RTL,
Platform Designer system, Linux transport, register-level model, asynchronous
RTL simulation, Quartus fit, and static timing are verified. Physical Linux
MMIO access, HPS boot software, board reset behavior, and a runtime-loaded game
on the actual board are **not** verified here; that belongs to Phase 4F-I.
Phase 4F-G was intentionally not part of this phase; it was subsequently
implemented as the end-to-end simulation described in
[`phase4f-g-runtime-boot-e2e.md`](phase4f-g-runtime-boot-e2e.md).

## Baseline and environment

Development started from `c1bcfb7`, the then-current `main` containing merged
Phases 4F-A through 4F-E. The branch was
`phase4/hps-fpga-bridge` and the tree was clean. The host was x86-64 with
Python 3.14.4, Verilator 5.032, and Quartus Prime Lite 23.1std.1 build 993.
The Quartus installation included `qsys-generate` and the Platform Designer
Cyclone V HPS components.

The baseline regression passed 1,360 Python tests, full Verilator lint, and
all existing simulations before this phase changed the design.

## Bridge selection and production path

The selected path is the Cyclone V **lightweight HPS-to-FPGA bridge**. It is a
better match than the full bridge for this interface:

- traffic is HPS-initiated control and byte streaming, not FPGA DMA;
- the complete register aperture is only 64 bytes;
- one outstanding command is intentional because the loader itself applies
  backpressure and reports typed completion;
- 16–40 KiB ROM transfers do not justify a wider burst/data-plane design;
- the lightweight window has a conventional Linux physical-MMIO access path;
- keeping buffering and acknowledgement in the loader adapter makes the
  command semantics explicit and maintainable.

The resulting path is:

```text
Linux nes-loader
    |
    | /dev/mem + mmap, 32-bit little-endian accesses
    v
Cyclone V lightweight HPS-to-FPGA AXI master
    |
    | Platform Designer AXI/Avalon interconnect
    v
32-bit Avalon-MM bridge export (HPS user-clock domain)
    |
    v
nes_runtime_loader_mmio (one-entry command bank)
    |
    v
nes_runtime_loader_cdc (held bundle + request/acknowledge toggles)
    |
    v
nes_runtime_cartridge (50 MHz FPGA domain; Phases 4F-A–D)
    |
    v
NES core
```

The full HPS-to-FPGA bridge and FPGA-to-HPS bridge remain disabled. They add no
useful reliability or throughput to this command-oriented path.

## Reproducible Platform Designer integration

`quartus/nes_hps_loader_system.qsys` is the source-controlled system. It
contains:

- the Cyclone V HPS hard subsystem and DE1-SoC DDR/peripheral configuration;
- `LWH2F_Enable = true`;
- HPS-to-FPGA user clock 0;
- a 32-bit, 8-bit-symbol, 6-bit-byte-address Avalon-MM bridge;
- lightweight-master connection to slave offset `0x0000`;
- clock and reset fanout exported to the board top.

`scripts/generate_hps_loader_system.sh` locates `qsys-generate`, regenerates
the synthesis output under `build/qsys_nes_hps_loader_system`, and rejects the
output unless `scripts/validate_hps_loader_address_map.py` proves that the
Qsys source and generated `.regmap` match the shared contract. The Quartus QSF
then consumes only the generated QIP from `build`; the multi-megabyte generated
HDL tree is not source controlled.

The DE1-SoC HPS board locations are in `quartus/de1_soc_hps_pins.qsf`.
`quartus/de1_soc_hps_ddr3.qsf` contains the Quartus 23.1 UniPHY assignments
generated for this exact HPS DDR configuration after post-map pin discovery.
Both are sourced by the existing production `de1_soc_nes_vga` project.

## Address derivation and single source of truth

The physical base is not an independent software literal. The derivation is:

```text
generated Cyclone V lwfpgaslaves window    0xff200000
Platform Designer loader slave offset    + 0x00000000
                                           ----------
software-visible loader base               0xff200000
```

The generated `.regmap` supplies the first value; the Qsys connection supplies
the second. `config/runtime_loader_mmio.json` records the expected generated
map and the register contract. `scripts/generate_runtime_loader_mmio_defs.py`
generates all three consumer definitions:

- `rtl/loader/nes_runtime_loader_mmio_pkg.sv`;
- `software/nes_loader/mmio_registers.py`;
- `quartus/nes_runtime_loader_mmio_map.tcl`.

The normal test suite runs the generator in `--check` mode. The Platform
Designer build additionally parses the Qsys XML and generated `.regmap`, checks
the bridge type/width/address units, and proves the 64-byte region remains
within the generated 2 MiB lightweight window. Software and RTL therefore do
not maintain independent address or register constants.

## MMIO contract version 1.0

All registers are 32-bit, little-endian, and naturally aligned. Avalon uses
byte addresses and four byte lanes. Reads from reserved offsets return zero;
writes to read-only or reserved offsets are ignored. Unimplemented/reserved
bits read as zero and must be written as zero.

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x00` | `MAGIC` | RO | `0x4e45534c` (`NESL`) |
| `0x04` | `VERSION` | RO | major in `[31:16]`, minor in `[15:0]`; currently `1.0` |
| `0x08` | `CAPABILITIES` | RO | manifest, PRG, CHR, atomic activation, coherent status CDC |
| `0x0c` | `STATUS` | RO | coherent loader state plus bridge-local handshake flags |
| `0x10` | `ERROR` | RO | last completed command result and MMIO submit rejection |
| `0x14` | `COMMAND` | WO | one write strobe; command encoding in `[1:0]` |
| `0x18` | `TARGET` | RW | target encoding in `[1:0]` |
| `0x1c` | `ADDRESS` | RW | byte address in `[15:0]` |
| `0x20` | `WRITE_DATA` | RW | byte payload in `[7:0]` |
| `0x24` | `MANIFEST` | RW | explicit packed configuration fields below |
| `0x28` | `MANIFEST_PRG_BYTES` | RW | declared PRG byte count in `[15:0]` |
| `0x2c` | `MANIFEST_CHR_BYTES` | RW | declared CHR byte count in `[15:0]` |
| `0x30` | `COMPLETED_COUNT` | RO | increments once per completed logical command, modulo 2³² |
| `0x34` | `CONTROL` | WO | bit 0 writes one to clear sticky submission rejection |

`COMMAND` values retain the shared loader protocol: `0` `BEGIN`, `1` `WRITE`,
`2` `COMMIT`, and `3` `ACTIVATE`. `TARGET` is `0` none, `1` PRG, `2` CHR; `3`
is reserved. A command write is valid only when byte lane 0 is enabled and all
bits above bit 1 are zero. It is a strobe, not a level: later reads or the
stored bus value cannot resubmit it.

The manifest word has an explicit language-independent layout:

| Bits | Field |
|---:|---|
| `[0]` | manifest valid |
| `[1]` | CHR is RAM |
| `[3:2]` | mirroring encoding |
| `[15:8]` | mapper number |
| all others | reserved zero |

There is no dependency on SystemVerilog structure packing or host compiler bit
fields. Python/RTL generation and cross-check tests use these exact shifts and
masks.

## Status and error semantics

`STATUS` is:

| Bits | Meaning | Semantics |
|---:|---|---|
| `[0]` | bridge ready | instantaneous; a command can be submitted now |
| `[1]` | command pending | instantaneous MMIO-side buffered command |
| `[2]` | loader busy | coherent destination status snapshot |
| `[3]` | loader command ready | coherent destination status snapshot |
| `[4]` | image valid | coherent destination status; cleared by valid `BEGIN` or reset |
| `[5]` | runtime active | coherent destination status |
| `[6]` | NES held reset | coherent destination status |
| `[7]` | loader error | coherent destination status; recovered by valid `BEGIN` or reset |
| `[8]` | activation in progress | coherent destination status |
| `[9]` | submission rejected | sticky MMIO-local flag |
| `[17:16]` | loader state | idle/loading/ready/error coherent snapshot |

The coherent destination fields are published as one held multi-bit status
bundle; they are not independently synchronized bits. `bridge ready`, pending,
and rejection are local to the MMIO clock domain. Submission rejection is set
when software writes `COMMAND` while the one-entry channel is unavailable or
writes a noncanonical command word. Reset or `CONTROL[0] = 1` clears it.

`ERROR[3:0]` is the existing `loader_error_t` code, `ERROR[8]` mirrors sticky
submission rejection, `ERROR[16]` says the last completed command failed, and
`ERROR[18:17]` reports its resulting loader state. Codes remain typed across
the boundary: wrong state, begin busy, bad command/target/address, empty load,
invalid manifest, unsupported mapper/PRG/CHR, unexpected address, incomplete
PRG/CHR, and activate-invalid are distinguishable in Linux error messages.

## Submission, backpressure, and exactly-once completion

Software executes one command transaction as follows:

1. poll `STATUS.bridge_ready` with a bounded timeout;
2. write target, address, data, and the manifest words when issuing `BEGIN`;
3. sample `COMPLETED_COUNT`;
4. write `COMMAND` once;
5. poll until `COMPLETED_COUNT` changes and `command_pending` clears;
6. read `ERROR` and preserve a typed FPGA failure.

The MMIO block copies every staged field into its command bank on the command
write. It then refuses overwrites until the CDC endpoint reports completion.
The CDC destination holds `destination_valid` and the complete payload until
the Phase 4F-A loader asserts command acceptance. Consequently loader
backpressure can delay a command without losing, duplicating, or tearing it.

Repeated register reads do not create commands. A second `COMMAND` write while
one is pending is rejected and cannot modify the in-flight bank. The
completion counter lets software distinguish a new completion from a status
value that happens to equal the previous status.

## Clock-domain crossing

The Avalon/MMIO side runs from HPS-to-FPGA user clock 0; the runtime cartridge
and NES run from the board 50 MHz clock. No equality or phase relationship is
assumed.

Commands use a held-bundle request/acknowledge toggle channel:

1. the source copies the full command/manifest payload to preserved registers;
2. it toggles a request and holds every payload bit until acknowledgement;
3. a three-register destination synchronizer detects the toggle;
4. the destination captures the already-stable bundle and holds `valid` across
   arbitrary loader backpressure;
5. one destination edge after loader acceptance, it captures the coherent
   state/error response and toggles acknowledgement;
6. a three-register source synchronizer detects acknowledgement, captures the
   held response bundle, pulses done once, and frees the source bank.

Only toggles pass through independent synchronizers. Multi-bit command and
response payloads are source-held bundles with explicit 20 ns maximum routing
constraints to their destination capture banks. Cyclone V synchronizer
identification attributes are applied to every toggle chain.

Returning live status uses a second request/acknowledge mailbox. The loader
domain publishes a complete status word only when the previous snapshot has
been acknowledged. The source captures that stable word before acknowledging
it. This prevents torn state/error observations.

## Reset behavior

The external key reset and the HPS bridge reset assert both mailbox endpoints
and the runtime loader. Reset assertion is asynchronous; each clock domain
uses `reset_sync` for synchronous release. A common assertion epoch clears the
toggle channels, command buffer, completion count, last response, and status
snapshot, preventing a stale pre-reset request from firing after only one
domain restarts.

After release, the bridge starts empty, identification registers are readable,
the loader is idle, the runtime cartridge is inactive, and the NES remains in
the safe loader-requested reset state until a validated image is activated.

## Linux transport

`RawMmio` separates raw memory access from protocol semantics:

```text
RawMmio
  +-- DevMemMmio     production /dev/mem + mmap implementation
  +-- FakeMmio       deterministic unit-test implementation

MmioRuntimeLoaderTransport
  +-- ID/version/capability verification
  +-- manifest encoding
  +-- bounded ready/completion/status polling
  +-- typed FPGA error decoding
```

`DevMemMmio` page-aligns the mapping offset, applies the within-page base
offset to every access, maps only the pages covering the 64-byte region, uses
little-endian aligned 32-bit accesses, and closes both mapping and descriptor.
Only the production path opens `/dev/mem`; tests require neither that device
nor root access.

The real path is selected by default:

```bash
python3 scripts/nes_loader.py load game.nes
```

`--dev-mem` can select another device file for controlled environments, while
`--dry-run` retains the Phase 4F-E logical mock. The CLI validates the FPGA
magic, major version, and every required capability before sending `BEGIN`.
All command, validation, and activation waits remain bounded by their separate
timeouts.

## Verification

The register-level Python backend executes the exact production
`MmioRuntimeLoaderTransport` against the Phase 4F-E loader model. Tests cover
identity/version/capability mismatch, manifest packing, full load and
activation, typed error propagation and `BEGIN` recovery, backpressure,
repeated reads, rejected overwrite, completion counting, page-crossing mmap
alignment, cleanup, and generated Python/RTL/Qsys definition agreement.

The self-checking SystemVerilog bench instantiates the real MMIO block, CDC,
and Phase 4F-A loader with unrelated 14 ns and 22 ns clocks. It checks register
identity and reserved behavior, byte lanes, manifest decoding, loader
backpressure, exactly-once execution, repeated reads, rejected overwrite, a
complete 16 KiB PRG transfer, commit/activate, typed failure and fresh-`BEGIN`
recovery, coherent status, and reset during an in-flight command. Its final
result is:

```text
PASS: Phase 4F-F MMIO/CDC full NROM-128 transfer writes=16384 checks=38 asynchronous clocks/backpressure/exactly-once/status/reset
```

Platform Designer generation reports 23 modules and validates the loader at
physical base `0xff200000`, 64-byte span. Quartus 23.1 analysis/synthesis,
fitting, assembly, and TimeQuest complete successfully for the production HPS
+ NES/VGA design. The fitted design uses 5,559 / 32,070 ALMs, 5,845 registers,
270 / 397 M10K blocks, 2,199,552 block-memory bits, no DSPs, and one FPGA PLL.
All reported corners have zero TNS; worst setup slack is +1.312 ns and worst
hold slack is +0.077 ns. Setup and hold are both reported fully constrained.

## Hardware handoff and deliberate limits

Quartus emits a valid FPGA programming image and an HPS software handoff.
Board deployment must use a preloader or equivalent modern boot flow matching
that handoff and must enable/deassert reset for the lightweight HPS-to-FPGA
bridge before Linux accesses the aperture. The target Linux kernel/device tree
must also permit the chosen `/dev/mem` access. Those operations depend on the
target boot image and are not guessed or installed without the board.

This phase does not claim:

- physical HPS-to-FPGA reads or writes;
- `/dev/mem` permission/kernel-policy validation on the target image;
- HPS boot, DDR calibration, or reset sequencing on a real board;
- a runtime-loaded game booting end to end (Phase 4F-G);
- microSD browsing/selection (Phase 4F-H);
- physical DE1-SoC validation (Phase 4F-I).
