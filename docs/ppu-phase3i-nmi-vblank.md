# Phase 3I: PPU VBlank and NMI

## Purpose

After the PPU finishes the visible picture, it enters vertical blanking
(VBlank). Software normally uses this interval to update graphics state. The
PPU can notify the CPU by activating its non-maskable-interrupt condition when
VBlank begins.

```text
PPU timing
   |
   v
VBlank flag ----\
                 AND ----> NMI condition ----> NMI edge/event
PPUCTRL bit 7 ---/
```

Phase 3I implements the PPU side only. Phase 3J will connect this interface to
the already verified CPU and establish the final CPU/PPU sampling alignment.

## State ownership and timing

`ppu_registers` remains the single owner of the CPU-visible PPUSTATUS VBlank
latch. No second VBlank register was introduced.

- Scanline 241 dot 1 sets PPUSTATUS bit 7 unless an accepted boundary read
  suppresses that set.
- Pre-render scanline 261 dot 1 clears VBlank, sprite-zero hit, and sprite
  overflow.
- An accepted PPUSTATUS read returns the pre-edge status value, then clears
  only VBlank and resets `w`.
- PPUSTATUS reads do not clear sprite-zero hit or sprite overflow.

VBlank exists even when NMI is disabled. PPUCTRL bit 7 only controls whether
the VBlank latch participates in the NMI condition.

## NMI condition and outputs

The active-high logical condition is exactly:

```text
ppu_nmi_level = status_vblank && PPUCTRL[7]
```

The integrated PPU exposes three active-high signals:

- `ppu_nmi_level`: the persistent logical condition above;
- `ppu_nmi_event`: a one-fabric-clock qualified activation pulse;
- `ppu_nmi_suppressed`: a one-fabric-clock verification/debug pulse when an
  accepted boundary PPUSTATUS read cancels the ordinary activation.

There is still one 50 MHz fabric clock. NMI logic is synchronous state and
does not create a CPU clock, PPU clock, generated clock, or PLL.

The verified CPU NMI input is also active high. The CPU synchronizes that
level through two fabric-clock registers, detects its rising edge, and retains
a pending request independently of `cpu_enable`. Phase 3J should therefore
connect/adapt `ppu_nmi_level`; `ppu_nmi_event` is a clean diagnostic event and
may be useful to verify that adapter. The final scheduler must still prove the
precise CPU sampling outcome of short boundary pulses.

## Ordinary and dynamic behavior

With PPUCTRL bit 7 continuously set, the VBlank flag and NMI condition activate
from the 241:1 event. One ordinary NMI event qualifies after the modeled
one-tick suppression window. The level may remain high for the rest of VBlank,
but no additional event is emitted until it first becomes inactive.

With bit 7 clear, the VBlank flag still sets and clears normally, while the NMI
level and event remain inactive.

Writing PPUCTRL bit 7 from zero to one while VBlank is already set immediately
changes the condition from inactive to active and emits an event on that
accepting fabric edge. Rewriting one while already enabled does not retrigger.
Writing zero deactivates the condition; a later zero-to-one write during the
same uncleared VBlank emits another event. Software can therefore deliberately
create multiple NMI activations within one VBlank.

Reading PPUSTATUS while VBlank is set returns bit 7 as one and then clears the
latch. This deactivates the NMI level without altering either sprite status
flag.

## Boundary suppression model

CPU register reads use the repository's established accepted-access rule:
`cpu_enable && cpu_bus_valid` at the accepting fabric edge. Read data is the
pre-edge value. The implemented NTSC PPU-tick window is deliberately explicit:

| Read offset from 241:1 | Presented coordinate | Returned bit 7 | State after the boundary | Ordinary event |
|---:|---:|---:|---:|---:|
| -2 | 240:340 | 0 | VBlank sets | yes |
| -1 | 241:0 | 0 | set is suppressed | no |
| 0 | 241:1 | 0 | set is suppressed | no |
| +1 | 241:2 | 1 | flag is read and cleared | no |
| +2 | 241:3 | 1 | flag is read and cleared | already emitted |

A 241:0 read arms suppression of the following set. A coincident 241:1 read
has direct priority over setting the latch. At 241:2, the flag has become
visible, but the accepted read cancels the pending ordinary event. Without
that read, the event qualifies on the enabled 241:2 tick. This qualification
delay is the digital PPU-tick model that permits the requested one-tick-after
suppression; it is not a claim about transistor-level pulse width.

Reads two or more ticks away follow normal PPUSTATUS behavior. Random
`ppu_enable` stalls freeze the presented coordinate and pending ordinary event.
CPU accesses retain their independent `cpu_enable` contract, so a status read
accepted while stalled at 241:2 can still clear the flag and cancel the event.

## Same-edge control policy

All same-edge decisions use explicit predicted next state rather than
SystemVerilog assignment order:

- A PPUCTRL enable write accepted at 241:1 participates in the ordinary
  VBlank-created activation and its suppression window.
- A write accepted after an established VBlank creates an immediate event if
  it changes the condition from zero to one.
- Pre-render clearing wins over a same-edge enable write. PPUCTRL stores the
  new bit, but the cleared VBlank latch keeps the NMI condition inactive.
- PPUSTATUS reads win over a same-edge VBlank set.

Reset clears the VBlank latch, PPUCTRL, suppression history, pending activation,
and both event outputs. Releasing reset cannot create an NMI.

## Verification

`verification/ppu_nmi.py` is an independent transaction-level model of the
VBlank latch, PPUCTRL enable, condition transitions, event qualification,
boundary suppression, pre-render clearing, stalls, and reset. It describes
semantic next state rather than copying the RTL process layout.

Directed Python tests cover normal and disabled frames, immediate enable,
rewriting an already-enabled control, four disable/re-enable activations in one
VBlank, PPUSTATUS return/clear ordering, all five boundary offsets, stalled
qualification, a stalled status read, pre-render rearming, and reset. The
integrated randomized RTL/reference run uses seed `0x39120260` and covers:

- 1,021,100 fabric cycles;
- 893,420 enabled PPU ticks and 127,677 stalls;
- 10 complete frame boundaries;
- 8 visible VBlank-latch set transitions and 8 clears;
- 54 accepted PPUSTATUS reads and 63 accepted PPUCTRL writes;
- 9 NMI-condition activations;
- 8 qualified NMI events and 3 boundary suppressions;
- zero RTL/reference mismatches.

The stream includes continuous-enable frames, disabled frames, multiple
enable toggles in one VBlank, every boundary-read offset, a same-edge 241:1
enable, a same-edge pre-render enable, ordinary mirrored register traffic,
random PPU stalls, and independent sprite-zero/overflow activity.

The complete retained suite also passes the exact Phase 3E background frame,
Phase 3G sprite frame, and Phase 3H final stream of 61,440 pixels with 37,583
background, 731 sprite, and 23,126 universal-background winners. NMI/status
logic does not alter pixel generation. CPU Phase 2A-2K, exhaustive ALU and
addressing, whole-project lint, and board-image builds remain retained.

## Synthesis

The integrated `ppu_sprite_core` fits Cyclone V `5CSEMA5F31C6` with one 50 MHz
global fabric clock:

| Resource/timing | Phase 3H | Phase 3I |
|---|---:|---:|
| ALMs | 2,297 | 2,306 / 32,070 |
| logic ALUTs | 1,873 | 1,881 |
| routing-only ALUTs | 65 | 67 |
| memory ALUTs | 590 | 590 |
| registers | 796 | 800 |
| MLAB RAM bits | 18,880 | 18,880 |
| MLABs | 74 | 74 |
| M10K | 0 | 0 |
| DSP | 0 | 0 |
| PLL | 0 | 0 |
| worst setup slack | +3.740 ns | +3.781 ns |
| worst hold slack | +0.158 ns | +0.158 ns |
| setup/hold TNS | 0 / 0 ns | 0 / 0 ns |
| worst minimum pulse-width slack | +8.625 ns | +8.626 ns |

The four additional production registers are the pre-boundary suppression bit,
pending activation bit, event pulse, and suppression pulse. All analyzed timing
corners have positive setup, hold, and minimum-pulse-width slack.

## Accuracy boundary and deferred work

The race window is a deterministic PPU-tick model based on the documented
VBlank/status interaction and one-PPU-clock empirical tests. Real hardware
suppression depends on the duration of the active-low physical NMI pulse and
the CPU's sampling phase. Phase 3I exposes both logical level and qualified
event but does not claim arbitrary CPU/PPU-phase or transistor-level accuracy.

Phase 3J still must connect the PPU and CPU, establish the final 3:1 enable
scheduler, and verify CPU-side NMI sampling alignment. OAM DMA `$4014`, APU,
mapper banking, cartridge loading/parsing, VGA, HDMI, framebuffer, analog
video, and transistor-level PPU bus behavior remain deferred. Phase 2K
physical LED/HEX confirmation remains outstanding and is not hardware-verified
by this phase.

Empirical behavior references: [NESdev PPU programmer reference](https://www.nesdev.org/wiki/PPU_programmer_reference)
and blargg's `ppu_vbl_nmi` tests, including the
[NMI control source](https://github.com/kabukki/wasm-nes/blob/main/backend/tests/roms/ppu/ppu_vbl_nmi/source/04-nmi_control.s).
