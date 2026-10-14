# Phase 7B — UxROM capacity decision

Status: **blocked before implementation; architecture decision required**.
Mapper 2 remains unsupported. This assessment does not establish UxROM
compatibility or completion of Phase 7B.

## Repository and scope

On 2026-10-14, a fresh `git fetch origin` confirmed that
`phase7/uxrom-mapper2`, its remote tracking branch, and `origin/main` all
identified `bbde4c4af8094e05d0817bfc8cbc0368ef48e8dd`, the merge of PR #53.
The initial working tree was clean and the remote was
`git@github.com:hhashmi4/nintendo-fpga.git`.

The [Phase 7A architecture and verification report](phase7a-mapper-framework.md),
[entry assessment](phase7a-mapper-assessment.md), and
[pending hardware checklist](phase7a-welland-validation.md) were reviewed.
Phase 7A explicitly identifies storage capacity and a versioned loader
extension as prerequisites for Phase 7B.

The Phase 7B request requires stopping before an unapproved breaking MMIO,
CDC, or storage change. This is that decision point. No RTL, loader,
software support policy, timing constraint, or CI workflow is changed by this
assessment. No unrelated mapper work has begun.

## Installed capacity and access path

| Boundary | Current implementation | Consequence |
|---|---|---|
| Runtime PRG store | `nes_runtime_cartridge_storage.sv`: 32,768 bytes, 15-bit read address | Two 16 KiB banks physically exist |
| Runtime CHR store | Same module: 8,192 bytes, 13-bit address | One 8 KiB CHR-ROM or CHR-RAM allocation |
| Runtime PRG RAM | Not implemented | No cartridge RAM at CPU `$6000–$7FFF` |
| Common mapper | `nes_mapper.sv`: 24-bit offsets and sizes | Address width reserves space; it does not allocate memory |
| Runtime mapper endpoint | 16-bit sizes; PRG offset narrowed to `[14:0]` after validation | Larger mapping alone would alias the existing store |
| Loader manifest | Mapper ID 8 bits; PRG/CHR byte counts 16 bits; RAM flag; H/V mirroring | 65,536 bytes cannot be represented as a byte count |
| Loader transfer | 16-bit byte address; PRG limit `$7FFF`, CHR limit `$1FFF` | Transfers beyond installed memory are rejected |
| Loader MMIO | v1.0, 64-byte window at `0xff200000` | 32-bit bus registers currently use only low 16 bits for address/sizes |
| Command CDC | Held command/manifest bundle, 16-bit address/sizes | Widening MMIO alone cannot convey a larger image |
| Active metadata / diagnostics | 16-bit cartridge sizes and 15-bit PRG debug address | Larger capacity also requires metadata and diagnostic review |
| Production fallback | Separate initialized NROM-128 PRG and CHR ROM | Physical reset can return to the immutable legacy cartridge |

The production fallback uses 16 KiB PRG and 8 KiB CHR. The reusable legacy
NROM endpoint supports 16/32 KiB PRG, 8 KiB CHR, and optional 8 KiB PRG RAM;
these are separate from runtime storage, not spare banks available to it.

`software/nes_loader/ines.py` extracts Mapper 2 correctly from classic-iNES
header bits, but runtime validation accepts only Mapper 0, one/two PRG banks,
and zero/one CHR-ROM banks. Zero CHR-ROM banks declares CHR RAM, with no CHR
payload transferred. File length must match the declared payload exactly.
`protocol.py` and `execute_load_plan` also reject unsupported or inconsistent
manifests before any transport operation. Merely adding `2` to
`SUPPORTED_MAPPERS` would be incorrect.

Ordinary UNROM images use 64/128 KiB PRG, and UOROM extends this to 256 KiB.
These already exceed the installed store. A two-bank 32 KiB demonstration
would not meet that capacity requirement. The broader Mapper 2 family also
includes larger boards; even a 256 KiB implementation would need an explicit
upper bound and variant policy. See [Programming UNROM](https://www.nesdev.org/wiki/Programming_UNROM).

## Physical memory budget

The archived Phase 7A production fitter report targets `5CSEMA5F31C6` and
reports **275 / 397 M10Ks**, with **2,238,504 / 4,065,280 block-memory bits**.
Its RAM summary attributes 32 M10Ks to runtime PRG and eight to runtime CHR.
The three 61,440-by-9 framebuffers use 68 M10Ks each (204 total); legacy
PRG/CHR uses another 24. These allocations preserve existing Phase 6 behavior.

For the existing byte-wide simple-dual-port PRG inference, the observed
allocation is one M10K per KiB. Replacing only that store gives:

| Proposed runtime PRG | 16 KiB banks | Estimated PRG M10Ks | Estimated whole design | Headroom / deficit |
|---|---:|---:|---:|---:|
| 32 KiB, installed | 2 | 32 | 275 | 122 free |
| 64 KiB | 4 | 64 | 307 | 90 free |
| 128 KiB | 8 | 128 | 371 | 26 free |
| 256 KiB | 16 | 256 | 499 | 102 over capacity |
| 512 KiB | 32 | 512 | 755 | 358 over capacity |

The estimates use `275 - 32 + proposed_PRG_KiB`. Only the installed 32 KiB
row has been fitted. Additional control logic, routing, and any changed
memory packing still require a real fit and timing run. In particular,
128 KiB is a plausible constrained option, not verified support.

Aggregate bit count alone is insufficient because memory width, depth,
ports, and physical block packing matter. Even ideal bit packing with all
current logical memory payloads retained gives
`2,238,504 - 262,144 + 2,097,152 = 4,073,512` bits for 256 KiB PRG,
exceeding the M10K bit capacity by 8,232 bits. Moving data into MLABs,
repacking buffers, or otherwise changing storage could alter this result,
but would be an architectural redesign requiring its own resource and
timing proof. Removing framebuffers or the legacy fallback is not an
acceptable silent tradeoff for Phase 6 functionality.

## Alternatives requiring a decision

| Alternative | Benefit | Work and limitation |
|---|---|---|
| A. Explicit 128 KiB maximum in M10K | Retains deterministic synchronous PRG access; likely fits | Requires a versioned loader/CDC/metadata extension; rejects 256 KiB UOROM and larger images; is partial UxROM support |
| B. FPGA-attached SDRAM for PRG | Capacity for conventional 256 KiB UOROM and larger explicitly bounded images | Requires a controller, board pins/SDC, initialization/refresh, loader backend, and a proven bounded response schedule |
| C. HPS DDR3-backed PRG | Large existing physical memory | Requires an FPGA memory master, Linux buffer ownership/coherency and arbitration/latency guarantees; existing HPS MMIO bridge is not this backend |
| D. Rework on-chip memory allocation | Could retain local PRG access if enough memory is recovered | Requires quantitative packing/MLAB/framebuffer redesign and full Phase 6 validation; no fit is established |

**Recommendation:** for conventional UNROM plus 256 KiB UOROM, approve a
dedicated FPGA-SDRAM PRG backend design and a versioned loading extension,
keeping CHR RAM on chip. First prove its worst-case service latency against
the existing bus schedule, including refresh and arbitrary bank changes.
If that bound cannot be met, stop for an explicit scheduler/interface design
rather than adding uncoordinated CPU stalls. Option A is a smaller alternative
only if a 128 KiB support limit is explicitly accepted.

The board provides 64 MB FPGA-attached SDRAM and 1 GB HPS DDR3 according to
[Terasic's specifications](https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=139&Language=English&No=836&PartNo=2).
Production currently exposes HPS DDR pins but has no cartridge SDRAM
controller or FPGA SDRAM pins in `de1_soc_nes_vga_top.sv`. Physical capacity
does not establish an implemented or qualified memory path.

The proposed loading extension must preserve old NROM v1.0 transactions and
make new address/size/variant capabilities discoverable. It must define exact
widths, maximum sizes, byte-enable handling, rejection of unsupported high
bits, and coherent source/destination/status bundles. Do not reinterpret
zero as 64 KiB or silently discard high address bits. At 256 KiB, offsets
need at least 18 bits and the byte count needs at least 19 bits. The separate
diagnostic v1.3 contract must also be preserved or explicitly extended.
No new wire format or register allocation is approved by this document.

## Mapping and lifecycle requirements after approval

The intended mapping is:

```text
CPU $8000–$BFFF -> selected 16 KiB bank B -> PRG[B * $4000 + (CPU & $3FFF)]
CPU $C000–$FFFF -> final 16 KiB bank N-1 -> PRG[(N-1) * $4000 + (CPU & $3FFF)]
PPU $0000–$1FFF -> 8 KiB CHR RAM        -> CHR[PPU & $1FFF]
```

CPU writes anywhere in `$8000–$FFFF` update mapper state, never PRG bytes.
The final bank remains selectable in the lower window as well. Support must
validate the bank count and physical capacity before address narrowing.
CHR RAM permits PPU writes; horizontal/vertical mirroring comes from the
accepted configuration. No mapper IRQ or runtime PRG RAM is implied.

UNROM uses three bank-select bits; UOROM uses four. Original boards have
bus conflicts, while other Mapper 2 variants may not. For AND conflicts,
the selected register value depends on the CPU byte and the ROM byte at the
write address **under the old mapping**. Classic iNES does not resolve this
ambiguity. A documented board profile/override or a deliberately scoped
NES 2.0 submapper extension is necessary; unknown variants must not be
silently treated as identical. Mapper 94/180 and other mappers are outside
this task. See [UxROM](https://www.nesdev.org/wiki/INES_Mapper_002) and
[NES 2.0 submappers](https://www.nesdev.org/wiki/NES_2.0_submappers).

For approved power-of-two ROM profiles, disconnected bank address bits should
alias according to the selected wiring; an arbitrary modulo operation on
unsupported bank counts is not a board model. Define deterministic FPGA bank
reset (for example bank zero) as an implementation policy, not a guarantee
of every physical board's power-on state. Test boot from the fixed reset
vector, reset/replacement clearing, and immediate execution after switching.

Current memories precharge registered reads on every 50 MHz fabric edge,
independently of accepted CPU/PPU strobes. A bank-register write changes the
address for a subsequent memory edge; its byte must be ready before the next
accepted read. There is no ready/wait interface at the cartridge read boundary.
A cache of only the current 16 KiB bank cannot guarantee this for arbitrary
writes without an explicit miss-service design. CPU/OAM/DMC ownership and
PPU/audio timing must remain consistent.

Retain the established single-store lifecycle: BEGIN holds the NES; accepted
writes overwrite that store; COMMIT verifies complete coverage; ACTIVATE
changes metadata under the four-cycle reset window. Failed software preflight
does not touch the active cartridge. Invalid raw BEGIN enters safe hold;
an interrupted valid transfer has no rollback and needs reload or physical
reset to legacy. CHR-RAM contents are retained and initialized by software.
Mapper state must clear on its functional reset epoch without resetting the
loader write port. The existing reset tree and its distinction between
loader/storage reset and console/activation reset must be preserved.

## Verification and remaining implementation

The complete `PATH="$PWD/.venv/bin:$PATH" scripts/test.sh` gate passed on
2026-10-14 with exit status zero: **2,300 Python tests**, warning-free full
Verilator lint, and **105 RTL/integration PASS records**. The PASS records
are identical to the archived Phase 7A full-regression log. Python took
123.04 seconds. No tests were added or removed: the count remains 2,300;
there is no implemented Phase 7B feature or post-implementation test count.
Only documentation changed, so no second identical full run was needed.
Logs are under ignored `build/phase7b/baseline/`.

| Fresh retained integration evidence | Result |
|---|---|
| Mapper framework | 2,097,547 checks; all 256 IDs, exhaustive NROM addresses/permissions, 32 reset/replacement epochs |
| Runtime lifecycle | Four loads, 266 checks, all 255 unsupported IDs, eight resets |
| Parser through MMIO/CDC to CPU boot | NROM-128/CHR-ROM and NROM-256/CHR-RAM boots; incomplete replacement held safely; 57,609 commands; CHR-RAM readback `$A6` |
| Loaded CHR-ROM frame | 61,440 pixels compared; zero mismatches |
| Sustained gameplay | 26,713,128 cycles; 300 frames; 297 NMI handlers, DMA transfers and controller polls |
| Gameplay plus Developer Mode | 69,720,005 cycles; 84 frames; 82 snapshots; 307,200 compared pixels; zero mismatches |
| Debugger gameplay | 132 frames; 187 commands/acknowledgements; 71 instruction steps; 41 frame steps |
| Final Phase 6G production system | 35,588,469 cycles; 52 PPU frames; 13 reset epochs; 155,949 MMIO commands; zero mismatches |
| Final system peripheral activity | DMA 9; DMC 2,674; controller reads 32,650 / 32,648; PCM 31,012 (30,971 nonzero); WM8731 words 30,969; HDMI words 13,260 |
| Final system video | VGA 307,200 pixels; HDMI 921,600 pixels; zero mismatches |

The final system run took 404.722 seconds and reproduced Phase 7A's counters.
These results establish the unchanged NROM/Phase 6 baseline, not Mapper 2
bank-switching execution. The existing CI workflow is unchanged. No
implementation commit, push, PR or new CI run was made at this stop point;
those remain deferred until the architecture decision and implementation.

The fresh production `scripts/build_de1_soc_nes_vga_quartus.sh` gate passed
using Quartus Prime Lite 23.1std.1 Build 993: synthesis, fitting, assembly,
RBF generation and fully constrained all-corners STA. This is a rebuild of
the unchanged Phase 7A hardware, not a Mapper 2 fit.

| Production measurement | Verified Phase 7A | Fresh Phase 7B entry baseline |
|---|---:|---:|
| ALMs | 9,667 | 9,667 |
| Registers | 15,090 | 15,090 |
| M10Ks | 275 / 397 | 275 / 397 |
| Block-memory bits | 2,238,504 | 2,238,504 |
| DSPs / PLLs | 7 / 2 | 7 / 2 |
| Minimum setup slack | +0.913 ns | +0.913 ns |
| Minimum hold slack | +0.077 ns | +0.077 ns |
| Minimum recovery / removal slack | +3.375 / +0.460 ns | +3.375 / +0.460 ns |
| Minimum pulse-width slack | +0.608 ns | +0.608 ns |
| TNS, all reported corners | 0.000 ns | 0.000 ns |
| Map / fit / assembly / STA warnings | 106 / 149 / 0 / 144 | 105 / 149 / 0 / 144 |

The limiting setup path remains `video|output_active` to `VGA_G[0]`;
the limiting hold path remains the HPS DDR `lfifo` to `os_oct_ddio_oe` path.
Warning categories/counts are identical except that the generated HPS
`altera_mem_if_hhp_qseq_synth_top` dangling-pin warning 12158 is absent in
the fresh synthesis report. The existing generated HPS `pll_dr_clk`
implicit-net warning remains; there are no new project-owned implicit nets,
inferred latches or multiple-driver warnings. No timing constraint or warning
suppression was changed. Reports and critical paths are archived in
`production-reports/`; the earlier reports are copied into
`phase7a-production-reports/` alongside them.

The fresh logical HDMI build (`bash scripts/build_phase6d_hdmi_audio_quartus.sh`)
passed synthesis, fitting, assembly and fully constrained all-corners STA.
It reproduces Phase 7A: 3,297 ALMs, 4,430 registers, 210 M10Ks, eight DSPs,
two PLLs, minimum setup/hold slack +0.747/+0.123 ns, and zero TNS throughout.
Map/fit/assembly/STA warnings remain 22/3/0/0. Reports are archived in
`hdmi-reports/` under the baseline directory. This separate target does not
contain the cartridge mapper; it is a retained compatibility check.

An additional audit probe generated classic-iNES Mapper 2 images with four,
eight and sixteen PRG banks (64/128/256 KiB), each declaring CHR RAM. All
three parsed with the correct mapper and exact PRG length, then were rejected
by runtime support validation. Removing one byte from each image produced a
truncation error. Manually constructed load plans were also rejected before
BEGIN: an already active simulated NROM cartridge retained identical status,
PRG bytes and CHR bytes, with zero new MMIO submissions. Results are saved in
`capacity-preflight-probe.json` beside the baseline logs. These are rejection
checks, not successful UxROM loads, and are not added to the pytest count.

After the capacity decision, implementation still needs independent RTL
address scoreboards across every installed bank, boundaries and repeated
writes; variant masks/conflicts; reset/replacement; CHR-RAM checks; invalid
configuration rejection; and retained Mapper 0/Phase 6 gates. Python must
exercise exact image lengths, bank counts, metadata, oversized/unsupported
profiles, bounded transfers and zero-MMIO preflight failure.

A project-owned test ROM must execute code across bank changes, return to
fixed-bank routines, initialize CHR RAM, and produce checked PPU output.
Successful loading alone is not execution evidence. No Mapper 2 execution,
commercial compatibility, or FPGA fit with expanded storage has been demonstrated.

Physical DE1-SoC programming, SDRAM qualification if selected, HPS loading,
bank-switching gameplay, CHR output, reset/replacement and sustained A/V remain
**pending**, alongside the Phase 7A/Phase 6 hardware checklist. Phase 7B is
not complete and does not establish readiness for Phase 7C.
