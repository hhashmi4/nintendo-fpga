# Nintendo FPGA

FPGA-based Nintendo Entertainment System project targeting the Terasic
DE1-SoC and its Intel Cyclone V SoC FPGA. The repository implements the Phase 1
platform foundation, the Phase 2A CPU architectural shell, the Phase 2B
reusable ALU, the Phase 2C address generator, the Phase 2D load/store/transfer
subset, the Phase 2E arithmetic/logic subset, the Phase 2F control-flow/stack
subset, Phase 2G reset/interrupt sequencing, Phase 2H cycle/bus timing, the
Phase 2I Ricoh 2A03 compatibility audit, and the Phase 2J completed official
CPU qualification. Phase 2K adds a separate CPU-integrated DE1-SoC diagnostic
image without changing the stable Phase 1 image. All 151 official opcode bytes
are implemented. Phase 3A adds the standalone NTSC PPU timing foundation, and
Phase 3B adds the CPU-facing PPU registers and internal scroll/address state.
Phase 3C adds the complete logical PPU memory map, cartridge CHR interface,
mirrored 2 KiB nametable CIRAM, and palette RAM. Phase 3D adds cycle-accurate
rendering-time scroll/address updates and future background-fetch addresses.
Phase 3E adds the background fetch/shifter pipeline and logical background
pixels. Phase 3F adds real primary/secondary OAM and cycle-scheduled sprite
evaluation. Phase 3G adds cartridge-facing sprite pattern fetches, flip logic,
X counters, shifters, and logical sprite candidates. Phase 3H mixes background
and sprite candidates, reads palette RAM, emits final six-bit NES colors plus
emphasis metadata, and implements sprite-zero hit. Phase 3I adds VBlank/NMI
condition timing and boundary suppression. Phase 3J integrates the CPU, PPU,
2 KiB CPU RAM, NES bus decode, 3:1 scheduler, cartridge boundaries, NMI, and
513/514-cycle OAM DMA as one NES core. Phase 3K adds real-rate NES enables, a
triple M10K framebuffer, safe NES/VGA frame handoff, 2x scaling, deterministic
NES-to-RGB conversion, and a synthesized 640x480 DE1-SoC VGA board image.
Phase 4A separates the NES CPU bus, complete memory decode, mirrored 2 KiB RAM,
and future APU/controller/cartridge boundaries while preserving the verified
CPU, PPU, and DMA behavior. Phase 4B adds strict host-side iNES import, a
replaceable cartridge shell, Mapper 0/NROM-128 and NROM-256 PRG mapping,
CHR ROM/RAM, cartridge-selected nametable mirroring, and a real cartridge
reset-vector boot path. Advanced mappers, physical cartridge loading, and
audio output remain future work. Phase 4C adds two authentic NES serial
controller ports, an abstract synchronized input boundary, DE1-SoC Controller
1 switch mapping, exhaustive protocol verification, and a cartridge program
that polls both ports into CPU RAM. Phase 4D-A extracts the verified OAM DMA
sequencer into a standalone internal bus master with explicit CPU/DMA
arbitration, cartridge-source reads, and expanded passive diagnostics. Native
HDMI remains future work. Phase 4D-B adds a project-owned MIT-licensed playable
NROM-128 image, reproducible cartridge import, controller/NMI/DMA/frame
milestones, a 300-frame sustained regression, and playable-ROM-to-VGA
verification. Phase 4E-A adds an observation-only, once-per-NES-frame debug
snapshot, a coherent toggle/acknowledge transfer into the VGA clock domain,
and a frame-stable destination bank. Phase 4E-B adds an independent direct-
pixel Developer Mode page, compact deterministic font, reusable hexadecimal
formatting, stale/invalid status, and a hard normal-video bypass. The board
image keeps Developer Mode hard-disabled because every slide switch is already
assigned; no physical control mapping changed. Phase 4E-C adds the simultaneous
512x480 exact-2x playable game region and 128x480 compact snapshot panel, with
an explicit boundary compositor and the same pixel-identical normal bypass.
Phase 4E-D adds five frame-latched panel pages that reuse the coherent snapshot,
font, formatter, colors, compositor, and fixed 512/128 geometry. Phase 4E-E adds
acknowledged RUN/PAUSE/instruction-step/frame-step commands, safe full-NES
suspension, and an 818-bit coherent status snapshot while VGA stays active.
Phase 4F-A adds the FPGA-side runtime-loader protocol/control foundation: typed
PRG/CHR byte writes, explicit ready/valid backpressure, deterministic error
states, and a fail-safe NES hold/reset request. Phase 4F-B adds a runtime-
writable 32 KiB PRG/8 KiB CHR endpoint, runtime-selectable NROM-128/NROM-256
translation, preserved CHR-ROM/RAM behavior, and deterministic reset/collision
semantics. Phase 4F-C adds an explicit Mapper-0 image manifest, strict
per-target sequential coverage, deterministic incomplete/ordering errors, and
a staged `image_valid` result. Phase 4F-D adds explicit atomic activation,
production legacy/runtime cartridge selection, a controlled whole-NES reset,
and natural CPU boot through the runtime reset vector. Phase 4F-E adds
dependency-light Linux/HPS software for strict classic-iNES
parsing, Mapper-0 runtime-image validation, exact manifest/load-plan creation,
bounded transport orchestration, and a contract-enforcing mock/dry-run CLI.
Phase 4F-F adds the real Cyclone V lightweight HPS-to-FPGA bridge, a versioned
32-bit MMIO contract, coherent exactly-once command/status CDC, a `/dev/mem`
Linux transport, reproducible Platform Designer integration, and production
HPS/NES/VGA synthesis and timing closure. Phase 4F-G proves the complete
runtime boot path in simulation. Phase 4F-H adds a configurable, safe,
deterministic microSD-style game library with header-only discovery,
supported/unsupported/invalid classification, stable selection, and direct
reuse of the existing loader. Physical board and removable-media validation
remain future work. Phase 5A adds the NTSC APU timing and register foundation:
exact CPU-slot frame sequencing, `$4015` status/control and read side effects,
parity-delayed `$4017` control, frame IRQ state, channel extension interfaces,
and independent Python/RTL model comparison. Phase 5B adds the first sound-
producing channel: register-accurate Pulse 1 duty/timer, envelope, length and
sweep units, raw 0..15 output, the channel-one negate quirk, and real `$4015`
activity. Phase 5C reuses that pulse datapath for Pulse 2, integrates
`$4004-$4007` and `$4015` bit 1, selects the channel-two sweep-negate rule, and
proves both raw 0..15 outputs simultaneously and independently. Phase 5D adds
the every-CPU-cycle Triangle timer, exact 32-step waveform, linear and length
counters, held-DAC semantics, `$4008/$400A/$400B`, and `$4015` bit 2 while
preserving both pulse channels. Phase 5E adds the Noise envelope/length unit,
all 16 NTSC timer periods, deterministic 15-bit long/short-mode LFSR,
`$400C/$400E/$400F`, harmless `$400D`, raw 0..15 output, and `$4015` bit 3.
Phase 5F adds the DMC reader/buffer/output unit, all 16 NTSC rates, raw 0..127
delta DAC, looping and terminal IRQ, `$4010-$4013` plus `$4015` bit 4/bit 7,
and an acknowledged 3/4-slot CPU-space fetch master integrated with CPU and
OAM-DMA arbitration through the runtime Mapper-0 path. Phase 5G closes the
complete raw APU with all-five-channel full-state comparison, exhaustive
`$4015` composition, frame/DMC IRQ interaction, frame-event collisions,
debugger/reset behavior, systematic DMC/OAM/controller stress, and runtime
NROM-128/NROM-256 replacement coverage. Final nonlinear mixing, CPU IRQ
consumption, resampling, and codec output remain later Phase 5 work.

## Phase 1 foundation

- One 50 MHz fabric clock with synchronous clock-enable pulses
- Asynchronous reset assertion and two-stage synchronous release
- Centralized provisional NTSC timing configuration
- Separate board, clock/reset, timing, future-system boundary, and diagnostic concerns
- Self-checking Verilator simulation with optional FST output
- Python timing/reference tests
- Quartus project, timing constraints, build script, and gated deployment script

The architecture and timing limitations are documented in
[`docs/platform-foundation.md`](docs/platform-foundation.md).

## Phase 2A CPU foundation

- 6502-family A, X, Y, SP, PC, and processor-status state
- Deterministic reset values and CPU-enable-only architectural progression
- Phase 2A fetch scaffold, now superseded by Phase 2G reset-vector sequencing
- Execution-state boundaries reserved for later CPU phases
- Independent Python reference tests and focused self-checking RTL simulation

The CPU shell, its reset choices, and its deliberately unimplemented behavior
are documented in [`docs/cpu-phase2a.md`](docs/cpu-phase2a.md).

## Phase 2B CPU ALU

- Binary-only 2A03 ADD/SUB arithmetic and signed-overflow behavior
- AND, OR, XOR, shifts, rotates, increment, decrement, and compare
- Explicit result and N/V/Z/C validity signals for later flag preservation
- Exhaustive Python and RTL verification across every functional input tuple

The ALU interface, carry semantics, flag ownership, and exhaustive coverage are
documented in [`docs/cpu-phase2b-alu.md`](docs/cpu-phase2b-alu.md).

## Phase 2C CPU addressing

- Opcode-independent arithmetic for all base 6502 addressing modes
- Explicit pointer-fetch addresses without hidden memory access
- Zero-page, 16-bit, relative, and NMOS indirect-JMP wrapping behavior
- Page-cross metadata for later instruction timing logic
- Independent Python model and 1,508,186-vector RTL simulation

The interface, wrap rules, bus-sequencing boundary, and exact coverage are
documented in
[`docs/cpu-phase2c-addressing.md`](docs/cpu-phase2c-addressing.md).

## Phase 2D CPU execution subset

- Official LDA, LDX, LDY, STA, STX, STY, and register-transfer opcodes
- Explicit fetch, decode, operand, pointer, memory, and writeback states
- Existing Phase 2C address generator reused for every effective address
- Deterministic unsupported-opcode trap with no bus or architectural effects
- Generic 64 KiB simulation memory and exact bus-trace verification
- 222 directed RTL vectors covering all 37 opcodes with six boundary values

The execution lifecycle, opcode matrix, current functional cycle counts, and
remaining CPU work are documented in
[`docs/cpu-phase2d-load-store-transfer.md`](docs/cpu-phase2d-load-store-transfer.md).

## Phase 2E CPU arithmetic and logic

- Official ADC, SBC, AND, ORA, EOR, CMP, CPX, CPY, INC/DEC, and shift/rotate opcodes
- Verified Phase 2B ALU reused for results and per-flag validity
- Accumulator, register, memory-source, and explicit memory RMW paths
- 516 directed RTL vectors across all 86 new opcodes/addressing combinations
- 2,048 deterministic randomized ADC/SBC instruction executions in Python

The opcode matrix, ALU integration, RMW architecture, current cycle scaffold,
and exact coverage are documented in
[`docs/cpu-phase2e-arithmetic-logic.md`](docs/cpu-phase2e-arithmetic-logic.md).

## Phase 2F CPU control flow and stack

- Official JMP, JSR, RTS, eight conditional branches, PHA, PLA, PHP, and PLP
- Explicit page-1 stack bus cycles with wrapping 8-bit SP behavior
- Phase 2C relative targets and NMOS indirect-JMP pointer wrapping reused
- Nonpersistent B and forced-U internal status policy with PHP synthesis
- 241 directed RTL vectors, 10 enable-stall checks, and deterministic random tests

The PC-redirection paths, stack contract, status representation, step counts,
and exact coverage are documented in
[`docs/cpu-phase2f-control-stack.md`](docs/cpu-phase2f-control-stack.md).

## Phase 2G CPU interrupts and reset

- Bus-visible RESET, NMI, and IRQ/BRK vector fetches
- Synchronized edge-latched NMI and synchronized level-sensitive masked IRQ
- Shared high/low/status stack-entry states for NMI, IRQ, and BRK
- Official BRK and RTI with explicit B/U status-byte representation
- 86 directed RTL vectors, 21 enable stalls, and eight reset-priority checks

The priority policy, vector ordering, status representation, functional step
counts, and verification coverage are documented in
[`docs/cpu-phase2g-interrupts-reset.md`](docs/cpu-phase2g-interrupts-reset.md).

## Phase 2H CPU cycle and bus timing

- Machine-readable timing metadata for every official opcode
- NMOS indexed tentative reads, conditional page repair, and 2/3/4-cycle branches
- Original-value plus modified-value writes for memory RMW instructions
- Canonical stack, JSR/RTS, BRK/RTI, interrupt, and seven-cycle reset sequences
- Independent exhaustive page/branch timing checks and exact RTL bus traces

The timing sources, cycle matrix, bus sequences, exact coverage, and remaining
edge limitations are documented in
[`docs/cpu-phase2h-cycle-timing.md`](docs/cpu-phase2h-cycle-timing.md).

## Phase 2I Ricoh 2A03 audit

- Exhaustive proof that ADC/SBC remain binary with D clear or set
- Explicit B/U stack-byte policy and seven-cycle reset re-audit
- Edge-latched NMI, level IRQ, priority, and corrected PLP IRQ polling delay
- Re-audited indirect-JMP wrapping, NMOS RMW writes, and page penalties
- Audit baseline identified the final ten official bytes completed in Phase 2J

The sources, 6502/2A03 comparison, exact coverage, compatibility assessment,
and deferred edge cases are documented in
[`docs/cpu-phase2i-2a03-audit.md`](docs/cpu-phase2i-2a03-audit.md).

## Phase 2J completed official CPU

- BIT zp/abs, CLC, SEC, CLI, SEI, CLV, CLD, SED, and official NOP
- 56 official mnemonics and all 151 official opcode bytes
- Old-I interrupt polling after CLI/SEI, matching the existing PLP mechanism
- Machine-readable JSON and generated Markdown opcode/cycle/flag matrix
- Verification-only flat 64 KiB program runner
- Klaus Dormann's open functional test passed on RTL with decimal tests disabled
- All 105 unofficial opcode bytes retain the deterministic trap policy

The final architecture, exact coverage, external-test method, synthesis data,
and Phase 3 boundary are documented in
[`docs/cpu-phase2j-final-verification.md`](docs/cpu-phase2j-final-verification.md).
The full opcode artifacts are
[`docs/cpu-official-opcodes.json`](docs/cpu-official-opcodes.json) and
[`docs/cpu-official-opcode-matrix.md`](docs/cpu-official-opcode-matrix.md).

The final local qualification comprises 467 Python tests, 2,382 focused Phase
2J RTL vectors, the complete retained RTL/exhaustive regression, and the Klaus
Dormann open functional test running to its stable success loop on RTL. The
standalone CPU synthesizes to an estimated 717 ALMs, 1,097 ALUTs, and 191
registers; the unchanged board diagnostic remains at 43 ALMs and closes 50 MHz
timing with non-negative slack at every analyzed corner.

## Phase 2K DE1-SoC CPU validation

- Dedicated `cpu_board_diag_top`; the Phase 1 `de1_soc_top` remains unchanged
- Same `CLOCK_50` clock and reset synchronizer, with enable-only run/debug modes
- Flat diagnostic RAM/ROM and bus-visible zero-page, stack, vector, and RMW traffic
- Hardware-generated IRQ, NMI, and multi-cycle `cpu_enable` stall tests
- Deterministic `$A5` PASS signature, section-specific failures, LEDs, and six HEX digits
- Self-checking RTL reaches the actual `$83F0`/`$4C` PASS loop in 518 enabled cycles
- CPU-integrated image fits in 3,244 ALMs and closes 50 MHz timing
- Volatile programming completed; physical LED/HEX observation is still required

The architecture, program, result codes, synthesis data, programming record,
and observation checklist are documented in
[`docs/cpu-phase2k-board-validation.md`](docs/cpu-phase2k-board-validation.md).

## Phase 3A PPU timing foundation

- NTSC 341-dot, 262-scanline timing with visible/post-render/vblank/pre-render regions
- Visible coordinates at dots 1-256 for exactly 61,440 pixels per frame
- Vblank set at 241:1 and cleared at 261:1 with precise event outputs
- Explicit even/odd parity and the rendered odd-frame `261:339 -> 0:0` skip
- Single fabric clock with complete `ppu_enable` state and event gating
- Independent Python model and 1,336,451-cycle RTL/reference comparison

The timing convention, enable contract, verification evidence, synthesis data,
and deliberately deferred PPU features are documented in
[`docs/ppu-phase3a-timing.md`](docs/ppu-phase3a-timing.md).

## Phase 3B PPU register interface

- `$2000-$2007` register decode mirrored exhaustively through `$3FFF`
- PPUCTRL/PPUMASK/PPUSTATUS state and deterministic digital open-bus behavior
- Canonical `v/t/x/w` PPUSCROLL and PPUADDR programming sequences
- Abstract OAMDATA and buffered PPUDATA interfaces for later memory phases
- PPUMASK-driven Phase 3A odd-frame timing and timing-driven status vblank
- Independent Python model and 208,249-cycle RTL/reference comparison

The CPU transaction contract, register semantics, memory abstraction,
integration proof, verification evidence, synthesis data, and deferred PPU
features are documented in
[`docs/ppu-phase3b-register-interface.md`](docs/ppu-phase3b-register-interface.md).

## Phase 3C PPU memory map

- Complete `$0000-$3FFF` region decoding and `$3000-$3EFF` normalization
- External cartridge CHR read/write interface with no production fake memory
- 2 KiB CIRAM with vertical, horizontal, and both single-screen mappings
- 32-byte palette RAM with complete repetition and universal-color aliases
- Real Phase 3B buffered/immediate PPUDATA reads and exactly-once writes
- MLAB-inferred storage plus exhaustive and randomized Python/RTL verification

The decoder, mirroring rules, storage implementation, PPUDATA integration,
verification evidence, synthesis data, and deferred rendering features are
documented in [`docs/ppu-phase3c-memory-map.md`](docs/ppu-phase3c-memory-map.md).

## Phase 3D PPU scroll engine

- One-owner rendering-time updates of the canonical `v/t/x/w` state
- Coarse-X wrapping, fine/coarse-Y rules, and correct nametable toggles
- Dot-257 horizontal reload and pre-render dots 280-304 vertical reload
- PPUMASK and `ppu_enable` gating with active-render `$2007` increments
- Future nametable and attribute fetch-address helpers
- Exhaustive helper/state tests and 758,097-cycle integrated RTL comparison

The algorithms, dot timing, CPU/render priority, verification evidence,
synthesis results, and deferred bus-conflict accuracy are documented in
[`docs/ppu-phase3d-scroll-engine.md`](docs/ppu-phase3d-scroll-engine.md).

## Phase 3E PPU background renderer

- Two-dot NT/attribute/pattern-low/pattern-high fetch scheduling
- Cartridge CHR and mirrored CIRAM access through the Phase 3C memory system
- Attribute-quadrant decoding and PPUCTRL-selected pattern addressing
- Four rolling 16-bit pattern/attribute shifters with MSB-first pixels
- Fine-X selection, PPUMASK background gating, and left-eight-pixel clipping
- Pre-render/scanline prefetch plus deterministic CPU/renderer arbitration
- Full-frame and randomized Python/RTL pixel-stream comparison

The fetch timing, memory latency contract, arbitration policy, shifter bit
orientation, verification evidence, synthesis results, and deferred sprite/video
features are documented in
[`docs/ppu-phase3e-background-renderer.md`](docs/ppu-phase3e-background-renderer.md).

## Phase 3F PPU sprite evaluation

- Synthesizable 256-byte primary OAM behind real `$2003/$2004` accesses
- Two-dot 32-byte secondary-OAM clearing during visible dots 1-64
- Odd-read/even-process sprite evaluation during dots 65-256
- First-eight OAM priority, original-index metadata, and sprite-zero selection
- Exhaustive 8x8/8x16 range verification with eight-bit Y arithmetic
- Documented diagonal `n/m` sprite-overflow bug and PPUSTATUS integration
- Stable eight-slot handoff interface for Phase 3G sprite fetches

The storage architecture, cycle timing, collision policy, overflow fidelity,
verification evidence, synthesis results, and deferred sprite renderer are
documented in
[`docs/ppu-phase3f-sprite-evaluation.md`](docs/ppu-phase3f-sprite-evaluation.md).

## Phase 3G PPU sprite renderer

- Eight two-dot-access sprite fetch groups across dots 257-320
- Exhaustively verified 8x8/8x16 CHR addressing and vertical flipping
- Cartridge-facing low/high pattern fetches with horizontal-flip loading
- Eight X counters and pattern-shifter pairs with `ppu_enable` stall safety
- First-opaque OAM-order selection with palette, priority, and sprite-zero metadata
- PPUMASK sprite enable and independent left-eight-pixel clipping
- Full-frame primary-OAM-to-logical-pixel RTL/reference comparison

The fetch cadence, CHR formulas, shifter orientation, arbitration policy,
verification evidence, synthesis results, and Phase 3H boundary are documented
in
[`docs/ppu-phase3g-sprite-renderer.md`](docs/ppu-phase3g-sprite-renderer.md).

## Phase 3H PPU pixel mixer

- Explicit universal/background/sprite transparency and priority selection
- Exact background and sprite palette-address generation through Phase 3C RAM
- Six-bit NES color output, PPUMASK grayscale, and emphasis metadata
- Sprite-zero-hit event with original-OAM identity, left masks, and X=255 rule
- Existing PPUSTATUS latch integration without changing vblank or overflow
- Stall-safe 256x240 logical pixel stream for future VGA or HDMI modules
- Full-frame integrated RTL/reference comparison across all 61,440 pixels

The mixer rules, palette lookup, status behavior, video boundary, verification,
synthesis results, and deferred RGB/video work are documented in
[`docs/ppu-phase3h-pixel-mixer.md`](docs/ppu-phase3h-pixel-mixer.md).

## Phase 3I PPU VBlank and NMI

- Single-owner PPUSTATUS VBlank set at 241:1 and pre-render clear at 261:1
- Active-high NMI condition from `status_vblank && PPUCTRL[7]`
- One-pulse activation events without retriggering a continuously active level
- Immediate events when NMI is enabled during an uncleared VBlank
- Repeated events after deliberate disable/re-enable condition transitions
- Explicit 241:0 through 241:2 PPUSTATUS boundary-suppression model
- Stall-safe ten-frame randomized Python/RTL comparison and Phase 3J interface

The status ownership, NMI equation, accepted-access race convention, CPU-side
interface boundary, verification evidence, synthesis results, and deferred
sampling alignment are documented in
[`docs/ppu-phase3i-nmi-vblank.md`](docs/ppu-phase3i-nmi-vblank.md).

## Phase 3J CPU/PPU integration

- One-clock `PPU, PPU, PPU+CPU-slot` scheduler with an exact logical 3:1 ratio
- Synthesizable 2 KiB CPU RAM mirrored through `$1FFF`
- PPU-register routing across `$2000-$3FFF` and deterministic open I/O space
- Separate cartridge-facing PRG and existing cartridge-facing CHR interfaces
- Active-high PPU NMI level connected to the CPU's verified edge synchronizer
- `$4014` OAM DMA with CPU stall, uninterrupted PPU operation, and 513/514 slots
- CPU programs that configure the PPU, execute NMI handlers, DMA OAM, and move
  a sprite in the final pixel stream

The scheduler phase, memory map, DMA state machine, NMI sampling result,
verification evidence, synthesis results, and deferred video/controller work
are documented in
[`docs/phase3j-cpu-ppu-integration.md`](docs/phase3j-cpu-ppu-integration.md).

## Phase 3K DE1-SoC VGA output

- NTSC-average PPU/CPU enables at 5.369318182/1.789772727 MHz with exact 3:1
- PLL-derived 25.2 MHz, 800x525, active-low-sync 640x480p60 VGA
- Three 256x240x9 dual-clock M10K framebuffers with frame-safe CDC ownership
- Exact centered 2x scaling to 512x480 and two black 64-pixel side borders
- Deterministic 64-color RGB palette and digital emphasis approximation
- Independent switch-selected color bars and CPU/PPU/DMA-driven NES scene
- Two complete 307,200-pixel Python comparisons with zero mismatches
- Dedicated board top and SOF/RBF flow; physical monitor confirmation pending

Architecture, board pins, clocking, framebuffer handoff, tests, build data,
Mac programming commands, physical expectations, and troubleshooting are in
[`docs/phase3k-de1soc-vga.md`](docs/phase3k-de1soc-vga.md).

## Phase 4A system bus integration

- Dedicated CPU decoder/router with one-owner read-data arbitration
- One physical 2 KiB CPU RAM mirrored through `$1FFF`
- Existing eight PPU registers mirrored through `$3FFF` without duplication
- Direction-correct APU, `$4014` DMA, and `$4016/$4017` controller boundaries
- Replaceable full-address cartridge CPU interface for `$4020-$FFFF`
- Passive CPU, PPU, DMA, and selected-target diagnostic outputs
- Exhaustive 65,536-address Python checks and 131,072 read/write RTL vectors
- Preserved one-clock, clock-enable-only 3:1 PPU/CPU relationship

The memory map, interfaces, reset/clock contracts, verification, and future
VGA/debug/HDMI architecture are documented in
[`docs/phase4a-system-bus.md`](docs/phase4a-system-bus.md).

## Phase 4B Mapper 0 cartridge subsystem

- Strict iNES 1.0 validation and reproducible PRG/CHR/JSON conversion tooling
- Generic CPU/PPU cartridge boundary with Mapper 0 behind the Phase 4A bus
- NROM-128 16 KiB PRG mirroring and NROM-256 direct 32 KiB mapping
- 8 KiB CHR ROM and writable 8 KiB CHR RAM configurations
- Optional 8 KiB PRG RAM architecture at `$6000-$7FFF`
- Horizontal/vertical cartridge metadata wired into the existing PPU CIRAM map
- Project-owned boot/display/mapping fixtures generated without commercial ROMs
- Real CPU reset-vector boot and CPU-to-PPU-to-CHR integration verification
- M10K-inferred PRG/CHR storage in the DE1-SoC board image

The format rules, mapper data flow, fixtures, reset boot proof, observability,
synthesis results, and future-mapper boundary are documented in
[`docs/phase4b-cartridge-nrom.md`](docs/phase4b-cartridge-nrom.md).

## Phase 4C controller subsystem

- Shared `$4016` strobe with simultaneous falling-edge latch of both ports
- Independent A/B/Select/Start/Up/Down/Left/Right shift registers
- `$4016` Controller 1 reads and `$4017` Controller 2 reads on deterministic D0
- NES-compatible logical ones after each eight-button sequence
- Preserved `$4017` write path for the future APU frame counter
- Abstract two-controller state vectors outside `nes_core`
- Two-flop DE1-SoC input synchronization and SW2-SW9 Controller 1 mapping
- Exhaustive 256-state-per-port Python and RTL protocol checking
- Real cartridge-driven CPU polling into RAM `$0010/$0011`
- Passive live, latched, index, serial, strobe, and access diagnostics

The protocol, board mapping, synchronization/debounce decision, end-to-end
data flow, verification, physical procedure, and Phase 4D boundary are in
[`docs/phase4c-controllers.md`](docs/phase4c-controllers.md).

## Phase 4D-A OAM DMA bus master

- Existing 513/514-slot sequencer extracted into `nes_oam_dma`
- Explicit CPU/DMA ownership in `nes_internal_bus_arbiter`
- Preserved dummy, optional alignment, read/write, and completion behavior
- Full 256-byte source sequence and `$2004` destination semantics
- CPU RAM mirror, PPU-register, cartridge, and deterministic I/O-source policy
- Verified cartridge-page DMA through the existing Mapper 0 interface
- Stable CPU architectural state during stalls and exact post-DMA resume
- NMI tests before, during, near completion, and immediately after DMA
- Controller isolation and passive owner/source/phase diagnostics

The preserved behavior, arbitration rules, verification, and Phase 4D-B
playable-ROM recommendation are documented in
[`docs/phase4d-a-oam-dma-bus-master.md`](docs/phase4d-a-oam-dma-bus-master.md).

## Phase 4D-B playable NROM validation

- Project-owned, MIT-licensed NROM-128 game image with no commercial ROM data
- Start-controlled gameplay, eight-button polling, bounded movement, backgrounds,
  sprites, VBlank NMI, and one page-$02 OAM DMA per gameplay frame
- Strict iNES metadata/vector checks and byte-identical source regeneration
- Nine deterministic 256x240 FPGA PPU frame hashes and viewable PPM artifacts
- 300-frame sustained CPU/controller/NMI/DMA/PPU integration regression
- Actual cartridge-to-framebuffer-to-640x480 VGA path comparison
- Sparse-enable synchronous-CHR compatibility fix with focused regression
- The Phase 4D-B playable image was subsequently validated on physical hardware

The ROM, import flow, compatibility fix, simulation evidence, Quartus results,
programming command, and physical checklist are documented in
[`docs/phase4d-b-playable-rom-validation.md`](docs/phase4d-b-playable-rom-validation.md).

## Phase 4E-A Developer Mode snapshot foundation

- Grouped 711-bit CPU, PPU, cartridge, controller, DMA, and system snapshot
- Deterministic capture at PPU frame start, plus a reserved manual trigger
- Stable source bank and bundled-data toggle/acknowledge CDC into `pixel_clk`
- Renderer-facing bank changes only at a VGA frame boundary
- Monotonic snapshot/frame IDs, sticky interval events, and lightweight counters
- Internal Developer Mode enable reserved and tied off because SW0-SW9 are occupied
- Focused asynchronous-clock/reset/FST test and playable 300-frame integration
- Normal output remains pixel-identical to all nine Phase 4D-B frame hashes

The field layout, CDC contract, verification, build comparison, and exact
Phase 4E-B renderer recommendation are documented in
[`docs/phase4e-a-devmode-snapshot.md`](docs/phase4e-a-devmode-snapshot.md).

## Phase 4E-B graphical Developer Mode renderer

- Full-screen 640x480 diagnostic page generated directly from coordinates
- 6x8 ROM-style uppercase font in 8x16 text cells, with no debug framebuffer
- CPU, PPU, cartridge, controllers, DMA, snapshot health, and system counters
- Deterministic 8-, 16-, and 32-bit uppercase hexadecimal formatting
- Four-frame stale threshold plus explicit `VALID`, `INVALID`, and `STALE`
- Renderer consumes only the Phase 4E-A stable video-domain snapshot
- Explicit RGB mux preserves normal pixels; HSYNC, VSYNC, and blanking bypass it
- Exhaustive 352-row glyph comparison and all 307,200 active pixels matched
  independently modeled Python output
- Board parameter defaults Developer Mode off; SW0-SW9 and KEY0 are unchanged

Architecture, layout, verification, resources, timing, and the Phase 4E-C
side-panel recommendation are documented in
[`docs/phase4e-b-devmode-renderer.md`](docs/phase4e-b-devmode-renderer.md).

## Phase 4E-C game and Developer side panel

- Developer Mode maps the 256x240 NES framebuffer at exact 2x scale to
  `x=0..511`, `y=0..479`
- A compact 16-column by 30-row snapshot panel occupies only `x=512..639`
- The Phase 4E-B 6x8 font, hexadecimal helpers, colors, and stale logic are
  reused without a debug framebuffer
- CPU, PPU, cartridge, Controller 1, DMA, source-frame, snapshot, NMI, and DMA
  state remain continuously visible
- One final compositor proves the hard `x=511` game / `x=512` panel boundary
- SW0 test bars and SW1 framebuffer freeze retain their established semantics;
  the panel continues to receive snapshots while the game capture is frozen
- Focused and real playable-ROM combined frames are independently compared at
  all 307,200 active pixels
- Normal Mode remains the literal existing NES RGB path and retains all nine
  Phase 4D-B hashes; board Developer Mode still defaults off

Architecture, compact layout, mode priority, verification, resources, timing,
and the Phase 4E-D page recommendation are documented in
[`docs/phase4e-c-devmode-side-panel.md`](docs/phase4e-c-devmode-side-panel.md).

## Phase 4E-D multiple Developer Mode pages

- Five frame-latched panel pages: Overview, CPU/Bus, PPU/Cartridge,
  DMA/Controllers, and System/Performance
- Page requests queue during a frame and commit atomically at VGA frame start
- Reset selects Page 0 and page-next wraps `0 -> 1 -> 2 -> 3 -> 4 -> 0`
- All pages reuse the same coherent 711-bit video-domain snapshot, font,
  formatting helpers, panel colors, compositor, and 512/128 geometry
- Common `VALID`, `INVALID`, and `STALE` status is visible on every page
- Five complete 640x480 RTL frames are compared against the independent
  Python reference at all 307,200 active pixels per page
- The internal virtual controls leave SW0, SW1, SW2-SW9, and KEY0 unchanged;
  the production board image still defaults Developer Mode off

Architecture, controls, layouts, verification, resources, timing, and the
Phase 4E-E debugger-control recommendation are documented in
[`docs/phase4e-d-devmode-pages.md`](docs/phase4e-d-devmode-pages.md).

## Phase 4E-E interactive Developer debugger

- Dedicated execution controller authorizes existing scheduler enables; no clock gating.
- PAUSE drains the instruction/interrupt entry and OAM DMA before freezing NES progression.
- STEP-I retires one opcode, including its bus/stack cycles and resulting DMA.
- STEP-F crosses the next scanline 0/dot 0 event, then drains in-flight work;
  its possible post-boundary overrun is measured in the pause snapshot.
- Acknowledged event CDC, sequence/result readback, and abstract virtual controls
  preserve all existing physical switch/reset assignments.
- Paused snapshots, page navigation, scanout, and stale-fault detection stay active.
- Three framebuffer banks retain completed frames across pause-induced scanout phase shifts.

Architecture, exact NMI/frame-step contracts, timing hardening, baseline/final
verification, and the Phase 4F-A HPS interface recommendation are documented in
[`docs/phase4e-e-interactive-debugger.md`](docs/phase4e-e-interactive-debugger.md).

## Phase 4F-A — HPS ↔ FPGA Runtime Loader Interface

- Separate loader command/data path; the HPS never impersonates the NES CPU
- Typed `BEGIN`, `WRITE`, and `COMMIT` commands with PRG/CHR targets
- Explicit 16-bit byte offsets: PRG `$0000-$7FFF`, CHR `$0000-$1FFF`
- Ready/valid backpressure propagated from the future storage endpoint
- Latched, classified errors with recovery through reset or a fresh `BEGIN`
- Fail-safe NES hold/reset request asserted in IDLE, LOADING, and ERROR
- Isolated integration boundary leaves the existing cartridge and board image
  unchanged; Phase 4F-B subsequently added standalone runtime storage
- Independent Python model, fixed-seed randomized vectors, directed RTL tests,
  Verilator assertions, and standalone Cyclone V synthesis check

FPGA-side runtime-loader protocol/control foundation implemented and verified
in simulation. Runtime `.nes` loading, microSD access, and physical HPS
communication are not implemented. Architecture and exact protocol semantics
are documented in
[`docs/phase4f-a-hps-runtime-loader.md`](docs/phase4f-a-hps-runtime-loader.md).

## Phase 4F-B — Runtime Mapper-0 cartridge storage

- 32 KiB PRG and 8 KiB CHR byte stores written by validated Phase 4F-A writes
- Runtime-selectable NROM-128 16 KiB mirroring and NROM-256 direct mapping
- Real loader → storage → Mapper-0 → CPU/PPU integration path
- Preserved CHR-ROM ignored-write and CHR-RAM PPU-write behavior
- Reset-masked reads with retained storage contents
- Explicit same-address write-first reads and loader priority over PPU writes
- Independent model, 12,021 fixed-seed operations, directed RTL boundaries,
  full regression coverage, and standalone Cyclone V timing/resource proof
- Existing build-time playable cartridge and production board path unchanged

Runtime cartridge byte storage and Mapper-0 reads are implemented and verified.
Image activation is intentionally deferred. Architecture,
collision/reset contracts, verification, and synthesis results are documented
in [`docs/phase4f-b-runtime-cartridge-storage.md`](docs/phase4f-b-runtime-cartridge-storage.md).

## Phase 4F-C — Runtime image validation

- Explicit `BEGIN` manifest for mapper, exact PRG/CHR sizes, CHR-ROM/RAM, and
  horizontal/vertical mirroring
- Supported Mapper-0 configurations: 16 KiB or 32 KiB PRG, with either an
  8 KiB CHR-ROM payload or CHR-RAM with no ROM payload
- Strict sequential coverage tracked independently for PRG and CHR, allowing
  target interleaving without any coverage RAM
- Deterministic rejection of malformed manifests, unsupported configurations,
  duplicate/gapped/reversed writes, range violations, and early commits
- `image_valid` status separated from cartridge activation and NES reset release
- Reset and every fresh `BEGIN` invalidate stale coverage and staged validity
- Independent Python oracle, 40 unit tests, and a 123,016-check RTL integration
  proof through loader, storage, Mapper 0, and CPU/PPU readback
- Standalone Cyclone V proof preserves exactly 40 M10Ks and closes 50 MHz timing

The future HPS/Linux loader must emit sequential byte addresses within each
target; PRG and CHR streams may interleave. Architecture, correctness proof,
error/recovery contract, verification, and synthesis results are documented in
[`docs/phase4f-c-runtime-image-validation.md`](docs/phase4f-c-runtime-image-validation.md).

## Phase 4F-D — Atomic runtime cartridge activation

- Explicit canonical `ACTIVATE` command; a completed image remains staged and
  held until software requests activation
- Atomic latching of runtime selection, PRG size, CHR-ROM/RAM mode, mapper,
  and nametable mirroring metadata
- Single 32 KiB PRG + 8 KiB CHR store reused safely while the complete NES is
  held; no resource-expensive payload double buffer
- Production legacy/runtime cartridge mux preserves the build-time playable
  ROM whenever no runtime session has begun
- Four-cycle controlled functional reset covers CPU, PPU, scheduler, system
  bus, DMA, controllers, debugger, framebuffer write side, and debug capture
- Natural `$FFFC/$FFFD` reset-vector fetch and instruction execution verified
  for both mirrored NROM-128 and direct-mapped NROM-256
- Runtime CHR-ROM reads/write protection, zero-payload CHR-RAM writes,
  repeated activation, replacement loading, DMA/NMI reset, and failure safety
- Independent activation-policy model plus a focused NES-core RTL integration
  proof; the normal legacy/playable/debugger regression remains unchanged

Architecture, exact command/reset semantics, verification, and synthesis
results are documented in
[`docs/phase4f-d-runtime-image-activation.md`](docs/phase4f-d-runtime-image-activation.md).

## Phase 4F-E — Linux/HPS iNES loader software

- Strict classic-iNES parsing with exact payload boundaries and explicit
  rejection of NES 2.0, trainers, four-screen, battery saves, console variants,
  unsupported mappers/bank counts, truncation, and trailing bytes
- Validated `RuntimeImage` boundary for NROM-128/NROM-256 with 8 KiB CHR-ROM
  or zero-payload CHR-RAM and horizontal/vertical mirroring
- Centralized command, target, manifest, state, error, size, and mirroring
  encodings checked against the RTL package
- Lazy deterministic load plan: `BEGIN`, sequential physical PRG, sequential
  CHR-ROM when present, `COMMIT`, wait-valid, `ACTIVATE`, wait-active
- Physical-transport-neutral interface with bounded command, validation, and
  activation waits; no MMIO addresses or fake FPGA communication
- Contract-enforcing deterministic mock with command recording, configurable
  backpressure/status delays, failure injection, and timeout coverage
- `inspect` and complete `load --dry-run` CLI workflows plus four generated,
  original synthetic iNES fixtures and 40 focused tests

Run the loader from the repository root:

```bash
python3 scripts/nes_loader.py inspect game.nes
python3 scripts/nes_loader.py load game.nes --dry-run
```

Architecture, the exact RTL-derived software contract, format policy,
timeouts, mock behavior, and verification are documented in
[`docs/phase4f-e-linux-hps-ines-loader.md`](docs/phase4f-e-linux-hps-ines-loader.md).

## Phase 4F-F — Cyclone V HPS ↔ FPGA runtime-loader bridge

- Cyclone V lightweight HPS-to-FPGA AXI path converted to a 32-bit Avalon-MM
  loader aperture by a source-controlled Platform Designer system
- Generated address-map validation: HPS lightweight window plus the actual
  assigned slave offset, shared with RTL and Python through one JSON contract
- Versioned magic/version/capability registers, explicit manifest fields,
  typed status/errors, a one-entry command bank, and completion counter
- Held-bundle request/acknowledge CDC between the HPS user clock and 50 MHz
  loader domain, with three-stage toggle synchronizers and coherent return
  status snapshots
- Production `MmioRuntimeLoaderTransport`, page-correct `/dev/mem` mapping,
  bounded polling, endpoint compatibility checks, and useful typed errors
- Faithful fake-MMIO software co-verification and a self-checking asynchronous
  RTL test with backpressure, reset recovery, and a complete 16 KiB transfer
- Integrated HPS + NES/VGA Quartus build with successful fit, assembly, fully
  constrained TimeQuest analysis, and non-negative slack in every corner

Run a real HPS load with the target image's required `/dev/mem` permissions:

```bash
python3 scripts/nes_loader.py load game.nes
```

No physical HPS↔FPGA communication is claimed in this phase. Board bootloader/
preloader integration and on-board validation remain Phase 4F-I. Architecture,
the exact register map, CDC/reset reasoning, address derivation, software
backend, build procedure, verification, and physical limits are documented in
[`docs/phase4f-f-hps-fpga-bridge.md`](docs/phase4f-f-hps-fpga-bridge.md).

## Phase 4F-G — End-to-end runtime `.nes` boot validation

- Project-owned legal NROM-128/CHR-ROM and NROM-256/CHR-RAM images generated
  deterministically at test time
- Real iNES parser, lazy load plan, and production MMIO transport generate the
  software-visible trace consumed through the real RTL MMIO bank and CDC
- Asynchronous clocks and a deterministic stall on every delivered command;
  exact 16,384/8,192 and 32,768/0 PRG/CHR transfer counts
- Natural `$FFFC/$FFFD` reset-vector fetches, unique CPU RAM signatures, NMI,
  OAM DMA, controller input, CHR-ROM rendering, and CHR-RAM write/readback
- Pixel-perfect 61,440-pixel runtime-CHR frame comparison with zero mismatches
- Same-configuration Game A → failed replacement → Game B sequence proving
  safe hold behavior, fresh-`BEGIN` recovery, and atomic replacement
- Malformed image rejection before any MMIO write and injected transport
  failure proving that activation is never issued

This is an end-to-end software/RTL simulation proof, not physical DE1-SoC
HPS↔FPGA validation. Physical validation remains Phase 4F-I. Architecture,
trace format, exact acceptance results, and failure behavior are documented in
[`docs/phase4f-g-runtime-boot-e2e.md`](docs/phase4f-g-runtime-boot-e2e.md).

## Phase 4F-H — microSD game library and selection

- Configurable `--library PATH` or `NES_LIBRARY_ROOT`; no fixed Linux mount
  point and a clear distinction between missing media and an empty library
- Non-recursive, case-insensitive `.nes` discovery with deterministic Unicode
  sorting and stable exact relative-filename IDs
- Header-only metadata scan through the existing iNES parser, exposing mapper,
  PRG/CHR type and size, mirroring, support state, and useful failure reasons
- Unsupported and corrupt games stay visible but cannot reach the load plan or
  transport
- Symlinks and non-regular files rejected; traversal, nested/absolute paths,
  media removal, changed files, read errors, spaces, Unicode, long names, and
  duplicate display names handled explicitly
- `list`, `info`, and `load-library` CLI commands; `load-library --dry-run`
  reuses the complete Phase 4F-E load plan and mock transport
- Original generated mixed-library fixtures and a 256-game header-scan test;
  no commercial ROM data and no writes to removable media

Generate fixtures and exercise the operator workflow:

```bash
python3 scripts/generate_game_library_fixtures.py build/game-library
python3 scripts/nes_loader.py list --library build/game-library
python3 scripts/nes_loader.py info "Alpha Test.nes" --library build/game-library
python3 scripts/nes_loader.py load-library "Alpha Test.nes" \
  --library build/game-library --dry-run
```

Architecture, discovery/security policy, CLI behavior, and verification are
documented in
[`docs/phase4f-h-microsd-game-library.md`](docs/phase4f-h-microsd-game-library.md).

## Phase 5A — APU foundation

- Single-clock APU state driven by the complete NES CPU-time slot stream
- Debugger pause freezes APU time; stepping resumes deterministically; OAM DMA
  continues to advance it while the CPU core is stalled
- Exactly-once `$4000-$4013` future-channel write events
- `$4015` channel-enable state, real active-status separation, frame-IRQ
  reporting/read-clear, and explicit future DMC status/clear boundaries
- Exact NTSC 4-step/5-step quarter- and half-frame event positions
- Immediate IRQ inhibit plus parity-dependent three/four-cycle `$4017` apply
- Production bus integration preserving `$4014`, `$4016`, and direction-split
  `$4017` controller/APU behavior
- Independent Python oracle, directed unit tests, and 142,214-cycle randomized
  RTL state/output comparison
- No channel waveform, mixer, DMC DMA, codec, or audible output in this phase

Architecture, timing sources and assumptions, register semantics, future APU
boundaries, and verification are documented in
[`docs/apu-phase5a-foundation.md`](docs/apu-phase5a-foundation.md).

## Phase 5B — APU Pulse 1

- Authentic `$4000-$4003` register semantics and `$4015` enable/active behavior
- Explicit eight-step implementations of all four NES pulse duty sequences
- Every-other-CPU-cycle 11-bit timer with the period-below-8 mute rule
- Quarter-frame envelope and half-frame length/sweep clocks from Phase 5A
- Shared 32-entry length table and Pulse 1 one's-complement negate quirk
- Raw four-bit channel amplitude only; no mixer, resampler, or board audio path
- Independent Python model, directed waveform/math tests, and a 220,195-cycle
  fixed-seed RTL state/output comparison with FST capture

Architecture, register semantics, timing, verification, synthesis results, and
limitations are documented in
[`docs/apu-phase5b-pulse1.md`](docs/apu-phase5b-pulse1.md).

## Phase 5C — APU Pulse 2

- A second instance of the proven shared pulse RTL for `$4004-$4007`
- Explicit Pulse 2 two's-complement sweep-negate behavior, differing from
  Pulse 1 by exactly one timer count for negative sweeps
- Independent duty phase, timer, envelope, length, sweep, enable, status, and
  raw four-bit amplitude for each pulse channel
- Shared Phase 5A quarter/half-frame events and complete CPU-time slot stream;
  no duplicate bus decoder or frame sequencer
- All four `$4015` Pulse 1/Pulse 2 enable and active-status combinations
- 36 directed Python tests plus a 272,426-cycle fixed-seed, top-level dual-pulse
  RTL/model comparison with zero mismatches and FST waveform capture
- No mixer, resampler, sample pipeline, or board audio path in this phase

Architecture, channel differences, simultaneous operation, verification,
synthesis results, and limitations are documented in
[`docs/apu-phase5c-pulse2.md`](docs/apu-phase5c-pulse2.md).

## Phase 5D — APU Triangle

- Authentic `$4008`, `$400A`, and `$400B` behavior with reserved `$4009`
  ignored and `$4015` bit 2 providing independent enable/active status
- Exact 32-step 0..15 digital waveform and 11-bit timer clocked on every
  accepted CPU/APU time slot
- Quarter-frame linear counter with exact reload-flag/control semantics and
  shared half-frame length counter whose halt uses the same control flag
- Sequencer advancement gated by nonzero linear and length counters while the
  raw DAC code holds its current value; periods 0 and 1 remain digitally active
- Simultaneous independent Pulse 1, Pulse 2, and Triangle outputs with pause,
  step, DMA, reset, register-isolation, and all `$4015` combinations verified
- 108 directed Python cases plus a 314,560-cycle fixed-seed top-level
  RTL/model comparison with zero mismatches and all 32 positions observed
- No Noise, DMC, mixer, resampler, sample pipeline, or board audio path in
  this phase

Architecture, register behavior, counter semantics, waveform verification,
synthesis results, and limitations are documented in
[`docs/apu-phase5d-triangle.md`](docs/apu-phase5d-triangle.md).

## Phase 5E — APU Noise

- Authentic `$400C`, `$400E`, and `$400F` behavior with unused `$400D`
  accepted harmlessly and `$4015` bit 3 providing enable/active status
- Shared quarter-frame envelope and half-frame length events, with independent
  state from both pulse envelopes and the existing shared length table
- All 16 centralized NTSC periods driving an every-other-CPU-slot divider
- Deterministic 15-bit right-shifting LFSR: bit 0 XOR bit 1 in normal mode,
  bit 0 XOR bit 6 in short mode, one seed, and bit-0 output gating
- Simultaneous independent Pulse 1, Pulse 2, Triangle, and Noise raw outputs;
  pause, step, DMA, reset, register isolation, and all status masks verified
- 106 directed Python cases plus a 371,608-cycle fixed-seed top-level
  RTL/model comparison with 6,930 exact LFSR shifts and zero mismatches
- No DMC, mixer, resampler, sample pipeline, or board audio path in this phase

Architecture, period/LFSR semantics, deterministic sequences, verification,
synthesis results, and limitations are documented in
[`docs/apu-phase5e-noise.md`](docs/apu-phase5e-noise.md).

## Phase 5F — APU DMC

- Authentic `$4010-$4013` reader/output semantics and `$4015` start, stop,
  active-status, and IRQ-clear behavior
- Centralized 16-entry NTSC rate table, one-byte sample buffer, LSB-first
  output shifter, silence state, and saturating seven-bit delta DAC
- Exact programmed address/length expansion, one decrement per acknowledged
  byte, looping/terminal IRQ, and explicit `$FFFF->$8000` sample wrap
- Held request/stable address/one-ack memory protocol through the existing CPU
  address decoder and production runtime Mapper-0 PRG path
- Write-safe parity-based 3/4-slot CPU stall with deterministic DMC-over-OAM
  arbitration; OAM resumes without data loss or altered 513/514 internal count
- Pause, single-step, reset-during-request, controller non-duplication, active
  runtime-game replacement, and generated cartridge-sample coverage
- Independent Python channel/DMA models and a 143,324-cycle DMC RTL/model
  comparison with 155 acknowledged bytes and zero mismatches
- Raw 0..127 output only; no mixer, resampler, WAV, I2S, or codec path

Architecture, timing accuracy boundary, bus arbitration, runtime integration,
verification, synthesis results, and limitations are documented in
[`docs/apu-phase5f-dmc.md`](docs/apu-phase5f-dmc.md).

## Phase 5G — complete APU closure

- Complete pre-mixer `ApuModel`/`CompleteApuState` spanning the frame
  sequencer, both pulses, Triangle, Noise, DMC, both IRQs, `$4015`, `$4017`,
  and DMC memory transactions
- Exhaustive 32-mask `$4015` enable/activity coverage and independent frame/
  DMC IRQ set, coexistence, read-clear, write-clear, and reset behavior
- Real-channel 4-step/5-step, parity-delay, adjacent-event, and register-write
  collision tests with explicit pre-edge event ordering
- Simultaneous five-source pause, debugger step, OAM-time, reset, disable,
  dense-write, and long-run stability tests
- Systematic DMC/OAM collision placement, controller-read non-duplication,
  and all-active runtime replacement from NROM-128 to NROM-256
- A 759,254-cycle fixed-seed full-output/377-bit-state RTL comparison with
  600,000 randomized cycles, 398 DMC acknowledgements, and zero mismatches
- Five separate raw outputs only; no mixer, PCM/WAV, resampling, I2S, or codec

Architecture audit, deferred-issue inventory, event ordering, integration
coverage, baseline, and qualification results are documented in
[`docs/apu-phase5g-completion.md`](docs/apu-phase5g-completion.md).

## Development environment

- Terasic DE1-SoC (`5CSEMA5F31C6`)
- Quartus Prime Lite 23.1.1
- SystemVerilog
- Verilator
- Python 3 and pytest
- openFPGALoader on the remote Mac programming host

Create a repository-local Python environment and install the pinned development
dependency:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements-dev.txt
```

If `python3 -m venv` reports that `ensurepip` is unavailable, install the venv
support package supplied by the host distribution and retry. No dependency
installation is performed by repository scripts, and `.venv` is ignored by
Git.

## Verification

Run the normal suite from the repository root:

```bash
./scripts/test.sh
```

The complete suite remains the local pre-push and pull-request gate. GitHub
Actions uses `./scripts/test_fast.sh` for feature-branch pushes and the complete
suite for pull requests to `main`; the event policy, fail-safe `main` behavior,
caching, concurrency, and timeout are documented in
[`docs/ci-verification.md`](docs/ci-verification.md).

This runs pytest, synthesizable RTL lint, the Phase 5A APU foundation, Phase 5B
Pulse 1, Phase 5C dual-pulse, Phase 5D three-channel Triangle, Phase 5E
four-channel Noise, Phase 5F DMC oracle/RTL and DMA/system comparisons, and the
Phase 5G complete-APU full-state comparison and interaction closure,
and the self-checking platform, Phase
4A exhaustive system-bus/RAM test, Phase 4B Mapper 0 and cartridge-boot tests,
Phase 4C exhaustive controller and integrated cartridge-poll tests, Phase
4D-A standalone/arbiter/integrated DMA and NMI tests, Phase 4D-B playable-ROM
boot/controller/frame/VGA and 300-frame sustained tests, the Phase 4E-A
snapshot/CDC/reset test, the Phase 4E-B glyph/renderer/compositor/full-frame
comparison, the Phase 4E-C panel/compositor full-frame and real playable-ROM
combined-frame comparisons, the Phase 4E-D page-selector and five-page
pixel-perfect comparisons, Phase 4E-E command CDC, deterministic instruction/DMA/NMI
steps, frame completion overruns, paused framebuffer/health checks, mixed playable
debugger long run, playable integration checks, the Phase 4F-A runtime-loader
protocol/model/backpressure test, and the Phase 4F-B runtime storage/Mapper-0
model and integration test, plus the Phase 4F-C manifest/coverage model and
end-to-end image-validation/readback test, the Phase 4F-D atomic activation,
runtime reset-vector boot, replacement, DMA/NMI, and CHR integration test, and
the Phase 4F-F asynchronous MMIO/CDC/backpressure/reset/full-transfer test,
and the Phase 4F-G parser-to-MMIO/CDC-to-NES runtime boot, frame, replacement,
and failure test, PPU
timing/register/memory/scroll/background/OAM/sprite/mixer, CPU, ALU,
address-generator, Phase 2D through Phase 2J instruction simulations, and the
Phase 2K board-program simulation, Phase 3J integrated system/NMI sampling,
and Phase 3K timing, framebuffer, CDC, full-frame, and integrated NES/VGA
programs.
The Python stage also exercises the Phase 4F-E/F/G/H iNES parser, runtime-image and
manifest mapping, lazy load plan, mock transport, backpressure/timeouts,
failure behavior, production MMIO transport semantics, endpoint compatibility,
typed FPGA errors, register-model co-verification, `/dev/mem` mapping behavior,
inspect/dry-run CLI, malformed-before-MMIO rejection, transport-failure
activation suppression, and safe deterministic removable-media game-library
discovery, classification, selection, and loading.
Waveforms are written under `build/sim`, including `platform_foundation.fst`,
`ppu_timing.fst`, `ppu_phase3b.fst`, `ppu_memory.fst`, `ppu_phase3c.fst`,
`ppu_scroll.fst`, `ppu_phase3d.fst`, `ppu_background.fst`, `ppu_phase3e.fst`,
`ppu_oam.fst`, `ppu_phase3f.fst`,
`ppu_sprite_renderer.fst`, `ppu_phase3g.fst`, `ppu_phase3h.fst`,
`ppu_phase3i.fst`, `nes_phase4a_bus.fst`, `mapper0_phase4b.fst`,
`nes_phase4b_boot.fst`, `nes_controller_phase4c.fst`,
`nes_phase4c_controller.fst`, `nes_oam_dma_phase4d.fst`,
`nes_internal_bus_arbiter_phase4d.fst`,
`nes_phase4d_dma_integration.fst`, `nes_phase4d_dma_nmi.fst`,
`nes_phase4db_playable.fst`, `nes_debug_snapshot.fst`,
`nes_debug_renderer.fst`, `nes_developer_side_panel.fst`,
`nes_debug_pages.fst`, `nes_runtime_loader_phase4fa.fst`,
`nes_runtime_cartridge_phase4fb.fst`,
`nes_runtime_image_phase4fc.fst`,
`nes_runtime_activation_phase4fd.fst`,
`nes_runtime_loader_mmio_phase4ff.fst`,
`nes_runtime_boot_phase4fg.fst`,
`nes_apu_phase5a.fst`, `nes_apu_pulse1_phase5b.fst`,
`nes_apu_pulse2_phase5c.fst`, `nes_apu_triangle_phase5d.fst`,
`nes_apu_noise_phase5e.fst`, `nes_apu_dmc_phase5f.fst`,
`nes_apu_complete_phase5g.fst`, `nes_dmc_dma_phase5f.fst`,
`nes_dmc_system_phase5f.fst`,
`nes_phase3j.fst`, `vga_phase3k.fst`,
`cpu_phase2a.fst`, `cpu_alu.fst`,
`cpu_address_gen.fst`, `cpu_phase2d.fst`,
`cpu_phase2e.fst`, `cpu_phase2f.fst`, `cpu_phase2g.fst`, and
`cpu_phase2h.fst`, `cpu_phase2i.fst`, `cpu_phase2j.fst`, and
`cpu_board_diag.fst`.

Individual checks are also available:

```bash
python -m pytest -v
./scripts/lint.sh
./scripts/sim.sh
```

## Quartus and hardware

Run standalone CPU analysis and synthesis without changing the board top:

```bash
./scripts/build_cpu_quartus.sh
```

Run standalone Phase 4F-A runtime-loader analysis and synthesis without
changing the board top or cartridge storage:

```bash
./scripts/build_runtime_loader_quartus.sh
```

Run the standalone Phase 4F-D runtime-cartridge validation/activation fit,
M10K-inference, and timing proof:

```bash
./scripts/build_runtime_cartridge_quartus.sh
```

Run the standalone Phase 3A PPU timing-core synthesis and timing proof:

```bash
./scripts/build_ppu_quartus.sh
```

Run the standalone integrated Phase 3B PPU synthesis and timing proof:

```bash
./scripts/build_ppu_phase3b_quartus.sh
```

Run the standalone integrated Phase 3C PPU-memory synthesis and timing proof:

```bash
./scripts/build_ppu_phase3c_quartus.sh
```

Run the standalone integrated Phase 3D PPU-scroll synthesis and timing proof:

```bash
./scripts/build_ppu_phase3d_quartus.sh
```

Run the standalone integrated Phase 3E PPU-background synthesis and timing proof:

```bash
./scripts/build_ppu_phase3e_quartus.sh
```

Run the standalone integrated Phase 3F PPU sprite-evaluation synthesis and
timing proof:

```bash
./scripts/build_ppu_phase3f_quartus.sh
```

Run the standalone integrated Phase 3G PPU sprite-renderer synthesis and
timing proof:

```bash
./scripts/build_ppu_phase3g_quartus.sh
```

Run the standalone integrated Phase 3H PPU pixel-mixer synthesis and timing
proof:

```bash
./scripts/build_ppu_phase3h_quartus.sh
```

Run the standalone integrated Phase 3I PPU NMI/VBlank synthesis and timing
proof:

```bash
./scripts/build_ppu_phase3i_quartus.sh
```

Run the combined Phase 3J CPU+PPU NES-core synthesis and timing proof:

```bash
./scripts/build_nes_phase3j_quartus.sh
```

Build the Phase 4F-F HPS-bridge/debugger/playable-ROM DE1-SoC NES/VGA image.
The script regenerates and validates the Platform Designer address map, then
runs strict ROM import, synthesis, fitter, assembler, fully constrained timing,
SOF, and RBF checks:

```bash
./scripts/build_de1_soc_nes_vga_quartus.sh
```

Build the SOF and RBF locally:

```bash
./scripts/build_quartus.sh
```

Build the separate CPU-integrated Phase 2K image:

```bash
./scripts/build_cpu_board_diag_quartus.sh
```

Generated artifacts remain under ignored build paths. Deployment is explicit
and never runs in CI:

```bash
./scripts/deploy.sh
./scripts/deploy_cpu_board_diag.sh
```

Deployment first reruns the complete software verification suite, then builds,
copies the RBF over SSH/Tailscale, and invokes openFPGALoader on JTAG chain
index 1. Review the environment-variable defaults in `scripts/deploy.sh`
before use.

## Project structure

- `rtl/platform` — clock, reset, and NES timing-enable foundation
- `rtl/diagnostic` — removable hardware diagnostic
- `rtl/cpu` — CPU state, ALU, addressing, decoder, and shared instruction sequencer
- `rtl/ppu` — PPU timing, CPU registers, memory map, and integrated cores
- `rtl/system` — NES CPU address decoder, system bus, and internal CPU RAM
- `rtl/cartridge` — build-time and runtime Mapper 0/NROM cartridge storage
- `rtl/controller` — NES serial protocol and physical-input synchronizer
- `rtl/dma` — coordinated standalone OAM and DMC DMA timing engines
- `rtl/apu` — APU frame/status logic plus Pulse 1, Pulse 2, Triangle, Noise,
  and DMC channels
- `rtl/debug` — observation-only snapshot/CDC, font, and Developer Mode renderer
- `rtl/loader` — runtime-loader protocol, manifest, and transfer validation
- `rtl/video` — framebuffer, VGA timing/scaling, and palette conversion
- `rtl/memory` — reserved for later phases
- `sim` — self-checking SystemVerilog testbenches
- `verification` and `tests/python` — Python reference infrastructure/tests
- `constraints` — SDC timing constraints
- `quartus` — hand-maintained Quartus project files
- `scripts` — verification, build, and explicit deployment entry points
- `docs` — architecture and engineering documentation
