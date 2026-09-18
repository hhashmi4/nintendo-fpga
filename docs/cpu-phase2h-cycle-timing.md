# Phase 2H CPU cycle and bus timing

Phase 2H replaces the earlier functional step scaffolds with a bus-visible
NMOS 6502/Ricoh 2A03 timing engine for every official opcode implemented
through Phase 2G. One asserted `cpu_enable` advances exactly one logical CPU
cycle. `CLOCK_50` remains the only fabric clock; no derived clock was added.

This phase adds no instruction family, unofficial opcode, DMA, NES memory
map, or peripheral integration.

## References and interpretation

The implementation was audited against these established sources rather than
memory alone:

- the original [MOS MCS6500 Programming Manual](https://www.bitsavers.org/components/mosTechnology/6500-50A_MCS6500pgmManJan76.pdf)
  for official instruction/addressing cycle counts and control-flow behavior;
- [NESdev 6502 cycle times](https://www.nesdev.org/wiki/6502_cycle_times) and
  [NESdev addressing modes](https://www.nesdev.org/wiki/Addressing_modes) for
  indexed tentative reads, page repair, branches, and fixed store timing;
- the [Visual6502 state-machine trace](https://www.nesdev.org/wiki/Visual6502wiki/6502_State_Machine)
  for per-cycle JSR/RTS, stack, RMW, BRK, RTI, IRQ/NMI, and reset bus activity;
- [Visual6502 interrupt timing](https://www.nesdev.org/wiki/Visual6502wiki/6502_Timing_of_Interrupt_Handling)
  for instruction-boundary interrupt polling and priority details;
- [NESdev CPU power-up state](https://www.nesdev.org/wiki/CPU_power_up_state)
  and the [6502 reset internals analysis](https://www.pagetable.com/?p=410) for
  the seven reset cycles and three stack-page reads/decrements.

Published cycle tables generally omit the addresses of dummy transactions,
while transistor/state-machine traces expose them. There is no conflict in
cycle count; this design follows the latter for observable bus ordering. On a
physical chip, the pre-vector PC contents during the first reset reads are not
an architectural promise. This core deliberately reads deterministic `0000`
on those cycles to satisfy the project's no-X requirement. The three stack
reads, SP decrements, and `FFFC/FFFD` vector order match the NMOS sequence.

## Machine-readable cycle table

`verification/cpu_timing.py` exports `CYCLE_TABLE`, a dictionary keyed by all
141 currently implemented official opcode bytes. Each immutable `CycleSpec`
contains:

- opcode and mnemonic;
- addressing mode;
- base cycles;
- indexed page-cross penalty;
- branch-taken and branch-page-cross penalties;
- bus class: read, write, RMW, branch, jump, stack, interrupt, or implied.

`instruction_cycles()` consumes the same table in tests. Unsupported bytes
are absent rather than being assigned a fabricated NOP timing.

The complete table is compactly represented below. `+p` means one extra
cycle only when indexed address addition crosses a page. Branch `+t+p` means
one cycle when taken and another if the taken target crosses a page.

| Instruction(s) | Mode and cycles |
| --- | --- |
| LDA | immediate 2; zp 3; zp,X 4; absolute 4; absolute,X 4+p; absolute,Y 4+p; (zp,X) 6; (zp),Y 5+p |
| LDX | immediate 2; zp 3; zp,Y 4; absolute 4; absolute,Y 4+p |
| LDY | immediate 2; zp 3; zp,X 4; absolute 4; absolute,X 4+p |
| STA | zp 3; zp,X 4; absolute 4; absolute,X 5; absolute,Y 5; (zp,X) 6; (zp),Y 6 |
| STX | zp 3; zp,Y 4; absolute 4 |
| STY | zp 3; zp,X 4; absolute 4 |
| TAX, TAY, TXA, TYA, TSX, TXS | implied 2 |
| ADC, SBC, AND, ORA, EOR | immediate 2; zp 3; zp,X 4; absolute 4; absolute,X 4+p; absolute,Y 4+p; (zp,X) 6; (zp),Y 5+p |
| CMP | immediate 2; zp 3; zp,X 4; absolute 4; absolute,X 4+p; absolute,Y 4+p; (zp,X) 6; (zp),Y 5+p |
| CPX, CPY | immediate 2; zp 3; absolute 4 |
| INX, INY, DEX, DEY | implied 2 |
| INC, DEC | zp 5; zp,X 6; absolute 6; absolute,X 7 |
| ASL, LSR, ROL, ROR | accumulator 2; zp 5; zp,X 6; absolute 6; absolute,X 7 |
| BCC, BCS, BEQ, BMI, BNE, BPL, BVC, BVS | relative 2+t+p |
| JMP | absolute 3; indirect 5 |
| JSR / RTS | absolute 6 / implied 6 |
| PHA, PHP / PLA, PLP | implied 3 / implied 4 |
| BRK / RTI | implied 7 / implied 6 |

RESET, IRQ, and NMI are not opcodes in the table. Each uses seven enabled
cycles once its sequence begins.

## Indexed addressing and page crossing

Phase 2C remains the only source of address arithmetic. It now exposes both
the final effective address and the NMOS tentative address formed from the
uncorrected base high byte plus wrapped low-byte addition.

For absolute,X, absolute,Y, and `(zp),Y` reads, the CPU reads the tentative
address. If no page was crossed, that read is final. If a page was crossed,
the next cycle repeats the read at the corrected address. Exactly 23 read
opcodes carry this conditional penalty: five load cases, fifteen ADC/SBC/
AND/ORA/EOR cases, and three CMP cases.

Stores never receive a variable page-cross penalty. Indexed stores always
perform the tentative read and then the final write, giving fixed timing.
Absolute,X RMW instructions likewise have fixed timing: the tentative read is
followed by the final-address read and two writes.

Zero-page indexed modes read the unindexed zero-page operand address before
the wrapped indexed access. `(zp,X)` performs that index dummy read before
its two wrapped pointer-byte reads.

## Branch timing

Branches consume two cycles when not taken. A taken branch reads the already
advanced PC on cycle three. If the target crosses a page, cycle four reads
`{old_page, target_low}` before PC is corrected to the full target. Thus the
implemented classes are exactly 2, 3, and 4 cycles. The signed target and
page-cross metadata still come from the Phase 2C relative-address path.

The Python suite exhausts all 256 PC low bytes by all 256 offsets for each of
the eight branch opcodes, checking both taken and not-taken timing. This is
65,536 address/offset relationships, 524,288 opcode relationships, and both
condition outcomes.

## Read-modify-write bus behavior

Every memory INC, DEC, ASL, LSR, ROL, and ROR now has the NMOS bus tail:

1. read the original byte;
2. write the original byte back as the dummy write;
3. write the modified byte.

Both writes are externally visible and use the same effective address.
Accumulator shifts/rotates remain two-cycle implied operations and never
assert a memory write. The generic simulation memory commits a transaction
only on an enabled CPU edge, so holding either write state while
`cpu_enable=0` cannot duplicate it.

## Stack, jump, and subroutine timing

PHA/PHP are three cycles: opcode, next-PC dummy read, stack write. PLA/PLP are
four: opcode, next-PC dummy read, current-stack dummy read with SP increment,
then the pull.

JMP absolute is three cycles. JMP indirect is five and retains the Phase 2C
NMOS high-byte page-wrap behavior. JSR is six cycles in the NMOS ordering:
opcode, target-low read, stack dummy read, return-high write, return-low write,
then target-high read and redirect. RTS is six: opcode, next-PC dummy read,
current-stack dummy read, low pull, high pull, and a read at the stacked
address while installing stacked-address-plus-one.

## RESET, interrupts, BRK, and RTI

RESET is seven enabled cycles after synchronized reset release:

1. two discarded reads at deterministic PC `0000`;
2. reads at `0100`, `01FF`, and `01FE`, decrementing SP from `00` to `FD`
   without writes;
3. vector-low read at `FFFC`;
4. vector-high read at `FFFD` and PC load.

I is set during reset sequencing. A/X/Y and all internal state remain
deterministic. Reset itself still has unconditional priority and immediately
suppresses bus validity until release.

IRQ and NMI are seven cycles once recognized: discarded opcode read, second
dummy read, PC-high write, PC-low write, status write, vector-low read, and
vector-high read. IRQ/NMI push B=0/U=1. NMI remains synchronized and
edge-latched, IRQ synchronized and level-sensitive, and recognition remains
at an instruction boundary with NMI priority over an unmasked IRQ.

BRK is seven cycles: opcode, padding-byte read, three stack writes with the
return PC two bytes beyond the opcode and B=1/U=1, then `FFFE/FFFF`. RTI is
six: opcode, next-PC dummy, current-stack dummy, status pull, PC-low pull, and
PC-high pull. Unlike RTS, RTI adds nothing to the restored PC.

The implementation does not claim transistor-exact interrupt polling within
the final cycles of every preceding instruction, late NMI vector hijacking,
or asynchronous pin latency. The synchronized, instruction-boundary policy
is deterministic and the accepted interrupt/reset bus sequences and counts
are cycle accurate.

## Bus contract and trace format

Every active CPU state exposes one read or write cycle. The address, direction,
and write data remain stable between enable pulses. A bus target completes a
transaction on `cpu_enable && bus_valid`; this prevents a held write state
from becoming repeated writes on the 50 MHz fabric clock.

`sim/cpu_phase2h_tb.sv` records, for every enabled cycle:

- zero-based trace index;
- PC and execution state;
- `bus_valid`, address, and read/write direction;
- write data and current read data;
- SP and current instruction byte.

It compares ordered addresses, direction, and data against expected traces
and asserts that every enabled instruction cycle has a valid bus access. The
generated waveform is `build/sim/cpu_phase2h.fst`.

## Verification coverage

The Python suite contains a separate architectural timing model rather than
RTL-state names. It verifies:

- all 141 implemented opcode entries and canonical fixed counts;
- all 65,536 low-byte/index combinations for every applicable page-penalty
  opcode;
- all 65,536 PC-low/relative-offset relationships across all eight branches,
  taken and not taken;
- store/RMW immunity to read-style page penalties;
- tentative indexed bus addresses, NMOS RMW writes, and seven-cycle reset and
  interrupt traces;
- 10,000 deterministic full-address indexed traces using seed `0x2A03`.

The Phase 2H RTL bench checks 28 exact-cycle traces/program fragments: indexed
read with and without crossing, indexed store, RMW, all three branch timing
classes, JSR/RTS, PHA/PLA, BRK/RTI, IRQ, NMI, and every reset performed by
those scenarios. Two explicit stalls hold the original-value and final RMW
write cycles for four fabric clocks each. Assertions cover bus order, cycle
count, write data/count, PC/SP outcomes, no bus-idle logical cycles, no
duplicate writes, and X/Z absence.

Earlier benches were retained and changed only where their former functional
step expectations were intentionally superseded. They continue to exercise
222 Phase 2D opcode vectors, 516 Phase 2E vectors, 241 Phase 2F vectors, 86
Phase 2G vectors, the 591,876-vector ALU regression, and the 1,508,186-vector
address-generator regression.

## Remaining limitations

- Unofficial opcodes are not implemented.
- DMA and RDY-style external bus suspension are not implemented.
- Transistor-exact interrupt polling edge cases and late NMI vector hijacking
  are not modeled.
- The NES memory map, PPU, APU, cartridge, mapper, and controller are not
  implemented.
- The CPU remains outside the stable Phase 1 board diagnostic top level.

Phase 2H stops at timing correction and bus-trace verification of the existing
official instruction subset.
