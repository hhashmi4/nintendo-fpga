# Phase 4A NES system bus and memory map

## Scope

Phase 4A turns the previously integrated CPU/PPU demonstration into an
explicit NES system-bus architecture. It separates address ownership, read
data arbitration, and internal CPU RAM from `nes_core`, while retaining the
verified CPU, PPU, scheduler, NMI path, and existing OAM DMA sequencer.

This phase does not add an APU, controller shift registers, a cartridge
mapper, a physical cartridge connector, or a developer UI. Instead, every one
of those future blocks now has a named, deterministic boundary.

## Baseline

The starting commit was `bf42b9a` on
`phase3/de1soc-vga-output`, synchronized exactly with its upstream (`0` ahead,
`0` behind) and with a clean working tree. The repository-local Python
environment was required because system Python did not contain pytest.

Before Phase 4A changes:

- all 618 Python tests passed;
- all Verilator lint targets passed;
- every retained CPU, PPU, Phase 3J integration/NMI, and Phase 3K VGA RTL
  simulation passed;
- the DE1-SoC NES/VGA project completed synthesis, fitter, assembler, and
  timing analysis;
- the board image used 3,003 ALMs, 3,498 combinational logic ALUTs, 590 memory
  ALUTs (4,088 total ALUTs), 1,180 registers, 206 M10K blocks, and 1,675,264
  block-memory bits;
- the worst reported setup slack was 1.054 ns and the worst reported hold
  slack was 0.163 ns.

The pre-existing Quartus warnings were unused diagnostic reduction signals, a
deliberately fixed-low `VGA_SYNC_N`, incomplete assignments for unused board
pins, Lite-edition LogicLock availability, automatic PLL compensation, and
two IRQ synchronizer filters optimized away because the board ties IRQ low.
There were no latch, multiple-driver, unconstrained-path, or negative-slack
warnings.

## Module boundaries

The integration hierarchy is deliberately small:

```text
cpu_core
   |
   v
nes_cpu_bus ----> nes_cpu_ram (one 2 KiB physical array)
   |  |  |  |  |  |
   |  |  |  |  |  +--> cartridge CPU interface
   |  |  |  |  +-----> controller placeholder
   |  |  |  +--------> existing OAM DMA trigger
   |  |  +-----------> future APU interface
   |  +--------------> existing PPU CPU-register port
   +-----------------> deterministic read-data mux
```

`nes_cpu_address_decoder` is pure combinational policy. `nes_cpu_bus` applies
that policy to accepted CPU cycles, produces peripheral strobes, and chooses
exactly one read-data source. `nes_cpu_ram` contains the only CPU RAM storage.
`nes_core` remains responsible for clock-enable scheduling, CPU/PPU assembly,
and arbitration with the retained DMA bus master.

Target encodings, shared by RTL through `nes_system_pkg`, are:

| Value | Target |
|---:|---|
| 0 | none/unmapped |
| 1 | internal RAM |
| 2 | PPU register |
| 3 | future APU |
| 4 | OAM DMA register |
| 5 | future controller ports |
| 6 | cartridge |

## CPU memory map

| CPU address | Owner | Normalization and Phase 4A behavior |
|---|---|---|
| `$0000-$07FF` | CPU RAM | Physical address `A[10:0]` |
| `$0800-$1FFF` | CPU RAM | Mirrors the same 2 KiB with `A[10:0]` |
| `$2000-$2007` | PPU | Existing register selected by `A[2:0]` |
| `$2008-$3FFF` | PPU | Mirrors the same eight PPU registers |
| `$4000-$4013` | future APU | Routed to the APU placeholder; stub data is supplied by the integrator |
| `$4014` | OAM DMA | Existing DMA trigger on writes; deterministic zero on reads |
| `$4015` | future APU | Routed to the APU placeholder |
| `$4016` | controller | Controller port 1 read and controller-strobe write boundary |
| `$4017` read | controller | Controller port 2 read boundary |
| `$4017` write | future APU | APU frame-counter write boundary |
| `$4018-$401F` | none | Deterministic zero, no peripheral strobe |
| `$4020-$FFFF` | cartridge | Full CPU address and explicit read/write strobes |

The `$4017` direction split is intentional NES behavior. It also preserves
one read-data owner: controller data can never contend with APU data during a
read.

## RAM and mirroring

The four apparent RAM ranges all reduce to `cpu_address[10:0]`. For example,
`$0000`, `$0800`, `$1000`, and `$1800` select physical byte zero; `$07FF`,
`$0FFF`, `$17FF`, and `$1FFF` select physical byte 2047. No mirror has a
separate array.

The RAM uses a registered read port so Quartus can infer one Cyclone V M10K
memory. CPU and DMA reads share that port because DMA stalls the CPU. RAM is
not cleared by system reset: its contents are unspecified until software
writes them, which avoids a large clear network and accurately defines the
SRAM initialization contract. Its control path, addresses, and visible bus
strobes are deterministic during reset.

## CPU-to-PPU communication

The bus canonicalizes all PPU aliases to `$2000 | cpu_address[2:0]`. Thus
`$2008` becomes `$2000` and `$3FFF` becomes `$2007`. The canonical transaction
then enters the existing `ppu_sprite_core` CPU port. The PPU remains the sole
owner of PPUCTRL, PPUMASK, PPUSTATUS, OAMADDR/OAMDATA, PPUSCROLL, PPUADDR, and
PPUDATA state.

During OAM DMA, the CPU is stalled and the retained DMA sequencer temporarily
owns this same PPU port. Source reads in the PPU range are canonicalized, and
destination writes use `$2004`. Normal CPU and DMA accesses therefore cannot
drive the PPU port together.

## Future interfaces

### Cartridge

The CPU cartridge boundary exports the full 16-bit address, 8-bit write data,
read enable, and write enable, and accepts 8-bit read data. The existing PPU
CHR address/read/write interface remains separate. A future mapper can own
both boundaries without any CPU or PPU modification. Phase 4A deliberately
does not assume NROM, bank sizes, PRG RAM placement, or physical pin timing.

### APU

The APU boundary exports the original CPU address, write data, and independent
read/write strobes, and accepts read data. The DE1-SoC Phase 4A top ties its
read data to zero. A later APU may implement `$4000-$4013`, `$4015`, and the
write side of `$4017` directly behind this interface.

### Controllers

The controller boundary exports a port selector, read strobe, `$4016` write
strobe, and write data, and accepts one read byte. The board top currently
ties the return value to zero. A later controller block can use the `$4016`
write to latch both physical ports and use the port selector for serial reads.

### OAM DMA

The already verified 513/514-cycle Phase 3J DMA engine remains in place. The
system bus now provides an explicit `$4014` select, write strobe, and page
byte. DMA is an internal bus master: it stalls CPU enables, shares the RAM
read port, can read the cartridge or PPU ranges, and writes OAM through the
PPU `$2004` port.

Phase 4D can move this sequencer into a standalone module without changing
the CPU decoder. That module should consume the existing `$4014` trigger,
request source reads through the system-bus master side, request OAM writes,
and return `cpu_stall`, active/phase, and event diagnostics. Phase 4D should
also decide how non-RAM DMA source pages interact with I/O open-bus behavior;
Phase 4A retains deterministic zero for unsupported APU/controller sources.

## Read-data arbitration

Only `nes_cpu_bus` drives `cpu_read_data`. The decoded target selects one of
RAM, PPU, APU, controller, or cartridge data. DMA and unmapped locations return
zero. Accepted-access outputs are one-hot-or-zero, and assertions reject
simultaneous reads and writes on any peripheral boundary. Reset forces the
visible target to `none`, suppresses every access strobe, and returns zero.

## Clocking and reset

The integration uses one 50 MHz fabric clock. `nes_enable` advances one PPU
cycle. A modulo-three scheduler emits one CPU slot after every three enabled
PPU cycles, preserving the exact logical `PPU, PPU, PPU+CPU` relationship.
The board-level fractional rate generator supplies `nes_enable` at the NTSC
average PPU rate. CPU, PPU, RAM, and DMA logic use clock enables rather than
derived clocks.

Synchronous system reset:

- returns the scheduler to phase zero and suppresses PPU and CPU enables;
- invokes the verified CPU seven-cycle reset-vector sequence after release;
- resets the PPU timing, register, NMI, rendering, and OAM control state;
- makes every bus/peripheral strobe inactive and returns deterministic zero
  for reset-time bus reads;
- clears DMA control/counters and leaves the sequencer idle;
- does not clear the CPU RAM array, as described above.

## Observation interface

All observation outputs are passive and have no path back into NES state.

CPU observation includes PC, A, X, Y, SP, status, current address, read data,
write data, bus-valid, read-state, and write-state. PPU observation includes
scanline, dot, frame parity/start/end, VBlank, sprite-zero hit, sprite
overflow, PPUCTRL, PPUMASK, NMI state/events, OAM events, and the final pixel
stream. System observation includes the selected target, normalized RAM and
PPU addresses, one access pulse per target, scheduler state, and detailed DMA
state/events.

## Future developer-video architecture

The developer display must be a peer of the NES image, not a layer that
depends on the PPU renderer working:

```text
NES PPU pixel stream ----+
                         +--> video mux --> DE1-SoC native VGA output
Debug renderer ----------+
    ^
    +--- passive CPU/PPU/system observation signals
```

The intended 640x480 layout integer-scales the NES 256x240 image by 2 to
512x480. The remaining 128 horizontal pixels may contain a diagnostic panel.
The video mux must also support a full-screen diagnostic mode, so CPU/bus
state remains visible if the PPU pixel path is broken. The debug renderer
should generate its own timing-safe pixels from observation snapshots and
must not read through, stall, or modify the NES bus.

VGA remains the development target. The internal NES pixel stream and debug
pixel stream should terminate at the video mux boundary; a later production
PCB can replace the VGA formatter with a native HDMI transmitter without
changing CPU, PPU, bus, or debug-renderer logic.

## Verification strategy

`verification/nes_bus.py` independently models ownership and sub-addresses.
Python tests enumerate all 65,536 addresses for reads and writes, separately
check RAM and PPU aliases, cover `$4014/$4016/$4017`, and cover cartridge
boundaries through `$FFFF`.

`generate_nes_phase4a_vectors.py` emits 131,072 independent reference rows.
`nes_phase4a_bus_tb.sv` compares every row against RTL, verifies one-owner
arbitration and read-data selection, performs writes and reads through every
RAM mirror, and checks reset-safe behavior. The retained Phase 3J program then
re-verifies CPU reset-vector fetches, PPU register programming, NMI, six DMA
transfers, mirrored RAM, cartridge reads, and final pixels through the new bus.

Run the complete qualification with:

```bash
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
scripts/build_de1_soc_nes_vga_quartus.sh
```

## Final qualification results

The Phase 4A qualification run completed with:

- 625 Python tests passed;
- every Verilator lint target passed with no emitted diagnostics;
- the 131,072-case exhaustive RTL decoder comparison passed, including
  mirrored-RAM transactions, reset behavior, and read-data arbitration;
- all retained CPU, PPU, Phase 3J integration/NMI, and Phase 3K VGA RTL
  simulations passed;
- Quartus Prime 23.1 Lite completed synthesis, fitter, assembler, timing
  analysis, and RBF conversion with zero errors and 12 warnings;
- the final image used 2,979 ALMs, 3,465 combinational logic ALUTs, 590 memory
  ALUTs (4,055 total ALUTs), 1,193 dedicated logic registers, 206 M10K
  blocks, 18,880 MLAB bits, and 1,675,264 total block-memory bits;
- timing was fully constrained, with a worst cross-corner setup slack of
  1.089 ns and worst cross-corner hold slack of 0.149 ns.

The warnings remain understood board/project conditions: unused diagnostic
reductions, one existing PPU connectivity hierarchy, fixed-low `VGA_SYNC_N`,
incomplete assignments for unused DE1-SoC pins, Lite-edition LogicLock
availability, automatic PLL compensation, and the two IRQ synchronizer SDC
filters optimized away because board IRQ is tied low. No new critical,
latch, multiple-driver, unconstrained-path, or negative-slack warning was
introduced.

## Phase 4B recommendation

Implement a replaceable cartridge subsystem beginning with iNES image
loading and mapper 0 (NROM), including PRG ROM, optional PRG RAM, CHR ROM/RAM,
mirroring metadata, reset-vector boot, and mapper-focused Python/RTL tests.
Keep the CPU and PPU on the Phase 4A cartridge boundaries, so later mappers
replace only the cartridge module.
