# Phase 4F-C — runtime image manifest and complete-transfer validation

Phase 4F-C extends the Phase 4F-A loader and Phase 4F-B runtime Mapper-0
storage so a successful `COMMIT` proves that one structurally supported image
was transferred completely. It does not activate that staged image in the
running NES. Atomic selection, functional NES reset integration, and ownership
of the active cartridge configuration remain Phase 4F-D work.

Implementation began on `phase4/runtime-image-validation` from commit
`5fa9279`, the current `main` containing merged Phases 4F-A and 4F-B. The
development environment was Python 3.14.4, Verilator 5.032, and Quartus Prime
Lite 23.1std.1 build 993.

## Established architecture retained

The existing ownership boundaries remain intact:

```text
BEGIN + manifest / WRITE / COMMIT
                |
                v
nes_runtime_loader                 protocol, session, validation
                |
                v
nes_runtime_mapper0
                |
                v
nes_runtime_cartridge_storage      32 KiB PRG + 8 KiB CHR
```

`nes_runtime_loader` still owns the single loader state machine and error
latch. `nes_runtime_mapper0` still translates NROM CPU/PPU accesses, and
`nes_runtime_cartridge_storage` still owns the two payload arrays. No second
session controller, payload bank, memory-clearing loop, iNES parser, or mapper
was added.

The production `nes_core` and board top still use the build-time cartridge.
The runtime composition remains a standalone integration boundary. The
existing runtime mapper configuration inputs also remain external: using the
validated manifest to atomically select an active cartridge is deliberately
deferred to Phase 4F-D.

## Manifest contract

The future Linux/iNES parser presents these fields alongside `BEGIN`; the
FPGA does not parse an iNES container:

| Field | Meaning | Phase 4F-C accepted values |
|---|---|---|
| `manifest_valid` | producer says all fields are present | `1` |
| `manifest_mapper[7:0]` | iNES-style mapper number | `0` |
| `manifest_prg_bytes[15:0]` | physical PRG payload size | 16,384 or 32,768 |
| `manifest_chr_bytes[15:0]` | CHR-ROM payload size | 8,192 for ROM, zero for RAM |
| `manifest_chr_is_ram` | pattern storage configuration | ROM or RAM under the size rule above |
| `manifest_mirroring[1:0]` | nametable arrangement | vertical `0` or horizontal `1` |

`BEGIN` must also carry the canonical non-write payload: target `NONE`, byte
address zero, and data zero. Reserved mirroring encodings, a missing manifest,
or a noncanonical `BEGIN` payload produce `INVALID_MANIFEST`. Mapper numbers
other than zero, unsupported PRG sizes, and contradictory/unsupported CHR
configurations have distinct errors.

The loader samples the accepted manifest into session registers. Later changes
at the manifest input do not change an in-progress session. The same latched
fields are exported as `image_*` status for the future activation phase.

Supported images are therefore:

- NROM-128 with one 16 KiB physical PRG payload. CPU `$C000-$FFFF` mirroring is
  performed by Mapper 0 and is not transferred a second time.
- NROM-256 with one 32 KiB physical PRG payload.
- Either configuration with an 8 KiB CHR-ROM payload.
- Either configuration with CHR-RAM and no CHR-ROM payload.

For CHR-RAM, `manifest_chr_bytes` must be zero and loader CHR writes are
rejected. The retained CHR memory contents are not treated as a ROM image;
later PPU writes provide normal CHR-RAM behavior.

## Complete-transfer algorithm

Phase 4F-C requires strict sequential addresses independently within the PRG
and CHR streams. Each stream starts at byte zero. Two 16-bit registers hold
the next expected address. A write advances its stream register only when the
ready/valid command is accepted by the real Phase 4F-B storage endpoint.

PRG and CHR writes may interleave. Within a target, however, the producer must
send exactly `0, 1, 2, ... size-1`. A duplicate, reversed address, or gap is
accepted as a protocol command, is not written to storage, does not advance
coverage, and enters `ERROR` with `UNEXPECTED_ADDRESS`. An address beyond the
declared image is `BAD_ADDRESS`; CHR is a bad target for a CHR-RAM session.

This rule gives a small proof of completeness. Starting from zero, the only
operation that increments a stream counter is an accepted write whose address
equals that counter. Consequently a counter can equal the declared size only
after every required address in the half-open range `[0, size)` was accepted
exactly once. Missing bytes, duplicate-only traffic, and storage-backpressured
transactions cannot create false completeness.

The alternatives considered were:

- A per-byte bitmap is correct for arbitrary ordering but adds 40,960 coverage
  bits for the maximum PRG+CHR image, plus session-clear machinery.
- A chunk bitmap is smaller but cannot prove every byte in a marked chunk was
  received without additional per-byte state or ordering rules.
- An unconstrained high-water mark is unsafe because a later address can hide
  a gap.
- Per-target sequential tracking is exact, uses only two counters, naturally
  handles reset/restart, and is simple for the future HPS software to emit.

Strict sequential transfer was therefore selected. It spends no M10Ks and
does not require clearing the payload RAM or a coverage RAM between sessions.

## Lifecycle and `COMMIT`

The Phase 4F-A states retain their encodings:

```text
IDLE -- valid BEGIN + manifest --> LOADING
LOADING -- accepted PRG/CHR bytes --> LOADING
LOADING -- complete COMMIT --> READY + IMAGE_VALID
any validation failure --> ERROR
ERROR/READY -- fresh valid BEGIN --> LOADING with zero coverage
```

`COMMIT` is now a request to validate the staged image. It reaches `READY` and
asserts `image_valid` only when the sampled manifest remains valid, PRG
coverage equals the declared PRG size, CHR coverage equals the declared CHR
size, and no prior error is active. Incomplete PRG has priority over incomplete
CHR and reports `PRG_INCOMPLETE`; otherwise incomplete CHR reports
`CHR_INCOMPLETE`.

`image_valid` means only that the bytes staged in runtime storage form a
complete, supported Mapper-0 image. It does not select that storage for the
production NES, release the functional NES from reset, or promise atomicity.
Those are separate Phase 4F-D responsibilities.

The first meaningful error remains latched in `ERROR`. Commands other than a
fresh `BEGIN` cannot overwrite it. A new valid `BEGIN` from `ERROR` or `READY`
clears the error, counters, and prior image validity. A rejected replacement
`BEGIN` also supersedes prior validity. Synchronous reset returns to `IDLE`,
clears manifest/coverage/validity state, and masks status deterministically;
the block RAM need not be physically cleared.

Phase 4F-A/B focused benches instantiate `IMAGE_VALIDATION_ENABLE=0` to keep
their historical protocol and storage proofs stable. The parameter defaults
to enabled, and the Phase 4F-C composition, synthesis target, and all future
integrations use the safe manifest-validating behavior.

## Error additions

Existing error values `0` through `6` retain their encodings. The typed error
field expands to four bits and adds:

| Code | Name | Meaning |
|---:|---|---|
| 7 | `INVALID_MANIFEST` | missing/reserved metadata or malformed `BEGIN` |
| 8 | `UNSUPPORTED_MAPPER` | mapper is not Mapper 0 |
| 9 | `UNSUPPORTED_PRG` | PRG size is not 16 KiB or 32 KiB |
| 10 | `UNSUPPORTED_CHR` | CHR-ROM/RAM size combination is unsupported |
| 11 | `UNEXPECTED_ADDRESS` | duplicate, gap, or reversed sequential address |
| 12 | `PRG_INCOMPLETE` | `COMMIT` before all declared PRG bytes |
| 13 | `CHR_INCOMPLETE` | `COMMIT` before all declared CHR-ROM bytes |

Existing `BAD_TARGET` and `BAD_ADDRESS` codes cover forbidden targets and
physical/declared range violations without multiplying error encodings.

## Verification

`verification/runtime_image.py` is an independent transaction-level oracle.
It models manifest support, sequential coverage, exact commit conditions,
latched errors, reset, and replacement sessions. Forty focused Python tests
cover NROM-128/NROM-256, CHR-ROM/RAM, malformed manifests, unsupported sizes,
empty/partial/complete transfers, exact last bytes, one-byte-short images,
duplicates, gaps, reset, error recovery, and stale-coverage prevention.

`sim/nes_runtime_image_phase4fc_tb.sv` drives the real loader, runtime mapper,
and runtime storage. It performs 123,016 directed checks and 122,880 accepted
storage writes across complete NROM-128 CHR-ROM, NROM-128 CHR-RAM, and
NROM-256 CHR-ROM sessions. It also checks every required failure and recovery
path, exact PRG/CHR boundaries, storage backpressure, CPU PRG readback, PPU CHR
readback, NROM-128 mirroring, and CHR-RAM PPU writes.

The pre-change full regression passed 1,265 Python tests, warning-free
Verilator lint, and every CPU, PPU, system-bus, Mapper-0, controller, DMA,
playable-ROM, VGA, Developer Mode, and debugger simulation. Phase 4F-C raises
the Python count to 1,305 and is part of the normal `scripts/test.sh` and CI
workflow.

## Cyclone V resources and timing

The standalone runtime-cartridge target remains fully constrained at 50 MHz
and still infers the 32 KiB PRG and 8 KiB CHR arrays as exactly 40 M10Ks.
Complete-transfer validation adds logic and registers but no coverage RAM:

| Metric | Phase 4F-B baseline | Phase 4F-C | Delta |
|---|---:|---:|---:|
| ALMs | 160 | 330 | +170 |
| combinational ALUTs | 120 | 317 | +197 |
| registers | 28 | 112 | +84 |
| M10Ks | 40 | 40 | 0 |
| block-memory bits | 327,680 | 327,680 | 0 |
| DSPs / PLLs | 0 / 0 | 0 / 0 | 0 / 0 |

Worst reported setup slack is +13.295 ns and worst hold slack is +0.171 ns.
Analysis/synthesis reports zero warnings; the full compile reports only the
standard Quartus Lite LogicLock license warning.

The deliberately unchanged production `de1_soc_nes_vga` image also completed
a full compile with its exact baseline resources: 4,897 ALMs, 6,493 logic
ALUTs, 4,528 registers, 230 M10Ks/1,871,872 block-memory bits, zero DSPs, and
one PLL. It remained fully constrained with +1.441 ns worst setup slack and
+0.142 ns worst hold slack. Its established 11 map, five fitter, and two
timing warnings (18 total) were unchanged.

## Deliberate exclusions

Phase 4F-C does not implement iNES parsing, HPS registers or CDC, Linux loader
software, hashes/CRC, additional mappers, active/staged double buffering,
cartridge activation, functional NES reset release, microSD selection, or
physical-board loading. Phase 4F-D is the next architectural step, but it is
not part of this change.
