# Phase 4F-D — atomic runtime cartridge activation and NES reset

Phase 4F-D crosses the boundary deliberately left by Phase 4F-C: a complete,
validated Mapper-0 image can now become the production NES cartridge without
rebuilding the FPGA image. Activation is explicit, all cartridge metadata is
published atomically, and the CPU naturally boots through `$FFFC/$FFFD` while
the complete NES is held in a deterministic reset sequence.

This phase does not add iNES parsing, Linux software, or the physical HPS/FPGA
bridge. The production top contains the logical loader/control/status endpoint
that Phase 4F-F will connect across its CDC boundary; no existing DE1-SoC pin
mapping is repurposed.

## Baseline

Development started at merge commit `600a72e` on
`phase4/runtime-image-activation`, with a clean worktree. The environment was
Python 3.14.4, Verilator 5.032, and Quartus Prime Lite 23.1std.1 build 993.

The pre-change regression passed 1,305 Python tests, warning-free full RTL
lint, and every CPU, PPU, system-bus, Mapper-0, controller, DMA, playable-ROM,
VGA, Developer Mode, debugger, and Phase 4F-A/B/C simulation. The playable
long run completed 300 frames with 297 NMI handlers and DMA transfers; the
mixed debugger long run completed 132 frames and 187 commands.

The pre-change standalone runtime-cartridge fit used 330 ALMs, 317 logic
ALUTs, 112 registers, 40 M10Ks, and 327,680 block-memory bits. It had +13.295
ns worst setup slack and +0.171 ns worst hold slack, with only Quartus Lite's
standard LogicLock warning. The production NES/VGA image used 4,897 ALMs,
6,493 logic ALUTs, 4,528 registers, 230 M10Ks, and 1,871,872 block-memory bits.
It closed timing with +1.441 ns setup and +0.142 ns hold slack and had its
established 18 warnings.

## Explicit activation protocol

Command encoding `3`, reserved by Phase 4F-A, is now the typed
`LOADER_COMMAND_ACTIVATE`. Its canonical payload is target `NONE`, address
zero, and data zero. Historical validation-disabled Phase 4F-A/B benches keep
the old behavior: encoding `3` remains a `BAD_COMMAND` there.

With validation enabled, activation has these semantics:

```text
IDLE/legacy
    -- BEGIN --> LOADING + whole-NES hold
    -- complete COMMIT --> READY + staged image_valid + hold remains
    -- ACTIVATE --> atomically latch active metadata/runtime select
                   + four-cycle functional reset
    -- reset window complete --> runtime RUN
```

`image_valid` therefore remains a staging result. The final byte and successful
`COMMIT` never select the runtime cartridge. `ACTIVATE` is accepted only from
`READY`; otherwise error code 14, `LOADER_ERROR_ACTIVATE_INVALID`, is reported.
A malformed activation payload receives the same deterministic error.

A successful activation deliberately leaves the loader in `READY`, so staged
validity remains visible. Repeating the same canonical `ACTIVATE` republishes
the same metadata and starts a fresh reset window. This defines repeated
activation as an idempotent cartridge selection with a deterministic reboot.

## Atomic single-store architecture

No second 32 KiB PRG plus 8 KiB CHR bank was added. An accepted `BEGIN` sets
`activation_required`, which holds the functional NES before any payload write
can be accepted. The existing runtime storage can then be overwritten safely.

On the one activation clock edge, `nes_runtime_cartridge` latches:

- runtime cartridge selection;
- mapper number;
- 16 KiB versus 32 KiB PRG size;
- CHR-ROM versus CHR-RAM mode and declared CHR size; and
- horizontal or vertical nametable mirroring.

The reset window begins on that same edge. CPU and PPU cartridge bus strobes
are disabled whenever the hold is active. The NES can therefore observe
neither a partial payload nor mixed old/new configuration.

`nes_cartridge_runtime_mux` is the production cartridge boundary. Before the
first successful activation it selects the original build-time cartridge,
including the playable ROM, CHR, mirroring, and debug observations. Starting a
runtime load holds that legacy execution but does not discard it. After
activation, the mux selects runtime PRG/CHR and active metadata together.

For replacement, Game A remains the selected configuration while Game B is
staged into the single store, but the NES stays reset throughout the overwrite.
Only Game B's successful `ACTIVATE` changes active metadata and releases a new
boot. Invalid manifests, incomplete transfers, ordering/range failures, loader
`ERROR`, invalid activation, or a reset during transfer can never publish the
replacement or release execution into it.

## Whole-NES reset integration

The production top combines the already synchronized board/system reset with
the same-domain runtime hold to form `nes_functional_reset`. Deassertion occurs
only after the active metadata has been stable for the complete four-cycle
activation window. This functional reset covers:

- `nes_core`, including CPU reset-vector sequencing, PPU, 3:1 scheduler,
  system bus, internal arbiter, and OAM DMA;
- both controller ports;
- debugger execution state and pending snapshot capture;
- the framebuffer write side; and
- the source side of the coherent debug snapshot.

The video PLL, VGA timing/scanout domain, loader controller, and runtime payload
RAM remain on system reset. This avoids a reset/hold feedback deadlock and
allows the loader to finish activation while the NES is held.

DMA's public `active` indication is masked while `nes_core.reset` is asserted.
This makes the arbiter move immediately to `NES_BUS_MASTER_NONE`; the DMA state
registers are synchronously cleared on the next fabric edge and can never
resume halfway through an old transfer. CPU and PPU enables are reset-gated,
so RUN, PAUSE, instruction-step, or frame-step authorization cannot override
loader safety. PPU reset clears the NMI level and event state before release;
normal VBlank/NMI behavior resumes after the new boot.

Physical/system reset clears active selection and returns to the original
build-time cartridge. Runtime RAM contents may remain physically stored, but
they are not selected or valid after reset.

## Status contract

The logical endpoint exposes the compact status needed by later HPS software:

- staged `image_valid` and existing loader state/error code;
- one-cycle `activation_accepted`;
- `runtime_active`;
- `activation_in_progress` and `nes_hold_reset`; and
- `activation_error`, derived from error code 14.

Phase 4F-F will assign these same concepts to a physical bridge/register and
CDC implementation. Phase 4F-D adds no speculative software register map.

## Verification

`verification/runtime_activation.py` is an independent policy-level model. Its
15 tests cover legacy mode, load hold, staged-versus-active separation,
NROM-128/NROM-256 metadata, invalid and malformed activation, failed loads,
repeat activation, Game A to Game B replacement, debugger precedence, DMA/NMI
reset, reset during transfer, and physical-reset recovery.

`sim/nes_runtime_activation_phase4fd_tb.sv` connects the real loader, single
runtime store, production cartridge mux, Mapper 0, and `nes_core`. It proves:

- legacy execution continues before a runtime session;
- activation before valid and activation during loading fail deterministically;
- NROM-128 `$FFFC/$FFFD` reads mirror through physical PRG offsets
  `$3FFC/$3FFD`, return `$00/$80`, and naturally construct PC `$8000`;
- runtime instructions execute and write `$42` to CPU RAM `$0002`;
- runtime CHR-ROM data reaches the PPU cartridge port and ignores PPU writes;
- replacement begins while OAM DMA is active and PPU NMI is pending, then
  clears DMA/NMI and suppresses CPU/PPU enables under reset;
- old horizontal/NROM-128/CHR-ROM metadata remains active until the replacement
  activation edge;
- NROM-256 vectors come from physical `$7FFC/$7FFD`, the independent lower and
  upper PRG halves are not NROM-128 mirrored, and the new program writes `$99`
  to CPU RAM `$0003`;
- zero-payload CHR-RAM is writable through the runtime PPU path;
- repeated activation fetches the reset vector again; and
- an invalid replacement remains held until physical reset restores legacy
  mode; a separate reset during a valid partial transfer also discards staged
  validity and returns safely to the legacy cartridge.

The focused run records three accepted activations, one runtime replacement,
three natural reads of each reset-vector byte, and three directed runtime CHR
reads. Its FST is `build/sim/nes_runtime_activation_phase4fd.fst`.

The final Python count is 1,320. Full lint remains warning-free, and the normal
regression retains all Phase 4F-A/B/C, playable-ROM, DMA/NMI, VGA, Developer
Mode, and debugger coverage.

## Cyclone V resources and timing

The standalone runtime-cartridge target remains fully constrained at 50 MHz:

| Metric | Phase 4F-C baseline | Phase 4F-D | Delta |
|---|---:|---:|---:|
| ALMs | 330 | 372 | +42 |
| combinational ALUTs | 317 | 343 | +26 |
| registers | 112 | 162 | +50 |
| M10Ks | 40 | 40 | 0 |
| block-memory bits | 327,680 | 327,680 | 0 |
| DSPs / PLLs | 0 / 0 | 0 / 0 | 0 / 0 |

Worst reported setup slack is +13.182 ns and worst hold slack is +0.168 ns.
Analysis/synthesis has zero warnings; the full compile has only the standard
LogicLock license warning.

The production `de1_soc_nes_vga` image also remains fully constrained:

| Metric | Phase 4F-C baseline | Phase 4F-D | Delta |
|---|---:|---:|---:|
| ALMs | 4,897 | 5,113 | +216 |
| combinational ALUTs | 6,493 | 6,845 | +352 |
| registers | 4,528 | 4,799 | +271 |
| M10Ks | 230 | 270 | +40 |
| block-memory bits | 1,871,872 | 2,199,552 | +327,680 |
| DSPs / PLLs | 0 / 1 | 0 / 1 | 0 / 0 |

Worst setup slack is +1.482 ns and worst hold slack is +0.149 ns. The exact
increase of 40 M10Ks and 327,680 bits proves that the single runtime payload
store is present in the production image; there is no duplicate runtime bank.
The established 11 map, five fitter, and two timing warnings remain 18 total.

## Deliberate exclusions

Phase 4F-D does not implement the Phase 4F-E Linux/HPS iNES loader, Phase 4F-F
physical Cyclone V bridge/CDC adapter, Phase 4F-G end-to-end game boot, microSD
selection, extra mappers, hashes/CRC, or physical-board runtime loading. Those
remain later roadmap items; this phase stops at the verified logical
activation/reset boundary.
