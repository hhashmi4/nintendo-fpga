# Phase 2I Ricoh 2A03 CPU audit

Phase 2I audits the existing timed CPU as a Ricoh 2A03 core. It adds no NES
memory map, APU, PPU, DMA, cartridge, controller, or unofficial instruction.
The only RTL behavior corrected by the audit is the NMOS interrupt-poll delay
after PLP. The audit also identifies ten official opcode bytes still outside
the implemented Phase 2A--2H subset; this is an explicit compatibility limit,
not a silently inflated coverage claim.

## References

The decisions and tests use these established sources:

- [NESdev CPU](https://www.nesdev.org/wiki/CPU) and
  [NESdev 2A03](https://www.nesdev.org/wiki/2A03) for the 2A03's 6502-derived
  core and disabled decimal arithmetic;
- [NESdev instruction reference](https://www.nesdev.org/wiki/Instruction_reference)
  for official opcodes, flag effects, addressing modes, and the delayed I-flag
  effect of CLI/SEI;
- [NESdev status flags](https://www.nesdev.org/wiki/Status_flag) and the
  [Visual6502 B-flag analysis](https://www.nesdev.org/wiki/Visual6502wiki/6502_BRK_and_B_bit)
  for nonpersistent B, stack-byte B/U synthesis, PLP/RTI behavior, and reset's
  write-suppressed stack accesses;
- [NESdev interrupts](https://www.nesdev.org/wiki/Interrupts),
  [Visual6502 interrupt timing](https://www.nesdev.org/wiki/Visual6502wiki/6502_Timing_of_Interrupt_Handling),
  and [interrupt hijacking](https://www.nesdev.org/wiki/Visual6502wiki/6502_Interrupt_Hijacking)
  for NMI edge detection, IRQ level sensitivity, priority, polling, I-flag
  latency, and collision edge cases;
- the original [MOS MCS6500 Programming Manual](https://www.bitsavers.org/components/mosTechnology/6500-50A_MCS6500pgmManJan76.pdf)
  and [NESdev cycle tables](https://www.nesdev.org/wiki/6502_cycle_times) for
  architectural semantics and documented instruction timing;
- [NESdev CPU power-up state](https://www.nesdev.org/wiki/CPU_power_up_state)
  for measured NES reset state and the distinction between guaranteed reset
  behavior and power-up observations;
- [NESdev unofficial opcodes](https://www.nesdev.org/wiki/CPU_unofficial_opcodes)
  for compatibility impact; and
- [NESdev emulator tests](https://www.nesdev.org/wiki/Emulator_tests) plus the
  open [nes-test-roms collection](https://github.com/christopherpow/nes-test-roms)
  for the external compatibility-test inventory.

Cycle tables often describe only count and architectural effects, while
Visual6502-derived material exposes internal polling and dummy bus activity.
There was no disagreement affecting decimal arithmetic, reset-vector order,
RMW writes, or indirect-JMP wrapping. Interrupt collision behavior is more
fine-grained than an instruction-boundary RTL model; those cases are classified
under deferred edge cases rather than guessed.

## Generic NMOS 6502, Ricoh 2A03, and this implementation

| Area | Generic NMOS 6502 | Ricoh 2A03 | Current implementation |
| --- | --- | --- | --- |
| ADC/SBC with D=1 | Decimal adjustment is active | Decimal circuitry is disabled; arithmetic stays binary | Binary Phase 2B ALU always used; D never enters its interface |
| D storage | D can be set, cleared, pushed, and pulled | D remains a stored flag even though it cannot select BCD arithmetic | D is persistent and survives PHP/PLP, interrupt frames, and RTI |
| B status bit | No persistent B latch; stack source distinguishes software/hardware entry | Same core behavior | Stored B is forced 0; PHP/BRK synthesize 1, IRQ/NMI synthesize 0 |
| U status bit | Stack representation has bit 5 high | Same core behavior | Stored U is normalized high; every pushed status has U=1 |
| Reset | Seven cycles, three write-suppressed stack accesses, then FFFC/FFFD | NES CPU exhibits the same sequence; programmer-visible SP becomes FD and I is set | Seven reads, no writes, deterministic pre-vector PC 0000, SP FD, I=1 |
| IRQ | Active-low level input, masked by I | Same core semantics, with NES sources wired internally | Synchronized logical-active-high request, level-sensitive, I-masked |
| NMI | Active-low edge-detected input | Same; normally driven by PPU `/NMI` | Synchronized logical-active-high request with rising-edge latch; integration must invert the physical-low convention |
| Indirect JMP at xxFF | High-byte address wraps within the pointer page | Quirk remains present | Phase 2C supplies xx00 and Phase 2H preserves its bus order |
| Memory RMW | Read, original-value write, modified-value write | Both writes are bus-visible | All 24 implemented memory RMW opcode forms perform both writes |
| On-chip system functions | CPU only | Adds APU, controller ports, and DMA around the CPU core | Deliberately absent from this CPU-only phase |

The deterministic A/X/Y zero values and pre-vector PC zero are project reset
policies required to prevent X/Z state. Software must not treat them as extra
hardware guarantees. Vector order, stack reads, visible SP, I, and PC load are
the compatibility-relevant reset behavior.

## Decimal-disabled behavior

`cpu_alu` has no decimal input. ADC computes 8-bit `A + M + C`; SBC computes
`A + ~M + C`, preserving the 6502 carry-means-no-borrow convention. D is stored
only in `cpu_status_t` and is never consulted by ALU selection or execution.

The independent Python model exhausts every A, operand, and carry combination:

- ADC: 256 x 256 x 2 = 131,072 comparisons, each evaluated with D=0 and D=1;
- SBC: 256 x 256 x 2 = 131,072 comparisons, each evaluated with D=0 and D=1.

This is 524,288 model evaluations and 262,144 direct D-invariance comparisons.
The RTL bench adds 32 directed ADC/SBC executions: 16 operand/carry cases, each
run once with D clear and once set. They cover carry, borrow, wrap, zero,
negative, signed overflow, and values that would differ under BCD correction.
Assertions compare result and N/V/Z/C bit-for-bit while checking D preservation.

## Status representation

Persistent status uses `N V 1 0 D I Z C`. B is not a physical persistent flag
and U is represented internally as one for deterministic visibility.

| Operation | Stack/restored representation |
| --- | --- |
| PHP | pushes `N V 1 1 D I Z C` |
| BRK | pushes `N V 1 1 D I Z C` |
| IRQ/NMI | pushes `N V 1 0 D I Z C` |
| PLP/RTI | restore N/V/D/I/Z/C, discard pulled B, force internal U=1 |

Python tests cover all 256 incoming status bytes. RTL tests cover all 64
combinations of N/V/D/I/Z/C through PLP followed by PHP. Existing Phase 2G/H
traces retain dedicated BRK, IRQ, NMI, and RTI assertions.

## Reset audit

The enabled-cycle sequence remains:

1. read deterministic PC 0000 twice;
2. read 0100, 01FF, and 01FE while decrementing SP without writing;
3. read reset-vector low at FFFC;
4. read reset-vector high at FFFD and install PC.

There are seven logical CPU cycles. Final SP is FD, I is set, B is clear, U is
high, and A/X/Y are deterministic zero. Reset has unconditional sequential
priority, suppresses the bus while asserted, and cannot leak a prior write.

## IRQ, NMI, BRK, and RTI audit

The core interface names `nmi` and `irq` as logical asserted requests. Both
pass through two-flop synchronizers on `CLOCK_50`; no derived clock exists.
NMI is captured on the synchronized rising edge and cleared only when accepted,
so a held input produces one entry and a new low-to-high transition rearms it.
IRQ remains a synchronized level and is eligible only when I is clear. At an
instruction boundary the order is reset, pending NMI, eligible IRQ, then normal
opcode fetch. BRK is instruction-driven and uses the IRQ/BRK vector.

Phase 2I corrects PLP polling. The poll associated with PLP uses the old I
value even though the pulled status is architecturally visible at completion.
A one-boundary override stores only that old I value:

- old I=1, pulled I=0: one following instruction executes before a held IRQ;
- old I=0, pulled I=1: an IRQ already seen by PLP is still admitted;
- RTI does not use the override; its restored I is effective immediately.

IRQ/NMI push PC high, PC low, then B=0/U=1 status before vector low/high. BRK
consumes its padding byte, stacks opcode-PC+2, pushes B=1/U=1, and uses
FFFE/FFFF. RTI restores status, PC low, and PC high with no RTS-style increment.

## Address, branch, and bus-visible behavior

- `JMP ($xxFF)` reads its target low byte at `xxFF` and high byte at `xx00`.
  The RTL audit explicitly checks `$12FF -> $12FF/$1200`.
- Absolute-X, absolute-Y, and `(zp),Y` reads use the Phase 2C page-cross bit and
  add one correction read only when required. Exactly 23 implemented read
  opcode bytes have this conditional penalty.
- Indexed stores keep fixed timing and never inherit a read penalty. Memory RMW
  also has fixed timing.
- Branches remain 2 cycles not taken, 3 taken on the same page, and 4 taken
  across a page.
- Every memory INC/DEC/ASL/LSR/ROL/ROR form uses read, original-value write,
  then modified-value write. The focused Python audit covers all 24 opcode
  forms; RTL traces each of the six operations directly.

## Official and unofficial opcode audit

The canonical NMOS set contains 151 official opcode bytes. Decoder and Python
tables agree exactly on 141 implemented official bytes. The ten missing bytes
are:

| Bytes | Instructions | Reason currently absent |
| --- | --- | --- |
| 24, 2C | BIT zp / BIT abs | BIT family was not part of Phases 2D--2G |
| 18, 38 | CLC / SEC | carry-control family was not part of prior subsets |
| 58, 78 | CLI / SEI | interrupt-control family was not part of prior subsets |
| B8 | CLV | flag-control family was not part of prior subsets |
| D8, F8 | CLD / SED | decimal-flag control was not part of prior subsets |
| EA | NOP | NOP was not part of prior subsets |

All ten currently take the same deterministic unsupported trap as every
unofficial byte: the opcode is consumed, no write is generated, and the core
stops in `CPU_STATE_TRAP` until reset. No unofficial byte appears in the decode
or cycle tables. Thus current official-byte coverage is 141/151 (93.38%), and
the CPU must not yet be described as a complete official-instruction 2A03.

There are 105 unofficial byte encodings. Trapping is useful for deterministic
bring-up and error discovery, but it is not full NES compatibility: a minority
of commercial and homebrew software deliberately uses stable unofficial
operations. A later explicitly scoped CPU-completion phase should implement
the ten missing official bytes first, then select required stable unofficial
operations using test-ROM evidence. Phase 2I implements neither group.

## Interrupt edge-case classification

| Class | Behavior | Decision |
| --- | --- | --- |
| A: required now | Decimal ignored; NMI edge latch; IRQ level/mask; NMI priority; instruction-boundary recognition; PLP old-I poll; RTI immediate restored I | Implemented and directly tested |
| B: safe to defer | Exact branch-cycle polling, very short IRQ pulses, CLI/SEI one-instruction I latency once those opcodes exist, late NMI hijacking of IRQ/BRK, and half-cycle collision/suppression behavior | Requires a finer pin/poll pipeline; normal NES interrupt sources remain asserted or latched, so deterministic boundary behavior is a practical first target |
| C: unnecessary here | Transistor metastability, analog pin timing, and behavior of an external SO pin not exposed by this NES CPU-core interface | Outside synthesizable architectural compatibility scope |

In particular, an NMI arriving during BRK/IRQ sequencing is latched for a later
boundary; it does not hijack an already selected vector. This is documented,
not claimed as transistor-exact. Phase 2J should revisit class-B items only
after the missing official instructions and a program-level NES bus harness
make the relevant interrupt test ROMs executable.

## Verification and compatibility programs

The focused Python file independently verifies decimal arithmetic, all status
bytes, PLP/RTI polling, NMI edge capture, reset, indirect JMP, all RMW forms,
page-cross class rules, and the 151-byte official inventory. Earlier exhaustive
ALU, address, branch, instruction, interrupt, and bus-timing suites remain
unchanged except that the Phase 2H PLP expectation now checks the corrected
one-instruction IRQ delay.

`sim/cpu_phase2i_tb.sv` contributes 32 decimal executions, 64 status vectors,
3 interrupt/polling vectors, and 125 counted reset/bus audit vectors. It checks
every enabled step for X/Z, write-valid consistency, vector/stack status,
seven-cycle reset order, held/rearmed NMI, NMI-over-IRQ priority, indirect JMP,
all six RMW operations, indexed read/store page crossing, branch 3/4-cycle
classes, and inert traps. Its waveform is `build/sim/cpu_phase2i.fst`.

The open NES test-ROM inventories were reviewed but no external `.nes` binary
was executed. This repository intentionally has no Phase 3 memory map,
cartridge loader, reset environment, or peripheral bus, and its ten missing
official bytes prevent honest end-to-end test-ROM execution. The focused local
vectors test the applicable CPU behaviors directly without downloading or
redistributing ROM images. Program-level compatibility remains a documented
future gate.

## Local gate results

- pytest: 453 passed, including 11 focused Phase 2I tests;
- Verilator lint: passed with no emitted warnings;
- all platform and Phase 2A--2I RTL simulations: passed with assertions and
  X/Z checks enabled;
- Phase 2I waveform: `build/sim/cpu_phase2i.fst`;
- standalone CPU Analysis & Synthesis: 0 errors, 2 expected stuck-output
  warnings, 684 estimated ALMs, 1,050 combinational ALUTs, 191 registers,
  0 DSPs, and 0 PLLs;
- full DE1-SoC diagnostic build: 0 errors, 2 known board-project warnings,
  43 ALMs, 76 combinational ALUTs, 64 registers, 0 DSPs, and 0 PLLs; and
- board timing: fully constrained, minimum setup slack +14.713 ns and minimum
  hold slack +0.142 ns across the reported corners.

The standalone stuck output is `debug_status.break_command=0`, which is the
intentional nonpersistent-B policy. The board warnings are the unchanged Lite
edition LogicLock notice and incomplete-I/O-assignment notice. Neither warning
was introduced by connecting the CPU; the board diagnostic remains unchanged
and the CPU is not instantiated in `de1_soc_top`.

## Remaining limitations

- Ten official opcode bytes and all unofficial opcodes trap.
- Late-NMI vector hijacking and transistor-exact interrupt poll timing are not
  modeled.
- External test ROMs cannot yet run without the NES memory/bus environment.
- DMA, NES memory map, PPU, APU, cartridge, mapper, and controller logic remain
  outside this phase.
- The CPU remains deliberately disconnected from the stable board diagnostic.

Phase 2I stops at the audited Ricoh 2A03 CPU boundary.
