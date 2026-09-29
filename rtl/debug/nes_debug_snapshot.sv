`timescale 1ns/1ps

// Phase 4E-A observation-only snapshot path. The source bank changes only at
// an accepted NES frame/manual capture. A toggle/acknowledge handshake holds
// that packed bus stable while the video domain takes a coherent copy. The
// renderer-facing bank is updated only at a video frame boundary.
module nes_debug_snapshot (
    input  logic source_clk,
    input  logic source_reset,
    input  logic source_frame_capture,
    input  logic manual_capture,
    input  nes_debug_snapshot_pkg::nes_debug_snapshot_t observations,

    input  logic nmi_event,
    input  logic nmi_suppressed_event,
    input  logic dma_complete_event,
    input  logic controller_poll_event,
    input  logic controller_read_4016_event,
    input  logic controller_read_4017_event,
    input  logic cpu_slot_event,
    input  logic ppu_cycle_event,
    input  logic prg_read_event,
    input  logic chr_read_event,

    output logic source_capture_accepted,
    output logic source_busy,

    input  logic destination_clk,
    input  logic destination_reset,
    input  logic destination_frame_start,
    output logic destination_update,
    output logic destination_valid,
    output nes_debug_snapshot_pkg::nes_debug_snapshot_t destination_snapshot
);
    import nes_debug_snapshot_pkg::*;

    (* preserve *) nes_debug_snapshot_t source_snapshot;
    (* preserve *) nes_debug_snapshot_t received_snapshot;
    (* preserve, noprune *) nes_debug_snapshot_t destination_snapshot_register;
    (* preserve, noprune *) logic destination_valid_register;
    logic request_toggle;
    logic acknowledge_toggle;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] acknowledge_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync;
    logic request_seen;
    logic received_valid;

    logic [31:0] snapshot_id;
    logic [31:0] source_frame_number;
    logic [31:0] nmi_count;
    logic [31:0] dma_count;
    logic [31:0] controller_poll_count;
    logic [31:0] cpu_slot_count;
    logic [31:0] ppu_cycle_count;
    logic [31:0] prg_read_count;
    logic [31:0] chr_read_count;
    logic [31:0] missed_capture_count;
    logic nmi_event_pending;
    logic nmi_suppressed_pending;
    logic dma_complete_pending;
    logic controller_read_4016_pending;
    logic controller_read_4017_pending;
    logic controller_latch_pending;
    nes_debug_snapshot_t assembled_snapshot;

    assign source_busy = request_toggle != acknowledge_sync[1];
    assign destination_snapshot = destination_snapshot_register;
    assign destination_valid = destination_valid_register;

    always_comb begin
        assembled_snapshot = observations;
        assembled_snapshot.ppu.nmi_event = nmi_event_pending || nmi_event;
        assembled_snapshot.ppu.nmi_suppressed =
            nmi_suppressed_pending || nmi_suppressed_event;
        assembled_snapshot.controller.read_4016 =
            controller_read_4016_pending || controller_read_4016_event;
        assembled_snapshot.controller.read_4017 =
            controller_read_4017_pending || controller_read_4017_event;
        assembled_snapshot.controller.latch_event =
            controller_latch_pending || controller_poll_event;
        assembled_snapshot.dma.complete_event =
            dma_complete_pending || dma_complete_event;
        assembled_snapshot.system.snapshot_id = snapshot_id + 32'd1;
        assembled_snapshot.system.source_frame_number =
            source_frame_number + 32'(source_frame_capture);
        assembled_snapshot.system.nmi_count =
            nmi_count + 32'(nmi_event);
        assembled_snapshot.system.dma_count =
            dma_count + 32'(dma_complete_event);
        assembled_snapshot.system.controller_poll_count =
            controller_poll_count + 32'(controller_poll_event);
        assembled_snapshot.system.cpu_slot_count =
            cpu_slot_count + 32'(cpu_slot_event);
        assembled_snapshot.system.ppu_cycle_count =
            ppu_cycle_count + 32'(ppu_cycle_event);
        assembled_snapshot.system.prg_read_count =
            prg_read_count + 32'(prg_read_event);
        assembled_snapshot.system.chr_read_count =
            chr_read_count + 32'(chr_read_event);
        assembled_snapshot.system.missed_capture_count = missed_capture_count;
    end

    always_ff @(posedge source_clk) begin
        acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
        source_capture_accepted <= 1'b0;

        if (source_reset) begin
            source_snapshot <= '0;
            request_toggle <= 1'b0;
            acknowledge_sync <= 2'b00;
            snapshot_id <= 32'd0;
            source_frame_number <= 32'd0;
            nmi_count <= 32'd0;
            dma_count <= 32'd0;
            controller_poll_count <= 32'd0;
            cpu_slot_count <= 32'd0;
            ppu_cycle_count <= 32'd0;
            prg_read_count <= 32'd0;
            chr_read_count <= 32'd0;
            missed_capture_count <= 32'd0;
            nmi_event_pending <= 1'b0;
            nmi_suppressed_pending <= 1'b0;
            dma_complete_pending <= 1'b0;
            controller_read_4016_pending <= 1'b0;
            controller_read_4017_pending <= 1'b0;
            controller_latch_pending <= 1'b0;
        end else begin
            if (source_frame_capture)
                source_frame_number <= source_frame_number + 32'd1;
            if (nmi_event) begin
                nmi_count <= nmi_count + 32'd1;
                nmi_event_pending <= 1'b1;
            end
            if (nmi_suppressed_event)
                nmi_suppressed_pending <= 1'b1;
            if (dma_complete_event) begin
                dma_count <= dma_count + 32'd1;
                dma_complete_pending <= 1'b1;
            end
            if (controller_poll_event) begin
                controller_poll_count <= controller_poll_count + 32'd1;
                controller_latch_pending <= 1'b1;
            end
            if (controller_read_4016_event)
                controller_read_4016_pending <= 1'b1;
            if (controller_read_4017_event)
                controller_read_4017_pending <= 1'b1;
            if (cpu_slot_event)
                cpu_slot_count <= cpu_slot_count + 32'd1;
            if (ppu_cycle_event)
                ppu_cycle_count <= ppu_cycle_count + 32'd1;
            if (prg_read_event)
                prg_read_count <= prg_read_count + 32'd1;
            if (chr_read_event)
                chr_read_count <= chr_read_count + 32'd1;

            if (source_frame_capture || manual_capture) begin
                if (!source_busy) begin
                    source_snapshot <= assembled_snapshot;
                    request_toggle <= !request_toggle;
                    snapshot_id <= snapshot_id + 32'd1;
                    source_capture_accepted <= 1'b1;
                    nmi_event_pending <= 1'b0;
                    nmi_suppressed_pending <= 1'b0;
                    dma_complete_pending <= 1'b0;
                    controller_read_4016_pending <= 1'b0;
                    controller_read_4017_pending <= 1'b0;
                    controller_latch_pending <= 1'b0;
                end else begin
                    missed_capture_count <= missed_capture_count + 32'd1;
                end
            end
        end
    end

    always_ff @(posedge destination_clk) begin
        request_sync <= {request_sync[1:0], request_toggle};
        destination_update <= 1'b0;

        if (destination_reset) begin
            request_sync <= 3'b000;
            request_seen <= 1'b0;
            acknowledge_toggle <= 1'b0;
            received_snapshot <= '0;
            received_valid <= 1'b0;
            destination_snapshot_register <= '0;
            destination_valid_register <= 1'b0;
        end else begin
            // Commit only the already-received bank. If a new request arrives
            // on this same edge it becomes pending for the following frame.
            if (destination_frame_start && received_valid) begin
                destination_snapshot_register <= received_snapshot;
                destination_valid_register <= 1'b1;
                destination_update <= 1'b1;
                received_valid <= 1'b0;
            end

            if (request_sync[2] != request_seen) begin
                received_snapshot <= source_snapshot;
                received_valid <= 1'b1;
                request_seen <= request_sync[2];
                acknowledge_toggle <= request_sync[2];
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (NES_CPU_DEBUG_SNAPSHOT_BITS == 102);
        assert (NES_PPU_DEBUG_SNAPSHOT_BITS == 92);
        assert (NES_CARTRIDGE_DEBUG_SNAPSHOT_BITS == 61);
        assert (NES_CONTROLLER_DEBUG_SNAPSHOT_BITS == 46);
        assert (NES_DMA_DEBUG_SNAPSHOT_BITS == 90);
        assert (NES_SYSTEM_DEBUG_SNAPSHOT_BITS == 320);
        assert (NES_DEBUG_SNAPSHOT_BITS == 818);
    end

    nes_debug_snapshot_t previous_source_snapshot;
    nes_debug_snapshot_t previous_destination_snapshot;

    always_ff @(posedge source_clk) begin
        if (source_reset) begin
            previous_source_snapshot <= '0;
        end else begin
            if (!source_capture_accepted)
                assert (source_snapshot == previous_source_snapshot);
            previous_source_snapshot <= source_snapshot;
        end
    end

    always_ff @(posedge destination_clk) begin
        if (destination_reset)
            previous_destination_snapshot <= '0;
        else begin
            if (!destination_update)
                assert (destination_snapshot_register ==
                        previous_destination_snapshot);
            if (destination_update)
                assert (destination_valid_register);
            previous_destination_snapshot <= destination_snapshot_register;
        end
    end
`endif
endmodule
