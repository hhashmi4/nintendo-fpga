`timescale 1ns/1ps

module nes_oam_dma_phase4d_tb;
    import nes_system_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_cycle_slot = 1'b0;
    logic cpu_cycle_odd = 1'b0;
    logic hold = 1'b0;
    logic trigger = 1'b0;
    logic [7:0] trigger_page = 8'h00;
    logic [7:0] source_read_data;
    logic [15:0] source_address;
    logic source_read_request;
    logic source_read_event;
    logic [7:0] oam_write_data;
    logic oam_write_strobe;
    logic active;
    logic cpu_stall;
    logic [2:0] phase;
    logic [7:0] source_page;
    logic [7:0] byte_index;
    logic started_odd;
    logic start_event;
    logic complete_event;
    logic dummy_cycle;
    logic alignment_cycle;
    logic [9:0] elapsed_cpu_cycles;
    logic [8:0] read_count;
    logic [8:0] write_count;

    logic [7:0] expected_bytes [0:255];
    integer observed_reads = 0;
    integer observed_writes = 0;
    integer observed_slots = 0;
    integer transfers = 0;

    always #5 clk <= !clk;

    function automatic logic [7:0] source_pattern(input logic [15:0] address);
        source_pattern = address[7:0] ^ address[15:8] ^ 8'ha5;
    endfunction

    assign source_read_data = source_pattern(source_address);

    nes_oam_dma dut (
        .clk(clk),
        .reset(reset),
        .cpu_cycle_slot(cpu_cycle_slot),
        .cpu_cycle_odd(cpu_cycle_odd),
        .hold(hold),
        .trigger(trigger),
        .trigger_page(trigger_page),
        .source_read_data(source_read_data),
        .source_address(source_address),
        .source_read_request(source_read_request),
        .source_read_event(source_read_event),
        .oam_write_data(oam_write_data),
        .oam_write_strobe(oam_write_strobe),
        .active(active),
        .cpu_stall(cpu_stall),
        .phase(phase),
        .source_page(source_page),
        .byte_index(byte_index),
        .started_odd(started_odd),
        .start_event(start_event),
        .complete_event(complete_event),
        .dummy_cycle(dummy_cycle),
        .alignment_cycle(alignment_cycle),
        .elapsed_cpu_cycles(elapsed_cpu_cycles),
        .read_count(read_count),
        .write_count(write_count)
    );

    always @(posedge clk) begin
        if (!reset) begin
            assert (!(source_read_event && oam_write_strobe));
            assert (source_read_request ==
                    (active && phase == NES_DMA_READ));
            assert (alignment_cycle ==
                    (active && phase == NES_DMA_ALIGN));
            if (active)
                assert (cpu_stall);
            if (active && cpu_cycle_slot)
                observed_slots <= observed_slots + 1;
            if (source_read_event) begin
                assert (observed_reads < 256);
                assert (source_address == {source_page,
                                           observed_reads[7:0]})
                    else $fatal(1, "source sequence %04x at %0d",
                                source_address, observed_reads);
                expected_bytes[observed_reads] <= source_read_data;
                observed_reads <= observed_reads + 1;
            end
            if (oam_write_strobe) begin
                assert (observed_writes < observed_reads);
                assert (oam_write_data == expected_bytes[observed_writes])
                    else $fatal(1, "write order %0d got=%02x expected=%02x",
                                observed_writes, oam_write_data,
                                expected_bytes[observed_writes]);
                observed_writes <= observed_writes + 1;
            end
        end
    end

    task automatic cpu_slot;
        logic [2:0] held_phase;
        logic [7:0] held_index;
        begin
            // State must hold on ordinary fabric clocks between CPU slots.
            @(negedge clk);
            held_phase = phase;
            held_index = byte_index;
            cpu_cycle_slot = 1'b0;
            @(posedge clk);
            #1;
            assert (phase == held_phase && byte_index == held_index);

            @(negedge clk);
            cpu_cycle_slot = 1'b1;
            @(posedge clk);
            #1;
            cpu_cycle_slot = 1'b0;
        end
    endtask

    task automatic run_transfer(
        input logic [7:0] page,
        input logic odd,
        input integer expected_cycles
    );
        begin
            observed_reads = 0;
            observed_writes = 0;
            observed_slots = 0;

            @(negedge clk);
            trigger_page = page;
            cpu_cycle_odd = odd;
            cpu_cycle_slot = 1'b1;
            trigger = 1'b1;
            #1;
            assert (start_event);
            @(posedge clk);
            #1;
            trigger = 1'b0;
            cpu_cycle_slot = 1'b0;
            assert (active && cpu_stall && dummy_cycle);
            assert (source_page == page && byte_index == 8'h00);
            assert (started_odd == odd);

            while (!complete_event)
                cpu_slot();

            assert (!active && !cpu_stall && phase == NES_DMA_IDLE);
            assert (observed_slots == expected_cycles);
            assert (elapsed_cpu_cycles == 10'(expected_cycles));
            assert (observed_reads == 256 && observed_writes == 256);
            assert (read_count == 9'd256 && write_count == 9'd256);
            assert (source_address == {page, 8'hff});
            assert (expected_bytes[0] == source_pattern({page, 8'h00}));
            assert (expected_bytes[255] == source_pattern({page, 8'hff}));
            transfers = transfers + 1;

            @(posedge clk);
            #1;
            assert (!complete_event);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_oam_dma_phase4d.fst");
        $dumpvars(0, nes_oam_dma_phase4d_tb);

        repeat (3) @(posedge clk);
        #1;
        assert (!active && !cpu_stall && phase == NES_DMA_IDLE);
        assert (source_address == 16'h0000);
        assert (!(start_event || source_read_event || oam_write_strobe ||
                  complete_event));
        reset = 1'b0;

        run_transfer(8'h00, 1'b0, 513);
        run_transfer(8'h02, 1'b1, 514);
        run_transfer(8'h0a, 1'b0, 513);
        run_transfer(8'h20, 1'b1, 514);
        run_transfer(8'h40, 1'b0, 513);
        run_transfer(8'h80, 1'b1, 514);

        // Reset also aborts an in-progress transfer deterministically.
        observed_reads = 0;
        observed_writes = 0;
        observed_slots = 0;
        @(negedge clk);
        trigger_page = 8'h55;
        trigger = 1'b1;
        cpu_cycle_slot = 1'b1;
        @(posedge clk);
        #1;
        trigger = 1'b0;
        cpu_cycle_slot = 1'b0;
        assert (active);
        repeat (5) cpu_slot();
        begin
            logic [2:0] held_phase;
            logic [7:0] held_index;
            logic [9:0] held_elapsed;
            held_phase = phase;
            held_index = byte_index;
            held_elapsed = elapsed_cpu_cycles;
            hold = 1'b1;
            repeat (10) cpu_slot();
            assert (phase == held_phase && byte_index == held_index &&
                    elapsed_cpu_cycles == held_elapsed);
            assert (!source_read_event && !oam_write_strobe);
            hold = 1'b0;
        end
        reset = 1'b1;
        @(posedge clk);
        #1;
        assert (!active && phase == NES_DMA_IDLE &&
                elapsed_cpu_cycles == 10'd0 &&
                read_count == 9'd0 && write_count == 9'd0);

        $display("PASS: Phase 4D-A standalone OAM DMA transfers=%0d reads=%0d writes=%0d cycles=513/514",
                 transfers, transfers * 256, transfers * 256);
        $finish;
    end
endmodule
