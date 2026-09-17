# Phase 2C CPU addressing

Phase 2C adds a combinational, opcode-independent effective-address generator
for the Ricoh 2A03 CPU foundation. It calculates addresses and metadata only.
It does not fetch operands, sequence bus cycles, decode opcodes, execute
instructions, or modify architectural state.

## Interface

`cpu_address_gen` accepts a packed `cpu_address_request_t` and returns a packed
`cpu_address_result_t`. The request contains:

- a raw 4-bit addressing-mode encoding;
- a 16-bit `base_address`;
- the 8-bit operand, X index, and Y index;
- caller-supplied low and high pointer bytes; and
- `pointer_data_valid`, which says that both pointer bytes are available.

The result separately exposes an effective address, the two pointer-fetch
addresses, a branch target, an immediate value, and mode metadata. Every value
with mode-dependent meaning has a corresponding validity bit.
`mode_valid` distinguishes supported modes from reserved encodings, while
`result_valid` indicates that the mode's final result is ready. Reserved
encodings 13 through 15 produce an all-zero, inert result.

The request carries a raw logic value rather than an enum-typed port so invalid
hardware encodings remain representable and testable. The enum constants in
`cpu_pkg.sv` still provide stable names for callers.

## Supported modes

| Mode | Input interpretation | Output |
| --- | --- | --- |
| implied | none | `is_implied`; no address/result |
| accumulator | none | `uses_accumulator`; no address/result |
| immediate | operand byte | immediate value |
| zero page | operand byte | `$00xx` effective address |
| zero page,X | operand plus X modulo 256 | `$00xx` effective address |
| zero page,Y | operand plus Y modulo 256 | `$00xx` effective address |
| absolute | base address | effective address |
| absolute,X | base plus X modulo 65536 | effective address and page crossing |
| absolute,Y | base plus Y modulo 65536 | effective address and page crossing |
| indirect | 16-bit pointer address | pointer-fetch addresses, then target |
| indexed indirect (X) | zero-page operand plus X | wrapped pointer addresses, then target |
| indirect indexed (Y) | zero-page operand and resolved pointer plus Y | pointer addresses, target, and page crossing |
| relative | caller-supplied branch base plus signed operand | branch target and page crossing |

Implied and accumulator are valid modes but do not naturally produce a value
or memory address, so `result_valid` remains clear. Immediate and relative
produce a value or target but deliberately leave `effective_address_valid`
clear. This keeps later execution logic from treating unlike results as memory
addresses.

## Wrapping and page crossing

Zero-page arithmetic is performed as a 9-bit sum followed by an explicit
selection of bits 7:0. It therefore always remains in `$0000`–`$00FF`:
`$FF + $01` and `$FE + $02` both produce `$0000`.

Absolute indexed arithmetic is performed as a 17-bit sum followed by an
explicit selection of bits 15:0. This is intentional modulo-65536 behavior, so
`$FFFF + $01` produces `$0000`. `page_cross` is the carry from the independent
low-byte addition. It is asserted for that wrap as well as for ordinary cases
such as `$12FF + $01 = $1300`. Future timing logic must use
`page_cross_valid` and decide whether the specific instruction pays an extra
cycle; this block does not decide timing.

Relative mode treats `$00`–`$7F` as 0 through +127 and `$80`–`$FF` as -128
through -1. The caller must supply the branch base explicitly—normally the PC
chosen by a later sequencer after reading the displacement. The generator does
not infer which PC phase the caller intended. An 18-bit signed intermediate
prevents intermediate overflow, and the target then wraps explicitly to 16
bits. Page crossing compares the supplied base page with the wrapped target
page.

This follows the original MCS6500 description of relative addressing as a
signed offset added after the displacement fetch; see the
[MCS6500 Microcomputer Family Programming Manual](https://syncopate.us/books/Synertek6502ProgrammingManual.html).

## Pointer modes and the bus boundary

Pointer modes require memory data and therefore have two distinct phases:

1. The generator reports `pointer_low_address` and `pointer_high_address`.
2. Future bus sequencing reads those locations and resubmits both bytes with
   `pointer_data_valid` set.

Until both bytes are marked valid, pointer addresses and `mode_valid` are
usable, but the effective address and `result_valid` remain clear. There is no
memory, bus master, or hidden read inside the generator.

For indexed indirect `(zero page,X)`, X is added before either pointer-byte
access. Both addresses wrap within zero page. Operand `$FF` with X `$02`
therefore fetches the low byte at `$0001` and the high byte at `$0002`.

For indirect indexed `(zero page),Y`, the pointer-byte addresses derive from
the unindexed operand and wrap within zero page. Operand `$FF` fetches from
`$00FF` and `$0000`. Once supplied, the 16-bit pointer is indexed by Y modulo
65536 and reports low-byte page crossing.

## NMOS indirect-JMP page wrap

The Ricoh 2A03 retains the original NMOS 6502 indirect-JMP page-boundary
behavior. The high-byte fetch increments only the pointer's low byte. Thus a
pointer at `$12FF` reports low and high fetches at `$12FF` and `$1200`, not
`$1300`. This is a deliberate compatibility behavior, not a generic 16-bit
pointer increment. The NES-specific behavior is documented by the
[NESdev CPU errata](https://www.nesdev.org/wiki/Errata) and its
[6502 reference](https://www.nesdev.org/obelisk-6502-guide/reference.html);
the latter also distinguishes later CMOS variants that corrected it.

## Verification coverage

The Python model calculates results with Python integer arithmetic, explicit
masks, and signed conversion rather than copying the RTL's intermediate-width
structure. Python tests cover the same exhaustive spaces and all required
directed boundaries.

The self-checking SystemVerilog testbench runs exactly **1,508,186 vectors**:

| Coverage group | Vectors |
| --- | ---: |
| implied and accumulator | 2 |
| all immediate and direct zero-page operands | 512 |
| zero page,X and zero page,Y, all operand/index pairs | 131,072 |
| required absolute boundaries | 10 |
| absolute,X and absolute,Y, all low-byte/index pairs over 6 high-byte partitions | 786,432 |
| every 16-bit indirect pointer address | 65,536 |
| indexed indirect (X), all operand/X pairs | 65,536 |
| indirect indexed (Y), every pointer-address operand | 256 |
| indirect indexed (Y), all low-byte/Y pairs over 6 pointer high-byte partitions | 393,216 |
| relative, all base-low-byte/offset pairs | 65,536 |
| required relative boundary/offset combinations | 70 |
| directed relative examples | 3 |
| additional unresolved-pointer handshake cases | 2 |
| reserved mode encodings | 3 |

Every RTL vector asserts the complete packed result and checks that no output
contains X or Z. The testbench also asserts the exact vector count. It writes
`build/sim/cpu_address_gen.fst` for debugging.

## Deliberate Phase 2C limitations

- No opcode table or opcode decode exists.
- No instruction, PC, cycle, or architectural-state update is performed.
- No bus sequencing, memory map, RAM, PPU, APU, DMA, cartridge, or controller
  behavior is implemented.
- Page-cross metadata is reported, but no timing penalty is selected.
- No address generator is connected to the board diagnostic or CPU shell.

Phase 2C stops at reusable address calculation and pointer-access planning.
