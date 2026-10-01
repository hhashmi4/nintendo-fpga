# Phase 4F-H — microSD game library and selection

Phase 4F-H adds a console-style library layer above the proven Phase 4F-E/F/G
runtime-loading path. It discovers games on a configurable removable-media
directory, reports supported, unsupported, and corrupt images, resolves a
stable selection, and only then hands a fully parsed `RuntimeImage` to the
existing `LoadPlan` and transport. It does not change loader protocol, MMIO,
CDC, cartridge RTL, activation, or NES boot behavior.

No commercial ROMs are included or downloaded. All tests use the original,
deterministic generators in `verification/runtime_loader_fixtures.py` and
temporary directories.

## Architecture

```text
configured library root
        |
        v
non-recursive safe directory scan
        |
        v
existing iNES header parser + exact stat size
        |
        +---- supported metadata
        +---- unsupported metadata + reason
        +---- invalid entry + reason
        |
        v
stable library-relative filename ID
        |
        v
safe regular-file revalidation + full existing parser
        |
        v
existing RuntimeImage -> LoadPlan -> transport -> FPGA
```

`software/nes_loader/library.py` owns discovery, identity, removable-media
errors, and selection. It does not know loader commands or MMIO registers.
`software/nes_loader/ines.py` now exposes metadata inspection that reuses the
same header parser and support policy as full loads. A scan reads 16 header
bytes and obtains the file length with `fstat`; it does not read PRG or CHR
payloads. A selected supported entry is then reopened without following a
symlink, fully parsed, and revalidated before any transport is constructed.

## Configurable storage root

Every library command accepts `--library PATH`. Operators may instead set
`NES_LIBRARY_ROOT`, which is useful when the Linux image assigns a stable mount
location. There is no compiled-in `/media` or `/mnt` assumption:

```bash
export NES_LIBRARY_ROOT=/media/microsd/games
python3 scripts/nes_loader.py list
```

A missing root reports `library not mounted or not found`. An existing empty
directory reports `No .nes games found` and succeeds. The distinction is
intentional for physical Phase 4F-I diagnosis. Scanning and loading are
read-only; no sidecar databases, thumbnails, or metadata files are created.

## Discovery and identity policy

- Scanning is non-recursive. Directories are ignored, including directories
  whose names end in `.nes`.
- The `.nes` extension comparison is case-insensitive, so `.nes`, `.NES`, and
  mixed-case variants are accepted. Selection IDs remain exact and
  case-sensitive because they name actual Linux directory entries.
- Entries are sorted by Unicode NFC-normalized, case-folded filename, then the
  normalized and original filename as deterministic tie breakers. No process
  locale or directory enumeration order affects the result.
- Spaces, Unicode, and long legal filenames are passed only through Python
  filesystem APIs. Game names are never interpolated into a shell command.
- The stable game ID is the exact library-relative filename. List indices are
  display-only and are never accepted as persistent identity, so inserting or
  reordering games cannot retarget a saved selection.
- Display names are filename stems and need not be unique. The printed ID
  distinguishes duplicate display names.

## Filesystem safety

The first version rejects all symlinked games, whether their targets are
inside or outside the configured root. It also ignores sockets, FIFOs, devices,
and other non-regular entries. Selection rejects absolute paths, `..`, nested
paths, and NUL bytes. Before a full load it resolves the configured root again,
requires the same selected root, checks the selected entry with `lstat`, checks
containment, and opens it with Linux `O_NOFOLLOW`. `O_NONBLOCK` prevents a
special-file substitution from hanging the process.

The scan catches per-file format and I/O errors rather than aborting the whole
library. Bad magic, short headers, truncated/trailing payloads, strict classic
iNES reserved-bit errors, and read failures appear as `Invalid: ...`. Understood
but unimplemented images remain visible as `Unsupported: ...`; examples include
Mapper 2 and NES 2.0. Unsupported and invalid entries are rejected before load
plan or transport construction.

If media or a selected file disappears between scan and load, the CLI reports
a normal error without a traceback. The full parse at load time also rechecks
the current file and rejects it if it became malformed or unsupported after
selection.

## CLI workflow

List a library:

```bash
python3 scripts/nes_loader.py list --library /media/microsd/games
```

Example output is intentionally operator-oriented while retaining a stable ID:

```text
Games

1. Alpha Test
   ID: Alpha Test.nes
   Mapper 0 · 16 KiB PRG · 8 KiB CHR-ROM · NROM-128 · Horizontal mirroring
   Supported

2. Unsupported Mapper 2
   ID: Unsupported Mapper 2.nes
   Mapper 2 · 16 KiB PRG · 8 KiB CHR-ROM · Horizontal mirroring
   Unsupported: Mapper 2 is not supported; runtime hardware supports Mapper 0
```

Inspect or load by exact stable ID:

```bash
python3 scripts/nes_loader.py info "Alpha Test.nes" --library /media/microsd/games
python3 scripts/nes_loader.py load-library "Alpha Test.nes" \
  --library /media/microsd/games --dry-run
python3 scripts/nes_loader.py load-library "Alpha Test.nes" \
  --library /media/microsd/games
```

`--dry-run` exercises selection, full parsing, manifest/load-plan creation,
mock transfer, validation, and activation without FPGA hardware. The direct
Phase 4F-E forms remain compatible:

```bash
python3 scripts/nes_loader.py inspect game.nes
python3 scripts/nes_loader.py load game.nes --dry-run
```

## Generated fixtures and verification

Generate a mixed development library under `build` if desired:

```bash
python3 scripts/generate_game_library_fixtures.py build/game-library
```

The generator emits supported NROM-128/CHR-ROM and NROM-256/CHR-RAM images,
spaces, Unicode, duplicate display names, an unsupported mapper, corrupt and
truncated inputs, and an unrelated text file. Tests additionally cover an
empty and missing root, deterministic sorting, mixed-case extensions, nested
directories, long names, read-only media, simulated permission failures,
symlinks, FIFOs, traversal and containment, a 256-game generated library,
file removal/change after selection, unsupported/corrupt load rejection,
environment configuration, all library CLI commands, direct-file CLI
compatibility, and a complete selected-image `LoadPlan` execution through the
existing mock transport.

Phase 4F-H adds no RTL. The unchanged full regression remains the independent
CPU, PPU, bus, cartridge, controller, DMA, video, Developer Mode, debugger,
runtime-loading, and end-to-end boot gate. Physical DE1-SoC/microSD validation
remains Phase 4F-I. APU and audio work remain Phase 5 and are not started here.

## Final verification

The post-change full local regression passed all 1,412 Python tests, complete
Verilator lint, and every platform, CPU, PPU, bus, Mapper, controller, DMA,
playable-ROM, video, Developer Mode, debugger, Phase 4F-A through 4F-G, and
integration simulation. The 4F-H-focused parser/library/integration selection
passed 69 tests, including execution through the existing load plan and mock
transport. The 300-frame playable regression and the 132-frame, 187-command
debugger regression both completed successfully.

The production DE1-SoC NES/VGA Quartus build completed in 10 minutes 37 seconds
with no errors or timing violations. The unchanged fit uses 5,559 ALMs, 5,845
registers, 2,199,552 block-memory bits, zero DSPs, and one PLL. Worst setup
slack is +1.312 ns, worst hold slack is +0.077 ns, and every reported TNS value
is zero. The build generated both the SOF and 7,007,204-byte RBF artifacts.
