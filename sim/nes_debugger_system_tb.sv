`timescale 1ns/1ps
module nes_debugger_system_tb;
    import cpu_pkg::*;
    import nes_debugger_pkg::*;
    import nes_debug_snapshot_pkg::*;
    logic clk = 0, reset = 1;
    logic command_valid = 0;
    logic [2:0] command = 0;
    logic [15:0] sequence_id = 0;
    logic command_done, authorized, changed;
    logic [2:0] response_state;
    logic [1:0] result;
    nes_debugger_snapshot_t status;
    logic cpu_enable, ppu_enable, dma_active, frame_start;
    logic [5:0] execution_state;
    logic [15:0] pc, cart_address;
    logic [7:0] a, x, y, sp, flags;
    logic [8:0] scanline, dot;
    logic [7:0] rom [0:65535];
    logic dma_read, dma_write, dma_done;
    logic [8:0] dma_reads, dma_writes;
    logic [9:0] dma_slots;
    logic dma_odd;
    integer frames = 0, retired_fetches = 0, dmas = 0;
    integer total_reads = 0, total_writes = 0, interrupt_entries = 0;
    logic old_fetch = 0;
    integer steps = 0, seq = 0;
    integer elapsed_ppu_ticks = 0, canonical_tick = 0;
    logic nmi_inject = 0;
    logic inject_enable = 0;
    always #5 clk = !clk;

    nes_debugger control (
        .clk(clk), .reset(reset), .command_valid(command_valid),
        .command(command), .command_sequence(sequence_id),
        .command_done(command_done), .response_state(response_state),
        .response_result(result), .snapshot_ready(1'b1),
        .cpu_enable(cpu_enable), .cpu_execution_state(execution_state),
        .cpu_pc(pc), .dma_active(dma_active), .ppu_enable(ppu_enable),
        .frame_start(frame_start), .scheduler_authorized(authorized),
        .status_changed(changed), .status(status)
    );
    /* verilator lint_off PINMISSING */
    /* verilator lint_off PINCONNECTEMPTY */
    nes_core nes (
        .clk(clk), .reset(reset), .nes_enable(authorized), .irq(1'b0),
        .mirroring_mode(2'd0), .cart_cpu_address(cart_address),
        .cart_cpu_read_data(rom[cart_address]), .apu_cpu_read_data(8'd0),
        .controller_cpu_read_data(8'd0), .chr_read_data(8'd0),
        .cpu_enable(cpu_enable), .ppu_enable(ppu_enable),
        .cpu_debug_execution_state(execution_state), .cpu_debug_pc(pc),
        .cpu_debug_a(a), .cpu_debug_x(x), .cpu_debug_y(y),
        .cpu_debug_sp(sp), .cpu_debug_status(flags),
        .dma_active(dma_active), .dma_read_event(dma_read),
        .dma_write_event(dma_write), .dma_complete_event(dma_done),
        .dma_read_count(dma_reads), .dma_write_count(dma_writes),
        .dma_stall_cycles(dma_slots), .dma_started_odd(dma_odd),
        .ppu_scanline(scanline), .ppu_dot(dot), .ppu_frame_start(frame_start)
    );
    /* verilator lint_on PINMISSING */
    /* verilator lint_on PINCONNECTEMPTY */

    always @(posedge clk) begin
        if (reset) begin
            frames <= 0; retired_fetches <= 0; dmas <= 0;
            total_reads <= 0; total_writes <= 0; old_fetch <= 0;
            interrupt_entries <= 0;
            elapsed_ppu_ticks <= 0; canonical_tick <= 0;
        end else begin
            old_fetch <= cpu_enable && execution_state == CPU_STATE_FETCH;
            if (old_fetch) begin
                if (execution_state == CPU_STATE_INTERRUPT_DUMMY)
                    interrupt_entries <= interrupt_entries + 1;
                else
                    retired_fetches <= retired_fetches + 1;
            end
            if (ppu_enable) elapsed_ppu_ticks <= elapsed_ppu_ticks + 1;
            if (frame_start) begin
                frames <= frames + 1;
                canonical_tick <= elapsed_ppu_ticks + 1;
            end
            if (dma_read) total_reads <= total_reads + 1;
            if (dma_write) total_writes <= total_writes + 1;
            if (dma_done) begin
                dmas <= dmas + 1;
                assert (dma_reads == 256 && dma_writes == 256);
                assert (dma_slots == (dma_odd ? 514 : 513));
            end
            if (status.state == DBG_PAUSED) begin
                assert (!cpu_enable && !ppu_enable && !dma_active);
                assert (execution_state == CPU_STATE_FETCH);
            end
        end
    end

    task automatic send(input logic [2:0] cmd, input logic [1:0] expected = DBG_OK);
        @(negedge clk);
        command_valid = 1;
        command = cmd;
        seq++;
        sequence_id = 16'(seq);
        do @(negedge clk); while (!command_done);
        assert (result == expected) else $fatal(1,"command %0d result %0d",cmd,result);
        assert (status.sequence_id == 16'(seq));
        repeat (3) @(negedge clk);
        command_valid = 0;
        @(negedge clk);
    endtask
    task automatic paused;
        do @(negedge clk); while (status.state != DBG_PAUSED);
        assert (!dma_active && execution_state == CPU_STATE_FETCH);
    endtask
    task automatic frozen;
        logic [15:0] old_pc;
        logic [17:0] coordinate;
        integer f, r, w;
        old_pc = pc; coordinate = {scanline,dot};
        f = retired_fetches; r=total_reads; w=total_writes;
        repeat (100) @(negedge clk);
        assert (pc == old_pc && {scanline,dot} == coordinate);
        assert (retired_fetches == f && total_reads == r && total_writes == w);
    endtask
    task automatic step(input logic [15:0] expected_pc,
                        input logic [7:0] ea, ex, ey, esp, ef = 8'h24);
        integer before_fetch;
        logic [15:0] before_pc;
        before_fetch = retired_fetches; before_pc = pc;
        send(DBG_STEP_I);
        paused(); steps++;
        assert (retired_fetches == before_fetch + 1)
            else $fatal(1,"step fetched %0d instructions",retired_fetches-before_fetch);
        assert (status.instruction_steps == 16'(steps));
        assert (pc == expected_pc && a == ea && x == ex && y == ey && sp == esp)
            else $fatal(1,"step %0d PC=%04x A=%02x X=%02x Y=%02x SP=%02x expected PC=%04x", steps,pc,a,x,y,sp,expected_pc);
        assert (flags == ef) else $fatal(1,"flags step=%0d actual=%02x expected=%02x",steps,flags,ef);
        assert (status.pc_before == before_pc && status.pc_after == pc);
        frozen();
    endtask
    task automatic pulse_nmi;
        force nes.cpu.nmi = 1'b1;
        repeat (5) @(negedge clk);
        force nes.cpu.nmi = 1'b0;
        repeat (5) @(negedge clk);
    endtask
    task automatic reset_to_program(input logic [15:0] vector);
        @(negedge clk); reset = 1; command_valid = 0;
        rom['hfffc] = vector[7:0]; rom['hfffd] = vector[15:8];
        repeat (6) @(negedge clk);
        reset = 0; seq = 0; steps = 0;
        send(DBG_PAUSE); paused();
        assert (pc == vector && status.instruction_steps == 0);
    endtask
    task automatic frame_step;
        integer f;
        f=frames;
        send(DBG_STEP_F);
        // Busy commands are acknowledged with rejection, never queued.
        send(DBG_STEP_I, DBG_BUSY);
        paused();
        assert (frames == f+1) else $fatal(1,"frame token advanced %0d",frames-f);
        assert (status.boundary == 3);
        // Independently subtract accepted-tick timestamps, including any tick
        // on the effective pause edge but excluding the canonical event tick.
        assert (32'(status.frame_overrun) == elapsed_ppu_ticks - canonical_tick);
        frozen();
    endtask
    initial begin
        $dumpfile("build/sim/nes_debugger_system.fst");
        $dumpvars(0, control);
        for (integer i=0;i<65536;i++) rom[i]=8'hea;
        // A project-owned deterministic instruction/control-flow program.
        rom['h8000]='ha9; rom['h8001]='h10;
        rom['h8002]='haa; rom['h8003]='ha0; rom['h8004]=3;
        rom['h8005]='h69; rom['h8006]=5;
        rom['h8007]='h85; rom['h8008]='h10;
        rom['h8009]='he8; rom['h800a]='hca; rom['h800b]='h48;
        rom['h800c]='ha9; rom['h800d]=0; rom['h800e]='h68;
        rom['h800f]='hd0; rom['h8010]=2;
        rom['h8011]='ha9; rom['h8012]='hee;
        rom['h8013]='hf0; rom['h8014]=2;
        rom['h8015]='h20; rom['h8016]='h30; rom['h8017]='h80;
        rom['h8018]='h4c; rom['h8019]='h20; rom['h801a]='h80;
        rom['h8020]='ha9; rom['h8021]=2;
        rom['h8022]='h8d; rom['h8023]='h14; rom['h8024]='h40;
        rom['h8025]=0; rom['h8026]='hea; rom['h8027]='he8;
        rom['h8028]='h4c; rom['h8029]='h28; rom['h802a]='h80;
        rom['h8030]='hc8; rom['h8031]='h60;
        rom['h9000]='he6; rom['h9001]='h11; rom['h9002]='h40;
        rom['h9100]='h40;
        rom['hfffa]=0; rom['hfffb]='h90;
        rom['hfffe]=0; rom['hffff]='h91;
        // Continuous DMA loop used to force a real transfer across dot 0.
        rom['h8200]='ha9; rom['h8201]=2;
        rom['h8202]='h8d; rom['h8203]='h14; rom['h8204]='h40;
        rom['h8205]='h4c; rom['h8206]=2; rom['h8207]='h82;
        reset_to_program('h8000);
        send(3'd7,DBG_BAD_COMMAND);
        send(DBG_PAUSE); frozen();
        step('h8002,'h10,0,0,'hfd);
        step('h8003,'h10,'h10,0,'hfd);
        step('h8005,'h10,'h10,3,'hfd);
        step('h8007,'h15,'h10,3,'hfd);
        step('h8009,'h15,'h10,3,'hfd);
        assert (nes.internal_cpu_ram.memory['h10] == 'h15);
        step('h800a,'h15,'h11,3,'hfd);
        step('h800b,'h15,'h10,3,'hfd);
        step('h800c,'h15,'h10,3,'hfc);
        assert (nes.internal_cpu_ram.memory['h1fd] == 'h15);
        step('h800e,0,'h10,3,'hfc,'h26); assert (flags[1]);
        step('h800f,'h15,'h10,3,'hfd); assert (!flags[1]);
        step('h8013,'h15,'h10,3,'hfd); // branch taken
        step('h8015,'h15,'h10,3,'hfd); // branch not taken
        step('h8030,'h15,'h10,3,'hfb); // JSR
        assert(nes.internal_cpu_ram.memory['h1fd]=='h80 && nes.internal_cpu_ram.memory['h1fc]=='h17);
        step('h8031,'h15,'h10,4,'hfb);
        step('h8018,'h15,'h10,4,'hfd); // RTS
        step('h8020,'h15,'h10,4,'hfd); // JMP
        step('h8022,2,'h10,4,'hfd);
        for (integer i=0;i<256;i++) nes.internal_cpu_ram.memory['h200+i]=8'(i^'h5a);
        step('h8025,2,'h10,4,'hfd); // entire DMA belongs to this token
        assert (dmas==1 && total_reads==256 && total_writes==256);
        for (integer i=0;i<256;i++)
            assert (nes.ppu.oam.primary_oam[i] == 8'(i^'h5a));
        step('h9100,2,'h10,4,'hfa); // BRK complete stack/vector
        assert(nes.internal_cpu_ram.memory['h1fc]=='h27 && nes.internal_cpu_ram.memory['h1fb]=='h34);
        step('h8027,2,'h10,4,'hfd); // RTI
        step('h8028,2,'h11,4,'hfd);
        // A pending NMI vectors normally, then the token executes exactly
        // one handler opcode. Entry itself must not consume that token.
        nes.internal_cpu_ram.memory['h11]=0;
        pulse_nmi();
        step('h9002,2,'h11,4,'hfa);
        assert (interrupt_entries==1);
        step('h8028,2,'h11,4,'hfd);
        // NMI arriving during a stepped JMP stays pending at its completion.
        fork
            begin
                do @(negedge clk); while (!(cpu_enable && execution_state==CPU_STATE_FETCH));
                pulse_nmi();
            end
            begin step('h8028,2,'h11,4,'hfd); end
        join
        assert (interrupt_entries==1);
        step('h9002,2,'h11,4,'hfa);
        step('h8028,2,'h11,4,'hfd);
        // Immediately after a completed step, while fully paused.
        pulse_nmi();
        step('h9002,2,'h11,4,'hfa);
        step('h8028,2,'h11,4,'hfd);
        assert (interrupt_entries==3 && nes.internal_cpu_ram.memory['h11]==3);
        release nes.cpu.nmi;
        $display("Deterministic/NMI steps=%0d interrupt_entries=%0d DMA=%0d",steps,interrupt_entries,dmas);
        begin
            integer overruns;
            overruns=0;
            repeat(3) begin
                frame_step();
                if(status.frame_overrun>0) overruns++;
            end
            assert(overruns>0);
            $display("Directed CPU frame completion overruns=%0d",overruns);
        end
        assert (status.frame_steps==3);
        send(DBG_RUN); send(DBG_STEP_I,DBG_WRONG_STATE);
        repeat(100) @(negedge clk);
        send(DBG_PAUSE); paused(); frozen();
        // Pause before DMA, during DMA, and within its final byte.
        reset_to_program('h8200);
        frozen();
        step('h8202,2,0,0,'hfd);
        for (integer phase_case=0;phase_case<2;phase_case++) begin
            send(DBG_RUN);
            do @(negedge clk); while (!dma_active ||
                (phase_case==1 && dma_writes<255));
            send(DBG_PAUSE); paused();
            assert (dma_reads==256 && dma_writes==256);
            frozen();
        end
        // Multiple actual PPU frame boundaries reached during the DMA loop.
        begin
            integer old_dmas, nonzero_overruns;
            nonzero_overruns=0;
            for(integer i=0;i<4;i++) begin
                old_dmas=dmas;
                frame_step();
                assert(dmas>old_dmas);
                if(status.frame_overrun!=0) nonzero_overruns++;
                assert(status.frame_overrun<4000);
                assert(total_reads==dmas*256 && total_writes==dmas*256);
            end
            assert(nonzero_overruns>0) else $fatal(1,"DMA overrun scenario not exercised");
            $display("Directed frame/DMA overruns=%0d last_ticks=%0d",nonzero_overruns,status.frame_overrun);
        end
        $display("PASS: debugger CPU stepping/control flow/BRK/RTI/DMA/NMI/pause/frame-overrun/reset commands=%0d",seq);
        $finish;
    end
    initial begin #30000000; $fatal(1,"debugger system timeout state=%0d pc=%04x",status.state,pc); end
endmodule
