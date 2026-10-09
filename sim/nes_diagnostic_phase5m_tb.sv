`timescale 1ns/1ps

module nes_diagnostic_phase5m_tb;
    import nes_diagnostic_mmio_pkg::*;

    logic fabric_clk = 1'b0;
    logic mmio_clk = 1'b0;
    logic fabric_reset = 1'b1;
    logic mmio_reset = 1'b1;
    logic system_reset = 1'b0;
    logic nes_reset = 1'b0;
    logic hps_bridge_reset = 1'b0;
    logic runtime_replacement = 1'b0;
    logic video_pll_locked = 1'b0;
    logic audio_pll_locked = 1'b0;
    logic cpu_cycle_event = 1'b0;
    logic cpu_progress_event = 1'b0;
    logic cpu_stalled = 1'b0;
    logic cpu_irq = 1'b0;
    logic cpu_nmi_event = 1'b0;
    logic [15:0] cpu_pc = 16'h8000;
    logic debugger_paused = 1'b1;
    logic debugger_step_event = 1'b0;
    logic ppu_frame_event = 1'b0;
    logic [8:0] ppu_scanline = '0;
    logic [8:0] ppu_dot = '0;
    logic ppu_frame_odd = 1'b0;
    logic ppu_nmi_level = 1'b0;
    logic ppu_nmi_event = 1'b0;
    logic vga_frame_toggle_async = 1'b0;
    logic vga_hsync_toggle_async = 1'b0;
    logic vga_vsync_toggle_async = 1'b0;
    logic vga_active_async = 1'b0;
    logic apu_cycle_event = 1'b0;
    logic codec_init_busy = 1'b0;
    logic codec_init_done = 1'b0;
    logic codec_init_error = 1'b0;
    logic [31:0] audio_codec_acks = '0;
    logic [31:0] audio_codec_nacks = '0;
    logic [31:0] audio_codec_timeouts = '0;
    logic [31:0] audio_codec_retries = '0;
    logic [31:0] audio_mixed_samples = '0;
    logic [31:0] audio_pcm_samples = '0;
    logic [31:0] audio_i2s_frames = '0;
    logic [15:0] audio_fifo_occupancy = '0;
    logic [31:0] audio_fifo_underruns = '0;
    logic [31:0] audio_fifo_overruns = '0;
    logic audio_muted = 1'b1;
    logic [7:0] audio_last_fault = '0;
    logic [1:0] loader_state = '0;
    logic loader_busy = 1'b0;
    logic loader_image_valid = 1'b0;
    logic loader_runtime_active = 1'b0;
    logic loader_hold_reset = 1'b0;
    logic loader_error = 1'b0;
    logic [3:0] loader_error_code = '0;
    logic loader_command_accepted = 1'b0;
    logic [1:0] loader_command = '0;
    logic [1:0] loader_target = '0;
    logic loader_activation_accepted = 1'b0;
    logic oam_dma_active = 1'b0;
    logic oam_dma_start = 1'b0;
    logic oam_dma_complete = 1'b0;
    logic dmc_dma_request = 1'b0;
    logic dmc_dma_acknowledge = 1'b0;
    logic [2:0] dma_bus_owner = '0;
    logic cartridge_present = 1'b0;
    logic [7:0] cartridge_mapper = '0;
    logic cartridge_nrom_256 = 1'b0;
    logic cartridge_chr_is_ram = 1'b0;
    logic [1:0] cartridge_mirroring = '0;
    logic [9:0] fault_inject = '0;
    logic [8:0] avs_address = '0;
    logic avs_read = 1'b0;
    logic avs_write = 1'b0;
    logic [31:0] avs_writedata = '0;
    logic [3:0] avs_byteenable = 4'hf;
    logic avs_waitrequest;
    logic [31:0] avs_readdata;
    logic avs_readdatavalid;
    logic [31:0] read_value;
    integer failure_count = 0;
    integer fault_index;
    integer event_index;
    integer physical_index;
    integer metrics_file;
    logic [23:0] trace_oldest_payload;
    logic [23:0] trace_newest_payload;

    always #5 fabric_clk = !fabric_clk;
    always #7 mmio_clk = !mmio_clk;

    nes_diagnostic_subsystem #(
        .CPU_STALL_LIMIT(8),
        .VIDEO_STALL_LIMIT(8),
        .DMA_TIMEOUT_LIMIT(8),
        .LOADER_TIMEOUT_LIMIT(8)
    ) dut (.*);

    task automatic check_result(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            failure_count = failure_count + 1;
        end
    endtask

    task automatic mmio_write(input logic [8:0] address,
                              input logic [31:0] data);
        @(negedge mmio_clk);
        avs_address = address;
        avs_writedata = data;
        avs_write = 1'b1;
        @(negedge mmio_clk);
        avs_write = 1'b0;
    endtask

    task automatic mmio_read(input logic [8:0] address,
                             output logic [31:0] data);
        @(negedge mmio_clk);
        avs_address = address;
        avs_read = 1'b1;
        @(posedge mmio_clk);
        #1;
        check_result(avs_readdatavalid, "read response must be valid");
        data = avs_readdata;
        @(negedge mmio_clk);
        avs_read = 1'b0;
    endtask

    task automatic wait_command;
        integer polls;
        begin
            polls = 0;
            mmio_read(DIAG_REG_CONTROL_STATUS, read_value);
            while (read_value[0] && polls < 32) begin
                mmio_read(DIAG_REG_CONTROL_STATUS, read_value);
                polls = polls + 1;
            end
            check_result(!read_value[0], "CDC command must complete");
        end
    endtask

    task automatic snapshot;
        begin
            mmio_write(DIAG_REG_CONTROL,
                       32'(1 << DIAG_CONTROL_SNAPSHOT_BIT));
            wait_command();
        end
    endtask

    task automatic pulse_fabric(ref logic signal_value);
        @(negedge fabric_clk);
        signal_value = 1'b1;
        @(negedge fabric_clk);
        signal_value = 1'b0;
    endtask

    initial begin
        repeat (4) @(posedge fabric_clk);
        repeat (3) @(posedge mmio_clk);
        fabric_reset = 1'b0;
        mmio_reset = 1'b0;
        repeat (4) @(posedge mmio_clk);

        mmio_read(DIAG_REG_MAGIC, read_value);
        check_result(read_value == DIAG_MAGIC, "magic identifier");
        mmio_read(DIAG_REG_VERSION, read_value);
        check_result(read_value == DIAG_VERSION, "interface version");
        mmio_read(DIAG_REG_BUILD_ID, read_value);
        check_result(read_value == DIAG_BUILD_ID, "build identifier");
        mmio_read(9'h1fc, read_value);
        check_result(read_value == 0, "unmapped address returns zero");

        snapshot();
        mmio_read(DIAG_REG_RESET_CAUSE, read_value);
        check_result(read_value[7:0] == DIAG_RESET_POWER_ON,
               "deterministic power-on reset cause");
        pulse_fabric(runtime_replacement);
        snapshot();
        mmio_read(DIAG_REG_RESET_CAUSE, read_value);
        check_result(read_value[7:0] == DIAG_RESET_RUNTIME_REPLACEMENT,
               "runtime replacement reset cause");

        // Exercise an HPS-only reset from a nonzero mailbox epoch. The
        // diagnostic counters survive while both toggle endpoints rebase.
        snapshot();
        check_result(dut.request_toggle_mmio,
               "mailbox epoch is nonzero before HPS reset");
        @(negedge fabric_clk);
        hps_bridge_reset = 1'b1;
        @(negedge mmio_clk);
        mmio_reset = 1'b1;
        repeat (4) @(posedge fabric_clk);
        repeat (3) @(posedge mmio_clk);
        @(negedge fabric_clk);
        hps_bridge_reset = 1'b0;
        @(negedge mmio_clk);
        mmio_reset = 1'b0;
        repeat (4) @(posedge mmio_clk);
        snapshot();
        mmio_read(DIAG_REG_RESET_CAUSE, read_value);
        check_result(read_value[7:0] == DIAG_RESET_HPS_BRIDGE_RESET,
               "HPS bridge reset cause");
        video_pll_locked = 1'b1;
        repeat (3) @(posedge fabric_clk);
        pulse_fabric(system_reset);
        snapshot();
        mmio_read(DIAG_REG_RESET_CAUSE, read_value);
        check_result(read_value[7:0] == DIAG_RESET_EXTERNAL_BUTTON,
               "external system reset cause");

        // Source counters advance, but an already captured MMIO snapshot is
        // stable until another request crosses the asynchronous mailbox.
        pulse_fabric(cpu_cycle_event);
        pulse_fabric(cpu_cycle_event);
        pulse_fabric(ppu_frame_event);
        pulse_fabric(apu_cycle_event);
        snapshot();
        mmio_read(DIAG_REG_CPU_CYCLES, read_value);
        check_result(read_value == 2, "CPU cycle counter");
        pulse_fabric(cpu_cycle_event);
        mmio_read(DIAG_REG_CPU_CYCLES, read_value);
        check_result(read_value == 2, "snapshot remains atomic and stable");
        snapshot();
        mmio_read(DIAG_REG_CPU_CYCLES, read_value);
        check_result(read_value == 3, "new snapshot observes later counter");
        mmio_read(DIAG_REG_CPU_INSTRUCTIONS, read_value);
        check_result(read_value == 32'hffff_ffff,
               "unavailable retirement count is explicit");
        mmio_read(DIAG_REG_AVAILABILITY, read_value);
        check_result(!read_value[11], "retirement availability is clear");

        // Natural 32-bit wrap is intentional for fabric-owned event counters.
        @(negedge fabric_clk);
        dut.cpu_cycles = 32'hffff_fffe;
        pulse_fabric(cpu_cycle_event);
        pulse_fabric(cpu_cycle_event);
        snapshot();
        mmio_read(DIAG_REG_CPU_CYCLES, read_value);
        check_result(read_value == 0, "counter rollover");

        // Every deterministic injected condition maps to its stable flag/code.
        for (fault_index = 0; fault_index < 10;
             fault_index = fault_index + 1) begin
            @(negedge fabric_clk);
            fault_inject = 10'(1 << fault_index);
            @(negedge fabric_clk);
            fault_inject = '0;
            snapshot();
            mmio_read(DIAG_REG_FAULT_FLAGS, read_value);
            check_result(read_value[fault_index], "injected fault flag");
            mmio_read(DIAG_REG_LAST_FAULT, read_value);
            check_result(read_value[7:0] == 8'(fault_index + 1),
                   "injected stable fault code");
            mmio_write(DIAG_REG_FAULT_CLEAR_MASK,
                       32'(1 << fault_index));
            mmio_write(DIAG_REG_CONTROL,
                       32'(1 << DIAG_CONTROL_FAULT_CLEAR_BIT));
            wait_command();
            snapshot();
            mmio_read(DIAG_REG_FAULT_FLAGS, read_value);
            check_result(!read_value[fault_index], "fault clear is explicit");
        end

        // Reset events carry the reset source that caused the event.
        mmio_write(DIAG_REG_CONTROL,
                   32'((1 << DIAG_CONTROL_TRACE_CLEAR_BIT) |
                       (1 << DIAG_CONTROL_TRACE_ARM_BIT)));
        wait_command();
        pulse_fabric(runtime_replacement);
        snapshot();
        mmio_write(DIAG_REG_TRACE_INDEX, 32'd0);
        mmio_read(DIAG_REG_TRACE_EVENT, read_value);
        check_result(read_value[7:0] == DIAG_EVENT_RESET,
               "runtime replacement emits reset trace event");
        mmio_read(DIAG_REG_TRACE_PAYLOAD, read_value);
        check_result(read_value[7:0] == DIAG_RESET_RUNTIME_REPLACEMENT,
               "reset trace payload identifies runtime replacement");

        // A newly latched fault records the failure before automatically
        // triggering, freezing and disarming the trace.
        mmio_write(DIAG_REG_CONTROL,
                   32'((1 << DIAG_CONTROL_TRACE_CLEAR_BIT) |
                       (1 << DIAG_CONTROL_TRACE_ARM_BIT)));
        wait_command();
        @(negedge fabric_clk);
        fault_inject = 10'(1 << DIAG_FAULT_CPU_STALL_TIMEOUT_BIT);
        @(negedge fabric_clk);
        fault_inject = '0;
        snapshot();
        mmio_read(DIAG_REG_TRACE_STATUS, read_value);
        check_result(read_value[1] && read_value[2] && !read_value[0],
               "new fault automatically triggers and freezes trace");
        mmio_write(DIAG_REG_TRACE_INDEX, 32'd0);
        mmio_read(DIAG_REG_TRACE_EVENT, read_value);
        check_result(read_value[7:0] == DIAG_EVENT_FAULT,
               "automatic trigger records fault event");
        mmio_read(DIAG_REG_TRACE_PAYLOAD, read_value);
        check_result(read_value[7:0] == DIAG_FAULT_CPU_STALL_TIMEOUT,
               "automatic trigger records stable fault code");
        mmio_write(DIAG_REG_FAULT_CLEAR_MASK,
                   32'(1 << DIAG_FAULT_CPU_STALL_TIMEOUT_BIT));
        mmio_write(DIAG_REG_CONTROL,
                   32'(1 << DIAG_CONTROL_FAULT_CLEAR_BIT));
        wait_command();

        // The trace is bounded, circular, reports overflow, and freezes on a
        // manual trigger. NMI events provide deterministic ordered payloads.
        mmio_write(DIAG_REG_CONTROL,
                   32'((1 << DIAG_CONTROL_TRACE_CLEAR_BIT) |
                       (1 << DIAG_CONTROL_TRACE_ARM_BIT)));
        wait_command();
        for (event_index = 0; event_index < 18;
             event_index = event_index + 1) begin
            cpu_pc = 16'(16'h9000 + event_index);
            pulse_fabric(cpu_nmi_event);
        end
        snapshot();
        mmio_read(DIAG_REG_TRACE_STATUS, read_value);
        check_result(read_value[7:3] == 5'(DIAG_TRACE_DEPTH),
               "trace count is bounded at depth");
        mmio_read(DIAG_REG_TRACE_OVERFLOW, read_value);
        check_result(read_value == 2, "trace overflow counts overwritten events");
        for (event_index = 0; event_index < DIAG_TRACE_DEPTH;
             event_index = event_index + 1) begin
            physical_index = (2 + event_index) % DIAG_TRACE_DEPTH;
            mmio_write(DIAG_REG_TRACE_INDEX, 32'(physical_index));
            mmio_read(DIAG_REG_TRACE_PAYLOAD, read_value);
            check_result(read_value[15:0] == 16'(16'h9002 + event_index),
                   "wrapped trace readout is oldest-to-newest");
            if (event_index == 0)
                trace_oldest_payload = read_value[23:0];
            if (event_index == DIAG_TRACE_DEPTH - 1)
                trace_newest_payload = read_value[23:0];
        end

        mmio_write(DIAG_REG_CONTROL,
                   32'(1 << DIAG_CONTROL_TRACE_TRIGGER_BIT));
        wait_command();
        pulse_fabric(cpu_nmi_event);
        snapshot();
        mmio_read(DIAG_REG_TRACE_STATUS, read_value);
        check_result(read_value[1] && read_value[2] && !read_value[0],
               "trigger freezes and disarms trace");
        mmio_write(DIAG_REG_TRACE_INDEX, 32'd0);
        mmio_read(DIAG_REG_TRACE_EVENT, read_value);
        check_result(read_value[7:0] == DIAG_EVENT_NMI,
               "trace readout returns event code");

        // Toggle CDC counts video-domain activity once per transition.
        vga_frame_toggle_async = !vga_frame_toggle_async;
        vga_hsync_toggle_async = !vga_hsync_toggle_async;
        vga_vsync_toggle_async = !vga_vsync_toggle_async;
        repeat (5) @(posedge fabric_clk);
        snapshot();
        mmio_read(DIAG_REG_VGA_FRAMES, read_value);
        check_result(read_value == 1, "VGA frame toggle CDC");
        mmio_read(DIAG_REG_VGA_HSYNC_EVENTS, read_value);
        check_result(read_value == 1, "VGA HSYNC toggle CDC");
        mmio_read(DIAG_REG_VGA_VSYNC_EVENTS, read_value);
        check_result(read_value == 1, "VGA VSYNC toggle CDC");

        metrics_file = $fopen("build/sim/phase5m_diagnostic_rtl.txt", "w");
        check_result(metrics_file != 0, "open RTL/model comparison metrics");
        $fdisplay(metrics_file, "cpu_rollover=%0d", dut.cpu_cycles);
        $fdisplay(metrics_file, "trace_count=%0d", dut.trace_count);
        $fdisplay(metrics_file, "trace_overflow=%0d", dut.trace_overflow);
        $fdisplay(metrics_file, "trace_write_index=%0d", dut.trace_write_index);
        $fdisplay(metrics_file, "trace_depth=%0d", DIAG_TRACE_DEPTH);
        $fdisplay(metrics_file, "trace_oldest_payload=%0d",
                  trace_oldest_payload);
        $fdisplay(metrics_file, "trace_newest_payload=%0d",
                  trace_newest_payload);
        $fclose(metrics_file);

        if (failure_count == 0) begin
            $display("Phase 5M diagnostic MMIO/CDC test passed");
            $finish;
        end else begin
            $fatal(1, "Phase 5M diagnostic test failed: %0d checks",
                   failure_count);
        end
    end
endmodule
