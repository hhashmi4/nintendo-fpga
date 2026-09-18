# Phase 2F CPU control flow and stack

> Historical phase note: Phase 2G implements the BRK, RTI, interrupt, and
> reset-vector items listed as limitations below. Phase 2H supersedes the
> functional step counts with canonical branch, stack, JSR/RTS, and dummy-read
> timing.

Phase 2F extends the existing CPU sequencer with official NMOS 6502/Ricoh
2A03 branches, jumps, subroutine control, and explicit stack operations. It
does not create a second execution engine, a derived clock, or hidden memory.
Every state transition and architectural update remains gated by
`cpu_enable`.

## Instruction and addressing matrix

| Family | Instruction | Opcode | Addressing mode |
| --- | --- | ---: | --- |
| Jump | JMP | `4C` | absolute |
| Jump | JMP | `6C` | indirect |
| Subroutine | JSR | `20` | absolute |
| Subroutine | RTS | `60` | implied |
| Branch | BCC | `90` | relative |
| Branch | BCS | `B0` | relative |
| Branch | BEQ | `F0` | relative |
| Branch | BMI | `30` | relative |
| Branch | BNE | `D0` | relative |
| Branch | BPL | `10` | relative |
| Branch | BVC | `50` | relative |
| Branch | BVS | `70` | relative |
| Stack | PHA | `48` | implied |
| Stack | PLA | `68` | implied |
| Stack | PHP | `08` | implied |
| Stack | PLP | `28` | implied |

All other newly encountered opcodes retain the Phase 2D deterministic trap
policy. In particular, BRK (`00`), RTI, interrupts, and unofficial opcodes are
not implemented. The trap has no active bus cycle and cannot write memory.

## Sequencer architecture

The existing fetch, decode, operand, address, and pointer-fetch states remain
the shared front end. Phase 2F adds only the micro-operation boundaries needed
for control flow:

- `BRANCH_DECIDE` applies an already calculated relative target.
- `STACK_PUSH`, `STACK_PULL`, and `STACK_READ` implement PHA/PHP/PLA/PLP.
- `JSR_PUSH_HIGH` and `JSR_PUSH_LOW` expose the two ordered stack writes.
- `RTS_PULL`, `RTS_PULL_LOW`, `RTS_PULL_HIGH`, and `RTS_COMPLETE` expose the
  pre-increment, two ordered reads, target reconstruction, and final increment.

The Phase 2C address generator remains the only source of relative-target and
indirect-pointer arithmetic. For a branch, `cpu_core` supplies the PC after
the displacement fetch as the explicit relative base. For indirect JMP, it
uses the generator's pointer-low and pointer-high addresses and performs the
two reads through the external bus.

## Branch semantics

The eight conditions are:

| Instruction | Taken when |
| --- | --- |
| BCC | `C == 0` |
| BCS | `C == 1` |
| BEQ | `Z == 1` |
| BMI | `N == 1` |
| BNE | `Z == 0` |
| BPL | `N == 0` |
| BVC | `V == 0` |
| BVS | `V == 1` |

The signed displacement is added to PC after both opcode and displacement
have been consumed. Addition wraps modulo 65536. The address generator reports
whether the target differs from that base in bits 15:8; this page-cross value
is retained for both taken and not-taken branches so Phase 2H can apply exact
timing. Branches do not modify status.

Phase 2F uses five enabled steps for both taken and not-taken branches:
fetch, decode, displacement fetch, address generation, and decision. It does
not yet add taken/page-cross penalty cycles.

## Stack bus contract

The stack address is always `{8'h01, SP}`. The 8-bit SP intentionally wraps
within page 1:

- push: write at `0100 | SP`, then decrement SP;
- pull: increment SP, then read at `0100 | SP`.

PHA and PHP generate exactly one architectural write. PLA and PLP generate
exactly one stack read. A bus state remains stable while `cpu_enable` is low;
the bus consumer commits a write only on an enabled edge, so a stall cannot
duplicate a push or SP update.

PHA preserves every flag. PLA replaces A and updates only N and Z. PHP
preserves internal status. PLP restores N, V, D, I, Z, and C under the status
representation policy below.

## PHP and PLP status representation

The persistent packed byte is ordered `NVUBDIZC`. It stores U as 1, stores D
for architectural compatibility, and always stores B as 0 because B is not a
persistent NMOS 6502 flag. D still has no effect on 2A03 arithmetic.

PHP synthesizes its bus byte as `NV11DIZC`: both U and B are 1. PLP accepts all
eight stack bits but normalizes the result, discarding stack B and forcing U
to 1 while restoring N, V, D, I, Z, and C. Thus neither PHP nor PLP can make B
persistent.

This policy follows the NMOS behavior described by the
[NESdev status-flag reference](https://www.nesdev.org/wiki/Status_flag) and
the transistor-level discussion in
[NESdev's Visual6502 B-bit notes](https://www.nesdev.org/wiki/Visual6502wiki/6502_BRK_and_B_bit).

## JMP, JSR, and RTS

JMP absolute consumes low then high operand bytes and redirects PC without a
stack access or flag change.

JMP indirect consumes a 16-bit pointer, reads target low at that pointer, then
reads target high at `{pointer[15:8], pointer[7:0] + 1}`. Consequently a pointer
ending in `FF` wraps its high-byte read within the same page: `JMP ($12FF)`
reads from `12FF` and `1200`, not `1300`. This is the Ricoh 2A03/NMOS behavior
documented by the [NESdev errata reference](https://www.nesdev.org/wiki/Errata),
and it is implemented once in the Phase 2C address generator.

After JSR fetches both target bytes, PC points to the following instruction.
JSR therefore stacks `PC - 1`, which is the address of its high operand byte.
It writes the return high byte first at the current SP, decrements SP, writes
the low byte, decrements SP again, and then installs the target PC. RTS pulls
low then high and installs the reconstructed value plus one. This produces the
normal JSR/RTS round trip to the byte following the three-byte JSR. The rule is
specified in the original
[MOS MCS6500 Programming Manual](https://www.bitsavers.org/components/mosTechnology/6500-50A_MCS6500pgmManJan76.pdf).

## Current deterministic enabled-step counts

These are functional sequencer counts, not final 6502 cycle claims.

| Instruction class | Enabled steps | External bus events |
| --- | ---: | ---: |
| Branch, taken or not | 5 | 2 reads |
| JMP absolute | 5 | 3 reads |
| JMP indirect | 8 | 5 reads |
| PHA / PHP | 3 | opcode read + stack write |
| PLA / PLP | 4 | opcode read + stack read |
| JSR | 7 | 3 reads + 2 writes |
| RTS | 6 | opcode read + 2 stack reads |

Exact dummy accesses, taken-branch penalties, and page-cross timing remain for
Phase 2H.

## Verification coverage

`tests/python/test_cpu_phase2f.py` contains 216 pytest cases. Its independent
functional model verifies:

- all 16 Phase 2F opcode/mode entries and exact RTL/Python decode agreement;
- 128 directed branch cases spanning all conditions, taken/not-taken,
  positive/negative displacement, page crossing, and 16-bit wrapping;
- all 256 possible input status bytes for PHP and all 256 for PLP;
- stack values `00`, `01`, `7F`, `80`, and `FF` at SP `FD`, `00`, and `FF`;
- boundary JMP, JSR, and RTS targets plus a complete JSR/RTS round trip;
- 4,096 randomized branches with seed `0x2FBA6502`;
- 1,024 randomized JSR executions with seed `0x2F5A6502`;
- 1,024 randomized PLP/status executions with seed `0x2F576502`.

`sim/cpu_phase2f_tb.sv` runs 241 directed RTL instruction vectors:

| Instruction | Directed RTL vectors |
| --- | ---: |
| Each branch opcode | 12 (96 total) |
| JMP absolute | 9 |
| JMP indirect | 3 |
| PHA | 15 |
| PLA | 15 |
| PHP | 24 |
| PLP | 24 |
| JSR | 27 |
| RTS | 27 |
| JSR/RTS round trip | 1 |

The RTL test also checks 10 explicit `cpu_enable` stalls: displacement fetch,
branch decision, stack write, stack read, each JSR push, each RTS pull, and
both indirect-JMP pointer reads. Assertions cover ordered bus events, exact
write counts, SP wrap, PC redirection, flag preservation/restoration,
unsupported trap behavior, and X/Z absence. The waveform is
`build/sim/cpu_phase2f.fst`.

Prior platform, CPU foundation, exhaustive ALU, exhaustive address generator,
load/store/transfer, and arithmetic/logic regressions remain in
`scripts/test.sh`.

## Deliberate limitations

- Interrupts, BRK, RTI, and reset-vector sequencing are not implemented.
- Final 6502 cycle accuracy, branch penalties, and dummy bus cycles are not
  claimed.
- DMA, unofficial opcodes, the NES memory map, PPU, APU, cartridge, mapper,
  and controller logic are not implemented.
- The CPU remains outside the stable Phase 1 board diagnostic top level.

Phase 2F stops at the requested branch, jump, subroutine, and stack subset.
