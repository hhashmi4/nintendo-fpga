# Phase 1 platform foundation

## Scope

Phase 1 supplies deterministic clock, reset, timing-enable, verification,
build, and hardware-diagnostic infrastructure. It deliberately contains no NES
CPU, PPU, APU, cartridge mapper, controller, game, video, or audio behavior.

## Architecture

`de1_soc_top` is the board boundary. It maps the DE1-SoC oscillator, reset
button, and three diagnostic LEDs to reusable platform logic.

`platform_core` composes two independent services:

1. `platform_clock` owns the system-clock interface. In Phase 1 it passes the
   50 MHz reference clock through unchanged and reports locked. A later PLL can
   replace this module without changing users of `platform_core`.
2. `reset_sync` and `nes_timing_gen` produce the synchronized reset and the
   `nes_master_ce`, `ppu_ce`, `cpu_ce`, and `apu_ce` integration interface.

Future NES system logic will consume `sys_clk`, `reset`, and these enables. It
must not be added to the board wrapper or diagnostic block.

`platform_diagnostic` is removable and sits beside that future system boundary.
It advances two counters from the PPU and CPU enables solely to make Phase 1
operation visible on the board.

## Reset strategy

DE1-SoC `KEY0` is active-low and drives the external reset request.

- Assertion into `reset_sync` is asynchronous, so reset does not depend on a
  running clock.
- Deassertion shifts through two flip-flops and therefore occurs only on a
  `CLOCK_50` rising edge.
- All downstream platform state uses the synchronized active-high reset
  synchronously.
- Synchronizer, timing accumulator, phases, and diagnostic counters have an
  explicit zero power-up value. Cyclone V configuration initializes these
  registers; the external button remains available for repeatable reentry.

The testbench checks initial state, held reset, two-edge release, asynchronous
reassertion, synchronous consumer clearing, and repeatable timing phase.

## Clock and timing strategy

The only Phase 1 fabric clock is the 50 MHz board oscillator. No divided or
gated fabric clocks are created, and there are no generated clocks to constrain.
Every future subsystem is expected to use `sys_clk` plus its clock enable.

The provisional NTSC engineering target is centralized in
`rtl/platform/platform_config_pkg.sv`:

- nominal master timing: `945,000,000 / 44 Hz`
- nominal PPU timing: master / 4
- nominal CPU and APU timing: master / 12
- exact logical relationship: three PPU enables per CPU/APU enable

Relative to 50 MHz, the nominal master-timing average is the reduced rational
ratio `189 / 440`. `nes_timing_gen` implements this with an accumulator, then
derives PPU enables from every fourth master enable and CPU/APU enables from
every twelfth. One 1760-cycle window therefore contains exactly 756 master,
189 PPU, and 63 CPU/APU enables.

This is an average-rate implementation. Enable pulses are separated by integer
50 MHz periods and therefore have bounded edge-placement jitter relative to an
original-console oscillator. It is not described as an exact NES master clock.
A future accuracy review must decide whether to retain this all-synchronous
approach or place a verified Cyclone V PLL behind `platform_clock`.

Before claiming console-accurate timing, authoritative evidence is still
required for:

- the oscillator frequency and tolerance for the exact NTSC console revision
  being targeted;
- CPU, PPU, and APU edge/phasing behavior, not only their average ratios;
- odd-frame and video/color timing consequences;
- whether a selected PLL/output configuration meets the required frequency,
  phase, and jitter tolerances.

## Timing constraints

`constraints/nintendo_fpga.sdc` defines `CLOCK_50` as a 20.000 ns primary clock
and derives clock uncertainty. The asynchronous `KEY0` input is false-pathed;
reset removal is synchronized by RTL. The three human-visible LED outputs are
explicitly false-pathed because they have no external synchronous receiver or
interface timing requirement. There are no derived clocks in Phase 1.

Timing Analyzer must report a constrained 50 MHz clock and non-negative setup,
hold, and minimum-pulse-width slack before a build is accepted. Recovery and
removal do not apply to downstream state because it uses synchronous reset;
the asynchronous external request is handled only by the identified reset
synchronizer. Warnings are reviewed rather than suppressed.

## Pin and device provenance

The Quartus target `5CSEMA5F31C6` and `LEDR0 = PIN_V16` were confirmed against
the earlier working local project at
`../board-tests/de1-soc/switch-led/switch_led.qsf`.

The clock, button, and diagnostic pins were cross-checked against the public
[DE1-SoC default project](https://github.com/thomasrussellmurphy/quartus-DE1_SOC-project/blob/master/DE1_SOC_TOP/DE1_SOC_TOP.qsf),
which identifies itself as a default project for Terasic's board:

- `CLOCK_50 = PIN_AF14`
- `KEY0 / KEY[0] = PIN_AA14`
- `LEDR0 = PIN_V16`
- `LEDR1 = PIN_W16`
- `LEDR2 = PIN_V17`

The repository did not initially contain the official Terasic manual or master
pin-assignment file. Physical validation on this exact board remains required.

## Verification

Create and activate the isolated Python environment before running the suite:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements-dev.txt
```

The normal verification command is:

```bash
./scripts/test.sh
```

`scripts/test.sh` is the single normal entry point and stops on the first
failure. It runs:

1. pytest timing/configuration checks;
2. Verilator lint of the synthesizable board design;
3. Verilator compilation and execution of the self-checking testbench.

The SystemVerilog testbench checks reset behavior, known state, enable pulse
counts, CPU/PPU/APU relationships, single-cycle behavior, and deterministic
restart. `scripts/sim.sh` removes any previous waveform before simulation and
requires a newly generated, non-empty `build/sim/platform_foundation.fst`, so a
stale trace cannot satisfy the waveform gate.

The Python layer mirrors timing calculations, checks the RTL constants, and
provides the initial location for future reference models. It does not replace
RTL simulation.

GitHub Actions installs the pinned pytest dependency and Verilator, then invokes
the same `scripts/test.sh` developers run locally. Quartus is intentionally not
installed in GitHub-hosted CI.

Phase 1 verification gates are:

1. all pytest reference/configuration tests pass, including the 1760-cycle
   756/189/63 enable-count case;
2. synthesizable RTL passes Verilator lint;
3. the self-checking RTL simulation and every assertion pass, and a fresh FST
   waveform is produced;
4. Quartus analysis, synthesis, fitter, assembler, and Timing Analyzer pass for
   `5CSEMA5F31C6`;
5. setup, hold, and minimum-pulse-width slack are non-negative, required timing
   paths are constrained, and SOF/RBF artifacts are generated;
6. GitHub Actions passes on the exact committed revision; and
7. the generated Phase 1 image programs successfully and the KEY0/LEDR0-2
   diagnostic behavior is physically observed.

A local or CI result is not treated as a substitute for a later gate. In
particular, Phase 1 is not physically verified until the final diagnostic has
been observed on the DE1-SoC.

## Quartus build

Run:

```bash
./scripts/build_quartus.sh
```

The script fails on Quartus or conversion errors. Expected artifacts are:

- `build/quartus/output_files/nintendo_fpga.sof`
- `build/quartus/nintendo_fpga.rbf`

Quartus databases and all generated bitstreams/reports are ignored by Git.

The Phase 1 compile completed with no errors and two remaining Fitter warnings:

- `292013` is the expected Quartus Prime Lite LogicLock subscription notice;
  this design does not use a LogicLock region.
- `15714` reports unspecified current strength and slew rate on the three LED
  outputs. Quartus applies 16 mA and slew-rate setting 1, matching the defaults
  observed in the earlier working switch/LED proof-of-concept. The warning is
  retained instead of inventing electrical constraints without the official
  board electrical specification; it does not affect clock/reset timing, but
  should be resolved after that source is archived and reviewed.

Timing Analyzer reports the design fully constrained for setup and hold. Across
the four analyzed corners, the worst reported setup slack is +14.713 ns, hold
slack is +0.142 ns, and minimum-pulse-width slack is +9.067 ns. No recovery or
removal paths exist in downstream logic because reset there is synchronous.

## Deployment and hardware diagnostic

Deployment is an explicit developer action:

```bash
./scripts/deploy.sh
```

It gates deployment on the software test suite and Quartus build, transfers the
RBF to the Mac over SSH/Tailscale, and runs the already proven programming
route: USB-Blaster II firmware, openFPGALoader, and Cyclone V JTAG chain index
1. It is never invoked by GitHub Actions.

After programming:

- `LEDR0` toggles from a counter enabled by `ppu_ce`;
- `LEDR1` illuminates while synchronized reset is active;
- `LEDR2` toggles from a counter enabled by `cpu_ce`.

Press and hold `KEY0`: `LEDR1` should illuminate and both heartbeat counters
reset. Release it: `LEDR1` should turn off after synchronization and the two
heartbeat patterns should restart deterministically. This proves configuration,
the board clock, reset path, enable infrastructure, and sequential logic. It
does not test any NES subsystem.
