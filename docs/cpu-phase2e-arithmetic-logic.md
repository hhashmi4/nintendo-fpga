# Phase 2E CPU arithmetic and logic instructions

> Historical phase note: Phase 2H supersedes the functional step counts and
> one-write RMW description below. Memory RMW now performs an original-value
> dummy write followed by the modified-value write; opcode semantics and ALU
> coverage remain unchanged.

Phase 2E integrates the verified Phase 2B ALU into the Phase 2D instruction
engine. It implements only official arithmetic, logic, compare,
increment/decrement, shift, and rotate opcodes. The Phase 1 board diagnostic
remains the top-level behavior, and `CLOCK_50` remains the only fabric clock.

## Instruction matrix

| Instruction | Official opcodes and addressing modes |
| --- | --- |
| ADC | `69` immediate, `65` zero page, `75` zero page,X, `6D` absolute, `7D` absolute,X, `79` absolute,Y, `61` indexed indirect (X), `71` indirect indexed (Y) |
| SBC | `E9` immediate, `E5` zero page, `F5` zero page,X, `ED` absolute, `FD` absolute,X, `F9` absolute,Y, `E1` indexed indirect (X), `F1` indirect indexed (Y) |
| AND | `29` immediate, `25` zero page, `35` zero page,X, `2D` absolute, `3D` absolute,X, `39` absolute,Y, `21` indexed indirect (X), `31` indirect indexed (Y) |
| ORA | `09` immediate, `05` zero page, `15` zero page,X, `0D` absolute, `1D` absolute,X, `19` absolute,Y, `01` indexed indirect (X), `11` indirect indexed (Y) |
| EOR | `49` immediate, `45` zero page, `55` zero page,X, `4D` absolute, `5D` absolute,X, `59` absolute,Y, `41` indexed indirect (X), `51` indirect indexed (Y) |
| CMP | `C9` immediate, `C5` zero page, `D5` zero page,X, `CD` absolute, `DD` absolute,X, `D9` absolute,Y, `C1` indexed indirect (X), `D1` indirect indexed (Y) |
| CPX | `E0` immediate, `E4` zero page, `EC` absolute |
| CPY | `C0` immediate, `C4` zero page, `CC` absolute |
| INX / INY | `E8` / `C8` implied |
| DEX / DEY | `CA` / `88` implied |
| INC | `E6` zero page, `F6` zero page,X, `EE` absolute, `FE` absolute,X |
| DEC | `C6` zero page, `D6` zero page,X, `CE` absolute, `DE` absolute,X |
| ASL | `0A` accumulator, `06` zero page, `16` zero page,X, `0E` absolute, `1E` absolute,X |
| LSR | `4A` accumulator, `46` zero page, `56` zero page,X, `4E` absolute, `5E` absolute,X |
| ROL | `2A` accumulator, `26` zero page, `36` zero page,X, `2E` absolute, `3E` absolute,X |
| ROR | `6A` accumulator, `66` zero page, `76` zero page,X, `6E` absolute, `7E` absolute,X |

The decoder recognizes exactly these 86 new opcodes plus the 37 Phase 2D
opcodes. Unsupported and unofficial bytes, including unofficial SBC `EB`,
retain the Phase 2D policy: consume the opcode, enter `TRAP`, issue no bus
cycle, and hold architectural state until reset.

## ALU integration and flag ownership

`cpu_decoder` supplies an ALU operation and instruction-class metadata.
`cpu_core` selects operands and carry-in, then instantiates `cpu_alu` directly.
The core contains no duplicate add, subtract, compare, increment, shift, or
rotate arithmetic. It updates N, V, Z, or C only when the corresponding ALU
valid output is asserted.

| Instruction class | ALU operation | Result destination | Flag writes |
| --- | --- | --- | --- |
| ADC | ADD | A | N, V, Z, C |
| SBC | SUB | A | N, V, Z, C |
| AND / ORA / EOR | AND / OR / XOR | A | N, Z |
| CMP / CPX / CPY | CMP | none | N, Z, C |
| INX / INY / INC | INC | register or memory | N, Z |
| DEX / DEY / DEC | DEC | register or memory | N, Z |
| ASL / LSR / ROL / ROR | matching ALU operation | A or memory | N, Z, C |

The ALU's `result_valid` is required for every architectural result write.
Compare deliberately has `result_valid=0`; the sequencer accepts only its
N/Z/C-valid combination and performs no register writeback. Flags without a
valid signal retain their previous value, so compare and shifts preserve V,
logic preserves C/V, and increment/decrement preserves C/V. I, D, U, and the
stored B representation are never selected by ALU flag writeback.

## Arithmetic and Ricoh 2A03 behavior

ADC supplies A, the fetched operand, and architectural C to the binary ADD
operation. SBC supplies the same inputs to binary SUB, where C set means no
incoming borrow. The signed-overflow and carry/no-borrow results are exactly
the Phase 2B outputs.

The stored D flag is not connected to the ALU. ADC and SBC therefore remain
binary even when D is one, matching the Ricoh 2A03's disabled decimal
arithmetic. The focused RTL test starts with D set and proves it is preserved
without changing results. `INITIAL_STATUS` is a verification parameter whose
default remains the Phase 2A reset value; production synthesis uses that
default.

## Compare, accumulator, and RMW execution

CMP selects A, CPX selects X, and CPY selects Y as the left operand. All use
the Phase 2B CMP operation: C means `lhs >= rhs`, Z means equality, and N is
bit 7 of the wrapped subtraction. No source register or memory is modified.

Accumulator ASL/LSR/ROL/ROR proceeds directly from decode to `ALU_EXECUTE`.
It performs no operand or data-memory read and no memory write. ROL and ROR
use architectural C as carry-in.

Memory INC, DEC, ASL, LSR, ROL, and ROR use an explicit read-modify-write
path:

1. fetch operand bytes and resolve the Phase 2C effective address;
2. expose a normal memory read bus cycle;
3. latch the byte and transform it in `ALU_EXECUTE`;
4. retain the ALU result in `data_latch`;
5. expose one final write in `RMW_WRITE`.

There is no hidden memory mutation. The simulation memory commits the final
write only on the enabled edge completing `RMW_WRITE`. Exact NMOS 6502 dummy
writes and cycle placement remain Phase 2H work, but the separate read, ALU,
and write states preserve a clean refinement boundary.

## Current enabled-step counts

Counts run from an initial `FETCH` state through the return to `FETCH`:

| Form | Enabled steps | Visible bus cycles |
| --- | ---: | ---: |
| implied register INC/DEC | 3 | 1 |
| accumulator shift/rotate | 3 | 1 |
| immediate ALU/compare | 5 | 2 |
| zero-page ALU/compare | 6 | 3 |
| absolute ALU/compare | 7 | 4 |
| pointer ALU/compare | 9 | 5 |
| zero-page memory RMW | 7 | 4 |
| absolute memory RMW | 8 | 5 |

Page-cross metadata remains latched for absolute indexed and indirect
indexed-Y reads. No penalty or speculative access is added yet. These are
deterministic functional counts, not a final cycle-accuracy claim.

## Verification coverage

The Python and RTL suites cover every official Phase 2E opcode/mode with six
directed vectors, for 516 RTL instruction vectors. Directed arithmetic cases
include both carry inputs, signed overflow, carry/no-borrow, zero, and negative
results. Compare includes less/equal/greater cases. INC/DEC and shift/rotate
include `00`, `01`, `7F`, `80`, `FE`, and `FF`, both rotate carry inputs, and
bit-zero/bit-seven transitions.

The Python model additionally executes 1,024 randomized ADC and 1,024
randomized SBC instructions. Seed bases are `0x2E6502 + instruction_id`.
Each vector randomizes the official addressing mode, accumulator, memory
operand, index, address/pointer, carry, and preserved status bits. Random tests
supplement rather than replace the directed matrix.

| Instruction | Opcodes | Directed RTL vectors | Randomized Python |
| --- | ---: | ---: | ---: |
| ADC | 8 | 48 | 1,024 |
| SBC | 8 | 48 | 1,024 |
| AND / ORA / EOR | 24 | 144 | 0 |
| CMP | 8 | 48 | 0 |
| CPX / CPY | 6 | 36 | 0 |
| INX / INY / DEX / DEY | 4 | 24 | 0 |
| INC / DEC | 8 | 48 | 0 |
| ASL / LSR / ROL / ROR | 20 | 120 | 0 |
| **Total** | **86** | **516** | **2,048** |

The RTL testbench directly checks the selected ALU operation, both operands,
carry-in, result, result validity, N/V/Z/C values, and all four flag-valid
signals at `ALU_EXECUTE`. It also checks exact bus order, PC consumption,
register/memory destinations, one-write RMW behavior, page metadata, and X/Z
absence. Dedicated stalls cover opcode fetch, operand fetch, memory read,
ALU execution, load writeback, and RMW write. The waveform is
`build/sim/cpu_phase2e.fst`.

All Phase 1 and Phase 2A through 2D regressions remain in `scripts/test.sh`,
including the 591,876-vector ALU test and 1,508,186-vector address-generator
test.

## Deliberate limitations

- No branch, jump, stack push/pop, interrupt, DMA, or unofficial opcode is
  implemented.
- Decimal arithmetic remains disabled.
- Final cycle accuracy, page-cross penalties, dummy accesses, and exact NMOS
  RMW bus behavior are not claimed.
- No NES memory map, PPU, APU, cartridge, mapper, controller, or board-level
  CPU integration is implemented.

Phase 2E stops at the requested arithmetic and logic subset.
