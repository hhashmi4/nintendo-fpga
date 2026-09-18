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
are implemented. No PPU,
APU, NES memory map, DMA, mapper, controller, or game-execution system exists
yet.

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

This runs pytest, synthesizable RTL lint, and the self-checking platform, CPU,
ALU, address-generator, Phase 2D through Phase 2J instruction simulations, and
the Phase 2K board-program simulation.
Waveforms are written under `build/sim`, including `platform_foundation.fst`,
`cpu_phase2a.fst`, `cpu_alu.fst`, `cpu_address_gen.fst`, `cpu_phase2d.fst`,
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
- `rtl/ppu`, `rtl/apu` — reserved for later phases
- `rtl/memory`, `rtl/cartridge`, `rtl/controller`, `rtl/video` — reserved
- `sim` — self-checking SystemVerilog testbenches
- `verification` and `tests/python` — Python reference infrastructure/tests
- `constraints` — SDC timing constraints
- `quartus` — hand-maintained Quartus project files
- `scripts` — verification, build, and explicit deployment entry points
- `docs` — architecture and engineering documentation
