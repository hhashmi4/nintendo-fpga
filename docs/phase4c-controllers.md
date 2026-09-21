# Phase 4C NES controller subsystem

## Scope and verified baseline

Phase 4C implements two standard NES serial controller ports behind the
direction-sensitive `$4016/$4017` interface created in Phase 4A. The CPU, PPU,
OAM DMA, Mapper 0 cartridge, scheduler, framebuffer, and VGA data paths are
unchanged. The controller protocol is a separate peripheral; physical board
wiring remains outside `nes_core`.

The starting commit was `5771ea0ad4eab53161ddd21a43eeb76d09233453` on
`phase4/cartridge-nrom`. It matched `origin/phase4/cartridge-nrom`, and the
working tree was clean. Before any Phase 4C change:

- all 646 Python tests passed;
- all retained CPU, PPU, DMA/NMI, Phase 3J integration, Phase 3K VGA, Phase
  4A bus, and Phase 4B cartridge/boot RTL simulations passed;
- all Verilator lint targets passed;
- Quartus completed synthesis, fitter, assembler, timing analysis, and RBF
  conversion with zero errors;
- the Phase 4B image used 2,874 ALMs, 3,282 logic ALUTs, 590 memory ALUTs,
  1,204 registers, 230 M10Ks, 1,871,872 block-memory bits, zero DSPs, and one
  PLL;
- worst cross-corner setup and hold slack were +0.836 ns and +0.151 ns,
  respectively, with zero TNS and fully constrained setup/hold paths.

This phase does not add APU/audio, different cartridge mappers, physical NES
controller connectors, USB/Bluetooth host logic, save states, or the graphical
developer-mode renderer.

## Protocol and button representation

Each abstract controller is one eight-bit active-high vector. A one means the
button is pressed:

| Vector bit / serial read | Button |
|---:|---|
| 0 / first | A |
| 1 / second | B |
| 2 / third | Select |
| 3 / fourth | Start |
| 4 / fifth | Up |
| 5 / sixth | Down |
| 6 / seventh | Left |
| 7 / eighth | Right |

The ordering deliberately makes the shift register's least-significant bit
the next serial response. It also means the byte reconstructed by the owned
test cartridge has the same bit layout as the live input vector.

`nes_controller` receives accepted transactions from the existing system
bus. Its two logical addresses have these direction-dependent meanings:

| CPU transaction | Phase 4C behavior |
|---|---|
| write `$4016` | set shared strobe from D0 |
| read `$4016` | return Controller 1 serial bit on D0 |
| read `$4017` | return Controller 2 serial bit on D0 |
| write `$4017` | remains on the APU interface for its future frame counter |

For controller reads, D7:D1 are deterministic zero. A physical NES exposes
open-bus-dependent upper bits; this system intentionally does not emulate that
analog/open-bus detail yet. The architectural controller value is therefore
always `0000000S`, where `S` is the selected serial bit.

## Strobe, latch, and shift behavior

The shared strobe follows bit zero of CPU writes to `$4016`:

```text
strobe=1: $4016/$4017 reads follow each controller's live A button
     1 -> 0 write transition: capture both eight-button vectors together
strobe=0: each port shifts only when that port is read
```

The high-to-low transition copies both live states into independent shift
registers and resets both read indices to zero. A `$4016` read presents
Controller 1 bit zero and then shifts only Controller 1. A `$4017` read does
the same for Controller 2. Reading one port cannot consume a bit from the
other port.

Each low-strobe shift inserts a one at bit seven. After eight reads, the shift
register is all ones, so every later read returns D0=1. The four-bit read index
saturates at eight and never wraps. Raising and lowering strobe again captures
a fresh snapshot and restarts both indices.

Reset clears strobe, both shift registers, and both indices. Read data and all
event diagnostics are zero while reset is asserted, and no transaction can
change controller state during reset.

## Integration and data flow

The controller is behind, rather than inside, the stable NES core:

```text
DE1-SoC SW2-SW9
       |
       v
two-flop controller_input_sync (50 MHz)
       |
       v
abstract Controller 1 [A..Right] ----+
abstract Controller 2 = inactive ----+--> nes_controller
                                           ^       |
                                           |       v
                       Phase 4A $4016/$4017 port   CPU read data
                                           ^       |
                                           +-- nes_core/system bus
```

`nes_core` still exports only a port selector, read strobe, `$4016` write
strobe/data, and one read byte. A future original-port sampler, USB host,
Bluetooth adapter, or production-PCB input module can supply the same two
eight-bit vectors without changing the CPU, PPU, bus, DMA, or cartridge.

Everything uses the existing 50 MHz fabric clock. CPU/controller transactions
occur only on accepted CPU clock-enable slots. The input synchronizer uses
ordinary fabric edges. No controller clock or asynchronous generated clock is
created.

## DE1-SoC development mapping

SW0 remains the VGA test-pattern selector and SW1 remains framebuffer capture
freeze. The eight remaining slide switches provide Controller 1:

| NES button | Board input | Cyclone V pin | Controller bit |
|---|---|---|---:|
| A | SW2 | `PIN_AF9` | 0 |
| B | SW3 | `PIN_AF10` | 1 |
| Select | SW4 | `PIN_AD11` | 2 |
| Start | SW5 | `PIN_AD12` | 3 |
| Up | SW6 | `PIN_AE11` | 4 |
| Down | SW7 | `PIN_AC9` | 5 |
| Left | SW8 | `PIN_AD10` | 6 |
| Right | SW9 | `PIN_AE12` | 7 |

An up/on slide switch is a pressed button. Controller 2 is tied to the
deterministic inactive vector `8'h00`; it remains fully implemented and is
covered independently in simulation. HEX1:HEX0 displays the synchronized
Controller 1 byte in hexadecimal for immediate board-level wiring checks.

### Synchronization and debouncing

`controller_input_sync` applies a two-flop synchronizer to all eight
asynchronous slide-switch inputs. Quartus is given explicit synchronizer
identification, and the SDC marks only the paths from physical pins to the
synchronizer as asynchronous.

No debounce counter is needed for this temporary mapping. Slide switches are
used as stable levels, and a controller snapshot occurs only on a software
latch edge; physical movement cannot itself create bus reads or serial shifts.
For deterministic manual testing, set a switch and allow more than two 50 MHz
cycles before the next poll. A future mechanical pushbutton or original-port
frontend may debounce or digitally filter its state before this abstract
vector boundary without changing NES serial semantics.

## Owned cartridge programs

The fixture generator now produces two additional legal NROM-128 images:

- `phase4c_controller_nrom128` writes strobe high then low, reads eight bits
  from `$4016`, reads eight bits from `$4017`, stores the reconstructed bytes
  in CPU RAM `$0010/$0011`, increments poll counter `$0012`, and repeats;
- `phase4c_controller_display_nrom128` performs the same polling while also
  running the Phase 4B checkerboard. It writes black to background palette
  entry 1 when no Controller 1 button is pressed and blue when any is pressed.

Both programs execute real 2A03 instructions from cartridge PRG ROM. Tests do
not force CPU state or write expected RAM values from the testbench.

The display fixture is used by the Quartus board image. Together, HEX1:HEX0
and the color change distinguish physical input/synchronizer mapping from the
end-to-end serial polling path.

## Passive debug observations

The controller module exposes these read-only signals for a future Developer
Mode renderer:

- live Controller 1 and Controller 2 vectors;
- both latched shift registers;
- both saturating serial indices;
- current serial output for each port;
- shared strobe state;
- `$4016` read, `$4017` read, and falling-edge latch events.

These are direct observations or combinational event qualifications. None feed
back into protocol state, bus arbitration, or CPU behavior.

## Verification

`verification/controller.py` independently models the shared strobe and two
shift registers. Python tests exhaust all 256 states separately on each port,
check the exact A/B/Select/Start/Up/Down/Left/Right sequence, post-eight ones,
high-strobe live-A behavior, repeated latching, changes between polls,
interleaved independent reads, reset, and invalid-port rejection.

`nes_controller_phase4c_tb` exercises the RTL across the same 512 exhaustive
per-port states, individual and simultaneous button combinations, interleaved
reads, repeated polls, reset, post-eight reads, debug events, and the two-flop
input pipeline. It records `build/sim/nes_controller_phase4c.fst`.

`nes_phase4c_controller_tb` boots the owned polling cartridge through Mapper
0, changes both external input vectors, and proves the following path twice:

```text
live input -> simultaneous latch -> independent serial reads
 -> Phase 4A bus -> CPU instructions -> CPU RAM $0010/$0011
```

The integrated waveform is
`build/sim/nes_phase4c_controller.fst`. Run complete qualification with:

```bash
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
scripts/build_de1_soc_nes_vga_quartus.sh
```

## Final qualification results

The final Phase 4C regression passed without a retained-test regression:

- 1,163 Python tests passed, including 517 controller-model tests and all 256
  possible button vectors independently on both ports;
- the standalone controller RTL passed 7,251 checks across 512 exhaustive
  per-port states;
- the integrated CPU/cartridge/controller test completed three real polls,
  observed 24 reads from each controller port and three shared latch events,
  and stored the second input pair as `$3c/$c3` in CPU RAM;
- every retained CPU, PPU, DMA/NMI, system/VGA, Phase 4A, and Phase 4B RTL
  regression passed; and
- every Verilator lint target passed with no emitted diagnostics.

Quartus Prime Lite 23.1std.1 completed synthesis, fitter, assembler, timing
analysis, SOF generation, and RBF conversion with zero errors. The fitted
Phase 4C image uses 2,888 ALMs, 3,308 logic ALUTs plus 590 memory ALUTs,
1,248 registers, 230 M10Ks, 1,871,872 block-memory bits, zero DSPs, and one
PLL. Relative to the recorded Phase 4B baseline, that is +14 ALMs, +26 logic
ALUTs, +44 registers, and no memory, DSP, or PLL increase.

The design is fully constrained for setup and hold, with zero TNS and no
unconstrained paths. Across all reported operating corners, the worst setup
slack is +0.374 ns and the worst hold slack is +0.139 ns. Quartus found 19
synchronizer chains, including the eight new two-register controller input
chains.

The full compilation reported the same 17 understood warnings as the Phase
4B baseline: ten during mapping, five during fitting, and two during timing.
They cover read-only inferred-ROM write-side defaults, one unused diagnostic
aggregate, a connectivity report, constant-low `VGA_SYNC_N`, incomplete
assignments on deliberately unused board pins, the Lite-edition LogicLock
notice, automatic PLL compensation, and two stale IRQ synchronizer filters
whose registers optimize away. No new critical warning was introduced.

The generated artifacts are:

- SOF: 6,690,502 bytes, SHA-256
  `1f7b9f7e2b754f635380c5571bcf8791981509d5ddb8f9237070cb5486e79fb4`;
- RBF: 7,007,204 bytes, SHA-256
  `116992205e19525a6906130e2adf8c11075f7cc39a2576ce68867e97f8b4f543`.

These results are build and simulation evidence only; physical board
validation was not performed.

## Physical validation procedure

The build produces
`build/quartus_de1_soc_nes_vga/output_files/de1_soc_nes_vga.sof` and
`build/quartus_de1_soc_nes_vga/de1_soc_nes_vga.rbf`.

1. Set SW0=0, SW1=0, and SW2-SW9=0; connect the DE1-SoC native VGA output.
2. Program the SOF or RBF with the existing USB-Blaster/openFPGALoader flow.
3. Release KEY0. Confirm the centered 2x checkerboard and stable VGA sync.
4. Confirm HEX1:HEX0 reads `00` and the checkerboard uses the no-button color.
5. Raise each of SW2 through SW9 individually. Confirm HEX1:HEX0 shows `01`,
   `02`, `04`, `08`, `10`, `20`, `40`, and `80`, respectively.
6. For every raised controller switch, confirm the checkerboard changes to
   the pressed-button color. That visual change is written only by the CPU
   after a real `$4016` serial poll.
7. Try multiple switches and confirm the HEX byte is their bitwise sum. Return
   all eight to zero and confirm both HEX and VGA color return to idle.
8. Set SW0=1 and confirm the framebuffer-independent VGA test bars still work;
   exercise SW1 to confirm capture freeze remains intact.

This procedure describes the intended board test. Producing an image is not a
claim that a board was programmed or physically observed.

## Phase 4D recommendation

Extract the already verified 513/514-cycle OAM DMA sequencer from `nes_core`
into a standalone internal bus-master module behind the existing `$4014`
trigger. Preserve exact CPU-stall parity, 256 source reads, 256 `$2004` writes,
RAM mirroring, cartridge-source reads, NMI behavior, and all current passive
diagnostics. Add explicit arbitration tests for DMA source pages that decode to
PPU/APU/controller/unmapped I/O, and define deterministic open-bus policy there.
Do not change the CPU address decoder or the newly completed controller port.
