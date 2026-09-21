`timescale 1ns/1ps

module nes_debug_snapshot_tb;
    import nes_debug_snapshot_pkg::*;

    logic source_clk = 1'b0;
    logic destination_clk = 1'b0;
    logic source_reset = 1'b1;
    logic destination_reset = 1'b1;
    logic source_frame_capture = 1'b0;
    logic manual_capture = 1'b0;
    logic destination_frame_start = 1'b0;
    logic nmi_event = 1'b0;
    logic nmi_suppressed_event = 1'b0;
    logic dma_complete_event = 1'b0;
    logic controller_poll_event = 1'b0;
    logic controller_read_4016_event = 1'b0;
    logic controller_read_4017_event = 1'b0;
    logic cpu_slot_event = 1'b0;
    logic ppu_cycle_event = 1'b0;
    logic prg_read_event = 1'b0;
    logic chr_read_event = 1'b0;
    logic source_capture_accepted;
    logic source_busy;
    logic destination_update;
    logic destination_valid;
    nes_debug_snapshot_t observations;
    nes_debug_snapshot_t destination_snapshot;
    /* verilator lint_off UNUSEDSIGNAL */
    nes_debug_snapshot_t first_observations;
    nes_debug_snapshot_t second_observations;
    /* verilator lint_on UNUSEDSIGNAL */
    integer accepted_captures = 0;
    integer destination_updates = 0;

    always #5 source_clk <= !source_clk;
    always #7 destination_clk <= !destination_clk;

    nes_debug_snapshot dut (
        .source_clk(source_clk),
        .source_reset(source_reset),
        .source_frame_capture(source_frame_capture),
        .manual_capture(manual_capture),
        .observations(observations),
        .nmi_event(nmi_event),
        .nmi_suppressed_event(nmi_suppressed_event),
        .dma_complete_event(dma_complete_event),
        .controller_poll_event(controller_poll_event),
        .controller_read_4016_event(controller_read_4016_event),
        .controller_read_4017_event(controller_read_4017_event),
        .cpu_slot_event(cpu_slot_event),
        .ppu_cycle_event(ppu_cycle_event),
        .prg_read_event(prg_read_event),
        .chr_read_event(chr_read_event),
        .source_capture_accepted(source_capture_accepted),
        .source_busy(source_busy),
        .destination_clk(destination_clk),
        .destination_reset(destination_reset),
        .destination_frame_start(destination_frame_start),
        .destination_update(destination_update),
        .destination_valid(destination_valid),
        .destination_snapshot(destination_snapshot)
    );

    always @(posedge source_clk) begin
        if (!source_reset && source_capture_accepted)
            accepted_captures <= accepted_captures + 1;
    end

    always @(negedge destination_clk) begin
        if (!destination_reset && destination_update)
            destination_updates <= destination_updates + 1;
    end

    task automatic clear_events;
        begin
            nmi_event = 1'b0;
            nmi_suppressed_event = 1'b0;
            dma_complete_event = 1'b0;
            controller_poll_event = 1'b0;
            controller_read_4016_event = 1'b0;
            controller_read_4017_event = 1'b0;
            cpu_slot_event = 1'b0;
            ppu_cycle_event = 1'b0;
            prg_read_event = 1'b0;
            chr_read_event = 1'b0;
        end
    endtask

    task automatic pulse_destination_frame;
        begin
            @(negedge destination_clk);
            destination_frame_start = 1'b1;
            @(negedge destination_clk);
            destination_frame_start = 1'b0;
        end
    endtask

    task automatic wait_for_transfer;
        integer timeout;
        begin
            timeout = 0;
            while (source_busy && timeout < 20) begin
                @(posedge source_clk);
                timeout = timeout + 1;
            end
            assert (!source_busy) else $fatal(1, "snapshot CDC acknowledge timeout");
        end
    endtask

    task automatic check_first_snapshot;
        /* verilator lint_off UNUSEDSIGNAL */
        nes_debug_snapshot_t expected;
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            expected = first_observations;
            expected.ppu.nmi_event = 1'b1;
            expected.ppu.nmi_suppressed = 1'b1;
            expected.controller.read_4016 = 1'b1;
            expected.controller.read_4017 = 1'b1;
            expected.controller.latch_event = 1'b1;
            expected.dma.complete_event = 1'b1;
            assert (destination_snapshot.cpu == expected.cpu);
            assert (destination_snapshot.ppu == expected.ppu);
            assert (destination_snapshot.cartridge == expected.cartridge);
            assert (destination_snapshot.controller == expected.controller);
            assert (destination_snapshot.dma == expected.dma);
            assert (destination_snapshot.system.snapshot_id == 32'd1);
            assert (destination_snapshot.system.source_frame_number == 32'd1);
            assert (destination_snapshot.system.nmi_count == 32'd1);
            assert (destination_snapshot.system.dma_count == 32'd1);
            assert (destination_snapshot.system.controller_poll_count == 32'd1);
            assert (destination_snapshot.system.cpu_slot_count == 32'd2);
            assert (destination_snapshot.system.ppu_cycle_count == 32'd3);
            assert (destination_snapshot.system.prg_read_count == 32'd1);
            assert (destination_snapshot.system.chr_read_count == 32'd1);
            assert (destination_snapshot.system.missed_capture_count == 32'd0);
        end
    endtask

    initial begin
        observations = '0;
        clear_events();
        $dumpfile("build/sim/nes_debug_snapshot.fst");
        $dumpvars(0, nes_debug_snapshot_tb);

        repeat (5) @(posedge source_clk);
        source_reset = 1'b0;
        repeat (5) @(posedge destination_clk);
        destination_reset = 1'b0;

        // A display boundary without a source capture cannot update the bank.
        pulse_destination_frame();
        assert (!destination_valid && destination_updates == 0);

        observations.cpu.pc = 16'h8123;
        observations.cpu.a = 8'h11;
        observations.cpu.x = 8'h22;
        observations.cpu.y = 8'h33;
        observations.cpu.sp = 8'hf8;
        observations.cpu.status = 8'ha4;
        observations.cpu.opcode = 8'had;
        observations.cpu.address = 16'h4016;
        observations.cpu.read_data = 8'h01;
        observations.cpu.write_data = 8'h80;
        observations.cpu.read = 1'b1;
        observations.cpu.bus_valid = 1'b1;
        observations.cpu.stalled = 1'b1;
        observations.cpu.bus_owner = 2'd2;
        observations.ppu.scanline = 9'd0;
        observations.ppu.dot = 9'd0;
        observations.ppu.frame_odd = 1'b1;
        observations.ppu.ctrl = 8'h80;
        observations.ppu.mask = 8'h1e;
        observations.ppu.status = 8'he0;
        observations.ppu.pixel_x = 8'hfe;
        observations.ppu.pixel_y = 8'hef;
        observations.ppu.palette_address = 14'h3f1c;
        observations.ppu.pixel_color = 6'h2a;
        observations.ppu.pixel_emphasis = 3'h5;
        observations.ppu.pixel_source = 2'd2;
        observations.ppu.pixel_valid = 1'b1;
        observations.ppu.nmi_enabled = 1'b1;
        observations.ppu.nmi_level = 1'b1;
        observations.ppu.vblank = 1'b1;
        observations.ppu.sprite_zero_hit = 1'b1;
        observations.ppu.sprite_overflow = 1'b1;
        observations.cartridge.present = 1'b1;
        observations.cartridge.mapper_number = 8'd0;
        observations.cartridge.nrom_256 = 1'b0;
        observations.cartridge.prg_address = 15'h4123;
        observations.cartridge.prg_data = 8'had;
        observations.cartridge.prg_read = 1'b1;
        observations.cartridge.chr_address = 13'h1abc;
        observations.cartridge.chr_data = 8'h5c;
        observations.cartridge.chr_read = 1'b1;
        observations.cartridge.chr_is_ram = 1'b0;
        observations.cartridge.mirroring = 2'd1;
        observations.controller.live1 = 8'ha5;
        observations.controller.live2 = 8'h5a;
        observations.controller.shift1 = 8'hd2;
        observations.controller.shift2 = 8'h4b;
        observations.controller.index1 = 4'd3;
        observations.controller.index2 = 4'd6;
        observations.controller.strobe = 1'b0;
        observations.controller.serial1 = 1'b1;
        observations.dma.active = 1'b1;
        observations.dma.source_page = 8'h02;
        observations.dma.source_address = 16'h02a6;
        observations.dma.source_data = 8'hc3;
        observations.dma.byte_index = 8'ha6;
        observations.dma.oam_data = 8'h3c;
        observations.dma.phase = 3'd4;
        observations.dma.started_odd = 1'b1;
        observations.dma.elapsed_slots = 10'd334;
        observations.dma.read_count = 9'd167;
        observations.dma.write_count = 9'd166;
        observations.dma.cpu_stall = 1'b1;
        observations.dma.bus_owner = 2'd2;
        observations.dma.start_event = 1'b1;
        observations.dma.read_event = 1'b1;
        observations.dma.write_event = 1'b0;
        observations.dma.dummy_cycle = 1'b0;
        observations.dma.alignment_cycle = 1'b0;
        first_observations = observations;

        // Accumulate representative events before the coherent frame capture.
        @(negedge source_clk);
        ppu_cycle_event = 1'b1;
        cpu_slot_event = 1'b1;
        nmi_event = 1'b1;
        controller_read_4016_event = 1'b1;
        @(negedge source_clk);
        clear_events();
        ppu_cycle_event = 1'b1;
        controller_read_4017_event = 1'b1;
        dma_complete_event = 1'b1;
        @(negedge source_clk);
        clear_events();
        ppu_cycle_event = 1'b1;
        cpu_slot_event = 1'b1;
        prg_read_event = 1'b1;
        chr_read_event = 1'b1;
        controller_poll_event = 1'b1;
        nmi_suppressed_event = 1'b1;
        source_frame_capture = 1'b1;
        @(negedge source_clk);
        clear_events();
        source_frame_capture = 1'b0;
        assert (source_capture_accepted);

        // Live inputs may change immediately; the held source bank must not.
        observations = '1;
        wait_for_transfer();
        repeat (4) @(posedge destination_clk);
        assert (!destination_valid);
        pulse_destination_frame();
        assert (destination_update);
        check_first_snapshot();

        // A second capture uses a completely different tag. Until the next
        // display boundary, the renderer-facing bank must remain snapshot 1.
        observations = '0;
        observations.cpu.pc = 16'h9007;
        observations.cpu.a = 8'h44;
        observations.cpu.x = 8'h55;
        observations.cpu.y = 8'h66;
        observations.cpu.sp = 8'he9;
        observations.cpu.status = 8'h25;
        observations.cpu.opcode = 8'h40;
        observations.cpu.address = 16'h2002;
        observations.cpu.read_data = 8'he0;
        observations.cpu.read = 1'b1;
        observations.cpu.bus_valid = 1'b1;
        observations.cpu.bus_owner = 2'd1;
        observations.ppu.scanline = 9'd0;
        observations.ppu.dot = 9'd0;
        observations.ppu.ctrl = 8'h80;
        observations.ppu.mask = 8'h1e;
        observations.cartridge.present = 1'b1;
        observations.cartridge.prg_address = 15'h1007;
        observations.cartridge.prg_data = 8'h40;
        observations.cartridge.prg_read = 1'b1;
        observations.controller.live1 = 8'h80;
        observations.controller.shift1 = 8'hff;
        observations.controller.index1 = 4'd8;
        observations.dma.source_page = 8'h02;
        observations.dma.source_address = 16'h02ff;
        observations.dma.source_data = 8'h77;
        observations.dma.byte_index = 8'hff;
        observations.dma.oam_data = 8'h77;
        observations.dma.bus_owner = 2'd1;
        second_observations = observations;

        @(negedge source_clk);
        source_frame_capture = 1'b1;
        ppu_cycle_event = 1'b1;
        @(negedge source_clk);
        source_frame_capture = 1'b0;
        ppu_cycle_event = 1'b0;
        assert (source_capture_accepted);
        wait_for_transfer();
        repeat (3) @(posedge destination_clk);
        assert (destination_snapshot.system.snapshot_id == 32'd1);
        assert (destination_snapshot.cpu.pc == 16'h8123);
        pulse_destination_frame();
        assert (destination_update);
        assert (destination_snapshot.cpu == second_observations.cpu);
        assert (destination_snapshot.ppu == second_observations.ppu);
        assert (destination_snapshot.cartridge == second_observations.cartridge);
        assert (destination_snapshot.controller == second_observations.controller);
        assert (destination_snapshot.dma == second_observations.dma);
        assert (destination_snapshot.system.snapshot_id == 32'd2);
        assert (destination_snapshot.system.source_frame_number == 32'd2);
        assert (destination_snapshot.system.nmi_count == 32'd1);
        assert (destination_snapshot.system.dma_count == 32'd1);
        assert (destination_snapshot.system.ppu_cycle_count == 32'd4);

        // The reserved manual trigger reuses the same protocol but does not
        // increment the source frame number.
        @(negedge source_clk);
        manual_capture = 1'b1;
        @(negedge source_clk);
        manual_capture = 1'b0;
        assert (source_capture_accepted);
        wait_for_transfer();
        repeat (3) @(posedge destination_clk);
        pulse_destination_frame();
        assert (destination_snapshot.system.snapshot_id == 32'd3);
        assert (destination_snapshot.system.source_frame_number == 32'd2);
        assert (accepted_captures == 3);
        @(posedge destination_clk);
        @(negedge destination_clk);
        assert (destination_updates == 3);

        repeat (4) @(posedge destination_clk);
        assert (!destination_update);
        assert (destination_snapshot.system.snapshot_id == 32'd3);

        // Reset clears both handshake endpoints, the renderer-visible bank,
        // validity, sticky events, counters, and sequence numbering.
        @(negedge source_clk);
        source_reset = 1'b1;
        @(negedge destination_clk);
        destination_reset = 1'b1;
        repeat (2) @(posedge source_clk);
        repeat (2) @(posedge destination_clk);
        assert (!source_busy && !source_capture_accepted);
        assert (!destination_valid && !destination_update);
        assert (destination_snapshot == '0);

        @(negedge source_clk);
        source_reset = 1'b0;
        @(negedge destination_clk);
        destination_reset = 1'b0;
        observations = '0;
        observations.cpu.pc = 16'hcafe;
        @(negedge source_clk);
        manual_capture = 1'b1;
        @(negedge source_clk);
        manual_capture = 1'b0;
        assert (source_capture_accepted);
        wait_for_transfer();
        repeat (3) @(posedge destination_clk);
        pulse_destination_frame();
        assert (destination_valid && destination_update);
        assert (destination_snapshot.cpu.pc == 16'hcafe);
        assert (destination_snapshot.system.snapshot_id == 32'd1);
        assert (destination_snapshot.system.source_frame_number == 32'd0);
        assert (destination_snapshot.system.nmi_count == 32'd0);
        assert (destination_snapshot.system.missed_capture_count == 32'd0);
        @(posedge destination_clk);
        @(negedge destination_clk);
        assert (accepted_captures == 4);
        assert (destination_updates == 4);

        $display("PASS: Phase 4E-A coherent debug snapshot/CDC/frame latch captures=%0d updates=%0d bits=%0d",
                 accepted_captures, destination_updates,
                 NES_DEBUG_SNAPSHOT_BITS);
        $finish;
    end

    initial begin
        repeat (1000) @(posedge source_clk);
        $fatal(1, "Phase 4E-A snapshot timeout");
    end
endmodule
