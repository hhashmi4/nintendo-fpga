# Phase 6E — USB-C power architecture and supervision

## Scope and qualification

This phase defines a proposed production power architecture and implements an
isolated, synthesizable **post-configuration observer**. It does not implement
physical USB PD, analog protection, regulator control, a production circuit,
or a board power modification. The DE1-SoC is unavailable. All physical results
are **NOT TESTED**. Phase 6F and later phases are not started.

The source of truth for units, estimates, rails, sources, faults and qualification
gaps is [`config/phase6e_power_architecture.json`](../config/phase6e_power_architecture.json).
Its `ESTIMATED` power values and `PROVISIONAL` rails are engineering assumptions,
not measured consumption, guaranteed maxima, component selections, or a BOM.

The production DE1-SoC retains its existing supply, clocks, reset, VGA and WM8731
connections. Only an append-only diagnostic schema extension is fitted there;
USB-C availability is false and its data is zero. `phase6e_power_top` is a
separate logical qualification project with virtual power/status ports. Its
SOF must not be interpreted as a production board power implementation.

## Repository inspection and baseline

Entry checks passed on clean `phase6/usbc-power` at `f1f242d`, the Phase 6D
merge. Origin is `git@github.com:hhashmi4/nintendo-fpga.git`. No source changes
were made before the complete baseline gate passed.

Actual interfaces inspected:

- `de1_soc_nes_vga_top`: 50 MHz fabric, video/audio PLLs, `reset_sync`,
  diagnostic reset from KEY0 independently of NES functional reset.
- `nes_hps_loader_system.qsys`: 5CSEMA5F31C6, HPS DDR3 at **1.5 V**, lightweight
  bridge; loader `0xff200000`/64 bytes and diagnostics `0xff201000`/512 bytes.
  HPS owns DDR boot/calibration, microSD and USB ULPI peripherals.
- `nes_audio_output`: existing Phase 5K FIR/conditioner, PCM, asynchronous FIFO,
  WM8731 startup and 12 MHz audio PLL. No audio data-path change is made.
- `phase6b_video_top`, `phase6c_hdmi_top`, `phase6d_hdmi_audio_top`: logical
  RGB/ADV7513/I2S qualification targets; production still uses VGA/WM8731.
- `nes_diagnostic_subsystem`: held snapshot bank, three-stage request/ack CDC,
  explicit commands, independent counters. Existing meanings are preserved.
- Production QSF/SDC, HPS-generated constraints, test/lint/simulation scripts,
  and the requested Phase 6A–6D and Phase 5M documents.

Baseline `PATH="$PWD/.venv/bin:$PATH" scripts/test.sh` passed **2,036 Python
tests**, full Verilator lint, every retained RTL/model suite, Phase 5K, Phase
5M, Phase 6B/C/D, and debugger integration. Representative comparison counts:

| Baseline check | Evidence |
|---|---|
| APU Phase 5A/B/C/D/E/F | 142,214 / 220,195 / 272,426 / 314,560 / 371,608 / 143,324 model-vector cycles |
| PPU background integration | 1,075,191 fabric cycles, zero mismatches |
| Phase 6B | 1,237,500 timing pixels; 691,200 game pixels; two atomic swaps |
| Phase 6C | 10 exact frames, 24 profile writes, 256 EDID bytes |
| Phase 6D | 270,817 serializer cycles; 271,072 CDC cycles; 11,389 control cycles, zero mismatches |
| Phase 6D long run | Nominal and fitted-clock tests, each 10,000,019 source cycles, 9,600 generated / 9,596 consumed samples |
| Playable NES | 300 frames / 26,713,128 cycles |
| Production-top playable VGA | 83 frames / 68,880,005 cycles; 307,200 compared pixels |
| Developer Mode | 307,200 pixels, zero mismatches |
| Debugger | 132 frames, 187 commands and acknowledgements |

These are per-suite counts, not an aggregate of overlapping measurements.
Baseline production Quartus was freshly run, including HPS generation,
synthesis, fitting, assembly, SOF/RBF and all-corners timing. Reports are retained
in ignored `build/phase6e/baseline.*`; this is not a reused historical build.

## Official evidence and controller qualification

Reviewed source revisions and sections are recorded individually in JSON.

- [STUSB4500 datasheet, DS12499 Rev 8](https://www.st.com/resource/en/datasheet/stusb4500.pdf):
  autonomous sink, dead-battery support, three fixed sink PDOs, external switch
  control and VBUS monitoring. Default profiles are **5 V/1.5 A, 15 V/1.5 A,
  20 V/1 A**, not our intended policy. NVM customization and readback are
  mandatory before use. Proposed profiles are 5 V/3 A and 9 V/3 A, with the
  main path permitted only above 5 V. Higher profiles are excluded. VDD supply
  operation is required for VBUS monitoring; I2C access waits the documented
  maximum 30 ms NVM load interval after power-up/reset. RESET is active high;
  resetting a VBUS-powered controller can remove the system's power. The
  controller reports attach, power-path status and alerts; it does not replace
  an eFuse, reverse blocking, regulator protection or rail supervisor.
- [ST UM2650 Rev 3](https://www.st.com/resource/en/user_manual/um2650-the-stusb4500-software-programing-guide-stmicroelectronics.pdf):
  negotiation requires source capabilities, request, acceptance and PS_READY.
  Reviewed register addresses: ALERT `0x0b`, mask `0x0c`, connection `0x0e`,
  CC `0x11`, policy state `0x29`, PDO count `0x70`, RDO `0x91..0x94`.
  Alert status uses read-clear associated registers `0x0d`, `0x0f`, `0x12`,
  `0x16`; a future adapter must preserve events and reread pending alerts.
  RDO object position identifies a **source** PDO, not a same-index sink PDO.
  Fixed PDO voltage/current units are 50 mV/10 mA. An RDO or an ACK alone is
  insufficient evidence of a settled, usable supply.
- [USB-IF Type-C functional test specification, March 2024](https://www.usb.org/sites/default/files/USB%20Type%20C%20Functional%20Test%20Specification%202024%2003%2003.pdf):
  a sink observes CC current advertisement and VBUS; default USB power is not
  permission for 3 A. Type-C 1.5 A/3 A operation applies at 5 V; elevated
  voltage requires PD. Advertisement changes require corresponding load
  adjustment. Attach, debounce, detach, discharge and hard-reset behavior
  belong to the autonomous controller and power path.
  [The current publication page lists Type-C Release 2.5](https://www.usb.org/document-library/usb-type-cr-cable-and-connector-specification-release-25).
  Full latest-revision compliance review remains a release gate; this work is
  not USB-IF certification or a PD conformance implementation.

The programming guide is public; **register availability is not a gap**.
This phase deliberately implements a normalized status boundary, not an I2C
controller driver or NVM programmer. Physical wiring, controller silicon/NVM,
alert races, electrical thresholds, and the adapter that proves a coherent
contract remain unqualified. There are no invented register transactions in RTL.

## Contract and input-power policy

The inlet is a dedicated **sink-only power port**. It has no USB host/data-role,
Alt Mode, PPS, EPR, source, role-swap or 5 A policy in this implementation.
Separate USB host peripherals remain an HPS concern.

| Source/report | Logical treatment | Full operation |
|---|---|---|
| No attach | POWER_OFF, or observed SHUTDOWN after detach | Disabled |
| Default 5 V attach without established current | Wait for a qualified report; do not infer 500 mA or 3 A | Disabled |
| 5 V, advertised 1.5 A | Valid Type-C current report, insufficient budget | Disabled |
| 5 V, advertised 3 A or completed 5 V/3 A PD | Valid candidate fallback; insufficient budget | Disabled |
| Completed 9 V/3 A fixed PD, protected input | Selected full-load contract | May qualify startup |
| 9 V with less current | Reportable, below the selected full-load policy | Disabled |
| Other voltage, zero/excess current, malformed unit encoding | Unsupported/invalid project contract | Disabled |
| PD reject, negotiation timeout, live contract loss/change | Sticky fault and disable request | Disabled |

PD reports accept 5 V or 9 V and 10–3,000 mA in 10 mA steps. Non-PD reports
require exactly one established 1.5 A or 3 A CC level at 5 V. These are project
acceptance limits, not a claim that other USB PD contracts are intrinsically
illegal. A completed PD contract takes precedence over CC current advertisement.
`select_contract()` chooses 9 V/3 A only when offered, otherwise an offered
5 V/3 A standby candidate, otherwise none. The FPGA does not negotiate it.

The external power architecture must enforce the same policy **before FPGA
configuration**. An insufficient source cannot be expected to boot an FPGA
merely to display its own fault. Standby indications require an independently
budgeted external indicator/controller. RTL POWER_OFF/ATTACHED observations
are useful in simulation or with a separately powered observer.

## Power tree and budget

```text
USB-C receptacle (sink, CC/VBUS protection)
  -> autonomous STUSB4500-class controller + qualified NVM
  -> fuse/eFuse, OVP/UVLO/current limit, controlled slew, reverse blocking
  -> protected input + autonomous sequencer / rail supervisor
       -> 1.1 V FPGA core and 1.1 V HPS core
       -> 2.5 V AUX / AUX_SHARED / PLL supplies, VCCBAT option
       -> bank-specific VCCPD / VCCIO / configuration / HPS reset-clock
       -> DDR supply + tracking VTT / VREF as required by selected topology
       -> 1.8 V and 3.3 V HDMI supplies
       -> codec, clocks, microSD/QSPI, support rails
       -> regulated 5 V, separately limited USB/HDMI connector loads
  -> post-configuration normalized reports -> FPGA observer -> diagnostics
```

There is no final regulator, schematic, PCB, pin-bank assignment or BOM.
The supply upstream of cutoff must tolerate possible source faults and
misprogrammed higher SPR profiles; a nominal 9 V plan does not justify rating
unprotected components for only 9 V. Ratings, TVS coordination and cutoff
thresholds require component and transient analysis.

All following loads are **estimates**, including the peak column. The HDMI
anchor is approximately 257 mW typical in the
[ADV7513 datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/adv7513.pdf),
not a guaranteed maximum. FPGA/HPS values are not a Quartus Power Analyzer
result. Support includes controller, debug/LEDs, level shifting and an HDMI
connector 5 V allowance. USB assumes one aggregate 500 mA peak accessory load.
DDR includes termination; it is not counted again as a separate output load.

| Regulated load | Typical W | Peak allowance W |
|---|---:|---:|
| FPGA core | 2.20 | 3.10 |
| FPGA auxiliary | 0.30 | 0.40 |
| HPS core | 1.10 | 1.80 |
| HPS auxiliary | 0.10 | 0.20 |
| FPGA I/O excluding DDR | 0.30 | 0.50 |
| DDR including termination | 1.10 | 1.50 |
| HDMI transmitter | 0.30 | 0.45 |
| Audio codec | 0.15 | 0.30 |
| microSD and QSPI | 0.25 | 0.80 |
| USB peripherals | 0.50 | 2.50 |
| Clocks | 0.20 | 0.30 |
| Support | 0.40 | 0.70 |
| **Regulated outputs** | **6.90** | **12.55** |

Calculation uses exact rational arithmetic, rounding the final mW upward:

- Typical input: `6900 / 0.90 + 150 = 7816.667 mW`, rounded **7,817 mW**.
- Peak before margin: `12550 / 0.85 + 350 = 15114.706 mW`, rounded **15,115 mW**.
- Input design budget: `(12550 / 0.85 + 350) × 1.25 = 18893.382 mW`,
  rounded **18,894 mW**. Margin is applied once to the unrounded input estimate.
- Regulator losses: 0.767 W typical / 2.215 W peak. Separate distribution and
  protection allowances: 0.150 W / 0.350 W. These efficiencies/losses are
  assumptions requiring measurement across line, load and temperature.

Phase 6A's listed entries actually sum to 7.15 W typical and 11.25 W peak,
rounded to 7.2/11.3 W; `11.25 × 1.25 = 14.0625 W`, rounded to 14.1 W.
They exclude bus-powered accessories and do not separately identify the codec.
The new allocation explicitly includes these loads and recalculates losses;
it does not simply add losses to an already loss-inclusive 14.1 W number.

A conservative **design allowance**, not a measured cable guarantee, uses
95% nominal source voltage and another 500 mV cable/connector drop:

| Contract | Nominal capacity | Derated connector capacity | Versus 18.894 W |
|---|---:|---:|---|
| 5 V/3 A | 15 W | `(5000×.95−500)×3 = 12.75 W` | Insufficient |
| 9 V/3 A | 27 W | `(9000×.95−500)×3 = 24.15 W` | 5.256 W estimated headroom |

Even nominal 15 W is insufficient for the full design budget. The 5 V fallback
is therefore **disabled for full operation**, despite legal 3 A advertisement.
No reduced-load mode is implemented. The exact 9 V/3 A policy intentionally
does not qualify every intermediate current that might satisfy the arithmetic.

Startup is separate. An illustrative **470 uF behind a controlled switch**,
charged through a 9 V/20 ms linear ramp, gives `I=C×dV/dt=211.5 mA`, 1.9035 W
input charging power and 19.035 mJ stored energy. An ideal constant 9 V source
supplies twice that stored energy through a dissipative linear charge path.
This is not a selected capacitance, a compliance claim, or the silicon inrush
limit. Silicon startup peaks, bank transients, regulator soft-start and load
staging remain unknown. No guaranteed startup wattage is claimed.

## Provisional rails and reset dependencies

For the selected non-SC 5CSEMA5 baseline, the
[FPGA operating conditions](https://docs.altera.com/r/docs/683801/current/cyclone-v-device-datasheet/recommended-operating-conditions)
identify 1.1 V core and 2.5 V auxiliary/PLL supplies. VCCPD must match 3.3 V I/O,
or be 2.5 V for lower-voltage banks. VCCBAT must be powered; 2.5 V is a candidate
when volatile-key storage is unused. Supply ramps must be monotonic; standard
POR allows 200 us–100 ms, fast POR 200 us–4 ms. DC tolerance does not replace
PDN dynamic analysis.

The [HPS supply table](https://docs.altera.com/r/docs/683801/current/cyclone-v-device-datasheet/hps-power-supply-operating-conditions)
requires AUX_SHARED and AUX to share a source for SE A5. HPS core, PLL,
pre-driver, I/O and reset/clock supplies must all be accounted for.
[AN 796](https://docs.altera.com/r/docs/683360/18.0/an-796-cyclone-v-and-arria-v-soc-device-design-guidelines/device-power-up)
requires transient/PDN analysis with EPE and later activity-based power analysis.

The [power sequence recommendation](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/power-up-sequence-recommendation-for-cyclone-v-devices)
places Group 2 after Group 1 reaches at least 80%. Its documented startup
transients are conditional, not additive steady-state loads. **The exact
package pin-group assignment remains an explicit audit gate.** The dependencies
below are coarse proposed external qualification dependencies, not a final
silicon ramp sequence. The selected DDR3 Qsys voltage does not qualify a future
DDR3L part or a new board's memory power-up timing.

| Rail / group | Nominal / DC range mV | Typical / peak mA | Proposed dependency | Source |
|---|---|---|---|---|
| fpga_core | 1100 / 1070–1130 | 2000 / 2819 | protected input | fpga_supplies |
| hps_core | 1100 / 1070–1130 | 1000 / 1637 | protected input | hps_supplies |
| aux_2v5 | 2500 / 2375–2625 | 160 / 240 | protected input | hps_supplies |
| io_3v3 | 3300 / 3135–3465 | 91 / 152 | aux_2v5 | fpga_supplies |
| hps_reset_clock | 3300 / 3135–3465 | unknown split | aux_2v5 | hps_supplies |
| ddr_1v5 | 1500 / unqualified | unknown split | aux_2v5 | repository |
| ddr_vtt | 750 / unqualified | unknown split | ddr_1v5 | repository |
| ddr_vref | 750 / unqualified | unknown split | ddr_1v5 | repository |
| hdmi_1v8 | 1800 / 1710–1900 | unknown split | io_3v3 | hdmi |
| hdmi_3v3 | 3300 / 3150–3450 | unknown split | io_3v3 | hdmi |
| codec_3v3 | 3300 / unqualified | 46 / 91 | io_3v3 | codec_summary |
| microsd_3v3 | 3300 / unqualified | 76 / 243 | io_3v3 | repository |
| usb_5v | 5000 / unqualified | 100 / 500 | io_3v3 | repository |

Currents are rounded engineering allocations, not datasheet limits or regulator
ratings. The auxiliary row combines FPGA/HPS allowances. Unallocated small
supplies, DDR termination and HDMI split currents are explicitly unknown, so
this rail table must not be summed as an independently closed power budget.
Source identifiers resolve to exact references in JSON. The codec 3.3 V choice
is provisional; [Cirrus's summary](https://statics.cirrus.com/pubs/brochure/Cirrus_Product_Summary_Guide_November_2021.pdf)
confirms the candidate's general supply range, not a final sequencing design.

Every rail has machine-readable startup, enable, PGOOD and monitoring fields.
Common enable is an externally qualified input plus dependency interlocks;
PGOOD comes from suitable external supervisors with final thresholds, tolerance,
hysteresis and deglitching still to be selected. FPGA-visible digital PGOOD is
not an ADC voltage measurement. DDR VTT must track its reference and provide
required source/sink current; VREF loading/noise and DDR reset/CKE timing await
an exact memory topology and datasheet. No 1.35 V migration is made here.

Physical POR holds configuration and HPS resets until required rails and clocks
are valid. [The FPGA configuration guidance](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/power-up)
requires valid POR-monitored supplies and holding nCONFIG low if ramp conditions
are not met. HPS boot/DDR calibration and FPGA configuration must not depend on
permission from unconfigured FPGA RTL. Existing HPS boot/FPGA loading order is
preserved. There is no new FPGA output controlling its own initial reset.

After configuration, an external adapter reports configuration-ready, HPS-ready
and DDR-ready separately. HPS reset or DDR readiness loss removes permissions
and records a fault without erasing observer history. The existing diagnostic
MMIO reset rebases its mailbox without resetting the observer. Observer reset
clears its volatile counters/history and permissions deterministically. A total
power failure can destroy all FPGA state before detach is recorded; persistent
fault capture needs an external latch/logger and qualified hold-up energy.

## Supervisory RTL and CDC contract

Files are `rtl/power/usbc_power_supervisor.sv`, `usbc_power_status_cdc.sv` and
`phase6e_power_top.sv`. The top accepts a normalized, held 64-bit status report
from an **unimplemented external adapter**. All fields are active-high:

| Bits | Report |
|---|---|
| 0 / 1 | Attached / VBUS detected |
| 2 / 3 | Completed PD contract / current-contract decision complete |
| 4 / 5 | Established CC 3 A / 1.5 A, meaningful without PD |
| 6 | Input protection path good |
| 7 / 8 / 9 | FPGA configuration-ready / HPS-ready / DDR-ready |
| 10 / 11 | Video clock-ready / audio clock-ready |
| 15:12 | Four external rail-group PGOOD observations; all required for READY |
| 25:16 | External fault bits 9:0 from the table below |
| 31:26 | Reserved, must be zero |
| 47:32 / 63:48 | Reported nominal contract mV / allowed mA |

The four rail-group bits summarize externally qualified core/auxiliary,
I/O/configuration, DDR and peripheral supplies. RTL does not infer their analog
ramp order or control their enables. A later adapter must validate the external
sequencer's detailed dependencies before reporting these group statuses.

`source_valid/source_ready` transfers one stable report. A registered held-data
bank remains immutable until a request toggle traverses three destination
stages and acknowledgement traverses three source stages. Destination capture
produces a single-cycle `status_valid`. The source must retain short fault
pulses upstream and include them in a report; a slow mailbox is not fast fault
protection. Both sides share RESET_N and use asynchronous assertion/synchronous
release through `reset_sync`. Independent producer-only reset requires an
additional epoch protocol and is outside this interface contract.

The standalone SDC times 50 MHz supervision and a 25 MHz report interface,
with finite input/output budgets. Only first toggle synchronizer stages and
the external reset assertion source are cut. The held 64-bit bundle has a
20 ns maximum and 0 ns minimum bound; no whole clock-domain false path is added.
Simulation varies clock ratios, phase and deterministic edge jitter. It checks
functional coherence, not analog metastability probability or physical MTBF.

The supervisor processes fresh synchronous packets or its last coherent report.
A watchdog invalidates old observations. No asynchronous signal feeds a
combinational reset. Fast brownout/overcurrent/OVP protection and hardware mute
must act externally, even if either clock stops or the FPGA disappears.

State encodings are stable:

| Code | State | Exit / purpose |
|---:|---|---|
| 0 | POWER_OFF | Attached report starts observation |
| 1 | ATTACHED | Enter contract qualification |
| 2 | CONTRACT_PENDING | Sufficient valid report, or PD timeout/fault |
| 3 | CONTRACT_VALID | Wait for protected VBUS |
| 4 | INPUT_PROTECTED | Begin rail observation |
| 5 | RAILS_STARTING | Wait for all four external groups |
| 6 | RAILS_STABLE | Require continuous complete prerequisites |
| 7 | FPGA_RELEASE | Observational milestone only; emits no configuration reset |
| 8 | SYSTEM_READY | Complete current prerequisites; monitor for loss |
| 9 | FAULT | Disabled; explicit clear requests a recovery attempt |
| 10 | SHUTDOWN | One observation cycle after detach, then POWER_OFF |
| 11 | RECOVERY | Require stable healthy reports before repeating full startup; bounded timeout |

Default policy intervals at 50 MHz are PD wait 2 s, total observed startup 5 s,
recovery 1 s, stable qualification 5 ms and stale-report timeout 100 ms.
They are **observer policy**, not USB PD wire-protocol timers or regulator ramp
specifications. A valid contract at the PD deadline and a fresh report at the
watchdog deadline win over those timeout conditions. Complete healthy recovery
qualification wins at the recovery deadline. The total startup deadline has
fault priority; startup must have completed before that boundary.

Detach immediately removes synchronous permissions at the next observed packet,
records the event, passes through SHUTDOWN and returns to POWER_OFF. Reattach
repeats full qualification. An attached FAULT requires explicit clear to enter
RECOVERY; continued faults cannot be overridden and eventually time out.
Recovery counter counts attempts, not successful repairs. Sticky history may
remain after reattach; it is distinct from currently active conditions.

`system_ready` additionally checks captured prerequisites, fault inputs and
freshness. Video/audio power permissions require system-ready and their own
clock-ready reports. The existing HDMI/codec configuration, mute, FIFO prime
and sink checks would still be required by a future wrapper. These permissions
are not connected to gameplay, VGA, codec or HDMI behavior in this phase.
`downstream_disable_request` is the inverse readiness request, not an electrical
kill switch or a guarantee that physical rails have discharged.

## Protection and fault handling

Physical requirements include CC/VBUS ESD and surge protection, independent
OVP/UVLO, current limiting and short-circuit response, reverse-current blocking,
thermal shutdown, controlled inrush/discharge, regulator protection, rail
supervision and reset interlocks. Thresholds must be selected against actual
components, tolerances and accepted voltages; no fabricated thresholds are
programmed in this phase.

| Bit | Sticky fault | Detection |
|---:|---|---|
| 0 | VBUS_OVERVOLTAGE | external hardware |
| 1 | VBUS_UNDERVOLTAGE | external hardware |
| 2 | INPUT_OVERCURRENT | external hardware |
| 3 | SHORT_CIRCUIT | external hardware |
| 4 | REVERSE_CURRENT | external hardware |
| 5 | THERMAL_SHUTDOWN | external hardware |
| 6 | REGULATOR_FAULT | external hardware |
| 7 | RAIL_POWER_GOOD_LOSS | external hardware |
| 8 | PD_REJECTED | external hardware |
| 9 | BROWNOUT | external hardware |
| 10 | UNEXPECTED_DETACH | logical observation |
| 11 | INVALID_CONTRACT | logical observation |
| 12 | INSUFFICIENT_POWER | logical observation |
| 13 | PD_TIMEOUT | logical observation |
| 14 | STARTUP_TIMEOUT | logical observation |
| 15 | RECOVERY_TIMEOUT | logical observation |
| 16 | STALE_STATUS | logical observation |
| 17 | INVALID_STATUS | logical observation |
| 18 | CONFIGURATION_LOSS | logical observation |
| 19 | HPS_NOT_READY | logical observation |
| 20 | DDR_NOT_READY | logical observation |
| 21 | INVALID_STATE | logical observation |

Bits 0–9 are supplied by the external adapter, not synthesized comparators.
Rail/input PGOOD loss and configuration/HPS/DDR readiness loss are also detected
when leaving a previously READY condition. Reserved packet bits and illegal FSM
encoding fail closed. Fault history is OR-latched; clear applies **before**
current active conditions are ORed back. Clear does not reset counters. Fault
count increments once per cycle containing any newly active fault bit, so a
simultaneous fault combination is one event. Persistent faults and repeated
clear do not continuously increment the count. All three observer counters
saturate at `0xffffffff`; reduced test ceilings exercise the same saturation
logic. Existing Phase 5M wrapping-counter semantics are unchanged.

## Diagnostic extension

The existing aperture remains `0xff201000`, 512 bytes. Interface version is
**1.3**, build `0x0006000e`. Capability bit 8 advertises the power schema;
availability bit 14 is set only with `USBC_POWER_AVAILABLE=1`. It defaults
false and remains false in production. Existing registers/bits/commands retain
their meanings. CONTROL bit 7 requests one fabric-domain power fault-clear
pulse through the existing exactly-once mailbox.

The atomic snapshot expands from 93 to 106 internal words. New registers are:

| Offset | Register | Interpretation |
|---:|---|---|
| 12c | USBC_ATTACHED | Last reported attach |
| 130 | USBC_PD_CONTRACT_VALID | Attached, PD-active and decision complete as reported by adapter |
| 134 | USBC_NEGOTIATED_MV | Reported nominal/configured voltage, not ADC voltage |
| 138 | USBC_NEGOTIATED_MA | Allowed/contract current, not measured load current |
| 13c | USBC_INPUT_POWER_MW | Calculated nominal capacity (`mV×mA/1000`), not consumption or derated capacity |
| 140 | USBC_POWER_GOOD | Last reported VBUS and protected input |
| 144 | USBC_RAILS_READY | Last reported group PGOOD aggregate |
| 148 | USBC_STARTUP_STATE | State code above |
| 14c | USBC_FAULT_STATUS | Sticky bitmap |
| 150 | USBC_FAULT_COUNT | Saturating new-fault event count |
| 154 | USBC_DETACH_COUNT | Saturating observed detach count |
| 158 | USBC_RECOVERY_COUNT | Saturating attempted-recovery count |
| 15c | USBC_PROVENANCE | bit0 simulated, bit1 configured/reported, bit2 estimated/calculated |

Staleness is indicated by the watchdog fault/state; historical report fields
remain readable and must not be interpreted as fresh telemetry. The logical
project emits provenance 7. No measured-voltage/current/power field is supported.
Production reads zero for the entire unavailable bank and ignores clear.
The Python client labels availability/provenance and returns `None` for measured
voltage/current/power. Offline defaults report USB-C unavailable until explicit
simulated data is supplied. Physical USB-C is always NOT TESTED in the report.

## Independent verification

`verification/usbc_power.py` computes contracts, derated input capacity, rational
conversion/margin arithmetic, capacitor charging, external rail dependencies,
state deadlines, fault history/counters and diagnostic words. Its state model
uses absolute observation times and ordered prerequisite milestones rather than
copying the RTL elapsed counters. RTL current-unit validation uses hexadecimal
digit sums; Python uses ordinary `% 10`. Every possible 16-bit current encoding
is compared, in addition to scenario and seeded verification.

JSON validation checks units, numerical ranges, source/revision metadata,
required fields, duplicate IDs, power arithmetic, contract sufficiency, rail
references and dependency cycles, enum/fault encodings, timeouts, inrush
arithmetic and qualification state. Negative tests deliberately corrupt each
class of input. Null rail values explicitly identify qualification gaps.

Directed coverage includes no cable, default 5 V, both CC current levels,
5 V PD, 9 V PD, insufficient power, rejection, invalid voltage/current/units,
all ten external faults (OV, UV, OC, short, reverse, thermal, regulator, PGOOD,
PD reject, brownout), delayed rails, startup/PD/recovery timeouts, detach/reattach,
clear with active re-latch, successful recovery, FPGA reset during startup and
running, HPS/DDR/configuration loss, separate A/V clock gating, stale reports,
deadline refresh, saturating counters and illegal state. MMIO tests check all
13 words, atomic retention, subsequent snapshots, exactly-once clear, and the
unavailable production parameter. Existing regressions prove retained behavior.

`generate_usbc_power_vectors.py` emits ignored build vectors and per-case
metadata. Three deterministic random seeds vary attachment, contracts, rail
status, fault combinations, delays, reset, clear, stale reporting and recovery.
`usbc_power_tb` compares every complete diagnostic word and all enable requests
on every vector cycle. The separate mailbox test checks 4,000 transferred
64-bit reports across four shared reset epochs, four frequency relationships
and deterministic edge jitter. Four accepted in-flight packets are deliberately
cancelled by reset and are accounted for separately.

Reproduction:

```sh
PATH="$PWD/.venv/bin:$PATH" scripts/test.sh
PATH="$PWD/.venv/bin:$PATH" bash scripts/test_usbc_power.sh
PATH="$PWD/.venv/bin:$PATH" scripts/build_de1_soc_nes_vga_quartus.sh
bash scripts/build_phase6e_power_quartus.sh
```

Full and FAST simulation profiles include the new power tests. Existing tests
and warning policy remain intact. New production power RTL passes strict
Verilator `--Wall` lint. No simulation vector, waveform, vendor PDF or compiled
artifact is committed.

## Results

The complete post-change `scripts/test.sh` run exited successfully: **2,117
Python tests** (81 new), full Verilator lint, all retained RTL/model suites,
Phase 5K audio, Phase 5M diagnostics, Phase 6B video, Phase 6C transmitter,
Phase 6D HDMI audio, and debugger integration. Production and standalone
Quartus qualification also passed. The final run log is
`build/phase6e/final-tests-complete.log`; generated logs/artifacts remain ignored.

Retained comparison counts match the baseline table: playable NES 300 frames /
26,713,128 cycles, production VGA 83 frames / 68,880,005 cycles / 307,200 compared
pixels, Phase 6B 1,237,500 timing pixels / 691,200 game pixels, and debugger
132 frames / 187 commands / 187 acknowledgements. Phase 6D nominal/fitted-clock
long runs each cover 10,000,019 cycles with zero FIFO underruns/overruns. No
unexplained mismatch remains. Hardware behavior and USB-C electrical performance
remain NOT TESTED.

The focused Phase 6E comparison passed **242,269 cycles across 44 cases**, with
zero mismatches, all 12 states visited, exhaustive 65,536 current encodings,
and a separate illegal-state injection. The independent model uses absolute
deadlines and rational power arithmetic; RTL uses counters and bounded integer
logic. The fitted current-unit validator uses a six-bit digit sum; exhaustive
comparison checks it against Python remainder arithmetic.

| Random seed | Compared cycles | Transitions | New-fault events | Recovery attempts | Mismatches |
|---|---:|---:|---:|---:|---:|
| `0x6e202601` | 32,454 | 3,215 | 631 | 405 | 0 |
| `0x6e202602` | 33,220 | 3,378 | 654 | 436 | 0 |
| `0x6e202603` | 31,199 | 3,113 | 645 | 410 | 0 |

Random event totals accumulate across reset epochs; they are not the final
volatile counter readings. The CDC test passed seed `0x6ecd2026`: 32,893 source
edges, 30,461 destination edges, 4,004 accepted / 4,000 delivered reports, four
intentional reset cancellations, zero mismatches. Both available and unavailable
MMIO parameter configurations passed snapshot and command checks.

Standalone Quartus 23.1std.1 completed synthesis, fitting, assembly and all four
operating corners. It uses **640 ALMs, 712 logic ALUTs, 568 registers, zero M10Ks,
zero DSPs and zero PLLs**. Worst setup is **+5.977 ns**, hold **+0.095 ns**, minimum
pulse width **+9.064 ns**, TNS **0 ns**, and unconstrained setup/hold paths **0**.
The setup critical path is `supervisor|age[12]` to `SYSTEM_READY` (also the
disable output), slow 1.1 V/85 C. The hold critical path is mailbox
`held_data[36]` to `destination_data[36]`, fast 1.1 V/0 C. The reporting script
writes detailed setup/hold paths for each corner.

Standalone stage warnings are map **240**, fit **1**, assembly **0**, timing
**0**: 238 constant diagnostic output bits, their parent constant-output warning,
one intentionally unused observation wire, and the Lite LogicLock license
warning. There are no inferred latches, multiple drivers or timing violations.
Virtual ports and representative digital timing budgets do not qualify a PCB
interface or electrical protection response.

The production rebuild passed synthesis, fitting, assembly, SOF/RBF generation
and all-corners timing. Comparison against the freshly qualified Phase 6D merge:

| Production metric | Phase 6D baseline | Phase 6E | Change |
|---|---:|---:|---:|
| ALMs | 9,632 | 9,572 | −60 |
| Logic ALUTs | 12,965 | 12,946 | −19 |
| Total registers | 14,997 | 15,027 | +30 |
| Dedicated logic registers | 14,771 | 14,801 | +30 |
| M10Ks | 275 | 275 | 0 |
| Block memory bits | 2,238,504 | 2,238,504 | 0 |
| DSPs / PLLs | 7 / 2 | 7 / 2 | 0 |
| Worst setup slack, ns | +1.549 | +1.364 | −0.185 |
| Worst hold slack, ns | +0.065 | +0.077 | +0.012 |
| Recovery / removal, ns | +3.375 / +0.266 | +3.375 / +0.460 | non-negative |
| Minimum pulse width, ns | +0.608 | +0.608 | 0 |
| TNS, ns | 0 | 0 | 0 |
| Unconstrained setup / hold | 0 / 0 | 0 / 0 | 0 |
| Map / fit / assembly / timing warnings | 108 / 149 / 0 / 144 | 109 / 149 / 0 / 144 | +1 map |

The new production setup critical path is `developer_mode_enable~DUPLICATE`
to `VGA_G[1]`, slow 1.1 V/85 C. The minimum hold path is the generated HPS DDR
`dq_ddio[2]` LFIFO OCT register to `os_oct_ddio_oe~DFF`, fast 1.1 V/0 C.
Placement changes explain resource/slack variation; no gameplay data path or
production clock/pin/SDC constraint was changed. The supervisor is absent from
this physical target; its separate resource count must not be added to the
reported production utilization as if it were fitted there.

Production warnings remain the existing generated-HPS width/unused/implicit-net
and DDR constraint-filter families, PLL compensation, incomplete I/O assignments
and Lite LogicLock messages. The one additional map warning is **12158**, a
dangling `altera_mem_if_hhp_qseq_synth_top` in generated `hps_sdram.v`; it is not
a new power-interface pin or unconnected power observer. Map/fit/timing warning
instances total 402 versus 401 baseline; these stage totals are distinguished
from flow-level counters. Existing clock-uncertainty advisory messages are
retained. No timing constraints or warning policy were weakened.

## Physical verification plan and remaining gates

1. Freeze the exact SoC ordering code, POR/configuration mode, DDR device and
   topology. Audit every supply pin, VCCPD/VCCIO relationship, AUX_SHARED,
   VCCBAT, ramp group and HPS reset dependency against vendor documentation.
2. Replace estimates with EPE/Power Analyzer and DDR/vendor load calculations,
   including simultaneous HPS, FPGA, video/audio, microSD writes and USB loads;
   measure startup, transients and thermal/process extremes.
3. Qualify a PD controller/evaluation board and program/read back NVM. Exercise
   default-current, 1.5 A, 3 A and PD supplies; missing 9 V, rejection, malformed
   policy, reset, detach, rapid reattach, cable drop and advertisement changes.
4. Select and bench-test the input protection, reverse blocking, regulators,
   rail supervisors, current limits, slew, discharge and hold-up requirements.
   Inject OV/UV/OC/short/thermal faults with appropriate lab equipment and verify
   autonomous safety with FPGA/HPS clocks stopped or entirely unpowered.
5. Scope all rails and reset/configuration signals during ramp, brownout,
   hot-plug and recovery. Validate DDR calibration, boot and storage integrity.
6. Implement and qualify the normalized hardware adapter, including read-clear
   alert races, reported-source PDO decoding, stale heartbeat, reset epochs
   and provenance. Add calibrated ADC/current telemetry only if real hardware
   exists; retain explicit uncertainty and calibration metadata.
7. Verify downstream HDMI/codec mute and startup on hardware without audible
   or visual artifacts; simulate/scope power loss during SD activity. Persistent
   logs and graceful shutdown require proven available energy, not assumptions.
8. Complete USB-IF, electrical safety, ESD/EMI, thermal and source/cable
   interoperability testing against the applicable current specification set.

No regulator/BOM is finalized, no production PCB is designed or routed, and
no physical success is claimed. Phase 6F is not started.
