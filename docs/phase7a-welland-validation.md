# Phase 7A Welland hardware validation

**Status: not executed. The DE1-SoC is unavailable.** Simulation, synthesis
and static timing do not complete any item below. Record the operator, date,
board revision, Git SHA, SOF/RBF hashes, HPS handoff/boot image, Linux version,
monitor/cables, codec configuration and power supply with the results.

This checklist supplements, and does not supersede, the physical bring-up
obligations in [Phase 6G](phase6g-system-integration.md#physical-de1-soc-bring-up-plan-not-executed),
[HPS bridge](phase4f-f-hps-fpga-bridge.md#hardware-handoff-and-deliberate-limits),
[audio codec](apu-phase5k-audio-codec.md),
[HDMI transmitter](phase6c-hdmi-transmitter.md), and
[HDMI audio](phase6d-hdmi-audio.md).

| Check | Procedure and evidence | Status |
|---|---|---|
| Programming and boot | Program the reviewed production image using the established deployment procedure; verify its matching HPS handoff and DDR initialization. Record all image identities. | Pending |
| MMIO identity | Enable the existing lightweight bridge and read loader identity/version/capabilities and diagnostic identity/version. Preserve loader v1.0 and diagnostics v1.3 addresses and meanings. | Pending |
| Actual HPS loading | Load original NROM fixtures from the physical microSD/Linux filesystem through the real CLI and `/dev/mem` transport; record completion, activation and error status. | Pending |
| NROM-128 gameplay | Observe reset-vector boot, sustained animation, controller response and advancing CPU/PPU/DMA counters. A successful load alone is insufficient. | Pending |
| NROM-256 and CHR-RAM | Run a fixture that independently exercises both 16 KiB PRG halves and writes CHR-RAM; observe its expected program result and rendered image. | Pending |
| Mirroring | Exercise horizontal and vertical fixtures and inspect known nametable transitions. | Pending |
| VGA | Verify stable sync, normal image and Developer Mode image, borders, colors and continued raster during cartridge reset. Record monitor mode and captures. | Pending |
| WM8731 LINE OUT | Check codec initialization, nonzero gameplay audio, channel test tones, silence, replacement and reset recovery; inspect underrun/overrun counters. | Pending |
| Debugger and menu/library | Exercise run/pause/instruction-step/frame-step and library selection; verify acknowledgements, coherent cartridge metadata and stable display through replacements. | Pending |
| Replacement | Repeatedly alternate NROM-128/CHR-ROM and NROM-256/CHR-RAM, including while DMA/audio are active. Verify each new program boots and old debug/frame/audio state does not resume. | Pending |
| Invalid files | Reject unsupported mapper IDs, malformed headers and truncated files through normal CLI/library paths before MMIO writes; verify the running game is unaffected. | Pending |
| Interrupted raw transfer | Interrupt a valid transfer and inject invalid raw metadata through a controlled diagnostic host. Verify sticky error/hold, no partial-image execution, complete reload recovery and physical-reset fallback to legacy. No rollback is promised by the single runtime store. | Pending |
| Repeated reset | Exercise KEY0, bridge reset and rapid replacement/reload. Verify reset-vector restart, fresh snapshots/frame ownership and audio recovery without stale commands. | Pending |
| Signal stability | Inspect clock/reset release, VGA signals and codec I2S with appropriate instruments. Check prolonged operation, counter stability and absence of unexpected IRQ/NMI/DMA behavior. | Pending |
| Physical HDMI, if qualified hardware exists | Use the separate logical-target/carrier qualification procedure; verify RGB clock/sync/DE, EDID, hotplug/reconnect, PCM/I2S and measured A/V behavior. The production stock-board image does not establish HDMI availability. | Pending |
| Phase 6 power/video obligations | Retain power sequencing, fault/protection, carrier SI, compliance and USB-C decisions from Phases 6A–6G. The disconnected power observer and deferred DP path are not physical validation. | Pending |

Future mapper-specific cartridges remain deferred to their respective phases.
UxROM must later demonstrate switchable/fixed PRG banks; CNROM, CHR banks;
MMC1, serial writes/banking/mirroring/RAM policy; MMC3, bank modes, RAM
protection and IRQ timing. Phase 7A must continue to reject all four mapper
IDs and must not label those tests passed or begin their implementation.
