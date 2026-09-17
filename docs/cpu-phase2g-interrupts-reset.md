# Phase 2G CPU interrupts and reset

Phase 2G adds bus-visible reset-vector sequencing, synchronized external NMI
and IRQ requests, BRK, and RTI to the existing CPU sequencer. It does not add
a second execution engine, a derived clock, hidden stack memory, or a hidden
vector ROM. Architectural progress remains gated by `cpu_enable`; only the
input synchronizers and the NMI edge-pending latch run at the existing fabric
clock so asynchronous events are not lost between CPU enable pulses.

## Vector map

| Source | Low byte | High byte |
| --- | ---: | ---: |
| NMI | `FFFA` | `FFFB` |
| RESET | `FFFC` | `FFFD` |
| IRQ / BRK | `FFFE` | `FFFF` |

Every vector byte is fetched through the normal CPU bus in low-then-high
order. There is no direct reset-target parameter and no combinational vector
lookup.

## Reset behavior and priority

The synchronized platform reset has unconditional priority over
`cpu_enable`, interrupt recognition, and every sequencer state. While reset is
asserted, the bus is inert, so an interrupted store or stack push cannot
complete. Architectural state is deterministic: A/X/Y=`00`, SP=`FD`,
PC=`0000`, status=`24`, instruction=`00`, B=0, and U=1. After reset release:

1. `RESET` enters `RESET_VECTOR_LOW` on an enabled step.
2. `RESET_VECTOR_LOW` reads `FFFC`.
3. `RESET_VECTOR_HIGH` reads `FFFD`, forms the 16-bit target, and enters
   `FETCH` at that address.

Thus the target PC is never silently assigned. The chosen Phase 2G reset model
defines the post-reset SP as `FD` and status as `24`; exact NMOS dummy reads and
the internal three-decrement reset mechanism are deliberately deferred to the
Phase 2H bus-cycle refinement. Reset preemption is verified during fetch,
operand fetch, memory read, memory write, ALU execution, branch decision,
stack write, and interrupt entry.

Priority at an instruction boundary is:

1. RESET
2. pending NMI edge
3. asserted IRQ when I=0
4. normal opcode fetch

BRK is decoded as an instruction and is not an external priority source.

## NMI and IRQ input semantics

The core ports use logical active-high requests. A board integration that
starts from active-low physical pins must invert them outside the core. Both
inputs pass through two fabric-clock flip-flops; no new clock is created.

NMI is rising-edge detected after synchronization and stored in a pending
latch. Holding NMI high therefore creates one request, while a synchronized
deassertion followed by another assertion creates another. This matches the
2A03's edge-sensitive NMI behavior described by the
[NESdev NMI reference](https://www.nesdev.org/wiki/NMI). IRQ remains a
synchronized level request. It is eligible only when the persistent I flag is
clear, and a still-asserted IRQ can be taken after RTI restores I=0.

Requests are recognized at the `FETCH` boundary before the next opcode is
consumed. A recognized interrupt suppresses that speculative opcode bus cycle
and preserves the current PC as its return PC. This boundary policy is
deterministic and supports later timing refinement, but Phase 2G does not
claim transistor-level interrupt polling timing.

## Shared interrupt entry

`cpu_interrupt_source_t` records RESET, NMI, IRQ, BRK, or NONE. NMI, IRQ, and
BRK share these states:

- `INTERRUPT_PUSH_HIGH`: write return PC high at `0100 | SP`, then decrement;
- `INTERRUPT_PUSH_LOW`: write return PC low, then decrement;
- `INTERRUPT_PUSH_STATUS`: write source-specific status, decrement, and set I;
- `INTERRUPT_VECTOR_LOW`: read the selected vector low byte;
- `INTERRUPT_VECTOR_HIGH`: read high, load PC, and return to fetch.

Stack addressing uses the Phase 2F contract and the 8-bit SP wraps entirely
inside page 1. Hardware entry pushes the pre-entry I value because I is set
only after the status bus write.

## Status B/U representation

Persistent status remains `NVUBDIZC`, with B forced to 0 and U forced to 1.
D is stored and restored for architectural compatibility but never enables
decimal arithmetic on the Ricoh 2A03.

| Operation | Pushed byte | Restore policy |
| --- | --- | --- |
| PHP | `NV11DIZC` | not applicable |
| BRK | `NV11DIZC` | not applicable |
| IRQ / NMI | `NV10DIZC` | not applicable |
| PLP / RTI | not applicable | discard B, force U=1, restore N/V/D/I/Z/C |

The B bit is a stack representation, not persistent state. This distinction
and the fact that I masks IRQ but not NMI or BRK follow the
[NESdev status reference](https://www.nesdev.org/wiki/Status_flag) and its
[B-bit hardware notes](https://www.nesdev.org/wiki/Visual6502wiki/6502_BRK_and_B_bit).

## BRK and RTI

BRK (`00`) fetches its opcode, performs an explicit padding/signature-byte
read, and stacks the address two bytes beyond the opcode. It pushes high, low,
then status with B=1/U=1; sets I; and fetches `FFFE` then `FFFF`.

RTI (`40`) pre-increments SP, pulls status, pulls PC low, pulls PC high, and
installs that PC exactly. It does not apply RTS's `+1`. These return-address
rules agree with the original
[MOS MCS6500 Programming Manual](https://www.bitsavers.org/components/mosTechnology/6500-50A_MCS6500pgmManJan76.pdf).

## Current enabled-step counts

These are functional sequencer counts, not final NMOS 6502 cycle claims.

| Operation | Enabled steps | Visible bus events |
| --- | ---: | ---: |
| RESET after release | 3 | 2 vector reads |
| NMI / IRQ entry | 6 | 3 stack writes + 2 vector reads |
| BRK | 8 | opcode + padding reads, 3 writes, 2 vector reads |
| RTI | 7 | opcode read + 3 stack reads |

Exact dummy accesses, interrupt polling windows, and hardware-cycle alignment
remain Phase 2H work.

## Verification coverage

The independent Python reference suite adds 87 pytest cases. It covers all
256 raw status-byte B/U transformations, 64 combinations of persistent
N/V/D/I/Z/C fields, all six requested SP boundaries, all four reset targets,
IRQ masking, NMI-over-IRQ priority, held and repeated NMI edges, BRK and all
three RTI round trips. Deterministic randomized coverage executes 4,096
interrupt-entry vectors with seed `0x2A032601` and 2,048 NMI/RTI round trips
with seed `0x65022602`.

`sim/cpu_phase2g_tb.sv` executes 86 named directed vectors, including the 64
status combinations, six SP boundaries, four reset targets, six BRK/RTI SP
cases, masking/priority/edge cases, and the unsupported-opcode check. It also
checks 14 `cpu_enable` stall locations and eight reset-preemption classes.
Assertions verify exact stack/vector bus ordering, no duplicated writes,
status representation, PC restoration, SP wrap, IRQ masking, NMI priority,
and X/Z absence. The waveform is `build/sim/cpu_phase2g.fst`.

All earlier platform, CPU foundation, exhaustive ALU, exhaustive address,
load/store/transfer, arithmetic/logic, and control/stack regressions remain in
the standard test script.

## Deliberate limitations

- Final NMOS 6502 cycle accuracy and dummy bus cycles are not claimed.
- DMA and unofficial opcodes are not implemented.
- The NES memory map, PPU, APU, cartridge, mapper, and controller are not
  implemented.
- The CPU remains outside the stable Phase 1 board diagnostic top level.

Phase 2G stops at RESET, NMI, IRQ, BRK, and RTI.
