`timescale 1ns/1ps

// DMC DMA timing front-end. A held channel request is converted into one
// acknowledged CPU-address-space read after a halt, dummy, and parity-based
// optional alignment slot. CPU writes are allowed to finish before HALT.
module nes_dmc_dma (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_cycle_slot,
    input  logic        cpu_cycle_odd,
    input  logic        halt_allowed,

    input  logic        request,
    input  logic [15:0] request_address,
    output logic        acknowledge,
    output logic        read_request,
    output logic        read_event,
    output logic [15:0] read_address,

    output logic        active,
    output logic        cpu_stall,
    output logic [2:0]  phase,
    output logic        started_odd,
    output logic [2:0]  elapsed_cpu_cycles,
    output logic        start_event,
    output logic        complete_event
);
    import nes_system_pkg::*;

    assign cpu_stall = !reset &&
                       (active || (request && halt_allowed));
    assign read_request = !reset && active;
    assign read_event = read_request && phase == NES_DMA_READ &&
                        cpu_cycle_slot;
    assign acknowledge = read_event;
    assign start_event = !reset && !active && request && halt_allowed &&
                         cpu_cycle_slot;

    always_ff @(posedge clk) begin
        if (reset) begin
            active <= 1'b0;
            phase <= NES_DMA_IDLE;
            read_address <= 16'h0000;
            started_odd <= 1'b0;
            elapsed_cpu_cycles <= 3'd0;
            complete_event <= 1'b0;
        end else begin
            complete_event <= 1'b0;
            if (!active && request && halt_allowed && cpu_cycle_slot) begin
                active <= 1'b1;
                phase <= NES_DMA_DUMMY;
                read_address <= request_address;
                started_odd <= cpu_cycle_odd;
                elapsed_cpu_cycles <= 3'd1;
            end else if (active && cpu_cycle_slot) begin
                elapsed_cpu_cycles <= elapsed_cpu_cycles + 3'd1;
                case (phase)
                    NES_DMA_DUMMY:
                        phase <= started_odd ? NES_DMA_ALIGN : NES_DMA_READ;
                    NES_DMA_ALIGN: phase <= NES_DMA_READ;
                    NES_DMA_READ: begin
                        active <= 1'b0;
                        phase <= NES_DMA_IDLE;
                        complete_event <= 1'b1;
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
        assert (phase == NES_DMA_IDLE || phase == NES_DMA_DUMMY ||
                phase == NES_DMA_ALIGN || phase == NES_DMA_READ);
        assert (elapsed_cpu_cycles <= 3'd4);
        if (!reset && active)
            assert (cpu_stall);
        if (acknowledge)
            assert (request && active && phase == NES_DMA_READ);
        if (complete_event)
            assert (elapsed_cpu_cycles == (started_odd ? 3'd4 : 3'd3));
        if (reset)
            assert (!cpu_stall && !acknowledge && !read_request);
    end
`endif
endmodule
