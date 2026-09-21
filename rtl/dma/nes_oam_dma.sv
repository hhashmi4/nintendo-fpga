`timescale 1ns/1ps

// Standalone NES OAM DMA bus master. The triggering $4014 CPU write completes
// normally; subsequent scheduled CPU slots are consumed by one dummy slot,
// an optional odd-parity alignment slot, and 256 read/write slot pairs.
module nes_oam_dma (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_cycle_slot,
    input  logic        cpu_cycle_odd,

    input  logic        trigger,
    input  logic [7:0]  trigger_page,

    input  logic [7:0]  source_read_data,
    output logic [15:0] source_address,
    output logic        source_read_request,
    output logic        source_read_event,

    output logic [7:0]  oam_write_data,
    output logic        oam_write_strobe,

    output logic        active,
    output logic        cpu_stall,
    output logic [2:0]  phase,
    output logic [7:0]  source_page,
    output logic [7:0]  byte_index,
    output logic        started_odd,
    output logic        start_event,
    output logic        complete_event,
    output logic        dummy_cycle,
    output logic        alignment_cycle,
    output logic [9:0]  elapsed_cpu_cycles,
    output logic [8:0]  read_count,
    output logic [8:0]  write_count
);
    import nes_system_pkg::*;

    logic [7:0] data_latch;

    assign source_address = {source_page, byte_index};
    // The level request keeps synchronous RAM/ROM addresses established for
    // the complete read phase. The event is the single CPU slot that consumes
    // the resulting byte.
    assign source_read_request = !reset && active && phase == NES_DMA_READ;
    assign source_read_event = source_read_request && cpu_cycle_slot;
    assign oam_write_strobe = !reset && active && cpu_cycle_slot &&
                              phase == NES_DMA_WRITE;
    assign oam_write_data = data_latch;
    assign cpu_stall = !reset && active;
    assign start_event = !reset && trigger;
    assign dummy_cycle = !reset && active && phase == NES_DMA_DUMMY;
    assign alignment_cycle = !reset && active && phase == NES_DMA_ALIGN;

    always_ff @(posedge clk) begin
        if (reset) begin
            active              <= 1'b0;
            phase               <= NES_DMA_IDLE;
            source_page         <= 8'h00;
            byte_index          <= 8'h00;
            data_latch          <= 8'h00;
            started_odd         <= 1'b0;
            elapsed_cpu_cycles  <= 10'd0;
            read_count          <= 9'd0;
            write_count         <= 9'd0;
            complete_event      <= 1'b0;
        end else begin
            complete_event <= 1'b0;

            if (trigger) begin
                active             <= 1'b1;
                phase              <= NES_DMA_DUMMY;
                source_page        <= trigger_page;
                byte_index         <= 8'h00;
                started_odd        <= cpu_cycle_odd;
                elapsed_cpu_cycles <= 10'd0;
                read_count         <= 9'd0;
                write_count        <= 9'd0;
            end else if (active && cpu_cycle_slot) begin
                elapsed_cpu_cycles <= elapsed_cpu_cycles + 10'd1;
                case (phase)
                    NES_DMA_DUMMY:
                        phase <= started_odd ? NES_DMA_ALIGN : NES_DMA_READ;
                    NES_DMA_ALIGN:
                        phase <= NES_DMA_READ;
                    NES_DMA_READ: begin
                        data_latch <= source_read_data;
                        read_count <= read_count + 9'd1;
                        phase <= NES_DMA_WRITE;
                    end
                    NES_DMA_WRITE: begin
                        write_count <= write_count + 9'd1;
                        if (byte_index == 8'hff) begin
                            active <= 1'b0;
                            phase <= NES_DMA_IDLE;
                            complete_event <= 1'b1;
                        end else begin
                            byte_index <= byte_index + 8'd1;
                            phase <= NES_DMA_READ;
                        end
                    end
                    default: begin
                        active <= 1'b0;
                        phase <= NES_DMA_IDLE;
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (phase <= NES_DMA_WRITE);
        assert (!(source_read_event && oam_write_strobe));
        assert (read_count <= 9'd256);
        assert (write_count <= 9'd256);
        if (reset) begin
            assert (!cpu_stall && !start_event && !source_read_request &&
                    !source_read_event && !oam_write_strobe);
        end
        if (complete_event) begin
            assert (read_count == 9'd256);
            assert (write_count == 9'd256);
            assert (elapsed_cpu_cycles ==
                    (started_odd ? 10'd514 : 10'd513));
        end
    end
`endif
endmodule
