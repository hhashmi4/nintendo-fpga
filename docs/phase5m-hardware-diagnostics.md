# Phase 5M — hardware diagnostics and fault reporting

Phase 5M adds a bounded, simulation-first diagnostic plane that remains alive
when the NES scheduler, CPU, debugger, loader, or runtime cartridge is stopped.
It does not add HDMI, USB-C, mapper support, or Phase 5L physical validation.
The DE1-SoC was unavailable during this work, so every board-facing result is
reported as **NOT TESTED**.

## Architecture

```text
CPU / PPU / APU / DMA / loader / cartridge (50 MHz)
              | existing status and event signals
              v
   counters + timeout monitors + sticky faults
              |
              +--> 16-entry circular trace
              |
              +--> atomic source snapshot bank
                        || request/ack toggle + held bundle
                        \/
               HPS-clock snapshot bank
                        |
       separate Platform Designer Avalon-MM slave
                        |
            lightweight HPS-to-FPGA bridge
```

`rtl/diagnostic/nes_diagnostic_subsystem.sv` owns the counters, fault latches,
trace and MMIO slave. Its diagnostic reset is derived from `KEY0`, not from the
NES functional reset. It therefore observes loader-held reset, debugger pause,
and CPU/DMA stalls without requiring NES CPU progress. Collection is passive:
it neither gates a clock enable nor participates in bus arbitration.

`config/diagnostic_mmio.json` is the versioned source of truth. The generator
`scripts/generate_diagnostic_mmio_defs.py` produces the SystemVerilog package,
Python constants, and Tcl address constants. `scripts/generate_hps_loader_system.sh`
validates the contract against the generated Platform Designer map and rejects
overlap, misalignment, incorrect width, or an out-of-window span.

## HPS MMIO allocation

The existing Phase 4F-F loader aperture is unchanged:

| Slave | Lightweight offset | Physical base | Span |
|---|---:|---:|---:|
| runtime loader | `0x0000` | `0xff200000` | 64 bytes |
| Phase 5M diagnostics | `0x1000` | `0xff201000` | 512 bytes |

The new `diagnostic_mmio_bridge` is separately decoded in
`quartus/nes_hps_loader_system.qsys`. No loader register or address changed.
The diagnostic bus is 32-bit little-endian, byte addressed, and requires
aligned accesses.

Interface magic is `0x4e455344` (`NESD`), version is `1.0`, and the Phase 5M
build identifier is `0x0005000d`. A major-version mismatch is rejected by the
Linux backend. CPU instruction retirement is deliberately absent from the
availability bitmap and reads as `0xffffffff`: the core has no retirement
pulse, and a changing PC is not treated as retirement.

### Register map

| Offset | Register | Semantics |
|---:|---|---|
| `000` | `MAGIC` | `NESD` identifier |
| `004` | `VERSION` | major in 31:16, minor in 15:0 |
| `008` | `BUILD_ID` | interface build identifier |
| `00c` | `CAPABILITIES` | snapshot, faults, trace, injection/model, heartbeats |
| `010` | `CONTROL` | command bits described below |
| `014` | `CONTROL_STATUS` | bit 0 busy, 1 snapshot valid, 2 rejected |
| `018` | `SNAPSHOT_SEQUENCE` | increments after each completed snapshot |
| `01c` | `AVAILABILITY` | validity bitmap; retirement bit is clear |
| `020` | `RESET_CAUSE` | most recently observable cause code |
| `024` | `SYSTEM_STATUS` | reset, pause, cartridge/runtime and fault summary |
| `028` | `CLOCK_STATUS` | current/seen PLL lock and video heartbeat |
| `02c` | `CPU_STATUS` | reset, stall, IRQ, pause and step state |
| `030` | `CPU_CYCLES` | accepted CPU cycle slots, modulo 2^32 |
| `034` | `CPU_INSTRUCTIONS` | unavailable sentinel `0xffffffff` |
| `038` | `CPU_STALL_CYCLES` | observed CPU stall cycles |
| `03c` | `CPU_IRQ_EVENTS` | IRQ inactive-to-active events |
| `040` | `CPU_NMI_EVENTS` | NMI events delivered by the PPU path |
| `044` | `CPU_DEBUG_EVENTS` | pause/resume/step events |
| `048` | `CPU_PC` | atomic 16-bit PC observation |
| `04c` | `PPU_STATUS` | dot, scanline, odd-frame and NMI level |
| `050` | `PPU_FRAMES` | NES PPU frame starts |
| `054` | `PPU_NMI_EVENTS` | PPU NMI events |
| `058` | `VIDEO_STATUS` | PLL, frame/line activity, active video and framebuffer status |
| `05c` | `VGA_FRAMES` | synchronized VGA frame toggles |
| `060` | `VGA_HSYNC_EVENTS` | synchronized line/HSYNC activity |
| `064` | `VGA_VSYNC_EVENTS` | synchronized frame/VSYNC activity |
| `068` | `APU_STATUS` | APU activity and IRQ summary |
| `06c` | `APU_CYCLES` | APU/CPU-time slots |
| `070` | `AUDIO_STATUS` | PLL, codec state and mute |
| `074` | `AUDIO_MIXED_SAMPLES` | reused Phase 5K generated-sample count |
| `078` | `AUDIO_PCM_SAMPLES` | reused Phase 5K generated PCM count |
| `07c` | `AUDIO_I2S_FRAMES` | reused transmitted-frame count |
| `080` | `AUDIO_FIFO` | current synchronized FIFO occupancy |
| `084` | `AUDIO_UNDERRUNS` | reused Phase 5K count |
| `088` | `AUDIO_OVERRUNS` | reused Phase 5K count |
| `08c` | `AUDIO_CODEC_ACKS` | codec initialization ACKs |
| `090` | `AUDIO_CODEC_NACKS` | codec initialization NACKs |
| `094` | `AUDIO_CODEC_TIMEOUTS` | codec bus timeouts |
| `098` | `AUDIO_CODEC_RETRIES` | initialization retries |
| `09c` | `AUDIO_LAST_FAULT` | existing Phase 5K audio fault code |
| `0a0` | `LOADER_STATUS` | state, busy, validity, active/reset and error |
| `0a4` | `LOADER_PRG_TRANSFERS` | accepted PRG write commands |
| `0a8` | `LOADER_CHR_TRANSFERS` | accepted CHR write commands |
| `0ac` | `LOADER_ACTIVATIONS` | accepted atomic activations |
| `0b0` | `LOADER_ERRORS` | loader error transitions |
| `0b4` | `DMA_STATUS` | CPU stall, OAM/DMC activity and bus owner |
| `0b8` | `DMA_OAM_COMPLETED` | completed OAM transactions |
| `0bc` | `DMA_DMC_COMPLETED` | acknowledged DMC reads |
| `0c0` | `DMA_ARBITRATION_WAITS` | CPU slots owned by DMA |
| `0c4` | `DMA_STALLED_REQUESTS` | pending DMC request cycles |
| `0c8` | `CARTRIDGE_STATUS` | presence, Mapper 0 metadata and mirroring |
| `0cc` | `FAULT_FLAGS` | sticky fault bitmap |
| `0d0` | `FAULT_CLEAR_MASK` | mask consumed by explicit clear command |
| `0d4` | `LAST_FAULT` | stable numeric fault code |
| `0d8` | `FABRIC_HEARTBEAT` | 50 MHz free-running counter in snapshot |
| `0dc` | `MMIO_HEARTBEAT` | live HPS-MMIO-domain counter |
| `0e0` | `TRACE_STATUS` | arm/trigger/freeze, count and write index |
| `0e4` | `TRACE_INDEX` | physical entry selector |
| `0e8` | `TRACE_TIMESTAMP` | selected entry timestamp |
| `0ec` | `TRACE_EVENT` | selected stable event code |
| `0f0` | `TRACE_PAYLOAD` | selected 24-bit payload |
| `0f4` | `TRACE_OVERFLOW` | overwritten-event count |

`CONTROL` bits are snapshot `0`, fault clear `1`, trace arm `2`, manual
trigger `3`, freeze `4`, and trace clear `5`. Only one cross-domain command may
be outstanding. A write while busy sets rejected status and has no source-side
effect. For clearing faults, software writes `FAULT_CLEAR_MASK`, issues fault
clear, waits for busy to clear, and requests a new snapshot. A still-active
condition is relatched; this prevents clear from hiding a real ongoing fault.

All multiword status registers except `MMIO_HEARTBEAT`, identity, control, and
trace selector are from one atomic snapshot. They remain stable until the next
completed snapshot. `MMIO_HEARTBEAT` is intentionally live so a stalled source
snapshot can be distinguished from a dead HPS-facing slave.

## Clock and reset observation

The 50 MHz fabric heartbeat runs independently of NES enables. Video and audio
PLL current/ever-locked bits are exposed. VGA frame, line/HSYNC and
frame/VSYNC pulses are converted to toggles in the pixel domain and passed
through forced three-stage synchronizers before counting. Active-video is a
two-stage level synchronization. Phase 5K already converts audio-domain sample
and underrun counters through Gray-coded CDC, so Phase 5M reuses those safe
50 MHz observations rather than adding a parallel crossing.

A missing VGA heartbeat can be detected while `CLOCK_50` remains live. No FPGA
logic clocked solely by `CLOCK_50` can diagnose complete loss of that same
reference clock; the HPS can instead observe that both the fabric heartbeat
and snapshot sequence stopped while the independent MMIO heartbeat remains
live. Lack of data alone never sets a hardware fault.

Phase 6B extends `VIDEO_STATUS` in formerly reserved bits without changing the
register address, interface version, snapshot behavior, or original meanings:

| Bit | Meaning |
|---:|---|
| 0 | current video PLL lock |
| 1 | synchronized VGA frame activity |
| 2 | synchronized VGA line/HSYNC activity |
| 3 | synchronized VGA frame/VSYNC activity |
| 4 | synchronized VGA active-video level |
| 5 | framebuffer capture active |
| 6 | completed framebuffer pending handoff |
| 7 | display bank contains a complete frame |
| 8 | sticky framebuffer write-range error |
| 9 | sticky framebuffer write-sequence error |

Bits 5, 6, 8 and 9 are produced in the 50 MHz fabric domain. Bit 7 crosses
from the VGA pixel domain through a forced two-flop synchronizer whose first
stage is explicitly constrained. The extension adds no unsynchronized
multi-bit observation. Bits 31:10 remain reserved and zero.

The diagnostic plane survives NES functional reset. Reset cause distinguishes
observable video-PLL loss, HPS bridge reset and runtime replacement. FPGA
configuration versus assertion of the shared physical `KEY0` reset cannot be
distinguished without always-on storage, so a fresh diagnostic reset reports
power-on.

## Counters and fault detection

Fabric-owned activity counters wrap modulo 2^32 and are tested at rollover.
The existing Phase 5K safety counters retain their original saturating
semantics. CPU progress uses the real CPU microcycle-enable event; instruction
retirement is not inferred from PC. CPU timeout excludes reset, debugger pause,
OAM DMA and DMC DMA. Loader and DMA timeouts count genuinely active operations.
The video timeout starts only with the video PLL locked and resets on a
synchronized frame event.

| Code / bit | Fault | Observable source |
|---:|---|---|
| 1 / 0 | `CLOCK_UNLOCKED` | a video/audio PLL loses lock after being seen locked |
| 2 / 1 | `CODEC_INIT_NACK` | Phase 5K NACK counter changes in codec error state |
| 3 / 2 | `CODEC_INIT_TIMEOUT` | Phase 5K timeout counter changes in codec error state |
| 4 / 3 | `AUDIO_FIFO_UNDERRUN` | Phase 5K underrun counter changes |
| 5 / 4 | `AUDIO_FIFO_OVERRUN` | Phase 5K overrun counter changes |
| 6 / 5 | `LOADER_TIMEOUT` | loader remains busy beyond its bounded monitor |
| 7 / 6 | `INVALID_CARTRIDGE` | loader emits a manifest/Mapper/size/activation error |
| 8 / 7 | `CPU_STALL_TIMEOUT` | no real CPU progress outside intentional holds |
| 9 / 8 | `VIDEO_HEARTBEAT_TIMEOUT` | no VGA frame while video is expected active |
| 10 / 9 | `DMA_TRANSACTION_TIMEOUT` | OAM/DMC request remains active too long |

The numeric code is stable for machine parsing. The bitmap is sticky until
explicit clear; `LAST_FAULT` records the latest detected priority code.
Simulation injection uses the same ten bits and is tied to zero in production.

## Bounded trace

The trace contains exactly 16 entries. Each entry is a 32-bit fabric timestamp,
an 8-bit event code, and a 24-bit payload. Events cover reset, IRQ/NMI,
cartridge activation, loader errors, OAM/DMC start/completion, codec/fifo
failure, debugger pause/resume, and otherwise uncategorized faults.

While armed, entries overwrite the oldest physical slot after the buffer is
full and increment `TRACE_OVERFLOW`. At most one event is recorded per fabric
cycle with documented failure-before-activity priority. `TRACE_STATUS` exposes
count and next write index, allowing software to return oldest-to-newest order:
index zero is oldest before the first wrap; after a full wrap, the next write
index is oldest. Manual trigger or freeze disarms and freezes. A newly latched
fault automatically triggers after recording its event. Clear resets trace
contents and metadata; arm resumes capture.

## CDC design

The HPS user clock, pixel clock, audio PLL clock and 50 MHz clock are unrelated.
Phase 5M uses no unsynchronized multi-bit observation:

- HPS commands and clear masks are held in a source bank. A request toggle
  traverses three forced synchronizer stages; the fabric then captures the
  stable bundle, executes once, and returns an acknowledge toggle. An HPS-only
  bridge reset rebases both mailbox epochs without clearing fabric diagnostics.
- Snapshot words and all trace entries are captured into a fabric bank. They
  are held while the acknowledge traverses three stages, then atomically copied
  into the HPS bank.
- SDC false-paths only the first metastability-catching toggle stages and sets
  finite 20 ns bounds on both held payload bundles.
- Pixel-domain activity crosses as synchronized toggles; audio statistics reuse
  the Phase 5K Gray-counter/FIFO CDC.

The directed RTL test uses unrelated 100 MHz and approximately 71.4 MHz clocks,
checks snapshot stability during live counter changes, and checks exactly-once
video toggle counting and deterministic reset.

## Linux backend and `nes-debug`

Use the repository-local command from the repository root:

```bash
./scripts/nes-debug doctor
./scripts/nes-debug doctor --full
./scripts/nes-debug status
./scripts/nes-debug faults
./scripts/nes-debug trace
./scripts/nes-debug report --format json
./scripts/nes-debug report --format text --output-dir build/diagnostics
```

This does not claim a system-wide installation. The default backend is
`offline`; it never opens `/dev/mem`. Real access requires explicit
`--backend mmio` and optionally `--dev-mem PATH`. Missing hardware, permission
denial, malformed reads, timeouts, command rejection, bad magic and unsupported
major versions produce structured errors and nonzero CLI status. The MMIO
backend reuses the page-correct Phase 4F-F `DevMemMmio` transport.

`doctor --full` runs the complete `scripts/test.sh` regression during that
invocation, including the Python model/backend tests and directed RTL/model
comparison. In offline mode it prints
`NOT TESTED` for the DE1-SoC, HPS bridge, FPGA clocks, codec and VGA. A passing
software/simulation result is never promoted to a physical hardware result.

Reports contain UTC timestamp, Git commit/branch, discovered tool versions,
interface/build version, backend, hardware availability, all observed
registers, decoded status, faults, trace, warnings and unavailable
measurements. They do not include environment variables, tokens, user names,
home paths, ROM contents, or arbitrary process output.

### Fault injection

Repeat `--inject` on an offline command with any of:

```text
codec-nack                 audio-underrun
audio-overrun              loader-timeout
invalid-cartridge          cpu-stall
missing-video-heartbeat    dma-timeout
clock-unlock               unsupported-version
```

The first nine map to the hardware fault code with the same name. The last
exercises interface-version rejection. Injection is rejected for the real
MMIO backend.

## Verification

The independent Python model implements modulo counters, atomic snapshot
copying, explicit unavailable values, sticky fault/clear behavior, and circular
trace ordering without transcribing the RTL state machine. The directed RTL
test emits seven semantic results that `scripts/verify_diagnostic_phase5m.py`
recomputes independently: rollover, trace depth/count, overflow, write index,
and the oldest/newest payload after circular wrap.

Focused verification covers the generated magic/version/map, address decode,
loader isolation, atomic snapshots, counter increment/rollover, sticky faults,
clear/re-latch, trace arm/trigger/freeze/overflow/readout/order, unrelated-clock
CDC, reset, every injected fault, unsupported versions, malformed reads,
missing hardware, permission denial, JSON/text output, CLI exit codes and
secret exclusion. `scripts/test.sh` retains the complete CPU, PPU, APU, DMA,
controller, Mapper 0, runtime loader, VGA, Developer Mode, debugger, playable
ROM and Phase 5J/5K regressions.

Toolchain used for qualification:

- Python 3.14.4 and pytest 8.3.5;
- Verilator 5.032 (2025-01-01 Debian revision);
- Quartus Prime Lite 23.1std.1 Build 993;
- Platform Designer/Qsys component version 23.1.

The pre-change Phase 5K baseline passed 1,942 Python tests and the complete RTL
regression. It used 7,031 ALMs, 9,897 logic ALUTs, 7,092 total registers, 275
M10Ks, 7 DSPs and 2 PLLs, with +0.863 ns worst setup, +0.077 ns worst hold and
zero setup/hold TNS.

The Phase 5M qualification passes 1,967 Python tests, complete Verilator lint,
the complete retained RTL/system regression, and the production Quartus flow.
The fitted image uses 9,613 ALMs, 12,931 logic ALUTs, 15,011 total registers
(14,785 dedicated logic registers), 275 M10Ks/2,238,504 block bits, 590 memory
ALUTs/18,880 MLAB bits, 7 DSPs and 2 PLLs. All setup and hold TNS values are
zero, the design has zero unconstrained paths, and the worst all-corner setup
and hold margins are +0.729 ns (`CLOCK_50`, slow 85 C) and +0.077 ns (HPS DDR
AFI, fast 0 C). Analysis/synthesis, fitter, assembler and timing emitted
106/149/0/144 warnings respectively; these are the retained generated HPS,
DDR, pin-model and clock-uncertainty classes, with no Phase 5M empty-collection
or ignored-constraint warning.

## Physical bring-up procedure and limitations

When a DE1-SoC is available in a later physical-validation phase:

1. Build and program the production SOF/RBF without changing the validated
   address contract.
2. Boot Linux and first run `nes-debug doctor --backend mmio`; verify magic,
   version and changing MMIO/fabric heartbeats.
3. Request repeated snapshots and verify stable sequence increments, PLL lock,
   reset cause and the expected idle loader/cartridge state.
4. Load the existing Mapper 0 test image, then check PRG/CHR counts, activation,
   CPU/PPU/APU progress, DMA and VGA heartbeat.
5. Check codec completion, 48 kHz sample/I2S progress, FIFO occupancy and zero
   new audio faults before listening tests.
6. Arm the trace, exercise reset/loader/DMA/debugger paths, freeze it and save a
   JSON report outside the repository.
7. Inject failures only in simulation; do not synthesize or drive the
   production `fault_inject` tie-off.

No step above was performed in Phase 5M. The implementation cannot diagnose
loss of its own 50 MHz reference without the independent HPS clock, cannot
distinguish FPGA configuration from the shared physical reset button, exposes
no genuine instruction-retirement count, and has no physical analogue, signal-
integrity, thermal, power, SD-card, or long-duration board evidence. Those
states remain unavailable or **NOT TESTED**, never PASS.
