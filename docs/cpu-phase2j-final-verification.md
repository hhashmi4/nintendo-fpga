# Phase 2J final Ricoh 2A03 CPU verification

Phase 2J completes and qualifies the repository's CPU subsystem. The core now
implements all 56 official NMOS 6502 mnemonics represented by all 151 official
opcode bytes, with Ricoh 2A03 binary-only arithmetic. It remains a CPU core,
not an NES system: the NES memory map, DMA, PPU, APU, cartridge, mapper, and
controllers are deliberately outside this phase.

The generated [official opcode matrix](cpu-official-opcode-matrix.md) is the
human-readable full matrix. Its machine-readable source is
[`cpu-official-opcodes.json`](cpu-official-opcodes.json). Each of its 151 rows
records mnemonic, opcode, addressing mode, byte length, base cycles,
page/branch penalties, bus class, flag effects, implementation status, and
test status. `scripts/generate_cpu_opcode_matrix.py` regenerates both views
from the independently checked official-byte set, decoder model, and timing
table.

## References

The completed behavior and tests use:

- [NESdev CPU](https://www.nesdev.org/wiki/CPU) and
  [NESdev 2A03](https://www.nesdev.org/wiki/2A03) for the NES CPU lineage and
  disabled decimal arithmetic;
- [NESdev instruction reference](https://www.nesdev.org/wiki/Instruction_reference)
  for official encodings, modes, lengths, cycles, and flag effects;
- [Visual6502 interrupt timing](https://www.nesdev.org/wiki/Visual6502wiki/6502_Timing_of_Interrupt_Handling)
  for old-I polling after CLI, SEI, and PLP;
- [NESdev status flags](https://www.nesdev.org/wiki/Status_flag) and
  [Visual6502 B-flag analysis](https://www.nesdev.org/wiki/Visual6502wiki/6502_BRK_and_B_bit)
  for B/U push and pull policy;
- [NESdev cycle tables](https://www.nesdev.org/wiki/6502_cycle_times), the
  [MOS MCS6500 Programming Manual](https://www.bitsavers.org/components/mosTechnology/6500-50A_MCS6500pgmManJan76.pdf),
  and the Phase 2H references for bus timing; and
- Klaus Dormann's GPL-3.0
  [6502/65C02 functional tests](https://github.com/Klaus2m5/6502_65C02_functional_tests)
  for external all-official-instruction qualification.

The instruction and Visual6502 references agree that CLI and SEI do not alter
the I value used by the instruction's already-associated interrupt poll. CLI
with old I=1 therefore permits one following instruction before a held IRQ;
SEI with old I=0 does not suppress an IRQ already recognized by that poll.

## Architecture

`rtl/cpu/cpu_core.sv` owns architectural A, X, Y, SP, PC, normalized status,
interrupt metadata, operand/pointer latches, and the shared microsequencer.
It instantiates:

- `cpu_decoder.sv`, which recognizes exactly the 151 official bytes;
- `cpu_alu.sv`, the sole implementation of arithmetic, logic, compare,
  increment/decrement, and shift/rotate semantics; and
- `cpu_address_gen.sv`, the sole implementation of effective-address,
  relative-target, indexed-tentative, pointer-fetch, and page-cross arithmetic.

The only fabric clock is `clk`, driven by board `CLOCK_50` through the existing
platform. Architectural and sequencer state changes occur only on a rising
edge with `cpu_enable=1`, except synchronous reset priority. Bus signals remain
deterministic during stalls, and the memory model commits a write only on an
enabled valid write edge.

### CPU bus interface

| Port | Width | Direction | Meaning |
| --- | ---: | --- | --- |
| `clk` | 1 | input | sole fabric clock |
| `reset` | 1 | input | synchronized active-high CPU reset |
| `cpu_enable` | 1 | input | one logical CPU cycle when asserted |
| `nmi` | 1 | input | logical active-high asynchronous NMI request, synchronized and edge-latched internally |
| `irq` | 1 | input | logical active-high asynchronous IRQ request, synchronized and level-tested internally |
| `bus_address` | 16 | output | current read/write address |
| `bus_write_data` | 8 | output | valid store/stack/RMW data during a write |
| `bus_read_data` | 8 | input | combinational read value for the current address |
| `bus_write_enable` | 1 | output | write direction; low means read |
| `bus_valid` | 1 | output | current logical cycle owns a bus access |

Every enabled NMOS-style CPU cycle is a valid bus read or write. Address and
write data are stable for the state. `bus_write_enable` is asserted only for
the intended final store, stack push, interrupt frame write, or the two
bus-visible memory RMW writes. The core has no ready/RDY input yet.

Debug/status outputs are `debug_a`, `debug_x`, `debug_y`, `debug_sp`,
`debug_pc`, `debug_status`, `debug_instruction`, `debug_execution_state`,
`debug_decoded_instruction`, `debug_addressing_mode`,
`debug_effective_address`, `debug_page_cross`, and
`debug_page_cross_valid`. They are observation ports and do not bypass normal
architectural state updates.

## Phase 2J instructions

| Opcode | Instruction | Mode | Bytes | Cycles | Flag effects |
| ---: | --- | --- | ---: | ---: | --- |
| 24 | BIT | zero page | 2 | 3 | N=M7, V=M6, Z=(A & M)==0 |
| 2C | BIT | absolute | 3 | 4 | N=M7, V=M6, Z=(A & M)==0 |
| 18 | CLC | implied | 1 | 2 | C=0 |
| 38 | SEC | implied | 1 | 2 | C=1 |
| 58 | CLI | implied | 1 | 2 | I=0; next poll uses old I |
| 78 | SEI | implied | 1 | 2 | I=1; next poll uses old I |
| B8 | CLV | implied | 1 | 2 | V=0 |
| D8 | CLD | implied | 1 | 2 | D=0 |
| F8 | SED | implied | 1 | 2 | D=1 |
| EA | NOP | implied | 1 | 2 | none |

BIT uses the normal operand/address states and final bus read. It never writes
A or memory. All flag controls and official NOP use `CPU_STATE_IMPLIED`, whose
second cycle performs the documented read from the next PC without consuming
another byte. Unofficial NOP encodings are not aliases for EA.

The D flag remains persistent so PHP/PLP and interrupt frames retain the
architectural bit. Neither D nor the new SED/CLD path reaches the ALU; ADC and
SBC remain bit-identical binary operations for D=0 and D=1.

## Complete CPU behavior

The core supports implied, accumulator, immediate, zero page, zero page X/Y,
absolute, absolute X/Y, indirect, indexed indirect X, indirect indexed Y, and
relative modes. Zero-page pointer arithmetic wraps in page zero, relative
offsets are signed, indexed read penalties use shared page-cross metadata, and
`JMP ($xxFF)` fetches its high byte from `$xx00`.

The stack is external bus memory at `$0100 | SP`. Push writes then decrements;
pull increments then reads. JSR stacks PC-1 high then low; RTS pulls low/high
and adds one. PHP/BRK synthesize B=1/U=1, IRQ/NMI synthesize B=0/U=1, and
PLP/RTI normalize internal B=0/U=1.

RESET performs seven reads: two deterministic discarded PC reads, three
write-suppressed page-1 stack reads/decrements, then FFFC and FFFD. NMI is
edge-latched, IRQ is level-sensitive and I-masked, and priority is RESET, NMI,
IRQ, normal fetch. NMI/IRQ/BRK share stack/vector states; RTI restores status
and PC without an RTS increment.

Phase 2H timing remains authoritative. Indexed read instructions conditionally
add a page-correction read; stores and absolute-indexed RMW forms retain fixed
timing. Branches take 2, 3, or 4 cycles. Memory INC/DEC/ASL/LSR/ROL/ROR expose
read, original-value write, and modified-value write. Accumulator forms never
write memory.

## Verification

The local Python suite contains 466 passing tests. Major aggregate coverage is:

- reusable ALU RTL: 591,876 asserted vectors, including every 8-bit input and
  carry combination for ADC/SBC and exhaustive logic/compare/shift spaces;
- address generator RTL: 1,508,186 asserted vectors;
- Phase 2D/2E/2F/2G RTL: 222, 516, 241, and 86 directed vectors;
- Phase 2H: 29 exact cycle/bus traces plus exhaustive Python branch and indexed
  low-byte relationships and 10,000 seed-`0x2A03` full-address traces;
- Phase 2I: 32 D-invariance RTL executions, 64 status vectors, 3 interrupt
  vectors, and 123 reset/bus vectors;
- Phase 2J RTL: 72 BIT vectors, 2,048 exhaustive raw-status flag/NOP vectors,
  2 CLI/SEI poll vectors, 2 SED arithmetic vectors, and 258 decoder/trap/stall
  policy vectors, or 2,382 focused vectors total;
- Phase 2J Python: 65,536 exhaustive BIT truth-table combinations, 72 executed
  BIT vectors, 2,048 status vectors, all 105 unofficial traps, all 151 matrix
  rows, 20,000 completion-instruction randomized vectors with seed
  `0x2A032A0A`, and 4,832 full-official-set randomized smoke vectors (32 per
  opcode byte) with seed `0x2A031510`;
- ten deterministic multi-instruction model programs covering arithmetic,
  compare/branch, nested JSR/RTS, stack, BIT/branch, flag control,
  decimal-disabled arithmetic, RMW, BRK/RTI, and IRQ/RTI; and
- retained randomized suites total 49,168 vectors across Phase 2E arithmetic,
  Phase 2F branch/JSR/status, Phase 2G interrupts, Phase 2H addressing, and
  Phase 2J completion.

Every focused RTL step asserts absence of X/Z and write-valid consistency.
Existing benches assert PC/SP ordering, vector/stack sequencing, no duplicate
writes under `cpu_enable` stalls, RMW double writes, and exact bus traces. The
Phase 2J waveform is `build/sim/cpu_phase2j.fst`.

### External program

The GPL-3.0 Klaus functional source was fetched from its upstream repository at
source SHA-256
`f2665bd02288866c2b210b908e3f387926b4c9f0e0af5ad5513c474361ad1265`.
Only `disable_decimal` was changed from 0 to 1, appropriate because the 2A03
does not implement BCD arithmetic. AS65 1.42 assembled the result; generated
Intel HEX SHA-256 was
`b9261fed58c15ef8bb5844e0b978f746b397641a95cc314e5f08e16c18708c4a`.

The verification-only flat-memory runner loaded the image at `$0400`, retained
normal bus-visible reset and execution, and reached the build's stable success
loop at `$336D` after **84,030,451 enabled CPU cycles** and **6,266,229 bus
writes**. Unsupported opcodes, X/Z, an alternate stable failure loop, or
100,000,000 cycles would have failed the run. No proprietary ROM was used or
committed. `sim/cpu_program_tb.sv`, `verification/cpu_program.py`,
`scripts/convert_intel_hex.py`, and `scripts/run_cpu_program.sh` form the
generic verification-only harness.

NES `.nes` timing and interrupt ROMs were not claimed as run: they require the
Phase 3 CPU memory map, cartridge window, and often PPU/APU register behavior.
Implementing that environment in this phase would violate the CPU-only scope.

## Synthesis and board boundary

Quartus Prime Lite 23.1.1 completed both required targets for Cyclone V
`5CSEMA5F31C6`:

| Target | Result | ALMs | ALUTs | Registers | RAM bits/blocks | DSPs | PLLs |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| standalone `cpu_core` Analysis & Synthesis | PASS, 0 errors/2 warnings | 717 estimated | 1,097 | 191 | 0 | 0 | 0 |
| full `de1_soc_top` fit | PASS, 0 errors/2 warnings | 43 | 76 | 64 | 0/0 | 0 | 0 |

The CPU-only warnings are the expected aggregate/stuck-output notice and the
constant-low nonpersistent debug B bit. The board warnings are the existing
Lite-edition LogicLock subscription notice and incomplete assignments for
unused board pins; neither is a timing or RTL warning. The full board timing
analysis is fully constrained. Across all four operating corners, worst setup
slack is **14.713 ns**, worst hold slack is **0.142 ns**, and setup/hold TNS is
**0.000 ns**. The board diagnostic continues to use one 50 MHz `CLOCK_50`.

The CPU remains disconnected from `de1_soc_top`; the stable Phase 1 diagnostic
is unchanged. Generated Quartus and simulation artifacts remain under ignored
`build/` paths.

## Unofficial opcode policy and remaining limitations

Exactly 105 unofficial byte encodings enter deterministic `CPU_STATE_TRAP`
after consuming the opcode. The trap performs no unintended write and persists
until reset. This is intentionally not compatibility with software that uses
stable unofficial instructions; some commercial and homebrew NES programs may
therefore require a later explicitly scoped extension.

Other intentional limitations are:

- no RDY/DMA stall input or OAM DMA engine;
- no NES CPU bus interconnect, internal RAM, mirrors, or open-bus policy;
- no PPU, APU, controller, cartridge, mapper, video, or audio subsystem;
- no late-NMI vector hijacking or transistor/half-cycle-exact interrupt
  collision behavior; synchronized instruction-boundary behavior is retained;
- no physical active-low pin convention at this logical core boundary; and
- no CPU hardware diagnostic was added because exposing a flat CPU program on
  the board would improperly begin system integration and disturb the stable
  diagnostic.

Phase 2J stops at the completed official CPU boundary. The next phase is Phase
3A, the NES CPU bus interconnect and address decoder.
