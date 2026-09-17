# Phase 2D CPU load, store, and transfer instructions

Phase 2D turns the architectural shell into a functional instruction engine
for the first official Ricoh 2A03 instruction subset. It implements only
loads, stores, and register transfers. The design still uses `CLOCK_50` as its
only fabric clock; every sequential transition is gated by `cpu_enable`.

## Execution architecture

The decoder, address arithmetic, sequential control, and memory are separate
concerns:

- `cpu_decoder` is a combinational table that recognizes exactly 37 official
  Phase 2D opcodes and supplies an instruction, addressing mode, and operand
  length.
- `cpu_core` owns architectural and sequencing state. It increments PC only
  when an opcode or operand byte is consumed.
- `cpu_address_gen` remains the only implementation of effective-address,
  zero-page wrap, index, pointer-address, and page-cross arithmetic.
- The CPU has no internal instruction/data memory. All reads and writes use
  the existing external bus.
- `cpu_test_memory` is a simulation-only generic 64 KiB memory, not an NES
  memory map.

The sequencer uses these explicit states:

1. `RESET` enters `FETCH` on the first enabled edge.
2. `FETCH` reads an opcode and increments PC.
3. `DECODE` either selects a supported path or enters `TRAP`.
4. `OPERAND_LOW` and, when required, `OPERAND_HIGH` read instruction bytes and
   increment PC once per byte.
5. `ADDRESS` submits the latched operands and index registers to the Phase 2C
   generator.
6. `POINTER_LOW` and `POINTER_HIGH` perform the two visible zero-page reads
   required by indexed-indirect modes. `ADDRESS` is then revisited with the
   caller-supplied pointer bytes.
7. `MEMORY_READ` or `MEMORY_WRITE` performs the final data bus cycle.
8. `WRITEBACK` updates a load destination and N/Z flags. `TRANSFER` performs
   an implied register transfer. Both return to `FETCH`.

There is no hidden combinational memory and no instruction-specific address
arithmetic inside the sequencer.

## Opcode and addressing-mode matrix

| Instruction | Official opcodes and modes implemented |
| --- | --- |
| LDA | `A9` immediate, `A5` zero page, `B5` zero page,X, `AD` absolute, `BD` absolute,X, `B9` absolute,Y, `A1` indexed indirect (X), `B1` indirect indexed (Y) |
| LDX | `A2` immediate, `A6` zero page, `B6` zero page,Y, `AE` absolute, `BE` absolute,Y |
| LDY | `A0` immediate, `A4` zero page, `B4` zero page,X, `AC` absolute, `BC` absolute,X |
| STA | `85` zero page, `95` zero page,X, `8D` absolute, `9D` absolute,X, `99` absolute,Y, `81` indexed indirect (X), `91` indirect indexed (Y) |
| STX | `86` zero page, `96` zero page,Y, `8E` absolute |
| STY | `84` zero page, `94` zero page,X, `8C` absolute |
| TAX | `AA` implied |
| TAY | `A8` implied |
| TXA | `8A` implied |
| TYA | `98` implied |
| TSX | `BA` implied |
| TXS | `9A` implied |

No illegal addressing combinations are inferred. The decoder starts from an
all-zero invalid result and assigns an instruction only in an explicit opcode
case.

## Bus contract and sequencing

`bus_valid=1` and `bus_write_enable=0` denotes a read. `bus_valid=1` and
`bus_write_enable=1` denotes the sole final write cycle of a store. Address and
write data remain stable for the entire sequencer state, including while
`cpu_enable=0`. A bus consumer commits a write exactly once on the enabled
edge that completes `MEMORY_WRITE`; the simulation memory follows this rule.

The observed bus ordering is:

- implied transfer: opcode read;
- immediate load: opcode, immediate byte;
- zero-page/absolute load or store: opcode, operand byte(s), final data cycle;
- indexed indirect `(zp,X)`: opcode, operand, indexed zero-page pointer low,
  wrapped pointer high, final data cycle;
- indirect indexed `(zp),Y`: opcode, operand, zero-page pointer low, wrapped
  pointer high, final indexed data cycle.

The pointer reads are therefore externally visible and cannot be mistaken for
an internal memory lookup. A store asserts write-enable only for its final
cycle, and no load, transfer, unsupported opcode, or internal state asserts a
write.

## Program counter and reset

PC increments on the enabled edge that consumes each instruction byte:

- implied transfers advance by 1;
- immediate and zero-page-family instructions advance by 2;
- absolute-family instructions advance by 3;
- both indexed-indirect families advance by 2.

No branch or jump can redirect PC in this phase. Production reset retains the
Phase 2A placeholder `PC=0000`; reset-vector reads remain deferred. `cpu_core`
has an `INITIAL_PC` parameter whose default is that architectural value. The
Phase 2D testbench deliberately overrides it to `0200` so program bytes do not
collide with zero-page pointer tests. Board and standalone synthesis use the
default, so the test mechanism does not change production reset behavior.

## Register and flag behavior

LDA, LDX, and LDY write only their destination and update N from result bit 7
and Z from a zero result. C, V, I, D, U, B representation, and unrelated
registers are preserved.

STA, STX, and STY place their source register on `bus_write_data` and perform
exactly one architectural memory write. They do not change any register or
status flag.

TAX, TAY, TXA, TYA, and TSX copy the named source to the destination and
update N/Z. TXS copies X to SP without changing any flag. Source registers are
not modified.

## Unsupported opcodes

Any opcode outside the table is fetched normally, so PC advances by one, and
then enters `CPU_STATE_TRAP`. The trap has no active bus cycle, performs no
write, and holds all architectural state until reset. It is intentionally not
treated as NOP.

## Page crossing and current cycle behavior

Absolute,X, absolute,Y, and indirect-indexed,Y latch the Phase 2C page-cross
value and validity metadata. No extra timing cycle is inserted yet. Later
Phase 2H timing work will decide instruction-specific penalties and introduce
any required dummy/speculative accesses.

Current functional enabled-step counts, measured from an initial `FETCH` state
through the return to `FETCH`, are:

| Form | Enabled steps | Visible bus cycles |
| --- | ---: | ---: |
| implied transfer | 3 | 1 |
| immediate load | 5 | 2 |
| zero-page-family load | 6 | 3 |
| zero-page-family store | 5 | 3 |
| absolute-family load | 7 | 4 |
| absolute-family store | 6 | 4 |
| indexed-indirect load | 9 | 5 |
| indexed-indirect store | 8 | 5 |

These counts are deterministic scaffolding, not a claim of final NMOS 6502
cycle accuracy.

## Verification coverage

Both the Python functional model and SystemVerilog testbench execute every
implemented opcode with each of `00`, `01`, `7F`, `80`, `FE`, and `FF` as the
data boundary value. The address partitions include `0000`, `0001`, `00FE`,
`00FF`, `0100`, `7FFF`, `8000`, `FF00`, `FFFE`, and `FFFF`; all six required
index values are exercised. There are no randomized vectors.

| Instruction | Opcodes | Directed RTL vectors | Randomized |
| --- | ---: | ---: | ---: |
| LDA | 8 | 48 | 0 |
| LDX | 5 | 30 | 0 |
| LDY | 5 | 30 | 0 |
| STA | 7 | 42 | 0 |
| STX | 3 | 18 | 0 |
| STY | 3 | 18 | 0 |
| TAX | 1 | 6 | 0 |
| TAY | 1 | 6 | 0 |
| TXA | 1 | 6 | 0 |
| TYA | 1 | 6 | 0 |
| TSX | 1 | 6 | 0 |
| TXS | 1 | 6 | 0 |
| **Total** | **37** | **222** | **0** |

For every directed vector, assertions check decode, bus ordering, PC,
effective address, page metadata, destination/source preservation, flags,
write count/data, and X/Z absence. Separate scenarios verify reset, an
unsupported opcode, and a store stalled in `MEMORY_WRITE` with
`cpu_enable=0`. The waveform is `build/sim/cpu_phase2d.fst`.

## Deliberate limitations

- No arithmetic, comparison, branch, jump, stack push/pop, interrupt, or reset
  vector execution is implemented.
- No final cycle accuracy, page-cross penalty, dummy access, or interrupt
  sampling timing is claimed.
- No NES memory map, RAM integration, DMA, PPU, APU, cartridge, mapper, or
  controller behavior exists.
- The CPU is not instantiated in `de1_soc_top`; the Phase 1 board diagnostic
  remains unchanged.

Phase 2D stops at the requested load/store/transfer subset.
