# Nintendo FPGA

FPGA-based Nintendo Entertainment System project targeting the Terasic
DE1-SoC and its Intel Cyclone V SoC FPGA. The repository currently implements
only the Phase 1 platform foundation; no NES CPU, PPU, APU, mapper, controller,
or game-execution logic exists yet.

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

This runs pytest, synthesizable RTL lint, and the self-checking platform
simulation. The waveform is written to
`build/sim/platform_foundation.fst`.

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
- `rtl/cpu`, `rtl/ppu`, `rtl/apu` — reserved for later phases
- `rtl/memory`, `rtl/cartridge`, `rtl/controller`, `rtl/video` — reserved
- `sim` — self-checking SystemVerilog testbenches
- `verification` and `tests/python` — Python reference infrastructure/tests
- `constraints` — SDC timing constraints
- `quartus` — hand-maintained Quartus project files
- `scripts` — verification, build, and explicit deployment entry points
- `docs` — architecture and engineering documentation
