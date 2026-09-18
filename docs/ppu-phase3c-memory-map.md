# Phase 3C: PPU memory map

## Objective

Phase 3C implements the complete logical 14-bit PPU address map behind the
Phase 3B PPUDATA interface. It adds cartridge-routed CHR accesses, 2 KiB of
internal nametable RAM (CIRAM), cartridge-selectable nametable mirroring, and
32 bytes of internal palette RAM. It does not add rendering fetch scheduling,
pixels, sprites, OAM, mapper banking, or video output.

## Architecture

`ppu_memory_core` composes the unchanged Phase 3A timing engine, the Phase 3B
register block, and the independently testable `ppu_memory` decoder/storage
block:

```text
CPU $2007 through ppu_registers
              |
              | address / read / write
              v
         $0000-$3FFF
              |
      +-------v--------+
      | PPU address    |
      | decoder        |
      +---+--------+---+
          |        |
     +----+        +----------------+
     |                              |
 $0000-$1FFF    $2000-$3EFF     $3F00-$3FFF
     |               |                |
     v               v                v
 CHR interface   NT normalization  Palette map
 to cartridge         |                |
                      v                v
                mirroring mapper   32-byte RAM
                      |
                      v
                 2 KiB CIRAM
```

There is one fabric `clk`. No CPU clock, PPU clock, PLL, or other generated
clock is introduced. Memory writes occur only on an accepted Phase 3B PPUDATA
transaction. The generic `ppu_memory` access port is not inherently CPU-only;
later rendering logic can drive the same address/data/request boundary once
arbitration is designed. Phase 3C intentionally does not add that arbitration.

## Address map and normalization

Only the low 14 address bits participate in decoding:

| Address range | Region | Phase 3C behavior |
| --- | --- | --- |
| `$0000-$1FFF` | Pattern/CHR | Routed to the external cartridge CHR port |
| `$2000-$2FFF` | Nametable | Four logical 1 KiB pages translated into CIRAM |
| `$3000-$3EFF` | Nametable mirror | Normalized to `$2000-$2EFF` first |
| `$3F00-$3FFF` | Palette | Repeated 32-byte internal palette map |

Every one of the 16,384 addresses is assigned exactly one region. The
`$3000-$3EFF` normalization subtracts `$1000` before logical-page and offset
extraction. Thus `$3000->$2000`, `$33FF->$23FF`, `$3800->$2800`, and
`$3EFF->$2EFF`; `$3F00` starts palette space and is not a nametable alias.

For a normalized nametable address, bits 11:10 select logical NT0-NT3 and bits
9:0 select one of 1,024 bytes. The 960 name bytes and 64 attribute bytes are
stored uniformly; attribute interpretation belongs to the later renderer.

## CHR cartridge interface

Pattern-space reads return external `chr_read_data`. Accepted reads and writes
produce `chr_read` or `chr_write`, `chr_addr[12:0]`, and `chr_write_data`.
Production RTL contains no CHR ROM or RAM and makes no ROM-only assumption, so
a later cartridge may implement CHR ROM, CHR RAM, or mapper-controlled banks.
The verification testbench supplies a separate 8 KiB fake CHR-RAM device only
to prove reads, writes, address/data routing, and strobes.

## Nametable CIRAM and mirroring

The logical four-page nametable space maps to two physical 1 KiB CIRAM pages.
The two-bit `mirroring_mode` input is intended to come from later cartridge
logic and may change dynamically:

| Mode | NT0 | NT1 | NT2 | NT3 | Pattern |
| --- | ---: | ---: | ---: | ---: | --- |
| Vertical | 0 | 1 | 0 | 1 | A B / A B |
| Horizontal | 0 | 0 | 1 | 1 | A A / B B |
| Single-screen lower | 0 | 0 | 0 | 0 | A A / A A |
| Single-screen upper | 1 | 1 | 1 | 1 | B B / B B |

Changing the mode only changes address translation. It does not clear or copy
CIRAM, so existing bytes immediately appear through the newly selected aliases.
Reads and writes through `$3000-$3EFF` pass through the same translator and
therefore remain coherent with their `$2000-$2EFF` counterparts.

True four-screen mapping is not claimed. It requires four distinct 1 KiB pages,
normally including cartridge-provided nametable RAM, while this module owns
only ordinary 2 KiB CIRAM. The decoder and logical-page boundary are localized
inside `ppu_memory`; a later mapper phase can widen the typed mirroring control
and route a four-screen selection to cartridge nametable storage without
changing Phase 3B register semantics. No unsupported mode is silently aliased.

## Palette RAM

Palette RAM stores deterministic byte-wide values in 32 physical entries. The
six-bit color interpretation is deferred to video-color conversion; CPU writes
and reads preserve all eight bits in this digital model.

The canonical index first takes `address[4:0]`, implementing repetition every
`$20` bytes through `$3FFF`. It then clears index bit 4 for entries whose low
two bits are zero. This implements all repetitions of the special aliases:

```text
$3F10 -> $3F00
$3F14 -> $3F04
$3F18 -> $3F08
$3F1C -> $3F0C
```

For example, `$3F20`, `$3F30`, `$3F00`, and `$3F10` ultimately select the same
universal-background entry. One normalization function owns both read and
write mapping.

## PPUDATA integration

The Phase 3B register block continues to expose `v[13:0]` as the memory address
and to increment 15-bit `v` exactly once per accepted `$2007` access.

- Below `$3F00`, a read returns the old PPUDATA buffer, refills it from the
  decoded CHR or CIRAM byte, and increments by the PPUCTRL-selected 1 or 32.
- In `$3F00-$3FFF`, a read returns the palette byte immediately, refills the
  internal buffer from `address-$1000` in nametable space, and increments once.
- A write selects exactly one destination: CHR, CIRAM, or palette RAM. It emits
  one write and increments once by 1 or 32.
- `cpu_enable=0`, invalid bus cycles, non-PPU CPU addresses, and reads never
  emit a memory write.

Palette data and its nametable-side refill are available simultaneously because
the palette array and CIRAM are separate. The auxiliary buffer-read result is
defined only for a palette primary access. That condition does not otherwise
consume CIRAM, allowing one physical CIRAM read port to serve normal nametable
reads and palette refills without duplicating the 2 KiB array.

## Storage implementation and reset

CIRAM and palette contents are deliberately not reset. NES software cannot
rely on their power-up contents, and clearing every byte would add a large
reset network and inhibit RAM inference. Testbenches initialize their own
storage instances to zero for reproducibility.

Both arrays use asynchronous reads to preserve the already verified Phase 3B
zero-latency PPUDATA contract. Cyclone V synthesis maps them to MLAB LUT RAM,
using 64 MLABs for the 16,384-bit CIRAM and one MLAB for the 256-bit palette.
The `no_rw_check` inference setting declares same-address output during the
active write cycle irrelevant: CPU writes do not consume read data on that
edge, and subsequent reads observe the committed byte. This avoided 16,640
flip-flops without changing any sampled CPU behavior. A future high-throughput
renderer may choose a pipelined M10K-oriented boundary, but that architectural
change is not needed for Phase 3C correctness.

## Verification

`verification/ppu_memory.py` is a behavioral model with separately expressed
region classification, `$3000` normalization, logical/physical page mapping,
palette canonicalization, and storage. Its fake CHR bytearray models only the
test cartridge.

The new Python suite adds 32 tests and covers:

- all 16,384 addresses in all four modes;
- every required boundary and the complete `$3000-$3EFF` range;
- all 256 palette-region addresses and both directions of every special alias;
- storage aliases and dynamic changes for all four mirroring modes;
- 100,000 deterministic semantic memory operations with seed `0x3C0FFEE1`.

The standalone RTL/reference trace checks 165,604 cycles: 65,536 exhaustive
address/mode cases, 66 directed storage/alias operations, and 100,000 random
accesses with seed `0x3C5EED01`. The random split is 49,906 reads, 50,094
writes, 50,168 CHR, 48,226 nametable, and 1,606 palette accesses. All mismatches
are zero.

The combined CPU/register/memory trace checks another 120,312 cycles. Its
120,000-cycle randomized section uses seed `0x3C200701` and contains 59,741
accepted CPU transactions, 29,822 PPUDATA accesses (14,853 reads and 14,969
writes), 37,683 active selected stalls, and 81,457 independent PPU ticks. The
PPUDATA region split is 15,818 CHR, 13,569 nametable, and 435 palette accesses;
all four mirroring modes are exercised. Another 100 directed PPUDATA accesses
cover boundaries, buffer sequencing, increments, wrap, aliases, and stalls.

Testbench assertions check ranges, one-hot write routing, read/write direction,
stall suppression, single address increments, state stability, and every
Python-model state/output comparison. Verilator whole-project lint is warning
free for the PPU hierarchy. The retained Phase 3B 208,249-cycle register trace
and its timing/status integration remain unchanged and pass.

## Synthesis

The integrated `ppu_timing + ppu_registers + ppu_memory` hierarchy was fitted
for the Cyclone V `5CSEMA5F31C6` using one 50 MHz fabric clock:

- 1,133 ALMs of 32,070 (4%)
- 438 combinational logic ALUTs plus 16 routing-only ALUTs
- 520 memory ALUTs
- 97 registers
- 16,640 MLAB memory bits in 65 MLABs
- 0 M10Ks / 0 block-memory bits
- 0 DSP blocks
- 0 PLLs
- worst setup slack `+9.300 ns`, setup TNS `0`
- worst hold slack `+0.172 ns`, hold TNS `0`
- worst minimum-pulse-width slack `+8.625 ns`

Quartus inferred exactly two simple dual-port `altdpram` instances: the 2 KiB
CIRAM and 32-byte palette. The fake CHR test memory is not in the synthesis
hierarchy.

## Limitations and next phase

Phase 3C does not implement background fetch scheduling, tile or attribute
shifters, rendered pixels, rendering-time scroll increments/transfers, sprites,
sprite evaluation/fetch, OAM RAM, OAM DMA, mapper banking, true four-screen
cartridge RAM, a cartridge loader or iNES parser, video output, framebuffer,
APU, NMI edge/race behavior, final CPU/PPU scheduling, or memory arbitration
with a renderer.

The recommended next phase is Phase 3D: implement rendering-time scroll address
operations around the verified timing, register, and memory foundations without
yet adding the background pixel pipeline.
