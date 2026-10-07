`timescale 1ns/1ps

module nes_dmc_dma_phase5f_tb;
    import nes_system_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_cycle_slot = 1'b0;
    logic cpu_cycle_odd = 1'b0;
    logic halt_allowed = 1'b1;
    logic request = 1'b0;
    logic [15:0] request_address = 16'h0000;
    logic acknowledge;
    logic read_request;
    logic read_event;
    logic [15:0] read_address;
    logic active;
    logic cpu_stall;
    logic [2:0] phase;
    logic started_odd;
    logic [2:0] elapsed_cpu_cycles;
    logic start_event;
    logic complete_event;

    integer transactions = 0;
    integer acknowledges = 0;
    integer paused_fabric_cycles = 0;

    nes_dmc_dma dut (.*);
    always #5 clk <= !clk;

    always @(posedge clk) begin
        if (!reset && acknowledge) begin
            acknowledges <= acknowledges + 1;
            assert (read_event && read_request && cpu_stall);
        end
    end

    task automatic idle_fabric_cycle;
        logic [2:0] held_phase;
        logic [2:0] held_elapsed;
        begin
            @(negedge clk);
            cpu_cycle_slot = 1'b0;
            held_phase = phase;
            held_elapsed = elapsed_cpu_cycles;
            @(posedge clk);
            #1;
            assert (phase == held_phase &&
                    elapsed_cpu_cycles == held_elapsed);
            paused_fabric_cycles++;
        end
    endtask

    task automatic run_transaction(
        input logic odd,
        input logic [15:0] address,
        input integer expected_cycles
    );
        integer slots;
        begin
            slots = 0;
            @(negedge clk);
            request = 1'b1;
            request_address = address;
            cpu_cycle_odd = odd;
            cpu_cycle_slot = 1'b1;
            #1;
            assert (cpu_stall && start_event);
            @(posedge clk);
            #1;
            slots++;
            cpu_cycle_slot = 1'b0;
            assert (active && phase == NES_DMA_DUMMY);
            assert (read_address == address && started_odd == odd);

            // FPGA fabric clocks and even a changing request-side address do
            // not mutate the captured transaction without a CPU slot.
            request_address = address ^ 16'hffff;
            repeat (7) idle_fabric_cycle();
            assert (read_address == address);

            while (active) begin
                @(negedge clk);
                cpu_cycle_slot = 1'b1;
                #1;
                assert (cpu_stall && read_address == address);
                @(posedge clk);
                #1;
                slots++;
                cpu_cycle_slot = 1'b0;
            end
            request = 1'b0;
            #1;
            assert (complete_event);
            assert (slots == expected_cycles);
            assert (elapsed_cpu_cycles == expected_cycles[2:0]);
            assert (!cpu_stall && phase == NES_DMA_IDLE);
            transactions++;
            @(posedge clk);
            #1;
            assert (!complete_event);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_dmc_dma_phase5f.fst");
        $dumpvars(0, nes_dmc_dma_phase5f_tb);

        repeat (3) @(posedge clk);
        #1;
        assert (!active && !cpu_stall && !acknowledge &&
                phase == NES_DMA_IDLE);
        reset = 1'b0;

        run_transaction(1'b0, 16'hc123, 3);
        run_transaction(1'b1, 16'hfffe, 4);

        // A DMC halt never interrupts a CPU write: the request remains held
        // until the integration layer reports a haltable read slot.
        @(negedge clk);
        request = 1'b1;
        request_address = 16'hd00d;
        halt_allowed = 1'b0;
        repeat (8) begin
            cpu_cycle_slot = 1'b1;
            @(posedge clk);
            #1;
            assert (!active && !cpu_stall && !start_event);
            @(negedge clk);
        end
        halt_allowed = 1'b1;
        cpu_cycle_odd = 1'b0;
        cpu_cycle_slot = 1'b1;
        @(posedge clk);
        #1;
        cpu_cycle_slot = 1'b0;
        assert (active && cpu_stall);
        repeat (10) idle_fabric_cycle();
        assert (active && phase == NES_DMA_DUMMY);

        // Reset aborts a pending transfer without an acknowledge.
        reset = 1'b1;
        @(posedge clk);
        #1;
        request = 1'b0;
        assert (!active && !cpu_stall && !acknowledge &&
                elapsed_cpu_cycles == 0 && phase == NES_DMA_IDLE);

        assert (transactions == 2 && acknowledges == 2);
        assert (paused_fabric_cycles == 24);
        $display("PASS: Phase 5F DMC DMA transactions=%0d acknowledgements=%0d cycles=3/4 pause=%0d write-deferral/reset",
                 transactions, acknowledges, paused_fabric_cycles);
        $finish;
    end
endmodule
