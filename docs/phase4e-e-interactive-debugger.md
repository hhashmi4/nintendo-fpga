# Phase 4E-E interactive Developer debugger

## Status

The debugger is implemented and the release gates passed: complete retained
regression, directed and mixed playable debugger tests, strengthened RUN/hash
and exact-overrun checks, full lint, and the complete Quartus flow with positive
setup/hold slack. Baseline and independent timing-hardening results below were
measured before integration. No physical FPGA programming or debugger hardware
validation is claimed.

## Repository and PR #24

The initial working tree was clean and synchronized with
`origin/phase4/devmode-interactive-debugger` at
`2788d63a8d6f5877b0c02a7cc2d5b7bd4860e380`. A fresh `git fetch origin`
confirmed current `origin/main` at
`4d0d087ef235d53253498d7d14f1f81ed4dab3b3`, the merge of PR #24.
`git merge-base --is-ancestor` succeeded for current main and both PPUDATA
commits, `2750371` and `67276d9`. No rebase was necessary because this branch
already contains current main.

`sim/nes_phase3j_tb.sv` reads palette data through real CPU `$2007` accesses,
stores the result in internal CPU RAM location `$0006`, and asserts that it
equals `$30`. The test uses the corrected `internal_cpu_ram.memory` hierarchy.
That assertion executed successfully in the fresh baseline regression.

## Executed baseline

Commands, with the existing development environment placed first on PATH:

```sh
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
PATH="$PWD/.venv/bin:$PATH" scripts/build_de1_soc_nes_vga_quartus.sh
```

Both commands returned exit status 0. Their complete logs are archived under
`build/phase4ee/baseline/`, alongside copies of the actual Quartus reports,
SOF, RBF, and detailed four-corner timing reports. Generated files remain
ignored by Git.

- Python: 1,184 passed.
- Full Verilator lint: passed.
- All retained CPU, ALU/addressing, PPU, scroll/background/sprite/mixer,
  interrupt/reset, DMA/NMI, controller, cartridge, and system-bus tests: passed.
- CPU ALU: 591,876 vectors; addressing: 1,508,186 vectors.
- Bus decode: 131,072 exhaustive read/write address vectors.
- PR #24 CPU PPUDATA readback: passed within Phase 3J integration.
- Phase 4A through Phase 4E-D and VGA tests: passed.
- Five Developer Mode pages: 1,536,000 pixels, zero mismatches.
- Normal-mode title, post-Start, A, B, Select, Left, Right, Up, Down hashes:
  all matched their existing reference values.
- Playable long run: 300 frames, 297 NMI events/handlers, 297 DMA completions,
  76,032 DMA reads and writes, 297 controller polls, 2,376 `$4016` reads,
  300 source snapshots and 300 destination updates.
- Real playable-ROM combined-frame comparison: 307,200 pixels,
  including 245,760 game pixels and 61,440 panel pixels, zero mismatches.
- Required retained FST files were checked for nonzero size by the regression.
- Quartus synthesis, fitter, assembler, timing, RBF conversion: passed.

### Normal-mode baseline hashes

| Fixture | RGB SHA-256 |
| --- | --- |
| title | `e7707b93cddfbdfa148dffb38523d03013d2ff9a717981a416cb00078db05ae2` |
| post-Start | `a49d66d2e3a6662c3b8113f701f70a4dc44e932e05d18100c270de626f951e52` |
| A | `ffe9da19bfc93c2c717dd5dfb046ebe8cb7330503556e4a12deb6d24d54f8939` |
| B | `35bba0c5f1de0b9159cccd77e4f7a045cd4e103950fad1c35bc17101a27b14ba` |
| Select / Left / Down | `35503fac899e59128a8bfb96f2c490c21ab5604cb1f6542b8d32033ebb73409c` |
| Right | `71d5e3a9e3268eddd86d5653fbb00ce16056fd73fbc6c1cf82b536cc2aacdb41` |
| Up | `83aaf2a6db7ad77d207c9cbad8293e4d2aa9f7e1b9379383aa989d2cd284d159` |

### Measured baseline resources and timing

| Metric | Fresh baseline |
| --- | ---: |
| ALMs | 4,702 |
| Logic ALUTs | 6,167 |
| Memory ALUTs | 590 |
| Registers | 3,944 |
| M10Ks | 230 |
| MLAB bits | 18,880 |
| Block memory bits | 1,871,872 |
| DSPs | 0 |
| PLLs | 1 |
| Worst setup slack | +0.073 ns |
| Worst hold slack | +0.151 ns |
| Setup / hold TNS | 0 / 0 ns |
| Unconstrained setup / hold paths | 0 / 0 |
| Snapshot source-bank setup slack | +0.816 ns |
| Pixel-domain setup slack | +1.147 ns |

The full Quartus compilation reported zero errors and 17 warnings: existing
unused status aggregation, tied-off inferred ROM write inputs, connectivity
and constant-output summaries, constant `VGA_SYNC_N`, subscription-only
LogicLock notice, incomplete I/O assignment summary, PLL compensation notice,
and unmatched `irq_meta`/`irq_sync` filters repeated in fitter/timing. The
standalone detailed timing audit completed with the two unmatched IRQ-filter
warnings. No artifact was programmed onto hardware.

### Baseline artifacts

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| SOF | 6,690,502 | `7d2d2de7fe90c89ddea92e3f89dc29d32e5dbd967bda9de12a7888bd472353db` |
| RBF | 7,007,204 | `61997f585c53848c32e0cd56f18600b24cf3679c27e905ddd9935928d5041946` |

## Timing investigation and independent hardening

The fresh worst setup path runs from
`nes|cpu|debug_addressing_mode[2]~DUPLICATE` to
`nes|ppu|sprite_renderer|pattern_high[1][0]`. It has 18 logic levels,
19.376 ns data delay, and -0.381 ns clock skew. Routing accounts for
12.096 ns (62%) of data delay. Despite its name, `debug_addressing_mode`
is functional CPU state, not an observation-only register.

The path passes through CPU bus-address generation, encoded bus-target
selection, PPU access acceptance, CIRAM address selection, and sprite data
capture. A CIRAM address net has fanout 512. The critical path does not end
in the debugger or panel. Snapshot observation shares part of this cone:
the slowest source snapshot path ends at `source_snapshot.dma.source_data[7]`
with +0.816 ns slack. This demonstrates shared logic, not a quantified claim
that observation loading causes the worst path.

The experiment in `rtl/system/nes_cpu_bus.sv` decodes PPU access strobes
directly from `cpu_address[15:13] == 3'b001`, which is exactly `$2000-$3FFF`.
This removes the dependency of those strobes on the encoded diagnostic target
and fine-grained `$40xx` decode. It adds no pipeline register, bus transaction,
or cycle. Read-data selection, mirrored addresses, and all other peripheral
strobes retain their existing logic. The existing exhaustive bus test checks
both directions for every address and passed with this change. The complete
retained regression returned exit status 0, including all 1,184 Python tests,
full lint, CPU/PPU/DMA/NMI tests, PPUDATA readback, normal frame hashes,
five-page pixels, 300-frame long run, and real multi-page VGA integration.
The long-run counts and combined-frame pixel hash match baseline exactly.
A fresh complete Quartus flow and four-corner
timing audit passed with the following results:

| Metric | Baseline | Hardening | Change |
| --- | ---: | ---: | ---: |
| ALMs | 4,702 | 4,724 | +22 |
| Logic ALUTs | 6,167 | 6,147 | -20 |
| Memory ALUTs | 590 | 590 | 0 |
| Registers | 3,944 | 3,919 | -25 |
| M10Ks | 230 | 230 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| DSPs / PLLs | 0 / 1 | 0 / 1 | 0 / 0 |
| Worst setup slack | +0.073 ns | +1.378 ns | +1.305 ns |
| Worst hold slack | +0.151 ns | +0.152 ns | +0.001 ns |
| Setup / hold TNS | 0 / 0 ns | 0 / 0 ns | 0 / 0 ns |
| Unconstrained setup / hold paths | 0 / 0 | 0 / 0 | 0 / 0 |
| Source snapshot setup slack | +0.816 ns | +3.296 ns | +2.480 ns |
| Pixel-domain setup slack | +1.147 ns | +1.378 ns | +0.231 ns |

The new worst path is `nes_vga_video:video|blue[0]` to `VGA_B[0]`.
The worst CLOCK_50 path is now `nes|cpu|debug_pc[0]` to
`nes|ppu|sprite_renderer|pattern_low[2][0]`, with +2.234 ns setup slack
and 17.219 ns data delay.
The full compilation again reported zero errors and 17 warnings of the same
categories. This hardening-only build predates debugger control; its resource and timing
results are not the final Phase 4E-E measurements. Hardening reports/artifacts are under
`build/phase4ee/hardening/`:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| SOF | 6,690,502 | `c9725d50dea379bf71c62a99ee3c416962131fc93f6de026dc11ad10eb3346dc` |
| RBF | 7,007,204 | `de3a5d2f1dc23d53a328d0110dee2fa0c226013d47d3d691509ffac41edf371f` |

Potential further work is to isolate high-fanout observation paths without
duplicating the entire snapshot bank. No timing exception should be added to
hide a CPU-to-PPU functional path.

## Execution architecture

```text
video-domain virtual request registers
  -> command/payload bank + request toggle
  -> three-stage event synchronizer
  -> NES debugger controller on CLOCK_50
  -> registered state authorizes existing nes_enable
  -> unchanged CPU / PPU / DMA / controller / cartridge execution

controller status -> existing coherent snapshot CDC -> frame-latched pages
command disposition -> held response bank + ACK toggle -> virtual readback
```

`nes_debugger` is separate from `cpu_core`. `nes_core` exposes its existing
CPU execution-state observation; the CPU datapath and its execution state
machine are unchanged. The only functional execution connection is
`nes_enable = nes_ppu_ce && debugger_authorized` at the board integration.
Neither CLOCK_50 nor the VGA PLL clock is gated, multiplexed, or replaced.
The NTSC rate generator continues running. The CPU/PPU three-phase scheduler
holds its phase whenever NES authorization is off.

RUNNING is transparent: no additional CPU/PPU bus cycle, stall, pipeline stage,
or different CPU execution path exists. The bus-decode hardening above is
separate from debugger control. Cartridge read precharge and interrupt
synchronizers retain their existing fabric-clock behavior while paused.

## State machine and reset

| State code | State | Authorization | Completion |
| --- | --- | --- | --- |
| 0 | RUNNING | enabled | PAUSE token requests safe suspension |
| 1 | PAUSE_REQUESTED | enabled | safe instruction/DMA boundary |
| 2 | PAUSED | disabled | accepted RUN or step token |
| 3 | INSTRUCTION_STEP | enabled | one opcode completes, then DMA drains |
| 4 | FRAME_STEP | enabled | next canonical frame event, then safe completion |

KEY0 and existing reset synchronizers retain their meanings. Shared reset
restores RUNNING, clears counters, last command/result, sequence, and step PCs,
and resets both sides of the command mailbox. A source valid level held high
through reset cannot produce a token until it first returns low.

## Safe pause and scheduler relationship

The controller changes to PAUSED only when DMA is inactive, the CPU is at its
FETCH boundary (or its existing terminal TRAP state), and `cpu_enable` is false
on that edge. Thus it cannot suppress a bus transaction already being accepted
on that edge. The last instruction or interrupt-entry cycle finishes first;
active DMA finishes all its source reads and OAM writes. The scheduler has
non-CPU fabric edges between CPU slots even in the accelerated logical test.

The PPU may consume the PPU tick on the state-transition edge; PAUSED takes
effect immediately after it, and no following NES tick is authorized. The
snapshot therefore reports the actual resulting frozen scanline, dot, CPU
state, and scheduler boundary. RUN resumes from the held scheduler phase on
the next available normal rate-generator enable. VGA, the framebuffer reader,
Developer Mode rendering, page navigation, controller input synchronization,
and command transport continue throughout the pause. CPU polling of controllers
and all NES bus side effects stop.

The controller observes FETCH boundaries; it does not force PC, alter stack
state, or synthesize instruction retirement. Existing CPU terminal-trap
behavior is not replaced by a debugger instruction implementation.

## Framebuffer handoff during pause/resume

The first mixed run exposed a real integration fault: pause/resume changes the
relative NES/VGA frame phase. A second complete NES image can then finish while
the preceding completed bank still awaits a VGA frame-end acknowledgement.
The retained framebuffer treated that condition as a sequence error, relying
on its previous continuously-running phase relationship.

The existing third bank now retains that completed image until the pending
handoff is acknowledged, then publishes it through the same CDC protocol.
Capture starts while that bank is waiting are skipped; CPU/PPU/DMA progression
is never delayed. A skipped capture loses a display sample only, never NES
execution or a partially written displayed frame. Normal capture behavior is
unchanged when the handoff is available. No extra RAM is allocated. Reset clears
the one new `completed_waiting` flag. Already completed frames can finish their
VGA handoffs after NES pause; scanout then holds the last complete image. This
is display pipeline latency, not continued game execution.

A directed asynchronous-clock regression withholds VGA handoffs for two full
source captures plus a third skipped frame, then verifies both retained frames,
all 61,440 pixels of the second, and normal capture recovery. The mixed playable
run checks the real pause-induced phase shifts with all framebuffer assertions.

## Instruction stepping, DMA, and NMI

An accepted STEP-I token records PC-before, clears its instruction-started
marker, and authorizes normal scheduling. The controller distinguishes a real
opcode fetch from interrupt entry by observing the existing FETCH transition.
FETCH to INTERRUPT_DUMMY is NMI/IRQ entry and does not consume the instruction
token. Returning to FETCH after one fetched opcode and any resulting DMA
increments the instruction-step counter, records PC-after, and pauses.

BRK is an instruction: its complete stack/vector sequence belongs to that
one token. RTI, JSR, RTS, branches, jumps, and stack operations use the existing
CPU implementation. A store to `$4014` completes its entire 256-read/256-write,
513/514-slot DMA before the token completes. No CPU fetch can bypass an active
DMA stall.

NMI pending before the step is serviced normally, followed by exactly one
handler instruction. A new NMI during the stepped instruction remains pending
at its completion; it is serviced on the next step or RUN. An NMI arriving
immediately after completion can latch in the existing synchronizer/pending
logic while architectural progression is paused. The frozen PPU cannot create
an unbounded stream of new VBlank events. Interrupt entry is never suspended
partway through its stack/vector sequence.

## Approved frame-step contract

The user explicitly approved: cross the next canonical frame boundary, then
finish the in-flight CPU instruction/interrupt entry and active DMA before
pausing, preserving normal CPU/PPU/DMA timing.

The event is the existing enabled PPU `frame_start`: scanline 0 / dot 0,
identical to the source snapshot frame definition. STEP-F starts from the
current paused coordinate and latches the next such event. If dot 0 is already
present but has not yet been consumed, its next enabled consumption is the
next event. An initial step from an arbitrary mid-frame pause can therefore
be shorter than a full frame-length interval; every accepted token crosses
exactly one source-frame event. Consecutive steps advance successive source
frames, with instruction/DMA completion allowed after each event.

After that event, normal scheduling continues until the safe boundary above.
If a CPU cycle is accepted on the event edge, its operation is in flight and
must finish. No early CPU quiescence, special DMA shortcut, or PPU-only drain
changes the relative NES timing. `frame_overrun` counts enabled PPU ticks after
the canonical event through effective pause; the event tick itself is excluded.
The pause snapshot records the actual stop coordinate and PC. Tests assert
one source event per token and an overrun below 4,000 PPU ticks for the directed
and playable workloads. This is a tested workload bound, not a new universal
NES timing constant.

## Command tokens, CDC, and acknowledgement

| Command | Encoding |
| --- | ---: |
| RUN | 0 |
| PAUSE | 1 |
| STEP_INSTRUCTION | 2 |
| STEP_FRAME | 3 |

`nes_debug_command_cdc` has one outstanding request. The producer supplies
`source_command[2:0]` and `source_valid`; acceptance occurs on a source-clock
edge with `source_valid && source_ready`. The command and a generated 16-bit
sequence number are held stable in a bank while a request toggle crosses
three destination synchronizer stages. Sequence numbers begin at 1 and wrap
modulo 65,536. A held valid level cannot repeat a command: it must return low
to rearm. The source must respect ready and keep an unaccepted request stable.

The consumer holds `destination_valid` until it presents `destination_done`,
state, and result. A stable response bank and three source synchronizer stages
return one `source_ack` pulse with sequence, state, and result. The ACK reports
command disposition, not completion of an instruction/frame step. Completion
is observed through state PAUSED and the incremented step counter/snapshot.

Results are 0 accepted, 1 wrong state, 2 busy, and 3 invalid command. Invalid
encodings 4–7 are rejected. Step tokens in RUNNING are rejected. All valid
commands received during PAUSE_REQUESTED or a step are explicitly rejected
as busy, without queuing or cancelling the operation. Repeated RUN in RUNNING
and PAUSE in PAUSED are acknowledged no-ops. The last-command field changes
only for accepted commands; sequence/result describe the last disposition,
including rejections. The consumer de-duplicates held destination valid.

A command received just after pause waits until the coherent pause snapshot
has been accepted and transferred before it can resume or step. This prevents
an immediate next token from erasing the before-step observation. Independent
unilateral reset of one mailbox domain is not supported: use the shared board
reset, abort the outstanding request, rearm, and retry.

## Snapshot, pages, and paused health

The existing source, received, and frame-visible snapshot banks are extended
in place. There is no duplicate snapshot pipeline or new RAM.

| Added debugger field | Bits |
| --- | ---: |
| state | 3 |
| last accepted command | 3 |
| disposition sequence | 16 |
| result | 2 |
| completed instruction steps | 16 |
| completed frame steps | 16 |
| pause boundary reason | 3 |
| PC before / after step | 16 / 16 |
| frame overrun in PPU ticks | 16 |
| **Added / old / new width** | **107 / 711 / 818** |

Running, pause-pending, paused, instruction-busy, and frame-busy flags are
unambiguously derived from state codes; no redundant flags are stored.
Boundary reasons are 0 none/in-progress, 1 PAUSE, 2 instruction completion,
and 3 frame completion. Step counters wrap modulo 65,536.

The three existing banks add 321 storage bits before implementation-specific
optimization. The controller, mailbox, heartbeat, and a 24-bit source-domain
status readback add separate lightweight control storage. Final fitted totals
are reported below, rather than inferred from RTL declarations.

A retried manual-capture request records each effective pause and status change.
It waits through a busy snapshot mailbox. While PAUSED, a source heartbeat
requests a coherent capture every 524,288 CLOCK_50 cycles (10.48576 ms). It
advances snapshot ID but does not advance source-frame, CPU-slot, PPU-cycle,
NMI, DMA, or controller-poll counters. The existing four-VGA-frame stale
threshold is unchanged. Thus an intentional pause remains healthy while a
broken snapshot commit path still becomes STALE. No blanket PAUSED exemption
masks a broken CDC link.

All five pages show compact RUN / WAIT / PAUSE / STEP-I / STEP-F beside the
health line. CPU/BUS and SYSTEM share a compact detail block showing numeric
state/command/result, sequence, instruction/frame counts, PC-before/after,
overrun, and boundary reason. The same font and character layout helpers are
used. The full-screen legacy view is retained. The game remains 512x480, the
panel 128x480, x=511 is game, x=512 is panel, and the literal normal-mode bypass
is unchanged. Snapshots and selected pages still commit only at VGA frame start.

## Virtual controls and future JTAG binding

No physical switch or key was repurposed. SW0 is test pattern, SW1 framebuffer
capture freeze, SW2–SW9 Controller 1, and KEY0 active-low reset.

The retained virtual producer in `de1_soc_nes_vga_top` uses pixel_clk:
`debugger_request_valid`, `debugger_request_command[2:0]`, ready/busy, ACK,
ACK sequence/state/result. Simulations drive these abstract registers. A
retained 24-bit `debugger_command_readback` samples
`{ready, busy, ack, sequence[15:0], state[2:0], result[1:0]}`; it prevents the
unbound ACK path from being optimized away. Developer Mode and page control
retain their separate video-domain virtual registers.

No Intel virtual-JTAG IP or physical JTAG debugger session is claimed. A future
binding can replace the virtual producer with a TCK-domain mailbox producer:
Update-DR captures command and raises source valid until accepted; it then
lowers valid to rearm. Capture-DR returns ready/busy and the last ACK sequence,
result, and state. Connect the CDC source clock/reset to that producer and keep
its destination on CLOCK_50. Reset the producer and destination coherently.
For Developer Mode enable/page selection, use a separate held-data acknowledged
transfer into pixel_clk; the existing page selector applies the choice at VGA
frame start. Do not route an unsynchronized TCK pulse to the scheduler or page
selector. Add explicit bundled-data timing constraints for the chosen TCK
implementation when integrating that IP.

## Verification design and measured directed results

`verification/debugger.py` is an independent architectural event model. It
uses completed-instruction and safe-boundary events, not RTL CPU-state numbers.
Its tests cover all eight command encodings in all five states, reset, no-op
RUN/PAUSE, safe pause/resume, busy rejection, repeated instruction/frame tokens,
interrupt-entry versus instruction retirement, DMA drain, overrun, held-valid
rearming, and sequence wrap. The current Python suite passes 1,228 tests.

`nes_debug_command_cdc_tb` uses asynchronous 14 ns / 22 ns clocks, varied
consumer delay, changing external payload/response signals after capture,
held valid, and shared reset while a request is outstanding. It verifies 49
acknowledged tokens without duplication and sequence restart after reset.

`nes_debugger_system_tb` drives the existing complete `nes_core` with a
project-owned deterministic ROM. It individually checks A, X, Y, SP, PC,
status flags, RAM, and stack results for loads/transfers/ADC/stores/increment/
decrement, PHA/PLA, taken and not-taken branches, JSR/RTS, JMP, BRK/RTI, and
STA `$4014`. It counts real opcode fetches, excluding interrupt-entry cycles,
and requires exactly one per instruction token. It checks frozen registers,
coordinates, and DMA events between tokens. Directed NMI is injected at the
CPU NMI input (not by modifying CPU architectural state), exercising the real
synchronizer, stack/vector entry, and handler code.

The strengthened directed run recorded 28 deterministic/NMI instruction
steps, three NMI entries, and one explicitly stepped DMA. Separate pause tests
cover before, during, and near the last byte of DMA. Frame tests use actual
PPU frame boundaries, including a continuous-DMA ROM loop: four frame steps
all required nonzero post-boundary DMA completion, with 1,450 PPU ticks on the
last one. Three CPU-only frame steps also produced one nonzero instruction
completion overrun. Every completed DMA checks 256 reads, 256 writes, all OAM bytes for
the stepped fixture, and the parity-dependent 513/514 CPU slots.

Representative individually asserted deterministic results (PC is after step):

| Operation | PC | Architectural result |
| --- | --- | --- |
| LDA #$10 / TAX / LDY #3 | $8002 / $8003 / $8005 | A=$10, X=$10, Y=3 |
| ADC #5 / STA $10 | $8007 / $8009 | A=$15, RAM[$10]=$15, P=$24 |
| PHA / LDA #0 / PLA | $800C / $800E / $800F | SP=$FC/$FC/$FD; P=$26 for zero load |
| BNE taken / BEQ not taken | $8013 / $8015 | correct distinct control-flow boundaries |
| JSR $8030 / INY / RTS | $8030 / $8031 / $8018 | SP=$FB then $FD; stacked return=$8017; Y=4 |
| JMP $8020 | $8020 | exact jump destination |
| STA $4014 | $8025 | all 256 patterned OAM bytes transferred before pause |
| BRK / RTI | $9100 / $8027 | full stack/vector entry; return=$8027, stacked P=$34 |
| NMI then INC $11 | $9002 | one handler opcode per token, three entries total, RAM[$11]=3 |

`nes_debugger_playable_tb` uses the production playable cartridge and complete
board/VGA integration with asynchronous command transfer. It tests ten paused
VGA/page frames, coherent pause snapshots, instruction steps, frame steps,
NMI-boundary and interrupt-entry pause requests, near-completion DMA pause,
shared KEY0 reset, and a mixed run/pause/step scenario repeated over more than
100 source frames. It compares a complete paused game/panel image against the
independent Python renderer and retained framebuffer contents. An injected
snapshot-commit interruption must become STALE while paused and recover after
commits resume. FST traces are retained with trace depth and array size limited by the
runner; assertions remain enabled throughout the mixed long run.

Controller testing changes Right while paused. Exactly one frame token polls
`$4016` once and moves game RAM X from 120 to 122. The ROM normally DMAs the
previous OAM shadow before publishing its main-loop input token, so this new
state is displayed only after subsequent frame/DMA pipeline progression. Two
no-input frame steps flush that unchanged pipeline: RAM stays at 122 and the
first opaque sprite pixel moves from 121 to 123. No forced framebuffer update,
extra controller poll while paused, or altered ROM/DMA ordering hides this
latency.

The complete `scripts/test.sh` regression returned exit status 0. Its final
log is `build/phase4ee/final/regression.log`; a fresh post-integration full lint
also returned 0 in `build/phase4ee/final/lint.log`. All retained Phase 2 CPU,
ALU/addressing, Phase 3 PPU/PPUDATA/NMI/VGA, Phase 4A–4E-D tests and all new
Phase 4E-E tests passed, with no waived test or Verilator warning. Python:
1,228 passed (44 new debugger reference tests).

The final mixed run measured:

| Measurement | Result |
| --- | ---: |
| Source frames | 132 |
| Commands / acknowledgements | 187 / 187 |
| Completed instruction / frame steps | 71 / 41 |
| NMI events / interrupt entries | 129 / 129 |
| DMA completions / controller polls | 129 / 129 |
| Page changes / coherent snapshot updates | 20 / 141 |
| Completed framebuffer images deferred safely | 9 |

All 16 mixed iterations, closing pause checks, and KEY0 reset checks passed.
Assertions verified no extra/missing opcode per instruction token, exactly one
source-frame event per frame token, complete DMA reads/writes, no lost/duplicate
NMI, live scanout, no framebuffer fault, and fresh coherent snapshots. The nine
deferred images demonstrate that the actual mixed workload exercised the
framebuffer fix, in addition to its independent delayed-handoff test.

The paused frame comparison checked 307,200 pixels with zero mismatches:
RGB SHA-256 `39886e3a73dfb6c037cf2cd64bcc3c067e1d8059fdc886761a6490c4d27b7e3d`.
The PPM is 921,615 bytes with SHA-256
`25fa7bf21e757e176aa2a8937e0cfda346122bb94fdb90daf29aae64e7648ad8`.
The retained live playable panel comparison also passed all 307,200 pixels.
All five page comparisons passed 1,536,000 pixels, using all five debugger
states and nonzero command/counter/PC/overrun fixtures on the detail pages.
The full-screen legacy renderer and normal compositor bypass passed too.

The retained 300-frame run reproduced the baseline counts: 297 NMI handlers,
297 complete DMAs, 76,032 reads/writes, 297 controller polls, 2,376 `$4016`
reads, and 300 snapshots/updates. All nine normal frame hashes match the table
above. The final hash bench additionally instantiates the real debugger in
RUNNING and uses its scheduler authorization, with no command tokens and an
assertion that debugger status stays at reset defaults. Its strengthened
300-frame/hash rerun returned exit status 0, reproduced every count above and
all nine hashes, and is recorded separately in
`build/phase4ee/final/running_hashes.log`.

The directed debugger bench was also strengthened after the full run to
subtract independently counted PPU timestamps at the canonical event and at
effective pause, requiring exact equality with `frame_overrun`. That affected
test rerun returned 0 in `build/phase4ee/final/overrun_ticks.log`, with the same
28 instruction steps, three NMI entries, CPU-only overrun case, and four DMA
overrun cases (last 1,450 ticks). Both strengthened checks are retained in the
normal regression runner. No functional RTL changed after the final fit.

The tests are retained in `scripts/test.sh`, with focused entry points
`scripts/test_debug_command_cdc.sh` and `scripts/test_debugger.sh`. The latter
prepares the project-owned playable cartridge before running. No hardware
programming, physical JTAG commands, or physical debugger observation occurred.

Generated nonempty waveforms from the final regression:

| FST artifact | Bytes |
| --- | ---: |
| `build/sim/nes_debug_command_cdc.fst` | 4,472 |
| `build/sim/nes_debugger_system.fst` | 3,947,580 |
| `build/sim/nes_framebuffer_pause.fst` | 2,367,260 |
| `build/sim/nes_debugger_playable.fst` | 1,191,221,714 |

## Changed files

New implementation and verification files:

- `rtl/debug/nes_debugger_pkg.sv`, `rtl/debug/nes_debugger.sv`,
  `rtl/debug/nes_debug_command_cdc.sv`.
- `verification/debugger.py`, `tests/python/test_debugger.py`.
- `sim/nes_debug_command_cdc_tb.sv`, `sim/nes_debugger_system_tb.sv`,
  `sim/nes_debugger_playable_tb.sv`, `sim/nes_framebuffer_pause_tb.sv`.
- `scripts/test_debug_command_cdc.sh`, `scripts/test_debugger.sh`.
- `docs/phase4e-e-interactive-debugger.md`.

Modified integration, observation, rendering, and retained verification files:

- `rtl/de1_soc_nes_vga_top.sv`, `rtl/nes_core.sv`,
  `rtl/system/nes_cpu_bus.sv`, `rtl/video/nes_framebuffer.sv`.
- `rtl/debug/nes_debug_snapshot_pkg.sv`, `rtl/debug/nes_debug_snapshot.sv`,
  `rtl/debug/nes_debug_panel_renderer.sv`, `rtl/debug/nes_debug_renderer.sv`.
- `verification/debug_snapshot.py`, `verification/debug_renderer.py`,
  `tests/python/test_debug_snapshot.py`.
- `sim/nes_debug_pages_tb.sv`, `sim/nes_phase4db_playable_tb.sv`,
  `sim/nes_vga_phase4db_tb.sv`.
- `scripts/verify_phase4ec_playable_frame.py`, `scripts/verify_phase4ed_pages.py`,
  `scripts/lint.sh`, `scripts/sim.sh`, `scripts/test.sh`.
- `quartus/de1_soc_nes_vga.qsf`, `README.md`.

The CPU datapath, PPU state machines, OAM DMA sequencer, playable ROM, board
pin mapping, and timing constraints are unchanged. Generated reports, traces,
pixel images, SOF, and RBF remain under ignored `build/` paths.

## Final Quartus release gate

The final build includes the framebuffer completion-wait fix and retained
virtual command readback. `scripts/build_de1_soc_nes_vga_quartus.sh` returned
exit status 0 after synthesis, Standard Fit, assembler, all-corner timing,
and SOF-to-RBF conversion. The separate four-corner detailed timing audit also
returned 0. Reports and programming artifacts are archived in
`build/phase4ee/final/` (generated, Git-ignored).

| Resource | Measured Phase 4E-D baseline | Final Phase 4E-E | Delta |
| --- | ---: | ---: | ---: |
| ALMs | 4,702 | 4,897 | +195 |
| Logic ALUTs | 6,167 | 6,493 | +326 |
| Memory ALUTs | 590 | 590 | 0 |
| Registers | 3,944 | 4,528 | +584 |
| M10Ks | 230 | 230 | 0 |
| MLAB bits | 18,880 | 18,880 | 0 |
| Block memory bits | 1,871,872 | 1,871,872 | 0 |
| DSPs | 0 | 0 | 0 |
| PLLs | 1 | 1 | 0 |

Relative to the separately verified hardening-only build, debugger integration
and framebuffer handoff support add 173 ALMs, 346 logic ALUTs, and 609 registers.
The 107-bit snapshot extension adds 321 logical bits across the existing three
banks; actual fitted register totals also include controller/mailbox/heartbeat,
readback, renderer, optimization, and fitter duplication effects.

| Timing metric | Final result |
| --- | ---: |
| Worst setup slack | +1.441 ns |
| Worst hold slack | +0.142 ns |
| Setup / hold TNS, all corners | 0 / 0 ns |
| Unconstrained setup / hold paths | 0 / 0 |
| Worst CLOCK_50 setup path | +2.817 ns |
| Debugger state to functional datapath | +4.648 ns |
| Functional observation to debugger state | +10.549 ns |
| Source snapshot path | +2.967 ns |
| Pixel path | +1.441 ns |

Worst setup is the pixel-domain `video|output_active~DUPLICATE` to `VGA_R[7]`
output path (6.358 ns data delay). The worst NES path runs from CPU
`debug_addressing_mode[3]` to PPU `ppu_data_read_buffer[6]` (16.597 ns data
delay). Debugger-state authorization reaches that PPU buffer with 14.744 ns
data delay and +4.648 ns slack; the worst input to debugger state is PPU
`dot[6]` to `status.state[2]`. The snapshot path is CPU addressing mode to
`source_snapshot.dma.source_data[4]`. Worst hold is debugger
`instruction_steps[7]` to its source-snapshot field at the fast 0 C corner.
All four corners passed. Setup margin improved by 1.368 ns over the measured
baseline. No new false paths or multicycle exceptions were added.

Full compilation reports 0 errors and 18 warnings: the same baseline warning
categories plus the intentionally retained, currently unbound virtual
`debugger_command_readback` register being assigned but not read by board
logic. The detailed timing audit reports the same two unmatched, tied-off IRQ
synchronizer filters. There are no inferred-latch or multiple-driver warnings.
The build script checked that setup/hold are fully constrained and every
reported setup/hold/pulse-width slack is nonnegative.

| Final artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `de1_soc_nes_vga.sof` | 6,690,502 | `0013ea9c9d5ae7a03d3f27abbe66926d9096b3feae3089ae9f3c34fc3e7efea8` |
| `de1_soc_nes_vga.rbf` | 7,007,204 | `d77626f33240f6b195831297a02b00e639d1fd39be0394b56898d7f1314fc1d9` |

These are generated images, not evidence of physical FPGA programming or
physical debugger operation. No hardware programming was performed.

## Phase 4F-A HPS to FPGA runtime-loader recommendation

Use aligned, little-endian 32-bit registers on the lightweight HPS-to-FPGA
bridge for a versioned control/status mailbox
and a separate bounds-checked bulk-transfer path into staging cartridge memory.
Reuse the debugger's acknowledged sequence/disposition convention and safe
pause completion, with a separate loader command namespace. Define the first
register contract before adding filesystem or boot UI policy:

| Offset | Register / operation |
| --- | --- |
| 0x00 | interface version and capabilities |
| 0x04 | command opcode and request sequence |
| 0x08 | acknowledged sequence and result |
| 0x0C | loader state, debugger paused, transfer busy/error |
| 0x10 | image byte length |
| 0x14 | cartridge metadata/format validation status |
| 0x18 | transfer byte offset |
| 0x1C | staged data word with defined byte enables/backpressure |
| 0x20 | expected integrity checksum |
| 0x24 | measured integrity checksum |

Commands should explicitly separate BEGIN, WRITE/TRANSFER, VALIDATE, COMMIT,
ABORT, and RESET/RESUME. Validate lengths, Mapper 0 configuration, PRG/CHR sizes,
mirroring, transfer coverage, and checksum before COMMIT. Reject unsupported
formats rather than partially loading them. COMMIT waits for PAUSED, swaps
only a complete validated staging image/configuration atomically, and resets
NES state through a separate functional NES reset while VGA/debug controls
and both sides of the existing CDC mailboxes remain alive. Do not reset only
one side of a live mailbox. Define storage capacity and
whether CHR is RAM/ROM explicitly; do not assume the current inferred ROMs are
runtime writable. Specify CDC, backpressure, byte ordering, reset ownership,
abort/retry, and failure recovery in directed tests. SD access, filesystem
policy, save states, extra mappers, and a menu remain separate later work.
