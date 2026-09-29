# Phase 4F-B runtime-writable Mapper-0 cartridge storage

Phase 4F-B adds the synthesizable PRG/CHR storage endpoint behind the Phase
4F-A loader. A validated loader byte can now traverse the real storage and
Mapper-0 path and be observed at the CPU or PPU cartridge interface. This
phase does not select files, validate a complete image, swap staging banks, or
connect `nes_hold_reset` to the production console reset tree.

## Scope and baseline

Implementation began on `phase4/runtime-cartridge-storage` from commit
`359beb9296d3ad35e3308d126d147787f478659d` after the complete unmodified
repository regression passed. The recorded environment was:

- Python 3.14.4 with pytest 8.3.5;
- Verilator 5.032;
- Quartus Prime Lite 23.1std.1 build 993.

The pre-change cartridge architecture was retained:

1. `nes_mapper0` owned initialized synchronous PRG and CHR arrays.
2. CPU addresses reached it through `nes_core`, `nes_cpu_bus`, and
   `nes_cartridge`.
3. NROM-128 selected CPU `A[13:0]`; NROM-256 selected `A[14:0]`.
4. PPU `$0000-$1FFF` requests crossed the existing cartridge CHR port and
   addressed the 8 KiB CHR array one-to-one.
5. Build-time NROM fixtures were generated as byte-oriented hex files and
   passed through `PRG_INIT_FILE`/`CHR_INIT_FILE` to `$readmemh`.
6. Existing CHR-RAM mode allowed PPU writes; CHR-ROM mode ignored them.
7. Quartus inferred the existing playable 16 KiB PRG and 8 KiB CHR images as
   16 and eight M10Ks respectively.

The runtime path is additive. Existing `nes_cartridge` and `nes_mapper0`
instances, the playable ROM, Developer Mode, debugger, and the DE1-SoC board
top continue to use their build-time initialized storage.

## Architecture

The Phase 4F-B path is:

```text
loader command
    |
    v
nes_runtime_loader                 Phase 4F-A validation/handshake
    |
    | validated storage write
    v
nes_runtime_mapper0
    |
    v
nes_runtime_cartridge_storage      32 KiB PRG + 8 KiB CHR
    ^                    ^
    |                    |
Mapper-0 CPU read    PPU CHR read/write
```

`nes_runtime_cartridge` is the composition boundary. It instantiates the
unchanged Phase 4F-A controller and the runtime Mapper-0 endpoint, exporting
the normal cartridge CPU/PPU ports and loader state. It remains independent of
the eventual HPS bridge and never acts as an NES bus master.

`nes_runtime_mapper0` owns address translation and cartridge behavior. Its
`nrom_256` and `chr_is_ram` configuration inputs are direct, unlatched Phase
4F-B inputs. Tests keep them stable for each access. Manifest validation and
atomic configuration activation belong to Phases 4F-C and 4F-D.

`nes_runtime_cartridge_storage` owns the payload arrays. Loader addressing is
relative to those arrays, not to CPU or PPU addresses:

| Target | Loader range | Physical capacity |
|---|---:|---:|
| PRG | `$0000-$7FFF` | 32 KiB |
| CHR | `$0000-$1FFF` | 8 KiB |

Both arrays use canonical synchronous simple-dual-port inference: one write
port shared by loader/CHR-RAM activity and one NES-side read port. The storage
accepts one validated loader byte on every fabric cycle. It repeats the target
and range checks as a local safety boundary, without duplicating loader state
or command validation.

## Mapper-0 behavior

PRG translation is runtime-selectable:

| CPU address | NROM-128 | NROM-256 |
|---|---:|---:|
| `$8000-$BFFF` | PRG `$0000-$3FFF` | PRG `$0000-$3FFF` |
| `$C000-$FFFF` | mirror PRG `$0000-$3FFF` | PRG `$4000-$7FFF` |

The physical PRG array is always 32 KiB so changing between supported NROM
sizes never requires FPGA recompilation. In NROM-128 mode the upper physical
16 KiB is not selected by CPU reads. A future manifest will define which
bytes form a complete active image.

CHR addresses `$0000-$1FFF` map directly. Loader writes are permitted in both
CHR-ROM and CHR-RAM configurations because runtime loading must populate a
CHR-ROM payload. PPU writes remain enabled only when `chr_is_ram` is asserted.
No mapper registers, bank switching, PRG RAM, or unsupported mapper behavior
were added.

## Handshake, reset, and collisions

The storage endpoint is ready whenever reset is inactive and the presented
target/address is locally valid. It has no active-cycle busy condition. Phase
4F-A therefore accepts each legal write once and the memory performs exactly
one corresponding byte write. Phase 4F-A's existing randomized test remains
the exhaustive proof of arbitrary downstream backpressure and held payloads.

Memory contents are intentionally not reset. Clearing 40 KiB with reset logic
would prevent efficient block-RAM inference. The reset contract is:

- loader storage writes are rejected;
- CPU and PPU read outputs are masked to zero;
- previously accepted PRG/CHR bytes are retained;
- the Phase 4F-A controller returns to IDLE and cancels its in-flight command.

Simulation initializes the arrays to zero for deterministic test startup. No
runtime software may rely on unwritten hardware power-up bytes; Phase 4F-C/D
will prevent execution until a complete image is validated and activated.

Read-during-write behavior is not left to the FPGA primitive. Small bypass
registers outside each inferred RAM make a same-address read observe the newly
written byte (write-first), even though Quartus reports the native mixed-port
mode as old-data. If loader and PPU CHR-RAM writes coincide, the loader wins;
the single CHR write port drops the PPU write. This priority is deterministic,
and Phase 4F-D will keep the NES inactive while loading.

## Verification

`verification/runtime_cartridge.py` independently models the byte stores,
NROM-128 mirroring, NROM-256 addressing, CHR behavior, overwrite semantics,
reset rejection, and write-first collision result. Its focused pytest module
contains 17 tests.

`scripts/generate_runtime_cartridge_vectors.py` uses fixed seed `0x04FB2026`
to generate 12,021 operations:

- 5,953 validated loader writes;
- 1,237 PPU writes across CHR-ROM and CHR-RAM modes;
- 4,831 CPU/PPU reads;
- 1,764 NROM-128 and 1,823 NROM-256 CPU reads.

`sim/nes_runtime_cartridge_phase4fb_tb.sv` sends every loader write through
the real `BEGIN`/`WRITE`/`COMMIT` Phase 4F-A interface and reads it back only
through the Mapper-0 CPU or PPU port. It also directs first/last/midpoint
boundaries, 16 KiB mirroring, independent 32 KiB halves, sequential writes,
overwrites, PRG/CHR isolation, CHR-ROM/RAM behavior, reset cancellation and
retention, post-reset recovery, and same-address collisions. The focused RTL
result is 12,021 vectors, 26,981 checks, and zero mismatches.

The test is part of `scripts/sim.sh`; the new production modules are part of
`scripts/lint.sh`, so the normal `scripts/test.sh` regression and CI workflow
cover Phase 4F-B.

## Cyclone V synthesis

`scripts/build_runtime_cartridge_quartus.sh` performs a standalone Cyclone V
full compile, checks RAM inference, and requires fully constrained,
non-negative timing. The initial noncanonical collision-forwarding form was
rejected during development because Quartus reported uninferred arrays. The
final canonical dual-port form infers both payloads as M10Ks.

| Metric | Phase 4F-A controller | Phase 4F-B composition | Delta |
|---|---:|---:|---:|
| ALMs | 20 | 160 | +140 |
| combinational ALUTs | 31 | 120 | +89 |
| registers | 8 | 28 | +20 |
| M10Ks | 0 | 40 | +40 |
| block-memory bits | 0 | 327,680 | +327,680 |
| DSPs / PLLs | 0 / 0 | 0 / 0 | 0 / 0 |

The 32 KiB PRG store consumes 32 M10Ks and the 8 KiB CHR store consumes eight.
Worst 50 MHz setup slack is 16.342 ns; worst hold slack is 0.168 ns across the
reported corners. Analysis/synthesis completed with zero warnings; the fit's
only warning is Quartus Lite's standard unavailable LogicLock feature notice.
The production board image is deliberately unchanged by this standalone
runtime path during Phase 4F-B. A full `de1_soc_nes_vga` compile confirms the
existing playable image still fits at 4,897 ALMs, 6,493 combinational ALUTs,
4,528 registers, 230 M10Ks (1,871,872 block-memory bits), zero DSPs, and one
PLL. Quartus completed with zero errors and the design remained fully
constrained; the worst reported setup and hold slacks were 1.441 ns and
0.142 ns respectively. Its 18 existing project warnings are unrelated to the
standalone Phase 4F-B endpoint.

## Deliberate exclusions

Phase 4F-B does not implement:

- expected PRG/CHR byte counts or coverage bitmaps;
- iNES parsing, metadata validation, CRC, or image hashes;
- complete-image acceptance;
- active/staging banks or atomic cartridge replacement;
- production NES hold/reset integration;
- HPS register mapping, CDC, Linux software, or microSD access;
- any mapper other than Mapper 0.

Phase 4F-C subsequently added manifest and complete-transfer validation without
weakening the byte-level and Mapper-0 guarantees established here. Its design
is documented in
[`phase4f-c-runtime-image-validation.md`](phase4f-c-runtime-image-validation.md).
