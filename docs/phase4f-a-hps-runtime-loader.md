# Phase 4F-A — HPS ↔ FPGA Runtime Loader Interface

## Purpose and scope

Phase 4F will eventually load an NES image at runtime without rebuilding the
FPGA bitstream. Phase 4F-A implements only the FPGA-side logical protocol and
control foundation. It provides typed commands, target and address validation,
write backpressure, deterministic status/error handling, and an execution-hold
request suitable for later connection to the NES reset architecture.

Phase 4F-A does not add runtime-writable PRG or CHR arrays, an HPS bridge,
Platform Designer/Qsys components, Linux or `/dev/mem` software, iNES parsing,
microSD access, a menu, APU/audio, or another mapper. It does not claim that a
`.nes` file can be loaded or that physical HPS communication works.

The pre-existing cartridge read path and board image are unchanged. The
runtime loader is deliberately isolated until Phase 4F-B provides a real
storage endpoint and the associated reset-tree integration.

## Repository and baseline

Work began on clean branch `phase4/hps-runtime-loader` at commit
`3b25c0bbe3065e76bf0e726e6b8e79c5207bca0b`. The host used Python 3.14.4 and
the verified Verilator 5.032 toolchain. Before any source change,
`PATH="$PWD/.venv/bin:$PATH" scripts/test.sh` completed successfully:

- 1,228 Python tests passed;
- complete Verilator lint passed;
- every retained CPU, PPU, system-bus, Mapper 0, controller, DMA/NMI,
  playable-ROM, VGA/video, and Phase 4E debugger simulation passed;
- the 300-frame playable test recorded 297 NMIs, DMA completions, and
  controller polls, with 300 coherent snapshot updates;
- five Developer Mode pages compared 1,536,000 pixels with zero mismatches;
- the final mixed debugger run completed 132 source frames, 187 commands and
  acknowledgements, 71 instruction steps, 41 frame steps, 129 NMIs, 129 DMA
  completions, and 129 controller polls.

No background regression remained active when implementation began.

## Existing architecture and new boundary

The Phase 4A bus already separates CPU cartridge traffic from the PPU CHR
port. Phase 4B places Mapper 0 behind the stable `nes_cartridge` shell. Phase
4E-E controls execution through scheduler authorization without giving an
external producer access to the NES bus. Phase 4F-A follows the same separation
of concerns:

```text
future Linux loader
        |
        v
Cyclone V HPS bridge                 (future)
        |
        v
bridge / register / CDC adapter      (future)
        |
        v
nes_runtime_loader                   (Phase 4F-A)
  | command/status
  | validated ready/valid byte write
  +------------------------------+
                                 v
                 runtime PRG/CHR storage endpoint   (Phase 4F-B)
                                 |
                                 v
                        cartridge / Mapper 0
                           ^             ^
                           |             |
                         CPU bus       PPU CHR port

nes_runtime_loader.nes_hold_reset ---> functional NES reset integration
                                      (Phase 4F-B)
```

The loader never drives CPU address, data, read/write, DMA, PPU register, or
controller signals. The HPS therefore cannot impersonate the NES CPU through
this interface.

## Package, commands, and targets

`rtl/loader/nes_runtime_loader_pkg.sv` owns every encoding and size constant.
No scattered numeric target values occur in the controller.

| Command | Value | Meaning |
| --- | ---: | --- |
| `BEGIN` | 0 | start a new load session and clear prior completion/error |
| `WRITE` | 1 | transfer one validated byte to the storage endpoint |
| `COMMIT` | 2 | complete a nonempty, error-free session |
| reserved | 3 | deterministic bad-command error |

| Target | Value | Legal byte offsets |
| --- | ---: | --- |
| none | 0 | never legal for a write |
| PRG | 1 | `$0000-$7FFF` (32 KiB maximum NROM PRG) |
| CHR | 2 | `$0000-$1FFF` (8 KiB NROM CHR) |
| reserved | 3 | never legal for a write |

Addresses are explicit unsigned 16-bit byte offsets and data is exactly eight
bits. A 16-bit representation allows the controller to detect `$8000-$FFFF`
as invalid PRG offsets and `$2000-$FFFF` as invalid CHR offsets rather than
silently truncating them. The target enum leaves the command structure usable
for a later metadata command without redefining PRG or CHR writes; Phase 4F-A
does not add that metadata protocol.

## State machine

```text
                 BEGIN
       +------------------------+
       |                        v
     IDLE                    LOADING
       ^                     |  |  |
       |                 WRITE  |  +-- error --> ERROR
       |                (repeat)|                 |
       |                       COMMIT             |
       |                        |                 |
       |                        v                 |
       +-- reset ------------ READY              |
                                |                |
                                +---- BEGIN ------+
                                                 |
                           fresh BEGIN -----------+
```

The actual transitions are:

| Current state | Accepted command | Result |
| --- | --- | --- |
| IDLE | BEGIN | LOADING; clear error/completion and write-seen |
| IDLE | WRITE or COMMIT | ERROR / wrong state |
| LOADING | legal accepted WRITE | remain LOADING; record nonempty session |
| LOADING | COMMIT after a write | READY |
| LOADING | COMMIT before a write | ERROR / empty load |
| LOADING | BEGIN | ERROR / begin while busy |
| READY | BEGIN | LOADING and assert hold for replacement load |
| READY | WRITE or COMMIT | ERROR / wrong state |
| ERROR | BEGIN | LOADING; clear the latched error |
| ERROR | any other command | remain ERROR and preserve first error |
| any | reserved command | ERROR / bad command, unless preserving an earlier error |
| any | reset | IDLE with cleared status |

`busy` is true only in LOADING. `completed` is true only in READY. `error` is
true only in ERROR. These status values are mutually exclusive.

## Handshake semantics

The command side uses `command_valid`, `command_ready`, and
`command_accepted = command_valid && command_ready`. BEGIN, COMMIT, and invalid
commands are accepted immediately when reset is inactive. A legal WRITE in
LOADING directly reflects `storage_write_ready` into `command_ready` and
asserts `storage_write_valid` with its typed target, address, and byte data.

If the endpoint lowers `storage_write_ready`, the producer must hold
`command_valid`, WRITE, target, address, and data stable. No command acceptance
or storage write occurs. Once ready rises, exactly one handshake accepts the
byte. Assertions check payload stability throughout backpressure. This is a
single-beat ready/valid channel, not AXI and not a speculative HPS bus.

The controller has no hidden FIFO. This keeps the later bridge adapter's
buffering and clock-domain choices separate from protocol correctness.

## Error semantics

The error output has a typed three-bit reason:

| Error | Cause |
| --- | --- |
| none | no error |
| wrong state | WRITE/COMMIT outside LOADING |
| begin busy | BEGIN while already LOADING |
| bad command | reserved command encoding |
| bad target | WRITE target is neither PRG nor CHR |
| bad address | target-specific byte offset is outside its legal range |
| empty load | COMMIT before any accepted write |

Every rejected WRITE produces no downstream write. The first error remains
latched in ERROR so later bad traffic cannot hide its cause. Reset or a fresh
BEGIN clears the error. A fresh BEGIN is the only non-reset recovery command.

Using one encoded command eliminates ambiguous simultaneous BEGIN/WRITE/COMMIT
pulses. The reserved opcode is the deterministic malformed-command case.

## Reset and NES execution safety

Synchronous reset returns the controller to IDLE, clears completion, error,
and write-seen state, suppresses command acceptance and downstream writes, and
asserts `nes_hold_reset`. Reset during a backpressured or active loading
session discards the partial session; it cannot emit a stale write after reset
or report READY.

`nes_hold_reset` is asserted in IDLE, LOADING, ERROR, and while reset itself is
active. It deasserts only in READY after an explicit COMMIT of a session with
at least one downstream-accepted write. Starting a replacement load from READY
asserts hold on the accepting clock edge before any new write can be accepted.

Phase 4F-A intentionally leaves this output unconnected in the production
top. Consequently the existing synthesized playable ROM behaves exactly as it
did before this phase. Phase 4F-B must connect it to a functional NES reset or
equivalent execution hold at the same time that runtime storage becomes
visible. Leaving it disconnected after adding runtime-writable storage would
violate the safety contract.

COMMIT is the upstream producer's statement that its image transfer is
complete. Phase 4F-A rejects an empty transfer but cannot prove whole-image
coverage because image length, iNES metadata, staging storage, and atomic
activation are outside this subphase. Phase 4F-B must add those storage and
coverage rules before presenting runtime-loaded data to the NES.

## Clock-domain assumptions

`nes_runtime_loader` is synchronous to one loader/storage clock. In the
current architecture that integration clock should be the 50 MHz fabric clock
used by the cartridge. Every command and storage handshake must already be
synchronous to that clock.

A real HPS transport may use another clock. Its future adapter must cross
commands and responses with a proper mailbox, asynchronous FIFO, or equivalent
CDC structure and must hold bundled payload data according to that structure's
contract. Phase 4F-A does not pass an asynchronous HPS pulse into NES logic and
does not guess at a Platform Designer bridge clock.

## Verification

`verification/runtime_loader.py` independently models the states, legal
ranges, handshake, error latch, reset, and hold output. The Python tests cover
every range boundary and error class, reset during backpressure, recovery, PRG
and CHR writes, completion, and 20,000 deterministic randomized cycles using
seed `$04FA2026`.

`scripts/generate_runtime_loader_vectors.py` uses the same architectural model
to generate 4,096 fixed-seed cycle vectors while obeying ready/valid payload
stability. `sim/nes_runtime_loader_phase4fa_tb.sv` compares every combinational
output and following state transition with those vectors. Directed RTL checks
also cover reset, WRITE/COMMIT before BEGIN, BEGIN while busy, reserved targets
and commands, both address limits, empty COMMIT, error latching/recovery, exact
PRG and CHR payloads, 64 ordered sequential writes, nine cycles of
backpressure, COMMIT/replacement load, and reset cancellation.

RTL assertions require one legal state, mutually exclusive status, no
downstream write outside a legal active load, hold throughout loading/error,
READY only with hold released, reset-safe outputs, and stable backpressured
payloads. Verilator 5.032 supports all retained constructs.

The focused result is 20 new Python tests passed, warning-free standalone lint,
100 directed RTL checks, 4,096 model cycles, and 91 observed downstream write
handshakes. The complete Python suite passes all 1,248 tests. The normal
`scripts/test.sh` path includes the new test through pytest,
`scripts/lint.sh`, and `scripts/sim.sh`; CI therefore needs no second workflow.

## Synthesis boundary

`quartus/nes_runtime_loader.qpf` and `.qsf` provide a standalone Cyclone V
analysis-and-synthesis target. `scripts/build_runtime_loader_quartus.sh` checks
successful synthesis and rejects latch or multiple-driver warnings. This
proves the controller itself is synthesizable without changing board pins,
constraints, the production top, or the cartridge memories.

Quartus Prime Lite 23.1.1 analysis and synthesis completed with zero errors
and zero warnings. The standalone controller uses an estimated 20 ALMs, 31
combinational ALUTs, eight registers, zero DSP blocks, and zero PLLs.

The unchanged production board project was also compiled with
`scripts/build_de1_soc_nes_vga_quartus.sh`. Analysis/synthesis, fitting,
assembly, and timing analysis all completed with zero errors; the generated
SOF and RBF passed the script's artifact checks. Timing remained fully
constrained with nonnegative reported slack (minimum reported slack 0.142 ns).
The fitted board design uses 4,897 ALMs (15%), 4,528 registers, 230 RAM blocks
(58%), zero DSP blocks, and one PLL. This is a production-path non-regression
check; the isolated Phase 4F-A controller is deliberately absent from that
board image until the Phase 4F-B storage/reset integration exists.

No physical DE1-SoC, HPS bridge, Linux process, JTAG session, or microSD card is
required or claimed for Phase 4F-A.

## Known limitations and Phase 4F continuation

- No bytes are stored by Phase 4F-A; the output write transaction is only the
  validated control boundary.
- COMMIT validates protocol completion and at least one accepted byte, not a
  complete iNES image, checksum, mapper configuration, or transfer coverage.
- The hold/reset request is not connected to `nes_core` in this isolated phase.
- The command source, bridge register map, CDC adapter, and Linux software do
  not yet exist.
- Only PRG and CHR targets and NROM-sized ranges are supported. No mapper was
  added.

Phase 4F-B subsequently added runtime-writable Mapper 0 PRG/CHR storage behind
the validated write interface while retaining the existing build-time ROM
path. Its architecture and verification are documented in
[`phase4f-b-runtime-cartridge-storage.md`](phase4f-b-runtime-cartridge-storage.md).
Complete-transfer validation is Phase 4F-C; atomic activation and functional
NES reset/hold integration are Phase 4F-D. The physical Cyclone V HPS bridge
and its CDC/register adapter remain later Phase 4F work.
