# Nintendo FPGA

FPGA-based Nintendo Entertainment System project targeting the Terasic
DE1-SoC and its Intel Cyclone V SoC FPGA. The repository implements the Phase 1
platform foundation, the Phase 2A CPU architectural shell, and the Phase 2B
reusable ALU, the Phase 2C address generator, and the Phase 2D load/store/
transfer execution subset. No complete CPU instruction set, PPU, APU, mapper,
controller, or game-execution logic exists yet.

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
- Deterministic reset values and CPU-enable-only sequential progression
- Read-only placeholder fetch bus cycle with no opcode execution
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
ALU, address-generator, and Phase 2D instruction simulations. Waveforms are written under
`build/sim`, including `platform_foundation.fst`, `cpu_phase2a.fst`,
`cpu_alu.fst`, `cpu_address_gen.fst`, and `cpu_phase2d.fst`.

Individual checks are also available:

```bash
python -m pytest -v
./scripts/lint.sh
./scripts/sim.sh
```

## Quartus and hardware

Build the SOF and RBF locally:

```bash
./scripts/build_quartus.sh
```

Generated artifacts remain under ignored build paths. Deployment is explicit
and never runs in CI:

```bash
./scripts/deploy.sh
```

Deployment first reruns the complete software verification suite, then builds,
copies the RBF over SSH/Tailscale, and invokes openFPGALoader on JTAG chain
index 1. Review the environment-variable defaults in `scripts/deploy.sh`
before use.

## Project structure

- `rtl/platform` — clock, reset, and NES timing-enable foundation
- `rtl/diagnostic` — removable hardware diagnostic
- `rtl/cpu` — CPU state, ALU, addressing, decoder, and Phase 2D sequencer
- `rtl/ppu`, `rtl/apu` — reserved for later phases
- `rtl/memory`, `rtl/cartridge`, `rtl/controller`, `rtl/video` — reserved
- `sim` — self-checking SystemVerilog testbenches
- `verification` and `tests/python` — Python reference infrastructure/tests
- `constraints` — SDC timing constraints
- `quartus` — hand-maintained Quartus project files
- `scripts` — verification, build, and explicit deployment entry points
- `docs` — architecture and engineering documentation
