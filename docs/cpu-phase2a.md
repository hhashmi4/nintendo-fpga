# CPU Phase 2A architectural foundation

> Historical phase note: Phase 2G supersedes the placeholder PC behavior
> described below with bus-visible `$FFFC/$FFFD` reset-vector sequencing while
> preserving the documented deterministic register/status reset values.

Phase 2A establishes the synthesizable architectural and bus shell for the
future Ricoh 2A03-compatible CPU. It uses the existing 50 MHz system clock and
the Phase 1 `cpu_ce` pulse; it does not generate or use a derived CPU clock.

**PHASE 2A DOES NOT IMPLEMENT THE 6502 INSTRUCTION SET.**

## Architectural state and reset

The synchronized platform `reset` is a synchronous reset at the CPU boundary
and has priority over `cpu_enable`. It initializes every implemented sequential
field on the next `clk` edge. Outside reset, CPU sequential state can change
only on an edge where `cpu_enable` is high.

| State | Width | Reset value | Phase 2A behavior |
| --- | ---: | ---: | --- |
| A accumulator | 8 | `00` | Held |
| X index | 8 | `00` | Held |
| Y index | 8 | `00` | Held |
| SP stack pointer | 8 | `FD` | Held |
| PC program counter | 16 | `0000` | Held; no increment yet |
| P processor status | 8 | `24` | Held |
| Instruction register | 8 | `00` | Captures placeholder fetch data |
| Execution state | 3 | `RESET` | Enters `FETCH` on the first enable |

`SP=FD` is a deterministic post-reset convention suitable for the future NES
CPU. `PC=0000` is explicitly a placeholder, not a model of 6502 reset-vector
loading. A later CPU phase must implement reads of `FFFC` and `FFFD` and load
the resulting address before any instruction is interpreted.

The status byte uses the conventional `N V U B D I Z C` layout. Reset value
`24` sets interrupt-disable (`I`) and the unused/reserved representation (`U`),
while all other bits are clear. Stored status is normalized so `U` remains one
and `B` remains zero. Break is not modeled as persistent state; a later stack
operation will synthesize its pushed representation. The decimal (`D`) bit is
retained as architectural storage for 6502-family compatibility, but the Ricoh
2A03 has no decimal arithmetic and this project will not use it to select BCD
arithmetic.

The `debug_*` outputs are read-only visibility for automated verification and
hardware bring-up. They do not form a second state path or clock domain.

## CPU bus

The CPU-side interface is intentionally independent of the future memory map:

| Signal | Direction | Meaning |
| --- | --- | --- |
| `bus_address[15:0]` | output | Current CPU address; PC during placeholder fetch |
| `bus_write_data[7:0]` | output | CPU write data; fixed to zero in Phase 2A |
| `bus_read_data[7:0]` | input | Read response sampled on an enabled fetch edge |
| `bus_write_enable` | output | High for a write; always low in Phase 2A |
| `bus_valid` | output | Active CPU bus cycle |

`bus_valid=1` with `bus_write_enable=0` denotes a read. A placeholder fetch
cycle stays valid between CPU enable pulses, allowing a future RAM/PPU/APU/
controller/cartridge/DMA interconnect to decode the stable address and return
data before the next enabled edge. Reset removes `bus_valid` combinationally;
all bus outputs have defined values during and after reset.

No RAM, cartridge storage, address decoding, arbitration, wait-state protocol,
or NES memory map is implemented here.

## Execution scaffold

`cpu_execution_state_t` reserves `RESET`, `FETCH`, `DECODE`, `EXECUTE`,
`MEMORY`, and `WRITEBACK`. Only two states are active:

1. Reset places the core in `RESET` with `bus_valid=0`.
2. The first `cpu_enable` after reset enters `FETCH`.
3. `FETCH` presents PC as a read cycle and samples `bus_read_data` into the
   instruction register on each later `cpu_enable`.
4. PC and all architectural registers remain unchanged.

There is deliberately no decode transition, opcode behavior, addressing mode,
ALU operation, stack transaction, interrupt sequence, reset-vector fetch, or
writeback. Reserved states recover to `RESET` if reached before implementation.

## Verification

Run the complete local software gate with an activated project virtualenv:

```bash
./scripts/test.sh
```

The independent Python model checks reset state, status representation, enable
gating, repeated reset, placeholder fetch behavior, bus defaults, and agreement
between model values and RTL package constants. The focused SystemVerilog
testbench checks the same behavior against RTL with immediate assertions,
including X/Z detection after reset, exact widths, reset priority, the absence
of writes, and PC hold behavior. It writes
`build/sim/cpu_phase2a.fst`; the existing platform test continues to write
`build/sim/platform_foundation.fst`.

The CPU files are listed in the Quartus project so they are parsed as
synthesizable SystemVerilog. `cpu_core` is not instantiated in `de1_soc_top` in
Phase 2A, preserving the verified Phase 1 LED diagnostic bitstream unchanged.
