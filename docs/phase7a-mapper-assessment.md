# Phase 7A cartridge architecture assessment

## Entry point

The inspected starting commit is
`117f1fdf7b9e0a88f578ee3d8f162e9937416ac2`, the merge of PR #52.
After `git fetch origin`, `origin/main`, the existing local
`phase7/mapper-framework` branch and its upstream all identify this commit.
The working tree was clean. No branch was deleted or force-updated.

The repository's phase descriptions are in `README.md` and `docs/`; there is
no separate tracked roadmap or requirements document. The Phase 7A request
defines the next scope. The existing Phase 4F and Phase 6G documents describe
the implementation below. Historical measurements are not new qualification
results. Baseline logs are collected under ignored `build/phase7a/baseline/`.

The initial Python stage passed 2,251 tests in 100.23 seconds and full
Verilator 5.032 lint reported no warnings/errors. The complete retained RTL, gameplay, debugger and Phase 6G system
regression also passed. The final system run reproduced 35,588,469 cycles,
52 PPU frames, 13 reset epochs and 155,949 MMIO commands with zero mismatches.
The baseline gate completed before production RTL changes.

Both fresh Quartus Prime Lite 23.1std.1 Build 993 baseline builds completed
synthesis, fitting, assembly and fully constrained all-corners timing;
production also generated its RBF. Reports are archived in `production-reports/`
and `hdmi-reports/` below the baseline log directory.

| Baseline measurement | Production VGA/WM8731/HPS | Logical HDMI |
|---|---:|---:|
| ALMs | 9,574 | 3,297 |
| Logic ALUTs | 12,974 | 4,819 |
| Routing ALUTs | 3,795 | 513 |
| Memory ALUTs | 590 | 0 |
| Registers | 15,046 | 4,430 |
| M10Ks | 275 | 210 |
| DSPs / PLLs | 7 / 2 | 8 / 2 |
| Worst setup slack | +1.048 ns | +0.747 ns |
| Worst hold slack | +0.077 ns | +0.123 ns |
| TNS, every reported corner | 0.000 ns | 0.000 ns |
| Map / fit / assembly / STA warnings | 105 / 149 / 0 / 144 | 22 / 3 / 0 / 0 |

These reproduce the Phase 6G final measurements. Production's remaining
implicit-net warning belongs to generated HPS DDR IP (`pll_dr_clk`); no
project-owned implicit net, inferred latch or multiple driver was accepted.
The retained warning categories and critical paths match the Phase 6G report.

## Actual module boundaries

| Responsibility | Existing source | Contract to preserve |
|---|---|---|
| CPU decode | `rtl/system/nes_cpu_address_decoder.sv`, `nes_cpu_bus.sv` | Cartridge address region and deterministic unmapped reads |
| CPU/OAM/DMC ownership | `rtl/system/nes_internal_bus_arbiter.sv`, `rtl/nes_core.sv` | One owner; accepted read/write strobes; precharged synchronous memory addresses |
| Build-time cartridge selection | `rtl/cartridge/nes_cartridge.sv` | Parameterized NROM image, mirroring and debug metadata |
| Build-time NROM memory | `rtl/cartridge/nes_mapper0.sv` | 16/32 KiB PRG, 8 KiB CHR ROM/RAM, optional 8 KiB PRG RAM |
| Runtime NROM mapping | `rtl/cartridge/nes_runtime_mapper0.sv` | Dynamic NROM size and CHR mode; existing debug conventions |
| Runtime payload storage | `rtl/cartridge/nes_runtime_cartridge_storage.sv` | One 32 KiB PRG and one 8 KiB CHR store; loader priority and write-first bypass |
| Session validation | `rtl/loader/nes_runtime_loader.sv` | BEGIN manifest validation, sequential coverage, sticky errors, COMMIT completeness |
| Runtime activation | `rtl/cartridge/nes_runtime_cartridge.sv` | Atomic active metadata, explicit ACTIVATE, four-cycle reset window |
| Production cartridge mux | `rtl/cartridge/nes_cartridge_runtime_mux.sv` | Legacy before activation; CPU/PPU strobes suppressed during load hold |
| PPU memory ownership | `rtl/ppu/ppu_background_core.sv`, `ppu_memory.sv` | CPU/render arbitration, cartridge CHR, internal CIRAM and palette |
| Board integration | `rtl/de1_soc_nes_vga_top.sv` | Existing functional reset tree, pins, enable cadence, audio/video/debug paths |

Both NROM implementations already perform the same small PRG address
translation. Their memory implementations differ intentionally: initialized
build-time memory versus writable runtime payload memory. They should retain
their memory inference patterns. The existing cartridge shells are appropriate
extension points; replacing the NES bus or loader is unnecessary for Mapper 0.

## Data flow and ownership

```text
CPU / OAM DMA / DMC DMA
        -> existing bus arbiter -> cartridge CPU address and strobes
        -> selected legacy/runtime NROM -> synchronous PRG data

PPU CPU-register accesses / background / sprite fetches
        -> ppu_background_core memory arbitration
        -> ppu_memory -> CHR port -> selected cartridge CHR memory
                      -> internal CIRAM (cartridge mirroring input)
                      -> internal palette RAM

iNES file -> software/nes_loader/ines.py -> RuntimeImage / Manifest
          -> loader.py LoadPlan -> mmio.py transport
          -> nes_runtime_loader_mmio -> nes_runtime_loader_cdc
          -> nes_runtime_loader -> payload storage -> COMMIT
          -> ACTIVATE -> active metadata and cartridge selection
```

PRG reads use CPU bits 13:0 for NROM-128 and 14:0 for NROM-256.
CHR uses PPU bits 12:0. CPU ROM writes are observable but ignored; CHR writes
affect memory only in RAM mode. Runtime has no PRG RAM. Internal CIRAM already
understands vertical, horizontal and both single-screen modes; runtime
manifests currently accept only horizontal or vertical mirroring.

All console logic uses the 50 MHz fabric clock with clock enables. Registered
cartridge reads run between console enable edges; gating these reads with the
accepted access strobe would change their timing and must be avoided.
Mapper state must use the same clock and functional reset epoch. The loader
and storage write port must remain outside that functional reset so a load can
complete while the console is held.

## Public software and physical contracts

The repository has **two independently versioned MMIO blocks**:

* Loader: `config/runtime_loader_mmio.json`, version **1.0**, 64 bytes at
  `0xff200000`.
* Diagnostics: `config/diagnostic_mmio.json`, version **1.3**, 512 bytes at
  `0xff201000`.

Both contracts must stay unchanged in Phase 7A. The manifest carries an
8-bit mapper ID, 16-bit PRG/CHR payload sizes, CHR-RAM flag and two mirroring
bits. A CHR-RAM manifest declares zero CHR payload bytes, while physical CHR
capacity remains 8 KiB. Classic iNES byte 8 is parsed but does not allocate
runtime PRG RAM. Battery, trainer, NES 2.0 and four-screen images are rejected.

Software validates files before constructing the hardware transport. The FPGA
independently rejects unsupported mapper IDs with error 8. The HPS bridge
uses a held command/manifest bundle and request/acknowledgement toggles, with
coherent return status. No mapper-specific CDC is needed or justified.

Developer Mode uses the existing coherent snapshot rather than reading mapper
state asynchronously. Its debug address widths describe current NROM storage;
future larger-bank diagnostics will need a separately designed extension.

## Failed-load semantics requiring explicit interpretation

The runtime store is **not double buffered**. A valid BEGIN holds the NES;
subsequent writes overwrite that store. COMMIT proves transfer completeness,
and ACTIVATE atomically changes metadata and restarts execution. An interrupted
transfer cannot resume the previous runtime game, because its bytes may have
been overwritten. It remains safely held until a complete reload/activation
or physical reset back to the immutable legacy image.

Even an invalid BEGIN is an accepted protocol transaction. It enters ERROR,
clears staged validity and sets the cartridge's activation-required hold;
it does not write payload memory or change active metadata. Existing tests
explicitly require this safe-stop behavior. Unsupported files rejected by the
normal software path never submit BEGIN and leave hardware untouched.

Therefore preservation of the existing contract permits safe-stop after raw
MMIO failure, but does not promise rollback or continued gameplay after every
failed load. Requiring that stronger guarantee would be a loader/storage
design decision, not a mapper-address refactor.

## Phase 7A design requirements

The common mapper boundary should separate address translation and permissions
from memory ownership, reuse NROM translation, report supported/config-valid
selection explicitly, suppress ownership and writes for invalid selection,
and provide a deterministic inactive IRQ for Mapper 0. Physical address
widths should allow later banked memories without allocating them now.
The reset/configuration contract must prevent old mapper state surviving
replacement. Read-data selection must preserve current synchronous latency.

Only mapper ID 0 may report support. IDs 1, 2, 3 and 4 must remain rejected;
no stub may advertise a future implementation. Software, loader validation
and hardware selection must agree on that support policy.

Future integrations need more than CHR read strobes:

* MMC1 needs CPU-cycle timing to distinguish consecutive register writes,
  including time spent outside cartridge accesses and during DMA.
* MMC3 needs the mapper-visible PPU address waveform and timing, including
  nametable and idle intervals; counting rendered scanlines or CHR requests
  alone is insufficient. Current PPU memory arbitration exposes an internal
  14-bit address, but the external cartridge interface truncates it to CHR.
* Mapper IRQ must enter the existing NES IRQ input alongside the APU level,
  without altering NMI. Mapper reset must cover replacement and physical reset.
* Current runtime capacity and 16-bit manifest sizes cannot represent normal
  large UxROM/MMC1/MMC3 images. A future storage and versioned loading design
  is required before claiming support for those images. Merely widening an
  internal physical address does not remove that limitation.
* Bus-conflict policy, board variants, PRG-RAM persistence and four-screen
  storage need explicit future decisions; none is implemented in Phase 7A.

These are integration requirements, not claims of implemented future mapper
behavior. MMC1 consecutive-write and MMC3 A12 behavior are documented by
[NESdev MMC1](https://www.nesdev.org/wiki/INES_Mapper_001) and
[NESdev MMC3](https://www.nesdev.org/wiki/MMC3).

## Verification gates

`PATH="$PWD/.venv/bin:$PATH" scripts/test.sh` is the complete local and PR
gate. It includes Python, lint, retained RTL simulations, debugger tests and
the Phase 6G integrated system run. FAST feature pushes retain the existing
policy; new deterministic mapper unit checks should run in FAST and FULL.
No retained check may be removed or weakened.

Both `scripts/build_de1_soc_nes_vga_quartus.sh` and
`bash scripts/build_phase6d_hdmi_audio_quartus.sh` are required local gates.
Their reports must be archived before rebuilding, including resource tables,
all-corners slack/TNS, critical paths and warning review. Production's rejection
of project-owned implicit nets and the existing timing constraints must remain.

The DE1-SoC is unavailable. Physical HPS/microSD loading, Mapper-0 gameplay,
VGA, WM8731, debugger/menu, cartridge replacement and reset recovery remain
pending in Welland, together with the complete Phase 6G bring-up checklist.
HDMI requires the separately qualified carrier; USB-C physical obligations
remain deferred under the Phase 6 architecture decisions.
