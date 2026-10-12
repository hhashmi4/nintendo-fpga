`timescale 1ns/1ps

// Phase 5M diagnostic collection and HPS MMIO slave. All counters and the
// bounded trace live in the independent 50 MHz fabric domain. The HPS domain
// receives only an explicitly requested bundled-data snapshot.
module nes_diagnostic_subsystem #(
    parameter integer CPU_STALL_LIMIT = 50_000_000,
    parameter integer VIDEO_STALL_LIMIT = 100_000_000,
    parameter integer DMA_TIMEOUT_LIMIT = 1_000_000,
    parameter integer LOADER_TIMEOUT_LIMIT = 250_000_000,
    parameter bit HDMI_AUDIO_AVAILABLE = 1'b0
) (
    input  logic        fabric_clk,
    input  logic        fabric_reset,
    input  logic        system_reset,
    input  logic        nes_reset,
    input  logic        hps_bridge_reset,
    input  logic        runtime_replacement,
    input  logic        video_pll_locked,
    input  logic        audio_pll_locked,

    input  logic        cpu_cycle_event,
    input  logic        cpu_progress_event,
    input  logic        cpu_stalled,
    input  logic        cpu_irq,
    input  logic        cpu_nmi_event,
    input  logic [15:0] cpu_pc,
    input  logic        debugger_paused,
    input  logic        debugger_step_event,

    input  logic        ppu_frame_event,
    input  logic [8:0]  ppu_scanline,
    input  logic [8:0]  ppu_dot,
    input  logic        ppu_frame_odd,
    input  logic        ppu_nmi_level,
    input  logic        ppu_nmi_event,

    input  logic        vga_frame_toggle_async,
    input  logic        vga_hsync_toggle_async,
    input  logic        vga_vsync_toggle_async,
    input  logic        vga_active_async,
    input  logic        video_capture_active,
    input  logic        video_capture_pending,
    input  logic        video_display_valid_async,
    input  logic        video_write_range_error,
    input  logic        video_write_sequence_error,

    // Phase 6C controller-domain observations.  The HDMI controller already
    // synchronizes HPD, pixel-lock, and frame toggles into fabric_clk.
    input  logic        hdmi_transmitter_present,
    input  logic        hdmi_transmitter_configured,
    input  logic        hdmi_transmitter_fault,
    input  logic [1:0]  hdmi_hpd_state,
    input  logic        hdmi_edid_valid,
    input  logic        hdmi_mode_supported,
    input  logic        hdmi_video_clock_locked,
    input  logic        hdmi_video_enabled,
    input  logic [3:0]  hdmi_startup_state,
    input  logic [31:0] hdmi_video_frames,
    input  logic [31:0] hdmi_i2c_nacks,
    input  logic [31:0] hdmi_i2c_timeouts,
    input  logic [31:0] hdmi_recoveries,
    input  logic [7:0]  hdmi_last_error,

    // Phase 6D HDMI-audio status is already synchronized/counted in the
    // 50 MHz controller domain; it joins the same atomic snapshot bundle.
    input  logic        hdmi_audio_enabled,
    input  logic        hdmi_audio_configured,
    input  logic        hdmi_audio_muted,
    input  logic        hdmi_audio_clock_locked,
    input  logic        hdmi_audio_fault,
    input  logic [3:0]  hdmi_audio_state,
    input  logic [31:0] hdmi_audio_sample_count,
    input  logic [15:0] hdmi_audio_fifo_occupancy,
    input  logic [31:0] hdmi_audio_fifo_underruns,
    input  logic [31:0] hdmi_audio_fifo_overruns,
    input  logic [31:0] hdmi_audio_reconnect_count,
    input  logic [7:0]  hdmi_audio_last_error,
    output logic        hdmi_audio_fault_clear,

    input  logic        apu_cycle_event,
    input  logic        codec_init_busy,
    input  logic        codec_init_done,
    input  logic        codec_init_error,
    input  logic [31:0] audio_codec_acks,
    input  logic [31:0] audio_codec_nacks,
    input  logic [31:0] audio_codec_timeouts,
    input  logic [31:0] audio_codec_retries,
    input  logic [31:0] audio_mixed_samples,
    input  logic [31:0] audio_pcm_samples,
    input  logic [31:0] audio_i2s_frames,
    input  logic [15:0] audio_fifo_occupancy,
    input  logic [31:0] audio_fifo_underruns,
    input  logic [31:0] audio_fifo_overruns,
    input  logic        audio_muted,
    input  logic [7:0]  audio_last_fault,

    input  logic [1:0]  loader_state,
    input  logic        loader_busy,
    input  logic        loader_image_valid,
    input  logic        loader_runtime_active,
    input  logic        loader_hold_reset,
    input  logic        loader_error,
    input  logic [3:0]  loader_error_code,
    input  logic        loader_command_accepted,
    input  logic [1:0]  loader_command,
    input  logic [1:0]  loader_target,
    input  logic        loader_activation_accepted,

    input  logic        oam_dma_active,
    input  logic        oam_dma_start,
    input  logic        oam_dma_complete,
    input  logic        dmc_dma_request,
    input  logic        dmc_dma_acknowledge,
    input  logic [2:0]  dma_bus_owner,

    input  logic        cartridge_present,
    input  logic [7:0]  cartridge_mapper,
    input  logic        cartridge_nrom_256,
    input  logic        cartridge_chr_is_ram,
    input  logic [1:0]  cartridge_mirroring,

    // Simulation-only deterministic fault stimuli. Production ties this low.
    input  logic [9:0]  fault_inject,

    input  logic        mmio_clk,
    input  logic        mmio_reset,
    input  logic [8:0]  avs_address,
    input  logic        avs_read,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    input  logic [3:0]  avs_byteenable,
    output logic        avs_waitrequest,
    output logic [31:0] avs_readdata,
    output logic        avs_readdatavalid
);
    import nes_diagnostic_mmio_pkg::*;

    localparam integer SNAPSHOT_WORDS = 93;
    localparam integer TRACE_WORD_BASE = 48;

    logic [31:0] snapshot_source_bank [0:SNAPSHOT_WORDS-1];
    logic [31:0] snapshot_mmio_bank [0:SNAPSHOT_WORDS-1];
    logic [31:0] trace_timestamp [0:DIAG_TRACE_DEPTH-1];
    logic [31:0] trace_header [0:DIAG_TRACE_DEPTH-1];

    logic [31:0] control_source_bank, clear_mask_source_bank;
    logic [31:0] control_mmio_bank, clear_mask_mmio_bank;
    logic request_toggle_mmio, acknowledge_toggle_source;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] acknowledge_sync;
    logic pending_snapshot, snapshot_valid, command_rejected;
    logic command_capture_pending;
    logic [31:0] snapshot_sequence, mmio_heartbeat;
    logic [3:0] trace_read_index;
    logic command_busy;

    logic [31:0] fabric_heartbeat;
    logic [31:0] cpu_cycles, cpu_stall_cycles, irq_events, nmi_events;
    logic [31:0] debug_events, ppu_frames, ppu_nmi_events, apu_cycles;
    logic [31:0] vga_frames, vga_hsync_events, vga_vsync_events;
    logic [31:0] loader_prg_transfers, loader_chr_transfers;
    logic [31:0] loader_activations, loader_errors;
    logic [31:0] oam_completed, dmc_completed, dma_arbitration_waits;
    logic [31:0] dma_stalled_requests;
    logic [31:0] loader_elapsed, cpu_idle_elapsed, video_elapsed, dma_elapsed;
    logic [31:0] fault_flags;
    logic [7:0] last_fault, reset_cause;
    logic [31:0] trace_overflow;
    logic [4:0] trace_count;
    logic [3:0] trace_write_index;
    logic trace_armed, trace_triggered, trace_frozen;

    logic previous_system_reset, previous_hps_bridge_reset;
    logic previous_runtime_replacement, previous_cpu_irq;
    logic previous_debugger_paused, previous_loader_error;
    logic previous_dmc_request, previous_codec_error;
    logic [31:0] previous_nacks, previous_timeouts;
    logic [31:0] previous_underruns, previous_overruns;
    logic video_pll_seen, audio_pll_seen;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] vga_frame_sync, vga_hsync_sync, vga_vsync_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] vga_active_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] video_display_valid_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] video_pll_lock_sync, audio_pll_lock_sync;
    logic previous_video_pll_locked;
    logic vga_frame_event, vga_hsync_event, vga_vsync_event;
    logic video_pll_locked_fabric, audio_pll_locked_fabric;

    logic [31:0] detected_faults;
    logic [7:0] detected_fault_code;
    logic trace_event_valid;
    logic [7:0] trace_event_code;
    logic [23:0] trace_event_payload;
    logic new_fault;
    integer index;

    assign command_busy = request_toggle_mmio != acknowledge_sync[2];
    assign avs_waitrequest = 1'b0;
    assign vga_frame_event = vga_frame_sync[2] ^ vga_frame_sync[1];
    assign vga_hsync_event = vga_hsync_sync[2] ^ vga_hsync_sync[1];
    assign vga_vsync_event = vga_vsync_sync[2] ^ vga_vsync_sync[1];
    assign video_pll_locked_fabric = video_pll_lock_sync[1];
    assign audio_pll_locked_fabric = audio_pll_lock_sync[1];

    always_comb begin
        detected_faults = {22'd0, fault_inject};
        if ((video_pll_seen && !video_pll_locked_fabric) ||
            (audio_pll_seen && !audio_pll_locked_fabric))
            detected_faults[DIAG_FAULT_CLOCK_UNLOCKED_BIT] = 1'b1;
        if ((audio_codec_nacks != previous_nacks) && codec_init_error)
            detected_faults[DIAG_FAULT_CODEC_INIT_NACK_BIT] = 1'b1;
        if ((audio_codec_timeouts != previous_timeouts) && codec_init_error)
            detected_faults[DIAG_FAULT_CODEC_INIT_TIMEOUT_BIT] = 1'b1;
        if (audio_fifo_underruns != previous_underruns)
            detected_faults[DIAG_FAULT_AUDIO_FIFO_UNDERRUN_BIT] = 1'b1;
        if (audio_fifo_overruns != previous_overruns)
            detected_faults[DIAG_FAULT_AUDIO_FIFO_OVERRUN_BIT] = 1'b1;
        if (loader_busy && loader_elapsed == LOADER_TIMEOUT_LIMIT - 1)
            detected_faults[DIAG_FAULT_LOADER_TIMEOUT_BIT] = 1'b1;
        if (loader_error && loader_error_code >= 4'd7)
            detected_faults[DIAG_FAULT_INVALID_CARTRIDGE_BIT] = 1'b1;
        if (!nes_reset && !debugger_paused && !oam_dma_active &&
            !dmc_dma_request && cpu_idle_elapsed == CPU_STALL_LIMIT - 1)
            detected_faults[DIAG_FAULT_CPU_STALL_TIMEOUT_BIT] = 1'b1;
        if (!system_reset && video_pll_locked_fabric &&
            video_elapsed == VIDEO_STALL_LIMIT - 1)
            detected_faults[DIAG_FAULT_VIDEO_HEARTBEAT_TIMEOUT_BIT] = 1'b1;
        if ((oam_dma_active || dmc_dma_request) &&
            dma_elapsed == DMA_TIMEOUT_LIMIT - 1)
            detected_faults[DIAG_FAULT_DMA_TRANSACTION_TIMEOUT_BIT] = 1'b1;

        detected_fault_code = 8'd0;
        if (detected_faults[DIAG_FAULT_DMA_TRANSACTION_TIMEOUT_BIT])
            detected_fault_code = DIAG_FAULT_DMA_TRANSACTION_TIMEOUT;
        if (detected_faults[DIAG_FAULT_VIDEO_HEARTBEAT_TIMEOUT_BIT])
            detected_fault_code = DIAG_FAULT_VIDEO_HEARTBEAT_TIMEOUT;
        if (detected_faults[DIAG_FAULT_CPU_STALL_TIMEOUT_BIT])
            detected_fault_code = DIAG_FAULT_CPU_STALL_TIMEOUT;
        if (detected_faults[DIAG_FAULT_INVALID_CARTRIDGE_BIT])
            detected_fault_code = DIAG_FAULT_INVALID_CARTRIDGE;
        if (detected_faults[DIAG_FAULT_LOADER_TIMEOUT_BIT])
            detected_fault_code = DIAG_FAULT_LOADER_TIMEOUT;
        if (detected_faults[DIAG_FAULT_AUDIO_FIFO_OVERRUN_BIT])
            detected_fault_code = DIAG_FAULT_AUDIO_FIFO_OVERRUN;
        if (detected_faults[DIAG_FAULT_AUDIO_FIFO_UNDERRUN_BIT])
            detected_fault_code = DIAG_FAULT_AUDIO_FIFO_UNDERRUN;
        if (detected_faults[DIAG_FAULT_CODEC_INIT_TIMEOUT_BIT])
            detected_fault_code = DIAG_FAULT_CODEC_INIT_TIMEOUT;
        if (detected_faults[DIAG_FAULT_CODEC_INIT_NACK_BIT])
            detected_fault_code = DIAG_FAULT_CODEC_INIT_NACK;
        if (detected_faults[DIAG_FAULT_CLOCK_UNLOCKED_BIT])
            detected_fault_code = DIAG_FAULT_CLOCK_UNLOCKED;
    end

    assign new_fault = |(detected_faults & ~fault_flags);

    // One trace entry is accepted per fabric cycle. The fixed priority is
    // part of the interface: reset/failure events precede activity events.
    always_comb begin
        trace_event_valid = 1'b0;
        trace_event_code = 8'd0;
        trace_event_payload = 24'd0;
        if ((previous_video_pll_locked && !video_pll_locked_fabric) ||
            (system_reset && !previous_system_reset) ||
            (hps_bridge_reset && !previous_hps_bridge_reset) ||
            (runtime_replacement && !previous_runtime_replacement)) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_RESET;
            if (previous_video_pll_locked && !video_pll_locked_fabric)
                trace_event_payload = {16'd0, DIAG_RESET_VIDEO_PLL_UNLOCK};
            else if (system_reset)
                trace_event_payload = {16'd0, DIAG_RESET_EXTERNAL_BUTTON};
            else if (hps_bridge_reset)
                trace_event_payload = {16'd0, DIAG_RESET_HPS_BRIDGE_RESET};
            else
                trace_event_payload = {16'd0, DIAG_RESET_RUNTIME_REPLACEMENT};
        end else if (codec_init_error && !previous_codec_error) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_CODEC_FAILURE;
            trace_event_payload = {16'd0, audio_last_fault};
        end else if (audio_fifo_underruns != previous_underruns) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_FIFO_UNDERRUN;
            trace_event_payload = audio_fifo_underruns[23:0];
        end else if (audio_fifo_overruns != previous_overruns) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_FIFO_OVERRUN;
            trace_event_payload = audio_fifo_overruns[23:0];
        end else if (loader_error && !previous_loader_error) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_LOADER_ERROR;
            trace_event_payload = {20'd0, loader_error_code};
        end else if (new_fault) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_FAULT;
            trace_event_payload = {16'd0, detected_fault_code};
        end else if (loader_activation_accepted) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_CARTRIDGE_ACTIVATED;
            trace_event_payload = {16'd0, cartridge_mapper};
        end else if (oam_dma_start) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_OAM_DMA_START;
        end else if (oam_dma_complete) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_OAM_DMA_COMPLETE;
        end else if (dmc_dma_request && !previous_dmc_request) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_DMC_DMA_REQUEST;
        end else if (dmc_dma_acknowledge) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_DMC_DMA_COMPLETE;
        end else if (cpu_nmi_event || ppu_nmi_event) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_NMI;
            trace_event_payload = {8'd0, cpu_pc};
        end else if (cpu_irq && !previous_cpu_irq) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_IRQ;
            trace_event_payload = {8'd0, cpu_pc};
        end else if (debugger_paused && !previous_debugger_paused) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_DEBUGGER_PAUSE;
            trace_event_payload = {8'd0, cpu_pc};
        end else if (!debugger_paused && previous_debugger_paused) begin
            trace_event_valid = 1'b1;
            trace_event_code = DIAG_EVENT_DEBUGGER_RESUME;
            trace_event_payload = {8'd0, cpu_pc};
        end
    end

    always_ff @(posedge fabric_clk) begin
        if (fabric_reset) begin
            hdmi_audio_fault_clear <= 1'b0;
            request_sync <= '0;
            acknowledge_toggle_source <= 1'b0;
            control_source_bank <= '0;
            clear_mask_source_bank <= '0;
            command_capture_pending <= 1'b0;
            vga_frame_sync <= '0;
            vga_hsync_sync <= '0;
            vga_vsync_sync <= '0;
            vga_active_sync <= '0;
            video_display_valid_sync <= '0;
            video_pll_lock_sync <= '0;
            audio_pll_lock_sync <= '0;
            fabric_heartbeat <= '0;
            cpu_cycles <= '0;
            cpu_stall_cycles <= '0;
            irq_events <= '0;
            nmi_events <= '0;
            debug_events <= '0;
            ppu_frames <= '0;
            ppu_nmi_events <= '0;
            apu_cycles <= '0;
            vga_frames <= '0;
            vga_hsync_events <= '0;
            vga_vsync_events <= '0;
            loader_prg_transfers <= '0;
            loader_chr_transfers <= '0;
            loader_activations <= '0;
            loader_errors <= '0;
            oam_completed <= '0;
            dmc_completed <= '0;
            dma_arbitration_waits <= '0;
            dma_stalled_requests <= '0;
            loader_elapsed <= '0;
            cpu_idle_elapsed <= '0;
            video_elapsed <= '0;
            dma_elapsed <= '0;
            fault_flags <= '0;
            last_fault <= '0;
            reset_cause <= DIAG_RESET_POWER_ON;
            trace_overflow <= '0;
            trace_count <= '0;
            trace_write_index <= '0;
            trace_armed <= 1'b0;
            trace_triggered <= 1'b0;
            trace_frozen <= 1'b0;
            previous_system_reset <= 1'b1;
            previous_hps_bridge_reset <= 1'b0;
            previous_runtime_replacement <= 1'b0;
            previous_cpu_irq <= 1'b0;
            previous_debugger_paused <= 1'b0;
            previous_loader_error <= 1'b0;
            previous_dmc_request <= 1'b0;
            previous_codec_error <= 1'b0;
            previous_nacks <= '0;
            previous_timeouts <= '0;
            previous_underruns <= '0;
            previous_overruns <= '0;
            video_pll_seen <= 1'b0;
            audio_pll_seen <= 1'b0;
            previous_video_pll_locked <= 1'b0;
            for (index = 0; index < DIAG_TRACE_DEPTH; index = index + 1) begin
                trace_timestamp[index] <= '0;
                trace_header[index] <= '0;
            end
            for (index = 0; index < SNAPSHOT_WORDS; index = index + 1)
                snapshot_source_bank[index] <= '0;
        end else begin
            hdmi_audio_fault_clear <= 1'b0;
            request_sync <= {request_sync[1:0], request_toggle_mmio};
            vga_frame_sync <= {vga_frame_sync[1:0], vga_frame_toggle_async};
            vga_hsync_sync <= {vga_hsync_sync[1:0], vga_hsync_toggle_async};
            vga_vsync_sync <= {vga_vsync_sync[1:0], vga_vsync_toggle_async};
            vga_active_sync <= {vga_active_sync[0], vga_active_async};
            video_display_valid_sync <= {video_display_valid_sync[0],
                                         video_display_valid_async};
            video_pll_lock_sync <= {video_pll_lock_sync[0], video_pll_locked};
            audio_pll_lock_sync <= {audio_pll_lock_sync[0], audio_pll_locked};
            fabric_heartbeat <= fabric_heartbeat + 1'b1;
            previous_system_reset <= system_reset;
            previous_hps_bridge_reset <= hps_bridge_reset;
            previous_runtime_replacement <= runtime_replacement;
            previous_cpu_irq <= cpu_irq;
            previous_debugger_paused <= debugger_paused;
            previous_loader_error <= loader_error;
            previous_dmc_request <= dmc_dma_request;
            previous_codec_error <= codec_init_error;
            previous_nacks <= audio_codec_nacks;
            previous_timeouts <= audio_codec_timeouts;
            previous_underruns <= audio_fifo_underruns;
            previous_overruns <= audio_fifo_overruns;
            previous_video_pll_locked <= video_pll_locked_fabric;
            if (video_pll_locked_fabric)
                video_pll_seen <= 1'b1;
            if (audio_pll_locked_fabric)
                audio_pll_seen <= 1'b1;

            if (cpu_cycle_event)
                cpu_cycles <= cpu_cycles + 1'b1;
            if (cpu_stalled)
                cpu_stall_cycles <= cpu_stall_cycles + 1'b1;
            if (cpu_irq && !previous_cpu_irq)
                irq_events <= irq_events + 1'b1;
            if (cpu_nmi_event)
                nmi_events <= nmi_events + 1'b1;
            if (debugger_step_event ||
                (debugger_paused != previous_debugger_paused))
                debug_events <= debug_events + 1'b1;
            if (ppu_frame_event)
                ppu_frames <= ppu_frames + 1'b1;
            if (ppu_nmi_event)
                ppu_nmi_events <= ppu_nmi_events + 1'b1;
            if (apu_cycle_event)
                apu_cycles <= apu_cycles + 1'b1;
            if (vga_frame_event)
                vga_frames <= vga_frames + 1'b1;
            if (vga_hsync_event)
                vga_hsync_events <= vga_hsync_events + 1'b1;
            if (vga_vsync_event)
                vga_vsync_events <= vga_vsync_events + 1'b1;
            if (loader_command_accepted && loader_command == 2'd1 &&
                loader_target == 2'd1)
                loader_prg_transfers <= loader_prg_transfers + 1'b1;
            if (loader_command_accepted && loader_command == 2'd1 &&
                loader_target == 2'd2)
                loader_chr_transfers <= loader_chr_transfers + 1'b1;
            if (loader_activation_accepted)
                loader_activations <= loader_activations + 1'b1;
            if (loader_error && !previous_loader_error)
                loader_errors <= loader_errors + 1'b1;
            if (oam_dma_complete)
                oam_completed <= oam_completed + 1'b1;
            if (dmc_dma_acknowledge)
                dmc_completed <= dmc_completed + 1'b1;
            if (cpu_cycle_event && (oam_dma_active || dmc_dma_request))
                dma_arbitration_waits <= dma_arbitration_waits + 1'b1;
            if (dmc_dma_request && !dmc_dma_acknowledge)
                dma_stalled_requests <= dma_stalled_requests + 1'b1;

            if (loader_busy)
                loader_elapsed <= loader_elapsed + 1'b1;
            else
                loader_elapsed <= '0;
            if (nes_reset || debugger_paused || oam_dma_active ||
                dmc_dma_request || cpu_progress_event)
                cpu_idle_elapsed <= '0;
            else
                cpu_idle_elapsed <= cpu_idle_elapsed + 1'b1;
            if (system_reset || !video_pll_locked_fabric || vga_frame_event)
                video_elapsed <= '0;
            else
                video_elapsed <= video_elapsed + 1'b1;
            if (oam_dma_active || dmc_dma_request)
                dma_elapsed <= dma_elapsed + 1'b1;
            else
                dma_elapsed <= '0;

            // Record every independently observable reset source. Functional
            // replacement and HPS bridge reset do not assert system_reset, so
            // their rising edges must be recognized directly.
            if (previous_video_pll_locked && !video_pll_locked_fabric) begin
                reset_cause <= DIAG_RESET_VIDEO_PLL_UNLOCK;
            end else if (system_reset && !previous_system_reset) begin
                reset_cause <= DIAG_RESET_EXTERNAL_BUTTON;
            end else if (hps_bridge_reset && !previous_hps_bridge_reset) begin
                reset_cause <= DIAG_RESET_HPS_BRIDGE_RESET;
            end else if (runtime_replacement &&
                         !previous_runtime_replacement) begin
                reset_cause <= DIAG_RESET_RUNTIME_REPLACEMENT;
            end

            if (|detected_faults) begin
                fault_flags <= fault_flags | detected_faults;
                last_fault <= detected_fault_code;
            end

            if (trace_armed && !trace_frozen && trace_event_valid) begin
                trace_timestamp[trace_write_index] <= fabric_heartbeat;
                trace_header[trace_write_index] <= {
                    trace_event_code, trace_event_payload
                };
                trace_write_index <= trace_write_index + 1'b1;
                if (trace_count < 5'(DIAG_TRACE_DEPTH))
                    trace_count <= trace_count + 1'b1;
                else
                    trace_overflow <= trace_overflow + 1'b1;
            end
            if (trace_armed && new_fault) begin
                trace_armed <= 1'b0;
                trace_triggered <= 1'b1;
                trace_frozen <= 1'b1;
            end

            // The HPS bridge can reset without resetting diagnostic state.
            // Reset only the mailbox epoch in both clock domains so a stale
            // toggle cannot leave the next command permanently busy.
            if (hps_bridge_reset) begin
                request_sync <= '0;
                acknowledge_toggle_source <= 1'b0;
                control_source_bank <= '0;
                clear_mask_source_bank <= '0;
                command_capture_pending <= 1'b0;
            end else begin
                if (request_sync[2] != acknowledge_toggle_source &&
                    !command_capture_pending) begin
                    control_source_bank <= control_mmio_bank;
                    clear_mask_source_bank <= clear_mask_mmio_bank;
                    command_capture_pending <= 1'b1;
                end
                if (command_capture_pending) begin
                    command_capture_pending <= 1'b0;
                    hdmi_audio_fault_clear <=
                        control_source_bank[DIAG_CONTROL_HDMI_AUDIO_FAULT_CLEAR_BIT];
                if (control_source_bank[DIAG_CONTROL_FAULT_CLEAR_BIT]) begin
                    fault_flags <= (fault_flags & ~clear_mask_source_bank) |
                                   detected_faults;
                    if ((fault_flags & ~clear_mask_source_bank) == 0 &&
                        detected_faults == 0)
                        last_fault <= 8'd0;
                end
                if (control_source_bank[DIAG_CONTROL_TRACE_CLEAR_BIT]) begin
                    trace_count <= '0;
                    trace_write_index <= '0;
                    trace_overflow <= '0;
                    trace_triggered <= 1'b0;
                    trace_frozen <= 1'b0;
                    for (index = 0; index < DIAG_TRACE_DEPTH;
                         index = index + 1) begin
                        trace_timestamp[index] <= '0;
                        trace_header[index] <= '0;
                    end
                end
                if (control_source_bank[DIAG_CONTROL_TRACE_ARM_BIT]) begin
                    trace_armed <= 1'b1;
                    trace_triggered <= 1'b0;
                    trace_frozen <= 1'b0;
                end
                if (control_source_bank[DIAG_CONTROL_TRACE_TRIGGER_BIT]) begin
                    trace_armed <= 1'b0;
                    trace_triggered <= 1'b1;
                    trace_frozen <= 1'b1;
                end
                if (control_source_bank[DIAG_CONTROL_TRACE_FREEZE_BIT]) begin
                    trace_armed <= 1'b0;
                    trace_frozen <= 1'b1;
                end
                if (control_source_bank[DIAG_CONTROL_SNAPSHOT_BIT]) begin
                    snapshot_source_bank[0] <= {24'd0, reset_cause};
                    snapshot_source_bank[1] <= {26'd0, |fault_flags,
                        loader_runtime_active, cartridge_present,
                        debugger_paused, nes_reset, system_reset};
                    snapshot_source_bank[2] <= {27'd0, vga_frame_event,
                        audio_pll_seen, video_pll_seen,
                        audio_pll_locked_fabric, video_pll_locked_fabric};
                    snapshot_source_bank[3] <= {27'd0,
                        debugger_step_event, debugger_paused, cpu_irq,
                        cpu_stalled, nes_reset};
                    snapshot_source_bank[4] <= cpu_cycles;
                    snapshot_source_bank[5] <= cpu_stall_cycles;
                    snapshot_source_bank[6] <= irq_events;
                    snapshot_source_bank[7] <= nmi_events;
                    snapshot_source_bank[8] <= debug_events;
                    snapshot_source_bank[9] <= {16'd0, cpu_pc};
                    snapshot_source_bank[10] <= {12'd0, ppu_frame_odd,
                        ppu_nmi_level, ppu_scanline, ppu_dot};
                    snapshot_source_bank[11] <= ppu_frames;
                    snapshot_source_bank[12] <= ppu_nmi_events;
                    // Bits 4:0 retain the Phase 5M meaning. Phase 6B uses
                    // formerly reserved bits for safe framebuffer status;
                    // only the display-valid level requires synchronization.
                    snapshot_source_bank[13] <= {22'd0,
                        video_write_sequence_error,
                        video_write_range_error,
                        video_display_valid_sync[1],
                        video_capture_pending, video_capture_active,
                        vga_active_sync[1], vga_vsync_event,
                        vga_hsync_event, vga_frame_event,
                        video_pll_locked_fabric};
                    snapshot_source_bank[14] <= vga_frames;
                    snapshot_source_bank[15] <= vga_hsync_events;
                    snapshot_source_bank[16] <= vga_vsync_events;
                    snapshot_source_bank[17] <= {30'd0, cpu_irq,
                        apu_cycle_event};
                    snapshot_source_bank[18] <= apu_cycles;
                    snapshot_source_bank[19] <= {26'd0, audio_muted,
                        codec_init_error, codec_init_done, codec_init_busy,
                        audio_pll_seen, audio_pll_locked_fabric};
                    snapshot_source_bank[20] <= audio_mixed_samples;
                    snapshot_source_bank[21] <= audio_pcm_samples;
                    snapshot_source_bank[22] <= audio_i2s_frames;
                    snapshot_source_bank[23] <= {16'd0,
                        audio_fifo_occupancy};
                    snapshot_source_bank[24] <= audio_fifo_underruns;
                    snapshot_source_bank[25] <= audio_fifo_overruns;
                    snapshot_source_bank[26] <= audio_codec_acks;
                    snapshot_source_bank[27] <= audio_codec_nacks;
                    snapshot_source_bank[28] <= audio_codec_timeouts;
                    snapshot_source_bank[29] <= audio_codec_retries;
                    snapshot_source_bank[30] <= {24'd0, audio_last_fault};
                    snapshot_source_bank[31] <= {21'd0,
                        loader_error_code, loader_error, loader_hold_reset,
                        loader_runtime_active, loader_image_valid,
                        loader_busy, loader_state};
                    snapshot_source_bank[32] <= loader_prg_transfers;
                    snapshot_source_bank[33] <= loader_chr_transfers;
                    snapshot_source_bank[34] <= loader_activations;
                    snapshot_source_bank[35] <= loader_errors;
                    snapshot_source_bank[36] <= {26'd0, dma_bus_owner,
                        dmc_dma_request, oam_dma_active, cpu_stalled};
                    snapshot_source_bank[37] <= oam_completed;
                    snapshot_source_bank[38] <= dmc_completed;
                    snapshot_source_bank[39] <= dma_arbitration_waits;
                    snapshot_source_bank[40] <= dma_stalled_requests;
                    snapshot_source_bank[41] <= {19'd0,
                        cartridge_mirroring, cartridge_chr_is_ram,
                        cartridge_nrom_256, cartridge_mapper,
                        cartridge_present};
                    snapshot_source_bank[42] <= fault_flags |
                                                       detected_faults;
                    snapshot_source_bank[43] <= {24'd0,
                        (|detected_faults) ? detected_fault_code : last_fault};
                    snapshot_source_bank[44] <= fabric_heartbeat;
                    snapshot_source_bank[45] <= {20'd0, trace_write_index,
                        trace_count, trace_frozen, trace_triggered,
                        trace_armed};
                    snapshot_source_bank[46] <= trace_overflow;
                    snapshot_source_bank[47] <= {23'd0,
                        trace_write_index, trace_count};
                    for (index = 0; index < DIAG_TRACE_DEPTH;
                         index = index + 1) begin
                        snapshot_source_bank[TRACE_WORD_BASE + index * 2]
                            <= trace_timestamp[index];
                        snapshot_source_bank[TRACE_WORD_BASE + index * 2 + 1]
                            <= trace_header[index];
                    end
                    snapshot_source_bank[80] <= {19'd0,
                        hdmi_startup_state, hdmi_video_enabled,
                        hdmi_video_clock_locked, hdmi_mode_supported,
                        hdmi_edid_valid, hdmi_hpd_state,
                        hdmi_transmitter_fault,
                        hdmi_transmitter_configured,
                        hdmi_transmitter_present};
                    snapshot_source_bank[81] <= hdmi_video_frames;
                    snapshot_source_bank[82] <= hdmi_i2c_nacks;
                    snapshot_source_bank[83] <= hdmi_i2c_timeouts;
                    snapshot_source_bank[84] <= hdmi_recoveries;
                    snapshot_source_bank[85] <= {24'd0, hdmi_last_error};
                    snapshot_source_bank[86] <= {23'd0,
                        hdmi_audio_state, hdmi_audio_fault,
                        hdmi_audio_clock_locked, hdmi_audio_muted,
                        hdmi_audio_configured, hdmi_audio_enabled};
                    snapshot_source_bank[87] <= hdmi_audio_sample_count;
                    snapshot_source_bank[88] <= {16'd0,
                        hdmi_audio_fifo_occupancy};
                    snapshot_source_bank[89] <= hdmi_audio_fifo_underruns;
                    snapshot_source_bank[90] <= hdmi_audio_fifo_overruns;
                    snapshot_source_bank[91] <= hdmi_audio_reconnect_count;
                    snapshot_source_bank[92] <= {24'd0,
                        hdmi_audio_last_error};
                end
                acknowledge_toggle_source <= request_sync[2];
                end
            end
        end
    end

    always_ff @(posedge mmio_clk) begin
        if (mmio_reset) begin
            acknowledge_sync <= '0;
            request_toggle_mmio <= 1'b0;
            control_mmio_bank <= '0;
            clear_mask_mmio_bank <= 32'hffff_ffff;
            pending_snapshot <= 1'b0;
            snapshot_valid <= 1'b0;
            command_rejected <= 1'b0;
            snapshot_sequence <= '0;
            mmio_heartbeat <= '0;
            trace_read_index <= '0;
            avs_readdata <= '0;
            avs_readdatavalid <= 1'b0;
            for (index = 0; index < SNAPSHOT_WORDS; index = index + 1)
                snapshot_mmio_bank[index] <= '0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[1:0],
                                  acknowledge_toggle_source};
            mmio_heartbeat <= mmio_heartbeat + 1'b1;
            avs_readdatavalid <= 1'b0;

            if (acknowledge_sync[2] == request_toggle_mmio &&
                command_busy == 1'b0 && pending_snapshot) begin
                for (index = 0; index < SNAPSHOT_WORDS; index = index + 1)
                    snapshot_mmio_bank[index] <= snapshot_source_bank[index];
                snapshot_sequence <= snapshot_sequence + 1'b1;
                snapshot_valid <= 1'b1;
                pending_snapshot <= 1'b0;
            end

            if (avs_write) begin
                if (avs_address == DIAG_REG_FAULT_CLEAR_MASK) begin
                    if (avs_byteenable[0])
                        clear_mask_mmio_bank[7:0] <= avs_writedata[7:0];
                    if (avs_byteenable[1])
                        clear_mask_mmio_bank[15:8] <= avs_writedata[15:8];
                    if (avs_byteenable[2])
                        clear_mask_mmio_bank[23:16] <= avs_writedata[23:16];
                    if (avs_byteenable[3])
                        clear_mask_mmio_bank[31:24] <= avs_writedata[31:24];
                end else if (avs_address == DIAG_REG_TRACE_INDEX) begin
                    if (avs_byteenable[0])
                        trace_read_index <= avs_writedata[3:0];
                end else if (avs_address == DIAG_REG_CONTROL &&
                             avs_byteenable[0]) begin
                    if (command_busy) begin
                        command_rejected <= 1'b1;
                    end else begin
                        control_mmio_bank <= avs_writedata;
                        pending_snapshot <=
                            avs_writedata[DIAG_CONTROL_SNAPSHOT_BIT];
                        command_rejected <= 1'b0;
                        request_toggle_mmio <= !request_toggle_mmio;
                    end
                end
            end

            if (avs_read) begin
                avs_readdatavalid <= 1'b1;
                unique case (avs_address)
                    DIAG_REG_MAGIC: avs_readdata <= DIAG_MAGIC;
                    DIAG_REG_VERSION: avs_readdata <= DIAG_VERSION;
                    DIAG_REG_BUILD_ID: avs_readdata <= DIAG_BUILD_ID;
                    DIAG_REG_CAPABILITIES: avs_readdata <= DIAG_CAPABILITIES;
                    DIAG_REG_CONTROL: avs_readdata <= control_mmio_bank;
                    DIAG_REG_CONTROL_STATUS: avs_readdata <= {
                        29'd0, command_rejected, snapshot_valid, command_busy};
                    DIAG_REG_SNAPSHOT_SEQUENCE:
                        avs_readdata <= snapshot_sequence;
                    DIAG_REG_AVAILABILITY: avs_readdata <= DIAG_AVAILABILITY &
                        (HDMI_AUDIO_AVAILABLE ? 32'hffffffff : 32'hffffdfff);
                    DIAG_REG_RESET_CAUSE: avs_readdata <= snapshot_mmio_bank[0];
                    DIAG_REG_SYSTEM_STATUS: avs_readdata <= snapshot_mmio_bank[1];
                    DIAG_REG_CLOCK_STATUS: avs_readdata <= snapshot_mmio_bank[2];
                    DIAG_REG_CPU_STATUS: avs_readdata <= snapshot_mmio_bank[3];
                    DIAG_REG_CPU_CYCLES: avs_readdata <= snapshot_mmio_bank[4];
                    DIAG_REG_CPU_INSTRUCTIONS: avs_readdata <= 32'hffff_ffff;
                    DIAG_REG_CPU_STALL_CYCLES:
                        avs_readdata <= snapshot_mmio_bank[5];
                    DIAG_REG_CPU_IRQ_EVENTS: avs_readdata <= snapshot_mmio_bank[6];
                    DIAG_REG_CPU_NMI_EVENTS: avs_readdata <= snapshot_mmio_bank[7];
                    DIAG_REG_CPU_DEBUG_EVENTS:
                        avs_readdata <= snapshot_mmio_bank[8];
                    DIAG_REG_CPU_PC: avs_readdata <= snapshot_mmio_bank[9];
                    DIAG_REG_PPU_STATUS: avs_readdata <= snapshot_mmio_bank[10];
                    DIAG_REG_PPU_FRAMES: avs_readdata <= snapshot_mmio_bank[11];
                    DIAG_REG_PPU_NMI_EVENTS:
                        avs_readdata <= snapshot_mmio_bank[12];
                    DIAG_REG_VIDEO_STATUS: avs_readdata <= snapshot_mmio_bank[13];
                    DIAG_REG_VGA_FRAMES: avs_readdata <= snapshot_mmio_bank[14];
                    DIAG_REG_VGA_HSYNC_EVENTS:
                        avs_readdata <= snapshot_mmio_bank[15];
                    DIAG_REG_VGA_VSYNC_EVENTS:
                        avs_readdata <= snapshot_mmio_bank[16];
                    DIAG_REG_APU_STATUS: avs_readdata <= snapshot_mmio_bank[17];
                    DIAG_REG_APU_CYCLES: avs_readdata <= snapshot_mmio_bank[18];
                    DIAG_REG_AUDIO_STATUS: avs_readdata <= snapshot_mmio_bank[19];
                    DIAG_REG_AUDIO_MIXED_SAMPLES:
                        avs_readdata <= snapshot_mmio_bank[20];
                    DIAG_REG_AUDIO_PCM_SAMPLES:
                        avs_readdata <= snapshot_mmio_bank[21];
                    DIAG_REG_AUDIO_I2S_FRAMES:
                        avs_readdata <= snapshot_mmio_bank[22];
                    DIAG_REG_AUDIO_FIFO: avs_readdata <= snapshot_mmio_bank[23];
                    DIAG_REG_AUDIO_UNDERRUNS:
                        avs_readdata <= snapshot_mmio_bank[24];
                    DIAG_REG_AUDIO_OVERRUNS:
                        avs_readdata <= snapshot_mmio_bank[25];
                    DIAG_REG_AUDIO_CODEC_ACKS:
                        avs_readdata <= snapshot_mmio_bank[26];
                    DIAG_REG_AUDIO_CODEC_NACKS:
                        avs_readdata <= snapshot_mmio_bank[27];
                    DIAG_REG_AUDIO_CODEC_TIMEOUTS:
                        avs_readdata <= snapshot_mmio_bank[28];
                    DIAG_REG_AUDIO_CODEC_RETRIES:
                        avs_readdata <= snapshot_mmio_bank[29];
                    DIAG_REG_AUDIO_LAST_FAULT:
                        avs_readdata <= snapshot_mmio_bank[30];
                    DIAG_REG_LOADER_STATUS: avs_readdata <= snapshot_mmio_bank[31];
                    DIAG_REG_LOADER_PRG_TRANSFERS:
                        avs_readdata <= snapshot_mmio_bank[32];
                    DIAG_REG_LOADER_CHR_TRANSFERS:
                        avs_readdata <= snapshot_mmio_bank[33];
                    DIAG_REG_LOADER_ACTIVATIONS:
                        avs_readdata <= snapshot_mmio_bank[34];
                    DIAG_REG_LOADER_ERRORS: avs_readdata <= snapshot_mmio_bank[35];
                    DIAG_REG_DMA_STATUS: avs_readdata <= snapshot_mmio_bank[36];
                    DIAG_REG_DMA_OAM_COMPLETED:
                        avs_readdata <= snapshot_mmio_bank[37];
                    DIAG_REG_DMA_DMC_COMPLETED:
                        avs_readdata <= snapshot_mmio_bank[38];
                    DIAG_REG_DMA_ARBITRATION_WAITS:
                        avs_readdata <= snapshot_mmio_bank[39];
                    DIAG_REG_DMA_STALLED_REQUESTS:
                        avs_readdata <= snapshot_mmio_bank[40];
                    DIAG_REG_CARTRIDGE_STATUS:
                        avs_readdata <= snapshot_mmio_bank[41];
                    DIAG_REG_FAULT_FLAGS: avs_readdata <= snapshot_mmio_bank[42];
                    DIAG_REG_FAULT_CLEAR_MASK:
                        avs_readdata <= clear_mask_mmio_bank;
                    DIAG_REG_LAST_FAULT: avs_readdata <= snapshot_mmio_bank[43];
                    DIAG_REG_FABRIC_HEARTBEAT:
                        avs_readdata <= snapshot_mmio_bank[44];
                    DIAG_REG_MMIO_HEARTBEAT: avs_readdata <= mmio_heartbeat;
                    DIAG_REG_TRACE_STATUS: avs_readdata <= snapshot_mmio_bank[45];
                    DIAG_REG_TRACE_INDEX: avs_readdata <= {28'd0,
                                                           trace_read_index};
                    DIAG_REG_TRACE_TIMESTAMP: avs_readdata <=
                        snapshot_mmio_bank[TRACE_WORD_BASE +
                                           trace_read_index * 2];
                    DIAG_REG_TRACE_EVENT: avs_readdata <= {24'd0,
                        snapshot_mmio_bank[TRACE_WORD_BASE +
                            trace_read_index * 2 + 1][31:24]};
                    DIAG_REG_TRACE_PAYLOAD: avs_readdata <= {8'd0,
                        snapshot_mmio_bank[TRACE_WORD_BASE +
                            trace_read_index * 2 + 1][23:0]};
                    DIAG_REG_TRACE_OVERFLOW:
                        avs_readdata <= snapshot_mmio_bank[46];
                    DIAG_REG_HDMI_STATUS:
                        avs_readdata <= snapshot_mmio_bank[80];
                    DIAG_REG_HDMI_VIDEO_FRAMES:
                        avs_readdata <= snapshot_mmio_bank[81];
                    DIAG_REG_HDMI_I2C_NACKS:
                        avs_readdata <= snapshot_mmio_bank[82];
                    DIAG_REG_HDMI_I2C_TIMEOUTS:
                        avs_readdata <= snapshot_mmio_bank[83];
                    DIAG_REG_HDMI_RECOVERIES:
                        avs_readdata <= snapshot_mmio_bank[84];
                    DIAG_REG_HDMI_LAST_ERROR:
                        avs_readdata <= snapshot_mmio_bank[85];
                    DIAG_REG_HDMI_AUDIO_STATUS:
                        avs_readdata <= snapshot_mmio_bank[86];
                    DIAG_REG_HDMI_AUDIO_SAMPLE_COUNT:
                        avs_readdata <= snapshot_mmio_bank[87];
                    DIAG_REG_HDMI_AUDIO_FIFO_OCCUPANCY:
                        avs_readdata <= snapshot_mmio_bank[88];
                    DIAG_REG_HDMI_AUDIO_FIFO_UNDERRUNS:
                        avs_readdata <= snapshot_mmio_bank[89];
                    DIAG_REG_HDMI_AUDIO_FIFO_OVERRUNS:
                        avs_readdata <= snapshot_mmio_bank[90];
                    DIAG_REG_HDMI_AUDIO_RECONNECT_COUNT:
                        avs_readdata <= snapshot_mmio_bank[91];
                    DIAG_REG_HDMI_AUDIO_LAST_ERROR:
                        avs_readdata <= snapshot_mmio_bank[92];
                    default: avs_readdata <= 32'h0000_0000;
                endcase
            end
        end
    end
endmodule
