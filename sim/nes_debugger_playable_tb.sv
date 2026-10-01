`timescale 1ns/1ps

module nes_debugger_playable_tb;
    import nes_debug_snapshot_pkg::*;
    import nes_debugger_pkg::*;
    import cpu_pkg::*;

    logic clock_50 = 1'b0;
    logic key0 = 1'b0;
    logic sw0 = 1'b0;
    logic sw1 = 1'b0;
    logic sw2 = 1'b0;
    logic sw3 = 1'b0;
    logic sw4 = 1'b0;
    logic sw5 = 1'b1;
    logic sw6 = 1'b0;
    logic sw7 = 1'b0;
    logic sw8 = 1'b0;
    logic sw9 = 1'b0;
    logic [9:0] ledr;
    logic [6:0] hex0;
    logic [6:0] hex1;
    logic [6:0] hex2;
    logic [6:0] hex3;
    logic [6:0] hex4;
    logic [6:0] hex5;
    logic [7:0] vga_r;
    logic [7:0] vga_g;
    logic [7:0] vga_b;
    logic vga_hs;
    logic vga_vs;
    logic vga_clk;
    logic vga_blank_n;
    logic vga_sync_n;

    logic [8:0] shadow0 [0:61439];
    logic [8:0] shadow1 [0:61439];
    logic [8:0] shadow2 [0:61439];
    integer bank_sprite_x [0:2];
    integer current_sprite_x = -1;
    integer system_cycles = 0;
    integer ppu_ticks = 0;
    integer nmi_events = 0;
    integer dma_completions = 0;
    integer controller_polls = 0;
    integer snapshot_updates = 0;
    integer cpu_state_changes = 0;
    integer page_changes = 0;
    integer combined_pixels = 0;
    logic [63:0] last_cpu_state = '0;
    logic have_cpu_state = 1'b0;
    integer source_frames=0, fetches=0, commands=0, acknowledgements=0;
    integer dma_reads=0, dma_writes=0, irq_entries=0;
    integer apu_cpu_slots=0, apu_dma_advances=0;
    logic previous_fetch=0, previous_deferred=0;
    logic previous_apu_slot=0, previous_dma_active=0;
    logic [15:0] previous_apu_cycle=0;
    integer deferred_frames=0;
    always @(posedge clock_50) begin
        if (!dut.system_reset) begin
            previous_deferred <= dut.framebuffer.completed_waiting;
            if(dut.framebuffer.completed_waiting && !previous_deferred)
                deferred_frames <= deferred_frames+1;
            if(dut.ppu_frame_start) source_frames <= source_frames+1;
            previous_fetch <= dut.nes_core_cpu_enable && dut.cpu_debug_execution_state==CPU_STATE_FETCH;
            if(previous_fetch) begin
                if(dut.cpu_debug_execution_state==CPU_STATE_INTERRUPT_DUMMY) irq_entries<=irq_entries+1;
                else fetches<=fetches+1;
            end
            if(dut.dma_read_event) dma_reads<=dma_reads+1;
            if(dut.dma_write_event) dma_writes<=dma_writes+1;
            if(dut.nes_core_cpu_cycle_slot) apu_cpu_slots<=apu_cpu_slots+1;
            if(previous_dma_active && previous_apu_slot &&
               dut.apu.frame_sequence_cycle!=previous_apu_cycle)
                apu_dma_advances<=apu_dma_advances+1;
            if(dut.debugger_status.state==DBG_PAUSED) begin
                assert(!dut.nes_core_cpu_enable && !dut.nes_core_cpu_cycle_slot &&
                       !dut.nes_core_ppu_enable && !dut.dma_debug_active);
                assert(!dut.apu_quarter_frame_tick &&
                       !dut.apu_half_frame_tick);
                assert(dut.cpu_debug_execution_state==CPU_STATE_FETCH);
            end
            assert(!dut.write_range_error && !dut.write_sequence_error);
            previous_apu_slot<=dut.nes_core_cpu_cycle_slot;
            previous_dma_active<=dut.dma_debug_active;
            previous_apu_cycle<=dut.apu.frame_sequence_cycle;
        end
    end
    always @(posedge dut.pixel_clk) begin
        if(!dut.video_reset && dut.debugger_ack) acknowledgements<=acknowledgements+1;
    end
    task automatic send_command(input logic [2:0] cmd);
        do @(negedge dut.pixel_clk); while(!dut.debugger_request_ready);
        case(cmd)
            0: force dut.debugger_request_command=3'd0;
            1: force dut.debugger_request_command=3'd1;
            2: force dut.debugger_request_command=3'd2;
            3: force dut.debugger_request_command=3'd3;
            default: force dut.debugger_request_command=3'd7;
        endcase
        force dut.debugger_request_valid=1'b1;
        commands++;
        do @(negedge dut.pixel_clk); while(!dut.debugger_ack);
        assert(dut.debugger_ack_sequence==16'(commands));
        assert(dut.debugger_ack_result==DBG_OK);
        repeat(30) @(negedge dut.pixel_clk);
        assert(acknowledgements==commands);
        force dut.debugger_request_valid=1'b0;
        repeat(2) @(negedge dut.pixel_clk);
    endtask
    task automatic await_pause;
        do @(negedge clock_50); while(dut.debugger_status.state!=DBG_PAUSED);
        do @(negedge clock_50); while(dut.debug_capture_pending || dut.debug_source_busy || dut.debugger_status_changed);
        assert(dut.debug_snapshot.source_snapshot.debugger.state==DBG_PAUSED);
        assert(dut.debug_snapshot.source_snapshot.cpu.pc==dut.cpu_debug_pc);
        assert(dut.debug_snapshot.source_snapshot.cpu.a==dut.cpu_debug_a);
        assert(dut.debug_snapshot.source_snapshot.cpu.sp==dut.cpu_debug_sp);
        assert(dut.debug_snapshot.source_snapshot.ppu.dot==dut.ppu_debug_dot);
        assert(dut.debug_snapshot.source_snapshot.ppu.scanline==dut.ppu_debug_scanline);
    endtask
    task automatic instruction_step;
        integer f, a;
        logic [20:0] apu_state;
        logic [15:0] count;
        f=fetches; a=apu_cpu_slots;
        apu_state={dut.apu.frame_sequence_cycle, dut.apu.cpu_cycle_odd,
                   dut.apu.frame_reset_pending, dut.apu.frame_reset_delay};
        count=dut.debugger_status.instruction_steps;
        send_command(DBG_STEP_I); await_pause();
        assert(fetches==f+1);
        assert(apu_cpu_slots>a);
        assert({dut.apu.frame_sequence_cycle, dut.apu.cpu_cycle_odd,
                dut.apu.frame_reset_pending, dut.apu.frame_reset_delay}!=apu_state);
        assert(dut.debugger_status.instruction_steps==count+16'd1);
        assert(dut.debug_snapshot.source_snapshot.debugger.instruction_steps==count+16'd1);
    endtask
    task automatic frame_step;
        integer f, a;
        logic [20:0] apu_state;
        logic [15:0] count;
        f=source_frames; a=apu_cpu_slots;
        apu_state={dut.apu.frame_sequence_cycle, dut.apu.cpu_cycle_odd,
                   dut.apu.frame_reset_pending, dut.apu.frame_reset_delay};
        count=dut.debugger_status.frame_steps;
        send_command(DBG_STEP_F); await_pause();
        assert(source_frames==f+1);
        assert(apu_cpu_slots>a);
        assert({dut.apu.frame_sequence_cycle, dut.apu.cpu_cycle_odd,
                dut.apu.frame_reset_pending, dut.apu.frame_reset_delay}!=apu_state);
        assert(dut.debugger_status.frame_steps==count+16'd1);
        assert(dma_reads==dma_completions*256 && dma_writes==dma_completions*256);
        assert(dut.debugger_status.frame_overrun<4000);
    endtask
    task automatic run_frames(input integer n);
        integer target_frame;
        target_frame=source_frames+n;
        while(source_frames<target_frame) @(negedge clock_50);
    endtask

    nes_debug_snapshot_t frame_snapshot;

    always #10 clock_50 = !clock_50;

    de1_soc_nes_vga_top #(
        .DEVELOPER_MODE_DEFAULT(1'b1),
        .PRG_INIT_FILE("build/cartridge/phase4db_playable_nrom128.prg.hex"),
        .CHR_INIT_FILE("build/cartridge/phase4db_playable_nrom128.chr.hex")
    ) dut (
        .CLOCK_50(clock_50),
        .KEY0(key0),
        .SW0(sw0), .SW1(sw1), .SW2(sw2), .SW3(sw3), .SW4(sw4),
        .SW5(sw5), .SW6(sw6), .SW7(sw7), .SW8(sw8), .SW9(sw9),
        .LEDR(ledr), .HEX0(hex0), .HEX1(hex1), .HEX2(hex2),
        .HEX3(hex3), .HEX4(hex4), .HEX5(hex5),
        .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b),
        .VGA_HS(vga_hs), .VGA_VS(vga_vs), .VGA_CLK(vga_clk),
        .VGA_BLANK_N(vga_blank_n), .VGA_SYNC_N(vga_sync_n)
    );

    task automatic set_buttons(input logic [7:0] buttons);
        begin
            {sw9, sw8, sw7, sw6, sw5, sw4, sw3, sw2} = buttons;
        end
    endtask

    task automatic request_virtual_next_page;
        logic [2:0] previous_page;
        logic [2:0] expected_page;
        begin
            previous_page = dut.developer_page_active;
            expected_page = (previous_page == 3'd4) ?
                            3'd0 : previous_page + 3'd1;
            do @(negedge dut.pixel_clk);
            while (dut.vga_frame_start);
            force dut.developer_page_next_request = 1'b1;
            @(posedge dut.pixel_clk);
            #1;
            force dut.developer_page_next_request = 1'b0;
            assert (dut.developer_page_active == previous_page);
            assert (dut.developer_page_request_pending);
            while (dut.developer_page_active == previous_page)
                @(posedge dut.pixel_clk);
            #1;
            assert (dut.developer_page_active == expected_page);
            assert (!dut.developer_page_request_pending);
            release dut.developer_page_next_request;
            page_changes = page_changes + 1;
        end
    endtask

    always @(posedge clock_50) begin
        integer shadow_address;
        if (!dut.system_reset) begin
            system_cycles <= system_cycles + 1;
            if (dut.nes_core_ppu_enable)
                ppu_ticks <= ppu_ticks + 1;
            if (dut.ppu_nmi_event)
                nmi_events <= nmi_events + 1;
            if (dut.dma_complete_event)
                dma_completions <= dma_completions + 1;
            if (dut.controller_debug_latch)
                controller_polls <= controller_polls + 1;

            if (dut.ppu_frame_start)
                current_sprite_x <= -1;
            if (dut.pixel_valid && dut.ppu_debug_pixel_source == 2'd2 &&
                current_sprite_x < 0)
                current_sprite_x <= 32'(dut.pixel_x);

            if (dut.framebuffer.accept_write) begin
                shadow_address = 32'({dut.pixel_y, dut.pixel_x});
                case (dut.framebuffer.selected_write_bank)
                    2'd1: shadow1[shadow_address] <=
                        {dut.pixel_emphasis, dut.pixel_color};
                    2'd2: shadow2[shadow_address] <=
                        {dut.pixel_emphasis, dut.pixel_color};
                    default: shadow0[shadow_address] <=
                        {dut.pixel_emphasis, dut.pixel_color};
                endcase
            end
            if (dut.capture_complete)
                bank_sprite_x[dut.framebuffer.completed_bank] <=
                    current_sprite_x;

        end
    end

    always @(posedge dut.pixel_clk) begin
        logic [63:0] current_cpu_state;
        if (!dut.video_reset && dut.debug_destination_update) begin
            snapshot_updates <= snapshot_updates + 1;
            current_cpu_state = {
                dut.debug_destination_snapshot.cpu.pc,
                dut.debug_destination_snapshot.cpu.a,
                dut.debug_destination_snapshot.cpu.x,
                dut.debug_destination_snapshot.cpu.y,
                dut.debug_destination_snapshot.cpu.sp,
                dut.debug_destination_snapshot.cpu.status,
                dut.debug_destination_snapshot.cpu.opcode
            };
            if (have_cpu_state && current_cpu_state != last_cpu_state)
                cpu_state_changes <= cpu_state_changes + 1;
            last_cpu_state <= current_cpu_state;
            have_cpu_state <= 1'b1;
        end
    end

    task automatic capture_real_combined_frame;
        integer trace_file;
        integer metadata_file;
        integer x;
        integer y;
        integer address;
        logic [8:0] expected_pixel;
        logic [1:0] selected_bank;
        begin
            do @(negedge dut.pixel_clk);
            while (!(dut.active_video && dut.scan_x == 0 &&
                     dut.scan_y == 0 && dut.debug_destination_valid &&
                     bank_sprite_x[dut.framebuffer_read_bank] >= 0));
            selected_bank = dut.framebuffer_read_bank;
            frame_snapshot = dut.debug_destination_snapshot;

            metadata_file = $fopen("build/sim/phase4ee_paused_snapshot.txt", "w");
            assert (metadata_file != 0);
            $fwrite(metadata_file, "pc %04x\n", frame_snapshot.cpu.pc);
            $fwrite(metadata_file, "a %02x\n", frame_snapshot.cpu.a);
            $fwrite(metadata_file, "x %02x\n", frame_snapshot.cpu.x);
            $fwrite(metadata_file, "y %02x\n", frame_snapshot.cpu.y);
            $fwrite(metadata_file, "sp %02x\n", frame_snapshot.cpu.sp);
            $fwrite(metadata_file, "status %02x\n", frame_snapshot.cpu.status);
            $fwrite(metadata_file, "opcode %02x\n", frame_snapshot.cpu.opcode);
            $fwrite(metadata_file, "bus_owner %x\n", frame_snapshot.cpu.bus_owner);
            $fwrite(metadata_file, "stalled %x\n", frame_snapshot.cpu.stalled);
            $fwrite(metadata_file, "scanline %03x\n", frame_snapshot.ppu.scanline);
            $fwrite(metadata_file, "dot %03x\n", frame_snapshot.ppu.dot);
            $fwrite(metadata_file, "frame_odd %x\n", frame_snapshot.ppu.frame_odd);
            $fwrite(metadata_file, "ctrl %02x\n", frame_snapshot.ppu.ctrl);
            $fwrite(metadata_file, "mask %02x\n", frame_snapshot.ppu.mask);
            $fwrite(metadata_file, "ppu_status %02x\n", frame_snapshot.ppu.status);
            $fwrite(metadata_file, "nmi_level %x\n", frame_snapshot.ppu.nmi_level);
            $fwrite(metadata_file, "vblank %x\n", frame_snapshot.ppu.vblank);
            $fwrite(metadata_file, "sprite_zero_hit %x\n", frame_snapshot.ppu.sprite_zero_hit);
            $fwrite(metadata_file, "mapper %02x\n", frame_snapshot.cartridge.mapper_number);
            $fwrite(metadata_file, "nrom_256 %x\n", frame_snapshot.cartridge.nrom_256);
            $fwrite(metadata_file, "prg_address %04x\n", frame_snapshot.cartridge.prg_address);
            $fwrite(metadata_file, "chr_address %04x\n", frame_snapshot.cartridge.chr_address);
            $fwrite(metadata_file, "mirroring %x\n", frame_snapshot.cartridge.mirroring);
            $fwrite(metadata_file, "pad1 %02x\n", frame_snapshot.controller.live1);
            $fwrite(metadata_file, "dma_active %x\n", frame_snapshot.dma.active);
            $fwrite(metadata_file, "dma_page %02x\n", frame_snapshot.dma.source_page);
            $fwrite(metadata_file, "dma_index %02x\n", frame_snapshot.dma.byte_index);
            $fwrite(metadata_file, "snapshot_id %08x\n", frame_snapshot.system.snapshot_id);
            $fwrite(metadata_file, "source_frame %08x\n", frame_snapshot.system.source_frame_number);
            $fwrite(metadata_file, "nmi_count %08x\n", frame_snapshot.system.nmi_count);
            $fwrite(metadata_file, "dma_count %08x\n", frame_snapshot.system.dma_count);
            $fwrite(metadata_file, "debugger_state %x\n", frame_snapshot.debugger.state);
            $fwrite(metadata_file, "debugger_command %x\n", frame_snapshot.debugger.last_command);
            $fwrite(metadata_file, "debugger_result %x\n", frame_snapshot.debugger.result);
            $fwrite(metadata_file, "debugger_sequence %x\n", frame_snapshot.debugger.sequence_id);
            $fwrite(metadata_file, "instruction_steps %x\n", frame_snapshot.debugger.instruction_steps);
            $fwrite(metadata_file, "frame_steps %x\n", frame_snapshot.debugger.frame_steps);
            $fwrite(metadata_file, "step_pc_before %x\n", frame_snapshot.debugger.pc_before);
            $fwrite(metadata_file, "step_pc_after %x\n", frame_snapshot.debugger.pc_after);
            $fwrite(metadata_file, "frame_overrun %x\n", frame_snapshot.debugger.frame_overrun);
            $fwrite(metadata_file, "pause_boundary %x\n", frame_snapshot.debugger.boundary);
            $fclose(metadata_file);

            trace_file = $fopen("build/sim/phase4ee_paused_combined_pixels.txt", "w");
            assert (trace_file != 0);
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    assert (dut.active_video && dut.scan_x == 10'(x) &&
                            dut.scan_y == 10'(y));
                    assert (dut.framebuffer_read_bank == selected_bank);
                    assert (dut.debug_destination_snapshot == frame_snapshot)
                        else $fatal(1, "snapshot tore inside displayed frame");
                    if (x < 512) begin
                        address = (y >> 1) * 256 + (x >> 1);
                        case (selected_bank)
                            2'd1: expected_pixel = shadow1[address];
                            2'd2: expected_pixel = shadow2[address];
                            default: expected_pixel = shadow0[address];
                        endcase
                    end else
                        expected_pixel = 9'h000;
                    $fwrite(trace_file, "%0d %0d %03x %02x%02x%02x\n",
                            x, y, expected_pixel, vga_r, vga_g, vga_b);
                    combined_pixels = combined_pixels + 1;
                    if (x != 639)
                        @(negedge dut.pixel_clk);
                    else if (y != 479) begin
                        do @(negedge dut.pixel_clk);
                        while (!(dut.active_video && dut.scan_x == 0 &&
                                 dut.scan_y == 10'(y + 1)));
                    end
                end
            end
            $fclose(trace_file);
        end
    endtask

    initial begin
        integer game_x, baseline_frames, baseline_polls, baseline_dmas, baseline_nmi;
        integer displayed_x, old_displayed_x;
        logic [15:0] frozen_pc;
        logic [17:0] frozen_ppu;
        logic [20:0] frozen_apu;
        logic [1:0] frozen_bank;
        $dumpfile("build/sim/nes_debugger_playable.fst");
        $dumpvars(0,dut.debugger,dut.debugger_mailbox);
        bank_sprite_x[0]=-1; bank_sprite_x[1]=-1; bank_sprite_x[2]=-1;
        repeat(10) @(posedge clock_50);
        key0=1;
        wait(!dut.system_reset && !dut.video_reset);
        assert(dut.debugger_status.state==DBG_RUNNING);
        while(dut.nes.internal_cpu_ram.memory[11'h002]!=1) @(negedge clock_50);
        set_buttons(0);
        run_frames(5);
        send_command(DBG_PAUSE); await_pause();
        frozen_pc=dut.cpu_debug_pc; frozen_ppu={dut.ppu_debug_scanline,dut.ppu_debug_dot};
        frozen_apu={dut.apu.frame_sequence_cycle, dut.apu.cpu_cycle_odd,
                    dut.apu.frame_reset_pending, dut.apu.frame_reset_delay};
        baseline_frames=source_frames; baseline_polls=controller_polls;
        baseline_dmas=dma_completions; baseline_nmi=nmi_events;
        // Ten whole VGA frames while NES is paused: page selection, coherent
        // heartbeat snapshots, scanout, and health must all stay live.
        for(integer p=0;p<10;p++) begin
            request_virtual_next_page();
            assert(dut.cpu_debug_pc==frozen_pc);
            assert({dut.ppu_debug_scanline,dut.ppu_debug_dot}==frozen_ppu);
            assert({dut.apu.frame_sequence_cycle, dut.apu.cpu_cycle_odd,
                    dut.apu.frame_reset_pending,
                    dut.apu.frame_reset_delay}==frozen_apu);
            assert(source_frames==baseline_frames && controller_polls==baseline_polls);
            assert(dma_completions==baseline_dmas && nmi_events==baseline_nmi);
            assert(!dut.debug_snapshot_stale);
            if(p>1) assert(dut.debug_destination_snapshot.debugger.state==DBG_PAUSED);
        end
        frozen_bank=dut.framebuffer_read_bank;
        capture_real_combined_frame();
        assert(dut.framebuffer_read_bank==frozen_bank);
        assert(dut.debug_destination_snapshot.cpu.pc==frozen_pc);
        // A stopped snapshot commit path must still become STALE while the
        // machine is intentionally paused, then recover when commits resume.
        force dut.debug_snapshot.destination_frame_start=1'b0;
        repeat(6) request_virtual_next_page();
        assert(dut.debug_snapshot_stale);
        release dut.debug_snapshot.destination_frame_start;
        repeat(2) request_virtual_next_page();
        assert(!dut.debug_snapshot_stale);
        $display("Paused scanout/pages/snapshots and stale-fault recovery PASS");
        instruction_step(); instruction_step(); instruction_step();
        frame_step(); frame_step();
        // One input poll changes game RAM once. Existing ROM OAM/framebuffer
        // pipeline latency is preserved; subsequent no-input tokens flush it.
        game_x=32'(dut.nes.internal_cpu_ram.memory[11'h003]);
        old_displayed_x=bank_sprite_x[dut.framebuffer_read_bank];
        set_buttons(8'h80); // Right
        repeat(12) @(negedge clock_50);
        baseline_polls=controller_polls; baseline_dmas=dma_completions;
        frame_step();
        assert(controller_polls==baseline_polls+1 && dma_completions==baseline_dmas+1);
        assert(dut.nes.internal_cpu_ram.memory[11'h010]==8'h80);
        assert(32'(dut.nes.internal_cpu_ram.memory[11'h003])==game_x+2);
        set_buttons(0);
        frame_step(); frame_step();
        assert(32'(dut.nes.internal_cpu_ram.memory[11'h003])==game_x+2);
        // Allow only the video-domain handoff, keeping NES paused.
        request_virtual_next_page(); request_virtual_next_page();
        displayed_x=bank_sprite_x[dut.framebuffer_read_bank];
        assert(displayed_x==old_displayed_x+2) else $fatal(1,"controller/framebuffer x=%0d expected=%0d",displayed_x,old_displayed_x+2);
        $display("Controller frame-step RAM=%0d->%0d display=%0d->%0d poll=%0d DMA=%0d",game_x,game_x+2,old_displayed_x,displayed_x,controller_polls,dma_completions);
        // Pause requests near VBlank, during interrupt entry, and during DMA.
        for(integer scenario=0;scenario<4;scenario++) begin
            send_command(DBG_RUN);
            case(scenario)
                0: do @(negedge clock_50); while(!(dut.ppu_debug_scanline==240 && dut.ppu_debug_dot>=330));
                1: do @(negedge clock_50); while(!(dut.ppu_debug_scanline==241 && dut.ppu_debug_dot==1));
                2: do @(negedge clock_50); while(dut.cpu_debug_execution_state!=CPU_STATE_INTERRUPT_PUSH_LOW);
                3: do @(negedge clock_50); while(!dut.dma_debug_active || dut.dma_debug_write_count<255);
            endcase
            send_command(DBG_PAUSE); await_pause();
            instruction_step(); frame_step();
            $display("Directed playable pause scenario=%0d PASS",scenario);
        end
        $dumpoff; // Keep a directed waveform; the long run retains assertions.
        // Mixed run/pause/three instruction steps/two frame steps/run/pause/
        // one instruction step/run, repeated over more than 100 source frames.
        for(integer iteration=0;iteration<16;iteration++) begin
            send_command(DBG_RUN); run_frames(3);
            send_command(DBG_PAUSE); await_pause();
            instruction_step(); instruction_step(); instruction_step();
            frame_step(); frame_step();
            send_command(DBG_RUN); run_frames(2);
            send_command(DBG_PAUSE); await_pause(); instruction_step();
            $display("Mixed debugger iteration=%0d frames=%0d PASS",iteration,source_frames);
        end
        send_command(DBG_RUN); run_frames(3);
        send_command(DBG_PAUSE); await_pause();
        assert(source_frames>100);
        assert(deferred_frames>0);
        assert(acknowledgements==commands);
        assert(nmi_events==irq_entries || nmi_events==irq_entries+1);
        assert(dma_reads==dma_completions*256 && dma_writes==dma_completions*256);
        assert(apu_dma_advances>dma_completions*500);
        assert(!dut.debug_snapshot_stale && !dut.write_sequence_error && !dut.write_range_error);
        $display("PASS: playable debugger mixed long run frames=%0d commands=%0d acknowledgements=%0d I=%0d F=%0d NMI=%0d entries=%0d DMA=%0d polls=%0d pages=%0d snapshots=%0d deferred_frames=%0d",source_frames,commands,acknowledgements,dut.debugger_status.instruction_steps,dut.debugger_status.frame_steps,nmi_events,irq_entries,dma_completions,controller_polls,page_changes,snapshot_updates,deferred_frames);
        // Shared KEY0 reset restores RUNNING, sequence/counters zero, no token.
        force dut.debugger_request_valid=1'b0;
        key0=0;
        repeat(100) @(posedge clock_50);
        assert(dut.debugger_status=='0);
        key0=1;
        wait(!dut.system_reset && !dut.video_reset);
        repeat(100) @(posedge clock_50);
        assert(dut.debugger_status.state==DBG_RUNNING && dut.debugger_status.sequence_id==0);
        assert(!dut.debugger_request_busy && !dut.debugger_ack);
        $finish;
    end
    initial begin #5000000000; $fatal(1,"playable debugger timeout"); end
endmodule
