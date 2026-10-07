`timescale 1ns/1ps

module nes_phase4d_dma_nmi_tb;
    import nes_system_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic nmi = 1'b0;
    logic cpu_cycle_parity = 1'b0;
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic [7:0] cpu_write_data;
    logic [7:0] cpu_read_data;
    logic cpu_write_enable;
    logic cpu_bus_valid;
    logic [7:0] cpu_a;
    logic [7:0] cpu_x;
    logic [7:0] cpu_y;
    logic [7:0] cpu_sp;
    logic [15:0] cpu_pc;
    logic [7:0] cpu_status;

    logic dma_trigger = 1'b0;
    logic [7:0] dma_trigger_page = 8'h02;
    logic [15:0] dma_source_address;
    logic dma_source_request;
    logic dma_read_event;
    logic [7:0] dma_write_data;
    logic dma_write_event;
    logic dma_active;
    logic dma_stall;
    logic [2:0] dma_phase;
    logic [7:0] dma_page;
    logic [7:0] dma_index;
    logic dma_started_odd;
    logic dma_start_event;
    logic dma_complete_event;
    logic dma_dummy;
    logic dma_align;
    logic [9:0] dma_elapsed;
    logic [8:0] dma_reads;
    logic [8:0] dma_writes;

    logic [7:0] memory [0:65535];
    logic previous_dma_active = 1'b0;
    logic [15:0] stalled_pc;
    logic [7:0] stalled_a;
    logic [7:0] stalled_x;
    logic [7:0] stalled_y;
    logic [7:0] stalled_sp;
    logic [7:0] stalled_status;
    integer index;
    integer completed_dmas = 0;
    integer nmi_pulses = 0;

    always #5 clk <= !clk;

    assign cpu_enable = !reset && !dma_stall;
    assign cpu_read_data = memory[cpu_address];

    /* verilator lint_off PINCONNECTEMPTY */
    cpu_core cpu (
        .clk(clk),
        .reset(reset),
        .cpu_enable(cpu_enable),
        .nmi(nmi),
        .irq(1'b0),
        .bus_address(cpu_address),
        .bus_write_data(cpu_write_data),
        .bus_read_data(cpu_read_data),
        .bus_write_enable(cpu_write_enable),
        .bus_valid(cpu_bus_valid),
        .debug_a(cpu_a),
        .debug_x(cpu_x),
        .debug_y(cpu_y),
        .debug_sp(cpu_sp),
        .debug_pc(cpu_pc),
        .debug_status(cpu_status),
        .debug_instruction(),
        .debug_execution_state(),
        .debug_decoded_instruction(),
        .debug_addressing_mode(),
        .debug_effective_address(),
        .debug_page_cross(),
        .debug_page_cross_valid()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    nes_oam_dma dma (
        .clk(clk),
        .reset(reset),
        .cpu_cycle_slot(!reset),
        .cpu_cycle_odd(cpu_cycle_parity),
        .hold(1'b0),
        .trigger(dma_trigger),
        .trigger_page(dma_trigger_page),
        .source_read_data(dma_source_address[7:0]),
        .source_address(dma_source_address),
        .source_read_request(dma_source_request),
        .source_read_event(dma_read_event),
        .oam_write_data(dma_write_data),
        .oam_write_strobe(dma_write_event),
        .active(dma_active),
        .cpu_stall(dma_stall),
        .phase(dma_phase),
        .source_page(dma_page),
        .byte_index(dma_index),
        .started_odd(dma_started_odd),
        .start_event(dma_start_event),
        .complete_event(dma_complete_event),
        .dummy_cycle(dma_dummy),
        .alignment_cycle(dma_align),
        .elapsed_cpu_cycles(dma_elapsed),
        .read_count(dma_reads),
        .write_count(dma_writes)
    );

    always @(posedge clk) begin
        if (reset) begin
            cpu_cycle_parity <= 1'b0;
            previous_dma_active <= 1'b0;
        end else begin
            cpu_cycle_parity <= !cpu_cycle_parity;
            if (cpu_enable && cpu_bus_valid && cpu_write_enable)
                memory[cpu_address] <= cpu_write_data;

            assert (dma_source_request ==
                    (dma_active && dma_phase == NES_DMA_READ));
            assert (dma_dummy ==
                    (dma_active && dma_phase == NES_DMA_DUMMY));
            assert (dma_align ==
                    (dma_active && dma_phase == NES_DMA_ALIGN));
            if (dma_read_event)
                assert (dma_source_address == {dma_page, dma_index});
            if (dma_write_event)
                assert (dma_write_data == dma_index);

            if (dma_active && !previous_dma_active) begin
                stalled_pc <= cpu_pc;
                stalled_a <= cpu_a;
                stalled_x <= cpu_x;
                stalled_y <= cpu_y;
                stalled_sp <= cpu_sp;
                stalled_status <= cpu_status;
            end else if (dma_active) begin
                assert (!cpu_enable);
                assert (cpu_pc == stalled_pc && cpu_a == stalled_a &&
                        cpu_x == stalled_x && cpu_y == stalled_y &&
                        cpu_sp == stalled_sp && cpu_status == stalled_status);
            end

            if (dma_complete_event) begin
                completed_dmas <= completed_dmas + 1;
                assert (dma_reads == 9'd256 && dma_writes == 9'd256);
                assert (dma_elapsed ==
                        (dma_started_odd ? 10'd514 : 10'd513));
            end
            previous_dma_active <= dma_active;
        end
    end

    task automatic pulse_nmi;
        begin
            @(negedge clk);
            nmi = 1'b1;
            repeat (4) @(posedge clk);
            @(negedge clk);
            nmi = 1'b0;
            nmi_pulses = nmi_pulses + 1;
        end
    endtask

    task automatic start_dma(input logic [7:0] page);
        begin
            @(negedge clk);
            dma_trigger_page = page;
            dma_trigger = 1'b1;
            #1;
            assert (dma_start_event);
            @(posedge clk);
            #1;
            dma_trigger = 1'b0;
            assert (dma_active);
        end
    endtask

    task automatic wait_nmi_count(input logic [7:0] expected);
        integer timeout;
        begin
            timeout = 0;
            while (memory[16'h0010] != expected && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert (timeout < 2000)
                else $fatal(1, "NMI count timeout expected=%0d got=%0d pc=%04x",
                            expected, memory[16'h0010], cpu_pc);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_phase4d_dma_nmi.fst");
        $dumpvars(0, nes_phase4d_dma_nmi_tb);

        for (index = 0; index < 65536; index++)
            memory[index] = 8'hea;
        memory[16'h0010] = 8'h00;
        memory[16'h8000] = 8'h4c;  // JMP $8000
        memory[16'h8001] = 8'h00;
        memory[16'h8002] = 8'h80;
        memory[16'h9000] = 8'he6;  // INC $10
        memory[16'h9001] = 8'h10;
        memory[16'h9002] = 8'h40;  // RTI
        memory[16'hfffa] = 8'h00;
        memory[16'hfffb] = 8'h90;
        memory[16'hfffc] = 8'h00;
        memory[16'hfffd] = 8'h80;
        memory[16'hfffe] = 8'h00;
        memory[16'hffff] = 8'h80;

        repeat (6) @(posedge clk);
        reset = 1'b0;
        while (cpu_pc != 16'h8000)
            @(posedge clk);

        // NMI before DMA is serviced normally.
        pulse_nmi();
        wait_nmi_count(8'd1);

        // An NMI early in DMA becomes pending but cannot advance the stalled
        // CPU until all 256 read/write pairs finish.
        start_dma(8'h02);
        while (dma_elapsed < 10'd100)
            @(posedge clk);
        pulse_nmi();
        assert (memory[16'h0010] == 8'd1);
        while (dma_active)
            @(posedge clk);
        wait_nmi_count(8'd2);

        // Repeat at the completion boundary.
        start_dma(8'h03);
        while (dma_elapsed < 10'd510)
            @(posedge clk);
        pulse_nmi();
        while (dma_active)
            @(posedge clk);
        wait_nmi_count(8'd3);

        // And immediately after bus ownership returns to the CPU.
        start_dma(8'h04);
        while (dma_active)
            @(posedge clk);
        pulse_nmi();
        wait_nmi_count(8'd4);

        assert (nmi_pulses == 4 && completed_dmas == 3);
        assert (!dma_active && cpu_enable);
        $display("PASS: Phase 4D-A NMI before/during/near/after DMA pulses=%0d handlers=%0d completions=%0d",
                 nmi_pulses, memory[16'h0010], completed_dmas);
        $finish;
    end
endmodule
