# Phase 2K — physical DE1-SoC CPU hardware validation

## Purpose and current result

Phase 2K places the verified Ricoh 2A03 CPU into a dedicated DE1-SoC hardware
diagnostic. It is a CPU-only silicon smoke test, not an NES memory map or
Phase 3 implementation. The stable Phase 1 `de1_soc_top` and
`platform_diagnostic` remain unchanged.

The exact image documented here was synthesized, fitted, timing-checked, and
loaded into volatile Cyclone V SRAM on 2026-09-18. The USB-Blaster II and FPGA
were detected and programming reached 100% with `Done`. There is no camera or
JTAG-visible status register available to the development host, so the LED and
HEX result has not been independently observed.

**Current status: PROGRAMMING PASS — PHYSICAL FUNCTIONAL CONFIRMATION REQUIRED.**

Phase 2K must not be called hardware verified until the board visibly shows
the PASS state described below.

## Architecture

```text
                         SW0 (synchronized)
                                |
CLOCK_50 --> platform_clock --> run/debug enable select
    |                           ^          |
    +--> reset_sync <--- KEY0   |          v
    |                     nes_timing_gen  stall inhibit
    |                                      |
    |                                      v
    +----------------------------------> cpu_core
                                           |
                                  16-bit CPU bus
                                           |
                    +----------------------+-------------------+
                    |                                          |
           cpu_board_diag_memory                     diagnostic controls
       zero page + stack + test cells             IRQ / NMI / stall / result
               program ROM + vectors
```

`CLOCK_50` is the only fabric clock. `platform_clock` passes it through
unchanged. All CPU progress occurs through `cpu_enable`; no divided, gated, or
generated CPU clock exists. A transaction commits only on
`cpu_enable && bus_valid`. This condition controls RAM writes and every
diagnostic control write.

KEY0 uses the existing asynchronous-assertion, synchronized-release reset
architecture. SW0 passes through a two-flop level synchronizer. SW0=0 selects
the existing nominal NES CPU enable from `nes_timing_gen`; SW0=1 selects a
20 Hz debug enable. Switching mode changes only an enable pulse source.

The forced stall starts after the program writes `$5A` to `$6003`. The harness
suppresses `cpu_enable` for 256 `CLOCK_50` cycles. It snapshots architectural
state and bus outputs on the first held cycle and compares them on every
subsequent held cycle. A mismatch prevents PASS. Simulation uses the same
mechanism with a shortened 24-clock parameter and observes six normally
scheduled run enables being suppressed.

## Diagnostic memory

The memory is deliberately small and is not an NES bus map:

| Address | Function |
| --- | --- |
| `$0000-$00FF` | zero-page diagnostic RAM |
| `$0100-$01FF` | stack RAM; all pushes and pulls are CPU bus transactions |
| `$0400` | absolute-address test cell |
| `$0500` | absolute-indexed page-cross test cell |
| `$6000` | result write: `$A5` PASS or a failure code |
| `$6001` | write `$5A` to assert IRQ; handler writes `$A5` to clear it |
| `$6002` | write `$5A` to generate a clean four-clock NMI pulse |
| `$6003` | write `$5A` to stall; read `$A5` after a clean completed stall |
| `$8000-$83FF` | generated diagnostic program ROM |
| `$FFFA/$FFFB` | NMI vector to `$83B0` |
| `$FFFC/$FFFD` | RESET vector to `$8000` |
| `$FFFE/$FFFF` | IRQ/BRK vector to `$83A0` |

The asynchronous read contract matches the CPU bus contract. Quartus therefore
implements this small memory as logic rather than block RAM. RAM is initialized
for FPGA configuration; the program initializes every location whose value
affects a result.

The generated program include is reproducible with:

```bash
python3 scripts/generate_cpu_board_diag_program.py
python3 scripts/generate_cpu_board_diag_program.py --check
```

## Program structure and coverage

The program starts at `$8000`, runs 518 enabled CPU cycles in board-harness
simulation, writes `$A5` to `$6000`, and reaches an actual stable JMP loop at
`$83F0`. PASS is not latched merely from the signature: the harness also
requires observed BRK, IRQ, and NMI vector fetches, IRQ acknowledgement, a
clean completed stall, and a CPU FETCH boundary at `$83F0` with opcode `$4C`.

The program exercises:

- seven-cycle RESET and `$FFFC/$FFFD` vector fetch;
- immediate LDA/LDX/LDY and TAX/TAY/TXA/TYA/TSX/TXS;
- binary ADC/SBC, including SED followed by binary `$09 + $01 = $0A`;
- AND/ORA/EOR/BIT, CMP/CPX/CPY, and N/V/Z/C/D/I flag controls;
- INX/INY/DEX/DEY, memory INC/DEC, and ASL/LSR/ROL/ROR;
- zero-page, absolute, zero-page-indexed, and page-crossing absolute-indexed
  reads and writes (`$04FF,X` reaches `$0500`);
- taken and not-taken branches;
- PHA/PLA and PHP/PLP through actual page-1 bus accesses;
- JSR/RTS and absolute JMP;
- BRK/RTI through the IRQ/BRK vector;
- a level IRQ whose handler acknowledges hardware and increments `$10`;
- an edge NMI whose handler increments `$11`;
- original-value and modified-value RMW writes; and
- a real multi-cycle `cpu_enable` stall followed by a `$6003` status read.

Simulation asserts both reset-vector reads, at least six stack reads and
writes, the page-cross read/write, exactly five writes to the INC/DEC RMW byte
(initial STA plus two writes per RMW), both interrupt vectors, suppressed
enable opportunities, the PASS bus write, and the stable final PC/opcode.

## PASS and failure codes

| Value | Meaning |
| ---: | --- |
| `$A5` | program PASS request |
| `$01` | loads, transfers, compare, or base memory access |
| `$02` | ADC/SBC or binary-only decimal-disabled arithmetic |
| `$03` | logic, BIT, or status-branch behavior |
| `$04` | increment/decrement, shift/rotate, or RMW |
| `$05` | taken/not-taken branch behavior |
| `$06` | stack data or status round trip |
| `$07` | JSR/RTS or JMP |
| `$08` | BRK/RTI |
| `$09` | deterministic hardware IRQ |
| `$0A` | deterministic hardware NMI |
| `$0B` | absolute-indexed page crossing |
| `$0C` | hardware stall/status |
| `$FC` | PASS requested without all harness prerequisites |
| `$FE` | CPU entered the unsupported-opcode trap state |

Each program failure writes its code and jumps to the common stable failure
loop at `$83D3`. PASS and FAIL remain latched until KEY0 reset.

## Board outputs

Normally the active-low common-anode displays show `PPPP OO`: HEX5..HEX2 are
PC and HEX1..HEX0 are `debug_instruction`. Once PASS is proven, the harness
freezes the actually observed final state:

```text
HEX5 HEX4 HEX3 HEX2 HEX1 HEX0
 8    3    F    0    4    C
```

On failure the display changes to `FPPPCC`, where `PPP` is the low 12 bits of
the live failure-loop PC and `CC` is the latched failure code.

| LED | Meaning | Expected after PASS |
| --- | --- | --- |
| LEDR0 | CPU-enable heartbeat | toggling |
| LEDR1 | PASS latched | 1 |
| LEDR2 | FAIL latched | 0 |
| LEDR3 | half-second write-activity stretch | 0 after settling |
| LEDR4 | IRQ vector observed | 1 |
| LEDR5 | NMI vector observed | 1 |
| LEDR6 | current `bus_valid` | 1 in the JMP loop |
| LEDR7 | clean stall completed | 1 |
| LEDR8 | synchronized debug mode | SW0 state |
| LEDR9 | synchronized reset | 0 after KEY0 release |

With SW0=0 after write activity settles, LEDR9..0 should read `001111001x`,
where `x` is the heartbeat phase.

## Verification and FPGA results

The untouched pre-change baseline passed first:

- 467/467 pytest tests;
- exhaustive ALU (591,876) and address-generator (1,508,186) RTL vectors;
- all Phase 2A and Phase 2D-2J focused simulations;
- Verilator lint;
- standalone CPU synthesis (717 estimated ALMs, 1,097 ALUTs, 191 registers);
- stable Phase 1 board fit and timing (worst setup +14.713 ns, hold +0.142 ns).

The CPU-integrated `cpu_board_diag` result for `5CSEMA5F31C6` is:

| Metric | Result |
| --- | ---: |
| Analysis & Synthesis | PASS, 0 errors |
| Fitter | PASS, 0 errors |
| Assembler | PASS, 0 errors |
| Timing Analyzer | PASS, fully constrained |
| ALMs | 3,244 / 32,070 (10%) |
| combinational ALUTs | 3,620 |
| registers | 4,617 |
| block RAM bits / blocks | 0 / 0 |
| DSP blocks | 0 |
| PLLs / generated clocks | 0 / 0 |
| worst setup slack | +1.454 ns |
| worst hold slack | +0.168 ns |
| setup / hold TNS | 0.000 ns / 0.000 ns |

Exactly one clock, `CLOCK_50` at 20.000 ns, is reported. No inferred latch or
multiple-driver warning exists. The three synthesis warnings are benign
constant-input notices on Quartus's internal representation of the read-only
program array. The two fitter warnings are the existing Lite LogicLock notice
and unspecified output drive/slew defaults. The SOF SHA-256 is
`42c3c67c92fccaf208e79fa5db1175dce81dfcd07fff36f58c4a94d5dc42e25c`;
the programmed RBF SHA-256 is
`411b0117c8970cc68993f4655bb9b230b4dfdc60cf176170d73b7f5b7034591f`.

## Programming record

The read-only probe reported USB-Blaster II firmware 1.39 and this chain:

- index 0: ARM Cortex-A9, IDCODE `0x4ba00477`;
- index 1: Altera Cyclone V SoC `5CSE*A5/5CST*5/5CSX*5`, IDCODE `0x02d120dd`.

The RBF was copied through the established SSH/Tailscale route to the remote
Mac and loaded at chain index 1. openFPGALoader reported `Load SRAM: 100.00%`
and `Done`. No persistent flash was written.

After programming, an observer must confirm LEDR1=1, LEDR2=0, LEDR4=1,
LEDR5=1, LEDR7=1, and HEX=`83F04C`. Until that observation is recorded, the
functional hardware result is awaiting confirmation.

## Commands used

```bash
git status --short --branch
git branch --show-current
git rev-parse HEAD
git remote -v
git log -1 --oneline
git checkout phase2/cpu-final-verification
git pull --ff-only
git switch -c phase2/cpu-board-validation
source .venv/bin/activate
./scripts/test.sh
./scripts/lint.sh
./scripts/sim.sh
./scripts/build_cpu_quartus.sh
./scripts/build_quartus.sh
./scripts/build_cpu_board_diag_quartus.sh
python3 scripts/generate_cpu_board_diag_program.py --check
```

Programmer detection and programming used the commands embodied in
`scripts/deploy_cpu_board_diag.sh`: openFPGALoader `--detect` first, then the
RBF at `--index-chain 1` with the proven USB-Blaster II probe firmware.

## Files changed

- dedicated Phase 2K top, harness, memory, generated ROM, HEX driver, and switch synchronizer;
- independent QPF/QSF/SDC, build script, and deployment script;
- board-diagnostic testbench plus lint/simulation integration and Python static checks;
- this document and the Phase 2K README summary.

No `cpu_core`, `cpu_alu`, `cpu_address_gen`, or `cpu_decoder` behavior changed.
No generated Quartus product or waveform is committed.

## Limitations and next gate

- The program is a representative silicon smoke test, not a replacement for
  the exhaustive Phase 2 simulation suites.
- The diagnostic RAM is intentionally sparse and private to Phase 2K.
- No SignalTap capture was added; latched visible status is the evidence path.
- No PPU, APU, controller, cartridge, mapper, DMA, video, audio, open-bus
  policy, or NES address map exists in this harness.
- Physical LED/HEX observation remains outstanding.

Recommendation: **PHASE 2K NOT YET HARDWARE VERIFIED** until the programmed
board is observed in the documented PASS state.
