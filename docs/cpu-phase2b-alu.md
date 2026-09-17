# CPU Phase 2B ALU and flag logic

Phase 2B adds a reusable, combinational ALU for the future Ricoh
2A03-compatible instruction engine. It does not decode opcodes, access the NES
memory map, or modify the Phase 2A architectural registers.

## Interface

`cpu_alu` accepts a 4-bit operation value, two 8-bit operands, and `carry_in`.
Callers use the `cpu_alu_operation_t` encodings declared in `cpu_pkg`. Keeping
the physical port as four raw bits ensures synthesis retains deterministic
behavior for the four unused encodings. The ALU produces:

- `result[7:0]` and `result_valid`;
- `negative`, `overflow`, `zero`, and `carry`; and
- `n_valid`, `v_valid`, `z_valid`, and `c_valid`.

Validity outputs define ownership. A later instruction engine updates a flag
only when its corresponding validity output is high; otherwise the prior
architectural flag must be preserved. Invalid operation encodings produce zero
values with every validity output low. This makes unsupported control values
deterministic without inventing architectural changes.

| Operation | Operands | Result valid | Flag writes |
| --- | --- | --- | --- |
| `ADD` | A + B + carry-in | yes | N, V, Z, C |
| `SUB` | A - B - (1 - carry-in) | yes | N, V, Z, C |
| `AND`, `OR`, `XOR` | A logic B | yes | N, Z |
| `ASL`, `LSR` | unary A | yes | N, Z, C |
| `ROL`, `ROR` | unary A plus carry-in | yes | N, Z, C |
| `INC`, `DEC` | unary A plus/minus one | yes | N, Z |
| `CMP` | A - B for flags | no | N, Z, C |

Flag values whose validity bit is low are driven to zero for deterministic
hardware behavior. Callers must use the validity interface, not those inert
values, when updating processor status.

## Arithmetic semantics

Addition computes a 9-bit `A + B + carry_in`. The low eight bits are the result
and bit eight is carry. Signed overflow is set when the two input signs match
and the result sign differs:

`V = ~(A7 ^ B7) & (A7 ^ result7)`

Subtraction follows 6502 SBC carry semantics and is implemented as
`A + ~B + carry_in`. Therefore carry set means no borrow; carry clear requests
an incoming borrow and reports an outgoing borrow. Signed overflow is:

`V = (A7 ^ B7) & (A7 ^ result7)`

The Ricoh 2A03 performs binary arithmetic only. The architectural D flag may
remain stored for software-visible compatibility, but it is not an ALU input
and cannot enable decimal adjustment.

## Compare, shifts, and rotates

`CMP` performs subtraction-style flag generation without result writeback.
`result_valid` is low, C is set exactly when A is greater than or equal to B, Z
is set on equality, and N comes from bit 7 of the wrapped subtraction result.
V is not owned and must be preserved.

`ASL` moves old bit 7 to C and shifts in zero. `LSR` moves old bit 0 to C and
shifts in zero at bit 7, so its valid N result is always clear. `ROL` shifts
carry-in into bit 0 and old bit 7 into C. `ROR` shifts carry-in into bit 7 and
old bit 0 into C. All four derive N and Z from the resulting byte and preserve
V through `v_valid=0`.

## Verification coverage

Both the independent Python model and the SystemVerilog testbench exhaust the
same complete functional input spaces, using independently expressed expected
arithmetic:

| Operation group | Exhaustive evaluations |
| --- | ---: |
| ADD: 256 x 256 x 2 carry inputs | 131,072 |
| SUB: 256 x 256 x 2 carry inputs | 131,072 |
| AND/OR/XOR: three times 256 x 256 | 196,608 |
| INC/DEC: two times 256 | 512 |
| ASL/LSR: two times 256 | 512 |
| ROL/ROR: two times 256 x 2 carry inputs | 1,024 |
| CMP: 256 x 256 x both ignored carry inputs | 131,072 |
| **Functional total** | **591,872** |

The RTL testbench also checks all four unused operation encodings, for 591,876
asserted RTL vectors total. Every vector checks result, result validity, N/V/Z/C,
per-flag validity, and the absence of X/Z outputs. Named Python boundary tests
cover the requested ADC/SBC edge cases in addition to the exhaustive grids.

Run `scripts/test.sh` for Python tests, lint, and all Phase 1/2A/2B simulations.
The ALU waveform is generated at `build/sim/cpu_alu.fst` and must be newly
created and non-empty for the simulation script to pass.

## Deliberately not implemented

Phase 2B does not implement opcode decode, addressing modes, instruction
sequencing, architectural writeback, decimal arithmetic, interrupts, the reset
vector sequence, the memory map, DMA, PPU, APU, controller, or cartridge logic.
The existing Phase 1 board diagnostic remains the board top-level behavior.

**PHASE 2B DOES NOT IMPLEMENT THE 6502 INSTRUCTION SET.**
